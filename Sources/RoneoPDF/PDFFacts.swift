import Foundation
import PDFKit

/// Facts about a loaded PDF that the print bar needs.
public enum PDFFacts {
    /// True when page 1, as displayed, is wider than tall: the crop box (which CUPS sizes the page
    /// from) with `/Rotate` applied.
    public static func firstPageIsLandscape(_ doc: PDFDocument) -> Bool {
        guard let page = doc.page(at: 0) else { return false }
        let box = page.bounds(for: .cropBox)
        let quarterTurn = page.rotation % 180 != 0
        let width = quarterTurn ? box.height : box.width
        let height = quarterTurn ? box.width : box.height
        return width > height
    }

    /// False when the document's permissions forbid printing.
    public static func allowsPrinting(_ doc: PDFDocument) -> Bool {
        doc.allowsPrinting
    }
}

/// Chooses the file CUPS receives for a document.
public enum PrintableFile {
    /// The original file, or for an encrypted document a temporary unencrypted copy in `scratch`
    /// (created when missing); the caller removes a temporary copy after the job. The copy is built
    /// from copies of the pages in a fresh document: writing the unlocked document itself keeps its
    /// encryption.
    public static func url(
        for doc: PDFDocument, original: URL, scratch: URL
    ) throws -> (url: URL, isTemporary: Bool) {
        guard doc.isEncrypted else { return (original, false) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let copy = scratch.appendingPathComponent("\(UUID().uuidString).pdf")
        let plain = PDFDocument()
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index)?.copy() as? PDFPage else {
                throw CocoaError(.fileWriteUnknown)
            }
            plain.insert(page, at: index)
        }
        guard plain.write(to: copy) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: copy.path])
        }
        return (copy, true)
    }
}
