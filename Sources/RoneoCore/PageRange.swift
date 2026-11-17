import Foundation

public enum PageRange {
    /// Canonical CUPS `page-ranges` text (`N`, `N-M`, comma-separated, no spaces, ascending, merged)
    /// for a 1-based selection, or nil when empty, non-numeric, zero, reversed or past `pageCount`.
    /// Spaces are allowed around a number, never inside one.
    public static func normalize(_ text: String, pageCount: Int) -> String? {
        ranges(text, pageCount: pageCount)?
            .map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: ",")
    }

    /// The selection as ascending, non-overlapping, non-adjacent ranges; nil when `normalize` is.
    static func ranges(_ text: String, pageCount: Int) -> [ClosedRange<Int>]? {
        var parts: [ClosedRange<Int>] = []
        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = item.split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count <= 2, let first = page(bounds[0], pageCount) else { return nil }
            if bounds.count == 2 {
                guard let last = page(bounds[1], pageCount), first <= last else { return nil }
                parts.append(first...last)
            } else {
                parts.append(first...first)
            }
        }
        var merged: [ClosedRange<Int>] = []
        for part in parts.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, part.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, part.upperBound)
            } else {
                merged.append(part)
            }
        }
        return merged
    }

    private static func page(_ s: Substring, _ pageCount: Int) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = Int(t), n >= 1, n <= pageCount else { return nil }
        return n
    }
}
