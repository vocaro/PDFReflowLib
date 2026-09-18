import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Borderless tables whose columns only their alignment draws (#150, #137). Census pages 12 and 15
// hold numeric tables under a header and a rule, with no cell rules, no shading and lower-case
// headings, and PDFKit returns most of their rows as one line (`rnkswp05 0.8861 0.9620`); no
// table reader read them, so #143 kept those pages on OCR with table images although their text
// now decodes. FAA page 410's VOR/VORTAC service-volume table reflowed as scrambled paragraphs
// for the same reason. The fixtures are captured after extraction, which splits the rows at their
// columns (`NativeTextReader.splitColumnGrids`); re-merging each row reproduces what PDFKit returns.

private func reflowed(_ page: PageContent) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func tables(in blocks: [ReflowBlock]) -> [ReflowBlock.Table] {
    blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }
}

private func paragraphs(in blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { block -> String? in
        switch block.content {
        case let .paragraph(text): text.text
        case let .heading(_, text, _): text.text
        default: nil
        }
    }
}

private func texts(_ row: ReflowBlock.Table.Row) -> [String] { row.cells.map(\.text.text) }

/// The lines with each baseline's cells joined into one line, as PDFKit returns a merged row.
private func merged(_ lines: [TextLine], within area: CGRect) -> [TextLine] {
    var rows: [[TextLine]] = []
    for line in lines.filter({ area.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) })
        .sorted(by: { $0.rect.minY > $1.rect.minY || $0.rect.minY == $1.rect.minY && $0.rect.minX < $1.rect.minX }) {
        if let last = rows.last?.first, abs(last.rect.minY - line.rect.minY) <= 1.5 { rows[rows.count - 1].append(line) }
        else { rows.append([line]) }
    }
    let joined = rows.map { row in
        TextLine(text: row.map(\.text).joined(separator: " "), rect: union(row.map(\.rect)), fontSize: row[0].fontSize)
    }
    return lines.filter { !area.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) } + joined
}

// MARK: Census pages 12 and 15

@Test func censusPage12TablesReadWithTheirHeadersAndRowLabels() throws {
    let page = try SourceLayoutFixture.load("census-12").content()
    let blocks = reflowed(page)
    let found = tables(in: blocks)
    #expect(found.count == 2)
    let table2 = try #require(found.first)
    try #require(table2.columns == 3 && table2.rows.count == 14)
    #expect(table2.rows[0].header && texts(table2.rows[0]) == ["", "d metric", "l metric"])
    #expect(texts(table2.rows[1]) == ["rnkswp05", "0.8861", "0.9620"])
    #expect(texts(table2.rows[4]) == ["add05", "0.7972", "0.7500"])
    #expect(texts(table2.rows[13]) == ["scalmixadd20", "0.0269", "0.1241"])
    // Distinct labels with values beside them name their rows (#121's rule).
    #expect(table2.rows.dropFirst().allSatisfy { $0.cells[0].header && !$0.cells[1].header && !$0.cells[2].header })
    let table3 = try #require(found.last)
    try #require(table3.columns == 7 && table3.rows.count == 15)
    // The group headings each span the three scores beneath them; the label column's are empty.
    #expect(table3.rows[0].header && texts(table3.rows[0]) == ["", "d Metric", "l Metric"])
    #expect(table3.rows[0].cells.map(\.span) == [1, 3, 3])
    #expect(table3.rows[1].header && texts(table3.rows[1]) == ["", "Ascore", "Dscore", "Sscore", "Ascore", "Dscore", "Sscore"])
    #expect(texts(table3.rows[2]) == ["rnkswp05", "46.11", "47.06", "46.66", "49.90", "50.85", "49.45"])
    #expect(texts(table3.rows[14]) == ["scalmixadd20", "2.89", "7.06", "4.94", "7.75", "11.92", "9.80"])
    // The titles stay paragraphs before their tables, and no row runs into the next.
    let prose = paragraphs(in: blocks).joined(separator: "\n")
    #expect(prose.contains("Table 2. Domingo Data Reidentification Rates") && prose.contains("Table 3. Domingo Data Scoring Metrics"))
    #expect(!prose.contains("0.9620") && !prose.contains("rnkswp10"))
    let markup = EPUBTextEncoder.table(table3)
    #expect(markup.contains(#"<th colspan="3">d Metric</th>"#) && markup.contains(#"<th scope="row">rnkswp05</th><td>46.11</td>"#))
}

