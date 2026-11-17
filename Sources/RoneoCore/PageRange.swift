import Foundation

public enum PageRange {
    /// Canonical CUPS `page-ranges` text (`N`, `N-M`, comma-separated, no spaces) for a 1-based
    /// selection, or nil when empty, non-numeric, zero, reversed or past `pageCount`.
    public static func normalize(_ text: String, pageCount: Int) -> String? {
        var parts: [String] = []
        for raw in text.split(separator: ",", omittingEmptySubsequences: false) {
            let item = raw.filter { !$0.isWhitespace }
            let bounds = item.split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count <= 2, let first = page(bounds.first, pageCount) else { return nil }
            if bounds.count == 2 {
                guard let last = page(bounds[1], pageCount), first <= last else { return nil }
                parts.append("\(first)-\(last)")
            } else {
                parts.append("\(first)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ",")
    }

    private static func page(_ s: Substring?, _ pageCount: Int) -> Int? {
        guard let s, !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = Int(s), n >= 1, n <= pageCount else { return nil }
        return n
    }
}
