import CoreGraphics
import CryptoKit
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

private func paintedGrid(rows: Int = 4, header: Bool = true) -> ([TextLine], [CGRect], [CGRect: String]) {
    var lines: [TextLine] = [], cells: [CGRect] = [], text: [CGRect: String] = [:]
    for row in 0..<rows {
        for column in 0..<2 {
            let rect = CGRect(x: 40 + column * 140, y: 600 - row * 30, width: 140,
                              height: row == 0 && header ? 18 : 30)
            let value = column == 0 ? "Label \(row)" : "Explanation \(row)"
            cells.append(rect)
            text[rect.insetBy(dx: 0.1, dy: 0.1)] = value
            lines.append(TextLine(text: value, rect: CGRect(x: rect.minX + 5, y: rect.minY + 3,
                                                          width: 100, height: 12), fontSize: 10))
        }
    }
    return (lines, cells, text)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"))
func paintedTwoColumnTextGridKeepsEveryCell() {
    let (lines, cells, text) = paintedGrid()
    let tables = PaintedCellTableReader.tables(lines: lines, cells: cells) { text[$0] ?? "" }
    #expect(tables.count == 1)
    #expect(tables.first?.rows.map { $0.map(\.text) } == (0..<4).map { ["Label \($0)", "Explanation \($0)"] })
    #expect(tables.first?.columns == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"))
func ordinaryColumnsAndIncompletePaintDoNotStateACellGrid() {
    let (lines, cells, text) = paintedGrid()
    #expect(PaintedCellTableReader.tables(lines: lines, cells: []) { text[$0] ?? "" }.isEmpty)
    // One full-width shaded band per row is no evidence of internal column boundaries.
    let bands = stride(from: 0, to: cells.count, by: 2).map { cells[$0].union(cells[$0 + 1]) }
    #expect(PaintedCellTableReader.tables(lines: lines, cells: bands) { text[$0] ?? "" }.isEmpty)
    #expect(PaintedCellTableReader.tables(lines: lines, cells: Array(cells.prefix(4))) { text[$0] ?? "" }.isEmpty)
    let (noHeaderLines, noHeaderCells, noHeaderText) = paintedGrid(header: false)
    #expect(PaintedCellTableReader.tables(lines: noHeaderLines, cells: noHeaderCells) {
        noHeaderText[$0] ?? ""
    }.isEmpty)
    // A cell read that drops a character cannot replace the original lines.
    #expect(PaintedCellTableReader.tables(lines: lines, cells: cells) { _ in "wrong" }.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"))
func filledRectangleEvidencePreservesSeparateWhiteCellsAndIgnoresCurves() throws {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
        testPDFStream("1 g 40 500 100 -30 re 140 500 100 -30 re f 0 g 40 300 m 50 500 80 550 90 300 c f")])
    let document = try #require(PDFDocument(data: data))
    defer { withExtendedLifetime(document) {} }
    let page = try #require(document.page(at: 0)?.pageRef)
    let filled = GraphicsReader.read(page).filledCells
    #expect(filled == [CGRect(x: 40, y: 470, width: 100, height: 30), CGRect(x: 140, y: 470, width: 100, height: 30)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"),
      .enabled(if: ProcessInfo.processInfo.environment["PDFREFLOW_NOAA_PDF"] != nil))
