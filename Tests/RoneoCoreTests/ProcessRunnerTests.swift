import XCTest
@testable import RoneoCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndStatus() throws {
        let r = try ProcessRunner().run("sh", ["-c", "echo out; echo err >&2; exit 3"], environment: nil)
        XCTAssertEqual(r.status, 3)
        XCTAssertEqual(r.stdout, "out\n")
        XCTAssertEqual(r.stderr, "err\n")
    }

    func testTimeoutTerminatesAndThrows() {
        let start = Date()
        XCTAssertThrowsError(try ProcessRunner(timeout: 0.5).run("sleep", ["30"], environment: nil)) {
            XCTAssertEqual($0 as? CommandTimedOut, CommandTimedOut(command: "sleep", seconds: 0.5))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testDefaultTimeoutIsFifteenSeconds() {
        XCTAssertEqual(ProcessRunner().timeout, 15)
    }
}
