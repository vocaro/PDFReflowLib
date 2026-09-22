import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Original fixtures isolate the spatial notation seen in algebra and statistical tables.
// Colors identify independent glyph groups; expectations come from these PDF coordinates,
// never from a golden image emitted by the converter.
private func regionPDF(table: Bool, separatedFraction: Bool = false) -> Data {
    let drawing: String
    if table {
        drawing = """
        0 G 1 w 80 180 240 150 re S
        200 180 m 200 330 l S
        80 230 m 320 230 l S 80 280 m 320 280 l S
        1 0 0 rg BT /F1 14 Tf 100 300 Td (36) Tj ET
        1 0 0 rg BT /F1 14 Tf 220 300 Td (84) Tj ET
        0 1 0 rg BT /F1 14 Tf 100 250 Td (9) Tj ET
        0 1 0 rg BT /F1 14 Tf 220 250 Td (21) Tj ET
        0 0 1 rg BT /F1 14 Tf 100 200 Td (3) Tj ET
        0 0 1 rg BT /F1 14 Tf 220 200 Td (7) Tj ET
        """
    } else {
        drawing = """
        0 g BT /F1 12 Tf \(separatedFraction ? 100 : 140) 247 Td (x =) Tj ET
        0 G 1 w 160 250 m 200 250 l S
        1 0 0 rg BT /F1 12 Tf 165 257 Td (36) Tj ET
        0 1 0 rg BT /F1 8 Tf 181 265 Td (2) Tj ET
        0 0 1 rg BT /F1 12 Tf 165 232 Td (84) Tj ET
        """
    }
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("""
        0 g BT /F1 12 Tf 40 420 Td (Read the worked example before continuing.) Tj ET
        \(drawing)
        0 g BT /F1 12 Tf 40 80 Td (The following paragraph must remain reflowable.) Tj ET
        """),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])
}

private struct RegionPixels: CustomStringConvertible {
    var description: String { "\(width)×\(height) raster" }
    var width: Int
    var height: Int
    var bytes: [UInt8]

    init(_ data: Data) throws {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        width = image.width; height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width,
                height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = pixels
    }

