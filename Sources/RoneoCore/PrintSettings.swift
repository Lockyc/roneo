import Foundation

public enum Scale: Equatable, Sendable { case actual, fit }

public enum PageSelection: Equatable, Sendable {
    case all, current, range(String)
}

/// Everything the print bar chooses for one job. Media fields hold PPD choice values and are
/// nil when the printer does not offer that option.
public struct PrintSettings: Equatable, Sendable {
    public var printer: String
    public var sides: Sides
    public var scale: Scale
    public var pages: PageSelection
    public var copies: Int
    /// PPD `PageSize`.
    public var paper: String?
    /// PPD `MediaType`.
    public var mediaType: String?
    /// PPD `InputSlot`.
    public var tray: String?
    /// PPD `ColorModel`.
    public var colour: String?

    public init(printer: String, sides: Sides, scale: Scale, pages: PageSelection, copies: Int,
                paper: String?, mediaType: String?, tray: String?, colour: String?) {
        self.printer = printer
        self.sides = sides
        self.scale = scale
        self.pages = pages
        self.copies = copies
        self.paper = paper
        self.mediaType = mediaType
        self.tray = tray
        self.colour = colour
    }

    /// The fixed starting point for a window: the printer's own defaults, 100% scale, all pages.
    public static func defaults(printer: String, capabilities: PrinterCapabilities) -> PrintSettings {
        PrintSettings(printer: printer, sides: capabilities.defaultSides, scale: .actual, pages: .all, copies: 1,
                      paper: capabilities.option("PageSize")?.defaultChoice,
                      mediaType: capabilities.option("MediaType")?.defaultChoice,
                      tray: capabilities.option("InputSlot")?.defaultChoice,
                      colour: capabilities.option("ColorModel")?.defaultChoice)
    }

    /// Moves to another printer: media fields take that printer's defaults, the rest carries
    /// over, and sides falls back to single when the printer cannot duplex.
    public func switching(to printer: String, capabilities: PrinterCapabilities) -> PrintSettings {
        var s = PrintSettings.defaults(printer: printer, capabilities: capabilities)
        s.sides = capabilities.supportsDuplex ? sides : .single
        s.scale = scale
        s.pages = pages
        s.copies = copies
        return s
    }
}
