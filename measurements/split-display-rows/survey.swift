import Foundation
import PDFKit

@main struct Survey {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fatalError("usage: survey <pdf> [maxGap]") }
        let source = URL(fileURLWithPath: args[1])
        let maxGap = args.count > 2 ? Double(args[2])! : 24.0
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
            min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.5
        }
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let graphics = GraphicsReader.read(reference)
                if graphics.unsupported || page.rotation % 360 != 0 { return }
                var content = PageContent(number: index + 1, bounds: bounds,
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
                guard !regions.isEmpty else { return }
                for line in content.lines where !regions.contains(where: { $0.intersects(line.rect) }) {
                    for region in regions {
                        guard content.lines.contains(where: {
                            $0 != line && region.intersects($0.rect) && sameRow($0.rect, line.rect)
                        }) else { continue }
                        let gap = line.rect.midX < region.midX
                            ? region.minX - line.rect.maxX : line.rect.minX - region.maxX
                        guard gap >= 0, gap <= maxGap else { continue }
                        let wordless = line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) == nil
                        print(String(format: "%d\t%.3f\t%.3f\t%.3f\t%@\t%@", index + 1, gap, body,
                                     Double(line.fontSize), wordless ? "MATH" : "WORD",
                                     line.text.replacingOccurrences(of: "\t", with: " ")))
                    }
                }
            }
        }
    }
}