func sourceNoaaPaintedTablesKeepBothTwoColumnGrids() throws {
    let path = try #require(ProcessInfo.processInfo.environment["PDFREFLOW_NOAA_PDF"])
    let url = URL(fileURLWithPath: path)
    let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    #expect(hash == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    let source = try PDFPageSource(url: url)
    let page = try PageReader.read(pageIndex: 24, from: source, limit: 100_000, options: ConversionOptions(), structure: nil).content
    #expect(page.tables.count == 2)
    #expect(page.tables.map { $0.rows.count } == [5, 8])
    #expect(page.tables.map(\.columns) == [2, 2])
    #expect(page.tables.map(\.headerRows) == [1, 1])
    #expect(page.tables.first?.rows.map { $0[0].text } == ["Confidence Level", "Very high", "High", "Medium", "Low"])
    #expect(page.tables.last?.rows.map { $0.map(\.text) } == [
        ["Likelihood Assessment", "Numeric Probability of Outcome"],
        ["Virtually certain", "99%–100%"], ["Very likely", "90%–100%"], ["Likely", "66%–100%"],
        ["As likely as not", "33%–66%"], ["Unlikely", "0%–33%"], ["Very unlikely", "0%–10%"],
        ["Exceptionally unlikely", "0%–1%"]])
    // Page 28 already has an admitted numeric table. Its painted subgrid cannot displace
    // that ownership and strand the remaining text inside the existing graphic crop.
    let neighbor = try source.page(at: 27)
    let reference = try #require(neighbor.pageRef)
    let graphics = GraphicsReader.read(reference)
    let shows = NativeSpacingReader.read(reference)
    let lines = try NativeTextReader.lines(on: neighbor, limit: 100_000, shows: shows)
    let rules = graphics.regions.filter(LayoutReconstructor.isThinRule)
    let existing = try TableReader.tables(on: neighbor, lines: lines, shows: shows, rules: rules)
    let withPaint = try TableReader.tables(on: neighbor, lines: lines, shows: shows, rules: rules,
                                          filledCells: graphics.filledCells)
    #expect(!existing.isEmpty)
    #expect(existing.allSatisfy { withPaint.contains($0) })
}

private func noaaPaintedPage() throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("noaa-25")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    var page = fixture.content()
    let cells = fixture.filledCells.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
    let readings = Dictionary(zip(cells.map { $0.insetBy(dx: 0.1, dy: 0.1) }, fixture.filledCellText),
                              uniquingKeysWith: { first, _ in first })
    page.tables = PaintedCellTableReader.tables(lines: page.lines, cells: cells) { readings[$0] ?? "" }
    PageDiagnosis.prepareExtracted(&page, evidence: PageEvidence(requiresPageImage: false,
        hasText: true, characters: page.lines.reduce(0) { $0 + $1.text.count }, replacementCharacters: 0,
        imageBackedText: page.graphics.contains { PageDiagnosis.coversPage($0, bounds: page.bounds) },
        damagedEncoding: false, implausibleLayer: nil, drawnText: false))
    return page
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"))
func noaaPaintedSourceFixtureKeepsTablesSeparateFromProseAndTheirTitles() throws {
    let page = try noaaPaintedPage()
    #expect(page.tables.map { $0.rows.count } == [5, 8])
    #expect(page.tables.map(\.headerRows) == [1, 1])
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    #expect(headingTexts(blocks).contains("Table 1. Calibrated Language for Confidence Assessment"))
    #expect(headingTexts(blocks).contains("Table 2. Calibrated Language for Likelihood Assessment"))
    #expect(blocks.count { if case .table = $0.content { true } else { false } } == 2)
    #expect(paragraphTexts(blocks).contains { $0.contains("The text supporting each Key Message provides evidence, discusses implications") })
    #expect(!paragraphTexts(blocks).contains { $0.contains("Very high") || $0.contains("99%–100%") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"))
func repeatedSourceCreditLabelsKeepTheirValuesOnTheirOwnLines() throws {
    let page = try SourceLayoutFixture.load("noaa-1738").content()
    let starts = LayoutReconstructor.labelValueStarts(in: page.lines)
    let names = page.lines.filter { starts.contains($0.rect) }.map(\.text)
    #expect(names.contains("Diane Burko"))
    #expect(names.contains("Allison R. Crimmins, US Global Change Research Program"))
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(blocks).contains("Cover Art"))
    #expect(paragraphTexts(blocks).contains("Diane Burko"))
    #expect(!paragraphTexts(blocks).contains("Cover Art Diane Burko"))
    #expect(paragraphTexts(blocks).contains { $0.contains("process. In: Fifth National Climate Assessment.") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/215"))
func anIsolatedShortLineAndOrdinaryProseDoNotStateCreditLabels() {
    let lines = (0..<6).map { row in
        TextLine(text: "Ordinary prose wraps on one measure without label/value pairs.",
                 rect: CGRect(x: 40, y: 600 - row * 16, width: 300, height: 12), fontSize: 10)
    }
    #expect(LayoutReconstructor.labelValueStarts(in: lines).isEmpty)
    let pair = [TextLine(text: "One short line", rect: CGRect(x: 40, y: 600, width: 70, height: 12), fontSize: 10),
                TextLine(text: "A longer line below it", rect: CGRect(x: 40, y: 584, width: 140, height: 12), fontSize: 10)]
    #expect(LayoutReconstructor.labelValueStarts(in: pair).isEmpty)
}
