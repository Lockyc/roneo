import Foundation

public enum JobState: Equatable, Sendable {
    /// Submitted; the app builds this right after `PrintSubmitter.submit`, never `jobState`.
    case sent(pages: Int)
    case printing
    case done
    case failed(String)
}

extension Cups {
    /// `.printing` while the job is queued, `.done` once it is listed as completed, otherwise
    /// `.failed` with the printer's own state line.
    public func jobState(id: String, printer: String) throws -> JobState {
        if try lists(id, ["-W", "not-completed", "-o", printer]) { return .printing }
        if try lists(id, ["-W", "completed", "-o", printer]) { return .done }
        let r = try run("lpstat", ["-p", printer])
        let line = r.stdout.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return .failed(line.isEmpty ? "The job didn't complete" : line)
    }

    private func lists(_ id: String, _ args: [String]) throws -> Bool {
        let r = try run("lpstat", args)
        return r.stdout.split(whereSeparator: \.isNewline).contains { $0.split(separator: " ").first.map(String.init) == id }
    }
}
