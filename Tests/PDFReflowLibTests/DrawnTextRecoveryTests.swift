import Foundation
import Testing
@testable import PDFReflowLib

/// Captured from the checksum-pinned Earthdata source slide 5 on 2026-09-23. The raster
/// insignia contains NASA; the two-line question is drawn as paths; only 5 is native text.
private func earthdataSlide() -> (PageContent, OCRReader.Result) {
    let native = TextLine(text: "5", rect: CGRect(x: 693.264, y: 0.407, width: 7.620, height: 11.640), fontSize: 12)
    let bounds = CGRect(x: 0, y: 0, width: 720, height: 405)
    let page = PageContent(number: 5, bounds: bounds, lines: [native], graphics: [bounds],
        pictures: [CGRect(x: 12.037, y: 358.897, width: 44.454, height: 36.808)])
    let lines = [
        TextLine(text: "NASA", rect: CGRect(x: 15.615, y: 371.265, width: 33.654, height: 12.004), fontSize: 12.004),
        TextLine(text: "How do we support user analysis", rect: CGRect(x: 100.345, y: 196.534, width: 530.798, height: 36.922), fontSize: 36.922, wraps: true),
        TextLine(text: "of very large data volumes?", rect: CGRect(x: 144.278, y: 146.659, width: 446.111, height: 39.729), fontSize: 39.729, wraps: false)]
    return (page, OCRReader.Result(lines: lines, tables: []))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/192")) func earthdataWordmarkStaysInItsPictureAndBothDrawnRowsStayInTheCrop() {
    let (page, recognized) = earthdataSlide()
    let reading = DrawnTextRecovery.reading(recognized, on: page)
    #expect(reading.lines.map(\.text) == ["How do we support user analysis", "of very large data volumes?", "5"])
    var result = page
    PageDisposition.replaced(reading).apply(to: &result)
    DrawnTextRecovery.preserveArtwork(in: &result, extracted: page)
    #expect(result.graphics == page.pictures)
    #expect(result.recognizedArtwork.count == 1)
    for line in recognized.lines.dropFirst() {
        #expect(result.recognizedArtwork[0].contains(line.rect))
    }
    #expect(result.recognizedArtwork[0].height < page.bounds.height / 2)
    #expect(result.preservePageReference)
}

@Test func incidentalPictureTextAloneDoesNotTurnAFailedDrawnReadingIntoSuccess() {
    let (page, reading) = earthdataSlide()
    let filtered = DrawnTextRecovery.reading(OCRReader.Result(lines: [reading.lines[0]], tables: []), on: page)
    #expect(filtered.lines.isEmpty)
    let evidence = PageEvidence(requiresPageImage: false, hasText: true, characters: 1,
        replacementCharacters: 0, imageBackedText: true, damagedEncoding: false,
        implausibleLayer: nil, drawnText: true)
    let resolution = RecognitionPolicy.resolve(.recognize(.replace, keepCropsIfUnread: true),
        evidence: evidence, outcome: .read(filtered), judge: .english(language: "en"))
    #expect(resolution.disposition == .keptAsExtracted)
    #expect(resolution.warnings.contains(.ocrFailed(.unreadDrawnText)))
    var kept = page
    resolution.disposition.apply(to: &kept)
    #expect(kept == page)
    #expect(kept.recognizedArtwork.isEmpty)
}

@Test func drawnRecoveryRetainsNativeSpellingAndTheWholeOverlappingArtwork() {
    var (page, reading) = earthdataSlide()
    page.lines = [TextLine(text: "Goals", rect: CGRect(x: 100, y: 300, width: 50, height: 12), fontSize: 12)]
    reading.lines.append(TextLine(text: "Goa1s", rect: page.lines[0].rect, fontSize: 12))
    let artwork = CGRect(x: 90, y: 130, width: 550, height: 120)
    page.graphics.append(artwork)
    let recovered = DrawnTextRecovery.reading(reading, on: page)
    #expect(recovered.lines.filter { $0.text == "Goals" }.count == 1)
    #expect(!recovered.lines.contains { $0.text == "Goa1s" })
    var result = page
    PageDisposition.replaced(recovered).apply(to: &result)
    DrawnTextRecovery.preserveArtwork(in: &result, extracted: page)
    #expect(result.recognizedArtwork.contains { $0.contains(artwork) })
    #expect(!result.graphics.contains(artwork)) // the crop must not swallow the reflowed sentence
}

@Test func aMergedRecognizedRowUsesTheNativeWordsSpellingAndStyleExactlyOnce() {
    let native = TextLine(content: InlineText("Goals", style: .bold),
        rect: CGRect(x: 90, y: 240, width: 100, height: 40), fontSize: 40)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 720, height: 405),
        lines: [native], graphics: [])
    let line = TextLine(text: "Goa1s support user analysis", rect: CGRect(x: 90, y: 240, width: 500, height: 40), fontSize: 40)
    let reading = OCRReader.Result(lines: [line], tables: [], wordBoxes: [[
        .init(range: 0..<5, box: native.rect),
        .init(range: 6..<13, box: CGRect(x: 220, y: 240, width: 120, height: 40))]])
    let recovered = DrawnTextRecovery.reading(reading, on: page)
    #expect(recovered.lines.count == 1)
    #expect(recovered.lines[0].text == "Goals support user analysis")
    #expect(recovered.lines[0].content.elements.contains(.text("Goals", .bold)))
    #expect(recovered.wordBoxes.isEmpty)
    // Missing word positions are not permission to guess: recognition is unresolved and the
    // existing drawn-text failure branch retains the native word and the original artwork.
    let unread = DrawnTextRecovery.reading(OCRReader.Result(lines: [line], tables: []), on: page)
    #expect(unread.lines.isEmpty)
    let evidence = PageEvidence(requiresPageImage: false, hasText: true, characters: 5,
        replacementCharacters: 0, imageBackedText: false, damagedEncoding: false,
        implausibleLayer: nil, drawnText: true)
    let resolution = RecognitionPolicy.resolve(.recognize(.replace, keepCropsIfUnread: true),
        evidence: evidence, outcome: .read(unread), judge: .english(language: "en"))
    #expect(resolution.disposition == .keptAsExtracted)
    #expect(resolution.warnings.contains(.ocrFailed(.unreadDrawnText)))
    var kept = page
    resolution.disposition.apply(to: &kept)
    #expect(kept == page)
    #expect(kept.recognizedArtwork.isEmpty)
}
