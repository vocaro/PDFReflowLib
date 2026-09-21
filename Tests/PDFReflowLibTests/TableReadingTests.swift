import CoreGraphics
import Foundation
import PDFKit
import ZIPFoundation
import Testing
@testable import PDFReflowLib

/// One cell the page draws: its text, and where its first glyph stands.
private struct Drawn {
    var text: String
    var x: Int
    var y: Int
}

/// A one-page PDF drawing `cells` in a simple font whose every glyph is half an em wide, so a
/// string of *n* characters set at 10 points is exactly 5*n* points wide and a test can state a
/// column's geometry in characters. `rules` are painted rectangles, which the underline evidence
/// and the crop seeds both read.
private func tablePDF(_ cells: [Drawn], rules: [CGRect] = [], size: Int = 10) -> Data {
    let widths = (32...126).map { _ in "500" }.joined(separator: " ")
    func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
    let painted = rules.map { "\($0.minX) \($0.minY) \($0.width) \($0.height) re f" }.joined(separator: "\n")
    let text = cells.map { cell in
        "BT /F1 \(size) Tf 1 0 0 1 \(cell.x) \(cell.y) Tm (\(escaped(cell.text))) Tj ET"
    }.joined(separator: "\n")
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(painted + "\n" + text),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding "
            + "/FirstChar 32 /LastChar 126 /Widths [\(widths)] >>",
    ])
}