    // Top-left raster coordinates. Saturated interiors avoid antialiasing/platform noise.
    func bounds(channel: Int, leftHalf: Bool? = nil) -> CGRect? {
        var result = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                if let leftHalf, (x < width / 2) != leftHalf { continue }
                let i = (y * width + x) * 4
                if bytes[i + channel] > 200 && (0..<3).filter({ $0 != channel }).allSatisfy({ bytes[i + $0] < 60 }) {
                    result = result.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return result.isNull ? nil : result
    }
}

private func convertRegion(table: Bool, directory: URL, dpi: Double, separatedFraction: Bool = false) async throws -> (ConversionReport, String, [Data]) {
    let source = directory.appendingPathComponent("source.pdf")
    let output = directory.appendingPathComponent("book.epub")
    try regionPDF(table: table, separatedFraction: separatedFraction).write(to: source)
    var options = ConversionOptions(); options.ocr = .never; options.rasterDPI = dpi
    let report = try await PDFConverter().convert(from: source, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    func read(_ path: String) throws -> Data { try archive.entryData(path) }
    let html = String(decoding: try read("EPUB/chapter-1.xhtml"), as: UTF8.self)
    let images = try archive.filter { $0.path.hasSuffix(".png") }.map { try read($0.path) }
    return (report, html, images)
}

@Test(arguments: [72.0, 144.0]) func displayedFractionAndExponentSurviveInEPUBPixels(dpi: Double) async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let (report, html, images) = try await convertRegion(table: false, directory: dir, dpi: dpi)
    #expect(report.reflowedPageCount == 1)
    #expect(report.recognizedPageCount == 0)
    #expect(!report.warnings.contains { $0.code == .pageImageFallback })
    #expect(report.warnings.contains { $0.code == .imageRegion && $0.page == 1 })
    #expect(html.contains("Read the worked example before continuing."))
    #expect(html.contains("The following paragraph must remain reflowable."))
    #expect(!html.contains("x =")) // The spatial expression must not also appear flattened as prose.
    #expect(images.count == 1)
    let pixels = try RegionPixels(#require(images.first))
    let numerator = try #require(pixels.bounds(channel: 0))
    let exponent = try #require(pixels.bounds(channel: 1))
    let denominator = try #require(pixels.bounds(channel: 2))
    let scale = dpi / 72
    #expect(exponent.maxY < numerator.maxY)
    #expect(exponent.minX > numerator.maxX)
    #expect(exponent.height < numerator.height)
    #expect(numerator.maxY < denominator.minY)
    #expect(abs(numerator.minX - denominator.minX) <= scale * 2)
    #expect(abs(denominator.minY - numerator.minY - 25 * scale) <= scale * 2)
    // A fraction bar must span the gap; a PNG containing only the colored glyphs is insufficient.
    var barRows = 0
    for y in Int(numerator.maxY)..<Int(denominator.minY) {
        let dark = (0..<pixels.width).filter { x in
            let i = (y * pixels.width + x) * 4
            return pixels.bytes[i..<i + 3].allSatisfy { $0 < 80 }
        }
        if dark.count >= Int(38 * scale) { barRows += 1 }
    }
    #expect(barRows >= 1)
    #expect(pixels.width < Int(130 * scale) && pixels.height < Int(90 * scale))
}

@Test(arguments: [72.0, 144.0]) func ruledTableKeepsEveryCellInItsRowAndColumn(dpi: Double) async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let (report, html, images) = try await convertRegion(table: true, directory: dir, dpi: dpi)
    #expect(report.reflowedPageCount == 1 && report.recognizedPageCount == 0)
    #expect(!report.warnings.contains { $0.code == .pageImageFallback })
    #expect(images.count == 1)
    let imagePosition = try #require(html.range(of: "<img "))
    #expect(try #require(html.range(of: "Read the worked example")).lowerBound < imagePosition.lowerBound)
    #expect(try #require(html.range(of: "The following paragraph")).lowerBound > imagePosition.lowerBound)
    for cell in ["36", "84", "9", "21", "3", "7"] {
        #expect(!html.contains(">\(cell)<"))
    }
    let pixels = try RegionPixels(#require(images.first))
    let scale = dpi / 72
    #expect(abs(Double(pixels.width) - 244 * scale) <= 2)
    #expect(abs(Double(pixels.height) - 154 * scale) <= 2)
    var priorY: CGFloat?
    for color in 0..<3 {
        let left = try #require(pixels.bounds(channel: color, leftHalf: true))
        let right = try #require(pixels.bounds(channel: color, leftHalf: false))
        #expect(abs(left.minY - right.minY) <= scale * 2)
        #expect(abs(right.minX - left.minX - 120 * scale) <= scale * 2)
        #expect(left.width > 4 * scale && left.height > 7 * scale)
        #expect(right.width > 4 * scale && right.height > 7 * scale)
        if let priorY { #expect(abs(left.minY - priorY - 50 * scale) <= scale * 2) }
        priorY = left.minY
    }
}

@Test func equationRecognitionDoesNotRasterizeCodeOrOrdinaryProse() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 500)
    for text in ["value = 42", "if a <= b:"] {
        let page = PageContent(number: 1, bounds: bounds, lines: [
            TextLine(text: text, rect: CGRect(x: 40, y: 300, width: 200, height: 12), fontSize: 12, monospaced: true),
        ], graphics: [])
        #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
            .map(\.text) == [text])
    }
    let page = PageContent(number: 1, bounds: bounds, lines: [
        TextLine(text: "Example 15. Reduce each fraction.", rect: CGRect(x: 40, y: 300, width: 220, height: 12),
            fontSize: 12, monospaced: false),
    ], graphics: [])
    #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
}

@Test func formulaDetectionPreservesUnruledExpressionsAndWholeIntersectingLabels() throws {
    for expression in ["a = b + c", "√25", "x ≤ 3", "∫ f(x)"] {
        let expressionRect = CGRect(x: 100, y: 250, width: 90, height: 12)
        let labelRect = CGRect(x: 185, y: 251, width: 50, height: 12)
        let bodyRect = CGRect(x: 40, y: 100, width: 280, height: 12)
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 500), lines: [
            TextLine(text: expression, rect: expressionRect, fontSize: 12, monospaced: false),
            TextLine(text: "(15)", rect: labelRect, fontSize: 12, monospaced: false),
            TextLine(text: "Continue with the next example.", rect: bodyRect, fontSize: 12, monospaced: false),
        ], graphics: [])
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        #expect(regions.count == 1)
        let region = try #require(regions.first)
        #expect(region.contains(expressionRect) && region.contains(labelRect))
        #expect(!region.intersects(bodyRect))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/20"))
