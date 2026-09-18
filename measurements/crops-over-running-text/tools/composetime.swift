import Foundation
import PDFKit

// usage: composetime <pdf> <page> [rounds]
// Best of `rounds` (default 5) for TintDetector.compose and LayoutReconstructor.graphicsWithLabels.
@main struct ComposeTime {
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let p = Int(args[2])!
        let rounds = args.count > 3 ? Int(args[3])! : 5
        let page = doc.page(at: p - 1)!
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(page.pageRef!)
        var lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
            columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
        _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
        var compose = Double.infinity, crops = Double.infinity
        var composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
        for _ in 0..<rounds {
            var start = Date()
            composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
            compose = min(compose, -start.timeIntervalSinceNow)
            var content = PageContent(number: p, bounds: bounds, lines: lines, graphics: composed.graphics)
            content.tints = composed.tints; content.separators = composed.separators
            start = Date()
            _ = LayoutReconstructor.graphicsWithLabels(content)
            crops = min(crops, -start.timeIntervalSinceNow)
        }
        print(String(format: "page %d paints %d lines %d compose %.1f ms crops %.1f ms",
                     p, g.paints.count, lines.count, compose * 1000, crops * 1000))
    }
}
