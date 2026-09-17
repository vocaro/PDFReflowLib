import Foundation
import PDFKit
import CryptoKit

// usage: stages <pdf> <page> [synthetic]
@main struct Stages {
    static func h(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined() }
    static func enc(_ c: PageContent) -> String {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        return String(data: try! e.encode(c), encoding: .utf8)!
    }
    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[1])
        let doc = PDFDocument(url: url)!
        let p = Int(args[2])!
        let synthetic = args.count > 3
        let index = try StructureTreeReader.read(url)
        let page = doc.page(at: p - 1)!, ref = page.pageRef!
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(ref)
        print("graphics", h("\(g.paints.map(\.rect)) \(g.regions) \(g.hasInvisibleText) \(g.hasOnlyInvisibleText)"))
        var lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
            columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect))
        print("lines", h(enc(PageContent(number: p, bounds: bounds, lines: lines, graphics: []))))
        if let tags = index.pages[p], !tags.isEmpty, !index.rejected {
            _ = StructureTreeReader.validates(tags, owners: index.owners[p] ?? [:], page: ref) && MarkedTextReader.apply(tags, page: ref, lines: &lines)
        }
        if !g.hasInvisibleText { _ = HiddenTextFilter.removeHidden(&lines, graphics: g) }
        let composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
        var content = PageContent(number: p, bounds: bounds, lines: lines, graphics: composed.graphics)
        content.tints = composed.tints; content.separators = composed.separators
        content.hasSyntheticTextStyle = synthetic
        let area = bounds.width * bounds.height
        if g.regions.contains(where: { $0.width * $0.height > area * 0.75 }) { content.graphics = [] }
        print("content", h(enc(content)))
        if let path = ProcessInfo.processInfo.environment["DUMP"] {
            try enc(content).write(toFile: path, atomically: true, encoding: .utf8)
        }
        var warnings: [ConversionWarning] = []
        let regions = LayoutReconstructor.graphicsWithLabels(content).enumerated().map { ($0.element, "image-\($0.offset)") }
        print("regions", h("\(regions)"))
        let blocks = LayoutReconstructor.blocks(page: content, images: regions, vocabulary: [], warnings: &warnings)
        print("blocks", blocks.count, h("\(blocks)"))
    }
}