func detachedFractionKeepsNumeratorExponentAndDenominatorTogether() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let (report, html, images) = try await convertRegion(table: false, directory: dir, dpi: 144, separatedFraction: true)
    #expect(report.reflowedPageCount == 1 && images.count == 1)
    #expect(report.warnings.contains { $0.code == .imageRegion })
    #expect(html.contains("Read the worked example before continuing."))
    #expect(html.contains("The following paragraph must remain reflowable."))
    let rasters = try images.map(RegionPixels.init)
    let intactFraction = rasters.contains { image in
        (0..<3).allSatisfy { image.bounds(channel: $0) != nil }
    }
    #expect(intactFraction)
}

@Test func mergingGraphicsCannotClipNewlyIntersectingLabels() throws {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 500)
    let first = CGRect(x: 100, y: 250, width: 20, height: 20)
    let second = CGRect(x: 122, y: 240, width: 20, height: 20)
    // The label intersects only the bounding box of the union, not either input rectangle.
    let label = CGRect(x: 130, y: 263, width: 45, height: 12)
    let nearby = CGRect(x: 174, y: 263, width: 20, height: 12)
    for graphics in [[first, second], [second, first]] {
        for rects in [[label, nearby], [nearby, label]] {
            let page = PageContent(number: 1, bounds: bounds, lines: rects.map {
                TextLine(text: "label", rect: $0, fontSize: 12, monospaced: false)
            }, graphics: graphics)
            let regions = LayoutReconstructor.graphicsWithLabels(page)
            #expect(regions.count == 1)
            let region = try #require(regions.first)
            #expect(region.contains(label) && region.contains(nearby))
            #expect(region.contains(first) && region.contains(second))
        }
    }
}

@Test func regionGrowthStaysInsidePageAndLeavesDistantTextSelectable() throws {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 500)
    let edge = TextLine(text: "Edge label", rect: CGRect(x: 390, y: 300, width: 30, height: 12),
        fontSize: 12, monospaced: false)
    let prose = TextLine(text: "Unrelated prose remains selectable.",
        rect: CGRect(x: 40, y: 100, width: 250, height: 12), fontSize: 12, monospaced: false)
    let page = PageContent(number: 1, bounds: bounds, lines: [edge, prose],
        graphics: [CGRect(x: 380, y: 295, width: 20, height: 30)])
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(regions.count == 1)
    let region = try #require(regions.first)
    #expect(bounds.contains(region))
    #expect(region.contains(edge.rect.intersection(bounds)))
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(region, "figure")], vocabulary: [], warnings: &warnings)
    #expect(blocks.filter(\.hasReflowedText).map(\.text) == [prose.text])
}

@Test func algebraExerciseLayoutPreservesWholeNumberedExpressions() throws {
    let fixture = try SourceLayoutFixture.load("algebra-17")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 17)
    let page = fixture.content()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    try #require(!regions.isEmpty)
    for line in page.lines {
        for region in regions where region.intersects(line.rect) {
            #expect(region.contains(line.rect.intersection(page.bounds)), "Partially clipped source text: \(line.text)")
        }
    }
    // Source review identifies these three exercise prefixes as part of their expressions,
    // not independent prose. Previous crops left them detached from their fractions.
    for prefix in ["67)", "71)", "60)"] {
        let line = try #require(page.lines.first { $0.text.hasPrefix(prefix) })
        #expect(regions.contains { $0.contains(line.rect) })
    }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "region-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    for instruction in ["Find each quotient.", "Evaluate each expression."] {
        #expect(blocks.contains { $0.hasReflowedText && $0.text == instruction })
    }
}

