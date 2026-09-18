import Foundation
import PDFKit

// Survey for #176: every page of one PDF, with the extraction steps the pipeline runs before its
// OCR decision, and the two facts the image-only rule reads:
//
//   * whether the page's reflowable text layer holds any letter (a slide whose only text is its
//     folio reflows nothing once furniture removal takes the folio away);
//   * the page's ink polarity and its text-shaped rows, measured both as `OCRTextCoverage` does
//     today (components darker than the ink threshold) and against the page's own background
//     (the darker side inverted when it covers most of the page).
//
// Every page is rendered at 72 DPI for the polarity fact; the 180 DPI measurement the library
// would run is added for pages whose layer holds no letter.
//
// Build (the library sources compile into the tool, so internal types are visible):
//   measurements/text-layer-plausibility/build-tool.sh measurements/image-only-pages/survey-pages.swift <out>
// Usage: survey-pages <pdf> [first last] > pages.jsonl
@main struct SurveyImageOnlyPages {
    struct Ink: Encodable {
        var dpi: Double
        /// The ink threshold and the share of pixels below it (the "dark" side).
        var threshold: Int, darkFraction: Double, inverted: Bool
        /// Candidate readings of "which side is the background": the most common luminance over
        /// 16-wide bins, the median luminance, the dark share of the page's outer 2% border ring,
        /// and the share of the page's area held by the largest dark component.
        var modalLuminance: Int, medianLuminance: Int, borderDarkFraction: Double
        var largestDarkComponentArea: Double
        /// `OCRTextCoverage.measure` as it stands today, over the raster as rendered.
        var textRows: Int, uncoveredRows: Int, textInk: Int, uncoveredInk: Int
        /// The same measurement against the page's own background.
        var normalizedTextRows: Int, normalizedUncoveredRows: Int
        var normalizedTextInk: Int, normalizedUncoveredInk: Int
        /// The library's own reading: against the page's background (only when the plain reading
        /// finds no row) and ignoring the page's placed images.
        var ruleTextRows: Int, ruleUncoveredRows: Int
        var seconds: Double
    }
    struct Record: Encodable {
        var page: Int
        var requiresPageImage: Bool, blank: Bool, pageSized: Bool, imageBacked: Bool
        var invisibleText: Bool
        var lines: Int, letters: Int, words: Int, characters: Int
        /// Crops the page would keep, and whether any is a picture of the whole page.
        var crops: Int
        var text: String
        var ink: [Ink]
    }

    /// The page's own background decides which pixels are ink: when the darker side of the ink
    /// threshold covers more than `darkBound` of the page, it is the background and the raster is
    /// inverted before the rows are found.
    static let darkBound = 0.5

    static func normalized(_ raster: OCRTextCoverage.GrayRaster) -> OCRTextCoverage.GrayRaster {
        OCRTextCoverage.GrayRaster(width: raster.width, height: raster.height,
                                   pixels: raster.pixels.map { 255 - $0 })
    }

    static func darkFraction(_ raster: OCRTextCoverage.GrayRaster, threshold: UInt8) -> Double {
        guard !raster.pixels.isEmpty else { return 0 }
        var dark = 0
        for value in raster.pixels where value < threshold { dark += 1 }
        return Double(dark) / Double(raster.pixels.count)
    }

    struct Background {
        var modal = 0, median = 0, border = 0.0, largestComponent = 0.0
    }