@Test func censusPage15TablesReadIncludingNumbersAWordSpaceApart() throws {
    let page = try SourceLayoutFixture.load("census-15").content()
    let found = tables(in: reflowed(page))
    #expect(found.count == 2)
    let table7 = try #require(found.first)
    try #require(table7.columns == 7 && table7.rows.count == 15)
    #expect(texts(table7.rows[0]) == ["", "Full File Matches", "20% Zone Matches"] && table7.rows[0].cells.map(\.span) == [1, 3, 3])
    #expect(texts(table7.rows[6]) == ["add01_sw", "0.70", "16.80", "11.65", "0.65", "16.75", "11.60"])
    // Table 8's numbers stand a word space apart; each stack of numbers sharing a right edge is a
    // column of its own.
    let table8 = try #require(found.last)
    try #require(table8.columns == 10 && table8.rows.count == 14)
    #expect(texts(table8.rows[0]) == ["", "IL1", "IL1s", "IL2", "IL3", "IL4", "IL5", "s0", "s1", "s2"])
    #expect(texts(table8.rows[1]) == ["rnkswp05", "0.114", "0.081", "1.407", "39.020", "158.950", "0.123", "48.875", "39.923", "40.141"])
    #expect(texts(table8.rows[13]) == ["scalmixadd20", "1.681", "1.004", "0.256", "0.693", "0.069", "0.033", "0.263", "0.547", "0.341"])
}

@Test func censusRowsAsPDFKitMergesThemAreNoTableAndKeepTheNumericGridGuard() throws {
    for name in ["census-12", "census-15"] {
        let page = try SourceLayoutFixture.load(name).content()
        #expect(!PDFReflowLibPipeline.holdsUnreadNumericGrid(page.lines), "\(name)")
        // Reproducer: each row as PDFKit returns it, one line, reads as no table and holds a
        // numeric grid, so the page keeps #38's path.
        var unsplit = page
        unsplit.lines = merged(page.lines, within: CGRect(x: 150, y: 170, width: 320, height: 450))
        #expect(tables(in: reflowed(unsplit)).isEmpty, "\(name)")
        #expect(PDFReflowLibPipeline.holdsNumericGrid(unsplit.lines) && PDFReflowLibPipeline.holdsUnreadNumericGrid(unsplit.lines), "\(name)")
    }
}

// MARK: FAA page 410

@Test func faa410ServiceVolumesReadAsAThreeColumnTable() throws {
    let page = try SourceLayoutFixture.load("faa-410").content()
    let blocks = reflowed(page)
    let table = try #require(tables(in: blocks).first)
    #expect(tables(in: blocks).count == 1)
    try #require(table.columns == 3 && table.rows.count == 7)
    // `Distance` above `(Miles)` is one heading; PDFKit reads the letter-spaced `(Miles)` apart.
    #expect(table.rows[0].header && texts(table.rows[0]) == ["Class", "Altitudes", "Distance ( M i l e s )"])
    #expect(table.rows.dropFirst().map(texts) == [
        ["T", "12,000' and below", "25"], ["L", "Below 18,000'", "40"], ["H", "Below 14,500'", "40"],
        ["H", "Within the conterminous 48 states only, between 14,500 and 17,999'", "100"],
        ["H", "18,000'—FL 450", "130"], ["H", "FL 450—60,000'", "100"]])
    // The class letters repeat, so they do not name their rows.
    #expect(table.rows.allSatisfy { $0.cells.allSatisfy { !$0.header } })
    let prose = paragraphs(in: blocks).joined(separator: "\n")
    #expect(prose.contains("The normal useful range for the various classes is shown in the following table:"))
    #expect(!prose.contains("12,000' and below") && !prose.contains("Altitudes ("))
    // Reproducer: the rows as PDFKit merges them read as no table.
    var unsplit = page
    unsplit.lines = merged(page.lines, within: CGRect(x: 70, y: 460, width: 242, height: 110))
    #expect(tables(in: reflowed(unsplit)).isEmpty)
}

