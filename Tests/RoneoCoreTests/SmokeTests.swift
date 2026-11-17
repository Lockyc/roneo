import XCTest
@testable import RoneoCore

final class SmokeTests: XCTestCase {
    func testCoreLinks() {
        XCTAssertFalse(RoneoCore.name.isEmpty)
    }
}
