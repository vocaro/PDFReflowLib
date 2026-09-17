import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Table headers and a borderless table (#121). Fed page 97's header sits on one coloured band per
// column, which the full-width header-band test rejected, so `Credit transfer` / `Debit transfer`
// were body cells. The first column of the Fed's text tables names each row (the PDF tags those
// cells `TH /Scope /Row`), but every cell was `td`. FAA page 131's borderless load-factor table
// reflowed as four scrambled paragraphs because PDFKit merges three of its rows' cells into one
// line each.

private func reflowed(_ page: PageContent) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func tables(in blocks: [ReflowBlock]) -> [ReflowBlock.Table] {
    blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }
}

private func texts(_ row: ReflowBlock.Table.Row) -> [String] { row.cells.map(\.text.text) }

// MARK: Header on one band per column (#121.1)

@Test func fed97HeaderOnColumnBandsIsTheHeaderRow() throws {
    let page = try SourceLayoutFixture.load("fed-97").content()
    let table = try #require(tables(in: reflowed(page)).first)
    #expect(table.columns == 2 && table.rows.count == 2)
    #expect(table.rows[0].header && texts(table.rows[0]) == ["Credit transfer", "Debit transfer"])
    #expect(!table.rows[1].header && table.rows[1].cells.count == 2)
    #expect(table.rows[1].cells[0].text.text.hasPrefix("Payroll direct deposits Government benefit payments"))
    // One body row: its first cell, a list of credit transfers, does not name a row.
    #expect(table.rows.allSatisfy { $0.cells.allSatisfy { !$0.header } })
    #expect(table.caption.first?.text == "Figure 6.5. Examples of automated clearinghouse transfers")
    let markup = EPUBTextEncoder.table(table)
    #expect(markup.contains("<thead><tr><th>Credit transfer</th><th>Debit transfer</th></tr></thead><tbody><tr><td>Payroll"))
    #expect(!markup.contains("scope"))
}

/// Fed page 97 with its two header bands (the 17.5-point-high tints over the header row) edited.
private func fed97(headerBands edit: ([CGRect]) -> [CGRect]) throws -> PageContent {
    var page = try SourceLayoutFixture.load("fed-97").content()
    let bands = page.tints.filter { abs($0.height - 17.5) < 1 && abs($0.minY - 151.3) < 1 }
    #expect(bands.count == 2)
    page.tints = page.tints.filter { !bands.contains($0) } + edit(bands.sorted { $0.minX < $1.minX })
    return page
}

@Test func columnBandsThatAreNotTheRowsOwnLeaveItABodyRow() throws {
    // Control: unedited, the header is read.
    #expect(try tables(in: reflowed(fed97 { $0 })).first?.rows.first?.header == true)
    let edits: [(String, ([CGRect]) -> [CGRect])] = [
        // Together the bands cover less than 90% of the table's width.
        ("narrow", { [$0[0], CGRect(x: $0[1].minX, y: $0[1].minY, width: 110, height: $0[1].height)] }),
        // The bands run down through the body row: they are column bands, not the header's.
        ("tall", { $0.map { CGRect(x: $0.minX, y: 96.6, width: $0.width, height: $0.maxY - 96.6) } }),
        // One band for a two-cell row.
        ("single", { [$0[0]] }),
        // The bands overlap by more than a body size.
        ("overlapping", { [$0[0], $0[1].offsetBy(dx: -20, dy: 0)] }),
    ]
    for (name, edit) in edits {
        let found = try tables(in: reflowed(fed97(headerBands: edit)))
        // As before #121 the table itself is still read, with its first row as data cells.
        let table = try #require(found.first, "\(name)")
        #expect(table.rows.first?.header == false, "\(name)")
        #expect(table.rows.first.map(texts) == ["Credit transfer", "Debit transfer"], "\(name)")
    }
}

// MARK: Row headers (#121.2)

@Test(arguments: [46, 47, 64, 83, 109, 120])
func fedFirstColumnLabelsAreRowHeaders(_ number: Int) throws {
    let page = try SourceLayoutFixture.load("fed-\(number)").content()
    let table = try #require(tables(in: reflowed(page)).first)
    let body = table.rows.filter { !$0.header && $0.cells.count > 1 }
    #expect(body.count >= 2, "fed-\(number)")
    for row in body {
        #expect(row.cells[0].header == !row.cells[0].text.text.isEmpty, "fed-\(number) \(texts(row))")
        #expect(row.cells.dropFirst().allSatisfy { !$0.header }, "fed-\(number) \(texts(row))")
    }
    // Header rows and section rows (one spanning cell) carry no row-header cells.
    #expect(table.rows.filter { $0.header || $0.cells.count == 1 }.allSatisfy { $0.cells.allSatisfy { !$0.header } }, "fed-\(number)")
    if number == 47 {
        // Table A's liabilities-only row: an empty asset label stays a data cell.
        let treasury = try #require(body.first { $0.cells[2].text.text == "U.S. Treasury, General Account" })
        #expect(!treasury.cells[0].header)
        #expect(body.filter { $0.cells[0].header }.count == 4)
    }
}