/// A line-end hyphen the book's font prints as "=" is not a relation, and neither is a full
/// measure of prose that holds one (#57).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func equationRecognitionReadsARelationRatherThanAnEqualsSign() {
    for equation in ["a = b + c", "x =− c", "ax2 + bx=− c", "=± b2"] {
        #expect(LayoutReconstructor.statesAnEquation(equation))
    }
    // A broken word's own line, and a sign standing alone, state nothing.
    for text in ["Tower’s collapse. Clearly, however, the prospect of another plane hitting the sec=",
                 "the full details of the planned planes operation.Abu Turab taught the opera=",
                 "dominant, with the most important n values given by nhw ==", "=", "ordinary prose"] {
        #expect(!LayoutReconstructor.statesAnEquation(text))
    }
    // Twelve words remains the measure of a relation the page set apart from its prose.
    #expect(!LayoutReconstructor.statesAnEquation("x = " + String(repeating: "term ", count: 12)))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func proseBelowAFigureStaysOutOfTheFiguresCrop() throws {
    let fixture = try SourceLayoutFixture.load("911-306")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    var page = fixture.content()
    // Exclude the running header, which the full-document furniture pass removes.
    page.lines.removeAll { $0.text.contains("THE 9/11 COMMISSION REPORT") }
    // The book's text font prints its line-end hyphen as "=", and PDFKit reports no space after
    // a full stop, so this eighty-two-character line of prose read as a twelve-word equation and
    // seeded a crop that grew over the whole paragraph beneath the figure.
    let broken = try #require(page.lines.first { $0.text.hasSuffix("=") })
    #expect(broken.text.hasSuffix("hitting the sec=") && broken.text.count == 82)
    let figure = try #require(page.graphics.first)
    let caption = try #require(page.lines.first { $0.text.hasPrefix("Rendering by") })
    let paragraph = page.lines.filter { $0.rect.maxY < caption.rect.minY }
    #expect(paragraph.count == 11 && paragraph.contains(broken))

    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let region = try #require(regions.first)
    // The stairwell rendering is still preserved, and no crop reaches the paragraph below it.
    #expect(regions.count == 1 && region.contains(figure))
    #expect(paragraph.allSatisfy { !region.intersects($0.rect) })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(region, "figure")], vocabulary: [], warnings: &warnings)
    let text = paragraphTexts(blocks).joined(separator: "\n")
    #expect(text.contains("the South Tower stated that the incident had occurred in the other building"))
    #expect(text.contains("beyond the contemplation of anyone giving advice"))
    // The rendering's caption is the picture's, not the paragraph's opening.
    #expect(paragraphTexts(blocks).first
        == "The World Trade Center North Tower Stairwell with Deviation Rendering by Marco Crupi")
}

/// The control for the same shape of page: a photograph with a caption and ordinary prose below
/// it keeps the picture in one crop, and its caption and the prose reflow.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func aPhotographStillLeavesItsCaptionAndTheProseBelowItReflowable() throws {
    let fixture = try SourceLayoutFixture.load("911-67")
    var page = fixture.content()
    page.lines.removeAll { $0.text.contains("THE FOUNDATION OF THE NEW TERRORISM") }
    let photograph = try #require(page.graphics.first)
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let region = try #require(regions.first)
    #expect(regions.count == 1 && region.contains(photograph))
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(region, "photograph")], vocabulary: [], warnings: &warnings)
    let paragraphs = paragraphTexts(blocks)
    #expect(paragraphs.contains("Usama Bin Ladin at a news conference in Afghanistan in 1998"))
    #expect(paragraphs.contains { $0.contains("Islam is divided into two main branches") })
    // The page's folio and the picture credit stand apart from the prose, as they did before.
    #expect(paragraphs.contains("49") && paragraphs.contains("©Reuters 2004"))
}

