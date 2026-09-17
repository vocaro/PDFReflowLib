import Foundation
import PDFKit

// usage: blocksurvey <pdf> [first last]
// Per page: the reconstructed blocks' text (tags applied, hidden text removed, tints composed,
// crops from graphicsWithLabels), without furniture removal, OCR or cross-page joins.
@main struct BlockSurvey {
    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[1])
        let doc = PDFDocument(url: url)!
        let first = args.count > 3 ? Int(args[2])! : 1
        let last = args.count > 3 ? Int(args[3])! : doc.pageCount
        let index = try StructureTreeReader.read(url)
        for p in first...last {
            autoreleasepool {
                guard let page = doc.page(at: p - 1), let ref = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let g = GraphicsReader.read(ref)
                guard !g.unsupported, var lines = try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                    columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect)) else { print("\(p)\tskipped"); return }
                if let tags = index.pages[p], !tags.isEmpty, !index.rejected {
                    if !(StructureTreeReader.validates(tags, owners: index.owners[p] ?? [:], page: ref) && MarkedTextReader.apply(tags, page: ref, lines: &lines)) {}
                }
                if !g.hasInvisibleText { _ = HiddenTextFilter.removeHidden(&lines, graphics: g) }
                let composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
                var content = PageContent(number: p, bounds: bounds, lines: lines, graphics: composed.graphics)
                content.tints = composed.tints; content.separators = composed.separators
                let area = bounds.width * bounds.height
                if g.regions.contains(where: { $0.width * $0.height > area * 0.75 }) { content.graphics = [] }
                var warnings: [ConversionWarning] = []
                let regions = LayoutReconstructor.graphicsWithLabels(content).enumerated().map { ($0.element, "image-\($0.offset)") }
                let blocks = LayoutReconstructor.blocks(page: content, images: regions, vocabulary: [], warnings: &warnings)
                print("\(p)\t\(blocks.count)")
                for b in blocks { print("  \(b.content)".prefix(400)) }
            }
        }
    }
}
