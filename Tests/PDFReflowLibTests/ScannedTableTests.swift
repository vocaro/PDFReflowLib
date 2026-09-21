import Foundation
import Testing
@testable import PDFReflowLib

// #31: tables on scanned and image-backed pages. What a recognition of such a page locates, what
// it transcribes, and what the reader is told about the picture that preserves it.
//
// Vision's reading of a given page is not stable across compiled model sets (#173), so the
// source-derived half of this suite replays a capture of the CIA Blue Book's pages 74 and 150
// (`tools/probes/probe-table-cell-evidence.swift --fixture`) rather than calling Vision, and the
// pipeline half uses canned readings, exactly as the recognition suites already do.

/// A capture of the tables one recognition located on a checksum-pinned corpus page: each
/// table's rectangle in the page's own points, and every cell's transcription.
private struct SourceTableFixture: Decodable {
    struct Table: Decodable {
        var rect: [Double]
        var columns: Int
        var cells: [[String]]

        var reading: TableCellEvidence.Reading {
            TableCellEvidence.reading(rect: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]),
                                      rows: cells, columns: columns)
        }
    }
    struct Page: Decodable {
        var page: Int
        var bounds: [Double]
        var tables: [Table]
    }
    var caseID: String
    var sourceSHA256: String
    var pages: [Page]

    static func load(_ name: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: fixtureURL("\(name)-tables.json")))
    }

    func page(_ number: Int) throws -> Page {
        try #require(pages.first { $0.page == number })
    }
}

private let blueBookSHA256 = "90e05e77fc088c29758c2ddda514c0c12f317e5686ee213d348db2f9da152ee3"

// MARK: - What the reading of each page came to

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func theTypewrittenTablePageIsOneTableWhoseCellsTheReadingFilled() throws {
    let fixture = try SourceTableFixture.load("blue-74-150")
    #expect(fixture.sourceSHA256 == blueBookSHA256)
    let page = try fixture.page(74)
    // The source prints one table, `TABLE IV CHI SQUARE TEST OF KNOWNS VERSUS UNKNOWNS ON THE
    // BASIS OF SHAPE`: a label column and four numeric columns over eight body rows, then three
    // rows of test statistics. The reading returns one grid of that shape.
    #expect(page.tables.count == 1)
    let reading = try #require(page.tables.first).reading
    #expect(reading.rows == 12)
    #expect(reading.columns == 5)
    #expect(reading.cells == 60)
    #expect(reading.transcribedCells == 50)
    #expect(Int((reading.transcribedFraction * 100).rounded()) == 83)
    #expect(reading.cellsWereRead)
    // It stands on the page's own table, not on its margin or its folio.
    #expect(reading.rect.minX > 70 && reading.rect.maxX < 540)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func theHandwrittenTablePageIsGridsTheReadingLeftEmpty() throws {
    let fixture = try SourceTableFixture.load("blue-74-150")
    let page = try fixture.page(150)
    // The source prints `TABLE A63 EVALUATION OF ALL SIGHTINGS FOR ALL YEARS BY COLORS
    // REPORTED` as four stacked grids, each 25 columns wide — an `Evaluation` column and four
    // color groups of `Number` and `Per Cent` over `Certain`, `Doubtful` and `Total` — with
    // twelve rows apiece, and every value in them written by hand.
    //
    // The reading returns two grids, not four, so half the page's tables are missing before a
    // cell is read; one of the two is ruled 26 columns wide, which the page never is.
    #expect(page.tables.count == 2)
    let readings = page.tables.map(\.reading)
    #expect(readings.map(\.rows) == [15, 15])
    #expect(readings.map(\.columns) == [26, 25])
    #expect(readings.map(\.cells) == [390, 375])
    #expect(readings.map(\.transcribedCells) == [104, 49])
    #expect(readings.map { Int(($0.transcribedFraction * 100).rounded()) } == [27, 13])
    #expect(readings.allSatisfy { !$0.cellsWereRead })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aHandwrittenTablesCellsAreNotItsNumbers() throws {
    // Why the reading of page 150 is refused rather than reported as cells. The source's first
    // body row of the second grid reads `0-Balloon 18 11 29 0.6 0.3 0.9 …`; nothing of that
    // survives, and what the grid does hold is not the page's writing at all.
    let page = try SourceTableFixture.load("blue-74-150").page(150)
    let cells = try #require(page.tables.first).cells.flatMap { $0 }.filter { !$0.isEmpty }
    #expect(cells.contains("CRASSE DR GLONINS CRAVGE"))   // `ORANGE OR GLOWING ORANGE`
    #expect(cells.contains("GRKEN OR GUWING GREEN"))      // `GREEN OR GLOWING GREEN`
    #expect(!cells.contains("0-Balloon"))
    #expect(!cells.contains("29"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func evenTheTypewrittenTablesCellsAreNotFitToPublish() throws {
    // And why a table this measure believes is still only preserved and reported. The source
    // prints `Meteor or comet 55 14 4 7.14`, `Flame 96 24 10 8.17` and `Total 1765 434 434
    // 29.05`. The reading drops one value outright and corrupts two more, so transcribing this
    // grid into the reader's text would publish a wrong statistical table under the book's name.
    let page = try SourceTableFixture.load("blue-74-150").page(74)
    let rows = try #require(page.tables.first).cells
    #expect(rows.contains { $0 == ["Meteor or comet", "55", "14", "", "7.14"] })
    #expect(rows.contains { $0 == ["Flame", "96", "24", "10", "8,17"] })
    #expect(rows.contains { $0.first == "Total" && $0.last != "29.05" })
}

