import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Table leftovers after #121 (#124). The Fed tags the spanning section rows of its regulation and
// consumer-law tables (`Banks and banking`, `Depository accounts`) `TH`, but they were written as one
// spanning `<td>` inside a single `<tbody>`. Table A on page 47 is two label/amount lists side by
// side; the Fed tags both label columns `TH /Scope /Row`, but only the first column's labels were
// row headers.

private func reflowed(_ page: PageContent) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func table(_ fixture: String) throws -> ReflowBlock.Table {
    let blocks = reflowed(try SourceLayoutFixture.load(fixture).content())
    return try #require(blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }.first)
}

private func texts(_ row: ReflowBlock.Table.Row) -> [String] { row.cells.map(\.text.text) }

// MARK: Section rows (#124.1)

@Test(arguments: [
    ("fed-83", ["Holding companies and nonbank financial companies", "Federal Reserve Credit",
                "Monetary policy and reserve requirements", "Securities credit transactions"]),
    // The continuation page opens with its first section; the tags mark all three `TH` (spanning).
    ("fed-120", ["General banking", "Depository accounts", "Credit/general lending"]),
])
func fedSectionRowsNameTheirRowGroups(_ fixture: String, _ sections: [String]) throws {
    let table = try table(fixture)
    let spanning = table.rows.filter { $0.cells.count == 1 }
    #expect(spanning.map { $0.cells[0].text.text } == sections, "\(fixture)")
    // Each is one header cell spanning every column, in a body row.
    #expect(spanning.allSatisfy { !$0.header && $0.cells[0].header && $0.cells[0].span == table.columns }, "\(fixture)")
    // Other rows keep their kinds: the header row's cells and the labelled first cells only.
    for row in table.rows where row.cells.count > 1 {
        #expect(row.cells.dropFirst().allSatisfy { !$0.header }, "\(fixture) \(texts(row))")
        #expect(row.header || row.cells[0].header, "\(fixture) \(texts(row))")
    }
    // Every section opens its own tbody with a rowgroup header; no data cell spans the table.
    let markup = EPUBTextEncoder.table(table)
    #expect(!markup.contains("<td colspan"), "\(fixture)")
    for section in sections {
        let escaped = section.replacingOccurrences(of: "&", with: "&amp;")
        #expect(markup.contains("<tbody><tr><th colspan=\"2\" scope=\"rowgroup\">\(escaped)</th></tr>"), "\(fixture) \(section)")
    }
    #expect(markup.components(separatedBy: "<tbody>").count - 1 == sections.count, "\(fixture)")
    #expect(markup.components(separatedBy: "scope=\"rowgroup\"").count - 1 == sections.count, "\(fixture)")
}

@Test func sectionRowsOpenTheirOwnBodyAndOtherSpanningCellsDoNot() {
    func cell(_ text: String, span: Int = 1, header: Bool = false) -> ReflowBlock.Table.Cell {
        .init(text: InlineText(text), span: span, header: header)
    }
    let head = ReflowBlock.Table.Row(cells: [cell("Regulation"), cell("Description")], header: true)
    let first = ReflowBlock.Table.Row(cells: [cell("A", header: true), cell("Credit")], header: false)
    let second = ReflowBlock.Table.Row(cells: [cell("D", header: true), cell("Reserves")], header: false)
    func section(_ text: String) -> ReflowBlock.Table.Row { .init(cells: [cell(text, span: 2, header: true)], header: false) }
    // Rows before the first section keep a body of their own.
    let table = ReflowBlock.Table(columns: 2, rows: [head, first, section("Credit & <reserves>"), second, section("Securities")])
    #expect(EPUBTextEncoder.table(table) == "<table><thead><tr><th>Regulation</th><th>Description</th></tr></thead>"
        + "<tbody><tr><th scope=\"row\">A</th><td>Credit</td></tr></tbody>"
        + "<tbody><tr><th colspan=\"2\" scope=\"rowgroup\">Credit &amp; &lt;reserves&gt;</th></tr><tr><th scope=\"row\">D</th><td>Reserves</td></tr></tbody>"
        + "<tbody><tr><th colspan=\"2\" scope=\"rowgroup\">Securities</th></tr></tbody></table>")
    // Controls: a spanning data cell stays in the body it is in; a row header spanning part of
    // the table is a row header; a spanning header row is a header row.
    let data = ReflowBlock.Table(columns: 2, rows: [head, first, .init(cells: [cell("Note", span: 2)], header: false), second])
    #expect(EPUBTextEncoder.table(data) == "<table><thead><tr><th>Regulation</th><th>Description</th></tr></thead>"
        + "<tbody><tr><th scope=\"row\">A</th><td>Credit</td></tr><tr><td colspan=\"2\">Note</td></tr><tr><th scope=\"row\">D</th><td>Reserves</td></tr></tbody></table>")
    let partial = ReflowBlock.Table(columns: 3, rows: [.init(cells: [cell("Both", span: 2, header: true), cell("Tools")], header: false),
                                                       .init(cells: [cell("Alone", span: 2, header: true)], header: false)])
    #expect(EPUBTextEncoder.table(partial) == "<table><tbody><tr><th colspan=\"2\" scope=\"row\">Both</th><td>Tools</td></tr>"
        + "<tr><th colspan=\"2\" scope=\"row\">Alone</th></tr></tbody></table>")
    let spanningHead = ReflowBlock.Table(columns: 2, rows: [.init(cells: [cell("Title", span: 2)], header: true), first])
    #expect(EPUBTextEncoder.table(spanningHead) == "<table><thead><tr><th colspan=\"2\">Title</th></tr></thead>"
        + "<tbody><tr><th scope=\"row\">A</th><td>Credit</td></tr></tbody></table>")
}

