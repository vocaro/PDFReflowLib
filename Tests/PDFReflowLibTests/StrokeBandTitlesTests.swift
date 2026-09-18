import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// NOAA NCA5 page 40 (#200). The box title `Box 1.1. Mitigation, Adaptation, and Resilience` sits on
// one 20-point stroke, which the graphics reader recorded as a thin rule through the title, and a
// pale tab along the stroke's top reached the title within its padding: both took the title into a
// crop. The box's three bullets, each on a shaded panel, read as a table of `•` and text. Page 40
// had reflowed all of it beside a page image until #200 stopped a photo credit's false table from
// sending the page to that fallback. Fixtures are native extraction from the checksum-pinned
// source, captured with each band recorded; expectations were read from the rendered pages.

private func blocks(_ name: String) throws -> (page: PageContent, blocks: [ReflowBlock]) {
    var content = try SourceLayoutFixture.load(name).styledContent()
    // The running head and foot are furniture the pipeline removes first.
    content.lines.removeAll { $0.rect.maxY < 31 || $0.rect.minY > content.bounds.maxY - 26 }
    let regions = LayoutReconstructor.graphicsWithLabels(content)
    var warnings: [ConversionWarning] = []
    return (content, LayoutReconstructor.blocks(page: content, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                                vocabulary: ["environmental"], warnings: &warnings))
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

@Test func aWideStraightStrokeIsTheBandItPaints() throws {
    // A 20-point horizontal stroke, a 20-point vertical one, an ordinary one-point rule and a
    // 20-point diagonal.
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
        testPDFStream("q 20 w 27 570 m 373 570 l S Q q 20 w 500 100 m 500 300 l S Q q 1 w 27 400 m 373 400 l S Q q 20 w 50 50 m 200 200 l S Q"),
    ])
    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    let paints = GraphicsReader.read(try #require(document.page(at: 1))).paints
    #expect(paints.count == 4)
    #expect(paints[0] == GraphicsReader.Paint(rect: CGRect(x: 27, y: 560, width: 346, height: 20), frame: false, filled: true, band: true))
    #expect(paints[1] == GraphicsReader.Paint(rect: CGRect(x: 490, y: 100, width: 20, height: 200), frame: false, filled: true, band: true))
    // An ordinary rule and a diagonal keep their padded paths.
    #expect(paints[2] == GraphicsReader.Paint(rect: CGRect(x: 25, y: 398, width: 350, height: 4), frame: false))
    #expect(paints[3] == GraphicsReader.Paint(rect: CGRect(x: 48, y: 48, width: 154, height: 154), frame: false))
}

@Test func noaaBoxTitleOnAStrokeBandReadsAsTextAndItsBulletsAsAList() throws {
    let (page, result) = try blocks("noaa-40")
    #expect(headings(result).contains("Box 1.1. Mitigation, Adaptation, and Resilience"))
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(!page.lines.filter { line in regions.contains { $0.intersects(line.rect) } }.contains { $0.text.hasPrefix("Box 1.1.") })
    // The bullets are list lines for the list pass, not table cells.
    #expect(!result.contains { if case .table = $0.content { true } else { false } })
    let listed = result.compactMap { if case let .preformatted(text) = $0.content { text.text } else { nil } }
    for term in ["• Mitigation:", "• Adaptation:", "• Resilience:"] { #expect(listed.contains { $0.hasPrefix(term) }, "\(term)") }
    #expect(ShadedTableDetector.tables(in: page, lines: page.lines).isEmpty)
}

@Test func aBandsEdgingGoesWithItAndABandInsideABoxIsItsTint() throws {
    // Page 84's Key Message label and title sit on a band stroke and a filled rectangle; page
    // 1490's two-line box title on one band inside the box's tint.
    #expect(headings(try blocks("noaa-84").blocks).contains("Key Message 2.1 Climate Is Changing, and Scientists Understand Why"))
    #expect(headings(try blocks("noaa-1490").blocks).contains {
        $0.hasPrefix("Box 30.1. Historical Under-Resourcing Results in Continuing Data Inequities")
    })
    // Page 1000's two-line box title on two stacked bands and page 62's sub-heading over its
    // box's photograph.
    #expect(headings(try blocks("noaa-1000").blocks).contains {
        $0.hasPrefix("Box 22.2. Reshaping FEMA Policy to Aid Disaster Recovery") && $0.hasSuffix("Cultural Heritage Corridor")
    })
    let box = try blocks("noaa-62")
    #expect(headings(box.blocks).contains("Box 1.3. Indigenous Ways of Life and Spiritual Health"))
    #expect(headings(box.blocks).contains("Exemplifying Indigenous Resilience"))
    // Control: the band read as the thin rule it was, page 40's title is taken by the crop again.
    let fixture = try SourceLayoutFixture.load("noaa-40")
    var paints = try #require(fixture.paints).map {
        GraphicsReader.Paint(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]),
                             frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false,
                             grouped: $0.grouped ?? false, band: $0.band ?? false)
    }
    let band = try #require(paints.firstIndex { $0.band })
    paints[band] = GraphicsReader.Paint(rect: CGRect(x: 25, y: 568.24, width: 350.5, height: 4), frame: false)
    var thin = fixture.content(tinted: false)
    thin.lines.removeAll { $0.rect.maxY < 31 }
    let composed = TintDetector.compose(paints, lines: thin.lines, bounds: thin.bounds)
    thin.graphics = composed.graphics
    thin.tints = composed.tints
    let regions = LayoutReconstructor.graphicsWithLabels(thin)
    #expect(thin.lines.contains { line in line.text.hasPrefix("Box 1.1.") && regions.contains { $0.intersects(line.rect) } })
}

@Test func aShadedTableWhoseFirstColumnHoldsOnlyMarkersIsAList() {
    // Three panels, each a `•` beside its item: a list. The same panels with labels are a table.
    func page(_ first: [String]) -> PageContent {
        let panels = (0..<3).map { CGRect(x: 70, y: 500 - CGFloat($0) * 40, width: 300, height: 38) }
        let lines = first.enumerated().flatMap { index, label in
            [TextLine(text: label, rect: CGRect(x: 81, y: 512 - CGFloat(index) * 40, width: label.count > 1 ? 40 : 3, height: 12), fontSize: 9),
             TextLine(text: "Item \(index + 1) with a description of several words", rect: CGRect(x: 130, y: 512 - CGFloat(index) * 40, width: 200, height: 12), fontSize: 9)]
        }
        var content = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
        content.tints = panels
        return content
    }
    let bullets = page(["•", "•", "•"])
    #expect(ShadedTableDetector.tables(in: bullets, lines: bullets.lines).isEmpty)
    let labelled = page(["High", "Medium", "Low"])
    #expect(ShadedTableDetector.tables(in: labelled, lines: labelled.lines).count == 1)
}