// MARK: - The rule

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func halfTheGridIsTheLineBetweenAReadTableAndADrawnOne() {
    func filled(_ cells: Int, of total: Int) -> TableCellEvidence.Reading {
        TableCellEvidence.Reading(rect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                  rows: 10, columns: total / 10, cells: total, transcribedCells: cells)
    }
    #expect(filled(50, of: 100).cellsWereRead)
    #expect(!filled(49, of: 100).cellsWereRead)
    // The measured margin: the emptiest table a recognition read (USGS copper page 2's world
    // production, 79 of 126) and the fullest it did not (the Blue Book's page 150, 104 of 390).
    #expect(filled(79, of: 126).cellsWereRead)
    #expect(!filled(104, of: 390).cellsWereRead)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aGridTooSmallToJudgeIsBelieved() {
    // Two cells say nothing either way, and a region a recognizer happens to call a table must
    // not change what a page reports on that evidence.
    let small = TableCellEvidence.reading(rect: .init(x: 0, y: 0, width: 10, height: 10),
                                          rows: [["a", ""], ["", ""]], columns: 2)
    #expect(small.cells == 4)
    #expect(small.isTooSmallToJudge)
    #expect(small.cellsWereRead)
    let judged = TableCellEvidence.reading(rect: .init(x: 0, y: 0, width: 10, height: 10),
                                           rows: [["a", "", ""], ["", "", ""], ["", "", ""]], columns: 3)
    #expect(judged.cells == 9)
    #expect(!judged.isTooSmallToJudge)
    #expect(!judged.cellsWereRead)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func whitespaceIsNotATranscription() {
    let blank = TableCellEvidence.reading(rect: .init(x: 0, y: 0, width: 10, height: 10),
                                          rows: [[" ", "\n", " "], ["\t", " ", " "], [" ", " ", " "]], columns: 3)
    #expect(blank.transcribedCells == 0)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aTableSplitAcrossABandRetryIsJudgedOnBothItsHalves() {
    // #116 recognizes a lossy page again in two bands and joins a table that crosses the split.
    // The joined table is judged on the cells both halves read, so a table cut in two is not
    // reported as unread merely for having been cut.
    let upper = TableCellEvidence.reading(rect: .init(x: 0, y: 0.5, width: 1, height: 0.3),
                                          rows: [["a", "b", "c"], ["d", "e", "f"]], columns: 3)
    let lower = TableCellEvidence.reading(rect: .init(x: 0, y: 0.2, width: 1, height: 0.3),
                                          rows: [["g", "h", "i"], ["j", "k", "l"]], columns: 3)
    let joined = TableCellEvidence.joined(upper, lower)
    #expect(joined.rows == 4)
    #expect(joined.cells == 12)
    #expect(joined.transcribedCells == 12)
    #expect(joined.cellsWereRead)
    #expect(joined.rect == upper.rect.union(lower.rect))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func bandsCarryEachTablesCellsBackIntoThePage() {
    func band(_ tables: [(CGRect, TableCellEvidence.Reading)]) -> OCRReader.Recognition {
        OCRReader.Recognition(lines: [], tables: tables.map(\.0), tableCells: tables.map(\.1))
    }
    func grid(_ rect: CGRect, filled: Int, of cells: Int) -> TableCellEvidence.Reading {
        TableCellEvidence.Reading(rect: rect, rows: 5, columns: cells / 5, cells: cells, transcribedCells: filled)
    }
    let top = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.5)
    let bottom = CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2)
    let merged = OCRReader.mergeBands([
        (band([(top, grid(top, filled: 2, of: 20))]), 0.4, 0.6),
        (band([(bottom, grid(bottom, filled: 3, of: 20))]), 0.0, 0.6),
    ])
    #expect(merged.tables.count == merged.tableCells.count)
    #expect(merged.tableCells.allSatisfy { !$0.cellsWereRead })
    // A reading with no cell counts leaves the merge with none, so nothing is judged on a
    // measurement that was never taken.
    let unmeasured = OCRReader.mergeBands([
        (OCRReader.Recognition(lines: [], tables: [top]), 0.4, 0.6),
        (OCRReader.Recognition(lines: [], tables: [bottom]), 0.0, 0.6),
    ])
    #expect(!unmeasured.tables.isEmpty)
    #expect(unmeasured.tableCells.isEmpty)
}

