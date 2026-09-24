import CoreGraphics
import Testing
@testable import PDFReflowLib

private func sourcePanelPage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("noaa-magazine-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    let page = fixture.content()
    return TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
}

@Test func nativeProseRowsKeepInlineReferenceFragmentsAndTheirHeadings() throws {
    let page = try sourcePanelPage(26)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    func released(_ lines: [TextLine], native: Bool) -> Set<Int> {
        PageDiagnosis.proseOverPictures(lines: lines, pictures: page.pictures,
            crops: crops, bounds: page.bounds, language: "en", nativeTypography: native)
    }
    let indices = released(page.lines, native: true)
    for prefix in ["Metrics and Definitions", "Economic Estimates", "Unless otherwise noted",
                   "Analysis’s Implicit", "12 Where documented", "in specific estimates", "Use of Scenarios"] {
        let index = try #require(page.lines.firstIndex { $0.text.hasPrefix(prefix) })
        #expect(indices.contains(index))
    }
    let heading = try #require(page.lines.firstIndex { $0.text.hasPrefix("Metrics and Definitions") })
    #expect(!released(page.lines, native: false).contains(heading))
    // A real gap separates columns; it cannot complete the width of this paragraph's row.
    var separated = page.lines
    let fragment = try #require(separated.firstIndex { $0.text.hasPrefix("12 Where documented") })
    separated[fragment].rect.origin.x += 20
    let opening = try #require(separated.firstIndex { $0.text.hasPrefix("Unless otherwise noted") })
    #expect(!released(separated, native: true).contains(opening))
}

@Test func semanticTablesKeepTheirIntroductionsOverDecorativeArtwork() throws {
    var page = try sourcePanelPage(25)
    let cells = try SourceLayoutFixture.load("noaa-25")
    let rectangles = cells.filledCells.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
    let readings = Dictionary(zip(rectangles.map { $0.insetBy(dx: 0.1, dy: 0.1) }, cells.filledCellText),
                              uniquingKeysWith: { first, _ in first })
    page.tables = PaintedCellTableReader.tables(lines: page.lines, cells: rectangles) { readings[$0] ?? "" }
    #expect(page.tables.count == 2)
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images,
        context: .init(language: "en", documentBody: 10), warnings: &warnings)
    #expect(headingTexts(blocks).contains("Table 1. Calibrated Language for Confidence Assessment"))
    #expect(headingTexts(blocks).contains("Table 2. Calibrated Language for Likelihood Assessment"))
    let prose = paragraphTexts(blocks).joined(separator: " ")
    #expect(prose.contains("The calibrated uncertainty terms below are used to express a probabilistic assessment"))
    #expect(prose.contains("levels listed below are used to reflect the quantity, quality, and degree of agreement"))
    #expect(!prose.contains("Virtually certain"))
    #expect(LayoutReconstructor.tableIntroductions(in: page.lines, tables: [], body: 10).isEmpty)
}

@Test func equalSizedNeighboringTableCellsDoNotCompleteAProseRow() {
    let texts = ["First cell has several ordinary words", "Neighbor cell also has ordinary words",
                 "Second row contains plain English", "More plain English in the next cell",
                 "Third row has a short ending", "Last neighboring cell also ends here"]
    let lines = texts.enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: index % 2 == 0 ? 20 : 224,
            y: 160 - (index / 2) * 14, width: index / 2 == 2 ? 90 : 200, height: 14), fontSize: 10)
    }
    // Even a narrow gutter cannot turn same-sized table cells into one prose measure.
    // The left column's second row is short enough to fail the inherited prose test.
    var rows = lines
    rows[2].rect.size.width = 90
    rows[3].rect.size.width = 90
    let image = CGRect(x: 10, y: 100, width: 430, height: 100)
    #expect(PageDiagnosis.proseOverPictures(lines: rows, pictures: [image], crops: [image],
        bounds: CGRect(x: 0, y: 0, width: 612, height: 792), language: "en", nativeTypography: true).isEmpty)
}