private func cell(_ text: String) -> ShadedTableDetector.Table.Cell {
    .init(lines: text.isEmpty ? [] : [TextLine(text: text, rect: CGRect(x: 100, y: 100, width: 60, height: 10), fontSize: 8)], span: 1)
}

private func row(_ cells: [String], header: Bool = false) -> ShadedTableDetector.Table.Row {
    .init(cells: cells.map(cell), header: header)
}

private func labelled(_ rows: [ShadedTableDetector.Table.Row]) -> [[Bool]] {
    ShadedTableDetector.rowHeaders(rows).map { $0.cells.map(\.header) }
}

@Test func rowHeadersNeedTwoDistinctLabelsWithValues() {
    let header = row(["Tool", "Definition"], header: true)
    let section = ShadedTableDetector.Table.Row(cells: [.init(lines: cell("General banking").lines, span: 2)], header: false)
    // Positive: two labelled rows; a section row, the header and an empty first cell stay data.
    #expect(labelled([header, section, row(["Discount window", "Lending"]), row(["", "Treasury"]), row(["Open market operations", "Buying"])])
        == [[false, false], [false], [true, false], [false, false], [true, false]])
    let controls: [(String, [ShadedTableDetector.Table.Row])] = [
        ("one labelled row", [header, row(["Payroll deposits", "Direct debits"])]),
        ("one labelled row beside an empty label", [header, row(["Payroll", "Debits"]), row(["", "Checks"])]),
        ("duplicate labels", [header, row(["Total", "7"]), row(["Total", "8"])]),
        ("a label without a value", [header, row(["Other assets", "939"]), row(["Notes", ""])]),
        ("labels without letters", [header, row(["1", "First step"]), row(["2", "Second step"])]),
        ("header rows only", [header, row(["A", "B"], header: true)]),
    ]
    for (name, rows) in controls {
        #expect(labelled(rows).allSatisfy { $0.allSatisfy { !$0 } }, "\(name)")
    }
}

@Test func rowHeaderCellsSerializeWithRowScope() {
    let table = ReflowBlock.Table(columns: 3, rows: [
        .init(cells: [.init(text: InlineText("Tool")), .init(text: InlineText("Definition"), span: 2)], header: true),
        .init(cells: [.init(text: InlineText("Group <A>"), span: 3)], header: false),
        .init(cells: [.init(text: InlineText("IORB & ON RRP"), header: true), .init(text: InlineText("Interest")), .init(text: InlineText("Rates"))], header: false),
        .init(cells: [.init(text: InlineText("Both"), span: 2, header: true), .init(text: InlineText("Tools"))], header: false),
    ])
    #expect(EPUBTextEncoder.table(table) == "<table><thead><tr><th>Tool</th><th colspan=\"2\">Definition</th></tr></thead><tbody>"
        + "<tr><td colspan=\"3\">Group &lt;A&gt;</td></tr>"
        + "<tr><th scope=\"row\">IORB &amp; ON RRP</th><td>Interest</td><td>Rates</td></tr>"
        + "<tr><th colspan=\"2\" scope=\"row\">Both</th><td>Tools</td></tr></tbody></table>")
}

// MARK: FAA page 131's borderless table (#121.3)

private let faaRows = [["CATEGORY", "LIMIT LOAD FACTOR"], ["Normal1", "3.8 to –1.52"],
                       ["Utility (mild acrobatics, including spins)", "4.4 to –1.76"], ["Acrobatic", "6.0 to –3.00"]]

