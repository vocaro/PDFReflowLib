import Foundation
import PDFKit

// usage: imgdiag <pdf> <page>: per image paint, the lines meeting/inside it and the prose count.
@main struct ImgDiag {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let p = Int(args[2])!
        let page = doc.page(at: p - 1)!
        let g = GraphicsReader.read(page.pageRef!)
        var lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true,
            columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
        _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
        let body = max(4, LayoutReconstructor.bodySize(lines))
        print("body", body)
        for paint in g.paints where paint.image {
            let rect = paint.rect
            let meeting = lines.filter { $0.rect.intersects(rect) }
            let inside = meeting.filter { l in let o = l.rect.intersection(rect); return !o.isNull && o.width * o.height >= l.rect.width * l.rect.height * 0.5 }
            let prose = inside.filter { !$0.monospaced && $0.fontSize >= body * 0.9 && $0.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4 }
            print("image", f(rect), "meeting", meeting.count, "inside", inside.count, "prose", prose.count, "zone", f(union(inside.map(\.rect))))
            for l in inside.prefix(8) { print("    in", f(l.rect), l.fontSize, l.text.prefix(60)) }
        }
        let after = TintDetector.withoutTextBackdrops(g.paints, lines: lines)
        for paint in after where paint.image { print("after image", f(paint.rect)) }
    }
}
