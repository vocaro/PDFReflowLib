import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(arguments: ["faa-91", "faa-511"])
func faaSourceColumnsCompleteBeforeTheNextColumn(name: String) throws {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    var page = fixture.content()
    // Exclude the source footer, which the full-document furniture pass removes.
    page.lines.removeAll { $0.text == "4-4" || $0.text == "G-35" }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: " ")
    let endings = name == "faa-91" ? ["must be defined.", "identify the same level."]
        : ["Wind direction indicators.", "Wind shear.", "restricted areas, obstructions and other pertinent data."]
    let right = try #require(text.range(of: name == "faa-91" ? "The computation of density altitude" : "Zone of confusion."))
    for ending in endings {
        #expect(try #require(text.range(of: ending)).lowerBound < right.lowerBound)
    }
    // Every extracted line must still contribute its words; ordering cannot discard a column.
    let sourceCharacters = page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted()
    #expect(text.filter { !$0.isWhitespace }.sorted() == sourceCharacters)
}

@Test func algebraSourceBaselineSurvivesAsASquaredExponent() throws {
    let fixture = try SourceLayoutFixture.load("algebra-343")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let line = try #require(fixture.attributedLines.first { $0.text.contains("quadratic is ax2") })
    #expect(line.runs.contains { $0.text.trimmingCharacters(in: .whitespaces) == "2" && $0.baselineOffset > 4 })
    let model = NativeTextReader.inlineText(from: line.attributedString())
    #expect(model.text == line.text)
    let html = EPUBTextEncoder.inline(model)
    #expect(html.contains("ax<sup>2"))
    #expect(html.contains("</sup>"))
    #expect(html.contains("+ bx + c = 0. We will now solve this for-"))
}

@Test func flagSourceTablePreservesBothHeadersAndAllTenRowsTogether() throws {
    let fixture = try SourceLayoutFixture.load("flag-27")
    #expect(fixture.sourceSHA256 == "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8")
    let page = fixture.content()
    let header = try #require(page.lines.first { $0.text.contains("FLAGPOLE HEIGHT") })
    #expect(header.text.contains("FLAG SIZE (FT.)"))
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let table = try #require(regions.first { $0.contains(header.rect) })
    let reference = [("20", "4x6"), ("25", "5x8"), ("40", "6x10"), ("50", "8x12"),
                     ("60", "10x15"), ("70", "12x18"), ("90", "15x25"), ("125", "20x30"),
                     ("200", "30x40"), ("250", "40x50")]
    for (height, size) in reference {
        let line = try #require(page.lines.first { $0.text.hasPrefix(height + " .") })
        let cells = line.text.replacingOccurrences(of: #"(?:\.\s*){3,}"#, with: "|", options: .regularExpression)
            .split(separator: "|").map { $0.filter { !$0.isWhitespace } }
        #expect(cells == [height, size])
        #expect(table.contains(line.rect))
    }
    #expect(table.width < page.bounds.width * 0.6 && table.height < page.bounds.height * 0.3)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: " ")
    #expect(text.contains("never store it until it is completely dry"))
    #expect(text.contains("sizes are shown in the following table:"))
    #expect(!text.contains("FLAGPOLE HEIGHT"))
}

@Test func narrowGuttersStillKeepSpanningHeadingsAndFiguresInPlace() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 12), image: nil)
    }
    let heading = line("Heading", x: 40, y: 700, width: 490)
    let left = [line("Left 1", x: 40, y: 660, width: 240), line("Left 2", x: 40, y: 640, width: 240)]
    let right = [line("Right 1", x: 292, y: 660, width: 238), line("Right 2", x: 292, y: 640, width: 238)]
    let figure = LayoutReconstructor.Element(rect: CGRect(x: 40, y: 500, width: 490, height: 100), image: "figure")
    let elements = right + [figure, heading] + left
    let ordered = LayoutReconstructor.ordered(elements, bodySize: 12)
    #expect(ordered.map { $0.line?.text ?? $0.image! } == ["Heading", "Left 1", "Left 2", "Right 1", "Right 2", "figure"])
    let single = [line("Third", x: 50, y: 640, width: 200), line("First", x: 40, y: 680, width: 205),
                  line("Second", x: 45, y: 660, width: 210)]
    #expect(LayoutReconstructor.ordered(single, bodySize: 12).map { $0.line!.text } == ["First", "Second", "Third"])
}

