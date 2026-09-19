import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// #176: a page that reflows no word of its own, whose art is writing, is recognized like a page
// with no text layer at all; a page whose art is decoration is left alone. The ink that decides
// is measured against the page's own background, so a slide printed white on dark is not blind.

// MARK: - Ink polarity

/// A raster of `background` luminance with `rows` rows of five hollow 10x12 boxes of `ink`
/// luminance, which `OCRTextCoverage` reads as glyph-sized components standing in a row.
private func raster(width: Int = 400, height: Int = 200, background: UInt8, ink: UInt8,
                    rows: Int, top: Int = 20) -> OCRTextCoverage.GrayRaster {
    var pixels = [UInt8](repeating: background, count: width * height)
    for row in 0..<rows {
        let y0 = top + row * 40
        for glyph in 0..<5 {
            let x0 = 20 + glyph * 24
            for y in y0..<(y0 + 12) {
                for x in x0..<(x0 + 10) where x == x0 || x == x0 + 9 || y == y0 || y == y0 + 11 {
                    pixels[y * width + x] = ink
                }
            }
        }
    }
    return OCRTextCoverage.GrayRaster(width: width, height: height, pixels: pixels)
}

@Test func darkPageWithNoInkRowsIsMeasuredAgainstItsOwnBackground() {
    // White writing on a dark ground: every pixel of the ground is below any ink threshold, so
    // the darker side is one page-sized component and no row is found until the page is inverted.
    let light = raster(background: 40, ink: 255, rows: 3)
    #expect(light.inkIsBackground())
    #expect(OCRTextCoverage.measure(light, lines: [], excluded: [], pixelsPerPoint: 1).textRows == 3)
    // Control: the same writing dark on white needs no inversion and reads the same rows.
    let dark = raster(background: 255, ink: 0, rows: 3)
    #expect(!dark.inkIsBackground())
    #expect(OCRTextCoverage.measure(dark, lines: [], excluded: [], pixelsPerPoint: 1).textRows == 3)
    // Control: a dark page with no writing on it stays empty both ways.
    let blank = raster(background: 40, ink: 255, rows: 0)
    #expect(OCRTextCoverage.measure(blank, lines: [], excluded: [], pixelsPerPoint: 1).textRows == 0)
}

@Test func aPageWhoseDarkInkAlreadyFormsRowsIsNeverInverted() {
    // A mostly dark page — a full-bleed photograph — whose printed text is dark on a light panel.
    var pixels = [UInt8](repeating: 20, count: 400 * 200)
    for y in 0..<90 { for x in 0..<400 { pixels[y * 400 + x] = 250 } }
    var page = OCRTextCoverage.GrayRaster(width: 400, height: 200, pixels: pixels)
    let writing = raster(background: 250, ink: 0, rows: 2)
    for y in 0..<80 { for x in 0..<400 { page.pixels[y * 400 + x] = writing.pixels[y * 400 + x] } }
    #expect(page.inkIsBackground())  // more than half the page is darker than the threshold
    let measured = OCRTextCoverage.measure(page, lines: [], excluded: [], pixelsPerPoint: 1)
    #expect(measured.textRows == 2)  // read as printed, not inverted
}

// MARK: - The rule

@Test func aLayerWithNoLetterReflowsNoWords() {
    func lines(_ texts: [String]) -> [TextLine] {
        texts.map { TextLine(text: $0, rect: CGRect(x: 0, y: 0, width: 10, height: 10), fontSize: 10) }
    }
    #expect(TextLayerPlausibility.reflowsNoWords([]))
    #expect(TextLayerPlausibility.reflowsNoWords(lines(["5"])))          // a folio
    #expect(TextLayerPlausibility.reflowsNoWords(lines(["10-12"])))      // a section folio
    #expect(TextLayerPlausibility.reflowsNoWords(lines(["37) 5 2 √ + 3 √", "38) 3"])))  // an answer key
    #expect(!TextLayerPlausibility.reflowsNoWords(lines(["5", "Goals"])))
    #expect(!TextLayerPlausibility.reflowsNoWords(lines(["a"])))
}

@Test func drawnTextNeedsMoreThanOneRowOutsideTheLayer() {
    func measurement(_ uncovered: Int) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.Measurement(textRows: 40, uncoveredRows: uncovered, textInk: 100, uncoveredInk: 100)
    }
    #expect(TextLayerPlausibility.carriesDrawnText(measurement(2)))
    #expect(TextLayerPlausibility.carriesDrawnText(measurement(3)))
    #expect(!TextLayerPlausibility.carriesDrawnText(measurement(1)))  // one row is a figure's label
    #expect(!TextLayerPlausibility.carriesDrawnText(measurement(0)))  // an answer key the layer covers
    // Only English books are judged, and a layer holding a word is never rendered.
    var renders = 0
    let writing = measurement(3)
    #expect(TextLayerPlausibility.judgeImageOnly(lines: [], language: "en") { renders += 1; return writing })
    #expect(!TextLayerPlausibility.judgeImageOnly(lines: [], language: "ar") { renders += 1; return writing })
    let worded = [TextLine(text: "Goals", rect: CGRect(x: 0, y: 0, width: 10, height: 10), fontSize: 10)]
    #expect(!TextLayerPlausibility.judgeImageOnly(lines: worded, language: "en") { renders += 1; return writing })
    #expect(renders == 1)
}

