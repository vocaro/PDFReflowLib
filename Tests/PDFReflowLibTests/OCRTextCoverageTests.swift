import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import PDFReflowLib

// #116: a recognition that silently drops text leaves text-shaped ink outside every line box.

/// A letter page rendered at the converter's 180 DPI (2.5 pixels per point).
private struct SyntheticPage {
    static let scale = 2.5
    static let size = CGSize(width: 612, height: 792)
    let context: CGContext
    /// Normalized lower-left boxes of the text lines drawn so far.
    var lineBoxes: [CGRect] = []

    init() {
        context = CGContext(data: nil, width: Int(Self.size.width * Self.scale), height: Int(Self.size.height * Self.scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: Self.scale, y: Self.scale)
    }

    /// Draws one line of text with its baseline at `y` points and records its box as Vision would.
    mutating func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat = 10, white: Bool = false) {
        pdfKitGated {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let color = CGColor(gray: white ? 1 : 0, alpha: 1)
            let attributed = NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
            lineBoxes.append(CGRect(x: x / Self.size.width, y: (y - descent) / Self.size.height,
                                    width: width / Self.size.width, height: (ascent + descent) / Self.size.height))
        }
    }

    mutating func paragraphs(lines: Int, top: CGFloat = 740) {
        let words = "Recognition quality depends on the scan, the typeface and the compiled models in use"
        for index in 0..<lines {
            text(words, x: 72, y: top - CGFloat(index) * 14)
        }
    }

    func measure(lines: [CGRect], excluded: [CGRect] = []) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.measure(image: context.makeImage()!, lines: lines, excluded: excluded,
                                pixelsPerPoint: Self.scale)
    }
}

@Test func coverageOfACompleteRecognitionShowsNoLoss() {
    var page = SyntheticPage()
    page.paragraphs(lines: 40)
    let measurement = page.measure(lines: page.lineBoxes)
    #expect(measurement.textRows >= 40)
    #expect(measurement.uncoveredRows == 0)
    #expect(measurement.uncoveredFraction < 0.02)
    #expect(!measurement.indicatesLoss)
}

@Test func coverageReadsOtherPixelFormatsLikeTheConvertersRaster() throws {
    var page = SyntheticPage()
    page.paragraphs(lines: 40)
    let rgba = try #require(page.context.makeImage())
    // A gray copy takes the drawing path instead of reading RGBA bytes directly.
    let gray = try #require(CGContext(data: nil, width: rgba.width, height: rgba.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    gray.draw(rgba, in: CGRect(x: 0, y: 0, width: rgba.width, height: rgba.height))
    let grayImage = try #require(gray.makeImage())
    // Text on a transparent background, alpha first and little-endian: read over white (#129).
    let bgra = try #require(CGContext(data: nil, width: rgba.width, height: rgba.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    let words = "Recognition quality depends on the scan, the typeface and the compiled models in use"
    pdfKitGated {
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]))
        bgra.scaleBy(x: SyntheticPage.scale, y: SyntheticPage.scale)
        for index in 0..<40 {
            bgra.textPosition = CGPoint(x: 72, y: 740 - CGFloat(index) * 14)
            CTLineDraw(line, bgra)
        }
    }
    let transparentImage = try #require(bgra.makeImage())
    let kept = Array(page.lineBoxes.prefix(8))
    for lines in [page.lineBoxes, kept] {
        let direct = OCRTextCoverage.measure(image: rgba, lines: lines, pixelsPerPoint: SyntheticPage.scale)
        for other in [grayImage, transparentImage] {
            let converted = OCRTextCoverage.measure(image: other, lines: lines, pixelsPerPoint: SyntheticPage.scale)
            #expect(direct.indicatesLoss == converted.indicatesLoss)
            #expect(abs(direct.textRows - converted.textRows) <= 2)
            #expect(abs(direct.uncoveredFraction - converted.uncoveredFraction) < 0.05)
        }
    }
}

@Test func retriedRecognitionKeepsOnlyTableRegionsBothRecognitionsFound() {
    // #129: the retry's table regions become images only where the first recognition saw a table.
    let upper = CGRect(x: 0.1, y: 0.55, width: 0.8, height: 0.35)
    let lower = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.35)
    let lowerSeenFirst = CGRect(x: 0.12, y: 0.12, width: 0.7, height: 0.2)
    // A retry that finds a table the first recognition missed adds no image.
    #expect(OCRReader.retainedTables(first: [], retry: [upper, lower]).isEmpty)
    // A table both saw keeps the retry's region; one only the first saw is not kept either.
    #expect(OCRReader.retainedTables(first: [lowerSeenFirst], retry: [upper, lower]) == [lower])
    #expect(OCRReader.retainedTables(first: [upper, lowerSeenFirst], retry: [lower]) == [lower])
    #expect(OCRReader.retainedTables(first: [upper], retry: []).isEmpty)
}

@Test func coverageDetectsEightyPercentOfLinesDropped() {
    var page = SyntheticPage()
    page.paragraphs(lines: 40)
    // A dropped paragraph run: Vision kept the first four and last four lines.
    let kept = Array(page.lineBoxes.prefix(4) + page.lineBoxes.suffix(4))
    let measurement = page.measure(lines: kept)
    #expect(measurement.uncoveredRows >= 30)
    #expect(measurement.uncoveredFraction > 0.7)
    #expect(measurement.indicatesLoss)
    // Scattered losses of the same share are found too, and nothing recognized at all is loss.
    let scattered = page.lineBoxes.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)
    #expect(page.measure(lines: scattered).indicatesLoss)
    #expect(page.measure(lines: []).indicatesLoss)
}