@Test func leaderTableControlsSeparateLookupRowsFromContentsAndEllipses() {
    func page(_ strings: [String], gap: Double = 14, mono: Bool = false, header: Bool = true) -> PageContent {
        var lines = strings.enumerated().map { index, text in
            TextLine(text: text, rect: CGRect(x: 40, y: 250 - Double(index) * gap, width: 180, height: 12),
                fontSize: 12, monospaced: mono)
        }
        if header { lines.append(TextLine(text: "Height  Width", rect: CGRect(x: 40, y: 274, width: 180, height: 12), fontSize: 12)) }
        return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 400), lines: lines, graphics: [])
    }
    for rows in [["10 .... 25", "20 .... 50", "30 .... 75"],
                 ["1.5 .... 2.5%", "2.5 .... 3.5%", "3.5 .... 4.5%"],
                 ["10 . . . 4 x 6", "20 . . . 5 x 8", "30 . . . 6 x 10"]] {
        let source = page(rows)
        let region = TableRegionDetector.regions(in: source)
        #expect(region.count == 1)
        #expect(source.lines.allSatisfy { line in region.contains { $0.contains(line.rect) } })
    }
    for source in [
        page(["Chapter 1 .... 10", "Chapter 2 .... 20", "Chapter 3 .... 30"]),
        page(["We waited ... then left.", "He paused ... and spoke.", "She replied ... yes."]),
        page(["10 .... 25", "20 .... 50"]),
        page(["10 .... 25", "20 .... 50", "30 .... 75"], gap: 70),
        page(["10 .... 25", "20 .... 50", "30 .... 75"], mono: true),
        page(["10 .... 25", "20 .... 50", "30 .... 75"], header: false),
    ] { #expect(TableRegionDetector.regions(in: source).isEmpty) }
    var interrupted = page(["10 .... 25", "20 .... 50", "30 .... 75"])
    interrupted.lines.append(TextLine(text: "Intervening explanation", rect: CGRect(x: 40, y: 238, width: 180, height: 12), fontSize: 12))
    #expect(TableRegionDetector.regions(in: interrupted).isEmpty)
}

@Test func narrowGutterDoesNotSeparateNamesFromDescriptions() throws {
    let source = try SourceLayoutFixture.load("911-451")
    var page = source.content()
    page.lines.removeAll { $0.text.hasPrefix("APPENDIX") }
    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
        .map(\.text).joined(separator: " ")
    let phrases = ["Abdullah bin Abdul Aziz", "Crown Prince and de facto regent", "Mohdar Abdullah",
                   "Yemeni; student in San Diego", "Sayf al Adl", "Egyptian; high-ranking member",
                   "Mahmud Ahmed", "Director General of Pakistan’s Inter-Services"]
    var previous = text.startIndex
    for phrase in phrases {
        let range = try #require(text.range(of: phrase))
        #expect(range.lowerBound >= previous)
        previous = range.upperBound
    }
}

// A page whose separating gaps never narrow is cut one block at a time, so its recursion depth
// is its block count. Ordinary pages cut nowhere near as deep (the deepest of the captured
// source layouts cuts eleven levels), so the limit is reached only by a page set with exactly
// uniform leading, such as a double-spaced typescript (#224). Page 1 is that page; page 2 sets
// the same lines solid, where no gap is wide enough to cut at all.
private func uniformlyLeadedPDF(lines: Int, leading: Double, size: Double) -> Data {
    func page(contents: Int) -> String {
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            + "/Resources << /Font << /F1 5 0 R >> >> /Contents \(contents) 0 R >>"
    }
    var solid = "", spaced = ""
    for index in 0..<lines {
        // Every line carries the same ascenders and descenders, so the extracted line boxes,
        // and with them the gaps between them, are exactly equal.
        let text = "Deposition line \(100 + index) of prose, with page, dog and query in it."
        spaced += "BT /F1 \(size) Tf 1 0 0 1 72 \(760 - Double(index) * leading) Tm (\(text)) Tj ET\n"
        solid += "BT /F1 \(size) Tf 1 0 0 1 72 \(760 - Double(index) * size) Tm (\(text)) Tj ET\n"
    }
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        page(contents: 6), page(contents: 7),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        testPDFStream(spaced), testPDFStream(solid),
    ])
}