/// The tables `TableReader` reads from such a page, with the page's own rules.
private func tablesRead(_ data: Data) throws -> (tables: [PageTable], lines: [TextLine]) {
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: 0))
    let rules = GraphicsReader.read(try #require(page.pageRef)).regions.filter(LayoutReconstructor.isThinRule)
    let shows = NativeSpacingReader.read(try #require(page.pageRef))
    let lines = try NativeTextReader.lines(on: page, limit: 100_000, rules: rules, shows: shows)
    return (try TableReader.tables(on: page, lines: lines, shows: shows, rules: rules), lines)
}

private func cellTexts(_ table: PageTable) -> [[String]] {
    table.rows.map { $0.map(\.text) }
}

/// A four-row statistics table with a heading row the page underlines: the shape of the USGS
/// mineral summaries, in a font a test can measure.
private func statisticsCells() -> [Drawn] {
    var cells = [Drawn(text: "Region", x: 50, y: 700), Drawn(text: "2023", x: 200, y: 700),
                 Drawn(text: "2024", x: 300, y: 700)]
    for (index, row) in [("North", "120", "130"), ("South", "90", "95"),
                         ("East", "70", "75"), ("West", "60", "65")].enumerated() {
        let y = 688 - index * 12
        cells += [Drawn(text: row.0, x: 50, y: y), Drawn(text: row.1, x: 200, y: y),
                  Drawn(text: row.2, x: 300, y: y)]
    }
    return cells
}

private let headingRules = [CGRect(x: 50, y: 694, width: 30, height: 0.8),
                            CGRect(x: 200, y: 694, width: 20, height: 0.8),
                            CGRect(x: 300, y: 694, width: 20, height: 0.8)]

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aBorderlessStatisticsTableIsReadAsCells() throws {
    let (tables, _) = try tablesRead(tablePDF(statisticsCells(), rules: headingRules))
    #expect(tables.count == 1)
    let table = try #require(tables.first)
    #expect(table.columns == 3)
    #expect(table.headerRows == 1)
    #expect(cellTexts(table) == [["Region", "2023", "2024"], ["North", "120", "130"],
                                 ["South", "90", "95"], ["East", "70", "75"], ["West", "60", "65"]])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aTableReadAsCellsLosesNoCharacterOfItsRows() throws {
    let (tables, lines) = try tablesRead(tablePDF(statisticsCells(), rules: headingRules))
    let table = try #require(tables.first)
    func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
    let covered = lines.filter { table.rect.insetBy(dx: -1, dy: -1).contains($0.rect) }
    #expect(!covered.isEmpty)
    #expect(compact(table.rows.flatMap { $0.map(\.text) }.joined())
            == compact(covered.sorted { $0.rect.maxY == $1.rect.maxY
                                        ? $0.rect.minX < $1.rect.minX : $0.rect.maxY > $1.rect.maxY }
                       .map(\.text).joined()))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aRowWhoseWidestValuesNearlyMeetStillDividesAtTheBlocksColumns() throws {
    // The USGS salient-statistics table's `Employment, mine and plant, number` row leaves 5.6
    // points between its values where the rows above leave 8.4, so a per-row gap threshold cuts
    // it wrong or not at all. Here the last row's values fill their columns to within a fifth of
    // the gap the rows above leave; the block's own corridors still divide it.
    var cells = statisticsCells()
    cells += [Drawn(text: "Total", x: 50, y: 640), Drawn(text: "112,000", x: 190, y: 640),
              Drawn(text: "118,000", x: 290, y: 640)]
    let table = try #require(try tablesRead(tablePDF(cells, rules: headingRules)).tables.first)
    #expect(cellTexts(table).last == ["Total", "112,000", "118,000"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aPageOfProseBesideAColumnOfNumbersIsNotATable() throws {
    // Page 416 of the FAA handbook prints its NDB table in the right column of a two-column page.
    // Every row of the left column is a line of prose filling that column exactly, so on geometry
    // alone those rows and the table's rows form one three-column grid. A column whose cells fill
    // it again and again is the page's own text, and the block is declined.
    var cells: [Drawn] = []
    let prose = ["of linear deviation. In the RNAV en route mode, maximum",
                 "deflection of the CDI typically represents 5 NM either",
                 "side of the selected course without regard to distance",
                 "from the waypoint. In the RNAV approach mode, the",
                 "maximum deflection of the CDI represents 1 NM either"]
    for (index, line) in prose.enumerated() {
        let y = 700 - index * 12
        cells += [Drawn(text: line, x: 50, y: y), Drawn(text: "Under \(index)0", x: 350, y: y),
                  Drawn(text: "\(index)5", x: 460, y: y)]
    }
    #expect(try tablesRead(tablePDF(cells)).tables.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func twoColumnsOfProseFacingEachOtherAreNotATable() throws {
    var cells: [Drawn] = []
    for index in 0..<6 {
        let y = 700 - index * 12
        cells += [Drawn(text: "the left column of an ordinary two-column", x: 50, y: y),
                  Drawn(text: "page, whose gutter is the only white 4", x: 330, y: y)]
    }
    #expect(try tablesRead(tablePDF(cells)).tables.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aBlockOfRowsWithNoColumnOfValuesIsNotATable() throws {
    var cells: [Drawn] = []
    for (index, row) in [("Adams", "clerk", "Maine"), ("Baker", "cooper", "Ohio"),
                         ("Chase", "miller", "Iowa"), ("Drake", "smith", "Utah")].enumerated() {
        let y = 700 - index * 12
        cells += [Drawn(text: row.0, x: 50, y: y), Drawn(text: row.1, x: 200, y: y),
                  Drawn(text: row.2, x: 300, y: y)]
    }
    #expect(try tablesRead(tablePDF(cells)).tables.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func theLetteringAroundADrawingIsNotATable() throws {
    // Page 424 of Wallace's algebra letters a right triangle — A, B, x, 63° and 7.6 around the
    // figure — and those labels stand on four rows that divide at four columns. A table fills its
    // cells; a drawing's lettering fills seven of sixteen.
    let cells = [Drawn(text: "A", x: 50, y: 700),
                 Drawn(text: "A", x: 150, y: 688), Drawn(text: "x", x: 250, y: 688),
                 Drawn(text: "B", x: 350, y: 688),
                 Drawn(text: "x", x: 50, y: 676), Drawn(text: "63", x: 350, y: 676),
                 Drawn(text: "7.6", x: 350, y: 664)]
    #expect(try tablesRead(tablePDF(cells)).tables.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aFigureCaptionBesideATableIsNotPartOfIt() throws {
    // Page 207 of the FAA handbook sets `Figure 8-4. Look at the chart…` over two printed rows in
    // the column beside a three-row altimeter-setting table. The four rows divide at four columns
    // and half their cells are filled, and the caption became two cells of the table it captions.
    var cells = [Drawn(text: "Mineral Wells altimeter setting", x: 260, y: 700),
                 Drawn(text: "29.94", x: 460, y: 700),
                 Drawn(text: "Abilene altimeter setting", x: 260, y: 688),
                 Drawn(text: "29.69", x: 460, y: 688),
                 Drawn(text: "Difference", x: 260, y: 676), Drawn(text: "0.25", x: 460, y: 676)]
    cells += [Drawn(text: "Figure 8-4. Look at the chart using a temperature", x: 50, y: 676),
              Drawn(text: "of -10 C and an aircraft altitude of 1,000 feet", x: 50, y: 664)]
    #expect(try tablesRead(tablePDF(cells)).tables.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aTableEmitsValidTableMarkupAndItsRowsAreNotAlsoProse() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pdfreflow-table-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("table.pdf")
    try tablePDF(statisticsCells(), rules: headingRules).write(to: source)
    let output = directory.appendingPathComponent("table.epub")
    let report = try await PDFConverter().convert(from: source, to: output)
    let html = String(decoding: try Archive(url: output, accessMode: .read)
        .entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(report.imageCount == 0)
    #expect(html.contains("<thead><tr><th scope=\"col\">"))
    #expect(html.contains("<td>North</td><td>120</td><td>130</td>"))
    #expect(html.contains("<td>West</td><td>60</td><td>65</td>"))
    // The rows are emitted once. A table that did not claim its own lines would print them again.
    #expect(html.components(separatedBy: "North").count == 2)
    #expect(!html.contains("<p>North"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func theWriterEmitsSpanningHeadingsAndTheModelRefusesARaggedTable() throws {
    let table = ReflowBlock.Table(rows: [
        [.init(text: InlineText("")), .init(text: InlineText("Mine production"), columns: 2)],
        [.init(text: InlineText("Country")), .init(text: InlineText("2023")), .init(text: InlineText("2024"))],
        [.init(text: InlineText("Chile")), .init(text: InlineText("5,250")), .init(text: InlineText("5,300"))],
    ], headerRows: 2)
    let markup = EPUBTextEncoder.table(table, labels: [:])
    #expect(markup.contains("<th scope=\"col\" colspan=\"2\">Mine production</th>"))
    #expect(markup.contains("<tbody><tr><td>Chile</td><td>5,250</td><td>5,300</td></tr></tbody>"))
    #expect(markup.hasPrefix("<table><thead>"))
    var validation = ReflowDocument.Validation()
    try validation.accept(.start(.init(title: "t", language: "en"), chapterStartPages: []))
    #expect(throws: ReflowDocument.ValidationError.invalidTable) {
        try validation.accept(.block(.init(content: .table(.init(rows: [
            [.init(text: InlineText("a")), .init(text: InlineText("b"))],
            [.init(text: InlineText("c"))],
        ])), page: 1)))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/210"))
func aValueIsANumberADashOrANumberWithAMarkAgainstIt() {
    for value in ["1,200", "e150", "(2)", "—", "7100,000", "430", "12,600", "e1,000"] {
        #expect(TableReader.isValue(value), "\(value) is a value")
    }
    for value in ["Korea, Republic of", "1% ad valorem.", "Free.", "Mine, recoverable", ""] {
        #expect(!TableReader.isValue(value), "\(value) is not a value")
    }
}
