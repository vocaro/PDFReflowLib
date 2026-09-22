import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// MARK: - A hanging indent is a paragraph, not a table (#268)

/// The row blocks `TableRegionDetector` reads over a fixture page, at the page's own body.
private func rowBlocks(_ fixture: String) throws -> (blocks: [CGRect], page: PageContent) {
    let page = try SourceLayoutFixture.load(fixture).content()
    return (TableRegionDetector.rowBlocks(in: page.lines, body: PageTypography(page: page).body), page)
}

/// The lines of `page` that fall inside one of `blocks`, in the order the page prints them.
private func rowTexts(_ blocks: [CGRect], on page: PageContent) -> [String] {
    page.lines.filter { line in blocks.contains { $0.insetBy(dx: -1, dy: -1).contains(line.rect) } }
        .sorted { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY > $1.rect.minY }
        .map(\.text)
}

/// A run of rows on one left edge, each row's pieces given as `(x, width, text)`, stepping down
/// at one leading in one size. This is the shape both a hanging-indent entry list and a
/// two-column table the page set without rules hand back, and the fixtures below differ only in
/// where the rows *end*.
private func run(_ rows: [[(CGFloat, CGFloat, String)]], top: CGFloat = 700, size: CGFloat = 9,
                 leading: CGFloat = 11) -> [TextLine] {
    var lines: [TextLine] = []
    for (index, row) in rows.enumerated() {
        let y = top - CGFloat(index) * leading
        for piece in row {
            lines.append(TextLine(text: piece.2,
                                  rect: CGRect(x: piece.0, y: y, width: piece.1, height: size),
                                  fontSize: size, monospaced: false))
        }
    }
    return lines
}

/// Replay Clocks sets its references with the citation number outdented and the entry hanging at
/// an indent, and page 10 hands that back with exactly the evidence `rowBlocks` reads as a table
/// the page set without rules: `[8]`, `[10]` and `[12]` arrive as a cell of their own on one
/// edge, and the rows PDFKit merged whole — `[9] David L Mills. …` — reach across it. The last
/// five references came out as `<pre>` rows.
///
/// They are not rows, because the page filled them to a measure: seven of the eleven end within
/// a fifth of a body of 558.2 and the four that fall short are each entry's closing line.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/268"))
func aHangingIndentReferenceListIsNotATable() throws {
    let fixture = try SourceLayoutFixture.load("replay-10")
    #expect(fixture.sourceSHA256 == "1e8172e4a347bdf6722dacc38755f6fb3299866336b8153f51b2c13f3ac6109a")
    #expect(fixture.page == 10)
    let page = fixture.content()

    // The page's own evidence, as the issue records it: the citation number kept apart on three
    // rows and merged into the entry on two, every wrapped line standing at 333.39.
    let apart = page.lines.filter { ["[8]", "[10]", "[12]"].contains($0.text) }
    #expect(apart.count == 3)
    #expect(apart.allSatisfy { $0.rect.maxX < 330 })
    let merged = page.lines.filter { $0.text.hasPrefix("[9] David") || $0.text.hasPrefix("[11] Mukesh") }
    #expect(merged.count == 2)
    #expect(merged.allSatisfy { $0.rect.minX < 322 && $0.rect.maxX > 550 })
    let wrapped = try #require(page.lines.first { $0.text.hasPrefix("Transactions on communications") })
    #expect(abs(wrapped.rect.minX - 333.39) < 0.5)

    // No block of rows anywhere on the page.
    let blocks = TableRegionDetector.rowBlocks(in: page.lines, body: PageTypography(page: page).body)
    #expect(blocks.isEmpty, Comment(rawValue: "rows read: \(rowTexts(blocks, on: page))"))

    // And the references reflow: no line of the page reads as a preformatted row.
    var warnings: [ConversionWarning] = []
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated()
        .map { ($0.element, "page-\(page.number)-region-\($0.offset)") }
    let produced = LayoutReconstructor.blocks(page: page, images: images,
                                              vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                              warnings: &warnings)
    func isRow(_ block: ReflowBlock) -> Bool {
        if case .preformatted = block.content { true } else { false }
    }
    #expect(!produced.contains(where: isRow),
            Comment(rawValue: "kept as rows: \(produced.filter(isRow).map(\.text))"))
    for entry in ["D. L. Mills. Network time protocol (ntp). RFC 958",
                  "Internet time synchronization: the network time protocol",
                  "Dapper, a large-scale distributed systems tracing infrastructure",
                  "An efficient implementation of",
                  "Analysis of bounds on hybrid vector clocks"] {
        #expect(produced.contains { $0.hasReflowedText && $0.text.contains(entry) },
                Comment(rawValue: "lost: \(entry)"))
    }
}

