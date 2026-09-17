import Foundation
import PDFKit

// Survey for #93: every image-backed page of one PDF (native text over a graphic covering more
// than 75% of the page, the `unverifiedTextLayer` signal), with the extraction steps the pipeline
// runs before its OCR decision, and the raw evidence the plausibility test reads: the page's
// native text, its line boxes, and text-shaped ink outside those boxes at two raster resolutions.
// Build (the library sources compile into the tool, so internal types are visible):
//   xcrun swiftc -parse-as-library -enable-bare-slash-regex -O <Sources/PDFReflowLib/*.swift except EPUBWriter, PDFConverter> \
//     measurements/text-layer-plausibility/survey-pages.swift -o <scratch>/survey-pages
// Usage: survey-pages <pdf> [first last] > pages.jsonl
@main struct SurveyPages {
    struct Ink: Encodable {
        var dpi: Double, textRows: Int, uncoveredRows: Int, textInk: Int, uncoveredInk: Int, seconds: Double
    }
    struct Record: Encodable {
        var page: Int, invisibleText: Bool, lines: Int, text: String
        var rects: [[Double]]
        var ink: [Ink]
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: survey-pages <pdf> [first last]")
        }
        let first = args.count >= 4 ? Int(args[2])! : 1
        let last = args.count >= 4 ? Int(args[3])! : document.pageCount
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for i in (first - 1)..<min(last, document.pageCount) {
            try autoreleasepool {
                guard let page = document.page(at: i), let reference = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let graphics = GraphicsReader.read(reference)
                let requiresPageImage = graphics.unsupported || page.rotation % 360 != 0
                let pageSized = graphics.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 }
                guard !requiresPageImage, pageSized else { return }
                let syntheticStyle = graphics.hasOnlyInvisibleText
                let native = !syntheticStyle
                var lines = try NativeTextReader.lines(on: page, limit: 20_000_000, includeStyle: native,
                    columnJoints: native ? GraphicsReader.columnJoints(graphics.paints.map(\.rect)) : [],
                    borderlessTableInk: native ? graphics.paints.map(\.rect) : nil)
                if !syntheticStyle { _ = HiddenTextFilter.removeHidden(&lines, graphics: graphics) }
                guard !lines.isEmpty else { return }
                var content = PageContent(number: i + 1, bounds: bounds, lines: lines, graphics: graphics.regions)
                let composed = TintDetector.compose(graphics.paints, lines: lines, bounds: bounds)
                content.graphics = composed.graphics
                content.tints = composed.tints
                content.separators = composed.separators
                // #117: a born-digital layout whose art only clusters into a page-sized region is exempt.
                guard !PDFReflowLibPipeline.layoutComesApart(content, graphics: graphics) else { return }
                let normalized = lines.map { line in
                    CGRect(x: (line.rect.minX - bounds.minX) / bounds.width, y: (line.rect.minY - bounds.minY) / bounds.height,
                           width: line.rect.width / bounds.width, height: line.rect.height / bounds.height)
                }
                var inks: [Ink] = []
                for dpi in [180.0, 72.0] {
                    var options = ConversionOptions()
                    options.rasterDPI = dpi
                    let start = Date()
                    let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
                    let m = OCRTextCoverage.measure(image: image, lines: normalized,
                                                    pixelsPerPoint: Double(image.width) / bounds.width)
                    inks.append(Ink(dpi: dpi, textRows: m.textRows, uncoveredRows: m.uncoveredRows, textInk: m.textInk,
                                    uncoveredInk: m.uncoveredInk, seconds: Date().timeIntervalSince(start)))
                }
                let record = Record(page: i + 1, invisibleText: graphics.hasInvisibleText, lines: lines.count,
                    text: lines.map(\.text).joined(separator: "\n"),
                    rects: normalized.map { [$0.minX, $0.minY, $0.width, $0.height] }, ink: inks)
                FileHandle.standardOutput.write(try encoder.encode(record) + Data("\n".utf8))
            }
        }
    }
}