@Test func faa410TableNeedsTheWholeTaggedParagraphInside() throws {
    let page = try SourceLayoutFixture.load("faa-410").content()
    let tagged = page.lines.filter { $0.text == "100" && $0.structure != nil }
    #expect(tagged.count == 1)
    #expect(BorderlessTableDetector.alignedTables(in: page.lines).count == 1)
    // Control: the wrapped altitude's paragraph also claims a line outside the table.
    let group = try #require(tagged.first?.structure?.group)
    var outside = TextLine(text: "Outside prose tagged into the same paragraph.", rect: CGRect(x: 72, y: 300, width: 200, height: 11.5), fontSize: 10)
    outside.structure = tagged.first?.structure
    #expect(BorderlessTableDetector.alignedTables(in: page.lines + [outside]).isEmpty, "\(group)")
    // Control: a heading tag keeps a line out of any table.
    let headed = page.lines.map { line -> TextLine in
        guard line.text == "25" else { return line }
        var copy = line
        copy.structure = TextStructure(group: 1, order: 1, headingLevel: 3, lineCount: 1)
        return copy
    }
    #expect(BorderlessTableDetector.alignedTables(in: headed).isEmpty)
}

// MARK: The rule, on synthetic lines

/// A table set in 9-point type at 11-point leading: `columns` gives each column's edge and whether
/// its cells are flush right against it; cells are 4.5 points a character wide.
private func grid(_ rows: [[String]], columns: [(edge: CGFloat, right: Bool)], top: CGFloat = 600,
                  leading: CGFloat = 11, size: CGFloat = 9) -> [TextLine] {
    rows.enumerated().flatMap { index, row in
        row.enumerated().compactMap { column, text -> TextLine? in
            guard !text.isEmpty else { return nil }
            let width = CGFloat(text.count) * size * 0.5
            let x = columns[column].right ? columns[column].edge - width : columns[column].edge
            return TextLine(text: text, rect: CGRect(x: x, y: top - CGFloat(index) * leading, width: width, height: size * 1.15), fontSize: size)
        }
    }
}

private let censusColumns: [(edge: CGFloat, right: Bool)] = [(245, false), (331, true), (368, true)]
private let censusRows = [["", "d metric", "l metric"], ["rnkswp05", "0.8861", "0.9620"], ["rnkswp10", "0.2694", "0.7287"],
                          ["add05", "0.7972", "0.7500"], ["mixadd01", "0.7667", "0.7176"]]

@Test func alignedColumnsUnderAHeaderReadAsATable() throws {
    let table = try #require(BorderlessTableDetector.alignedTables(in: grid(censusRows, columns: censusColumns)).first)
    #expect(table.columns == 3 && table.rows.count == 5 && table.rows[0].header)
    #expect(table.rows[3].cells.map { $0.lines.map(\.text).joined() } == ["add05", "0.7972", "0.7500"])
    // Years head their columns over an empty label heading.
    let years = try #require(BorderlessTableDetector.alignedTables(in: grid([["", "2023", "2024"]] + censusRows.dropFirst(),
                                                                              columns: censusColumns)).first)
    #expect(years.rows[0].header && years.rows[0].cells.map { $0.lines.map(\.text).joined() } == ["", "2023", "2024"])
}

/// The grids `ColumnGrid` reads from lines directly, as extraction reads a region's words.
private func directGrids(_ lines: [TextLine]) -> [ColumnGrid.Grid] {
    ColumnGrid.grids(in: ColumnGrid.baselines(lines.map { ColumnGrid.Piece(rect: $0.rect, text: $0.text, size: $0.fontSize) }))
}

