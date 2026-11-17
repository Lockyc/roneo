import XCTest
@testable import RoneoCore

final class FileStampTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try Data("%PDF-1.4 one".utf8).write(to: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testReadingTheFileIsNotAChange() throws {
        let before = FileStamp(of: url)
        Thread.sleep(forTimeInterval: 0.05)
        _ = try Data(contentsOf: url)
        var accessed = URLResourceValues()
        accessed.contentAccessDate = Date()
        try url.setResourceValues(accessed)
        XCTAssertNotNil(before)
        XCTAssertEqual(FileStamp(of: url), before)
    }

    func testWritingTheFileIsAChange() throws {
        let before = FileStamp(of: url)
        Thread.sleep(forTimeInterval: 0.05)
        try Data("%PDF-1.4 two".utf8).write(to: url)
        XCTAssertNotEqual(FileStamp(of: url), before)
    }

    func testReplacingTheFileIsAChange() throws {
        let before = FileStamp(of: url)
        let other = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("%PDF-1.4 one".utf8).write(to: other)
        let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]!
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: other.path)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: other)
        XCTAssertNotEqual(FileStamp(of: url), before)
    }

    func testAMissingFileHasNoStamp() throws {
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(FileStamp(of: url))
    }
}
