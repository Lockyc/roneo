import AppKit
import PDFKit

/// One document window: a collapsible page-thumbnail sidebar beside the page column, which stacks
/// the print bar's container, the find strip (shown by ⌘F) and the `PDFView`.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSSearchFieldDelegate, PDFDocumentDelegate {
    let pdfView = PDFView()
    /// Holds the print bar, above the page. Empty and zero-height until the bar is installed.
    let barContainer = NSView()

    private let thumbnails = PDFThumbnailView()
    private let split = NSSplitView()
    private let findStrip = NSStackView()
    private let findField = NSSearchField()
    private let findCount = NSTextField(labelWithString: "")
    private var matches: [PDFSelection] = []
    private var matchIndex = -1
    private var searching = false
    /// The text the current matches are for.
    private var searchedText = ""

    /// The zero-based index of the page the view shows; setting it scrolls to that page.
    var currentPageIndex: Int {
        get {
            guard let doc = pdfView.document, let page = pdfView.currentPage else { return 0 }
            return doc.index(for: page)
        }
        set {
            guard let doc = pdfView.document, doc.pageCount > 0,
                  let page = doc.page(at: min(max(newValue, 0), doc.pageCount - 1)) else { return }
            pdfView.go(to: page)
        }
    }

    init() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let size = NSSize(width: min(900, visible.width), height: min(1100, visible.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.tabbingMode = .disallowed
        window.animationBehavior = .none
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        super.init(window: window)
        window.delegate = self
        buildViews(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildViews(in window: NSWindow) {
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = true

        thumbnails.pdfView = pdfView
        thumbnails.thumbnailSize = NSSize(width: 96, height: 128)
        thumbnails.backgroundColor = .windowBackgroundColor

        buildFindStrip()

        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.heightAnchor.constraint(equalToConstant: 0).isActive = true

        let column = NSStackView(views: [barContainer, findStrip, pdfView])
        column.orientation = .vertical
        column.spacing = 0
        column.alignment = .width
        column.setHuggingPriority(.defaultLow, for: .vertical)
        pdfView.setContentHuggingPriority(.defaultLow, for: .vertical)

        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(thumbnails)
        split.addArrangedSubview(column)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        window.contentView = split
        thumbnails.frame.size.width = 140
        split.setPosition(140, ofDividerAt: 0)

        NotificationCenter.default.addObserver(self, selector: #selector(viewStateChanged(_:)),
                                               name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(viewStateChanged(_:)),
                                               name: .PDFViewScaleChanged, object: pdfView)
    }

    private func buildFindStrip() {
        findField.placeholderString = "Find"
        findField.sendsSearchStringImmediately = false
        findField.sendsWholeSearchString = false
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findFieldChanged(_:))
        findField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        findCount.textColor = .secondaryLabelColor
        let previous = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!,
                                target: self, action: #selector(findPrevious(_:)))
        let next = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!,
                            target: self, action: #selector(findNext(_:)))
        let done = NSButton(title: "Done", target: self, action: #selector(closeFind(_:)))
        for button in [previous, next, done] { button.bezelStyle = .accessoryBarAction }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        [findField, previous, next, findCount, spacer, done].forEach(findStrip.addArrangedSubview)
        findStrip.orientation = .horizontal
        findStrip.spacing = 6
        findStrip.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        findStrip.isHidden = true
    }

    // MARK: Showing a document

    /// Shows `pdf`, at `page` and `scale` when given (from window restoration), else fitted to width
    /// at its first page.
    func display(_ pdf: PDFDocument, page: Int? = nil, scale: CGFloat? = nil) {
        pdfView.document = pdf
        if let scale, scale > 0 {
            pdfView.autoScales = false
            pdfView.scaleFactor = scale
        } else {
            pdfView.autoScales = true
        }
        if let page { currentPageIndex = page }
    }

    /// The view's position and zoom, carried across a reload.
    struct ViewState {
        let page: Int
        let point: NSPoint?
        let autoScales: Bool
        let scale: CGFloat
    }

    var viewState: ViewState {
        ViewState(page: currentPageIndex, point: pdfView.currentDestination?.point,
                  autoScales: pdfView.autoScales, scale: pdfView.scaleFactor)
    }

    /// Shows the re-read `pdf` at the page, scroll point and zoom of `state`.
    func display(_ pdf: PDFDocument, restoring state: ViewState) {
        clearMatches()
        pdfView.document = pdf
        if state.autoScales {
            pdfView.autoScales = true
        } else {
            pdfView.autoScales = false
            pdfView.scaleFactor = state.scale
        }
        guard pdf.pageCount > 0, let page = pdf.page(at: min(state.page, pdf.pageCount - 1)) else { return }
        if let point = state.point {
            pdfView.go(to: PDFDestination(page: page, at: point))
        } else {
            pdfView.go(to: page)
        }
    }

    @objc private func viewStateChanged(_ note: Notification) {
        document?.invalidateRestorableState()
    }

    // MARK: View menu

    @objc func toggleThumbnails(_ sender: Any?) {
        thumbnails.isHidden.toggle()
        split.adjustSubviews()
        if !thumbnails.isHidden { split.setPosition(140, ofDividerAt: 0) }
    }

    @objc func actualSize(_ sender: Any?) {
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
    }

    @objc func zoomToFitWidth(_ sender: Any?) {
        pdfView.autoScales = true
    }

    @objc func zoomIn(_ sender: Any?) { pdfView.zoomIn(sender) }
    @objc func zoomOut(_ sender: Any?) { pdfView.zoomOut(sender) }

    @objc func goToPage(_ sender: Any?) {
        guard let window, let doc = pdfView.document, doc.pageCount > 0, !doc.isLocked else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Page 1 to \(doc.pageCount)"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "\(currentPageIndex + 1)")
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.animationBehavior = .none
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let number = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            self?.currentPageIndex = number - 1
        }
    }

    // MARK: File menu

    /// The system print dialog for what the print bar doesn't cover, at 100% by default.
    @objc func printWithSystemDialog(_ sender: Any?) {
        guard let window, let doc = pdfView.document, let info = document?.printInfo,
              let operation = doc.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: true)
        else { return }
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Find

    @objc func showFind(_ sender: Any?) {
        findStrip.isHidden = false
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    @objc func findNext(_ sender: Any?) { step(by: 1) }
    @objc func findPrevious(_ sender: Any?) { step(by: -1) }

    @objc func closeFind(_ sender: Any?) {
        pdfView.document?.cancelFindString()
        clearMatches()
        findStrip.isHidden = true
        window?.makeFirstResponder(pdfView)
    }

    /// ⌘G and ⇧⌘G open the strip when there is nothing to cycle through.
    private func step(by delta: Int) {
        guard !matches.isEmpty else {
            if findStrip.isHidden || findField.stringValue.isEmpty { showFind(nil) } else { startSearch() }
            return
        }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        showCurrentMatch()
    }

    @objc private func findFieldChanged(_ sender: Any?) { startSearch() }

    private func startSearch() {
        guard let doc = pdfView.document, !doc.isLocked else { return }
        if searching { doc.cancelFindString() }
        clearMatches()
        let text = findField.stringValue
        searchedText = text
        guard !text.isEmpty else { return }
        doc.delegate = self
        searching = true
        findCount.stringValue = "Searching…"
        doc.beginFindString(text, withOptions: [.caseInsensitive])
    }

    private func clearMatches() {
        matches = []
        matchIndex = -1
        pdfView.highlightedSelections = nil
        pdfView.clearSelection()
        findCount.stringValue = ""
    }

    func didMatchString(_ instance: PDFSelection) {
        instance.color = .systemYellow
        matches.append(instance)
        if matchIndex < 0 {
            matchIndex = 0
            showCurrentMatch()
        }
        updateCount()
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        searching = false
        pdfView.highlightedSelections = matches
        updateCount()
    }

    private func updateCount() {
        if matches.isEmpty {
            findCount.stringValue = searching ? "Searching…" : "Not found"
        } else {
            findCount.stringValue = "\(matchIndex + 1) of \(matches.count)"
        }
    }

    private func showCurrentMatch() {
        guard matches.indices.contains(matchIndex) else { return }
        let match = matches[matchIndex]
        if !searching { pdfView.highlightedSelections = matches }
        pdfView.setCurrentSelection(match, animate: false)
        pdfView.go(to: match)
        updateCount()
    }

    /// Return and ⇧Return step through matches; Escape closes the strip.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            closeFind(nil)
        case #selector(NSResponder.insertNewline(_:)):
            if matches.isEmpty || findField.stringValue != searchedText { startSearch() } else {
                step(by: NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? -1 : 1)
            }
        default:
            return false
        }
        return true
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let viewable = pdfView.document.map { !$0.isLocked && $0.pageCount > 0 } ?? false
        switch item.action {
        case #selector(toggleThumbnails(_:)):
            item.title = thumbnails.isHidden ? "Show Thumbnails" : "Hide Thumbnails"
            return true
        case #selector(zoomIn(_:)):
            return viewable && pdfView.canZoomIn
        case #selector(zoomOut(_:)):
            return viewable && pdfView.canZoomOut
        case #selector(actualSize(_:)), #selector(zoomToFitWidth(_:)), #selector(goToPage(_:)),
             #selector(showFind(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)):
            return viewable
        case #selector(printWithSystemDialog(_:)):
            return viewable && pdfView.document?.allowsPrinting == true
        default:
            return true
        }
    }
}
