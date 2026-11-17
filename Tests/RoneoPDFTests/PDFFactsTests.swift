import CoreGraphics
import PDFKit
import XCTest
@testable import RoneoPDF

final class PDFFactsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makePDF(
        _ name: String, width: CGFloat = 595, height: CGFloat = 842, aux: [CFString: Any] = [:]
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, aux as CFDictionary))
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    private func makeCropped(_ name: String, rotation: Int = 0, encrypted: Bool = false) throws -> URL {
        let plain = dir.appendingPathComponent("plain-\(name)")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try XCTUnwrap(CGContext(plain as CFURL, mediaBox: &box, nil))
        var crop = CGRect(x: 10, y: 20, width: 500, height: 300)
        ctx.beginPDFPage([kCGPDFContextCropBox: Data(bytes: &crop, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        ctx.endPDFPage()
        ctx.closePDF()
        let doc = try XCTUnwrap(PDFDocument(url: plain))
        try XCTUnwrap(doc.page(at: 0)).rotation = rotation
        let out = dir.appendingPathComponent(name)
        let opts: [PDFDocumentWriteOption: Any] = encrypted
            ? [.userPasswordOption: "u", .ownerPasswordOption: "o"] : [:]
        XCTAssertTrue(doc.write(to: out, withOptions: opts))
        return out
    }

    private func open(_ url: URL) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(url: url))
    }

    func testPortrait() throws {
        let doc = try open(makePDF("p.pdf"))
        XCTAssertFalse(PDFFacts.firstPageIsLandscape(doc))
    }

    func testLandscape() throws {
        let doc = try open(makePDF("l.pdf", width: 842, height: 595))
        XCTAssertTrue(PDFFacts.firstPageIsLandscape(doc))
    }

    func testRotatedPortraitMediaIsLandscape() throws {
        let url = try makePDF("r.pdf")
        let doc = try open(url)
        try XCTUnwrap(doc.page(at: 0)).rotation = 90
        XCTAssertTrue(PDFFacts.firstPageIsLandscape(doc))
        let out = dir.appendingPathComponent("r2.pdf")
        XCTAssertTrue(doc.write(to: out))
        XCTAssertTrue(PDFFacts.firstPageIsLandscape(try open(out)))
    }

    func testCropBoxLandscapeInPortraitMedia() throws {
        let doc = try open(makeCropped("c.pdf"))
        XCTAssertTrue(PDFFacts.firstPageIsLandscape(doc))
    }

    func testPlainFileIsOriginal() throws {
        let url = try makePDF("plain.pdf")
        let doc = try open(url)
        let r = try PrintableFile.url(for: doc, original: url, scratch: dir.appendingPathComponent("s"))
        XCTAssertEqual(r.url, url)
        XCTAssertFalse(r.isTemporary)
    }

    func testEncryptedUnlockedCopyIsUnencrypted() throws {
        let url = try makeCropped("enc.pdf", rotation: 90, encrypted: true)
        let doc = try open(url)
        XCTAssertTrue(doc.isEncrypted)
        XCTAssertTrue(doc.unlock(withPassword: "u"))
        let scratch = dir.appendingPathComponent("scratch")
        let r = try PrintableFile.url(for: doc, original: url, scratch: scratch)
        XCTAssertTrue(r.isTemporary)
        XCTAssertNotEqual(r.url, url)
        XCTAssertTrue(r.url.path.hasPrefix(scratch.path))
        let copy = try open(r.url)
        XCTAssertFalse(copy.isEncrypted)
        XCTAssertEqual(copy.pageCount, doc.pageCount)
        XCTAssertEqual(
            copy.page(at: 0)?.bounds(for: .mediaBox), doc.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(
            copy.page(at: 0)?.bounds(for: .cropBox), CGRect(x: 10, y: 20, width: 500, height: 300))
        XCTAssertEqual(copy.page(at: 0)?.rotation, 90)
    }

    func testNoPrintPermission() throws {
        let url = try makePDF("np.pdf", aux: [
            kCGPDFContextOwnerPassword: "o", kCGPDFContextAllowsPrinting: false,
        ])
        XCTAssertFalse(PDFFacts.allowsPrinting(try open(url)))
        XCTAssertTrue(PDFFacts.allowsPrinting(try open(makePDF("ok.pdf"))))
    }
}