// MARK: - What the reader is given

private func workspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("scanned-tables-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A canned reading of the bundled scanned fixture: one paragraph of the page's own words, and
/// the tables named, each with the grid given.
private func reading(_ text: String, tables: [(CGRect, TableCellEvidence.Reading)] = []) -> OCRReader.Result {
    OCRReader.Result(lines: [TextLine(text: text, rect: CGRect(x: 54, y: 60, width: 300, height: 12), fontSize: 12)],
                     tables: tables.map(\.0), tableCells: tables.map(\.1))
}

private func grid(_ rect: CGRect, filled: Int, of cells: Int) -> TableCellEvidence.Reading {
    TableCellEvidence.Reading(rect: rect, rows: 10, columns: cells / 10, cells: cells, transcribedCells: filled)
}

private func captions(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .image(let image) = $0.content { image.caption } else { nil } }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aTableTheReadingDidNotTranscribeIsReportedAtItsOwnPicture() async throws {
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let table = CGRect(x: 60, y: 300, width: 480, height: 300)
    let result = try await PDFReflowLibPipeline.reconstruct(
        from: fixtureURL("scanned.pdf"), options: .init(), workspace: directory,
        recognize: { _, _ in reading("The page's own paragraph", tables: [(table, grid(table, filled: 26, of: 260))]) }
    ) { _ in }
    let warnings = result.warnings.filter { $0.code == .unreadTableCells }
    #expect(warnings.count == 1)
    let warning = try #require(warnings.first)
    #expect(warning.page == 1)
    // The message reports a measurement of the reading, never the page's own rows or columns.
    #expect(warning.message.contains("transcribed only 10% of the 260 cells"))
    #expect(warning.message.contains("Read the table in the accompanying image."))
    // The picture says what it holds, instead of `Preserved region from page 1`.
    #expect(captions(result.book.blocks).contains("Table from page 1, preserved as an image. "
        + "Its cells are not transcribed; read them in this picture."))
    #expect(!captions(result.book.blocks).contains("Preserved region from page 1"))
    // Positive control: the page keeps the text it reads.
    #expect(result.book.blocks.contains { $0.text.contains("The page's own paragraph") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aTableTheReadingDidTranscribeIsStillOnlyAPictureAndSaysSo() async throws {
    // Signaling is kept separate from repair. The library writes no table markup, so even a
    // table whose cells the reading filled reaches the reader only as a picture; the picture
    // says it is a table, and no warning claims the reading was wrong.
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let table = CGRect(x: 60, y: 300, width: 480, height: 300)
    let result = try await PDFReflowLibPipeline.reconstruct(
        from: fixtureURL("scanned.pdf"), options: .init(), workspace: directory,
        recognize: { _, _ in reading("The page's own paragraph", tables: [(table, grid(table, filled: 240, of: 260))]) }
    ) { _ in }
    #expect(!result.warnings.contains { $0.code == .unreadTableCells })
    #expect(captions(result.book.blocks).contains { $0.hasPrefix("Table from page 1") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func twoUnreadTablesOnOnePageAreReportedOnceEach() async throws {
    // The signal is per region, not per page: the CIA report's page 150 carries two located
    // grids, and a reader told once cannot tell which picture the warning is about.
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let upper = CGRect(x: 60, y: 520, width: 480, height: 180)
    let lower = CGRect(x: 60, y: 200, width: 480, height: 180)
    let result = try await PDFReflowLibPipeline.reconstruct(
        from: fixtureURL("scanned.pdf"), options: .init(), workspace: directory,
        recognize: { _, _ in
            reading("The page's own paragraph",
                    tables: [(upper, grid(upper, filled: 26, of: 260)), (lower, grid(lower, filled: 13, of: 260))])
        }
    ) { _ in }
    let warnings = result.warnings.filter { $0.code == .unreadTableCells }
    #expect(warnings.count == 2)
    #expect(warnings.allSatisfy { $0.page == 1 })
    #expect(warnings.contains { $0.message.contains("only 10%") })
    #expect(warnings.contains { $0.message.contains("only 5%") })
    #expect(captions(result.book.blocks).filter { $0.hasPrefix("Table from page 1") }.count == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aRecognizedPageWithNoTableIsUntouched() async throws {
    // Positive control. A scanned page of prose reports nothing about tables and loses no text.
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = try await PDFReflowLibPipeline.reconstruct(
        from: fixtureURL("scanned.pdf"), options: .init(), workspace: directory,
        recognize: { _, _ in reading("This page contains a clear scanned paragraph.") }
    ) { _ in }
    #expect(!result.warnings.contains { $0.code == .unreadTableCells })
    #expect(!captions(result.book.blocks).contains { $0.hasPrefix("Table from page") })
    #expect(result.book.blocks.contains { $0.text.contains("This page contains a clear scanned paragraph.") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func aBornDigitalPagesPicturesKeepTheirOwnDescription() async throws {
    // Positive control from another layout. Nothing recognizes the prose fixture, so its
    // pictures, if any, are described exactly as they were before this rule existed.
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = try await PDFReflowLibPipeline.reconstruct(
        from: fixtureURL("graphics.pdf"), options: .init(), workspace: directory,
        recognize: { _, _ in reading("Never used") }
    ) { _ in }
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .unreadTableCells })
    #expect(!captions(result.book.blocks).contains { $0.hasPrefix("Table from page") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/31"))
func onlyTheCropHoldingATableIsDescribedAsOne() {
    // A page can preserve a figure beside a table. The description follows the table's own
    // rectangle into the crop that contains it, and no further.
    let table = CGRect(x: 60, y: 300, width: 300, height: 200)
    let figure = CGRect(x: 380, y: 300, width: 160, height: 200)
    let assets = LayoutReconstructor.tableAssets(
        [(table.insetBy(dx: -4, dy: -4), "table.png"), (figure, "figure.png")],
        tables: [grid(table, filled: 20, of: 200)], page: 7)
    #expect(assets == ["table.png": LayoutReconstructor.tableDescription(page: 7)])
}
