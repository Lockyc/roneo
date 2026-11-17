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

/// Writes the file CUPS receives for a document.
public enum PrintableFile {
    /// Writes `data`, the exact bytes the window parsed, to a new file in `scratch` (created when
    /// missing) and returns it; the caller removes it after the job. A document that needs a
    /// password to open is written instead as an unencrypted copy unlocked with `password`, built
    /// from copies of its pages in a fresh document (writing the unlocked document itself keeps its
    /// encryption). Throws when `data` isn't a PDF or `password` doesn't unlock it.
    public static func write(_ data: Data, password: String?, scratch: URL) throws -> URL {
        guard let doc = PDFDocument(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let url = scratch.appendingPathComponent("\(UUID().uuidString).pdf")
        guard doc.isLocked else {
            try data.write(to: url)
            return url
        }
        guard let password, doc.unlock(withPassword: password) else { throw CocoaError(.fileReadNoPermission) }
        let plain = PDFDocument()
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index)?.copy() as? PDFPage else {
                throw CocoaError(.fileWriteUnknown)
            }
            plain.insert(page, at: index)
        }
        guard plain.write(to: url) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }
}
