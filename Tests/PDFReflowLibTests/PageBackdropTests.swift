import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// A page that paints only its own backdrop (#164). The Earthdata deck is a Google Slides export:
// every slide is a 720 × 405 landscape page with a full-bleed background fill, a filled box
// behind each text placeholder, and its diagram drawn in panels and outlined boxes over that
// ground. Clustered, the art covers the slide, so every slide took the unverified-text-layer
// treatment (review warning and a source-page image) meant for text over a picture of the page,
// although its text is a complete native Arial/Verdana layer. The DGA cover is the control: it
// also paints a page-sized fill, but its title is drawn as art over that fill and its text layer
// is a Type 3 transcription that paints nothing, so its crops hold most of its words.
// Expectations were read from 100 DPI renders of the pinned sources.

private let slidesSHA256 = "f0a1ea3f5711228a9de2544fd1a94b05cfb8d9323fe3a4c253542f5a6ead5c94"
private let dgaSHA256 = "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472"

private func fixture(_ name: String, sha256: String) throws -> SourceLayoutFixture {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256)
    return fixture
}

private func paints(_ fixture: SourceLayoutFixture) -> [GraphicsReader.Paint] {
    (fixture.paints ?? []).map {
        GraphicsReader.Paint(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]),
                             frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false)
    }
}

/// The page as extraction hands it to layout, composed as the pipeline composes it: with the art
/// beside the page's backdrop when it paints only one, and with every paint otherwise.
private func composed(_ fixture: SourceLayoutFixture) -> (page: PageContent, graphics: GraphicsReader.Result) {
    var page = fixture.content(tinted: false)
    let all = paints(fixture)
    let art = PDFReflowLibPipeline.artBesideBackdrops(all, lines: page.lines, bounds: page.bounds)
    let result = TintDetector.compose(art ?? all, lines: page.lines, bounds: page.bounds)
    page.graphics = result.graphics
    page.tints = result.tints
    page.separators = result.separators
    return (page, GraphicsReader.Result(regions: page.graphics, paints: all, unsupported: false))
}

private func area(_ rect: CGRect) -> Double { Double(rect.width) * Double(rect.height) }

@Test func aSlidesBackgroundFillAndPlaceholdersAreNoPictureOfThePage() throws {
    // Slide 13 draws its title and note on placeholder fills and its pipeline in two panels with
    // five outlined boxes, all over the slide's background: 37 paints, one of them page-sized.
    let source = try fixture("slides-13", sha256: slidesSHA256)
    let all = paints(source)
    #expect(PDFReflowLibPipeline.paintsOnlyItsBackdrop(all, bounds: CGRect(x: 0, y: 0, width: 720, height: 405)))
    let (page, graphics) = composed(source)
    #expect(page.graphics.allSatisfy { area($0) <= area(page.bounds) * 0.75 })
    #expect(PDFReflowLibPipeline.layoutComesApart(page, graphics: graphics))
    // Reproducer: read as any other page, the art clusters into one crop over the whole slide,
    // which takes every line of it.
    var untouched = source.content(tinted: true)
    untouched.graphics = TintDetector.compose(all, lines: untouched.lines, bounds: untouched.bounds).graphics
    #expect(untouched.graphics.contains { area($0) > area(untouched.bounds) * 0.75 })
    #expect(!PDFReflowLibPipeline.layoutComesApart(untouched, graphics: graphics))
    let outcome = PDFReflowLibPipeline.cropOutcome(untouched)
    #expect(outcome.taken == outcome.total)
}

@Test func aBackdropPageKeepsTheArtThatHoldsNoText() throws {
    // Slide 5 prints its question without a text layer: Poppler and PDFKit find only the slide
    // number, and the question is one filled path a fifth of the slide. That path holds no line,
    // so it keeps its crop and the slide is carried by it; the placeholders around it do not.
    let source = try fixture("slides-5", sha256: slidesSHA256)
    let (page, graphics) = composed(source)
    #expect(page.lines.map(\.text) == ["5"])
    #expect(page.graphics.contains { $0.width > 600 && $0.height > 80 })
    #expect(PDFReflowLibPipeline.layoutComesApart(page, graphics: graphics))
    #expect(PDFReflowLibPipeline.cropOutcome(page).taken == 0)
    // Control: the slide-number placeholder holds the page's only line and seeds no crop.
    #expect(!page.graphics.contains { $0.contains(CGPoint(x: 690, y: 20)) && $0.width < 100 })
}