// MARK: Row headers beyond the first column (#124.2)

@Test func fed47LiabilityLabelsNameTheirRowsToo() throws {
    let table = try table("fed-47")
    #expect(table.columns == 4)
    #expect(table.rows[0].header && table.rows[0].cells.map(\.span) == [2, 2])
    let body = table.rows.dropFirst()
    #expect(body.map { $0.cells.map(\.header) } == [
        [true, false, true, false], [true, false, true, false],
        // U.S. Treasury, General Account: the asset side is empty.
        [false, false, true, false],
        [true, false, true, false], [true, false, true, false]])
    #expect(body.map { $0.cells[2].text.text } == ["Deposits of depository institutions", "Federal Reserve notes in circulation",
                                                  "U.S. Treasury, General Account", "Capital and other liabilities", "Total"])
    #expect(EPUBTextEncoder.table(table).contains("<tr><td></td><td></td><th scope=\"row\">U.S. Treasury, General Account</th><td>1,587</td></tr>"))
}

private func line(_ text: String) -> [TextLine] {
    text.isEmpty ? [] : [TextLine(text: text, rect: CGRect(x: 100, y: 100, width: 60, height: 10), fontSize: 8)]
}

private func row(_ cells: [String], spans: [Int]? = nil, header: Bool = false) -> ShadedTableDetector.Table.Row {
    .init(cells: cells.enumerated().map { .init(lines: line($0.element), span: spans?[$0.offset] ?? 1) }, header: header)
}

private func labelled(_ rows: [ShadedTableDetector.Table.Row]) -> [[Bool]] {
    ShadedTableDetector.rowHeaders(rows).map { $0.cells.map(\.header) }
}

@Test func labelColumnsFollowHeaderCellsThatEachSpanALabelAndItsValues() {
    let lists = row(["Assets", "Liabilities"], spans: [2, 2], header: true)
    let body = [row(["Treasury securities", "4,197", "Deposits", "2,938"]),
                row(["", "", "General Account", "1,587"]),
                row(["Other assets", "939", "Capital", "642"])]
    // Positive: both label columns, the empty asset label a data cell.
    #expect(labelled([lists] + body) == [[false, false], [true, false, true, false], [false, false, true, false], [true, false, true, false]])
    // Each list is judged alone: repeated liability labels cost only that list its headers.
    let repeated = [lists, body[0], row(["", "", "Deposits", "1,587"]), body[2]]
    #expect(labelled(repeated) == [[false, false], [true, false, false, false], [false, false, false, false], [true, false, false, false]])
    // A liability label whose only value is on the asset side has none of its own.
    let noValue = [lists, body[0], row(["Notes", "12", "Other", ""]), body[2]]
    #expect(labelled(noValue) == [[false, false], [true, false, false, false], [true, false, false, false], [true, false, false, false]])
    let controls: [(String, [ShadedTableDetector.Table.Row], [[Bool]])] = [
        // A header of one spanning cell and one single-column cell is not a set of lists: the
        // first-column rule alone applies.
        ("one single-column header cell", [row(["Name", "Amounts", "Notes"], spans: [2, 1, 1], header: true),
                                            row(["Treasury", "4,197", "Deposits", "2,938"]), row(["Other", "939", "Capital", "642"])],
         [[false, false, false], [true, false, false, false], [true, false, false, false]]),
        // A single spanning header cell is a title over one table.
        ("one spanning header cell", [row(["Balance sheet"], spans: [4], header: true)] + body,
         [[false], [true, false, false, false], [false, false, false, false], [true, false, false, false]]),
        // Spans that do not cover the body's columns do not group them.
        ("spans short of the columns", [row(["Assets", "Liabilities"], spans: [2, 2], header: true),
                                         row(["Treasury", "4,197", "Deposits", "2,938", "x"]), row(["Other", "939", "Capital", "642", "y"])],
         [[false, false], [true, false, false, false, false], [true, false, false, false, false]]),
    ]
    for (name, rows, expected) in controls {
        #expect(labelled(rows) == expected, "\(name)")
    }
}
