import XCTest
@testable import RoneoCore

final class PageRangeTests: XCTestCase {
    func testNormalize() {
        let table: [(String, String?)] = [
            ("1-3, 5", "1-3,5"), ("2", "2"), (" 4 - 6 ", "4-6"),
            ("", nil), ("0", nil), ("5-2", nil), ("21", nil), ("abc", nil),
            ("1-", nil), (",", nil), ("1,,2", nil), ("-3", nil), ("1-21", nil),
            ("1 2", nil), ("1 0-15", nil), ("1-1 5", nil),
        ]
        for (input, expected) in table {
            XCTAssertEqual(PageRange.normalize(input, pageCount: 20), expected, input)
        }
    }

    /// CUPS rejects descending or overlapping `page-ranges`, so the output is ascending and merged.
    func testNormalizeSortsAndMerges() {
        let table: [(String, String)] = [
            ("5,1-3", "1-3,5"), ("3,3", "3"), ("1-4,3-6", "1-6"), ("2-2", "2"),
            ("1-3,4", "1-4"), ("7,2,5-6", "2,5-7"), ("10-12, 1, 11", "1,10-12"),
        ]
        for (input, expected) in table {
            XCTAssertEqual(PageRange.normalize(input, pageCount: 20), expected, input)
        }
    }
}