@Test func aSlidesTitleAndStatementStandOutsideEveryCrop() throws {
    // Slides 1 and 10 paint nothing but the background, the NASA insignia and the fills behind
    // their text, so nothing of either reaches a crop: the title slide's four lines and the
    // Architectural Concept statement reflow whole beside the insignia alone.
    for name in ["slides-1", "slides-10"] {
        let source = try fixture(name, sha256: slidesSHA256)
        let (page, graphics) = composed(source)
        #expect(PDFReflowLibPipeline.layoutComesApart(page, graphics: graphics), "\(name)")
        #expect(PDFReflowLibPipeline.cropOutcome(page).taken == 0, "\(name)")
        // The insignia covers 1.2% of a slide; nothing else keeps a crop.
        #expect(page.graphics.allSatisfy { area($0) <= area(page.bounds) * 0.05 }, "\(name)")
    }
}

@Test func theDGACoverIsStillAPictureOfItself() throws {
    // The cover paints a page-sized cream fill under 45 small images and its outlined lettering.
    // It is a backdrop page, but the lettering and images hold 10 of its 16 words, so it keeps
    // the review signal and its source-page reference (#117).
    let source = try fixture("dga-1-illustrated", sha256: dgaSHA256)
    let all = paints(source)
    #expect(PDFReflowLibPipeline.paintsOnlyItsBackdrop(all, bounds: CGRect(x: 0, y: 0, width: 612, height: 792)))
    let (page, graphics) = composed(source)
    let outcome = PDFReflowLibPipeline.cropOutcome(page)
    #expect(outcome.total == 16 && outcome.taken == 10)
    #expect(!PDFReflowLibPipeline.layoutComesApart(page, graphics: graphics))
    // Control: at the deck's worst share (5 of 20 words) the same page would come apart, so the
    // measure, not the page-sized fill, is what keeps the cover's signal.
    #expect(outcome.taken * 2 > outcome.total)
}

@Test func aPageSizedPaintThatIsNotAFillIsStillAPictureOfThePage() throws {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let page = GraphicsReader.Paint(rect: bounds, frame: true, filled: true)
    let scan = GraphicsReader.Paint(rect: bounds, frame: true, image: true)
    let border = GraphicsReader.Paint(rect: bounds, frame: true)
    let icon = GraphicsReader.Paint(rect: CGRect(x: 20, y: 700, width: 60, height: 60), frame: true, filled: true)
    #expect(PDFReflowLibPipeline.paintsOnlyItsBackdrop([page, icon], bounds: bounds))
    #expect(!PDFReflowLibPipeline.paintsOnlyItsBackdrop([scan, icon], bounds: bounds))
    #expect(!PDFReflowLibPipeline.paintsOnlyItsBackdrop([page, border], bounds: bounds))
    #expect(!PDFReflowLibPipeline.paintsOnlyItsBackdrop([page, scan], bounds: bounds))
    // A page painting nothing page-sized is not a backdrop page: DGA pages 3–5 keep #117's rule.
    #expect(!PDFReflowLibPipeline.paintsOnlyItsBackdrop([icon], bounds: bounds))
    #expect(!PDFReflowLibPipeline.paintsOnlyItsBackdrop([], bounds: bounds))
    #expect(PDFReflowLibPipeline.artBesideBackdrops([scan, icon], lines: [], bounds: bounds) == nil)
}

@Test func onlyTheArtThatHoldsNoTextSurvivesABackdrop() throws {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let line = TextLine(text: "Cumulus Data Archive", rect: CGRect(x: 100, y: 400, width: 200, height: 12), fontSize: 12)
    let backdrop = GraphicsReader.Paint(rect: bounds, frame: true, filled: true)
    let box = GraphicsReader.Paint(rect: CGRect(x: 90, y: 380, width: 220, height: 60), frame: false, filled: true)
    let arrow = GraphicsReader.Paint(rect: CGRect(x: 150, y: 420, width: 40, height: 4), frame: false, filled: true)
    let figure = GraphicsReader.Paint(rect: CGRect(x: 400, y: 200, width: 120, height: 90), frame: false, filled: true)
    let icon = GraphicsReader.Paint(rect: CGRect(x: 120, y: 390, width: 30, height: 30), frame: true, image: true)
    let art = try #require(PDFReflowLibPipeline.artBesideBackdrops([backdrop, box, arrow, figure, icon],
                                                                   lines: [line], bounds: bounds))
    // The backdrop, the box holding the line, and the arrow drawn inside that box are decoration;
    // the figure standing on its own and every image keep their crop.
    #expect(art.map(\.rect) == [figure.rect, icon.rect])
}