// A page's own footer band is furniture, not a figure that owns the text beside it (#246).

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/246")) func aFooterBandDoesNotTakeTheNotesItGrazes() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    // Dietary Guidelines page 2 to the tenth of a point: a full-measure band up to y=80.12, and
    // four notes in two columns, the lower pair running from y=77.49 to y=85.45.
    let band = CGRect(x: 0, y: 0, width: 612, height: 80.12)
    func note(_ x: Double, _ y: Double, _ text: String) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: 180, height: 7.96), fontSize: 7)
    }
    let lines = [note(54, 87.99, "1 https://www.cdc.gov/chronic-disease/facts.html"),
                 note(54, 77.49, "2 https://www.cdc.gov/nchs/fastats/obesity.htm"),
                 note(315, 87.99, "3 https://gis.cdc.gov/grasp/diabetes/atlas.html"),
                 note(315, 77.49, "4 https://www.cdc.gov/physical-activity/unfit.html")]
    let page = PageContent(number: 2, bounds: bounds, lines: lines, graphics: [band])
    #expect(LayoutReconstructor.isEdgeBand(band, bounds: bounds))
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(band, "footer")], vocabulary: [], warnings: &warnings)
    let reflowed = blocks.filter(\.hasReflowedText).map(\.text).joined(separator: " ")
    for note in ["chronic-disease", "nchs/fastats", "grasp/diabetes", "physical-activity"] {
        #expect(reflowed.contains(note), "note lost to the footer band: \(note)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/246")) func onlyAFullMeasureBandAtAPageEdgeIsFurniture() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    #expect(LayoutReconstructor.isEdgeBand(CGRect(x: 0, y: 0, width: 612, height: 80), bounds: bounds))
    #expect(LayoutReconstructor.isEdgeBand(CGRect(x: 0, y: 712, width: 612, height: 80), bounds: bounds))
    // A figure the width of the measure but away from either edge is not furniture, and neither
    // is a band that leaves a column of the measure free.
    #expect(!LayoutReconstructor.isEdgeBand(CGRect(x: 0, y: 300, width: 612, height: 80), bounds: bounds))
    #expect(!LayoutReconstructor.isEdgeBand(CGRect(x: 0, y: 0, width: 300, height: 80), bounds: bounds))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/59")) func aCropReleasesTheHalfOfAWordItTook() {
    // Replay Clocks page 8 to the point: a figure caption hyphenated over two lines, with the
    // crop's lower edge 0.49 pt above the second line, so the first half was taken and the second
    // reflowed alone between two figures.
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let first = TextLine(text: "Figure 7: tau vs E when varying delta, alpha = 40 mes-",
                         rect: CGRect(x: 53.8, y: 469.99, width: 241.9, height: 8.47), fontSize: 8)
    let second = TextLine(text: "sages/second.",
                          rect: CGRect(x: 53.8, y: 459.03, width: 54.1, height: 8.47), fontSize: 8)
    var body: [TextLine] = []
    for i in 0..<6 {
        body.append(TextLine(text: "Ordinary prose establishing this page's body size and measure.",
                             rect: CGRect(x: 53.8, y: 400 - Double(i) * 12, width: 300, height: 9), fontSize: 8))
    }
    let page = PageContent(number: 8, bounds: bounds, lines: [first, second] + body, graphics: [])
    let crop = CGRect(x: 51.8, y: 467.99, width: 245.9, height: 118.4)
    #expect(LayoutReconstructor.takes(crop, first))
    #expect(!LayoutReconstructor.takes(crop, second))
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(crop, "figure")], vocabulary: [], warnings: &warnings)
    let texts = blocks.filter(\.hasReflowedText).map(\.text)
    // Both halves reflow, in one block: no fragment of the caption becomes body prose of its own.
    // Whether the hyphen itself goes is `HyphenRepair`'s decision and needs the book's vocabulary,
    // which this page does not carry.
    #expect(!texts.contains { $0.trimmingCharacters(in: .whitespaces) == "sages/second." },
            Comment(rawValue: texts.joined(separator: " | ")))
    #expect(texts.contains { $0.contains("mes") && $0.contains("sages/second.") },
            Comment(rawValue: texts.joined(separator: " | ")))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/255"))
func aCropNeverAdmitsALineOfTheBooksOwnProse() {
    let body = "A strong alliance has long existed between the two departments."
    let label = "Figure 4"
    let sentence = TextLine(text: body, rect: CGRect(x: 40, y: 300, width: 300, height: 12), fontSize: 10)
    let caption = TextLine(text: label, rect: CGRect(x: 40, y: 300, width: 60, height: 12), fontSize: 10)
    #expect(LayoutReconstructor.releasesProse(sentence, language: "en"))
    #expect(!LayoutReconstructor.releasesProse(caption, language: "en"))
    // Recognition's reading of the CIA report's handwritten tables is not prose, in a book that
    // declares English: the word test refuses it where the shape alone would not.
    let noise = TextLine(text: "0/iLE 1112£ E/(19U/,£r//?/Z/ <?E O,fJE(!r .S/6/(T//I/GS Ec?~ /ILi f'EARS",
                         rect: CGRect(x: 40, y: 300, width: 300, height: 12), fontSize: 10)
    #expect(LayoutReconstructor.readsAsSentence(noise))
    #expect(!LayoutReconstructor.releasesProse(noise, language: "en"))
    // An English lexicon judges nothing about another script, so shape alone decides there.
    let chinese = TextLine(text: "如果您要从工作表中查找的金额至少为 19,100 美元, 但低于 19,104 美元，并且您没有",
                           rect: CGRect(x: 40, y: 300, width: 300, height: 12), fontSize: 10)
    #expect(LayoutReconstructor.releasesProse(chinese, language: "en") == LayoutReconstructor.readsAsSentence(chinese))
    #expect(LayoutReconstructor.releasesProse(noise, language: "zh-Hans"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/255"))
func aSentenceACropCannotCutAroundStaysInTheProse() {
    // A picture with a sentence of the page's own prose running across its lower edge, which no
    // cut can clear while still holding the picture.
    var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 500),
                           lines: [], graphics: [CGRect(x: 40, y: 260, width: 320, height: 120)])
    page.pictures = page.graphics
    page.lines = [
        TextLine(text: "A strong alliance has long existed between the two departments.",
                 rect: CGRect(x: 30, y: 250, width: 340, height: 12), fontSize: 10),
        TextLine(text: "Figure 4", rect: CGRect(x: 40, y: 238, width: 60, height: 12), fontSize: 10),
    ]
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let sentence = page.lines[0]
    #expect(!crops.contains { LayoutReconstructor.takes($0, sentence) },
            "the book's own sentence must reflow, not travel into the picture")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.map { ($0, "image-1") },
                                            vocabulary: [], warnings: &warnings)
    #expect(blocks.contains { $0.text.contains("A strong alliance") })
}

