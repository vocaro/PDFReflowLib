import Foundation
import PDFKit

// usage: paintcount <pdf> -> top 8 pages by paint count, with candidate counts and compose time
@main struct PaintCount {
    static func main() throws {
        let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
        var rows: [(page: Int, paints: Int, candidates: Int, thin: Int)] = []
        for p in 0..<doc.pageCount {
            autoreleasepool {
                let g = GraphicsReader.read(doc.page(at: p)!.pageRef!)
                let candidates = g.paints.filter { !$0.image && !$0.frame && !TintDetector.isThin($0.rect) }.count
                let thin = g.paints.filter { TintDetector.isThin($0.rect) }.count
                rows.append((p + 1, g.paints.count, candidates, thin))
            }
        }
        rows.sort { $0.paints > $1.paints }
        print("pages \(doc.pageCount) max paints \(rows.first?.paints ?? 0)")
        for r in rows.prefix(8) {
            var line = "page \(r.page) paints \(r.paints) candidates \(r.candidates) thin \(r.thin)"
            autoreleasepool {
                let page = doc.page(at: r.page - 1)!
                let g = GraphicsReader.read(page.pageRef!)
                let lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000)) ?? []
                let start = Date()
                let composed = TintDetector.compose(g.paints, lines: lines, bounds: page.bounds(for: .cropBox))
                line += String(format: " lines %d compose %.3fs graphics %d", lines.count, Date().timeIntervalSince(start), composed.graphics.count)
            }
            print(line)
        }
    }
}
