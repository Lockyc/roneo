import Foundation
@testable import RoneoCore

/// Answers commands from a table keyed by the joined command line and records every call.
final class RecordingRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
        let environment: [String: String]?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let results: [String: CommandResult]

    init(results: [String: CommandResult]) {
        self.results = results
    }

    convenience init(outputs: [String: String]) {
        self.init(results: outputs.mapValues { CommandResult(status: 0, stdout: $0, stderr: "") })
    }

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func run(_ executable: String, _ args: [String], environment: [String: String]?) throws -> CommandResult {
        lock.lock()
        recorded.append(Call(executable: executable, args: args, environment: environment))
        lock.unlock()
        let key = ([executable] + args).joined(separator: " ")
        return results[key] ?? CommandResult(status: 1, stdout: "", stderr: "unexpected: \(key)")
    }
}

let brotherCapabilities = PrinterOptionsParser.parse("""
Collate/Collate: True *False
ColorModel/Color Mode: Gray *RGB
Duplex/2-Sided Printing: None *DuplexNoTumble DuplexTumble
PageSize/Media Size: 3x5 *A4 A5 Letter Custom.WIDTHxHEIGHT
MediaType/MediaType: stationery *any
InputSlot/Media Source: auto manual main
""")

let simplexCapabilities = PrinterOptionsParser.parse("""
ColorModel/Color Mode: *Gray RGB
PageSize/Media Size: A4 *Letter
MediaType/MediaType: *plain
InputSlot/Media Source: *tray1 tray2
""")

let testEmptyHome = URL(fileURLWithPath: "/private/var/empty-home")

extension Cups {
    /// Queries that never read `HOME` don't care which empty home they get.
    init(runner: CommandRunner) { self.init(runner: runner, emptyHome: testEmptyHome) }
}