/// The CIA report's page 203, set as its text layer hands it back: three tables down the page,
/// each a column-header row beside the rule the page paints in its margin, a second header row
/// over the stub column of evaluations, and rows of cells in two column groups. Every row begins
/// a piece on the same edges, and the header rows print one label once per column.
private func columnHeaderPage(
    header: String = "Number Per Cent Number Per Cent Nuntler Per Cent Number Per Celt"
) -> PageContent {
    var page = PageContent(number: 203, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: [], graphics: [CGRect(x: 200, y: 344, width: 162, height: 22)])
    page.pictures = page.graphics
    let stub = ["0-Balloon", "1-Astronomical", "2-Aircraft", "3-Light Phenom.", "4-Birds", "Total"]
    let cells = ["26 8 34 195 60 255", "13 5 18 95 35 130", "4 1 5 30 10 40",
                 "1 0 1 5 0 5", "0 2 2 0 15 15", "44 16 60 325 120 445"]
    var lines: [TextLine] = []
    for table in 0..<3 {
        let top = CGFloat(680 - table * 170)
        lines.append(TextLine(text: "I", rect: CGRect(x: 84, y: top, width: 3, height: 6), fontSize: 6))
        lines.append(TextLine(text: header,
                              rect: CGRect(x: 144, y: top, width: 372, height: 6), fontSize: 6))
        lines.append(TextLine(text: "Evaluation",
                              rect: CGRect(x: 94, y: top - 8, width: 19, height: 6), fontSize: 6))
        lines.append(TextLine(text: "Certain Doubtful Total Certain Doubtful Total",
                              rect: CGRect(x: 126, y: top - 8, width: 200, height: 6), fontSize: 6))
        lines.append(TextLine(text: "ertain Ooubtfut Total Certain Doubtful Total",
                              rect: CGRect(x: 335, y: top - 8, width: 197, height: 6), fontSize: 6))
        for (index, label) in stub.enumerated() {
            let y = top - 20 - CGFloat(index * 10)
            lines.append(TextLine(text: label, rect: CGRect(x: 85, y: y, width: 30, height: 6), fontSize: 6))
            lines.append(TextLine(text: cells[index], rect: CGRect(x: 126, y: y, width: 200, height: 6), fontSize: 6))
            lines.append(TextLine(text: cells[(index + 1) % cells.count],
                                  rect: CGRect(x: 335, y: y, width: 197, height: 6), fontSize: 6))
        }
    }
    page.lines = lines
    return page
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/257"))
func aCropNeverReleasesATablesColumnHeaderToTheProse() {
    let page = columnHeaderPage()
    let body = max(4, LayoutReconstructor.bodySize(page.lines))
    let headers = TableRegionDetector.columnHeaders(in: page, body: body)
    let header = page.lines.first { $0.text.hasPrefix("Number Per Cent") }!
    // The word test admits it: every token is an English word, and it reads as a sentence.
    #expect(LayoutReconstructor.readsAsSentence(header))
    #expect(LayoutReconstructor.releasesProse(header, language: "en"))
    // Read as what it is — the label of the columns below it — it is never released (#257).
    #expect(headers.contains(header.rect))
    #expect(!LayoutReconstructor.releasesProse(header, language: "en", columnHeaders: headers))
    // The third table's own picture lies across its header, and no cut clears the header while
    // still holding the picture. Before #255 the crop grew and took it; #255 let it out into the
    // prose; read as the label of its columns it goes back to the picture of its table.
    let lowest = page.lines.last { $0.text.hasPrefix("Number Per Cent") }!
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(crops.contains { LayoutReconstructor.takes($0, lowest) },
            "the table's own column header belongs to the picture of its table")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.map { ($0, "image-1") },
                                            vocabulary: [], warnings: &warnings)
    // Two of the three tables have no picture lying across their header, so those two headers
    // reflow as they did before: this rule refuses a release, it does not hide a line no crop
    // was reaching for.
    #expect(blocks.count(where: { $0.text.contains("Nuntler Per Cent") }) == 2,
            Comment(rawValue: blocks.map(\.text).joined(separator: " | ")))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/257"))
