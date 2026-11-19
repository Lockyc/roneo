import Foundation

public enum JobBuilder {
    /// The `MediaType` choice macOS adds to a driverless printer's PPD as its default. CUPS sends it
    /// as `media-type=auto`, which such a printer may not support; a Brother HL-L3280CDW given it
    /// ignores the job's `sides` too and prints one-sided. A job on this choice names no type, so
    /// the printer uses its own default.
    public static let anyMediaType = "any"

    /// Arguments for `/usr/bin/lp`. Assumes `Preflight` passed; an unnormalisable range is passed
    /// through raw so CUPS rejects the job rather than printing every page. `title` names the job in
    /// the queue, since `file` is a scratch copy.
    public static func lpArguments(settings: PrintSettings, file: URL, title: String, currentPage: Int,
                                   pageCount: Int, firstPageLandscape: Bool) -> [String] {
        let sides: String
        switch settings.sides {
        case .single: sides = "one-sided"
        case .double: sides = firstPageLandscape ? "two-sided-short-edge" : "two-sided-long-edge"
        }
        var a = ["-d", settings.printer, "-n", "\(settings.copies)",
                 "-o", "sides=\(sides)",
                 "-o", "print-scaling=\(settings.scale == .actual ? "none" : "fit")",
                 "-o", "number-up=1", "-o", "page-set=all", "-o", "mirror=false"]
        if settings.scale == .actual { a += ["-o", "fit-to-page=false"] }
        switch settings.pages {
        case .all: break
        case .current: a += ["-o", "page-ranges=\(currentPage)"]
        case .range(let text):
            a += ["-o", "page-ranges=\(PageRange.normalize(text, pageCount: pageCount) ?? text)"]
        }
        let mediaType = settings.mediaType == anyMediaType ? nil : settings.mediaType
        for (key, value) in [("PageSize", settings.paper), ("MediaType", mediaType),
                             ("InputSlot", settings.tray), ("ColorModel", settings.colour)] {
            if let value { a += ["-o", "\(key)=\(value)"] }
        }
        return a + ["-t", title, "--", file.path]
    }
}

/// Sends a job to CUPS with a `HOME` that holds no `~/.cups/lpoptions`, so a user's saved
/// per-printer overrides cannot alter the job.
public struct PrintSubmitter {
    private let runner: CommandRunner
    private let emptyHome: URL

    /// How long `lp` gets: handing a large PDF to cupsd can outlast a query's timeout.
    public static let timeout: TimeInterval = 120

    public init(runner: CommandRunner, emptyHome: URL) {
        self.runner = runner
        self.emptyHome = emptyHome
    }

    /// Runs the real `lp` with `timeout`.
    public init(emptyHome: URL) {
        self.init(runner: ProcessRunner(timeout: Self.timeout), emptyHome: emptyHome)
    }

    /// Returns the CUPS job id from `request id is <id> (1 file(s))`.
    public func submit(_ args: [String]) throws -> String {
        let r = try runner.run("/usr/bin/lp", args, environment: environment(emptyHome: emptyHome))
        guard r.status == 0 else { throw CupsError(command: "lp", stderr: r.stderr) }
        let prefix = "request id is "
        guard let line = r.stdout.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) }),
              let id = line.dropFirst(prefix.count).split(separator: " ").first else {
            throw CupsError(command: "lp", stderr: "lp gave no request id: \(r.stdout)")
        }
        return String(id)
    }
}