@Test func alignedColumnsWithoutTableEvidenceKeepTheirReflow() throws {
    // Control: the synthetic table reads both ways.
    #expect(directGrids(grid(censusRows, columns: censusColumns)).count == 1)
    let controls: [(String, [TextLine])] = [
        // No header above the body: a list of figures, not a table.
        ("no header", grid(Array(censusRows.dropFirst()), columns: censusColumns)),
        // Two body rows are not enough.
        ("two rows", grid(Array(censusRows.prefix(3)), columns: censusColumns)),
        // Cells end in numbers, but no column holds one number in every row: a list of places.
        ("no numeric column", grid([["", "Topic", "Where"], ["Flags", "folding", "page 12"], ["Seals", "history", "page 14"],
                                    ["Songs", "anthem", "page 16"]], columns: censusColumns)),
        // Every row opens with a list marker: exercises set in columns.
        ("marker column", grid([["", "Problem", "Answer"], ["a)", "12", "5"], ["b)", "14", "7"], ["c)", "16", "9"]],
                               columns: censusColumns)),
        // Dot leaders join entries to their values.
        ("leaders", grid([["", "Size", "Hoist"], ["Small", ". . . . 4", "6"], ["Medium", ". . . . 5", "8"], ["Large", ". . . . 6", "10"]],
                         columns: censusColumns)),
        // A cell wider than fifteen ems is prose, not a cell.
        ("wide cell", grid(censusRows.map { $0.enumerated().map { $0.offset == 0 && !$0.element.isEmpty ? $0.element + " and a great deal of running prose here" : $0.element } },
                           columns: [(100, false), (350, true), (400, true)])),
        // A heading line that does not divide over the columns (Census page 14's `Total File
        // Matches 20% Zone Matches`, one line): the first body row reads as a body row, so it
        // heads nothing either.
        ("body row above", grid(Array(censusRows.dropFirst()), columns: censusColumns) + [
            TextLine(text: "Total File Matches 20% Zone Matches", rect: CGRect(x: 277, y: 611, width: 118, height: 10), fontSize: 9)]),
    ]
    for (name, lines) in controls {
        #expect(BorderlessTableDetector.alignedTables(in: lines).isEmpty, "\(name)")
        #expect(directGrids(lines).isEmpty, "\(name)")
    }
    // A column whose cells neither start nor end together is not a column.
    var ragged = grid(censusRows, columns: censusColumns)
    ragged = ragged.map { line in
        guard line.text == "0.2694" else { return line }
        var copy = line; copy.rect.origin.x -= 6; return copy
    }
    #expect(BorderlessTableDetector.alignedTables(in: ragged).isEmpty && directGrids(ragged).isEmpty)
    // Words: a channel narrower than twice the gaps inside the cells beside it divides no columns.
    // Each label's two words stand 3.5 points apart, and the channel after them is 6.5.
    var words: [TextLine] = []
    for (index, row) in censusRows.enumerated() {
        let y = 600 - CGFloat(index) * 11
        if !row[0].isEmpty {
            words += [TextLine(text: "set", rect: CGRect(x: 245, y: y, width: 13.5, height: 10), fontSize: 9),
                      TextLine(text: row[0], rect: CGRect(x: 262, y: y, width: 36, height: 10), fontSize: 9)]
        }
        words += [TextLine(text: row[1], rect: CGRect(x: 304.5, y: y, width: 26.5, height: 10), fontSize: 9),
                  TextLine(text: row[2], rect: CGRect(x: 341.5, y: y, width: 26.5, height: 10), fontSize: 9)]
    }
    #expect(directGrids(words).isEmpty)
    // Control: with the labels' words a word space apart, the channel divides the columns.
    #expect(directGrids(words.map { line in
        guard line.rect.minX == 262 else { return line }
        var copy = line; copy.rect.origin.x = 260.5; return copy
    }).count == 1)
}

@Test func aContinuationLineContinuesOneCellAndFillsEmptyOnes() throws {
    // FAA's wrapped altitude: the row's second line continues its altitude and sets its distance.
    let columns: [(edge: CGFloat, right: Bool)] = [(75, false), (144, false), (309, true)]
    let rows = [["Class", "Altitudes", "Miles"], ["T", "12,000' and below", "25"], ["L", "Below 18,000'", "40"],
                ["H", "Within the 48 states", ""], ["", "only, between 14,500", "100"], ["H", "18,000'—FL 450", "130"]]
    let table = try #require(BorderlessTableDetector.alignedTables(in: grid(rows, columns: columns)).first)
    #expect(table.rows.count == 5)
    #expect(table.rows[3].cells.map { $0.lines.map(\.text).joined(separator: " ") } == ["H", "Within the 48 states only, between 14,500", "100"])
    // Control: two timelines side by side, where the second's new entry continues no cell of the
    // first; a line continuing two cells ends the table.
    let timelines: [(edge: CGFloat, right: Bool)] = [(40, false), (76, false), (202, false), (241, false)]
    let sideBySide = [["Time", "Event", "Time", "Event"], ["7:59", "Takeoff", "8:14", "Takeoff"],
                      ["8:14", "Last routine radio", "8:42", "Last radio"], ["", "communication", "8:47", "Transponder"],
                      ["8:19", "Attendant notifies", "8:52", "Attendant"]]
    #expect(BorderlessTableDetector.alignedTables(in: grid(sideBySide, columns: timelines)).isEmpty)
}

