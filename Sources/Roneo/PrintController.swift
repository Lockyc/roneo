import AppKit
import PDFKit
import RoneoCore
import RoneoPDF

/// Runs one window's print bar: loads the printers off the main thread, keeps the window's
/// `PrintSettings` in step with the controls, gates Print on `Preflight` and sends the job to CUPS,
/// then shows its state. Its settings live and die with the window; nothing is persisted.
final class PrintController: NSObject, NSTextFieldDelegate {
    private weak var windowController: DocumentWindowController?
    private weak var document: PDFFileDocument?
    private let bar: PrintBarView
    private let cups = Cups(runner: ProcessRunner())
    private let queue = DispatchQueue(label: "roneo.print", qos: .userInitiated)

    /// nil while the list is loading.
    private var printers: [String]?
    /// Why the printers or the selected printer's options couldn't be read; blocks Print.
    private var loadFailure: String?
    private var capabilities: [String: PrinterCapabilities] = [:]
    /// True while the selected printer's options load.
    private var loadingOptions = false
    private var settings: PrintSettings?
    /// The Range field's text, kept while another Pages choice is selected.
    private var rangeText = ""
    /// True from Print until `lp` returns.
    private var sending = false
    /// Advances on every print, so a superseded job's polling stops updating the status.
    private var jobGeneration = 0

    private static let loadingReason = "Loading printers…"
    private static let unreachable = "Can't reach the print system"
    private static let pollInterval: TimeInterval = 1
    private static let pollLimit: TimeInterval = 120