@Test func abandonedWhitespaceCutsAreReportedAsAComplexLayout() async throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("deposition.pdf")
    try uniformlyLeadedPDF(lines: 40, leading: 18, size: 6).write(to: input)
    let report = try await PDFConverter().convert(from: input, to: directory.appendingPathComponent("book.epub"))
    #expect(report.warnings.filter { $0.code == .complexLayout }.map(\.page) == [1])
    let warning = try #require(report.warnings.first { $0.code == .complexLayout })
    #expect(warning.message.contains("keeps the order it was extracted in"))
    // The page still reflows: the warning reports an order that was not established, not content
    // that was lost.
    #expect(report.reflowedPageCount == 2)
}

/// The 9/11 report's page 254 ends `…arrived.Hawsawi told`, and PDFKit reports `told` as a line
/// of its own, level with the line it ends. The word belongs to the paragraph, and the paragraph
/// continues onto page 255 (#57).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func aPagesLastWordStaysInItsParagraphAndTheParagraphContinues() throws {
    let first = try SourceLayoutFixture.load("911-254"), second = try SourceLayoutFixture.load("911-255")
    #expect(first.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    var start = first.content(), next = second.content()
    // Exclude the running headers, which the full-document furniture pass removes.
    start.lines.removeAll { $0.text.contains("THE 9/11 COMMISSION REPORT") }
    next.lines.removeAll { $0.text.contains("THE ATTACK LOOMS") }
    let word = try #require(start.lines.last)
    #expect(word.text == "told" && word.sharesRow(with: start.lines[start.lines.count - 2]))

    var warnings: [ConversionWarning] = []
    var blocks: [ReflowBlock] = []
    for (page, previous) in [(start, nil), (next, start)] as [(PageContent, PageContent?)] {
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
        if previous == nil {
            #expect(try #require(paragraphTexts(pageBlocks).last).hasSuffix("each had arrived.Hawsawi told"))
        }
        LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: previous, to: &blocks,
                                       vocabulary: [], warnings: &warnings)
    }
    let continued = try #require(blocks.first { $0.text.contains("each had arrived.Hawsawi told") })
    #expect(continued.text.contains("arrived.Hawsawi told the muscle hijackers that they would be met by Atta"))
    if case let .paragraph(text) = continued.content { #expect(text.sourcePages == [255]) }
    else { Issue.record("the continued paragraph") }
}

/// The control for a short line that genuinely ends a page: the printed folio below the last line
/// of prose is its own block, and the paragraph above it does not take it (#45, #57).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func aPrintedFolioBelowThePagesProseIsStillItsOwnBlock() throws {
    let fixture = try SourceLayoutFixture.load("911-126")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    let page = fixture.content()
    #expect(page.lines.last?.text == "108")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let paragraphs = paragraphTexts(blocks)
    #expect(paragraphs.last == "108")
    let closing = try #require(paragraphs.dropLast().last)
    #expect(closing.contains("Until 1996,hardly anyone in the U.S.government") && !closing.contains("108"))
    // The chapter number, its title and the sub-heading above the prose remain headings.
    #expect(headingTexts(blocks).contains("RESPONSES TO AL QAEDA’S"))
}

