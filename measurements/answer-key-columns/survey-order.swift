import Foundation
import PDFKit

// Prints the reading order `LayoutReconstructor.ordered` gives a page, with each element's
// rectangle, so an answer key's numbering sequence can be read off the order. Build it from the
// repository root with the reader's sources, as `doc/regression-testing.md` builds
// `capture-layout-fixture.swift`, then `survey-order <pdf> <page> [<page> …]`.
@main struct SurveyOrder {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { fatalError("usage: survey-order <pdf> <page> [<page> …]") }
        let source = URL(fileURLWithPath: args[1])
        let pages = args.dropFirst(2).compactMap { Int($0) }
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        for number in pages {
            try autoreleasepool {
                guard let page = document.page(at: number - 1), let reference = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let graphics = GraphicsReader.read(reference)
                var content = PageContent(number: number, bounds: bounds,
                    lines: try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true,
                        columnJoints: GraphicsReader.columnJoints(graphics.paints.map(\.rect)),
                        borderlessTableInk: graphics.paints.map(\.rect),
                        glyphDecodings: [:], report: nil),
                    graphics: graphics.regions)
                _ = HiddenTextFilter.removeHidden(&content.lines, graphics: graphics)
                let composed = TintDetector.compose(graphics.paints, lines: content.lines, bounds: bounds)
                content.graphics = composed.graphics
                content.tints = composed.tints
                content.separators = composed.separators
                let body = max(4, LayoutReconstructor.bodySize(content.lines))
                let regions = LayoutReconstructor.graphicsWithLabels(content)
                let lines = content.lines.filter { line in !regions.contains { $0.intersects(line.rect) } }
                let free = LayoutReconstructor.joiningRowPieces(
                    LayoutReconstructor.joiningMarkerPieces(lines), images: regions, body: body)
                let elements = free.map { LayoutReconstructor.Element(rect: $0.readingRect ?? $0.rect, line: $0) }
                    + regions.enumerated().map {
                        LayoutReconstructor.Element(rect: $0.element, image: "region-\($0.offset)")
                    }
                print("== page \(number)  body \(String(format: "%.2f", Double(body)))  "
                      + "lines \(free.count)  regions \(regions.count)")
                for (index, element) in LayoutReconstructor.ordered(elements, bodySize: body).enumerated() {
                    let r = element.rect
                    let what = element.line.map { "\"\($0.text)\"" } ?? (element.image ?? "?")
                    print(String(format: "%3d  x %7.2f…%7.2f  y %7.2f…%7.2f  %@",
                                 index, Double(r.minX), Double(r.maxX), Double(r.minY), Double(r.maxY), what))
                }
            }
        }
    }
}
