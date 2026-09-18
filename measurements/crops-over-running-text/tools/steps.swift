import Foundation
import PDFKit

// usage: steps <pdf> <page>: paints after each compose step.
@main struct Steps {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func show(_ label: String, _ paints: [GraphicsReader.Paint]) {
        print(label, paints.count)
        for p in paints.prefix(60) { print("   ", p.image ? "IMG" : "   ", p.frame ? "F" : " ", p.filled ? "fill" : "    ", f(p.rect)) }
    }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let p = Int(args[2])!
        let page = doc.page(at: p - 1)!
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(page.pageRef!)
        var lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true,
            columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
        _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
        let a = TintDetector.withoutTextBackdrops(g.paints, lines: lines)
        show("backdrops", a)
        let b = TintDetector.withoutTitleBackdrops(a, lines: lines)
        show("titles", b)
        show("titles on original", TintDetector.withoutTitleBackdrops(g.paints, lines: lines))
        let running = TintDetector.blockText(lines)
        print("blockText lines: \(running.count)")
        for l in running.prefix(40) { print("    blk", f(l.rect), String(format: "%.1f", l.fontSize), l.text.prefix(50)) }
        let r = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
        print("graphics"); for x in r.graphics { print("   ", f(x)) }
        print("tints"); for x in r.tints { print("   ", f(x)) }
    }
}
