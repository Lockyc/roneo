import Foundation

/// One window's print bar as data: the printer list, which printer the popup shows, the settings
/// Print sends, and why the controls or Print are unavailable. The controller feeds it events and
/// renders it; every decision about which printer the bar is on lives here.
public struct BarState: Sendable {
    /// What the printer directory read: queue names, their descriptions, the printer a new bar
    /// starts on and that printer's options (nil when they couldn't be read).
    public struct Printers: Sendable {
        public let names: [String]
        public let descriptions: [String: String]
        public let first: String?
        public let caps: PrinterCapabilities?

        public init(names: [String], descriptions: [String: String], first: String?, caps: PrinterCapabilities?) {
            self.names = names
            self.descriptions = descriptions
            self.first = first
            self.caps = caps
        }
    }

    /// The document as Print sees it. `pdf` is nil while the file is still being read.
    public struct Document: Sendable {
        public var pdf: PDF?
        public var fileExists: Bool

        public struct PDF: Sendable {
            public var pageCount: Int
            public var isLocked: Bool
            public var allowsPrinting: Bool

            public init(pageCount: Int, isLocked: Bool, allowsPrinting: Bool) {
                self.pageCount = pageCount
                self.isLocked = isLocked
                self.allowsPrinting = allowsPrinting
            }
        }

        public init(pdf: PDF?, fileExists: Bool) {
            self.pdf = pdf
            self.fileExists = fileExists
        }
    }

    /// What choosing a printer needs from the caller.
    public enum Choice: Equatable, Sendable {
        /// Nothing changed, or the bar moved to a printer whose options it already had.
        case done
        /// Read this printer's options and deliver them with `optionsLoaded`.
        case loadOptions(String)
    }

    public static let loadingReason = "Loading printers…"
    public static let unreachable = "Can't reach the print system"
    public static let noPDF = "No PDF open"
    public static let locked = "Unlock the PDF to print"
    public static let sendingReason = "Sending…"

    /// Queue names; nil while the list is loading.
    public private(set) var printers: [String]?
    /// Each queue's description, the name the popup shows.
    public private(set) var descriptions: [String: String] = [:]
    /// Why the printer list couldn't be read; blocks Print.
    public private(set) var loadFailure: String?
    public private(set) var capabilities: [String: PrinterCapabilities] = [:]
    /// The queue the popup shows; `settings.printer` whenever there are settings.
    public private(set) var selectedPrinter: String?
    /// Why `selectedPrinter`'s options couldn't be read while there are no settings yet.
    public private(set) var optionsFailure: String?
    /// True while the chosen printer's options load.
    public private(set) var loadingOptions = false
    /// What Print sends. The controls edit its fields; `choose` and `optionsLoaded` change its printer.
    public var settings: PrintSettings?
    /// True from Print until `lp` returns.
    public var sending = false

    public init() {}

    public var selectedCapabilities: PrinterCapabilities? { settings.flatMap { capabilities[$0.printer] } }

    public mutating func printersLoaded(_ result: Result<Printers, Error>) {
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
    }

    /// The popup chose `printer`.
    public mutating func choose(_ printer: String) -> Choice {
        guard printer != selectedPrinter else { return .done }
        if let caps = capabilities[printer] {
            use(printer, caps)
            return .done
        }
        loadingOptions = true
        return .loadOptions(printer)
    }

    /// `printer`'s options arrived, or couldn't be read (nil). Returns a status line to show, if any.
    @discardableResult
    public mutating func optionsLoaded(_ printer: String, _ caps: PrinterCapabilities?) -> String? {
        loadingOptions = false
        if let caps {
            use(printer, caps)
            return nil
        }
        if settings != nil {
            // The bar stays on the printer it showed, which is still the one Print uses.
            return cantRead(printer)
        }
        selectedPrinter = printer
        optionsFailure = cantRead(printer)
        return nil
    }

    /// Why the setting controls are unavailable, or nil when there are settings to show.
    public var controlsBlocked: String? {
        guard let printers, !loadingOptions else { return Self.loadingReason }
        if printers.isEmpty { return loadFailure ?? Preflight.noPrinters }
        return settings == nil ? optionsFailure ?? Self.loadingReason : nil
    }

    /// Why Print is unavailable now, or nil when Print sends the job. `document` is nil when the
    /// window has no file.
    public func blockReason(document: Document?) -> String? {
        guard let document else { return Self.noPDF }
        if let controlsBlocked { return controlsBlocked }
        guard let printers, let settings, let pdf = document.pdf else { return Self.loadingReason }
        if pdf.isLocked { return Self.locked }
        if sending { return Self.sendingReason }
        return Preflight.blockReason(settings: settings, printers: printers, pageCount: pdf.pageCount,
                                     fileExists: document.fileExists, allowsPrinting: pdf.allowsPrinting)
    }

    private func cantRead(_ printer: String) -> String { "Can't read \(descriptions[printer] ?? printer)'s options" }

    /// Moves the bar to `printer`: its defaults for a first printer, `switching(to:)` after that.
    private mutating func use(_ printer: String, _ caps: PrinterCapabilities) {
        capabilities[printer] = caps
        settings = settings?.switching(to: printer, capabilities: caps) ?? .defaults(printer: printer, capabilities: caps)
        selectedPrinter = printer
        optionsFailure = nil
    }
}
