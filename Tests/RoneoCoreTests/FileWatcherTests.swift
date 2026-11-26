import XCTest
@testable import RoneoCore

final class FileWatcherTests: XCTestCase {
    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("watched.pdf") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Watches `file`, runs `change`, and waits for a report that arrives well inside the
    /// file-coordination daemon's batching delay (over a second).
    private func expectReport(after change: () throws -> Void, line: UInt = #line) rethrows -> FileWatcher {
        let reported = expectation(description: "change reported")
        reported.assertForOverFulfill = false
        let watcher = FileWatcher(url: file) { reported.fulfill() }
        try change()
        wait(for: [reported], timeout: 0.3)
        return watcher
    }

    func testAnInPlaceWriteIsReported() throws {
        let watcher = try expectReport { try Data("two, longer".utf8).write(to: file) }
        watcher.cancel()
    }

    func testAnAtomicReplaceIsReported() throws {
        let watcher = try expectReport { try Data("two".utf8).write(to: file, options: .atomic) }
        watcher.cancel()
    }

    func testADeleteIsReported() throws {
        let watcher = try expectReport { try FileManager.default.removeItem(at: file) }
        watcher.cancel()
    }

    /// After a replace the watcher follows the path, so the new file's own writes are reported.
    func testWritesAfterAReplaceAreReported() throws {
        var count = 0
        let watcher = FileWatcher(url: file) { count += 1 }
        try Data("two".utf8).write(to: file, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let before = count
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" more".utf8))
        try handle.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(count, before)
        watcher.cancel()
    }

    func testAFileCreatedAfterADeleteIsWatched() throws {
        var count = 0
        let watcher = FileWatcher(url: file) { count += 1 }
        try FileManager.default.removeItem(at: file)
        try Data("back".utf8).write(to: file)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let before = count
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" again".utf8))
        try handle.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(count, before)
        watcher.cancel()
    }

    func testNothingIsReportedAfterCancel() throws {
        var count = 0
        let watcher = FileWatcher(url: file) { count += 1 }
        watcher.cancel()
        try Data("two".utf8).write(to: file)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(count, 0)
    }
}