func aColumnHeaderPrintsOneLabelUnderEachColumn() {
    // The report's headers, exactly as its inherited text layer spells them.
    #expect(TableRegionDetector.printsOneColumnLabel(
        "Number Per Cent Number Per Cent Nuntler Per Cent Number Per Celt"))
    #expect(TableRegionDetector.printsOneColumnLabel(
        "Certain Doubtful Total Certain Doubtful Total ertain Ooubtfut Total Certain Doubtful Total"))
    #expect(TableRegionDetector.printsOneColumnLabel("-Variable Total Const Variable Total"))
    // Prose never prints one group over and over, whatever columns the page sets it in.
    #expect(!TableRegionDetector.printsOneColumnLabel(
        "A strong alliance has long existed between USDA and DOD"))
    #expect(!TableRegionDetector.printsOneColumnLabel(
        "I All of the above calculations were made with IBM equipment. Sines,"))
    #expect(!TableRegionDetector.printsOneColumnLabel(
        "travels from person to person. Only the females feed on blood."))
    // The nearest miss the corpus holds: a worked exercise in Wallace's algebra, three repeated
    // words in four where a header needs four in five.
    #expect(!TableRegionDetector.printsOneColumnLabel("10 lbs of nuts and 20 lbs of chocolate"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/262"),
      .bug("https://github.com/vocaro/PDFReflowLib/issues/257"))
