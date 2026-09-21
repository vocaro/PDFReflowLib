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

// MARK: - A picture across the measure at the head of a page (#160)

/// A figure a page sets across both its columns carries the whole measure with it, so while it
/// stands in the block no gutter can be found beneath it either. The FAA handbook opens page 391
/// with exactly that — a world aeronautical chart across both columns, nothing printed above it —
/// and the picture rule refused to cut there because one of its two sides was empty. The page was
/// then read row by row: the right column's prose interleaved with the left column's captions, so
/// `Figure 16-4. Meridians and parallels…` arrived in three pieces with sentences between them
/// (#160).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func aFigureAcrossTheMeasureAtTheHeadOfAPageStillSeparatesItsColumns() throws {
    let fixture = try SourceLayoutFixture.load("faa-391")
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    var page = fixture.content()
    // Exclude the source footer, which the full-document furniture pass removes.
    page.lines.removeAll { $0.text == "16-4" }
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let chart = try #require(regions.max { $0.width < $1.width })
    #expect(chart.width >= page.lines.map(\.rect).reduce(chart) { $0.union($1) }.width * 0.9)
    #expect(!page.lines.contains { $0.rect.minY >= chart.maxY })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                            vocabulary: [], warnings: &warnings)
    let paragraphs = paragraphTexts(blocks)
    #expect(paragraphs.contains("Figure 16-3. World aeronautical chart."))
    #expect(paragraphs.contains(
        "Figure 16-4. Meridians and parallels—the basis of measuring time, distance, and direction."))
    // The left column's two captions are read before any of the right column's paragraphs.
    let text = blocks.map(\.text).joined(separator: "\n")
    let captions = try #require(text.range(of: "Figure 16-4."))
    for prose in ["The standard practice is to establish a time zone",
                  "Figure 16-5 shows the time zones in the conterminous United",
                  "These time zone differences must be taken into account"] {
        #expect(try captions.upperBound < #require(text.range(of: prose)).lowerBound)
    }
    // The right column's paragraphs are whole: no caption fell into the middle of one.
    let closing = try #require(paragraphs.last)
    #expect(closing.hasPrefix("These time zone differences") && closing.hasSuffix("an hour is lost when"))
}

/// The caption a page sets across the same measure directly beneath such a figure bridges the
/// columns exactly as the figure does, so cutting at the figure alone leaves them joined. FAA page
/// 341 sets `Figure 14-6. (A) Displaced runway threshold drawing…` 7.7 points under a figure that
/// spans both columns, and the caption crosses the cut with the picture it labels (#160).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func aCaptionAcrossTheMeasureCrossesTheCutWithItsFigure() throws {
    let fixture = try SourceLayoutFixture.load("faa-341")
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    var page = fixture.content()
    page.lines.removeAll { $0.text == "14-7" }
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                            vocabulary: [], warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: "\n")
    // The spanning caption heads the page, then the left column's prose, then the right column's
    // two figures with their captions. Each caption is one block.
    let paragraphs = paragraphTexts(blocks)
    #expect(paragraphs.contains("Figure 14-7. Runway Safety Area."))
    #expect(paragraphs.contains(
        "Figure 14-8. Runway safety area boundary sign and marking located on Taxiway Kilo."))
    #expect(paragraphs.contains("Figure 14-9. Runway holding position sign at takeoff end of Runway "
        + "14 with collocated Taxiway Alpha location sign."))
    let spanning = try #require(text.range(of: "Figure 14-6."))
    let left = try #require(text.range(of: "If a taxiway intersects a runway somewhere other than at"))
    let right = try #require(text.range(of: "Figure 14-8."))
    #expect(spanning.upperBound < left.lowerBound)
    #expect(left.upperBound < right.lowerBound)
    // The left column's own paragraph is whole, rather than cut where a right-column caption
    // shared its row.
    let column = try #require(paragraphs.first { $0.hasPrefix("If a taxiway intersects") })
    #expect(column.hasSuffix("the threshold for Runway 18 is to the left and the threshold for"))
}

