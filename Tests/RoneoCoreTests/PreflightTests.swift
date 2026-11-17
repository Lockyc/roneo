import XCTest
@testable import RoneoCore

final class PreflightTests: XCTestCase {
    private let settings = PrintSettings.defaults(printer: "B", capabilities: brotherCapabilities)

    private func reason(_ s: PrintSettings? = nil, printers: [String] = ["B"], file: Bool = true, allows: Bool = true) -> String? {
        Preflight.blockReason(settings: s ?? settings, printers: printers, pageCount: 10,
                              fileExists: file, allowsPrinting: allows)
    }

    func testNoPrintersDisablesPrint() {
        XCTAssertEqual(reason(printers: []), "No printers set up")
    }

    func testMissingFileBlocksPrint() {
        XCTAssertEqual(reason(file: false), "The file is no longer where it was opened from")
    }

    func testNoPrintPermissionBlocks() {
        XCTAssertEqual(reason(allows: false), "This PDF doesn't allow printing")
    }

    func testBadRangeBlocks() {
        var s = settings
        s.pages = .range("5-2")
        XCTAssertEqual(reason(s), "Pages: enter a range like 1-3, 5")
    }

    func testBadCopiesBlocks() {
        var s = settings
        s.copies = 0
        XCTAssertEqual(reason(s), "Copies must be 1 or more")
    }

    func testOrderPrintersFirst() {
        XCTAssertEqual(reason(printers: [], file: false, allows: false), "No printers set up")
        XCTAssertEqual(reason(file: false, allows: false), "This PDF doesn't allow printing")
    }

    func testValidSettingsPass() {
        XCTAssertNil(reason())
        var s = settings
        s.pages = .range("1-3, 5")
        XCTAssertNil(reason(s))
    }
}
