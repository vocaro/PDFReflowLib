import Foundation
import PDFKit

// usage: diag <pdf> <page> [paints]
@main struct Diag {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let p = Int(args[2])!
        let page = doc.page(at: p - 1)!
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(page.pageRef!)
        var lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true,
            columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
        let index = try StructureTreeReader.read(URL(fileURLWithPath: args[1])); if let tags = index.pages[p], !tags.isEmpty { let ok = StructureTreeReader.validates(tags, owners: index.owners[p] ?? [:], page: page.pageRef!) && MarkedTextReader.apply(tags, page: page.pageRef!, lines: &lines); print("tags applied", ok) }
        _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
        print("bounds", f(bounds))
        if args.count > 3 {
            for (i, paint) in g.paints.enumerated() {
                let img = paint.image ? "IMG" : "   "
                print(String(format: "paint %3d", i), img, paint.frame ? "F" : " ", f(paint.rect))
            }
        }
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
            for l in taken.prefix(40) { print("      ", f(l.rect), String(format: "%.1f", l.fontSize), l.text.prefix(80)) }
        }
        let free = lines.filter { l in !crops.contains { $0.intersects(l.rect) } }
        if args.contains("lines") { for l in free { print("   free", f(l.rect), String(format: "%.1f", l.fontSize), l.structure.map { "\($0)" } ?? "-", l.text.prefix(70)) } }
        if args.contains("blocks") { var w: [ConversionWarning] = []; content.lines.removeAll { $0.rect.maxY < 60 }; let regions = LayoutReconstructor.graphicsWithLabels(content).enumerated().map { ($0.element, "image-\($0.offset)") }; for (r, n) in regions { print("  region", n, f(r)) }; for b in LayoutReconstructor.blocks(page: content, images: regions, vocabulary: [], warnings: &w) { print("  block", b.text.prefix(80), b.content) } }
        print("free lines \(free.count), words \(free.reduce(0) { $0 + $1.text.split(separator: " ").count })")
    }
}