/// The magazine sets three columns above an L-shaped picture frame, and its third column runs on
/// into a measure twice as wide beside that frame. No straight gutter crosses the page, because
/// the wide measure bridges the gutter between the second column and the third; and no whitespace
/// band crosses it either, because the columns are leaded so tightly that consecutive rows
/// overlap. The page-wide row-major sort those two failures fall back to wove the three columns
/// together line by line. The columns are read as runs now, so each completes before the next
/// begins and the wide measure is read as the third column continuing (#174).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/174"))
func aColumnRunningOnIntoAWiderMeasureContinuesThatColumn() throws {
    let fixture = try SourceLayoutFixture.load("usda-6")
    #expect(fixture.sourceSHA256 == "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761")
    let page = fixture.content()
    // The page's own geometry: the run-on measure starts 90 points left of the column it
    // continues, in the gutter that column shares with the second, and stands directly beneath
    // it; and the columns' rows overlap rather than leaving a band to cut at.
    let column = try #require(page.lines.first { $0.text.hasPrefix("deterrent effects of callicarpenal") })
    let runOn = try #require(page.lines.first { $0.text.hasPrefix("looked at an efficient synthetic") })
    #expect(abs(column.rect.minX - runOn.rect.minX - 90) < 1 && abs(column.rect.maxX - runOn.rect.maxX) < 1)
    #expect(column.rect.minY < runOn.rect.maxY && runOn.rect.maxY - column.rect.minY < 0.5)
    let rows = [try #require(page.lines.first { $0.text.hasPrefix("and ticks. (See") }),
                try #require(page.lines.first { $0.text.hasPrefix("Folk Remedy Yields") })]
    #expect(rows[0].rect.minY - rows[1].rect.maxY < -1.2)

    try expectInOrder(reconstructedText(of: page), [
        "we’ve got,” Burkett says.", "have developed entirely new classes of",      // the first column
        "insecticides out of the DWFP program,", "significant repellency against",  // the second
        "and ticks. (See", "deterrent effects of callicarpenal and",                // the third
        "looked at an efficient synthetic approach", "mosquitoes from biting.",      // its run-on measure
        "Left: Technician Solomon Green III",                                        // and then the captions
    ])
}

/// The same defect the other way up: the second column runs on into a measure spanning the
/// picture beside it and returns to its own measure below that picture. The wide band hid the
/// gutter between the column and the pictures, so the pictures and their captions were woven
/// into the column's prose line by line (#174).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/174"))
func aColumnThatWidensAndNarrowsAgainKeepsThePicturesBesideItOutOfItsProse() throws {
    let fixture = try SourceLayoutFixture.load("usda-17")
    #expect(fixture.sourceSHA256 == "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761")
    let text = reconstructedText(of: fixture.content())
    try expectInOrder(text, [
        "as possible and keeping crops viable",                   // the first column, complete
        "postharvest were in the 10",
        "Infrared thermometer mounted on a pole",                 // the upper picture's caption
        "consistently higher than the 3",                         // the second column, complete
        "potential were consistent with",
        "data collected by the infrared sensors",                 // its run-on measure
        "use year after year.",
        "viable approach to managing",                            // and its own measure again
        "Soil scientist Dong Wang examines",                      // the lower picture's caption
    ])
    // That caption is one block of its own, not four lines woven into the column beside it.
    #expect(text.contains("Infrared thermometer mounted on a pole for measuring peach tree canopy temperature"))
}

/// The controls. A page whose straight cut already separates its columns states no run-on
/// measure, so its reading order is the cut's, unchanged: the FAA handbook's two columns, the
/// Fed's column beside its boxed sidebar, and the climate assessment's column around its
/// figure (#174).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/174"),
      arguments: [("faa-511", ["Wind direction indicators.", "Wind shear.", "World Aeronautical Charts",
                                      "restricted areas, obstructions and other pertinent data.", "Zone of confusion."]),
                  ("fed-54", ["These vulnerability assessments inform", "Asset Valuations and Risk Appetite",
                              "Elevated asset valuations constitute", "However, it is very difficult to judge"]),
                  ("noaa-1056", ["The sociodemographic profiles of Puerto Rico",
                                 "These islands are particularly vulnerable", "23-7 | US Caribbean"])])
func straightCutColumnsAreUnchangedByTheRunOnRule(name: String, phrases: [String]) throws {
    try expectInOrder(reconstructedText(of: try SourceLayoutFixture.load(name).content()), phrases)
}

