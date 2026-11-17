import AppKit
import PDFKit

/// A PDF open for viewing. Read-only: never edited, saved or autosaved. The whole file is read into
/// memory, so the window keeps showing it if the file is replaced mid-write or deleted.
@objc(PDFFileDocument) final class PDFFileDocument: NSDocument {
    private(set) var pdf: PDFDocument?
    /// The password that unlocked this file, reused when a change on disk reloads it.
    private var password: String?
    /// Page and zoom from window restoration, applied once the document is viewable (after unlock).
    private var restoredView: DocumentWindowController.ViewState?
    /// True once the window has shown the document or asked for its password; later `showWindows`
    /// calls (reopening an open file) only bring the window forward.
    private var didPresent = false
    private var passwordSheetIsUp = false
    /// The view state from before a burst of changes on disk, kept until a reload of a settled file
    /// completes, so a reload of a half-written file can't move the view for good.
    private var preReloadView: DocumentWindowController.ViewState?
    private var reloadTimer: Timer?
    /// The file's size when the reload timer last started.
    private var sizeAtChange: Int?

    /// How long the file must go without changing before it is re-read.
    private static let settleDelay: TimeInterval = 0.25

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
        if pdf.isLocked, let password { pdf.unlock(withPassword: password) }
        self.pdf = pdf
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    private var controller: DocumentWindowController? {
        windowControllers.first as? DocumentWindowController
    }

    override func showWindows() {
        super.showWindows()
        guard !didPresent, let pdf, let controller else { return }
        didPresent = true
        if pdf.isLocked {
            askForPassword(wrong: false)
        } else {
            controller.display(pdf, restoring: restoredView)
        }
    }

    // MARK: Password

    private func askForPassword(wrong: Bool) {
        guard !passwordSheetIsUp, let window = controller?.window else { return }
        passwordSheetIsUp = true
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
            self.passwordSheetIsUp = false
            guard response == .alertFirstButtonReturn else {
                self.close()
                return
            }
            guard let pdf = self.pdf, pdf.unlock(withPassword: field.stringValue) else {
                self.askForPassword(wrong: true)
                return
            }
            self.password = field.stringValue
            self.controller?.display(pdf, restoring: self.preReloadView ?? self.restoredView)
        }
    }

    // MARK: Reload on change

    /// Re-reads the file once it has stopped changing, keeping the window's page and zoom. Each
    /// change restarts the wait; a file that can't be read (missing, mid-write) leaves the last good
    /// content on screen.
    override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in self?.scheduleReload() }
    }

    /// A deleted file leaves the window showing its last content.
    override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }

    private var fileSize: Int? {
        guard let path = fileURL?.path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
    }

    private func scheduleReload() {
        if preReloadView == nil, pdf?.isLocked == false { preReloadView = controller?.viewState }
        sizeAtChange = fileSize
        reloadTimer?.invalidate()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            self?.reloadIfSettled()
        }
    }

    private func reloadIfSettled() {
        reloadTimer = nil
        guard let size = fileSize else { return }  // Missing: keep the last content.
        guard size == sizeAtChange else {
            scheduleReload()
            return
        }
        guard let url = fileURL, let fileType, let controller else { return }
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
        } else if !passwordSheetIsUp {
            controller.display(pdf, restoring: preReloadView)
            preReloadView = nil
        }
    }

    // MARK: Restoration

    private static let pageKey = "pageIndex", scaleKey = "scaleFactor", fitKey = "fitsWidth"

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        guard let controller, pdf?.isLocked == false else { return }
        let view = controller.viewState
        coder.encode(view.page, forKey: Self.pageKey)
        coder.encode(Double(view.scale), forKey: Self.scaleKey)
        coder.encode(view.autoScales, forKey: Self.fitKey)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard coder.containsValue(forKey: Self.pageKey) else { return }
        let view = DocumentWindowController.ViewState(
            page: coder.decodeInteger(forKey: Self.pageKey), point: nil,
            autoScales: coder.decodeBool(forKey: Self.fitKey),
            scale: CGFloat(coder.decodeDouble(forKey: Self.scaleKey)))
        restoredView = view
        if let pdf, !pdf.isLocked, didPresent { controller?.display(pdf, restoring: view) }
    }
}
