// Writes the test PDFs the viewer and print bar are checked against.
// Usage: swift scripts/fixtures.swift <out-dir> [long-page-count]
import CoreGraphics
import CoreText
import Foundation

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "build/fixtures", isDirectory: true)
let longPages = args.count > 2 ? Int(args[2]) ?? 600 : 600
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let mm = 72.0 / 25.4
let a4 = CGRect(x: 0, y: 0, width: 210 * mm, height: 297 * mm)
let a4Landscape = CGRect(x: 0, y: 0, width: a4.height, height: a4.width)

/// Draws `text` centred horizontally at baseline `y`.
func draw(_ text: String, size: CGFloat, centredIn box: CGRect, y: CGFloat, in ctx: CGContext) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: box.midX - width / 2, y: y)
    CTLineDraw(line, ctx)
}

/// Writes a PDF of `count` pages of `box` to `name`, calling `page` to draw each.
func write(_ name: String, box: CGRect, count: Int, info: [CFString: Any] = [:],
           page: (Int, CGContext) -> Void) {
    var media = box
    let url = out.appendingPathComponent(name) as CFURL
    guard let ctx = CGContext(url, mediaBox: &media, info as CFDictionary) else {
        fatalError("can't create \(name)")
    }
    for index in 0..<count {
        ctx.beginPDFPage(nil)
        page(index, ctx)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    print("wrote \(out.appendingPathComponent(name).path)")
}

func numbered(_ index: Int, _ count: Int, box: CGRect, _ ctx: CGContext) {
    draw("\(index + 1)", size: 220, centredIn: box, y: box.midY - 70, in: ctx)
    draw("of \(count)", size: 36, centredIn: box, y: box.midY - 140, in: ctx)
}

write("long.pdf", box: a4, count: longPages) { numbered($0, longPages, box: a4, $1) }
write("two-page.pdf", box: a4, count: 2) { numbered($0, 2, box: a4, $1) }
write("landscape.pdf", box: a4Landscape, count: 1) { numbered($0, 1, box: a4Landscape, $1) }
write("locked.pdf", box: a4, count: 1, info: [
    kCGPDFContextUserPassword: "roneo", kCGPDFContextOwnerPassword: "roneo",
]) { numbered($0, 1, box: a4, $1) }

// A 3×7 label grid inside 10 mm margins, plus a 50 mm square to check 100% scale with a ruler.
write("label-sheet.pdf", box: a4, count: 1) { _, ctx in
    let margin = 10 * mm
    let grid = a4.insetBy(dx: margin, dy: margin)
    let w = grid.width / 3, h = grid.height / 7
    ctx.setLineWidth(0.5)
    for row in 0..<7 {
        for col in 0..<3 {
            let cell = CGRect(x: grid.minX + CGFloat(col) * w, y: grid.minY + CGFloat(row) * h, width: w, height: h)
            ctx.stroke(cell)
            draw("\(row * 3 + col + 1)", size: 14, centredIn: cell, y: cell.midY - 5, in: ctx)
        }
    }
    let square = CGRect(x: a4.midX - 25 * mm, y: a4.midY - 25 * mm, width: 50 * mm, height: 50 * mm)
    ctx.setLineWidth(1)
    ctx.stroke(square)
    // Just inside the square's top edge: its centre is label 11's cell.
    draw("50 mm", size: 12, centredIn: square, y: square.maxY - 4 * mm, in: ctx)
}
