import Foundation

public enum Preflight {
    /// The reason for an empty printer list, here and in the bar before any settings exist.
    public static let noPrinters = "No printers set up"

    /// Why Print is unavailable, or nil when the job can be sent. The first applicable reason wins.
    public static func blockReason(settings: PrintSettings, printers: [String], pageCount: Int,
                                   fileExists: Bool, allowsPrinting: Bool) -> String? {
        if printers.isEmpty { return noPrinters }
        if !allowsPrinting { return "This PDF doesn't allow printing" }
        if !fileExists { return "The file is no longer where it was opened from" }
        if case .range(let text) = settings.pages, PageRange.normalize(text, pageCount: pageCount) == nil {
            return "Pages: enter a range like 1-3, 5"
        }
        if settings.copies < 1 { return "Copies must be 1 or more" }
        return nil
    }
}