// MARK: - End to end

/// A one-slide PDF: a full-bleed `background` fill, `sentence` drawn as filled glyph outlines in
/// `ink` (no text layer at all), an optional real-text `folio`, and optional decoration instead of
/// the sentence. This is how Google Slides exported slide 5 of the Earthdata deck.
private func drawnTextPDF(sentence: [String], folio: String?, background: CGFloat,
                          ink: CGFloat, decoration: Bool = false) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let font = pdfKitGated { CTFontCreateWithName("Helvetica" as CFString, 40, nil) }
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.setFillColor(gray: background, alpha: 1)
    pdf.fill(page)
    pdf.setFillColor(gray: ink, alpha: 1)
    pdfKitGated {
        if decoration {
            // Art with no writing in it: three plain discs, the size of the sentence's words.
            for index in 0..<3 {
                pdf.fillEllipse(in: CGRect(x: 120 + index * 180, y: 160, width: 120, height: 120))
            }
        } else {
            for (index, text) in sentence.enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let origin = CGPoint(x: 90, y: 240 - CGFloat(index) * 60)
                for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(), &glyphs)
                    CTRunGetPositions(run, CFRange(), &positions)
                    for (glyph, position) in zip(glyphs, positions) {
                        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                        var transform = CGAffineTransform(translationX: origin.x + position.x,
                                                          y: origin.y + position.y)
                        if let moved = path.copy(using: &transform) { pdf.addPath(moved) }
                    }
                }
                pdf.fillPath()
            }
        }
        if let folio {
            let small = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            pdf.textPosition = CGPoint(x: 680, y: 24)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: folio, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): small,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
        }
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

private let question = ["How do we support user analysis", "of very large data volumes?"]

private func reflow(_ data: Data, policy: ConversionOptions.OCRPolicy = .automatic) async throws
    -> (result: PDFReflowLibPipeline.Result, text: String) {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.pdf")
    try data.write(to: source)
    var options = ConversionOptions(); options.ocr = policy
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    return (result, result.document.blocks.map(\.text).joined(separator: " "))
}

@Test func aSlideWhoseOnlyWritingIsDrawnWhiteOnDarkIsRecognized() async throws {
    let slide = try drawnTextPDF(sentence: question, folio: "5", background: 0.25, ink: 1)
    let (result, text) = try await reflow(slide)
    #expect(result.recognizedPageCount == 1)
    #expect(result.warnings.contains { $0.code == .ocrUsed && $0.page == 1 })
    #expect(text.lowercased().contains("large data volumes"), "\(text)")
    // The policy that keeps image-backed text still recognizes a page that has no text layer.
    let (kept, keptText) = try await reflow(slide, policy: .automaticKeepingImageBackedText)
    #expect(kept.recognizedPageCount == 1)
    #expect(keptText.lowercased().contains("large data volumes"), "\(keptText)")
    // `.never` recognizes nothing: the slide keeps its art and reflows no sentence.
    let (never, neverText) = try await reflow(slide, policy: .never)
    #expect(never.recognizedPageCount == 0)
    #expect(!neverText.lowercased().contains("large data volumes"), "\(neverText)")
}

@Test func theSameSlidePrintedDarkOnLightIsRecognizedToo() async throws {
    let slide = try drawnTextPDF(sentence: question, folio: "5", background: 1, ink: 0)
    let (result, text) = try await reflow(slide)
    #expect(result.recognizedPageCount == 1)
    #expect(text.lowercased().contains("large data volumes"), "\(text)")
}

@Test func writingInsideAPhotographIsNotThePageWriting() async throws {
    // A page whose only writing is inside a picture — the Arabic civics cards' blackboard photo,
    // and Mount Rushmore, whose strata the ink test reads as rows of glyphs. Its crop keeps it.
    let photographed = try photographPDF(sentence: question, folio: "56")
    let (result, text) = try await reflow(photographed)
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
    #expect(!text.lowercased().contains("large data volumes"), "\(text)")
}

