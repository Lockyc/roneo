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

/// The real runner: resolves `executable` on PATH via `/usr/bin/env`, captures both streams.
/// `environment` replaces the inherited one only when non-nil.
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ args: [String], environment: [String: String]?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Drain both pipes before waiting so a full pipe buffer cannot deadlock the child.
        nonisolated(unsafe) var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}

public struct CupsError: Error, Equatable {
    public let command: String
    public let stderr: String
}

/// Printer discovery over the CUPS command-line tools.
public struct Cups {
    private let runner: CommandRunner

    public init(runner: CommandRunner) {
        self.runner = runner
    }

    /// Runs a CUPS query with the inherited environment.
    func run(_ executable: String, _ args: [String]) throws -> CommandResult {
        try runner.run(executable, args, environment: nil)
    }

    public func printers() throws -> (names: [String], defaultName: String?) {
        let list = try run("lpstat", ["-e"])
        guard list.status == 0 else { throw CupsError(command: "lpstat -e", stderr: list.stderr) }
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

    public func capabilities(for printer: String) throws -> PrinterCapabilities {
        let r = try run("lpoptions", ["-p", printer, "-l"])
        guard r.status == 0 else { throw CupsError(command: "lpoptions -p \(printer) -l", stderr: r.stderr) }
        return PrinterOptionsParser.parse(r.stdout)
    }
}
