import Foundation
import PDFKit

// usage: ulsurvey <pdf>: pages where TableRegionDetector.underlinedColumnRegions finds a region,
// with the words it holds and how many of its lines are the page's block text (#158's blockText).
@main struct ULSurvey {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        for p in 1...doc.pageCount {
            autoreleasepool {
                guard let page = doc.page(at: p - 1), let ref = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let g = GraphicsReader.read(ref)
                if g.unsupported || page.rotation % 360 != 0 { return }
                guard var lines = try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                    columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect)) else { return }
                _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
                let composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
                var content = PageContent(number: p, bounds: bounds, lines: lines, graphics: composed.graphics)
                content.tints = composed.tints; content.separators = composed.separators
                let regions = TableRegionDetector.underlinedColumnRegions(in: content)
                guard !regions.isEmpty else { return }
                let text = TintDetector.blockText(lines)
                for r in regions {
                    let held = lines.filter { r.intersects($0.rect) }
                    let block = held.filter { l in text.contains { $0.rect == l.rect && $0.text == l.text } }
                    let words = held.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
                    print("\(p)\t\(f(r))\tlines=\(held.count)\tblock=\(block.count)\twords=\(words)\t\(held.prefix(3).map { $0.text.prefix(30) })")
                }
            }
        }
    }
}