@Test func higherHeadingsSpanTheColumnsNearestThemOrContinueAnAlignedHeading() throws {
    // Census Table 3: centred group headings over three scores each.
    let columns: [(edge: CGFloat, right: Bool)] = [(193, false), (277, true), (307, true), (335, true), (364, true), (394, true), (422, true)]
    var rows = [["", "", "", "", "", "", ""], ["", "Ascore", "Dscore", "Sscore", "Ascore", "Dscore", "Sscore"]]
    rows += (0..<3).map { ["label\($0)", "46.11", "47.06", "46.66", "49.90", "50.85", "49.45"] }
    var lines = grid(rows, columns: columns)
    lines += [TextLine(text: "d Metric", rect: CGRect(x: 275, y: 600, width: 35, height: 10), fontSize: 9),
              TextLine(text: "l Metric", rect: CGRect(x: 363.5, y: 600, width: 32.7, height: 10), fontSize: 9)]
    let table = try #require(BorderlessTableDetector.alignedTables(in: lines).first)
    #expect(table.rows[0].cells.map(\.span) == [1, 3, 3])
    // `l Metric` ends two points short of its column's edge: near, but no continuation of `Sscore`.
    #expect(table.rows.count == 5 && table.rows[1].cells.count == 7)
    // FAA: `Distance` ends exactly on the distance column's edge, as `(Miles)` does beneath it.
    let faa: [(edge: CGFloat, right: Bool)] = [(75, false), (144, false), (309, true)]
    var stacked = grid([["", "", ""], ["Class", "Altitudes", "(Miles)"], ["T", "12,000' and below", "25"],
                        ["L", "Below 18,000'", "40"], ["H", "Below 14,500'", "40"]], columns: faa)
    stacked.append(TextLine(text: "Distance", rect: CGRect(x: 309 - 36, y: 600, width: 36, height: 10), fontSize: 9))
    let heading = try #require(BorderlessTableDetector.alignedTables(in: stacked).first)
    #expect(heading.rows.count == 4 && heading.rows[0].cells.map { $0.lines.map(\.text).joined(separator: " ") } == ["Class", "Altitudes", "Distance (Miles)"])
}

@Test func aNumericGridATableReadsNoLongerHoldsARepairedPage() throws {
    // Cells that each hold two decimals (a range beside its value) make a numeric grid; read as a
    // table they no longer keep an index-glyph page on #38's path.
    let rows = [["Class", "Range", "Miles"], ["T", "0.5 to 1.5", "25"], ["L", "1.5 to 2.5", "40"], ["H", "2.5 to 3.5", "130"]]
    let lines = grid(rows, columns: [(75, false), (144, false), (309, true)])
    #expect(PDFReflowLibPipeline.holdsNumericGrid(lines))
    #expect(!PDFReflowLibPipeline.holdsUnreadNumericGrid(lines))
    // Control: without the header no table reads them, and the grid holds the page.
    #expect(PDFReflowLibPipeline.holdsUnreadNumericGrid(Array(lines.filter { !["Class", "Range", "Miles"].contains($0.text) })))
}

@Test func aProseColumnBesideTheTableStaysOutOfIt() throws {
    var lines = grid(censusRows, columns: censusColumns)
    // A page column of prose to the right, its baselines between the table's.
    lines += (0..<8).map { TextLine(text: "Running prose in the neighbouring page column, line \($0) 12", rect: CGRect(x: 380, y: 603 - CGFloat($0) * 7, width: 200, height: 10), fontSize: 9) }
    let table = try #require(BorderlessTableDetector.alignedTables(in: lines).first)
    #expect(table.rows.count == 5 && table.lines.allSatisfy { $0.rect.maxX < 370 })
}

// MARK: The extraction split