@Test func faa131LoadFactorTableReadsAsATable() throws {
    let page = try SourceLayoutFixture.load("faa-131").content()
    let blocks = reflowed(page)
    let found = tables(in: blocks)
    #expect(found.count == 1)
    let table = try #require(found.first)
    #expect(table.columns == 2 && table.caption.isEmpty)
    #expect(table.rows.map(\.header) == [true, false, false, false])
    #expect(table.rows.map(texts) == faaRows)
    // FAA tags these first cells TD; no row headers are inferred for a borderless table.
    #expect(table.rows.allSatisfy { $0.cells.allSatisfy { !$0.header } })
    // The sentence introducing the table precedes it and the footnote follows; neither holds a cell.
    let paragraphs = blocks.map(\.text)
    let tableIndex = try #require(blocks.firstIndex { if case .table = $0.content { true } else { false } })
    let intro = try #require(paragraphs.firstIndex { $0.hasSuffix("specified for aircraft in the various categories are:") })
    let footnote = try #require(paragraphs.firstIndex { $0.hasPrefix("1 For aircraft with gross weight") })
    #expect(intro + 1 == tableIndex && tableIndex + 1 == footnote)
    #expect(!blocks.contains { block in
        if case .table = block.content { false } else { ["–1.76", "Acrobatic", "CATEGORY"].contains { block.text.contains($0) } }
    })
}

/// FAA page 131 with the split rows merged back into the single lines PDFKit returns.
private func faa131Merged() throws -> PageContent {
    var page = try SourceLayoutFixture.load("faa-131").content()
    for (left, right) in [("CATEGORY", "LIMIT LOAD FACTOR"), ("Normal1", "3.8 to –1.52"), ("Acrobatic", "6.0 to –3.00")] {
        let a = try #require(page.lines.first { $0.text == left }), b = try #require(page.lines.first { $0.text == right })
        let index = try #require(page.lines.firstIndex(of: a))
        page.lines.removeAll { $0 == a || $0 == b }
        page.lines.insert(TextLine(text: "\(left) \(right)", rect: a.rect.union(b.rect), fontSize: a.fontSize), at: index)
    }
    return page
}

@Test func faa131MergedRowsAreNotATable() throws {
    // Reproducer: as PDFKit reads it (before the extraction split), the rows reflow scrambled
    // and no grid can be read from them.
    let blocks = reflowed(try faa131Merged())
    #expect(tables(in: blocks).isEmpty)
    #expect(blocks.contains { $0.text == "CATEGORY LIMIT LOAD FACTOR Normal1 3.8 to –1.52" })
    #expect(blocks.contains { $0.text == "including spins) Acrobatic 6.0 to –3.00" })
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 10) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 1.15), fontSize: size)
}

/// The FAA table's split lines, with a neighbouring page column's prose on the right.
private func faaLines(heading: (String, String) = ("CATEGORY", "LIMIT LOAD FACTOR")) -> [TextLine] {
    [line(heading.0, x: 68, y: 680, width: 54), line(heading.1, x: 163, y: 680, width: 100),
     line("Normal", x: 78, y: 665, width: 34), line("3.8 to –1.52", x: 189, y: 665, width: 48),
     line("Utility (mild acrobatics,", x: 47, y: 650, width: 96), line("4.4 to –1.76", x: 189, y: 650, width: 48),
     line("including spins)", x: 63, y: 637, width: 64),
     line("Acrobatic", x: 75, y: 622, width: 39), line("6.0 to –3.00", x: 189, y: 622, width: 48),
     line("factor increases at a terrific rate after a bank has reached", x: 285, y: 669, width: 237),
     line("45° or 50°. The load factor for any aircraft in a coordinated", x: 285, y: 657, width: 237)]
}

@Test func borderlessTablesNeedCapitalHeadingsAndAFullGrid() {
    let found = BorderlessTableDetector.tables(in: faaLines())
    #expect(found.count == 1)
    #expect(found.first?.rows.map { $0.cells.map { $0.lines.map(\.text).joined(separator: " ") } }
        == [["CATEGORY", "LIMIT LOAD FACTOR"], ["Normal", "3.8 to –1.52"], ["Utility (mild acrobatics, including spins)", "4.4 to –1.76"], ["Acrobatic", "6.0 to –3.00"]])
    var tagged = faaLines()
    for index in tagged.indices where tagged[index].text.hasPrefix("Normal") {
        tagged[index].structure = TextStructure(group: 1, order: 1, headingLevel: 0)
    }
    let controls: [(String, [TextLine])] = [
        ("title-case heading", faaLines(heading: ("Category", "Limit load factor"))),
        ("one body row", faaLines().filter { $0.rect.minY >= 665 || $0.rect.minX >= 285 }),
        ("first body row without a value", faaLines().filter { $0.text != "3.8 to –1.52" }),
        ("a label running across the gap", faaLines().map { $0.text == "Normal" ? line("Normal category aircraft", x: 78, y: 665, width: 105) : $0 }),
        ("prose under the heading", [faaLines()[0], faaLines()[1],
            line("There is an upward graduation in load factor with the", x: 36, y: 665, width: 237)] + faaLines().dropFirst(4)),
        ("a smaller first row", faaLines().map { $0.text == "Normal" || $0.text == "3.8 to –1.52" ? line($0.text, x: $0.rect.minX, y: 665, width: $0.rect.width, size: 7) : $0 }),
        ("a tagged row", tagged),
        ("headings far apart", faaLines().map { $0.text == "LIMIT LOAD FACTOR" ? line($0.text, x: 240, y: 680, width: 100) : $0 }),
        ("rows too far below the heading", faaLines().map { $0.rect.minY < 680 && $0.rect.minX < 285 ? line($0.text, x: $0.rect.minX, y: $0.rect.minY - 12, width: $0.rect.width) : $0 }),
    ]
    for (name, lines) in controls {
        #expect(BorderlessTableDetector.tables(in: lines).isEmpty, "\(name)")
    }
}

