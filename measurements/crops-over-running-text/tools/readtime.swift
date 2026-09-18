import Foundation
import PDFKit

// usage: readtime <pdf> <page> [rounds] — best of N for GraphicsReader.read.
@main struct ReadTime {
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let p = Int(args[2])!
        let rounds = args.count > 3 ? Int(args[3])! : 5
        let page = doc.page(at: p - 1)!
        var best = Double.infinity
        var count = 0
        for _ in 0..<rounds {
            let start = Date()
            let g = GraphicsReader.read(page.pageRef!)
            best = min(best, -start.timeIntervalSinceNow)
            count = g.paints.count
        }
        print(String(format: "page %d paints %d read %.1f ms", p, count, best * 1000))
    }
}
