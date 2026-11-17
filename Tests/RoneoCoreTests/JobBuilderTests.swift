import XCTest
@testable import RoneoCore

final class JobBuilderTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/doc.pdf")

    private func base(_ edit: (inout PrintSettings) -> Void = { _ in }) -> PrintSettings {
        var s = PrintSettings.defaults(printer: "B", capabilities: brotherCapabilities)
        edit(&s)
        return s
    }

    private func args(_ s: PrintSettings, landscape: Bool = false, file: URL? = nil) -> [String] {
        JobBuilder.lpArguments(settings: s, file: file ?? self.file, currentPage: 4, pageCount: 10, firstPageLandscape: landscape)
    }

    func testSingle100Percent() {
        XCTAssertEqual(args(base { $0.sides = .single }), [
            "-d", "B", "-n", "1",
            "-o", "sides=one-sided", "-o", "print-scaling=none", "-o", "number-up=1",
            "-o", "page-set=all", "-o", "mirror=false", "-o", "fit-to-page=false",
            "-o", "PageSize=A4", "-o", "MediaType=any", "-o", "InputSlot=auto", "-o", "ColorModel=RGB",
            "--", "/tmp/doc.pdf",
        ])
    }

    func testDoublePortraitUsesLongEdge() {
        XCTAssertTrue(args(base()).contains("sides=two-sided-long-edge"))
    }

    func testDoubleLandscapeUsesShortEdge() {
        let a = args(base(), landscape: true)
        XCTAssertTrue(a.contains("sides=two-sided-short-edge"))
        XCTAssertFalse(a.contains("sides=two-sided-long-edge"))
    }

    func testSingleLandscapeStaysOneSided() {
        XCTAssertTrue(args(base { $0.sides = .single }, landscape: true).contains("sides=one-sided"))
    }

    func testFitOmitsFitToPageFalse() {
        let a = args(base { $0.scale = .fit })
        XCTAssertTrue(a.contains("print-scaling=fit"))
        XCTAssertFalse(a.contains("fit-to-page=false"))
    }

    func testCurrentPage() {
        XCTAssertTrue(args(base { $0.pages = .current }).contains("page-ranges=4"))
    }

    func testRangeIsNormalised() {
        XCTAssertTrue(args(base { $0.pages = .range("5, 1-3") }).contains("page-ranges=1-3,5"))
    }

    func testInvalidRangeIsStillPassedThrough() {
        XCTAssertTrue(args(base { $0.pages = .range("99") }).contains("page-ranges=99"))
    }

    func testAllOmitsPageRanges() {
        XCTAssertFalse(args(base()).contains { $0.hasPrefix("page-ranges=") })
    }

    func testNilMediaOptionsAreOmitted() {
        let a = args(base { $0.paper = nil; $0.mediaType = nil; $0.tray = nil; $0.colour = nil })
        XCTAssertFalse(a.contains { $0.hasPrefix("PageSize=") || $0.hasPrefix("MediaType=") || $0.hasPrefix("InputSlot=") || $0.hasPrefix("ColorModel=") })
    }

    func testFileArgumentFollowsDoubleDash() {
        let a = args(base(), file: URL(fileURLWithPath: "/tmp/-a b ü.pdf"))
        XCTAssertEqual(Array(a.suffix(2)), ["--", "/tmp/-a b ü.pdf"])
    }

    func testCopies() {
        let a = args(base { $0.copies = 3 })
        XCTAssertEqual(a[2], "-n")
        XCTAssertEqual(a[3], "3")
    }

    func testSubmitSetsEmptyHomeAndParsesId() throws {
        let home = URL(fileURLWithPath: "/tmp/empty-home")
        let runner = RecordingRunner(outputs: [
            "/usr/bin/lp -d B -- /tmp/x.pdf": "request id is Brother_HL_L3280CDW_series-42 (1 file(s))\n",
        ])
        let id = try PrintSubmitter(runner: runner, emptyHome: home).submit(["-d", "B", "--", "/tmp/x.pdf"])
        XCTAssertEqual(id, "Brother_HL_L3280CDW_series-42")
        let env = try XCTUnwrap(runner.calls.first?.environment)
        XCTAssertEqual(env["HOME"], "/tmp/empty-home")
        XCTAssertEqual(env["PATH"], ProcessInfo.processInfo.environment["PATH"])
    }

    func testSubmitThrowsStderr() {
        let runner = RecordingRunner(results: [
            "/usr/bin/lp -d B": CommandResult(status: 1, stdout: "", stderr: "lp: The printer is not responding."),
        ])
        XCTAssertThrowsError(try PrintSubmitter(runner: runner, emptyHome: URL(fileURLWithPath: "/tmp/h")).submit(["-d", "B"])) {
            XCTAssertEqual(($0 as? CupsError)?.stderr, "lp: The printer is not responding.")
        }
    }

    func testSubmitThrowsOnUnparseableOutput() {
        let runner = RecordingRunner(outputs: ["/usr/bin/lp -d B": "ok\n"])
        XCTAssertThrowsError(try PrintSubmitter(runner: runner, emptyHome: URL(fileURLWithPath: "/tmp/h")).submit(["-d", "B"]))
    }
}