/// Census Table 2 as its source sets it: each row one show, its cells positioned by TJ
/// adjustments, so PDFKit returns the row as one line; a title, the header and prose around.
private func censusPDF(header: Bool = true, labels: [String] = ["rnkswp05", "rnkswp10", "add05", "mixadd01"]) -> Data {
    let values = [("0.8861", "0.9620"), ("0.2694", "0.7287"), ("0.7972", "0.7500"), ("0.7667", "0.7176")]
    var content = "BT /F1 9 Tf 210 640 Td (Table 2. Domingo Data Reidentification Rates) Tj ET\n"
    if header { content += "BT /F1 9 Tf 301 612 Td (d metric) Tj 38 0 Td (l metric) Tj ET\n" }
    for (index, (label, value)) in zip(labels, values).enumerated() {
        let y = 600 - index * 11
        // Times-Roman digits are half an em; the label is followed by enough adjustment to reach x 306.
        let labelWidth = label.reduce(0) { $0 + ($1.isNumber ? 500 : 480) }
        let pad = Int((306 - 245) * 1000 / 9) - labelWidth
        content += "BT /F1 9 Tf 245 \(y) Td [(\(label)) -\(pad) (\(value.0)) -1230 (\(value.1))] TJ ET\n"
    }
    content += "BT /F1 9 Tf 150 520 Td (The table above lists the reidentification rates of each masking method.) Tj ET\n"
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>",
    ])
}

