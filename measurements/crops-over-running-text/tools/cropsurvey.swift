import Foundation
import PDFKit

// usage: cropsurvey <pdf> [first last]
// One block per page: page, flags, composed crops (graphicsWithLabels) and the lines each takes;
// a totals line per page with words taken. Mirrors extractPage's graphics steps (no tags, no
// page-sized clearing: a superset), plus whether layoutComesApart holds.
@main struct CropSurvey {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let first = args.count > 3 ? Int(args[2])! : 1
        let last = args.count > 3 ? Int(args[3])! : doc.pageCount
        for p in first...last {
            autoreleasepool {
                guard let page = doc.page(at: p - 1), let ref = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let g = GraphicsReader.read(ref)
                if g.unsupported || page.rotation % 360 != 0 { print("\(p)\tunsupported"); return }
                let synthetic = g.hasOnlyInvisibleText && g.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 }
                if synthetic { print("\(p)\tsynthetic"); return }
                guard var lines = try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                    columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect)) else { print("\(p)\tnolines"); return }
                _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
                let composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
                var content = PageContent(number: p, bounds: bounds, lines: lines, graphics: composed.graphics)
                content.tints = composed.tints; content.separators = composed.separators
                let crops = LayoutReconstructor.graphicsWithLabels(content)
                let area = bounds.width * bounds.height
                let pageSized = g.regions.contains { $0.width * $0.height > area * 0.75 }
                let apart = pageSized ? PDFReflowLibPipeline.layoutComesApart(content, graphics: g) : true
                func words(_ ls: [TextLine]) -> Int { ls.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
                let taken = lines.filter { l in crops.contains { $0.intersects(l.rect) } }
                var out = "\(p)\tpageSized=\(pageSized) apart=\(apart)\tcrops=\(crops.count)\ttaken=\(words(taken))/\(words(lines))\ttints=\(composed.tints.count)"
                for c in crops {
                    let t = lines.filter { c.intersects($0.rect) }
                    out += "\n  \(f(c)) \(words(t))w " + t.prefix(60).map { "\"\($0.text.prefix(40))\"" }.joined(separator: " ")
                }
                print(out)
            }
        }
    }
}
