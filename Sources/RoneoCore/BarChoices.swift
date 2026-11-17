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
}

extension PrinterCapabilities {
    /// Grey is the first `ColorModel` choice containing "Gray" or "Grey"; Colour is the default
    /// when it isn't grey, else the first non-grey choice. Nil when the printer has no
    /// `ColorModel`, or it lacks a grey or a non-grey choice.
    public var colourChoices: ColourChoices? {
        guard let option = option("ColorModel") else { return nil }
        func isGrey(_ c: String) -> Bool { c.localizedCaseInsensitiveContains("gray") || c.localizedCaseInsensitiveContains("grey") }
        guard let grey = option.choices.first(where: isGrey) else { return nil }
        let colour = option.defaultChoice.flatMap { isGrey($0) ? nil : $0 } ?? option.choices.first { !isGrey($0) }
        return colour.map { ColourChoices(colour: $0, grey: grey) }
    }
}

extension PageSelection {
    /// Pages in one copy of the job: every page, one, or those the range names (repeats counted);
    /// nil when the range doesn't normalise.
    public func pageCount(of documentPages: Int) -> Int? {
        switch self {
        case .all: return documentPages
        case .current: return 1
        case .range(let text):
            guard let normal = PageRange.normalize(text, pageCount: documentPages) else { return nil }
            return normal.split(separator: ",").reduce(0) { total, part in
                let bounds = part.split(separator: "-").compactMap { Int($0) }
                return total + (bounds.count == 2 ? bounds[1] - bounds[0] + 1 : 1)
            }
        }
    }
}
