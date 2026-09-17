import Foundation
import PDFKit

// For every line a page leaves outside every crop, the nearest crop's geometry: the distance to
// the crop's rectangle, whether the line stands inside the crop's own vertical or horizontal span,
// the crop's size, and the line's text. Build it from the repository root with the reader's
// sources, as `doc/regression-testing.md` builds `capture-layout-fixture.swift`, then
// `survey <pdf> [maxGap]`. Columns: pdf, page, gap, dx, dy, insideY, insideX, chars, cropW, cropH,
// cropLines, body, drawn, worded, longestHeldLine, text.
@main struct Survey {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fatalError("usage: survey <pdf> [maxGap]") }
        let source = URL(fileURLWithPath: args[1])
        let maxGap = args.count > 2 ? Double(args[2])! : 12.0
        let name = source.deletingPathExtension().lastPathComponent
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
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
                        let dx = max(region.minX - line.rect.maxX, line.rect.minX - region.maxX, 0)
                        let dy = max(region.minY - line.rect.maxY, line.rect.minY - region.maxY, 0)
                        let gap = max(dx, dy)
                        guard gap <= maxGap else { continue }
                        let insideY = line.rect.minY >= region.minY && line.rect.maxY <= region.maxY
                        let insideX = line.rect.minX >= region.minX && line.rect.maxX <= region.maxX
                        let held = content.lines.filter { region.intersects($0.rect) }
                        let drawn = content.graphics.contains {
                            region.intersects($0) && $0.width >= body && $0.height >= body
                        }
                        let longest = held.map { $0.text.trimmingCharacters(in: .whitespaces).count }.max() ?? 0
                        let worded = held.contains {
                            $0.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
                        }
                        print(String(format: "%@\t%d\t%.3f\t%.3f\t%.3f\t%@\t%@\t%d\t%.1f\t%.1f\t%d\t%.1f\t%@\t%@\t%d\t%@",
                                     name, index + 1, gap, Double(dx), Double(dy),
                                     insideY ? "inY" : "-", insideX ? "inX" : "-",
                                     line.text.trimmingCharacters(in: .whitespaces).count,
                                     Double(region.width), Double(region.height), held.count, Double(body),
                                     drawn ? "drawn" : "-", worded ? "worded" : "-", longest,
                                     line.text.replacingOccurrences(of: "\t", with: " ")))
                    }
                }
            }
        }
    }
}