    /// Scratch space for unlocked copies of encrypted PDFs.
    private static let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("roneo")
    /// The `HOME` `lp` runs with: empty, so no `~/.cups/lpoptions` applies.
    private static let emptyHome: URL = {
        let url = scratch.appendingPathComponent("home")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Installs the bar in `window`'s bar container in its loading state and starts loading the
    /// printers in the background.
    init(window: DocumentWindowController, document: PDFFileDocument) {
        windowController = window
        self.document = document
        bar = PrintBarView()
        super.init()
        install(in: window)
        render()
        loadPrinters()
    }

    private func install(in window: DocumentWindowController) {
        window.barHeight.isActive = false
        window.barContainer.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: window.barContainer.topAnchor),
            bar.bottomAnchor.constraint(equalTo: window.barContainer.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: window.barContainer.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: window.barContainer.trailingAnchor),
        ])
        for control in bar.settingControls + [bar.printButton] { control.target = self }
        bar.printer.action = #selector(printerChanged(_:))
        bar.sides.action = #selector(sidesChanged(_:))
        bar.scale.action = #selector(scaleChanged(_:))
        bar.pages.action = #selector(pagesChanged(_:))
        bar.copiesStepper.action = #selector(stepperChanged(_:))
        bar.paper.action = #selector(paperChanged(_:))
        bar.mediaType.action = #selector(mediaTypeChanged(_:))
        bar.tray.action = #selector(trayChanged(_:))
        bar.colour.action = #selector(colourChanged(_:))
        bar.printButton.action = #selector(printClicked(_:))
        bar.range.delegate = self
        bar.copies.delegate = self

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refresh), name: .PDFViewDocumentChanged, object: window.pdfView)
        if let w = window.window {
            center.addObserver(self, selector: #selector(refresh), name: NSWindow.didBecomeKeyNotification, object: w)
        }
    }

    // MARK: Loading

    private func loadPrinters() {
        let cups = self.cups
        queue.async { [weak self] in
            let result: Result<(names: [String], defaultName: String?, caps: PrinterCapabilities?), Error>
            do {
                let list = try cups.printers()
                let first = list.defaultName.flatMap { list.names.contains($0) ? $0 : nil } ?? list.names.first
                result = .success((list.names, first, try first.map { try cups.capabilities(for: $0) }))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { self?.printersLoaded(result) }
        }
    }

    private func printersLoaded(_ result: Result<(names: [String], defaultName: String?, caps: PrinterCapabilities?), Error>) {
        switch result {
        case .success(let loaded):
            printers = loaded.names
            if let name = loaded.defaultName, let caps = loaded.caps {
                capabilities[name] = caps
                settings = .defaults(printer: name, capabilities: caps)
            }
        case .failure:
            printers = []
            loadFailure = Self.unreachable
        }
        render()
    }

    @objc private func printerChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem, let current = settings, name != current.printer else { return }
        if let caps = capabilities[name] {
            settings = current.switching(to: name, capabilities: caps)
            render()
            return
        }
        loadingOptions = true
        render()
        let cups = self.cups
        queue.async { [weak self] in
            let caps = try? cups.capabilities(for: name)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingOptions = false
                if let caps, let latest = self.settings {
                    self.capabilities[name] = caps
                    self.settings = latest.switching(to: name, capabilities: caps)
                    self.loadFailure = nil
                } else {
                    self.loadFailure = "Can't read \(name)'s options"
                }
                self.render()
            }
        }
    }

    // MARK: Controls

    @objc private func sidesChanged(_ sender: NSSegmentedControl) {
        settings?.sides = sender.selectedSegment == 1 ? .double : .single
        render()
    }

    @objc private func scaleChanged(_ sender: NSSegmentedControl) {
        settings?.scale = sender.selectedSegment == 1 ? .fit : .actual
        render()
    }

    @objc private func pagesChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: settings?.pages = .current
        case 2: settings?.pages = .range(rangeText)
        default: settings?.pages = .all
        }
        render()
        if sender.selectedSegment == 2 { bar.window?.makeFirstResponder(bar.range) }
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        settings?.copies = sender.integerValue
        bar.copies.stringValue = "\(sender.integerValue)"
        render()
    }

    @objc private func paperChanged(_ sender: NSPopUpButton) {
        settings?.paper = sender.selectedItem?.representedObject as? String
        render()
    }

    @objc private func mediaTypeChanged(_ sender: NSPopUpButton) {
        settings?.mediaType = sender.selectedItem?.representedObject as? String
        render()
    }

    @objc private func trayChanged(_ sender: NSPopUpButton) {
        settings?.tray = sender.selectedItem?.representedObject as? String
        render()
    }

    @objc private func colourChanged(_ sender: NSSegmentedControl) {
        guard let choices = selectedCapabilities?.colourChoices else { return }
        settings?.colour = sender.selectedSegment == 1 ? choices.grey : choices.colour
        render()
    }

    /// Range and Copies take effect on every keystroke, so Print always sends what the fields show.
    /// Copies above the stepper's maximum are cut back to it in the field.
    func controlTextDidChange(_ note: Notification) {
        guard let field = note.object as? NSTextField else { return }
        if field === bar.range {
            rangeText = field.stringValue
            settings?.pages = .range(rangeText)
        } else if field === bar.copies {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            var copies = text.allSatisfy(\.isASCII) ? Int(text) ?? 0 : 0
            if copies > Int(bar.copiesStepper.maxValue) {
                copies = Int(bar.copiesStepper.maxValue)
                field.stringValue = "\(copies)"
            }
            settings?.copies = copies
        }
        render()
    }

    @objc func refresh() { render() }

    // MARK: Printing

    private var selectedCapabilities: PrinterCapabilities? { settings.flatMap { capabilities[$0.printer] } }

    private var pdf: PDFDocument? { windowController?.pdfView.document }

    /// Why Print is unavailable now, or nil when ⌘P and Print send the job.
    private var blockReason: String? {
        guard let printers, !loadingOptions else { return Self.loadingReason }
        if let loadFailure { return loadFailure }
        guard let settings, let pdf, let url = document?.fileURL else {
            return printers.isEmpty ? "No printers set up" : Self.loadingReason
        }
        if pdf.isLocked { return "Unlock the PDF to print" }
        if sending { return "Sending…" }
        return Preflight.blockReason(settings: settings, printers: printers, pageCount: pdf.pageCount,
                                     fileExists: FileManager.default.fileExists(atPath: url.path),
                                     allowsPrinting: PDFFacts.allowsPrinting(pdf))
    }

    var canPrint: Bool { blockReason == nil }

    @objc private func printClicked(_ sender: Any?) { printFromBar() }

    /// Sends the job with exactly the bar's settings, then follows it in CUPS.
    func printFromBar() {
        guard blockReason == nil, let settings, let pdf, let original = document?.fileURL,
              let windowController else { return }
        let pageCount = pdf.pageCount
        let pages = settings.pages.pageCount(of: pageCount) ?? 0
        let file: (url: URL, isTemporary: Bool)
        do {
            file = try PrintableFile.url(for: pdf, original: original, scratch: Self.scratch)
        } catch {
            show("Didn't print: \(error.localizedDescription)")
            return
        }
        let args = JobBuilder.lpArguments(settings: settings, file: file.url,
                                          currentPage: windowController.currentPageIndex + 1,
                                          pageCount: pageCount,
                                          firstPageLandscape: PDFFacts.firstPageIsLandscape(pdf))
        jobGeneration += 1
        let generation = jobGeneration
        sending = true
        show("Sending…")
        render()
        let submitter = PrintSubmitter(runner: ProcessRunner(), emptyHome: Self.emptyHome)
        queue.async { [weak self] in
            let result = Result { try submitter.submit(args) }
            if file.isTemporary { try? FileManager.default.removeItem(at: file.url) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sending = false
                switch result {
                case .success(let id):
                    self.show(.sent(pages: pages), generation: generation)
                    self.poll(id: id, printer: settings.printer, generation: generation)
                case .failure(let error):
                    self.show("Didn't print: \(Self.describe(error))")
                }
                self.render()
            }
        }
    }

    /// Asks CUPS for the job's state every `pollInterval` until it is done or failed, or
    /// `pollLimit` passes; the last state stays shown.
    private func poll(id: String, printer: String, generation: Int) {
        let cups = self.cups
        let deadline = Date().addingTimeInterval(Self.pollLimit)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while Date() < deadline {
                Thread.sleep(forTimeInterval: Self.pollInterval)
                let state: JobState?
                do { state = try cups.jobState(id: id, printer: printer) } catch { state = nil }
                var stop = false
                DispatchQueue.main.sync {
                    guard let self, self.jobGeneration == generation else { stop = true; return }
                    if let state { self.show(state, generation: generation) } else { self.show(Self.unreachable) }
                }
                if stop { return }
                switch state {
                case .done, .failed: return
                default: continue
                }
            }
        }
    }

    private func show(_ state: JobState, generation: Int) {
        guard generation == jobGeneration else { return }
        switch state {
        case .sent(let pages): show("Sent · \(pages) page\(pages == 1 ? "" : "s")")
        case .printing: show("Printing")
        case .done: show("Done")
        case .failed(let text): show("Didn't print: \(text)")
        }
    }

    private func show(_ text: String) {
        bar.status.stringValue = text
        bar.status.toolTip = text.isEmpty ? nil : text
    }

    private static func describe(_ error: Error) -> String {
        guard let cups = error as? CupsError else { return error.localizedDescription }
        let text = cups.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? unreachable : text
    }

    // MARK: Rendering

    /// Sets every control from the settings and the selected printer's options. A control that
    /// can't be used stays in place, disabled, with the reason as its tooltip.
    private func render() {
        let caps = selectedCapabilities
        let blocked: String? = {
            guard let printers, !loadingOptions else { return Self.loadingReason }
            if printers.isEmpty { return loadFailure ?? "No printers set up" }
            return settings == nil ? (loadFailure ?? Self.loadingReason) : nil
        }()

        renderPrinterPopup(blocked: blocked)
        if let blocked {
            for control in bar.settingControls where control !== bar.printer {
                control.isEnabled = false
                control.toolTip = blocked
            }
        }
        if blocked == nil, let settings, let caps {
            for control in bar.settingControls {
                control.isEnabled = true
                control.toolTip = nil
            }
            bar.sides.selectedSegment = settings.sides == .double ? 1 : 0
            if !caps.supportsDuplex {
                bar.sides.isEnabled = false
                bar.sides.toolTip = "This printer can't print double-sided"
            }
            bar.scale.selectedSegment = settings.scale == .fit ? 1 : 0
            switch settings.pages {
            case .all: bar.pages.selectedSegment = 0
            case .current: bar.pages.selectedSegment = 1
            case .range: bar.pages.selectedSegment = 2
            }
            if bar.range.stringValue != rangeText { bar.range.stringValue = rangeText }
            if case .range = settings.pages {} else {
                bar.range.isEnabled = false
                bar.range.toolTip = "Choose Range to enter pages"
            }
            if bar.copies.currentEditor() == nil { bar.copies.stringValue = "\(settings.copies)" }
            bar.copiesStepper.integerValue = min(max(settings.copies, 1), 999)
            renderChoices(bar.paper, caps.option("PageSize"), selected: settings.paper,
                          missing: "This printer has no paper size choice")
            renderChoices(bar.mediaType, caps.option("MediaType"), selected: settings.mediaType,
                          missing: "This printer has no paper type choice")
            renderChoices(bar.tray, caps.option("InputSlot"), selected: settings.tray,
                          missing: "This printer has no tray choice")
            renderColour(caps, selected: settings.colour)
        }

        let reason = blockReason
        bar.printButton.isEnabled = reason == nil
        bar.printButton.toolTip = reason ?? "Print with these settings (⌘P)"
    }

    private func renderPrinterPopup(blocked: String?) {
        let popup = bar.printer
        let names = printers ?? []
        let titles = names.isEmpty ? [printers == nil ? Self.loadingReason : "No printers"] : names
        if popup.itemTitles != titles {
            popup.removeAllItems()
            popup.addItems(withTitles: titles)
        }
        if let settings { popup.selectItem(withTitle: settings.printer) }
        popup.isEnabled = !names.isEmpty && !loadingOptions && settings != nil
        popup.toolTip = popup.isEnabled ? nil : blocked
    }

    private func renderChoices(_ popup: NSPopUpButton, _ option: PrinterOption?, selected: String?, missing: String) {
        popup.removeAllItems()
        guard let option else {
            popup.addItem(withTitle: "—")
            popup.isEnabled = false
            popup.toolTip = missing
            return
        }
        // Through the menu: `addItem(withTitle:)` drops a title already present.
        for choice in option.choices {
            let item = NSMenuItem(title: ChoiceLabel.display(choice), action: nil, keyEquivalent: "")
            item.representedObject = choice
            popup.menu?.addItem(item)
        }
        if let selected, let index = option.choices.firstIndex(of: selected) { popup.selectItem(at: index) }
    }

    private func renderColour(_ caps: PrinterCapabilities, selected: String?) {
        guard let choices = caps.colourChoices else {
            bar.colour.isEnabled = false
            guard let selected else {
                bar.colour.toolTip = "This printer has no colour choice"
                bar.colour.selectedSegment = -1
                return
            }
            // The one mode the printer has is still the one the job sends, so it shows.
            let grey = ColourChoices.isGrey(selected)
            bar.colour.toolTip = grey ? "This printer prints only in grey" : "This printer has no greyscale mode"
            bar.colour.selectedSegment = grey ? 1 : 0
            return
        }
        bar.colour.selectedSegment = selected == choices.grey ? 1 : 0
    }
}
