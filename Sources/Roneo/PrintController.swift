import AppKit
import PDFKit
import RoneoCore
import RoneoPDF

/// Runs one window's print bar: takes the printers from `PrinterDirectory`, keeps the window's
/// `PrintSettings` in step with the controls, gates Print on `Preflight` and sends the job to CUPS,
/// then shows its state. Its settings live and die with the window; nothing is persisted.
final class PrintController: NSObject, NSTextFieldDelegate {
    private weak var windowController: DocumentWindowController?
    private weak var document: PDFFileDocument?
    private let bar: PrintBarView
    private let cups = PrinterDirectory.shared.cups
    private let queue = DispatchQueue(label: "roneo.print", qos: .userInitiated)

    /// Queue names; nil while the list is loading.
    private var printers: [String]?
    /// Each queue's description, the name the popup shows.
    private var descriptions: [String: String] = [:]
    /// Why the printer list couldn't be read; blocks Print.
    private var loadFailure: String?
    private var capabilities: [String: PrinterCapabilities] = [:]
    /// The queue the popup shows; `settings.printer` whenever there are settings.
    private var selectedPrinter: String?
    /// Why `selectedPrinter`'s options couldn't be read while there are no settings yet.
    private var optionsFailure: String?
    /// True while the selected printer's options load.
    private var loadingOptions = false
    private var settings: PrintSettings?
    /// The printer the Paper, Type and Tray menus were built for.
    private var menusPrinter: String?
    /// The Range field's text, kept while another Pages choice is selected.
    private var rangeText = ""
    /// True from Print until `lp` returns.
    private var sending = false
    /// Advances on every print, so a superseded job's polling stops updating the status.
    private var jobGeneration = 0

