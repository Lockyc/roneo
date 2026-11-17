import Foundation

public enum JobState: Equatable, Sendable {
    /// Submitted; the app builds this right after `PrintSubmitter.submit`, never `jobState`.
    case sent(pages: Int)
    /// Submitted as one named page (Pages: Current); 1-based.
    case sentPage(Int)
    case printing
    case done
    case failed(String)
    /// In neither CUPS list (purged, or on another server); `printer` is the printer's state line.
    /// Not a failure: the job may well have printed.
    case notFound(printer: String?)

    /// The bar's status text.
    public var text: String {
        switch self {
        case .sent(let pages): return "Sent · \(pages) page\(pages == 1 ? "" : "s")"
        case .sentPage(let page): return "Sent · page \(page)"
        case .printing: return "Printing"
        case .done: return "Done"
        case .failed(let reasons): return "Didn't print: \(reasons)"
        case .notFound(let printer): return "Couldn't find the job" + (printer.map { " (\($0))" } ?? "")
        }
    }

    /// True once the state can't change, so polling stops.
    public var isFinal: Bool {
        switch self {
        case .done, .failed, .notFound: return true
        case .sent, .sentPage, .printing: return false
        }
    }
}

extension Cups {
    /// `.printing` while the job is queued. A job in the completed list is `.done` unless its
    /// state reasons say it was cancelled, aborted or ended with errors, which is `.failed` with
    /// those reasons. A job in neither list is `.notFound` with the printer's own state line.
    /// Throws `CupsError` when `lpstat` itself fails, so a scheduler hiccup never reads as a
    /// failed job.
    public func jobState(id: String, printer: String) throws -> JobState {
        let active = try query(["-W", "not-completed", "-o", printer])
        if active.split(whereSeparator: \.isNewline).contains(where: { Self.jobID($0) == id }) { return .printing }

        let completed = try query(["-l", "-W", "completed", "-o", printer])
        if let reasons = Self.stateReasons(of: id, in: completed) {
            let bad = reasons.filter { r in ["cancel", "abort", "error"].contains { r.contains($0) } }
            return bad.isEmpty ? .done : .failed(bad.map { $0.replacingOccurrences(of: "-", with: " ") }.joined(separator: ", "))
        }

        let line = try query(["-p", printer]).split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return .notFound(printer: line.isEmpty ? nil : line)
    }

    private func query(_ args: [String]) throws -> String {
        let r = try run("lpstat", args)
        guard r.status == 0 else { throw CupsError(command: "lpstat " + args.joined(separator: " "), stderr: r.stderr) }
        return r.stdout
    }

    private static func jobID(_ line: Substring) -> String? {
        line.first?.isWhitespace == false ? line.split(separator: " ").first.map(String.init) : nil
    }

    /// The `Alerts:` reasons in `id`'s block of `lpstat -l` output; nil when the job is absent.
    private static func stateReasons(of id: String, in output: String) -> [String]? {
        var inBlock = false
        var found = false
        var reasons: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            if line.first?.isWhitespace == false {
                inBlock = jobID(line) == id
                found = found || inBlock
            } else if inBlock {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Alerts:") {
                    reasons = t.dropFirst("Alerts:".count).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
                }
            }
        }
        return found ? reasons : nil
    }
}
