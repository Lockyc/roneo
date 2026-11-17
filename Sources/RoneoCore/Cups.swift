import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs an external command; a seam so CUPS logic is testable without a real printer system.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ args: [String], environment: [String: String]?) throws -> CommandResult
}

/// A command that didn't exit within the runner's timeout; it was terminated.
public struct CommandTimedOut: Error, Equatable {
    /// The command's name, without its path.
    public let command: String
    public let seconds: TimeInterval
}

/// The real runner: resolves `executable` on PATH via `/usr/bin/env`, captures both streams.
/// `environment` replaces the inherited one only when non-nil. A command still running after
/// `timeout` seconds is terminated and `CommandTimedOut` thrown, so a hung scheduler can't hold a
/// window's bar on "Loading printers…" or "Sending…" for ever.
public struct ProcessRunner: CommandRunner {
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public func run(_ executable: String, _ args: [String], environment: [String: String]?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        // Drain both pipes while waiting so a full pipe buffer cannot deadlock the child.
        nonisolated(unsafe) var outData = Data(), errData = Data()
        let drained = DispatchGroup()
        for (pipe, keep) in [(out, { (d: Data) in outData = d }), (err, { (d: Data) in errData = d })] {
            drained.enter()
            DispatchQueue.global().async {
                keep(pipe.fileHandleForReading.readDataToEndOfFile())
                drained.leave()
            }
        }
        let deadline = DispatchTime.now() + timeout
        guard exited.wait(timeout: deadline) == .success, drained.wait(timeout: deadline) == .success else {
            process.terminate()
            throw CommandTimedOut(command: URL(fileURLWithPath: executable).lastPathComponent, seconds: timeout)
        }
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}

public struct CupsError: Error, Equatable {
    public let command: String
    public let stderr: String
}

/// The inherited environment with `HOME` at `emptyHome`, so no `~/.cups/lpoptions` applies.
func environment(emptyHome: URL) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["HOME"] = emptyHome.path
    return env
}

/// Printer discovery over the CUPS command-line tools.
public struct Cups: Sendable {
    private let runner: CommandRunner
    private let emptyHome: URL

    /// `emptyHome` is the empty directory `lpoptions` runs with as `HOME`, as `lp` does.
    public init(runner: CommandRunner, emptyHome: URL) {
        self.runner = runner
        self.emptyHome = emptyHome
    }

    /// Runs a CUPS query with the inherited environment.
    func run(_ executable: String, _ args: [String]) throws -> CommandResult {
        try runner.run(executable, args, environment: nil)
    }

    /// The queues and the system default. No destinations is an empty list, whichever way `lpstat`
    /// reports it (macOS: no output, exit 0; upstream CUPS: "No destinations added.", exit 1).
    public func printers() throws -> (names: [String], defaultName: String?) {
        let list = try run("lpstat", ["-e"])
        if list.status != 0 {
            guard list.stderr.contains("No destinations added") else {
                throw CupsError(command: "lpstat -e", stderr: list.stderr)
            }
            return ([], nil)
        }
        let names = list.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // `lpstat -d` exits 0 with "no system default destination" when none is set.
        let def = try run("lpstat", ["-d"])
        let prefix = "system default destination:"
        var defaultName: String?
        if let line = def.stdout.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) }) {
            let name = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            defaultName = name.isEmpty ? nil : name
        }
        return (names, defaultName)
    }

    /// The printer's description, the name the system shows for it (the `Description:` line of
    /// `lpstat -l -p`); `printer` itself when that is empty or `lpstat` fails, since the name is
    /// only for display.
    public func description(of printer: String) -> String {
        guard let r = try? run("lpstat", ["-l", "-p", printer]), r.status == 0 else { return printer }
        let prefix = "Description:"
        let text = r.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(prefix) }
            .map { $0.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) } ?? ""
        return text.isEmpty ? printer : text
    }

    /// The printer's options and its own defaults; user-saved defaults never apply.
    public func capabilities(for printer: String) throws -> PrinterCapabilities {
        let r = try runner.run("lpoptions", ["-p", printer, "-l"], environment: environment(emptyHome: emptyHome))
        guard r.status == 0 else { throw CupsError(command: "lpoptions -p \(printer) -l", stderr: r.stderr) }
        return PrinterOptionsParser.parse(r.stdout)
    }
}