/// The control the picture rule was landed for: the 9/11 report sets two flights' timelines side
/// by side under one map across both of them, and cutting at the map is what puts each timeline
/// back in its own column (#137). Nothing here has an empty side, and the order is unchanged.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func aPictureWithTextAboveAndBelowDividesExactlyAsBefore() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 12), image: nil)
    }
    let heading = line("Heading", x: 40, y: 700, width: 490)
    let map = LayoutReconstructor.Element(rect: CGRect(x: 40, y: 560, width: 490, height: 100), image: "map")
    let left = [line("Left 1", x: 40, y: 520, width: 240), line("Left 2", x: 40, y: 500, width: 240)]
    let right = [line("Right 1", x: 292, y: 520, width: 238), line("Right 2", x: 292, y: 500, width: 238)]
    let ordered = LayoutReconstructor.ordered([right[0], left[1], map, right[1], heading, left[0]], bodySize: 12)
    #expect(ordered.map { $0.line?.text ?? $0.image! }
        == ["Heading", "map", "Left 1", "Left 2", "Right 1", "Right 2"])
}

// MARK: - The wrapped entries of a hung list (#160)

/// Project Blue Book sets its list of illustrations from one margin and hangs each entry's wrap
/// 48.5 points in, at 7.8-point type — six times the size, where a column's two lines may stand
/// one and a half bodies apart. So every wrapped entry of page 6 reflowed as two paragraphs, cut
/// where the page wrapped it, with the page numbers read afterwards in their own column and
/// nothing between the halves (#160).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func eachWrappedEntryOfAHungListIsOneParagraph() throws {
    let fixture = try SourceLayoutFixture.load("blue-6")
    #expect(fixture.sourceSHA256 == "90e05e77fc088c29758c2ddda514c0c12f317e5686ee213d348db2f9da152ee3")
    let page = fixture.content()
    let body = LayoutReconstructor.bodySize(page.lines)
    let hung = LayoutReconstructor.hangingEntries(in: page.lines, body: body)
    #expect(hung.count == 18)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    // Figures 14 to 37, one paragraph each.
    let entries = paragraphTexts(blocks).filter { $0.hasPrefix("Figure ") }
    #expect(entries.count == 24)
    #expect(entries.first == "Figure 14 Distribution of Object Sightings by Months Among the Eight "
        + "Duration Groups for All Years")
    #expect(entries.contains("Figure 27 Comparison of Monthly Distribution of Object Sightings Evaluated "
        + "as Insufficient Information Versus Total Object Sightings Less Insufficient Information"))
    #expect(entries.last == "Figure 37 Comparison of Evaluation of Object Sightings in the Strategic "
        + "Areas of the South West Region")
    // No entry ends where the page wrapped it: the shortest whole entry still runs ten words.
    for entry in entries { #expect(entry.split(whereSeparator: \.isWhitespace).count >= 10) }
}

/// The control from another book: *Agricultural Research* opens each paragraph on a first-line
/// indent, which sets the same two edges in the same alternation as a hung list — `firstLineIndentRun`
/// reads the Blue Book's list as one of its own. Joining there would run two paragraphs into one,
/// so nothing on that page is a hung entry: the line above an indented opening is a paragraph's
/// short last line, not an entry that ran out of room (#160).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func aFirstLineIndentIsNotAHungEntry() throws {
    let fixture = try SourceLayoutFixture.load("usda-9")
    let page = fixture.content()
    #expect(LayoutReconstructor.firstLineIndentRun(in: page.lines, step: 10, size: 10.5))
    #expect(LayoutReconstructor.hangingEntries(in: page.lines,
                                               body: LayoutReconstructor.bodySize(page.lines)).isEmpty)
}

/// The second control: Blue Book page 5 sets the same list with its titles in a column of their
/// own, so the wraps stand 5.5 points in and the ordinary column test already joins them. The
/// hung-entry rule speaks only where that test is silent, so it reads nothing there (#160).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func aWrapInsideTheColumnWindowIsNotAHungEntry() throws {
    let fixture = try SourceLayoutFixture.load("blue-5")
    let page = fixture.content()
    #expect(LayoutReconstructor.hangingEntries(in: page.lines,
                                               body: LayoutReconstructor.bodySize(page.lines)).isEmpty)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(blocks).contains("Distribution of Object Sightings by Evaluation for All "
        + "Years With Comparisons of Each Year for Each Evaluation Group •"))
}