/// The same slide with its sentence inside a placed raster rather than drawn on the page.
private func photographPDF(sentence: [String], folio: String) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let scale = 3.0
    let picture = CGRect(x: 60, y: 90, width: 600, height: 240)
    let bitmap = try #require(CGContext(data: nil, width: Int(picture.width * scale),
        height: Int(picture.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    bitmap.setFillColor(gray: 0.25, alpha: 1)
    bitmap.fill(CGRect(x: 0, y: 0, width: picture.width * scale, height: picture.height * scale))
    bitmap.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        let large = CTFontCreateWithName("Helvetica" as CFString, 40 * scale, nil)
        for (index, text) in sentence.enumerated() {
            bitmap.textPosition = CGPoint(x: 30 * scale, y: (150 - CGFloat(index) * 60) * scale)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): large,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), bitmap)
        }
    }
    let image = try #require(bitmap.makeImage())
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.setFillColor(gray: 0.25, alpha: 1)
    pdf.fill(page)
    pdf.draw(image, in: picture)
    pdf.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        let small = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        pdf.textPosition = CGPoint(x: 670, y: 24)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: folio, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): small,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

/// The drawn-text slide, but its background is an actual placed raster image spanning the page
/// (not a solid content-stream fill, which `GraphicsReader` does not track as a region) so
/// `imageBackedText` (#93's own precondition) is true here, unlike `drawnTextPDF`'s pages. Its
/// only real text-layer line is the folio, so it also satisfies #176's `reflowsNoWords`
/// candidacy — the two features' preconditions overlap on this one page, where #7's
/// `comparesLayer` cannot reach (see `misreadInPlaceAndReflowsNoWordsCannotBothHoldForTheSameLines`).
/// The sentence is drawn on top of, and spatially within, that same full-page placed image.
private func drawnTextOverPlacedImagePDF(sentence: [String], folio: String) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let bitmap = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    bitmap.setFillColor(gray: 0.25, alpha: 1)
    bitmap.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let image = try #require(bitmap.makeImage())
    let font = pdfKitGated { CTFontCreateWithName("Helvetica" as CFString, 40, nil) }
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.draw(image, in: page)
    pdf.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        for (index, text) in sentence.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let origin = CGPoint(x: 90, y: 240 - CGFloat(index) * 60)
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                for (glyph, position) in zip(glyphs, positions) {
                    guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                    var transform = CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y)
                    if let moved = path.copy(using: &transform) { pdf.addPath(moved) }
                }
            }
            pdf.fillPath()
        }
        let small = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        pdf.textPosition = CGPoint(x: 680, y: 24)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: folio, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): small,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

@Test func aPageWhoseOnlyRowsSitInsideAFullPagePlacedImageIsNotRecognizedEitherWay() async throws {
    // Verifies, rather than assumes, how #93's ink-test path and #176's drawnText candidacy
    // interact when their preconditions overlap (imageBackedText true, and the layer's only line
    // a folio). They do not double-fire and neither wrongly recognizes the page: #93's ink test
    // needs 7 uncovered rows (`minimumUncoveredRows`) and this two-line sentence supplies only 2,
    // so it stays nil regardless; #176's own, lower threshold (2 rows, `minimumImageOnlyRows`)
    // would otherwise be cleared by the same two rows, but `measureInk`'s `excluding: placedImages`
    // (the same exclusion `writingInsideAPhotographIsNotThePageWriting` relies on) removes ink
    // inside the placed image's bounds from the count. Because the background image spans the
    // whole page, that exclusion also removes the sentence drawn on top of it, so drawnText's own
    // ink test finds no rows either. The page is correctly left exactly as extracted (folio only,
    // preserved crops), not silently recognized by one path when the other's precondition holds,
    // and not double-warned.
    let slide = try drawnTextOverPlacedImagePDF(sentence: question, folio: "5")
    let (result, text) = try await reflow(slide)
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
    #expect(!result.warnings.contains { $0.code == .implausibleTextLayer })
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(!text.lowercased().contains("large data volumes"), "\(text)")
    #expect(text.contains("5"))
}

@Test func decorativeArtWithoutWritingIsNotRecognized() async throws {
    // Negative control: the same dark slide, the same folio, art that is not writing.
    let decorated = try drawnTextPDF(sentence: [], folio: "5", background: 0.25, ink: 1, decoration: true)
    let (result, _) = try await reflow(decorated)
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
    // Negative control: a slide whose sentence is real text is never rendered or recognized.
    let native = try nativeSlidePDF()
    let (control, text) = try await reflow(native)
    #expect(control.recognizedPageCount == 0)
    #expect(!control.warnings.contains { $0.code == .ocrUsed })
    #expect(text.contains("How do we support user analysis"), "\(text)")
}

/// The same slide with its sentence drawn as ordinary visible text over the dark fill.
private func nativeSlidePDF() throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.setFillColor(gray: 0.25, alpha: 1)
    pdf.fill(page)
    pdf.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        for (index, text) in question.enumerated() {
            pdf.textPosition = CGPoint(x: 90, y: 240 - CGFloat(index) * 60)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
        }
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}