/// The controls. Every one of these pages sets a two-column table the same way the reference
/// list is set — a short value outdented, the entry hung at an indent — and every one must keep
/// its printed rows. They are what the two guards measured under #171 broke, and the reading
/// this change makes must leave them exactly as they were.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/268"))
func theTablesSetWithTheSameHangingShapeKeepTheirRows() throws {
    // The 9/11 report's flight timelines, pages 50 and 51: four blocks, one per flight.
    let fifty = try rowBlocks("911-50")
    #expect(fifty.blocks.count == 2)
    let fiftyRows = rowTexts(fifty.blocks, on: fifty.page)
    for cell in ["8:19", "Flight attendant notifies AA of", "8:46:40", "AA 11 crashes into 1 WTC",
                 "9:20 UA headquarters aware that"] {
        #expect(fiftyRows.contains { $0.contains(cell) }, Comment(rawValue: "lost row: \(cell)"))
    }
    let fiftyOne = try rowBlocks("911-51")
    #expect(fiftyOne.blocks.count == 2)
    let fiftyOneRows = rowTexts(fiftyOne.blocks, on: fiftyOne.page)
    for cell in ["10:03:11", "Flight 93 crashes in field in", "8:51-8:54 Likely takeover",
                 "9:37:46", "AA 77 crashes into the"] {
        #expect(fiftyOneRows.contains { $0.contains(cell) }, Comment(rawValue: "lost row: \(cell)"))
    }

    // The report's list of illustrations, page 9: the page reference outdented, the caption hung.
    // Four of its fifteen rows reach the block's own right edge, which is a ragged column of
    // captions and not a measure.
    let nine = try rowBlocks("911-9")
    #expect(nine.blocks.count == 1)
    #expect(rowTexts(nine.blocks, on: nine.page).contains { $0.contains("FAA Air Traffic Control Centers") })

    // The Blue Book's contents, the FAA handbook's cruise table, and the USGS statistics, each of
    // which #171 also names.
    #expect(try rowBlocks("blue-5").blocks.count == 1)
    #expect(try rowBlocks("faa-459").blocks.count == 3)
    #expect(try rowBlocks("usgs-1").blocks.count == 1)
    #expect(try rowBlocks("usgs-2").blocks.count == 1)

    // The NOAA chapter contents, whose rows *do* all end on one edge — because that edge is a
    // column of right-aligned page numbers. An edge carried by numbers is a column.
    let noaa = try rowBlocks("noaa-9")
    #expect(noaa.blocks.count == 4)
    let noaaRows = rowTexts(noaa.blocks, on: noaa.page)
    for number in ["4-16", "4-23", "5-9", "7-20"] {
        #expect(noaaRows.contains { $0.contains(number) }, Comment(rawValue: "lost page number: \(number)"))
    }
}

/// The mechanism on its own, with everything but the right edge held fixed. Both runs outdent a
/// short first piece on three rows, merge it into the row on two, and hang every other line at
/// one indent; they differ only in where the lines end.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/268"))
func onlyTheRightEdgeTellsAHangingIndentFromATable() {
    // A paragraph filled to a measure at x = 300: every line but each entry's last reaches it.
    let filled = run([
        [(100, 200, "[1] Ada Lovelace. A note upon the analytical")],
        [(120, 180, "engine, and upon the numbers it may be")],
        [(120, 90, "made to print.")],
        [(100, 10, "[2]"), (120, 180, "Alan Turing. On computable numbers, with")],
        [(120, 180, "an application to the decision problem, in")],
        [(120, 80, "the Proceedings.")],
        [(100, 10, "[3]"), (120, 180, "Grace Hopper. The education of a")],
        [(120, 60, "in the ACM.")],
    ])
    #expect(TableRegionDetector.rowBlocks(in: filled, body: 9).isEmpty)

    // The same run set raggedly, as a table's cells are: an outdented short first piece the
    // extractor keeps apart on two rows and merges into two others, every other line hung at one
    // indent, one size, one leading. Only the right edge differs, and this one is rows.
    let ragged = run([
        [(100, 130, "8:14 Last routine radio")],
        [(120, 95, "communication; likely takeover")],
        [(100, 10, "8:19"), (120, 105, "Flight attendant notifies AA")],
        [(120, 45, "of hijacking")],
        [(100, 120, "8:21 Transponder is turned off")],
        [(120, 60, "over Albany")],
        [(100, 10, "8:23"), (120, 110, "AA attempts to contact the")],
        [(120, 40, "cockpit")],
    ])
    #expect(TableRegionDetector.rowBlocks(in: ragged, body: 9).count == 1)
}
