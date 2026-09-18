import Foundation
import PDFKit

// usage: diag <pdf> <page> [paints] [lines] [free] [all]
@main struct Diag {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let p = Int(args[2])!
        let page = doc.page(at: p - 1)!
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(page.pageRef!)
        print("unsupported", g.unsupported, "invisible", g.hasInvisibleText, "paints", g.paints.count)
        var lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true,
            columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
        _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
        print("bounds", f(bounds), "body", LayoutReconstructor.bodySize(lines))
        if args.contains("paints") {
            for (i, paint) in g.paints.enumerated() {
                print(String(format: "paint %3d", i), paint.image ? "IMG" : "   ", paint.frame ? "F" : " ", paint.filled ? "fill" : "    ", f(paint.rect))
            }
        }
        if args.contains("lines") { for l in lines { print("   line", f(l.rect), String(format: "%.1f", l.fontSize), l.text.prefix(90)) } }
        print("regions:"); for r in g.regions { print("  ", f(r)) }
        let composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
        var content = PageContent(number: p, bounds: bounds, lines: lines, graphics: composed.graphics)
        content.tints = composed.tints; content.separators = composed.separators
        print("composed graphics:"); for r in composed.graphics { print("  ", f(r)) }
        print("tints:"); for r in composed.tints { print("  ", f(r)) }
        let crops = LayoutReconstructor.graphicsWithLabels(content)
        print("crops:")
        for c in crops {
            let taken = lines.filter { c.intersects($0.rect) }
            print("  ", f(c), "takes \(taken.count) lines, \(taken.reduce(0) { $0 + $1.text.split(separator: " ").count }) words")
            for l in taken.prefix(args.contains("all") ? 400 : 12) { print("      ", f(l.rect), String(format: "%.1f", l.fontSize), l.text.prefix(80)) }
        }
        if args.contains("block") {
            let bt = TintDetector.blockText(lines)
            for l in lines { print(bt.contains(where: { $0.rect == l.rect && $0.text == l.text }) ? "  BLOCK" : "  ·    ", f(l.rect), String(format: "%.1f", l.fontSize), l.text.prefix(60)) }
        }
        if args.contains("each") {
            for seed in composed.graphics {
                var one = PageContent(number: p, bounds: bounds, lines: lines, graphics: [seed])
                one.tints = composed.tints; one.separators = composed.separators
                let c = LayoutReconstructor.graphicsWithLabels(one)
                print("  seed", f(seed), "->", c.map(f).joined(separator: " "))
            }
        }
        let free = lines.filter { l in !crops.contains { $0.intersects(l.rect) } }
        if args.contains("free") { for l in free { print("   free", f(l.rect), String(format: "%.1f", l.fontSize), l.text.prefix(70)) } }
        print("comesApart", PDFReflowLibPipeline.layoutComesApart(content, graphics: g))
        print("free lines \(free.count), words \(free.reduce(0) { $0 + $1.text.split(separator: " ").count }) of \(lines.reduce(0) { $0 + $1.text.split(separator: " ").count })")
    }
}
