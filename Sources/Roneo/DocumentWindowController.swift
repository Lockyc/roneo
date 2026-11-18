import AppKit
import PDFKit

/// One document window: the print bar's container across the top, above a collapsible
/// page-thumbnail sidebar beside the page column, which stacks the find strip (shown by ⌘F) and
/// the `PDFView`.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSSearchFieldDelegate, PDFDocumentDelegate {
    /// A `PageView` only when `FirstDrawTimer` is on, so the draw override never costs a normal run.
    let pdfView: PDFView = FirstDrawTimer.isEnabled ? PageView() : PDFView()
    /// Holds the print bar, above the page. Empty until the bar is installed.
    let barContainer = NSView()
    /// Fixes `barContainer` at zero height while it is empty; deactivate it when installing the bar.
    let barHeight: NSLayoutConstraint
    /// The print bar's controller, installed by the document once the window exists.
    var printController: PrintController?

    private static let sidebarWidth: CGFloat = 140
    /// Wide enough for the whole print bar unclipped.
    private static let defaultWidth: CGFloat = 1100
    private let thumbnails = PDFThumbnailView()
    private let split = NSSplitView()
    private let findStrip = NSStackView()
    private let findField = NSSearchField()
    private let findCount = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: PrintController.noPDF)
    private var matches: [PDFSelection] = []
    private var matchIndex = -1
    /// Advances on every search begun or cancelled.
    private var searchGeneration = 0
    /// The generation of the search in progress; nil when none runs.
    private var runningSearch: Int?
    /// The text the current matches are for.
    private var searchedText = ""
    /// The page in view when the current search began.
    private var searchStartPage = 0

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
        let size = NSSize(width: min(Self.defaultWidth, visible.width), height: min(1100, visible.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.tabbingMode = .disallowed
        window.animationBehavior = .none
        window.minSize = NSSize(width: 480, height: 360)
        if let last = NSApp.mainWindow {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else {
            window.center()
        }
        barHeight = barContainer.heightAnchor.constraint(equalToConstant: 0)
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
        thumbnails.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        let preferred = thumbnails.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        preferred.priority = .init(260)
        preferred.isActive = true

        buildFindStrip()

        emptyLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 4)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        pdfView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: pdfView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: pdfView.centerYAnchor),
        ])

        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barHeight.isActive = true

        let column = NSStackView(views: [findStrip, pdfView])
        column.orientation = .vertical
        column.spacing = 0
        column.alignment = .width
        column.setHuggingPriority(.defaultLow, for: .vertical)
        pdfView.setContentHuggingPriority(.defaultLow, for: .vertical)

        split.isVertical = true
        split.dividerStyle = .thin
        split.frame = window.contentLayoutRect
        split.addArrangedSubview(thumbnails)
        split.addArrangedSubview(column)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        split.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: window.contentLayoutRect)
        content.addSubview(barContainer)
        content.addSubview(split)
        NSLayoutConstraint.activate([
            barContainer.topAnchor.constraint(equalTo: content.topAnchor),
            barContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            barContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: barContainer.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.layoutIfNeeded()
        split.setPosition(Self.sidebarWidth, ofDividerAt: 0)

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

    /// The view's position and zoom, carried across a reload and through window restoration.
    struct ViewState {
        /// The page `point` lies on.
        let page: Int
        /// The top-left visible point, in `page`'s coordinates; nil scrolls to the page's top.
        let point: NSPoint?
        /// Fitted to width; `scale` applies only when false.
        let autoScales: Bool
        let scale: CGFloat
    }

    /// The view's position and zoom. Page and point both come from `currentDestination`, so they
    /// name the same page.
    var viewState: ViewState {
        let destination = pdfView.currentDestination
        let page = destination?.page.flatMap { pdfView.document?.index(for: $0) }
        return ViewState(page: page ?? currentPageIndex, point: page == nil ? nil : destination?.point,
                         autoScales: pdfView.autoScales, scale: pdfView.scaleFactor)
    }

    /// Shows `pdf` at the page, scroll point and zoom of `state`, or fitted to width at its first
    /// page when `state` is nil.
    func display(_ pdf: PDFDocument, restoring state: ViewState? = nil) {
        emptyLabel.isHidden = true
        cancelSearch(on: pdfView.document)
        clearMatches()
        pdfView.document = pdf
        guard let state else {
            pdfView.autoScales = true
            return
        }
        if state.autoScales {
            pdfView.autoScales = true
        } else if state.scale > 0 {
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

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        (document as? PDFFileDocument)?.isBlank == true ? "roneo" : displayName
    }

    /// The page area of a window with no PDF.
    func showEmpty() {
        emptyLabel.isHidden = false
    }

    @objc private func viewStateChanged(_ note: Notification) {
        document?.invalidateRestorableState()
    }

    // MARK: View menu

    @objc func toggleThumbnails(_ sender: Any?) {
        thumbnails.isHidden.toggle()
        split.adjustSubviews()
        if !thumbnails.isHidden { split.setPosition(Self.sidebarWidth, ofDividerAt: 0) }
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

    /// ⌘P: sends the job with the print bar's settings.
    @objc func printFromBar(_ sender: Any?) {
        printController?.printFromBar()
    }

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
        cancelSearch(on: pdfView.document)
        clearMatches()
        findStrip.isHidden = true
        window?.makeFirstResponder(pdfView)
    }

    /// ⌘G and ⇧⌘G open the strip when there is nothing to cycle through. With matches but none
    /// chosen yet, either goes to the first match at or after the page the search began on.
    private func step(by delta: Int) {
        guard !matches.isEmpty else {
            if findStrip.isHidden || findField.stringValue.isEmpty { showFind(nil) } else { startSearch() }
            return
        }
        if matchIndex < 0 {
            matchIndex = firstMatchFromStartPage ?? 0
        } else {
            matchIndex = (matchIndex + delta + matches.count) % matches.count
        }
        showCurrentMatch()
    }

    private var firstMatchFromStartPage: Int? {
        guard let doc = pdfView.document else { return nil }
        return matches.firstIndex { match in
            match.pages.first.map { doc.index(for: $0) >= searchStartPage } ?? false
        }
    }

    @objc private func findFieldChanged(_ sender: Any?) { startSearch() }

    private var isSearching: Bool { runningSearch != nil }

    private func startSearch() {
        guard let doc = pdfView.document, !doc.isLocked else { return }
        cancelSearch(on: doc)
        clearMatches()
        let text = findField.stringValue
        searchedText = text
        guard !text.isEmpty else { return }
        doc.delegate = self
        searchStartPage = currentPageIndex
        searchGeneration += 1
        runningSearch = searchGeneration
        findCount.stringValue = "Searching…"
        doc.beginFindString(text, withOptions: [.caseInsensitive])
    }

    /// Stops the running search. `cancelFindString` posts the search's end notification before it
    /// returns; the generation moves first, so that end is never taken for a completed search.
    private func cancelSearch(on doc: PDFDocument?) {
        guard isSearching else { return }
        searchGeneration += 1
        runningSearch = nil
        doc?.cancelFindString()
    }

    private func clearMatches() {
        matches = []
        matchIndex = -1
        pdfView.highlightedSelections = nil
        pdfView.clearSelection()
        findCount.stringValue = ""
    }

    /// Matches arrive in page order; the first shown is the first at or after the page in view
    /// when the search began.
    func didMatchString(_ instance: PDFSelection) {
        guard isSearching, let doc = pdfView.document,
              let page = instance.pages.first, page.document === doc,
              instance.string?.caseInsensitiveCompare(searchedText) == .orderedSame else { return }
        instance.color = .systemYellow
        matches.append(instance)
        if matchIndex < 0, doc.index(for: page) >= searchStartPage {
            matchIndex = matches.count - 1
            showCurrentMatch()
        }
        updateCount()
    }

    /// Completes the running search; the end of a cancelled one finds no running search and is
    /// ignored.
    func documentDidEndDocumentFind(_ notification: Notification) {
        guard let token = runningSearch, token == searchGeneration, let doc = pdfView.document,
              notification.object as? PDFDocument === doc else { return }
        runningSearch = nil
        if matchIndex < 0, !matches.isEmpty {
            matchIndex = 0
            showCurrentMatch()
        }
        pdfView.highlightedSelections = matches
        updateCount()
    }

    /// Escape closes the find strip wherever focus is in the window.
    override func cancelOperation(_ sender: Any?) {
        if findStrip.isHidden {
            nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
        } else {
            closeFind(sender)
        }
    }

    private func updateCount() {
        if matches.isEmpty {
            findCount.stringValue = isSearching ? "Searching…" : "Not found"
        } else if matchIndex < 0 {
            findCount.stringValue = "\(matches.count) found"
        } else {
            findCount.stringValue = "\(matchIndex + 1) of \(matches.count)"
        }
    }

    private func showCurrentMatch() {
        guard matches.indices.contains(matchIndex) else { return }
        let match = matches[matchIndex]
        if !isSearching { pdfView.highlightedSelections = matches }
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
        case #selector(printFromBar(_:)):
            return printController?.canPrint == true
        case #selector(printWithSystemDialog(_:)):
            return viewable && pdfView.document?.allowsPrinting == true
        default:
            return true
        }
    }
}
