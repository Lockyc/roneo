import XCTest
@testable import RoneoCore

final class PageRangeTests: XCTestCase {
    func testNormalize() {
        let table: [(String, String?)] = [
            ("1-3, 5", "1-3,5"), ("2", "2"), (" 4 - 6 ", "4-6"), ("3,3", "3,3"),
            ("", nil), ("0", nil), ("5-2", nil), ("12", nil), ("abc", nil),
            ("1-", nil), (",", nil), ("1,,2", nil), ("-3", nil), ("1-11", nil),
        ]
        for (input, expected) in table {
            XCTAssertEqual(PageRange.normalize(input, pageCount: 10), expected, input)
        }
    }
}
