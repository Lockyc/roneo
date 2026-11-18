import PropertyBased
import Testing
@testable import RoneoCore

/// Generated page-range text, checked against the contract CUPS enforces on `page-ranges` and the
/// page count the bar shows. Each run draws fresh inputs; a failure prints the seed that
/// reproduces it.
struct PageRangePropertyTests {
    /// One comma-separated item: a start placed anywhere in 0...pageCount+2 (as a fraction of that
    /// span), a length that may be negative (a reversed range), whether a one-page item is written
    /// as a bare number, and the spaces around each number.
    struct Item: CustomStringConvertible {
        var start: Int
        var length: Int
        var bare: Bool
        var pads: [Int]

        func bounds(pageCount: Int) -> (Int, Int) {
            let first = start * (pageCount + 3) / 1001
            return (first, first + length)
        }

        func text(pageCount: Int) -> String {
            let (a, b) = bounds(pageCount: pageCount)
            let pad = pads.map { String(repeating: " ", count: $0) }
            if a == b, bare { return pad[0] + "\(a)" + pad[1] }
            return pad[0] + "\(a)" + pad[1] + "-" + pad[2] + "\(b)" + pad[3]
        }

        var description: String { "Item(start: \(start), length: \(length), bare: \(bare), pads: \(pads))" }
    }

    struct Input: CustomStringConvertible {
        var pageCount: Int
        var items: [Item]

        var text: String { items.map { $0.text(pageCount: pageCount) }.joined(separator: ",") }
        var isValid: Bool {
            items.allSatisfy {
                let (a, b) = $0.bounds(pageCount: pageCount)
                return 1 <= a && a <= b && b <= pageCount
            }
        }
        /// The pages the text names, when it is valid.
        var pages: Set<Int> {
            Set(items.flatMap { item -> ClosedRange<Int> in
                let (a, b) = item.bounds(pageCount: pageCount)
                return a...b
            })
        }

        var description: String { "pageCount \(pageCount), text \"\(text)\"" }
    }

    static let item = zip(Gen.int(in: 0...1000), Gen.int(in: -1...6), Gen.bool, Gen.int(in: 0...2).array(of: 4))
        .map { Item(start: $0, length: $1, bare: $2, pads: $3) }
    static let input = zip(Gen.int(in: 1...150), item.array(of: 1...6))
        .map { Input(pageCount: $0, items: $1) }

    private static func pages(of normalized: String) -> [ClosedRange<Int>] {
        normalized.split(separator: ",").map { part in
            let bounds = part.split(separator: "-").map { Int($0)! }
            return bounds[0]...bounds[bounds.count - 1]
        }
    }

    /// What CUPS accepts: ascending, non-overlapping ranges within the document, no spaces; and
    /// adjacent ranges merged, so the text is canonical. Text naming any page outside the document,
    /// or a reversed range, is refused.
    @Test func normalizedTextIsAscendingMergedAndInBounds() async {
        await propertyCheck(count: 500, input: Self.input) { input in
            let result = PageRange.normalize(input.text, pageCount: input.pageCount)
            #expect((result != nil) == input.isValid)
            guard let result else { return }
            #expect(!result.contains(" "))
            let ranges = Self.pages(of: result)
            for range in ranges { #expect(range.lowerBound >= 1 && range.upperBound <= input.pageCount) }
            for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound + 1 < b.lowerBound) }
        }
    }

    @Test func normalizingIsIdempotent() async {
        await propertyCheck(count: 500, input: Self.input) { input in
            guard let once = PageRange.normalize(input.text, pageCount: input.pageCount) else { return }
            #expect(PageRange.normalize(once, pageCount: input.pageCount) == once)
        }
    }

    /// The normalized text names exactly the pages the input does, and the bar counts each once.
    @Test func countIsTheNumberOfDistinctPagesNamed() async {
        await propertyCheck(count: 500, input: Self.input) { input in
            guard input.isValid else { return }
            #expect(PageSelection.range(input.text).pageCount(of: input.pageCount) == input.pages.count)
            let normalized = PageRange.normalize(input.text, pageCount: input.pageCount)!
            #expect(Set(Self.pages(of: normalized).flatMap { $0 }) == input.pages)
        }
    }

    /// Spaces may surround a number but never split one: "1 2" is not page 12.
    @Test func aSpaceInsideANumberIsRefused() async {
        await propertyCheck(count: 500, input: zip(Self.input, Gen.int(in: 0...1000))) { input, pick in
            let text = input.text
            let splits = text.indices.filter { i in
                let next = text.index(after: i)
                return next < text.endIndex && text[i].isNumber && text[next].isNumber
            }
            guard !splits.isEmpty else { return }
            var broken = text
            broken.insert(" ", at: text.index(after: splits[pick % splits.count]))
            #expect(PageRange.normalize(broken, pageCount: input.pageCount) == nil, "\(broken)")
        }
    }
}