private func extracted(_ data: Data, split: Bool) throws -> [TextLine] {
    let page = try #require(PDFDocument(data: data)?.page(at: 0))
    let paints = GraphicsReader.read(try #require(page.pageRef)).paints.map(\.rect)
    return try NativeTextReader.lines(on: page, limit: 100_000, borderlessTableInk: split ? paints : nil)
}

@Test func mergedRowsOfAnAlignedTableAreSplitIntoCells() throws {
    // Reproducer: PDFKit returns each row as one line.
    let unsplit = try extracted(censusPDF(), split: false).map(\.text)
    #expect(unsplit.contains("rnkswp05 0.8861 0.9620") && unsplit.contains("d metric l metric"))
    let lines = try extracted(censusPDF(), split: true)
    let texts = lines.map(\.text)
    #expect(["rnkswp05", "0.8861", "0.9620", "mixadd01", "0.7667", "0.7176", "d metric", "l metric"].allSatisfy(texts.contains), "\(texts)")
    #expect(texts.contains("Table 2. Domingo Data Reidentification Rates"))
    #expect(texts.contains("The table above lists the reidentification rates of each masking method."))
    let table = try #require(BorderlessTableDetector.alignedTables(in: lines).first)
    #expect(table.rows.count == 5 && table.columns == 3)
    // Controls: without a header, or without numbers, the rows stay as PDFKit returns them.
    #expect(try extracted(censusPDF(header: false), split: true).map(\.text).contains("rnkswp05 0.8861 0.9620"))
}

/// Pages drawn in a Type1 font whose `Differences` name each code `G<code + 3>` (#143's shifted
/// Census fonts), 520 units a glyph at 9 points. Each line is (x, y, TJ elements): strings and
/// adjustments in thousandths of an em.
private func shiftedTablePDF(_ pages: [[(x: CGFloat, y: CGFloat, parts: [Any])]]) -> Data {
    let strings = pages.flatMap { $0 }.flatMap { $0.parts.compactMap { $0 as? String } }
    let codes = Set(strings.flatMap { $0.unicodeScalars.map(\.value) }.filter { $0 != 32 }).sorted()
    let differences = "[" + codes.map { "\($0) /G\($0 + 3)" }.joined(separator: " ") + "]"
    let widths = "/FirstChar 0 /LastChar 255 /Widths [" + Array(repeating: "520", count: 256).joined(separator: " ") + "]"
    var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "",
                   "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica \(widths) /Encoding << /Differences \(differences) >> >>"]
    var kids: [String] = []
    for page in pages {
        var content = ""
        for line in page {
            let elements = line.parts.map { part -> String in
                if let text = part as? String { return "(\(text))" }
                return "\(part)"
            }
            content += "BT /F1 9 Tf 1 0 0 1 \(line.x) \(line.y) Tm [\(elements.joined(separator: " "))] TJ ET\n"
        }
        objects.append(testPDFStream(content))
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents \(objects.count) 0 R >>")
        kids.append("\(objects.count) 0 R")
    }
    objects[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"
    return testPDF(objects: objects)
}

@Test func aShiftedFontTableUnderAHeaderReflowsNativelyAsATable() async throws {
    // Prose that establishes the font's offset, then Census Table 2's shape: each row one TJ show
    // whose adjustments set the numbers in two columns, PDFKit's one line per row.
    let words = ["This paper describes methods for data perturbation that include rank swapping.",
                 "It also describes enhanced methods of reidentification using record linkage.",
                 "The empirical comparisons use variants of the framework for measuring loss.",
                 "Section 5 gives the discussion and the final section consists of remarks."]
    let prose = words.enumerated().map { (x: CGFloat(72), y: CGFloat(700 - $0.offset * 14),
                                           parts: $0.element.split(separator: " ").map(String.init).flatMap { [$0, -333] as [Any] }) }
    let rows = [("rnkswp05", "0.8861", "0.9620"), ("rnkswp10", "0.2694", "0.7287"), ("add05", "0.7972", "0.7500"),
                ("scalmixadd01", "0.7704", "0.7370")]
    func table(header: Bool) -> [(x: CGFloat, y: CGFloat, parts: [Any])] {
        var lines: [(x: CGFloat, y: CGFloat, parts: [Any])] = []
        if header { lines += [(220, 592, ["Ascore"]), (280, 592, ["Dscore"])] }
        for (index, row) in rows.enumerated() {
            // Numbers start at x 220 and 280: 4.68 points a glyph.
            let pad = Int(((220 - 100) - CGFloat(row.0.count) * 4.68) / 9 * 1000)
            lines.append((100, CGFloat(581 - index * 11), [row.0, -pad, row.1, -3547, row.2]))
        }
        return lines
    }
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("shifted-table.pdf")
    // The prose beneath each table gives its page enough words for #38's statistics.
    let below = prose.map { (x: $0.x, y: $0.y - 220, parts: $0.parts) }
    try shiftedTablePDF([prose, table(header: true) + below, table(header: false) + below]).write(to: url)
    #expect(try #require(PDFDocument(url: url)?.page(at: 1)?.string).contains("uqnvzs38"))
    for policy in [ConversionOptions.OCRPolicy.never, .automatic] {
        var options = ConversionOptions(); options.ocr = policy
        options.removeRepeatedHeadersAndFooters = false
        let result = try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
            workspace: dir.appendingPathComponent("work-\(policy)"), progress: { _ in })
        // The table page reflows natively with its table; without a header the rows are a numeric
        // grid no table reads, and the page keeps #38's path.
        #expect(result.warnings.filter { $0.code == .damagedTextEncoding }.map(\.page) == [3], "\(policy)")
        let found = result.document.blocks.filter { $0.page == 2 }.compactMap { block -> ReflowBlock.Table? in
            if case let .table(table) = block.content { table } else { nil }
        }
        let table = try #require(found.first, "\(policy)")
        #expect(table.rows.map { $0.cells.map(\.text.text) } == [["", "Ascore", "Dscore"], ["rnkswp05", "0.8861", "0.9620"],
            ["rnkswp10", "0.2694", "0.7287"], ["add05", "0.7972", "0.7500"], ["scalmixadd01", "0.7704", "0.7370"]], "\(policy)")
    }
}

@Test func styledTextDividesAtItsWordsIntoCells() throws {
    let text = InlineText(elements: [.text("rnkswp05 ", []), .text("0.8861", .bold), .text("  0.9620", [])])
    let parts = try #require(NativeTextReader.slices(text, tokenCounts: [1, 1, 1]))
    #expect(parts.map(\.text) == ["rnkswp05", "0.8861", "0.9620"] && parts[1].elements == [.text("0.8861", .bold)])
    #expect(NativeTextReader.slices(text, tokenCounts: [2, 1])?.map(\.text) == ["rnkswp05 0.8861", "0.9620"])
    // A different number of words, or a linked marker, gives no division.
    #expect(NativeTextReader.slices(text, tokenCounts: [1, 1]) == nil)
    #expect(NativeTextReader.slices(text, tokenCounts: [1, 1, 1, 1]) == nil)
    #expect(NativeTextReader.slices(InlineText(elements: [.text("a ", []), .sourcePage(3), .text("b", [])]), tokenCounts: [1, 1]) == nil)
}
