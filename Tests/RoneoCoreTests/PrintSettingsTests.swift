import XCTest
@testable import RoneoCore

final class PrintSettingsTests: XCTestCase {
    func testDefaultsFromBrother() {
        let s = PrintSettings.defaults(printer: "B", capabilities: brotherCapabilities)
        XCTAssertEqual(s.printer, "B")
        XCTAssertEqual(s.sides, .double)
        XCTAssertEqual(s.scale, .actual)
        XCTAssertEqual(s.pages, .all)
        XCTAssertEqual(s.copies, 1)
        XCTAssertEqual(s.paper, "A4")
        XCTAssertEqual(s.mediaType, "any")
        XCTAssertEqual(s.tray, "auto")
        XCTAssertEqual(s.colour, "RGB")
    }

    func testSwitchingPrinterResetsMediaKeepsSides() {
        var s = PrintSettings.defaults(printer: "B", capabilities: brotherCapabilities)
        s.paper = "Letter"; s.colour = "Gray"; s.copies = 3; s.sides = .single
        s.scale = .fit; s.pages = .range("1-2")
        let t = s.switching(to: "C", capabilities: brotherCapabilities)
        XCTAssertEqual(t.printer, "C")
        XCTAssertEqual(t.paper, "A4")
        XCTAssertEqual(t.colour, "RGB")
        XCTAssertEqual(t.sides, .single)
        XCTAssertEqual(t.copies, 3)
        XCTAssertEqual(t.scale, .fit)
        XCTAssertEqual(t.pages, .range("1-2"))
    }

    func testSwitchingToSimplexPrinterForcesSingle() {
        let s = PrintSettings.defaults(printer: "B", capabilities: brotherCapabilities)
        XCTAssertEqual(s.sides, .double)
        let t = s.switching(to: "S", capabilities: simplexCapabilities)
        XCTAssertEqual(t.sides, .single)
        XCTAssertEqual(t.paper, "Letter")
        XCTAssertEqual(t.tray, "tray1")
    }
}
