import XCTest
@testable import RoneoCore

final class JobStateTests: XCTestCase {
    private let active = "lpstat -W not-completed -o P"
    private let completed = "lpstat -W completed -o P"
    private let status = "lpstat -p P"

    func testPrinting() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [active: "P-42  me  1024  Tue 17 Nov\n"]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .printing)
    }

    func testDone() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [
            active: "P-4  me  1024  Tue\n", completed: "P-41  me  1\nP-42  me  1\n",
        ]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .done)
    }

    func testFailedUsesPrinterStateLine() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [
            active: "", completed: "P-4  me  1\n",
            status: "printer P disabled since Tue - Paper jam\n",
        ]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"),
                       .failed("printer P disabled since Tue - Paper jam"))
    }

    func testFailedWithEmptyStatusLine() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [active: "", completed: "", status: ""]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .failed("The job didn't complete"))
    }
}
