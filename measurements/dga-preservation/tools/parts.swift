import Foundation
import PDFKit

// usage: parts <pdf> <page>... -> time each #117 step of compose on those pages
@main struct Parts {
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        for p in args.dropFirst(2).compactMap({ Int($0) }) {
            autoreleasepool {
                let page = doc.page(at: p - 1)!
                let g = GraphicsReader.read(page.pageRef!)
                let lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000)) ?? []
                func time<T>(_ body: () -> T) -> (T, Double) { let s = Date(); let r = body(); return (r, Date().timeIntervalSince(s)) }
                let (trimmed, t1) = time { TintDetector.withoutTitleBackdrops(g.paints, lines: lines) }
                let (seeds, t2) = time { TintDetector.seedClusters(trimmed.map(\.rect), lines: lines) }
                let (plain, t3) = time { clusters(trimmed.map(\.rect), distance: 4) }
                let (_, t4) = time { TintDetector.compose(g.paints, lines: lines, bounds: page.bounds(for: .cropBox)) }
                print(String(format: "page %d paints %d titleBackdrops %.3fs seedClusters %.3fs (%d) clusters %.3fs (%d) compose %.3fs",
                             p, g.paints.count, t1, t2, seeds.count, t3, plain.count, t4))
            }
        }
    }
}
