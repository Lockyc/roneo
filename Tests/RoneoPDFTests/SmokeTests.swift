import XCTest
@testable import RoneoPDF

final class SmokeTests: XCTestCase {
    func testPDFLinks() {
        XCTAssertFalse(RoneoPDF.name.isEmpty)
    }
}
