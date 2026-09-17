import Foundation
import PDFKit

// usage: survey <pdf> [first last]  -> one TSV line per image-backed-text page
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let doc = PDFDocument(url: url)!
let first = args.count > 3 ? Int(args[2])! : 1
let last = args.count > 3 ? Int(args[3])! : doc.pageCount
let index = try StructureTreeReader.read(url)
var total = 0
var tagged = 0
print("page\tlines\tinvisible\tonlyInvisible\tunsupported\trotated\ttags\tapplies\tmaxRegionFrac")
for n in first...last {
    autoreleasepool {
        let page = doc.page(at: n - 1)!
        let ref = page.pageRef!
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(ref)
        if !index.pages[n, default: [:]].isEmpty { tagged += 1 }
        let area = bounds.width * bounds.height
        let maxFrac = g.regions.map { $0.width * $0.height / area }.max() ?? 0
        guard maxFrac > 0.75 else { return }
        let requires = g.unsupported || page.rotation % 360 != 0
        let synthetic = g.hasOnlyInvisibleText
        var lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: !requires && !synthetic)) ?? []
        guard !lines.isEmpty else { return }
        total += 1
        let tags = index.pages[n] ?? [:]
        var applies = "-"
        if !tags.isEmpty {
            let v = StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref)
            let a = v && MarkedTextReader.apply(tags, page: ref, lines: &lines)
            let count = lines.filter { $0.structure != nil }.count
            applies = v ? (a ? "all(\(count))" : "partial(\(count))") : "invalid"
        }
        print("\(n)\t\(lines.count)\t\(g.hasInvisibleText)\t\(g.hasOnlyInvisibleText)\t\(g.unsupported)\t\(page.rotation % 360 != 0)\t\(tags.count)\t\(applies)\t\(String(format: "%.3f", maxFrac))")
    }
}
FileHandle.standardError.write("imageBackedPages \(total) of \(doc.pageCount); pagesWithTags \(tagged); rejectedTree \(index.rejected)\n".data(using: .utf8)!)
