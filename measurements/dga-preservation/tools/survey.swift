import Foundation
import PDFKit

// usage: survey <pdf> [first last] -> one TSV line per page with a >75% region and native lines
@main struct Survey {
    static func main() {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let first = args.count > 3 ? Int(args[2])! : 1
        let last = args.count > 3 ? Int(args[3])! : doc.pageCount
        print("page\tlines\tinvis\tonlyInvis\tunsup\tregionFrac\tnPaints\tbyKind(path/img/form/sh)\tmaxSingle\tmaxSingleKind\tmaxImg\tmaxPathFrame\timgUnion")
        var n = 0
        for p in first...last {
            autoreleasepool {
                let page = doc.page(at: p - 1)!
                let bounds = page.bounds(for: .cropBox)
                let area = bounds.width * bounds.height
                let g = GraphicsReader.read(page.pageRef!)
                guard let region = g.regions.filter({ $0.width * $0.height > area * 0.75 }).first else { return }
                let lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)) ?? []
                guard !lines.isEmpty else { return }
                n += 1
                let inside = g.paints.filter { region.insetBy(dx: -0.5, dy: -0.5).contains($0.rect) }
                var counts = [0, 0, 0, 0]
                for q in inside { counts[Int(q.kind)] += 1 }
                let best = inside.max { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
                let frac = { (r: CGRect) in r.width * r.height / area }
                let maxImg = inside.filter { $0.kind == 1 }.map { frac($0.rect) }.max() ?? 0
                let maxPath = inside.filter { $0.kind == 0 }.map { frac($0.rect) }.max() ?? 0
                // coarse union of image paints on a 4pt grid
                var grid = Set<Int>()
                let cols = Int(bounds.width / 4) + 1
                for q in inside where q.kind == 1 {
                    let r = q.rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
                    for y in stride(from: Int(r.minY / 4), to: Int(r.maxY / 4), by: 1) {
                        for x in stride(from: Int(r.minX / 4), to: Int(r.maxX / 4), by: 1) { grid.insert(y * cols + x) }
                    }
                }
                let union = Double(grid.count * 16) / Double(area); let imgSum = inside.filter { $0.kind == 1 }.map { frac($0.rect) }.reduce(0, +)
                print("\(p)\t\(lines.count)\t\(g.hasInvisibleText)\t\(g.hasOnlyInvisibleText)\t\(g.unsupported)\t\(String(format: "%.3f", frac(region)))\t\(inside.count)\t\(counts.map(String.init).joined(separator: "/"))\t\(String(format: "%.3f", best.map { frac($0.rect) } ?? 0))\t\(best?.kind ?? 9)\t\(String(format: "%.3f", maxImg))\t\(String(format: "%.3f", maxPath))\t\(String(format: "%.3f", union))\t\(String(format: "%.3f", imgSum))")
            }
        }
        FileHandle.standardError.write("pages \(n) of \(doc.pageCount)\n".data(using: .utf8)!)
    }
}
