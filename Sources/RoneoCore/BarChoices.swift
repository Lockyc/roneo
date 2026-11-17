import Foundation

public enum ChoiceLabel {
    /// Display text for a PPD choice keyword: a leading reverse-DNS vendor part (`com.`) dropped,
    /// hyphens and underscores as spaces, the first letter capitalised. Display only; settings keep
    /// the raw keyword.
    public static func display(_ keyword: String) -> String {
        var text = Substring(keyword)
        if let dot = text.firstIndex(of: "."), dot != text.startIndex {
            let head = text[..<dot]
            if head.count <= 3, head.allSatisfy({ $0.isASCII && $0.isLowercase }) { text = text[text.index(after: dot)...] }
        }
        let spaced = text.map { $0 == "-" || $0 == "_" ? " " : String($0) }.joined()
        guard let first = spaced.first else { return keyword }
        return first.uppercased() + spaced.dropFirst()
    }
}

/// The two `ColorModel` choices behind the bar's Colour and Grey segments.
public struct ColourChoices: Equatable, Sendable {
    public let colour: String
    public let grey: String

    /// True for a greyscale `ColorModel` choice: one containing "Gray", "Grey", "Black" or "Mono"
    /// in any case (`Gray`, `KGray`, `Black`, `Monochrome`).
    public static func isGrey(_ choice: String) -> Bool {
        ["gray", "grey", "black", "mono"].contains { choice.localizedCaseInsensitiveContains($0) }
    }
}

extension PrinterCapabilities {
    /// Grey is the first grey `ColorModel` choice; Colour is the default when it isn't grey, else
    /// the first non-grey choice. Nil when the printer has no `ColorModel`, or it lacks a grey or a
    /// non-grey choice.
    public var colourChoices: ColourChoices? {
        guard let option = option("ColorModel") else { return nil }
        let isGrey = ColourChoices.isGrey
        guard let grey = option.choices.first(where: isGrey) else { return nil }
        let colour = option.defaultChoice.flatMap { isGrey($0) ? nil : $0 } ?? option.choices.first { !isGrey($0) }
        return colour.map { ColourChoices(colour: $0, grey: grey) }
    }
}

extension PageSelection {
    /// Distinct pages in one copy of the job: every page, one, or those the range names; nil when
    /// the range doesn't normalise.
    public func pageCount(of documentPages: Int) -> Int? {
        switch self {
        case .all: return documentPages
        case .current: return 1
        case .range(let text):
            guard let normal = PageRange.normalize(text, pageCount: documentPages) else { return nil }
            var pages = Set<Int>()
            for part in normal.split(separator: ",") {
                let bounds = part.split(separator: "-").compactMap { Int($0) }
                guard let first = bounds.first, let last = bounds.last, first <= last else { return nil }
                pages.formUnion(first...last)
            }
            return pages.count
        }
    }
}
