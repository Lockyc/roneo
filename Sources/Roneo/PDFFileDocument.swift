import AppKit
import OSLog
import PDFKit
import RoneoCore

/// A PDF open for viewing. Read-only: never edited, saved or autosaved. The whole file is read into
/// memory, so the window keeps showing it if the file is replaced mid-write or deleted.
@objc(PDFFileDocument) final class PDFFileDocument: NSDocument {
    private(set) var pdf: PDFDocument?
    /// The bytes `pdf` was parsed from; Print sends these, so the job is what the window shows.
    private(set) var data: Data?
    /// The password that unlocked this file, reused when a change on disk reloads it and when
    /// printing unlocks its own copy of `data`.
    private(set) var password: String?
    /// Page and zoom from window restoration, applied once the document is viewable (after unlock).
    private var restoredView: DocumentWindowController.ViewState?
    /// True once the window has shown the document or asked for its password; later `showWindows`
    /// calls (reopening an open file) only bring the window forward.
    private var didPresent = false
    private var passwordSheetIsUp = false
    private var reload = ReloadGate<DocumentWindowController.ViewState>()
    private var reloadTimer: Timer?
    private var watcher: FileWatcher?
    private static let log = Logger(subsystem: "com.lockyc.roneo", category: "reload")

    /// How long the file must go without changing before it is re-read.
    private static let settleDelay: TimeInterval = 0.1

    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override class var writableTypes: [String] { [] }
    override class func isNativeType(_ type: String) -> Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }
    override var isEntireFileLoaded: Bool { true }

    override func read(from url: URL, ofType typeName: String) throws {
        let stamp = FileStamp(of: url)
        try super.read(from: url, ofType: typeName)
        reload.didRead(stamp)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let pdf = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if pdf.isLocked, let password { pdf.unlock(withPassword: password) }
        self.pdf = pdf
        self.data = data
    }

    override func makeWindowControllers() {
        let window = DocumentWindowController()
        addWindowController(window)
        window.printController = PrintController(window: window, document: self)
    }

    private var controller: DocumentWindowController? {
        windowControllers.first as? DocumentWindowController
    }

    /// A document with no file: the window a launch or Dock click shows when it opens nothing.
    var isBlank: Bool { fileURL == nil }

    /// Shows a blank window: the document layout with no PDF and Print disabled. It is never
    /// restored, and opening a PDF closes it.
    static func openBlank() {
        let blank = PDFFileDocument()
        NSDocumentController.shared.addDocument(blank)
        blank.makeWindowControllers()
        blank.controller?.window?.isRestorable = false
        blank.controller?.showEmpty()
        blank.showWindows()
    }

    override func showWindows() {
        super.showWindows()
        if !isBlank {
            for case let blank as PDFFileDocument in NSDocumentController.shared.documents where blank.isBlank {
                blank.close()
            }
        }
        present(restoring: restoredView)
    }

    /// Shows the document in its window, or asks for its password, once: from `showWindows` when
    /// opened, from `restoreState` when window restoration reopens it (which never calls
    /// `showWindows`), whichever comes first.
    private func present(restoring view: DocumentWindowController.ViewState?) {
        guard !didPresent, let pdf, let controller else { return }
        didPresent = true
        watch()
        if pdf.isLocked {
            askForPassword(wrong: false)
        } else {
            controller.display(pdf, restoring: view)
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
            guard let pdf = self.pdf else { return }
            // A reload while the sheet was up may have brought an unencrypted file.
            if pdf.isLocked {
                guard pdf.unlock(withPassword: field.stringValue) else {
                    self.askForPassword(wrong: true)
                    return
                }
                self.password = field.stringValue
            }
            self.controller?.display(pdf, restoring: self.reload.takePreReloadView() ?? self.restoredView)
        }
    }

    // MARK: Reload on change

    /// The file at `fileURL` is watched (`FileWatcher`) from when the document is first shown, and
    /// the watch follows a move of the file.
    override var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.watcher != nil else { return }
                self.watch()
            }
        }
    }

    private func watch() {
        watcher?.cancel()
        watcher = fileURL.map { FileWatcher(url: $0) { [weak self] in self?.fileMayHaveChanged() } }
    }

    override func close() {
        watcher?.cancel()
        watcher = nil
        reloadTimer?.invalidate()
        super.close()
    }

    /// Coordinated writes reach the document as a presenter too; both feed the same gate.
    override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in self?.fileMayHaveChanged() }
    }

    /// Re-reads the file once it has stopped changing (`ReloadGate`), keeping the window's page and
    /// zoom; a file that can't be read leaves the last good content on screen, and a deleted one
    /// disables Print.
    private func fileMayHaveChanged() {
        guard let url = fileURL else { return }
        let view = pdf?.isLocked == false ? controller?.viewState : nil
        guard reload.changed(stamp: FileStamp(of: url), size: fileSize, view: view) else { return }
        Self.log.debug("change seen, settling")
        startSettleTimer()
        controller?.printController?.refresh()
    }

    override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
        DispatchQueue.main.async { [weak self] in self?.fileMayHaveChanged() }
    }

    private var fileSize: Int? {
        guard let path = fileURL?.path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
    }

    private func startSettleTimer() {
        reloadTimer?.invalidate()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            self?.reloadIfSettled()
        }
    }

    private func reloadIfSettled() {
        reloadTimer = nil
        let settle = reload.settled(size: fileSize)
        Self.log.info("settled: \(String(describing: settle), privacy: .public)")
        switch settle {
        case .keepLastContent: return
        case .wait: startSettleTimer()
        case .reload: revertToFile()
        }
    }

    private func revertToFile() {
        guard let url = fileURL, let fileType, let controller else { return }
        let previous = (pdf, data, reload)
        do {
            try revert(toContentsOf: url, ofType: fileType)
        } catch {
            Self.log.error("reload failed, keeping last content: \(error.localizedDescription, privacy: .public)")
            (pdf, data, reload) = previous
            return
        }
        guard let pdf else { return }
        if pdf.isLocked {
            // The password changed with the file.
            password = nil
            askForPassword(wrong: false)
        } else if !passwordSheetIsUp {
            controller.display(pdf, restoring: reload.takePreReloadView())
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
        if coder.containsValue(forKey: Self.pageKey) {
            restoredView = DocumentWindowController.ViewState(
                page: coder.decodeInteger(forKey: Self.pageKey), point: nil,
                autoScales: coder.decodeBool(forKey: Self.fitKey),
                scale: CGFloat(coder.decodeDouble(forKey: Self.scaleKey)))
        }
        if didPresent {
            if let pdf, !pdf.isLocked, let restoredView { controller?.display(pdf, restoring: restoredView) }
        } else {
            present(restoring: restoredView)
        }
    }
}
