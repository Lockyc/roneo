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

    private var scratch: URL { dir.appendingPathComponent("scratch") }

    func testPlainFileSendsTheGivenBytes() throws {
        let bytes = try Data(contentsOf: makePDF("plain.pdf"))
        let url = try PrintableFile.write(bytes, password: nil, scratch: scratch)
        XCTAssertTrue(url.path.hasPrefix(scratch.path))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    /// Encrypted for permissions only: opens without a password, so it prints from its own bytes.
    func testPermissionOnlyEncryptedSendsTheGivenBytes() throws {
        let url = try makePDF("perm.pdf", aux: [kCGPDFContextOwnerPassword: "o"])
        let bytes = try Data(contentsOf: url)
        let doc = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertTrue(doc.isEncrypted)
        XCTAssertFalse(doc.isLocked)
        XCTAssertEqual(try Data(contentsOf: PrintableFile.write(bytes, password: nil, scratch: scratch)), bytes)
    }

    func testPasswordLockedCopyIsUnencrypted() throws {
        let bytes = try Data(contentsOf: makeCropped("enc.pdf", rotation: 90, encrypted: true))
        let doc = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertTrue(doc.isLocked)
        let url = try PrintableFile.write(bytes, password: "u", scratch: scratch)
        XCTAssertTrue(url.path.hasPrefix(scratch.path))
        let copy = try open(url)
        XCTAssertFalse(copy.isEncrypted)
        XCTAssertEqual(copy.pageCount, doc.pageCount)
        XCTAssertEqual(
            copy.page(at: 0)?.bounds(for: .cropBox), CGRect(x: 10, y: 20, width: 500, height: 300))
        XCTAssertEqual(copy.page(at: 0)?.rotation, 90)
    }

    func testPasswordLockedWithoutPasswordThrows() throws {
        let bytes = try Data(contentsOf: makeCropped("enc2.pdf", encrypted: true))
        XCTAssertThrowsError(try PrintableFile.write(bytes, password: nil, scratch: scratch))
        XCTAssertThrowsError(try PrintableFile.write(bytes, password: "wrong", scratch: scratch))
    }

    func testPasswordLockedCopyKeepsAnnotations() throws {
        let doc = try open(makePDF("a.pdf"))
        let page = try XCTUnwrap(doc.page(at: 0))
        let square = PDFAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150),
                                   forType: .square, withProperties: nil)
        square.color = .red
        page.addAnnotation(square)
        let text = PDFAnnotation(bounds: CGRect(x: 100, y: 400, width: 200, height: 40),
                                 forType: .freeText, withProperties: nil)
        text.contents = "Kept"
        page.addAnnotation(text)
        let locked = dir.appendingPathComponent("a-enc.pdf")
        XCTAssertTrue(doc.write(to: locked, withOptions: [.userPasswordOption: "u", .ownerPasswordOption: "o"]))

        let url = try PrintableFile.write(Data(contentsOf: locked), password: "u", scratch: scratch)
        let kept = try XCTUnwrap(open(url).page(at: 0)).annotations
        XCTAssertEqual(Set(kept.compactMap(\.type)), ["Square", "FreeText"])
        XCTAssertEqual(kept.first { $0.type == "FreeText" }?.contents, "Kept")
    }

    func testNoPrintPermission() throws {
        let url = try makePDF("np.pdf", aux: [
            kCGPDFContextOwnerPassword: "o", kCGPDFContextAllowsPrinting: false,
        ])
        XCTAssertFalse(PDFFacts.allowsPrinting(try open(url)))
        XCTAssertTrue(PDFFacts.allowsPrinting(try open(makePDF("ok.pdf"))))
    }
}
