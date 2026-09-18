import Foundation
import PDFKit

// One row per preserved image the converter would emit, with the evidence that names it (#187).
// Columns: book, page, kind, caption ("-" when the page prints none for this crop), raster
// ("raster" when a placed image XObject inks a tenth of the crop, "vector" otherwise), width,
// height, lines, words, the caption text, and the first 120 characters of the lines the crop holds.
//
// Build from the worktree root:
//   swiftc -swift-version 6 -O $(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter\|PDFReflowLibPipeline\|EPUBTextEncoder') \
//     measurements/preserved-image-alt-text/survey.swift -o /tmp/alt-survey
//   for pdf in corpus/cache/*.pdf; do /tmp/alt-survey "$pdf"; done > survey.tsv
@main struct Survey {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fatalError("usage: survey <pdf> [firstPage [lastPage]]") }
        let source = URL(fileURLWithPath: args[1])
        let name = source.deletingPathExtension().lastPathComponent
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        // Optional page range, one-based and inclusive, for a quick look at a few pages.
        let first = args.count > 2 ? Int(args[2])! - 1 : 0
        let last = args.count > 3 ? Int(args[3])! : document.pageCount
        for index in first..<min(last, document.pageCount) {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let graphics = GraphicsReader.read(reference)
                if graphics.unsupported || page.rotation % 360 != 0 {
                    print("\(name)\t\(index + 1)\tunsupported\t-\t-\t0\t0\t0\t0\t")
                    return
                }
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
                if ProcessInfo.processInfo.environment["SURVEY_LINES"] != nil {
                    for line in content.lines {
                        print(String(format: "  line %.1f %.1f %.1f %.1f size %.1f  %@", Double(line.rect.minX),
                                     Double(line.rect.minY), Double(line.rect.maxX), Double(line.rect.maxY),
                                     Double(line.fontSize), line.text))
                    }
                }
                if ProcessInfo.processInfo.environment["SURVEY_GRAPHICS"] != nil {
                    for rect in content.graphics {
                        print(String(format: "  graphic %.1f %.1f %.1f %.1f", Double(rect.minX), Double(rect.minY),
                                     Double(rect.width), Double(rect.height)))
                    }
                }
                let classified = LayoutReconstructor.classifiedGraphics(content)
                guard !classified.isEmpty else { return }
                let captions = LayoutReconstructor.sourceCaptions(for: classified.map(\.rect), in: content)
                let rasters = graphics.paints.filter { $0.image && $0.rect.isFinite && !$0.rect.isNull }.map(\.rect)
                for (rect, kind) in classified {
                    let held = content.lines.filter { rect.intersects($0.rect) }
                    let words = held.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
                    let raster = rasters.contains { inked($0, rect) }
                    let caption = captions[rect]
                    let heldText = String(held.map(\.text).joined(separator: " | ").prefix(120))
                    print(String(format: "%@\t%d\t%@\t%@\t%@\t%.0f\t%.0f\t%d\t%d\t%@\t%@",
                                 name, index + 1, kind.rawValue, caption == nil ? "-" : "captioned",
                                 raster ? "raster" : "vector", Double(rect.width), Double(rect.height),
                                 held.count, words,
                                 (caption ?? "").replacingOccurrences(of: "\t", with: " "),
                                 heldText.replacingOccurrences(of: "\t", with: " ")))
                }
            }
        }
    }

    /// Whether a placed raster covers a tenth of the crop, which is what makes the crop a picture
    /// rather than a drawing that happens to carry a logo.
    static func inked(_ raster: CGRect, _ crop: CGRect) -> Bool {
        let overlap = raster.intersection(crop)
        guard !overlap.isNull, crop.width > 0, crop.height > 0 else { return false }
        return overlap.width * overlap.height >= crop.width * crop.height * 0.1
    }
}
