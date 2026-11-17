import XCTest
@testable import RoneoCore

final class JobStateTests: XCTestCase {
    private let active = "lpstat -W not-completed -o P"
    private let completed = "lpstat -l -W completed -o P"
    private let status = "lpstat -p P"

    /// One job block as `lpstat -l` prints it.
    private func block(_ id: String, alerts: String) -> String {
        "\(id) me          240640   Tue 17 Nov 18:01:26 2026\n\tStatus: \n\tAlerts: \(alerts)\n\tqueued for P\n"
    }

    func testPrinting() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [active: "P-42  me  1024  Tue 17 Nov\n"]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .printing)
    }

    func testPrintingMatchesWholeId() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [
            active: "P-4  me  1024  Tue\n", completed: block("P-42", alerts: "job-completed-successfully"),
        ]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .done)
    }

    func testDoneForSuccessAndForRealCompletedReason() throws {
        // A job that printed fine reports processing-to-stop-point on real CUPS.
        for alerts in ["job-completed-successfully", "processing-to-stop-point"] {
            let cups = Cups(runner: RecordingRunner(outputs: [active: "", completed: block("P-42", alerts: alerts)]))
            XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .done, alerts)
        }
    }

    func testCancelledAndAbortedAreFailed() throws {
        let cancelled = Cups(runner: RecordingRunner(outputs: [
            active: "", completed: block("P-41", alerts: "none") + block("P-42", alerts: "job-canceled-by-user"),
        ]))
        XCTAssertEqual(try cancelled.jobState(id: "P-42", printer: "P"), .failed("job canceled by user"))
        let aborted = Cups(runner: RecordingRunner(outputs: [active: "", completed: block("P-42", alerts: "aborted-by-system")]))
        XCTAssertEqual(try aborted.jobState(id: "P-42", printer: "P"), .failed("aborted by system"))
    }

    func testUnlistedJobUsesPrinterStateLine() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [
            active: "", completed: block("P-4", alerts: "none"),
            status: "printer P disabled since Tue - Paper jam\n",
        ]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"),
                       .notFound(printer: "printer P disabled since Tue - Paper jam"))
    }

    func testNotFoundWithEmptyStatusLine() throws {
        let cups = Cups(runner: RecordingRunner(outputs: [active: "", completed: "", status: ""]))
        XCTAssertEqual(try cups.jobState(id: "P-42", printer: "P"), .notFound(printer: nil))
    }

    func testStatusText() {
        XCTAssertEqual(JobState.notFound(printer: "printer P is idle.").text,
                       "Couldn't find the job (printer P is idle.)")
        XCTAssertEqual(JobState.notFound(printer: nil).text, "Couldn't find the job")
        XCTAssertEqual(JobState.failed("aborted by system").text, "Didn't print: aborted by system")
        XCTAssertEqual(JobState.sent(pages: 1).text, "Sent · 1 page")
        XCTAssertEqual(JobState.sent(pages: 3).text, "Sent · 3 pages")
        XCTAssertEqual(JobState.sentPage(4).text, "Sent · page 4")
        XCTAssertEqual(JobState.printing.text, "Printing")
        XCTAssertEqual(JobState.done.text, "Done")
    }

    func testLpstatFailureThrows() {
        let fail = CommandResult(status: 1, stdout: "", stderr: "lpstat: scheduler not responding")
        let ok = CommandResult(status: 0, stdout: "", stderr: "")
        let cases: [[String: CommandResult]] = [
            [active: fail],
            [active: ok, completed: fail],
            [active: ok, completed: ok, status: fail],
        ]
        for results in cases {
            let cups = Cups(runner: RecordingRunner(results: results))
            XCTAssertThrowsError(try cups.jobState(id: "P-42", printer: "P")) {
                XCTAssertEqual(($0 as? CupsError)?.stderr, "lpstat: scheduler not responding")
            }
        }
    }
}