    static func background(_ raster: OCRTextCoverage.GrayRaster, threshold: UInt8) -> Background {
        var result = Background()
        guard !raster.pixels.isEmpty else { return result }
        var histogram = [Int](repeating: 0, count: 256)
        for value in raster.pixels { histogram[Int(value)] += 1 }
        var bins = [Int](repeating: 0, count: 16)
        for (value, count) in histogram.enumerated() { bins[value / 16] += count }
        result.modal = (bins.enumerated().max { $0.element < $1.element }!.offset) * 16 + 8
        var seen = 0
        for (value, count) in histogram.enumerated() {
            seen += count
            if seen * 2 >= raster.pixels.count { result.median = value; break }
        }
        let width = raster.width, height = raster.height
        let inset = max(1, min(width, height) / 50)
        var borderDark = 0, borderTotal = 0
        for y in 0..<height {
            let edgeRow = y < inset || y >= height - inset
            for x in 0..<width where edgeRow || x < inset || x >= width - inset {
                borderTotal += 1
                if raster.pixels[y * width + x] < threshold { borderDark += 1 }
            }
        }
        result.border = borderTotal == 0 ? 0 : Double(borderDark) / Double(borderTotal)
        let largest = raster.components(darkerThan: threshold).map(\.pixels).max() ?? 0
        result.largestComponent = Double(largest) / Double(raster.pixels.count)
        return result
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
                guard bounds.isFinite, bounds.width > 0, bounds.height > 0 else { return }
                let graphics = GraphicsReader.read(reference)
                let requiresPageImage = graphics.unsupported || page.rotation % 360 != 0
                let syntheticStyle = graphics.hasOnlyInvisibleText && graphics.regions.contains {
                    $0.width * $0.height > bounds.width * bounds.height * 0.75
                }
                let native = !requiresPageImage && !syntheticStyle
                var lines = try NativeTextReader.lines(on: page, limit: 20_000_000, includeStyle: native,
                    columnJoints: native ? GraphicsReader.columnJoints(graphics.paints.map(\.rect)) : [],
                    borderlessTableInk: native ? graphics.paints.map(\.rect) : nil)
                if native { _ = HiddenTextFilter.removeHidden(&lines, graphics: graphics) }
                var content = PageContent(number: i + 1, bounds: bounds, lines: lines, graphics: graphics.regions)
                if !requiresPageImage {
                    let art = PDFReflowLibPipeline.artBesideBackdrops(graphics.paints, lines: lines, bounds: bounds)
                    let composed = TintDetector.compose(art ?? graphics.paints, lines: lines, bounds: bounds)
                    content.graphics = composed.graphics
                    content.tints = composed.tints
                    content.separators = composed.separators
                }
                content.requiresPageImage = requiresPageImage
                let blank = lines.isEmpty
                    && BlankPageDetector.drawsNothing(lines: lines, graphics: graphics, annotations: 0)
                    && BlankPageDetector.rendersWhite(reference, bounds: bounds)
                let pageArea = bounds.width * bounds.height
                let pageSized = graphics.regions.contains { $0.width * $0.height > pageArea * 0.75 }
                    && (requiresPageImage || !PDFReflowLibPipeline.layoutComesApart(content, graphics: graphics))
                let text = lines.map(\.text).joined(separator: "\n")
                let letters = text.filter(\.isLetter).count
                func normalize(_ rect: CGRect) -> CGRect {
                    CGRect(x: (rect.minX - bounds.minX) / bounds.width,
                           y: (rect.minY - bounds.minY) / bounds.height,
                           width: rect.width / bounds.width, height: rect.height / bounds.height)
                }
                let normalizedLines = lines.map { normalize($0.rect) }
                let placedImages = (graphics.paints.filter(\.image).map(\.rect) + graphics.inlineImages)
                    .map(normalize)
                var inks: [Ink] = []
                // Every page is measured at 72 DPI for its polarity; a page whose layer holds no
                // letter is also measured at the 180 DPI the library's ink test uses.
                var resolutions = [72.0]
                if !blank && (letters == 0 || args.count >= 4) { resolutions.append(180.0) }
                for dpi in resolutions {
                    var options = ConversionOptions()
                    options.rasterDPI = dpi
                    let start = Date()
                    let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
                    guard let raster = OCRTextCoverage.GrayRaster(image) else { return }
                    let pixelsPerPoint = Double(raster.width) / bounds.width
                    let threshold = raster.inkThreshold()
                    let fraction = darkFraction(raster, threshold: threshold)
                    let ground = background(raster, threshold: threshold)
                    let plain = OCRTextCoverage.measure(raster, lines: normalizedLines, excluded: [],
                                                        pixelsPerPoint: pixelsPerPoint)
                    let inverted = fraction > darkBound
                    let other = inverted
                        ? OCRTextCoverage.measure(normalized(raster), lines: normalizedLines, excluded: [],
                                                  pixelsPerPoint: pixelsPerPoint)
                        : plain
                    let ruled = OCRTextCoverage.measure(raster, lines: normalizedLines,
                        excluded: placedImages, pixelsPerPoint: pixelsPerPoint)
                    inks.append(Ink(dpi: dpi, threshold: Int(threshold), darkFraction: fraction, inverted: inverted,
                        modalLuminance: ground.modal, medianLuminance: ground.median,
                        borderDarkFraction: ground.border, largestDarkComponentArea: ground.largestComponent,
                        textRows: plain.textRows, uncoveredRows: plain.uncoveredRows,
                        textInk: plain.textInk, uncoveredInk: plain.uncoveredInk,
                        normalizedTextRows: other.textRows, normalizedUncoveredRows: other.uncoveredRows,
                        normalizedTextInk: other.textInk, normalizedUncoveredInk: other.uncoveredInk,
                        ruleTextRows: ruled.textRows, ruleUncoveredRows: ruled.uncoveredRows,
                        seconds: Date().timeIntervalSince(start)))
                }
                let record = Record(page: i + 1, requiresPageImage: requiresPageImage, blank: blank,
                    pageSized: pageSized, imageBacked: !lines.isEmpty && pageSized,
                    invisibleText: graphics.hasInvisibleText,
                    lines: lines.count, letters: letters,
                    words: text.split(whereSeparator: \.isWhitespace).count, characters: text.count,
                    crops: LayoutReconstructor.graphicsWithLabels(content).count,
                    text: letters == 0 ? text : String(text.prefix(200)), ink: inks)
                FileHandle.standardOutput.write(try encoder.encode(record) + Data("\n".utf8))
            }
        }
    }
}