    private static let loadingReason = "Loading printers…"
    private static let unreachable = "Can't reach the print system"
    /// Shown before any settings exist for `Preflight` to judge; the same words it uses.
    private static let noPrinters = "No printers set up"
    static let noPDF = "No PDF open"
    private static let pollInterval: TimeInterval = 1
    private static let pollLimit: TimeInterval = 120

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
        center.addObserver(self, selector: #selector(refresh), name: .PDFViewPageChanged, object: window.pdfView)
        if let w = window.window {
            center.addObserver(self, selector: #selector(refresh), name: NSWindow.didBecomeKeyNotification, object: w)
        }
    }

    // MARK: Loading

    private func loadPrinters() {
        PrinterDirectory.shared.load { [weak self] in self?.printersLoaded($0) }
    }

    private func printersLoaded(_ result: Result<PrinterDirectory.Printers, Error>) {
        switch result {
        case .success(let loaded):
            printers = loaded.names
            descriptions = loaded.descriptions
            if let name = loaded.first {
                if let caps = loaded.caps {
                    use(name, caps)
                } else {
                    selectedPrinter = name
                    optionsFailure = cantRead(name)
                }
            }
        case .failure:
            printers = []
            loadFailure = Self.unreachable
        }
        render()
    }

    private func cantRead(_ printer: String) -> String { "Can't read \(descriptions[printer] ?? printer)'s options" }

    /// Moves the bar to `printer`: its defaults for a first printer, `switching(to:)` after that.
    private func use(_ printer: String, _ caps: PrinterCapabilities) {
        capabilities[printer] = caps
        settings = settings?.switching(to: printer, capabilities: caps) ?? .defaults(printer: printer, capabilities: caps)
        selectedPrinter = printer
        optionsFailure = nil
    }

    @objc private func printerChanged(_ sender: NSPopUpButton) {
        guard let name = sender.selectedItem?.representedObject as? String, name != selectedPrinter else { return }
        if let caps = capabilities[name] {
            use(name, caps)
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
                if let caps {
                    self.use(name, caps)
                } else if self.settings != nil {
                    // The bar stays on the printer it showed, which is still the one Print uses.
                    self.show(self.cantRead(name))
                } else {
                    self.selectedPrinter = name
                    self.optionsFailure = self.cantRead(name)
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

    /// Copies left empty or zero becomes 1, so the field and the stepper agree on what Print sends.
    func controlTextDidEndEditing(_ note: Notification) {
        guard note.object as? NSTextField === bar.copies, let copies = settings?.copies, copies < 1 else { return }
        settings?.copies = 1
        bar.copies.stringValue = "1"
        render()
    }

    @objc func refresh() { render() }

    // MARK: Printing

    private var selectedCapabilities: PrinterCapabilities? { settings.flatMap { capabilities[$0.printer] } }

    /// The document's PDF, which exists (locked or not) before the view shows it.
    private var pdf: PDFDocument? { document?.pdf }

    /// Why the setting controls are unavailable, or nil when there are settings to show.
    private var controlsBlocked: String? {
        guard let printers, !loadingOptions else { return Self.loadingReason }
        if printers.isEmpty { return loadFailure ?? Self.noPrinters }
        return settings == nil ? optionsFailure ?? Self.loadingReason : nil
    }

    /// Why Print is unavailable now, or nil when ⌘P and Print send the job.
    private var blockReason: String? {
        guard let url = document?.fileURL else { return Self.noPDF }
        if let controlsBlocked { return controlsBlocked }
        guard let printers, let settings, let pdf else { return Self.loadingReason }
        if pdf.isLocked { return "Unlock the PDF to print" }
        if sending { return "Sending…" }
        return Preflight.blockReason(settings: settings, printers: printers, pageCount: pdf.pageCount,
                                     fileExists: FileManager.default.fileExists(atPath: url.path),
                                     allowsPrinting: PDFFacts.allowsPrinting(pdf))
    }

    var canPrint: Bool { blockReason == nil }

    @objc private func printClicked(_ sender: Any?) { printFromBar() }

    /// Sends the job with exactly the bar's settings, then follows it in CUPS. A held ⌘P's key
    /// repeats are ignored, so holding it sends one job.
    func printFromBar() {
        if let event = NSApp.currentEvent, event.type == .keyDown, event.isARepeat { return }
        guard blockReason == nil, let settings, let pdf, let data = document?.data,
              let windowController else { return }
        let pageCount = pdf.pageCount
        let currentPage = windowController.currentPageIndex + 1
        let sent: JobState = settings.pages == .current
            ? .sentPage(currentPage) : .sent(pages: settings.pages.pageCount(of: pageCount) ?? 0)
        let landscape = PDFFacts.firstPageIsLandscape(pdf)
        let password = document?.password
        let title = document?.displayName ?? "roneo"
        jobGeneration += 1
        let generation = jobGeneration
        sending = true
        show("Sending…")
        render()
        let submitter = PrintSubmitter(emptyHome: PrinterDirectory.emptyHome)
        queue.async { [weak self] in
            let result = Result { () throws -> String in
                // The bytes the window parsed, so pages, landscape and preflight match what is
                // sent; PDFDocument isn't thread-safe, so the window's own is never touched here.
                let file = try PrintableFile.write(data, password: password, scratch: Scratch.app.directory)
                defer { try? FileManager.default.removeItem(at: file) }
                return try submitter.submit(JobBuilder.lpArguments(
                    settings: settings, file: file, title: title, currentPage: currentPage,
                    pageCount: pageCount, firstPageLandscape: landscape))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sending = false
                switch result {
                case .success(let id):
                    self.show(sent, generation: generation)
                    self.poll(id: id, printer: settings.printer, generation: generation)
                case .failure(let error as CommandTimedOut):
                    // lp may have queued the job before it stopped answering.
                    self.show("No answer from \(error.command); check the printer's queue before printing again")
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
                if stop || state?.isFinal == true { return }
            }
        }
    }

    private func show(_ state: JobState, generation: Int) {
        guard generation == jobGeneration else { return }
        show(state.text)
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
        let blocked = controlsBlocked

        let current = "Current (\((windowController?.currentPageIndex ?? 0) + 1))"
        if bar.pages.label(forSegment: 1) != current { bar.pages.setLabel(current, forSegment: 1) }

        renderPrinterPopup(blocked: blocked)
        if let blocked {
            for control in bar.settingControls where control !== bar.printer {
                control.isEnabled = false
                control.toolTip = blocked
            }
        }
        if blocked == nil, let settings, let caps {
            for control in bar.settingControls where control !== bar.printer {
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
            let media: [(NSPopUpButton, String, String?, String)] = [
                (bar.paper, "PageSize", settings.paper, "This printer has no paper size choice"),
                (bar.mediaType, "MediaType", settings.mediaType, "This printer has no paper type choice"),
                (bar.tray, "InputSlot", settings.tray, "This printer has no tray choice"),
            ]
            if menusPrinter != settings.printer {
                menusPrinter = settings.printer
                for (popup, key, _, _) in media { buildChoices(popup, caps.option(key)) }
            }
            for (popup, key, selected, missing) in media {
                if caps.option(key) == nil {
                    popup.isEnabled = false
                    popup.toolTip = missing
                } else if let selected {
                    popup.selectItem(at: popup.indexOfItem(withRepresentedObject: selected))
                }
            }
            renderColour(caps, selected: settings.colour)
        }

        let reason = blockReason
        bar.printButton.isEnabled = reason == nil
        bar.printButton.toolTip = reason ?? "Print with these settings (⌘P)"
    }

    /// Titles each queue with its description; the queue name rides in `representedObject`.
    private func renderPrinterPopup(blocked: String?) {
        let popup = bar.printer
        let names = printers ?? []
        if popup.itemArray.map({ $0.representedObject as? String }) != names.map(Optional.some) || names.isEmpty {
            popup.removeAllItems()
            if names.isEmpty {
                popup.addItem(withTitle: printers == nil ? Self.loadingReason : "No printers")
            }
            // Through the menu: `addItem(withTitle:)` drops a title already present.
            for name in names {
                let item = NSMenuItem(title: descriptions[name] ?? name, action: nil, keyEquivalent: "")
                item.representedObject = name
                popup.menu?.addItem(item)
            }
        }
        if let selectedPrinter { popup.selectItem(at: popup.indexOfItem(withRepresentedObject: selectedPrinter)) }
        popup.isEnabled = !names.isEmpty && !loadingOptions
        popup.toolTip = popup.isEnabled ? popup.titleOfSelectedItem : blocked
    }

    private func buildChoices(_ popup: NSPopUpButton, _ option: PrinterOption?) {
        popup.removeAllItems()
        guard let option else {
            popup.addItem(withTitle: "—")
            return
        }
        for choice in option.choices {
            let item = NSMenuItem(title: ChoiceLabel.display(choice), action: nil, keyEquivalent: "")
            item.representedObject = choice
            popup.menu?.addItem(item)
        }
    }

    private func renderColour(_ caps: PrinterCapabilities, selected: String?) {
        // A printer with one mode still shows it, since it is the one the job sends.
        bar.colour.selectedSegment = ColourChoices.isGrey(selected ?? "") ? 1 : 0
        guard caps.colourChoices == nil else { return }
        bar.colour.isEnabled = false
        if caps.option("ColorModel") == nil {
            bar.colour.toolTip = "This printer has no colour choice"
        } else {
            bar.colour.toolTip = ColourChoices.isGrey(selected ?? "")
                ? "This printer prints only in grey" : "This printer has no greyscale mode"
        }
    }
}
