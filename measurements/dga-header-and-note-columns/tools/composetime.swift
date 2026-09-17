import Foundation
import PDFKit

// usage: composetime <pdf> <page>...   -> paints, images, compose ms (best of 5)
@main struct ComposeTime {
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        for p in args.dropFirst(2).compactMap({ Int($0) }) {
            let page = doc.page(at: p - 1)!
            let bounds = page.bounds(for: .cropBox)
            let g = GraphicsReader.read(page.pageRef!)
            let lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
            var best = Double.infinity
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
                best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            print("\(p)\tpaints \(g.paints.count)\timages \(g.paints.filter(\.image).count)\tlines \(lines.count)\tcompose \(String(format: "%.1f", best)) ms")
        }
    }
}