// MARK: The extraction split (#121.3)

/// FAA page 131's table set as the source sets it (Times-Roman 10, centred cells), with prose above.
private func borderlessPDF(heading: (String, String) = ("CATEGORY", "LIMIT LOAD FACTOR"), normalValueX: CGFloat = 189,
                           rule: Bool = false, bodyRows: Bool = true) -> Data {
    var content = rule ? "0 G 0.5 w 40 645 m 260 645 l S\n" : ""
    var rows: [(String, CGFloat, String?, CGFloat, CGFloat)] = [(heading.0, 68, heading.1, 163, 682)]
    if bodyRows {
        rows += [("Normal", 78, "3.8 to -1.52", normalValueX, 667), ("Utility \\(mild acrobatics,", 47, "4.4 to -1.76", 189, 652),
                 ("including spins\\)", 63, nil, 0, 639.5), ("Acrobatic", 75, "6.0 to -3.00", 189, 624.5)]
    }
    for (left, leftX, right, rightX, y) in rows {
        content += "BT /F1 10 Tf \(leftX) \(y) Td (\(left)) Tj ET\n"
        if let right { content += "BT /F1 10 Tf \(rightX) \(y) Td (\(right)) Tj ET\n" }
    }
    content += "BT /F1 10 Tf 36 710 Td (factors specified for aircraft in the various categories are the following:) Tj ET\n"
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>",
    ])
}

private func extracted(_ data: Data, split: Bool) throws -> [String] {
    let page = try #require(PDFDocument(data: data)?.page(at: 0))
    let paints = GraphicsReader.read(try #require(page.pageRef)).paints.map(\.rect)
    return try NativeTextReader.lines(on: page, limit: 100_000, borderlessTableInk: split ? paints : nil).map(\.text)
}

@Test func borderlessRowsPDFKitMergesAreSplitAtTheColumnGap() throws {
    let merged = ["CATEGORY LIMIT LOAD FACTOR", "Normal 3.8 to -1.52", "Acrobatic 6.0 to -3.00"]
    // Reproducer: PDFKit merges three rows' cells, but keeps the Utility row's apart.
    let unsplit = try extracted(borderlessPDF(), split: false)
    #expect(merged.allSatisfy(unsplit.contains))
    #expect(unsplit.contains("Utility (mild acrobatics,") && unsplit.contains("4.4 to -1.76"))
    let lines = try extracted(borderlessPDF(), split: true)
    #expect(lines == ["factors specified for aircraft in the various categories are the following:", "CATEGORY", "LIMIT LOAD FACTOR",
                      "Normal", "3.8 to -1.52", "Utility (mild acrobatics,", "4.4 to -1.76", "including spins)", "Acrobatic", "6.0 to -3.00"])
    let controls: [(String, Data)] = [
        ("title-case heading", borderlessPDF(heading: ("Category", "Limit load factor"))),
        ("a drawn rule inside the table", borderlessPDF(rule: true)),
        // A row whose cells stand closer than two ems ends the run before the split pair.
        ("tight row under the heading", borderlessPDF(normalValueX: 118)),
    ]
    for (name, data) in controls {
        let control = try extracted(data, split: true)
        #expect(control.contains("CATEGORY LIMIT LOAD FACTOR") || control.contains("Category Limit load factor"), "\(name): \(control)")
        #expect(control.contains("Acrobatic 6.0 to -3.00"), "\(name): \(control)")
    }
    // The heading alone is not a table: nothing beneath it to pair with.
    #expect(try extracted(borderlessPDF(bodyRows: false), split: true).contains("CATEGORY LIMIT LOAD FACTOR"))
}
