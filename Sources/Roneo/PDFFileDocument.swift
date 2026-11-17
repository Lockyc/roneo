import AppKit
import PDFKit

/// A PDF open for viewing. Read-only: never edited, saved or autosaved. The whole file is read into
/// memory, so the window keeps showing it if the file is replaced mid-write or deleted.
@objc(PDFFileDocument) final class PDFFileDocument: NSDocument, PDFDocumentDelegate {
    private(set) var pdf: PDFDocument?
    /// The password that unlocked this file, reused when a change on disk reloads it.
    private var password: String?
    /// Page and zoom from window restoration, applied once the document is viewable (after unlock).
    private var restoredView: (page: Int, scale: CGFloat)?
    private var reloadPending = false

    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override class var writableTypes: [String] { [] }
    override class func isNativeType(_ type: String) -> Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }
    override var isEntireFileLoaded: Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let pdf = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if FirstDrawTimer.isEnabled { pdf.delegate = self }
        if pdf.isLocked, let password { pdf.unlock(withPassword: password) }
        self.pdf = pdf
    }

    func classForPage() -> AnyClass { TimedPage.self }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    private var controller: DocumentWindowController? {
        windowControllers.first as? DocumentWindowController
    }

    override func showWindows() {
        super.showWindows()
        guard let pdf, let controller else { return }
        if pdf.isLocked {
            askForPassword(wrong: false)
        } else {
            controller.display(pdf, page: restoredView?.page, scale: restoredView?.scale)
        }
    }

    // MARK: Password

    private func askForPassword(wrong: Bool) {
        guard let window = controller?.window else { return }
        let alert = NSAlert()
        alert.messageText = "“\(displayName ?? "This PDF")” is locked"
        alert.informativeText = wrong ? "Wrong password" : "Enter the password to open it."
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.animationBehavior = .none
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else {
                self.close()
                return
            }
            guard let pdf = self.pdf, pdf.unlock(withPassword: field.stringValue) else {
                self.askForPassword(wrong: true)
                return
            }
            self.password = field.stringValue
            self.controller?.display(pdf, page: self.restoredView?.page, scale: self.restoredView?.scale)
        }
    }

    // MARK: Reload on change

    /// Re-reads the file when it changes on disk, keeping the window's page and zoom. Changes
    /// arriving together collapse into one reload; a file that can't be read (missing, mid-write)
    /// leaves the last good content on screen.
    override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.reloadPending else { return }
            self.reloadPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.reload() }
        }
    }

    /// A deleted file leaves the window showing its last content.
    override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }

    private func reload() {
        reloadPending = false
        guard let url = fileURL, let fileType, let controller,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let state = controller.viewState
        let previous = pdf
        do {
            try revert(toContentsOf: url, ofType: fileType)
        } catch {
            pdf = previous
            return
        }
        guard let pdf else { return }
        if pdf.isLocked {
            // The password changed with the file.
            password = nil
            askForPassword(wrong: false)
        } else {
            controller.display(pdf, restoring: state)
        }
    }

    // MARK: Restoration

    private static let pageKey = "pageIndex", scaleKey = "scaleFactor"

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        guard let controller, pdf?.isLocked == false else { return }
        coder.encode(controller.currentPageIndex, forKey: Self.pageKey)
        coder.encode(Double(controller.pdfView.scaleFactor), forKey: Self.scaleKey)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard coder.containsValue(forKey: Self.pageKey) else { return }
        let view = (page: coder.decodeInteger(forKey: Self.pageKey),
                    scale: CGFloat(coder.decodeDouble(forKey: Self.scaleKey)))
        restoredView = view
        if let pdf, !pdf.isLocked { controller?.display(pdf, page: view.page, scale: view.scale) }
    }
}