@Test func coverageStaysQuietOnASparseComicLikePage() {
    var page = SyntheticPage()
    let context = page.context
    // Panel borders, a dark filled scene, a window grid over a mid-gray facade, crowd speckle.
    context.setStrokeColor(gray: 0, alpha: 1)
    context.setLineWidth(4)
    context.stroke(CGRect(x: 30, y: 420, width: 552, height: 340))
    context.stroke(CGRect(x: 30, y: 30, width: 552, height: 370))
    context.setFillColor(gray: 0.1, alpha: 1)
    context.fill(CGRect(x: 40, y: 40, width: 250, height: 200))
    context.setFillColor(gray: 0.55, alpha: 1)
    context.fill(CGRect(x: 320, y: 60, width: 240, height: 320))
    context.setFillColor(gray: 0.05, alpha: 1)
    for row in 0..<14 {
        for column in 0..<9 {
            context.fill(CGRect(x: 330 + CGFloat(column) * 25, y: 70 + CGFloat(row) * 21, width: 12, height: 9))
        }
    }
    var generator = SystemRandomNumberGeneratorSeeded(seed: 116)
    for _ in 0..<400 {
        let x = CGFloat(generator.next() % 540) + 40, y = CGFloat(generator.next() % 300) + 440
        let w = CGFloat(generator.next() % 4) + 1, h = CGFloat(generator.next() % 4) + 1
        context.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    // A balloon with two short recognized lines.
    context.setFillColor(gray: 1, alpha: 1)
    context.fillEllipse(in: CGRect(x: 60, y: 600, width: 220, height: 110))
    context.strokeEllipse(in: CGRect(x: 60, y: 600, width: 220, height: 110))
    page.text("I'M NURSE EVANS... JUST", x: 100, y: 665, size: 11)
    page.text("FOLLOW ME!", x: 130, y: 648, size: 11)
    let recognized = page.measure(lines: page.lineBoxes)
    #expect(!recognized.indicatesLoss, "\(recognized)")
    // Even with the balloon unread, a page this sparse has too little text to call a loss.
    #expect(!page.measure(lines: []).indicatesLoss)
}

@Test func coverageIgnoresInkInsideExcludedRegions() {
    var page = SyntheticPage()
    page.paragraphs(lines: 30)
    // The lower 20 lines form a table region that becomes an image: its ink is not counted.
    let table = CGRect(x: 0.05, y: 0, width: 0.9, height: (740 - 9.5 * 14) / 792)
    let upper = Array(page.lineBoxes.prefix(10))
    #expect(page.measure(lines: upper).indicatesLoss)
    #expect(!page.measure(lines: upper, excluded: [table]).indicatesLoss)
}

@Test func retryBandsMergeWithoutDuplicatingTheSharedStrip() {
    typealias Line = OCRReader.Recognition.Line
    // Top band covers page height 0.4...1.0 and bottom band 0.0...0.6 (band-normalized boxes).
    let top = OCRReader.Recognition(lines: [
        Line(text: "top", box: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.02), wraps: true),
        Line(text: "shared above split", box: CGRect(x: 0.1, y: 0.25, width: 0.5, height: 0.02), wraps: false),
        Line(text: "shared below split", box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02), wraps: false),
    ], tables: [CGRect(x: 0.2, y: 0.0, width: 0.6, height: 0.3)])
    let bottom = OCRReader.Recognition(lines: [
        Line(text: "shared above split", box: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.02), wraps: false),
        Line(text: "shared below split", box: CGRect(x: 0.1, y: 0.65, width: 0.5, height: 0.02), wraps: false),
        Line(text: "bottom", box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02), wraps: nil),
    ], tables: [CGRect(x: 0.2, y: 0.5, width: 0.6, height: 0.5)])
    let merged = OCRReader.mergeBands([(top, 0.4, 0.6), (bottom, 0.0, 0.6)])
    #expect(merged.lines.map(\.text) == ["top", "shared above split", "shared below split", "bottom"])
    #expect(merged.lines[0].wraps == true && merged.lines[3].wraps == nil)
    #expect(abs(merged.lines[0].box.minY - 0.88) < 1e-9)
    #expect(abs(merged.lines[3].box.minY - 0.06) < 1e-9)
    // One table crossing the split, seen partly in each band, becomes one region.
    #expect(merged.tables.count == 1)
    #expect(abs(merged.tables[0].minY - 0.3) < 1e-9 && abs(merged.tables[0].maxY - 0.6) < 1e-9)
}

@Test func coverageNoteDescribesRetryAndRemainingLoss() {
    #expect(OCRReader.coverageNote(retriedInBands: false, uncoveredTextFraction: nil, referencesDisabled: false) == "")
    #expect(OCRReader.coverageNote(retriedInBands: true, uncoveredTextFraction: nil, referencesDisabled: false)
            == " The first recognition left text-shaped ink outside every recognized line, so the page was recognized again in two overlapping bands.")
    #expect(OCRReader.coverageNote(retriedInBands: false, uncoveredTextFraction: 0.434, referencesDisabled: false)
            == " About 43% of the page's text-shaped ink is still outside every recognized line, so some text may be missing; compare the original page image.")
    #expect(OCRReader.coverageNote(retriedInBands: true, uncoveredTextFraction: 0.26, referencesDisabled: true)
            .hasSuffix("About 26% of the page's text-shaped ink is still outside every recognized line, so some text may be missing; compare the source PDF."))
}

private struct SystemRandomNumberGeneratorSeeded: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }
}