func aColumnLabelTheRecognizerSplitOrJoinedIsOneLabelStill() {
    // The two headers #257 could not read, as the report's inherited layer spells them: page 151
    // broke `Number` into `lt` and `mber` and closed `Per Cent` up into `Percent`, and page 241
    // closed it up into `PerCeat`. Word for word neither has a counterpart to be near; read as
    // the label's letters in order, with the spaces the recognizer moved taken out, both are
    // `Number Per Cent` twice (#262).
    #expect(TableRegionDetector.printsOneColumnLabel("! lt>mber Per Cent Number Percent"))
    #expect(TableRegionDetector.printsOneColumnLabel("I Number Per Cent Number PerCeat"))
    // The same spoiling elsewhere in the book, which the word reading also missed.
    #expect(TableRegionDetector.printsOneColumnLabel("! r.imber Per Cent Number Per Cent"))
    #expect(TableRegionDetector.printsOneColumnLabel("Number Percent Nuoi>er Percent"))
    #expect(TableRegionDetector.printsOneColumnLabel("Co\"\"t Variable Total Const Variable Total"))
    // Everything #257 read is read still.
    #expect(TableRegionDetector.printsOneColumnLabel(
        "Number Per Cent Number Per Cent Nuntler Per Cent Number Per Celt"))
    #expect(TableRegionDetector.printsOneColumnLabel(
        "Certain Doubtful Total Certain Doubtful Total ertain Ooubtfut Total Certain Doubtful Total"))
    #expect(TableRegionDetector.printsOneColumnLabel("-Variable Total Const Variable Total"))
    // The five lines #255 was landed for — two sentences of the report's own prose and three
    // figure titles — are none of them a repeated label, letters or words.
    for released in ["I All of the above calculations were made with IBM equipment. Sines,",
                     "I Having found the angle ZS, the bearing of the sun ( angle B} was ob",
                     "FIGURE 2 DISTRIBUTION OF EVALUATIONS OF OBJECT,",
                     "UNIT, AND ALL SIGHTINGS FOR ALL YEARS I",
                     "FIGURE 8 DISTRIBUTION OF OBJECT SIGHTINGS BY SIGHTING"] {
        #expect(!TableRegionDetector.printsOneColumnLabel(released), Comment(rawValue: released))
    }
    // Nor is the magazine's prose, whose columns give every row of it a table's shape, nor the
    // nearest miss in Wallace's algebra.
    for prose in ["A strong alliance has long existed between USDA and DOD",
                  "tween USDA and DOD as far back as",
                  "interrupt malaria transmission in the South",
                  "Human factors science, or human factors technologies,",
                  "the miniature aircraft up or down to align the miniature aircraft with",
                  "10 lbs of nuts and 20 lbs of chocolate"] {
        #expect(!TableRegionDetector.printsOneColumnLabel(prose), Comment(rawValue: prose))
    }
    // Dropping the printed spaces is what reads the spoiled label, and it is also what would let
    // arithmetic in. A label is written in words: a line holding a group that is only figures is
    // the table's own data or an equation, whatever its letters repeat. The IRS publication's
    // earned-income tables and Wallace's exercises are full of both.
    for figures in ["0 0 0 200", "0 1,192 3,019 3,913", "1,050 1,100", "3r + 6+ 3r =30",
                    "13)r2 + 3r + 2", "5) (1− 7n)(1+ 7n)"] {
        #expect(!TableRegionDetector.printsOneColumnLabel(figures), Comment(rawValue: figures))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/262"))
func aCropKeepsAColumnHeaderTheRecognizerSpoiledTheRepetitionOf() {
    // Page 151's table, set as page 203's is, with page 151's own header over it.
    let page = columnHeaderPage(header: "! lt>mber Per Cent Number Percent")
    let body = max(4, LayoutReconstructor.bodySize(page.lines))
    let headers = TableRegionDetector.columnHeaders(in: page, body: body)
    let header = page.lines.first { $0.text.hasPrefix("! lt>mber") }!
    // Every token reads as a word, so #255's test releases it into the prose beside the picture
    // of its own table.
    #expect(LayoutReconstructor.readsAsSentence(header))
    #expect(LayoutReconstructor.releasesProse(header, language: "en"))
    // Read as the label of its columns it is never released, and the crop over the lowest table
    // takes its header back.
    #expect(headers.contains(header.rect))
    #expect(!LayoutReconstructor.releasesProse(header, language: "en", columnHeaders: headers))
    let lowest = page.lines.last { $0.text.hasPrefix("! lt>mber") }!
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(crops.contains { LayoutReconstructor.takes($0, lowest) },
            "the table's own column header belongs to the picture of its table")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.map { ($0, "image-1") },
                                            vocabulary: [], warnings: &warnings)
    #expect(blocks.count(where: { $0.text.contains("lt>mber Per Cent") }) == 2,
            Comment(rawValue: blocks.map(\.text).joined(separator: " | ")))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/257"),
      .bug("https://github.com/vocaro/PDFReflowLib/issues/255"))
func prosePDFKitHandsBackBesideAnotherColumnIsStillReleased() {
    // The magazine sets three columns whose lines PDFKit returns on shared baselines, so every
    // row of its running prose holds pieces the page kept apart on an edge every other row
    // states. Read on that geometry alone this rule buries 17,340 characters of its articles;
    // the header's own words are what keep it out of them (#257).
    var page = PageContent(number: 5, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: [], graphics: [CGRect(x: 30, y: 400, width: 200, height: 120)])
    page.pictures = page.graphics
    let columns = [
        ["General Douglas MacArthur was quoted", "as saying, it is going to be a very long",
         "war if for every division I have facing the", "enemy, I have one sick in the hospital and"],
        ["tween USDA and DOD as far back as", "1932, when an entomological research",
         "laboratory was established in Orlando,", "Florida, to combat mosquitoes, filth flies,"],
        ["interrupt malaria transmission in the South", "Pacific to protect soldiers stationed there.",
         "The Deployed War-Fighter Protection", "research program was implemented in 2004"],
    ]
    for (column, texts) in columns.enumerated() {
        for (row, text) in texts.enumerated() {
            page.lines.append(TextLine(text: text,
                                       rect: CGRect(x: CGFloat(36 + column * 184), y: CGFloat(520 - row * 13),
                                                    width: 172, height: 13), fontSize: 10))
        }
    }
    let body = max(4, LayoutReconstructor.bodySize(page.lines))
    let headers = TableRegionDetector.columnHeaders(in: page, body: body)
    for line in page.lines {
        #expect(!headers.contains(line.rect), Comment(rawValue: line.text))
        #expect(LayoutReconstructor.releasesProse(line, language: "en", columnHeaders: headers),
                Comment(rawValue: line.text))
    }
}