/// A row the page sets across its columns is not a column running on. One spanning row — a
/// table's total, a note beneath its cells — widens the run above it exactly as a run-on measure
/// does, and reading that page as columns would take every cell out of its row. The measure must
/// be one the run keeps, over at least two of its elements (#137, #174).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/174"))
func oneRowSpanningTheColumnsIsNotAColumnRunningOn() throws {
    func cell(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 13)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 11), image: nil)
    }
    // Two columns of prose leaded so tightly that consecutive rows overlap by a point, so no
    // whitespace band cuts them.
    var elements: [LayoutReconstructor.Element] = []
    for row in 0..<5 {
        let y = 700 - Double(row) * 12
        elements.append(cell("The left column of this page, set to its own measure", x: 40, y: y, width: 140))
        elements.append(cell("and the right column beside it, set to the same", x: 186, y: y, width: 140))
    }
    #expect(LayoutReconstructor.ordered(elements, bodySize: 11).map { $0.rect.minX } == elements.map { $0.rect.minX })
    #expect(LayoutReconstructor.columnRuns(elements, bodySize: 11) == nil)
    // One row set across both columns widens the left run, but the run does not keep that
    // measure, so the page is still read row by row.
    let spanning = cell("A total of every row above it, set across both columns", x: 40, y: 628, width: 286)
    #expect(LayoutReconstructor.columnRuns(elements + [spanning], bodySize: 11) == nil)
    // Two such rows are a measure the run keeps, and the page is read as columns.
    let second = cell("and a second line of that same spanning note beneath it", x: 40, y: 616, width: 286)
    let runs = try #require(LayoutReconstructor.columnRuns(elements + [spanning, second], bodySize: 11))
    #expect(runs.map(\.count).sorted() == [5, 7])
    #expect(runs.contains { $0.last?.line?.text == "and a second line of that same spanning note beneath it" })
    // The same shape in short cells is a table, whose rows the page means to be read across: the
    // report's list of illustrations sets its page numbers against their titles this way.
    var cells: [LayoutReconstructor.Element] = []
    for row in 0..<5 {
        let y = 700 - Double(row) * 12
        cells.append(cell("p. \(row * 17 + 15)", x: 40, y: y, width: 30))
        cells.append(cell("The title of the illustration on that page", x: 90, y: y, width: 236))
    }
    #expect(LayoutReconstructor.columnRuns(cells + [spanning, second], bodySize: 11) == nil)
}

/// A run standing inside another run's rows is that row, not a column. A worked example sets an
/// annotation beside the step it explains, on the step's own rows; the chaining gives it a run of
/// its own because it is too far below the step above it to join, and reading the two runs out
/// one after the other would take every step away from its annotation. The runs must stand apart
/// — no element of one touching an element of another — which is what a column running on never
/// violates, because it widens across a gutter only where the column beside it has ended (#174).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/174"))
func aRunStandingInsideAnotherRunsRowsIsNotAColumn() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 13)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 11), image: nil)
    }
    // The working: two narrow steps, then two set to the full measure, which is a run-on.
    let working = [line("Distribute 3 through the parenthesis", x: 84, y: 520, width: 216),
                   line("and then subtract seven", x: 84, y: 508, width: 216),
                   line("Take the whole of the remaining expression and divide it through", x: 84, y: 496, width: 426),
                   line("by the coefficient standing in front of the variable to solve", x: 84, y: 484, width: 426)]
    // The annotation stands on the last two rows of that working, inside them.
    let annotation = [line("Subtract seven", x: 276, y: 496, width: 162),
                      line("from both sides", x: 276, y: 484, width: 162)]
    #expect(LayoutReconstructor.columnRuns(working + annotation, bodySize: 11) == nil)
    // Without it, the same working is one run, and one run is not a decomposition either.
    #expect(LayoutReconstructor.columnRuns(working, bodySize: 11) == nil)
}

/// One page's blocks as text, crops taken as the pipeline takes them.
private func reconstructedText(of page: PageContent) -> String {
    var warnings: [ConversionWarning] = []
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
        .map(\.text).joined(separator: " ")
}

/// Reading order phrase by phrase, reported with the phrase that is out of place.
private func expectInOrder(_ text: String, _ phrases: [String]) throws {
    var previous = text.startIndex
    for phrase in phrases {
        guard let range = text.range(of: phrase, range: previous..<text.endIndex) else {
            Issue.record("\(phrase) is missing, or stands before \(text[..<previous].suffix(80))")
            return
        }
        previous = range.upperBound
    }
}
