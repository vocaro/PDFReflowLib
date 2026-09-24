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

@Test func answerKeyTitlePrecedesAColumnWhoseFirstCropRisesIntoItsRow() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 12), image: nil)
    }
    let previousKey = line("8.6", x: 85, y: 445, width: 13)
    let title = line("Answers - Rational Exponents", x: 219, y: 422, width: 156)
    let fraction = LayoutReconstructor.Element(rect: CGRect(x: 85, y: 398, width: 50, height: 30), image: "1")
    let next = line("9) 4", x: 85, y: 215, width: 25)
    let otherColumn = line("16) 1", x: 233, y: 365, width: 30)
    let elements = [fraction, otherColumn, next, previousKey, title]
    let order = LayoutReconstructor.ordered(elements, bodySize: 12).map { $0.line?.text ?? $0.image! }
    #expect(order.first == "8.6")
    #expect(order.firstIndex(of: "Answers - Rational Exponents")! < order.firstIndex(of: "1")!)
    #expect(order.firstIndex(of: "Answers - Rational Exponents")! < order.firstIndex(of: "9) 4")!)
}

@Test func wallaceRationalExponentTitlePrecedesItsFirstPreservedAnswer() throws {
    let fixture = try SourceLayoutFixture.load("algebra-475")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let title = try #require(page.lines.first { $0.text == "Answers - Rational Exponents" })
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let first = try #require(regions.enumerated().first { _, region in
        region.midX < 150 && region.midY < title.rect.midY && region.maxY > title.rect.minY - 10
    })
    let images = regions.enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    let headingIndex = try #require(blocks.firstIndex { $0.text == title.text })
    let imageIndex = try #require(blocks.firstIndex {
        if case let .image(image) = $0.content { image.assetID == "image-\(first.offset)" } else { false }
    })
    #expect(headingIndex < imageIndex)
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

// MARK: - A printed row the extractor split, left to right (#272)

/// The 9/11 report's page 259 prints one paragraph and the reading broke it in the middle of its
/// own sentence. PDFKit hands the row `ning for what later became the 9/11 attack. At the time of
/// their travel through` back in two pieces, at x 44.70…151.77 and x 156.89…356.71, and the
/// column test that joins a paragraph's wraps measured the second piece's 156.89 against the
/// 44.70 of `Iran, the al Qaeda operatives themselves were probably not aware…`. The row's own
/// start is 44.70. #41 carried it for a right-to-left page and left this side alone (#272).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/272"))
func aSplitRowLendsItsOwnStartToTheLineBeneathIt() throws {
    let fixture = try SourceLayoutFixture.load("911-259")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    var page = fixture.content()
    // Exclude the running header, which the full-document furniture pass removes.
    page.lines.removeAll { $0.text.contains("THE ATTACK LOOMS") }
    // The page's own evidence: one printed row, in two pieces, on one baseline.
    let pieces = page.lines.filter {
        $0.text.hasPrefix("ning for what later became") || $0.text.hasPrefix("the 9/11 attack.")
    }
    #expect(pieces.count == 2 && pieces[0].sharesRow(with: pieces[1]))
    #expect(abs(pieces[0].rect.minX - 44.70) < 0.01 && abs(pieces[1].rect.minX - 156.89) < 0.01)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let paragraphs = paragraphTexts(blocks)
    let joined = try #require(paragraphs.first { $0.contains("We have found no evidence") })
    #expect(joined.contains("travel through Iran, the al Qaeda operatives themselves were probably not aware"))
    #expect(joined.hasSuffix("cific details of their future operation."))
    #expect(!paragraphs.contains { $0.hasPrefix("Iran, the al Qaeda operatives") })
    // The paragraph the page prints beneath it still opens on its own: the row lends its start to
    // the line under it, not to everything that follows.
    #expect(paragraphs.contains { $0.hasPrefix("After 9/11, Iran and Hezbollah") })
    #expect(paragraphs.contains { $0.hasPrefix("7.4 FINAL STRATEGIES AND TACTICS") })
    #expect(paragraphs.first?.hasPrefix("Moqed, flew into Iran from Bahrain.") == true)
}

/// A row the extractor cut where the page left no space lends nothing. PDFKit ends a line at a
/// gap; where the pieces touch it cut between two runs the page set beside each other, and what
/// the page began that row with says nothing about the line beneath.
///
/// USGS MCS 2025 page 2 closes `…undiscovered resources contained an estimated 3.5 billion` at
/// x 522.42 with the 6.5-point note marker `8` at x 522.48, six hundredths of a point past it,
/// and sets `Substitutes: Aluminum substitutes…` on the same left edge 22.36 points of baseline
/// below, where its own leading is 10.53 (#272).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/272"))
func aRowCutWhereThePageLeftNoSpaceKeepsItsStartToItself() throws {
    let lines = [
        TextLine(text: "World Resources:6 The most recent U.S. Geological Survey assessment of global copper resources",
                 rect: CGRect(x: 45.36, y: 259.25, width: 512.36, height: 14.43), fontSize: 10.08),
        TextLine(text: "as of 2015, identified resources contained 1.5 billion tons of unextracted copper (2.1 billion",
                 rect: CGRect(x: 45.36, y: 248.72, width: 519.09, height: 13.76), fontSize: 10.08),
        TextLine(text: "of 0.6 billion tons is included) and undiscovered resources contained an estimated 3.5 billion",
                 rect: CGRect(x: 45.36, y: 237.69, width: 477.06, height: 13.76), fontSize: 10.08),
        TextLine(text: "8", rect: CGRect(x: 522.48, y: 242.45, width: 3.60, height: 8.85), fontSize: 6.48),
        TextLine(text: "Substitutes: Aluminum substitutes for copper in automobile radiators, cooling and refrigeration",
                 rect: CGRect(x: 45.36, y: 215.33, width: 487.67, height: 14.43), fontSize: 10.08),
        TextLine(text: "equipment, and power cable. Optical fiber substitutes for copper in telecommunications uses,",
                 rect: CGRect(x: 45.36, y: 204.80, width: 498.89, height: 13.76), fontSize: 10.08),
    ]
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(
        page: PageContent(number: 2, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                          lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    let paragraphs = paragraphTexts(blocks)
    // The marker still belongs to the row it closes, and that row is still one block.
    #expect(paragraphs.contains { $0.hasPrefix("World Resources:") && $0.hasSuffix("3.5 billion 8") })
    #expect(paragraphs.contains { $0.hasPrefix("Substitutes: Aluminum") })
    #expect(!paragraphs.contains { $0.contains("3.5 billion 8 Substitutes:") })
}

/// A hanging entry whose marker the extractor split off keeps the wrap the page hangs under it.
/// The census's RRS-2002-01 page 17 hands back `[ 12]` at x 134.81 and
/// `Lambert, D.: … Journal of Official Statistics,` at x 157.25 as one row, and hangs
/// `9, (1993) 313–331.` at x 156.17. The row's own start is the marker's, two and a half bodies
/// out from the edge the entry's wrap stands on, so the piece's start stays admissible too (#272).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/272"))
func aRowSplitAtItsHangingMarkerKeepsTheWrapBeneathIt() throws {
    let lines = [
        TextLine(text: "[ 12]", rect: CGRect(x: 134.81, y: 203.48, width: 17.35, height: 10.43), fontSize: 9),
        TextLine(text: "Lambert, D.: Measures of Disclosure Risk and Harm, Journal of Official Statistics,",
                 rect: CGRect(x: 157.25, y: 203.48, width: 323.34, height: 10.43), fontSize: 9),
        TextLine(text: "9, (1993) 313–331.",
                 rect: CGRect(x: 156.17, y: 192.02, width: 74.35, height: 10.92), fontSize: 9),
    ]
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(
        page: PageContent(number: 17, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                          lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.count == 1)
    #expect(blocks[0].text.contains("Journal of Official Statistics, 9, (1993) 313–331."))
}

/// A space the page repeats in the same place on row after row is a column it set, not a space
/// inside a printed line, and successive rows of it stay separate blocks. Project Blue Book's
/// statistical appendix is rows of cells standing closer than a gutter; reading each row as one
/// line ran thirty of them together (#272).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/272"))
func aSeamThePageRepeatsOnRowAfterRowIsAColumnAndNotASpace() throws {
    func row(_ left: String, _ right: String, y: Double) -> [TextLine] {
        [TextLine(text: left, rect: CGRect(x: 60, y: y, width: 90, height: 10), fontSize: 10),
         TextLine(text: right, rect: CGRect(x: 155, y: y, width: 90, height: 10), fontSize: 10)]
    }
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let lines = row("0-Balloon", "certain doubtful", y: 600) + row("1-Astronomical", "certain doubtful", y: 588)
        + row("2-Aircraft", "certain doubtful", y: 576) + row("3-Light Phenomena", "certain doubtful", y: 564)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(
        page: PageContent(number: 120, bounds: bounds, lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    // Each row is still one block — its pieces join as they always have — and no row takes the
    // one beneath it.
    #expect(LayoutReconstructor.columnSeams(in: lines, body: 10, rightToLeft: false) == [155, 155, 155, 155])
    #expect(paragraphTexts(blocks).count == 4)
    #expect(paragraphTexts(blocks).first == "0-Balloon certain doubtful")
    // The control: one row of the same shape, on a page that repeats the seam nowhere, is a line
    // the page broke at a space, and the line beneath it joins.
    let single = row("A sentence the page broke at a wide space", "and the rest of that line", y: 600)
        + [TextLine(text: "carries on beneath it at the same edge.",
                    rect: CGRect(x: 60, y: 588, width: 180, height: 10), fontSize: 10)]
    #expect(LayoutReconstructor.columnSeams(in: single, body: 10, rightToLeft: false).isEmpty)
    let joined = LayoutReconstructor.blocks(
        page: PageContent(number: 120, bounds: bounds, lines: single, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(joined).count == 1)
}

// MARK: - A line rectangle PDFKit grew to fit what the line carries (#230)

/// PDFKit gives a line the height of the tallest glyph on it rather than the line's own extent,
/// so a line of running prose carrying one inline radical reaches into the line beneath it.
/// Wallace's page 290 prints one paragraph and the reading broke it mid-sentence: the line
/// `72 = 36 · 2, but often the time it takes to discover the larger perfect square is more` is
/// reported 20.46 points high where every other line of that paragraph is 11.98, so it overlaps
/// `than it would take to simplify in several steps.` by 5.82 points (#230; the same measurement
/// #213 records from the cropping side, drafted for Apple as
/// `measurements/apple-feedback-line-heights/report.md`).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/230"))
func aLineRectangleGrownByWhatItCarriesDoesNotBreakItsParagraph() throws {
    let fixture = try SourceLayoutFixture.load("algebra-290")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    // The page's own evidence: three consecutive lines of one paragraph, the middle one grown.
    let paragraph = page.lines.filter {
        $0.text.hasPrefix("The previous example could have been done in fewer")
            || $0.text.hasPrefix("72=") || $0.text.hasPrefix("than it would take to simplify")
    }.sorted { $0.rect.maxY > $1.rect.maxY }
    #expect(paragraph.count == 3)
    #expect(abs(paragraph[0].rect.height - 11.98) < 0.01)
    #expect(abs(paragraph[1].rect.height - 20.46) < 0.01)
    #expect(abs(paragraph[2].rect.height - 11.98) < 0.01)
    // The grown rectangle reaches 5.82 points into the line beneath it.
    #expect(abs((paragraph[1].rect.minY - paragraph[2].rect.maxY) + 5.82) < 0.01)
    // And the page states what an ordinary line of that size measures.
    #expect(LayoutReconstructor.ordinaryLineHeights(in: page.lines)[12].map { abs($0 - 11.98) < 0.01 } == true)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let joined = try #require(paragraphTexts(blocks).first { $0.hasPrefix("The previous example could have been done in fewer") })
    #expect(joined.hasSuffix("is more than it would take to simplify in several steps."))
    #expect(!paragraphTexts(blocks).contains { $0.hasPrefix("than it would take to simplify") })
}

/// The adjustment is asked only where the two rectangles overlap, and reaches only as far as the
/// page's own ordinary line at that size: it can bring a negative gap back towards nothing and
/// can never open one, so no pair of lines the page already reads as one paragraph is separated
/// by it (#230).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/230"))
func anOrdinaryRectangleIsStillTheLine() throws {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    // Eight ordinary lines state the page's ordinary height, and a ninth the page pushed a
    // paragraph's space below still opens its own block: the gap there is positive, so nothing
    // is adjusted.
    var lines = (0..<8).map { index in
        TextLine(text: "an ordinary line of this page's prose, number \(index), filling its measure",
                 rect: CGRect(x: 60, y: 700 - CGFloat(index) * 14, width: 300, height: 12), fontSize: 12)
    }
    lines.append(TextLine(text: "A line the page set a paragraph's space below the last of them.",
                          rect: CGRect(x: 60, y: 700 - 8 * 14 - 12, width: 300, height: 12), fontSize: 12))
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(
        page: PageContent(number: 1, bounds: bounds, lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(LayoutReconstructor.ordinaryLineHeights(in: lines)[12] == 12)
    #expect(paragraphTexts(blocks).count == 2)
    #expect(paragraphTexts(blocks)[1].hasPrefix("A line the page set a paragraph"))
}

// MARK: - A row of cells the page states no column for (#285)

/// Project Blue Book's statistical appendix is handwriting-quality OCR, so its eight-column rows
/// break in a different place on every one of them: no seam recurs on three rows, and each break
/// is a space's width, so neither the repeated-seam test nor the gutter reaches them. Five of
/// those rows took the row beneath them, because a row's own start is its first cell's and the
/// next row begins on that same column.
///
/// The piece that closed the row is what the reading takes the row's text and its wrap from, so
/// it is what has to read as a line of writing. `~ 2(./ /.l,O .2/.I` is a cell of figures, and a
/// row it closes stands for no line (#285).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/285"))
func aRowClosedByACellOfFiguresLendsNoStart() throws {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    func page(closing: String) -> PageContent {
        PageContent(number: 242, bounds: bounds, lines: [
            TextLine(text: "6-lnsuffic.lnfo. 7 0 7 11.3 0.0 11.8 10 0 10 11.1 0.0 11.1",
                     rect: CGRect(x: 60, y: 600, width: 280, height: 10), fontSize: 10),
            TextLine(text: closing, rect: CGRect(x: 345, y: 600, width: 60, height: 10), fontSize: 10),
            TextLine(text: "7-Psychological 1 1 2 0.0 1.6 1.6 0 0 0 0.0 0.0 0.0",
                     rect: CGRect(x: 60, y: 588, width: 270, height: 10), fontSize: 10),
        ], graphics: [])
    }
    var warnings: [ConversionWarning] = []
    // The page repeats no seam: the rule this one guards stood aside for nothing here.
    #expect(LayoutReconstructor.columnSeams(in: page(closing: "~ 2(./ /.l,O .2/.I").lines,
                                            body: 10, rightToLeft: false).isEmpty)
    let cells = paragraphTexts(LayoutReconstructor.blocks(
        page: page(closing: "~ 2(./ /.l,O .2/.I"), images: [], vocabulary: [], warnings: &warnings))
    // The row's own pieces still join — only its start is withheld — and the row beneath it opens
    // its own block.
    #expect(cells.count == 2)
    #expect(cells[0].hasPrefix("6-lnsuffic.lnfo.") && cells[0].hasSuffix("~ 2(./ /.l,O .2/.I"))
    #expect(cells[1].hasPrefix("7-Psychological"))
    // The control, which is what #272 is for: the same geometry, closed by writing, is one
    // printed line and the line beneath it is its wrap.
    let prose = paragraphTexts(LayoutReconstructor.blocks(
        page: page(closing: "and the rest of it"), images: [], vocabulary: [], warnings: &warnings))
    #expect(prose.count == 1)
    #expect(prose[0].contains("and the rest of it 7-Psychological"))
}

/// A piece of one or two marks says nothing either way, and is asked nothing. The Blue Book's own
/// speed legend closes `Meteor-Ii ke` with the rule the page draws for "not stated", and the line
/// beneath it is that answer (#285, the join #272 makes here).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/285"))
func aPieceTooShortToSaySoLendsTheRowsStartAsBefore() throws {
    #expect(BlockAssembler.readsAsWriting("-"))
    #expect(BlockAssembler.readsAsWriting("8"))
    #expect(BlockAssembler.readsAsWriting("12"))
    // Three marks is where the page is asked, and half its marks must be letters.
    #expect(BlockAssembler.readsAsWriting("Ii ke"))
    #expect(BlockAssembler.readsAsWriting("and the rest of that line"))
    #expect(BlockAssembler.readsAsWriting("the 9/11 attack. At the time of their travel through"))
    #expect(BlockAssembler.readsAsWriting("occurred far later than"))
    #expect(BlockAssembler.readsAsWriting("Lambert, D.: Measures of Disclosure Risk and Harm,"))
    #expect(!BlockAssembler.readsAsWriting("~ 2(./ /.l,O .2/.I"))
    #expect(!BlockAssembler.readsAsWriting("\u{2713}.:-"))
    #expect(!BlockAssembler.readsAsWriting("26 JJ' S'I- ff.I /9.!i 5i.t. If j'_,"))
    #expect(!BlockAssembler.readsAsWriting("1.5 0.0 11.8"))
    // Any script counts as writing, not Latin alone.
    #expect(BlockAssembler.readsAsWriting("\u{7B2C}\u{4E8C}\u{7AE0}"))
    #expect(BlockAssembler.readsAsWriting("\u{0627}\u{0644}\u{0648}\u{0644}\u{0627}\u{064A}\u{0627}\u{062A}"))
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

/// The control for trying that cut last: the handbook's appendix of abbreviations opens page 461
/// under a full-measure banner and sets two columns of short entries beneath it. Its intro spans
/// both columns, so no gutter is found and no whitespace band crosses the page either — but
/// `columnRuns` reads the two columns as runs, and cutting the banner out first would hand what
/// is left to the row-major sort, one entry of each column at a time (#160, #174).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func aBannerOverTwoColumnsOfEntriesLeavesTheColumnRunsAlone() throws {
    let fixture = try SourceLayoutFixture.load("faa-461")
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    var page = fixture.content()
    page.lines.removeAll { $0.text == "A-1" }
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let banner = try #require(regions.first)
    #expect(banner.width >= page.bounds.width * 0.75 && !page.lines.contains { $0.rect.minY >= banner.maxY })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                            vocabulary: [], warnings: &warnings)
    // The left column is read out before the right one, rather than one entry of each in turn.
    let text = blocks.map(\.text).joined(separator: "\n")
    try expectInOrder(text, ["A/C—aircraft", "A/FD—airport/facility directory", "AAF—Army Air Field",
                             "ABV—above", "ADIN—AUTODIN service", "ADJ—adjacent"])
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

// MARK: - Columns read as runs (#174)

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
        "consistently higher than the 3",                         // #214 resumes the same paragraph
        "Infrared thermometer mounted on a pole",                 // its separately retained caption
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

/// A hanging bullet column is not a column (#279).
///
/// A page that hangs its bullets clear of their items sets a column of markers beside a column of
/// item text. Where the items are short, `columnRuns` (#174) read that as two columns and handed
/// the whole run of markers over before any of their items — and nothing downstream could put an
/// item back with its marker, because #261's rule joins a marker to the piece the page set on its
/// own printed row, and by the time the markers arrived their rows were gone.
///
/// The marker run only forms at all by chaining onto the paragraph that introduces the list: each
/// marker stands within a body beneath that paragraph's last line and overlaps its measure, and
/// the run is then substantial because the *introduction's* lines are wide. It holds no
/// substantial line of its own, which is the thing `columnRuns` already refuses, one step removed.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/279"))
func aHangingBulletColumnIsNotAColumn() throws {
    // The FAA handbook's page 31 prints the sport-pilot hours as six one-line items, the marker at
    // x=294.00 and the item at x=312.00 on one baseline; page 239 does the same with the four
    // items of its ELT inspection list. Those two pages are the whole of it in this book: after
    // #261 the handbook held 10 blocks that were a bare bullet, six here and four there.
    for (name, items) in [("faa-31", ["Airplane: 20 hours", "Powered Parachute: 12 hours",
                                      "Weight-Shift Control (Trikes): 20 hours", "Glider: 10 hours",
                                      "Rotorcraft (gyroplane only): 20 hours",
                                      "Lighter-Than-Air: 20 hours (airship) or 7 hours"]),
                          ("faa-239", ["Proper installation", "Battery corrosion",
                                       "Operation of the controls and crash sensor",
                                       "The presence of a sufficient signal radiated from its"])] {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
        var warnings: [ConversionWarning] = []
        let blocks = LayoutReconstructor.blocks(page: fixture.content(), images: [], vocabulary: [],
                                                warnings: &warnings)
        // Each marker reaches the reader with the item it marks, and no block is a bare bullet.
        for item in items {
            #expect(blocks.contains { $0.text == "• \(item)" }, Comment(rawValue: "\(name): \(item)"))
        }
        #expect(!blocks.contains { $0.text.trimmingCharacters(in: .whitespaces) == "•" },
                Comment(rawValue: name))
        // And the items are not run together into one paragraph, which is what reading the two
        // runs out as columns did to them.
        #expect(!blocks.contains { $0.text.contains(items[0]) && $0.text.contains(items[1]) },
                Comment(rawValue: name))
    }
}

/// The bound is the one #261 measured: a marker is never a column of its own, but what the page
/// sets a *column* away on that row is a column and is read as one (#279).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/279"))
func aBulletSetAColumnAwayFromWhatFollowsItStillReadsAsAColumn() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 10), image: nil)
    }
    // The FAA handbook's page 31 in miniature: an introduction that wraps and closes short, four
    // bullets hung clear of the pieces beside them, and two lines running on beneath. The markers
    // chain onto the introduction and borrow its substance; the pieces beside them form a run of
    // their own, because the introduction's own last line is too short to take the first of them.
    func page(pieceX: Double, pieceWidth: Double) -> [LayoutReconstructor.Element] {
        var elements = [line("An introduction to the list that follows, set across the whole measure",
                             x: 40, y: 736, width: 260),
                        line("of this page and wrapping once beneath itself before it closes on",
                             x: 40, y: 724, width: 260),
                        line("this page:", x: 40, y: 712, width: 30)]
        for row in 0..<4 {
            let y = 700 - Double(row) * 12
            elements.append(line("\u{2022}", x: 40, y: y, width: 3.5))
            elements.append(line("A piece of this page standing on that row, row \(row)",
                                 x: pieceX, y: y, width: pieceWidth))
        }
        for row in 0..<2 {
            elements.append(line("A line set across the whole measure of this page, running on",
                                 x: 40, y: 652 - Double(row) * 12, width: 260))
        }
        return elements
    }
    // A piece 1.45 bodies past the marker is the item that marker marks, and these are rows.
    #expect(LayoutReconstructor.columnRuns(page(pieceX: 58, pieceWidth: 130), bodySize: 10) == nil)
    // A piece twelve bodies along that row is the second column of the page — the Blue Book sets
    // one at 12.2 bodies and the Warren Commission at 5.2 and 8.1 — and the page is read as the
    // columns it sets. Both readings were available before this guard; only the first has moved.
    #expect(LayoutReconstructor.columnRuns(page(pieceX: 163.5, pieceWidth: 136), bodySize: 10) != nil)
}


/// A reference list the page hangs under an outdented marker column is one paragraph per entry
/// (#282).
///
/// Nothing in the geometry alone says so. The ordinary column test allows one and a half bodies
/// and these entries hang further — 1.35 bodies in the Replay Clocks paper, 2.37 in the Census
/// paper — so each wrap opened a paragraph of its own; #160's hung-entry rule asks the wrap to
/// stop a body short of the entry's right edge, which a justified reference list never does; and
/// where the extractor kept the marker apart it stood past the gutter two pieces of one row are
/// joined within, and joined the paragraph *above* it. What states the list is the marker column.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/282"))
func aReferenceListHungUnderItsMarkerColumnIsOneParagraphPerEntry() throws {
    for (name, sha, count) in [("replay-10", "1e8172e4a347bdf6722dacc38755f6fb3299866336b8153f51b2c13f3ac6109a", 12),
                               ("census-17", "0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905", 14)] {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == sha)
        var warnings: [ConversionWarning] = []
        let blocks = LayoutReconstructor.blocks(page: fixture.content(), images: [], vocabulary: [],
                                                warnings: &warnings)
        // One block per citation, opening on its own number.
        let entries = blocks.filter { $0.text.hasPrefix("[") }
        #expect(entries.count == count, Comment(rawValue: "\(name): \(entries.map { $0.text.prefix(12) })"))
        for number in 1...count {
            #expect(entries.contains { $0.text.range(of: "^\\[ ?\(number)\\] ", options: .regularExpression) != nil },
                    Comment(rawValue: "\(name): [\(number)]"))
        }
        // No block is a bare citation number, and none of the entry text stands on its own.
        #expect(!blocks.contains { $0.text.range(of: "^\\[ ?[0-9]+\\]$", options: .regularExpression) != nil },
                Comment(rawValue: name))
    }
    // Each paper's own worked case. Replay Clocks' entry 11 hangs its wrap 1.70 bodies, which the
    // column test refuses and which only one entry of the twelve does, so #160's three-on-one-edge
    // rule never believed it; its entry 4 is broken after `…with physical clocks.` at a row the
    // extractor split, 5.4 points along that same row.
    var warnings: [ConversionWarning] = []
    let replay = LayoutReconstructor.blocks(page: try SourceLayoutFixture.load("replay-10").content(),
                                            images: [], vocabulary: [], warnings: &warnings)
    #expect(replay.contains { $0.text.contains("efficient implementation of vector clocks. Inf. Process. Lett., 43(1):47–52, 1992.") })
    #expect(replay.contains { $0.text.contains("with physical clocks. In Proceedings of the 23rd") })
    // The Census paper's entry 8 kept its number apart at x 134.81 with the entry at x 156.17,
    // 2.37 bodies away: the number used to close the paragraph above it.
    let census = LayoutReconstructor.blocks(page: try SourceLayoutFixture.load("census-17").content(),
                                            images: [], vocabulary: [], warnings: &warnings)
    #expect(census.contains { $0.text.hasPrefix("[ 8] Kim, J. J.: A Method for Limiting Disclosure") })
    #expect(!census.contains { $0.text.hasSuffix("(1969) 1183–1210. [ 7]") })
}

/// The marker column is what the rule reads, and a page has to set one (#282).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/282"))
func aPageStatesItsMarkerColumnOrTheRuleIsSilent() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 10), fontSize: 9)
    }
    /// A reference list: three outdented numbers, their entries at one edge, one hung wrap.
    func list(markers: Int, wraps: Bool, indent: Double = 20) -> [TextLine] {
        var lines: [TextLine] = []
        var y = 700.0
        for index in 1...max(markers, 1) {
            lines.append(line("[\(index)]", x: 100, y: y, width: 9))
            lines.append(line("An author, a title long enough to fill this column's whole measure,",
                              x: 100 + indent, y: y, width: 240))
            y -= 11
            if wraps {
                lines.append(line("and the rest of that entry, hung beneath it on the entry's edge.",
                                  x: 100 + indent, y: y, width: 230))
                y -= 11
            }
        }
        return lines
    }
    #expect(LayoutReconstructor.hangingMarkerList(in: list(markers: 3, wraps: true), body: 9) != nil)
    // Fewer than three entries state no column: two lines agreeing on an edge agree on nothing.
    #expect(LayoutReconstructor.hangingMarkerList(in: list(markers: 2, wraps: true), body: 9) == nil)
    // A column of numbers beside one-line cells hangs nothing, and is a table's business (#210).
    #expect(LayoutReconstructor.hangingMarkerList(in: list(markers: 4, wraps: false), body: 9) == nil)
    // And the marker must be outdented by an indent, not by a column's gutter: beyond three
    // bodies the page has set two columns, which the column and table readers read.
    #expect(LayoutReconstructor.hangingMarkerList(in: list(markers: 3, wraps: true, indent: 28), body: 9) == nil)
    // A short cell beside each number is no entry either.
    let cells = (1...4).flatMap { index in
        [line("[\(index)]", x: 100, y: 700 - Double(index) * 11, width: 9),
         line("12.5", x: 120, y: 700 - Double(index) * 11, width: 20)]
    }
    #expect(LayoutReconstructor.hangingMarkerList(in: cells, body: 9) == nil)
}

/// A page number a contents entry runs its leader out to belongs to that entry (#277, #207).
///
/// Project Blue Book sets its contents and its list of illustrations in three columns — the
/// `Figure N` or `Table N` label, the title, and the page number at the right margin. The white
/// between the titles and the numbers is far wider than any gutter, so the column cut was made
/// and each band read out its entries and then their numbers. Until #264 the geometry of these
/// pages was unusable — the rule the book paints down its margin was merged into the line beside
/// it — so this is what the corrected geometry exposed underneath.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/277"))
func aContentsEntryKeepsThePageNumberItsLeaderRunsOutTo() throws {
    func reading(_ name: String) throws -> [String] {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == "90e05e77fc088c29758c2ddda514c0c12f317e5686ee213d348db2f9da152ee3")
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: fixture.content(), images: [], vocabulary: [],
                                          warnings: &warnings).map(\.text)
    }
    // Page 5's list of illustrations: label, title, number, then the next entry.
    let five = try reading("blue-contents-5")
    try expectInOrder(five.joined(separator: "\n"), [
        "Figure l", "Frequency of Sightings by Year", "17",
        "Figure 2", "Distribution of Evaluations of Object", "18",
        "Figure 3", "With Comparisons", "19",
        "Figure 4", "for All Years and Each Year", "20",
        "Figure 5", "Within Months for All Years", "21",
    ])
    // Page 7 does the same for its tables, and its own numbers include one the scanned layer
    // misread: `ti6` for 66, in a column where every other entry reads as a figure.
    let seven = try reading("blue-contents-7")
    try expectInOrder(seven.joined(separator: "\n"), [
        "Table IV", "on the Basis of Shape", "64",
        "Table V", "on the Basis of Duration of Observation", "65",
        "Table VI", "on the Basis of Speed", "ti6",
        "Table VII", "on the Basis of Light Brightness", "67",
    ])
    // And no band hands its numbers over in a run of their own, which is the whole defect.
    for reading in [five, seven] {
        let numbers = reading.enumerated().filter {
            $0.element.range(of: "^[0-9]+$", options: .regularExpression) != nil
        }.map(\.offset)
        #expect(!numbers.contains { numbers.contains($0 + 1) },
                Comment(rawValue: numbers.map { reading[$0] }.joined(separator: " ")))
    }
}

/// The cut the guard holds back is the one a page of prose columns needs (#277).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/277"))
func twoColumnsOfProseAreStillCutAtTheirGutter() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 10), image: nil)
    }
    // Two columns of prose, a wide gutter between them: read down one and then the other.
    var page: [LayoutReconstructor.Element] = []
    for row in 0..<4 {
        let y = 700 - Double(row) * 13
        page.append(line("A line of the left-hand column of this page, row \(row)", x: 40, y: y, width: 200))
        page.append(line("A line of the right-hand column of this page, row \(row)", x: 300, y: y, width: 200))
    }
    let columns = LayoutReconstructor.ordered(page, bodySize: 10).map { $0.rect.minX }
    #expect(columns == Array(repeating: 40.0, count: 4) + Array(repeating: 300.0, count: 4))
    // Replace the right-hand column with the page numbers those lines run their leaders out to,
    // and the page is read across its rows instead.
    var contents: [LayoutReconstructor.Element] = []
    for row in 0..<4 {
        let y = 700 - Double(row) * 13
        contents.append(line("An entry of a contents page, row \(row)", x: 40, y: y, width: 200))
        contents.append(line("\(17 + row)", x: 500, y: y, width: 9))
    }
    #expect(LayoutReconstructor.ordered(contents, bodySize: 10).map { $0.rect.minX }
            == [40, 500, 40, 500, 40, 500, 40, 500])
}

/// A two-column list whose right column is prose is read row by row, whatever divides its rows
/// (#283, #270).
///
/// The 9/11 report's appendix B is a table of names: twenty-three printed rows, a name at
/// x=44.70 and an office at x=152.70, with 29 points of white between them — four times what a
/// column cut needs. PDFKit merges exactly one of those rows, the `Janet Reno` row, and that
/// undivided line bridging the gutter is the only thing that keeps the page from being cut there.
/// Divide it, which is the correct reading of what the page prints and what #270's rule does on
/// its own geometry, and every name loses its office.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/283"))
func aTableOfNamesIsReadRowByRowOnceItsMergedRowIsDivided() throws {
    let fixture = try SourceLayoutFixture.load("911-451")
    let page = fixture.content()
    let merged = try #require(page.lines.first { $0.text.hasPrefix("Janet Reno Attorney General") })
    // The row as #270's cut divides it: the name on the left column's edge and the office on the
    // right column's, on the one baseline the page printed them on.
    func piece(_ text: String, x: Double, width: Double) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: merged.rect.minY, width: width,
                                          height: merged.rect.height), fontSize: merged.fontSize)
    }
    var lines = page.lines.filter { $0 != merged }
    lines.append(piece("Janet Reno", x: 44.70, width: 45.86))
    lines.append(piece("Attorney General, 1993–2001", x: 152.70, width: 110.33))
    let divided = PageContent(number: page.number, bounds: page.bounds, lines: lines,
                              graphics: page.graphics, pictures: page.pictures)
    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.blocks(page: divided, images: [], vocabulary: [],
                                          warnings: &warnings).map(\.text).joined(separator: "\n")
    try expectInOrder(text, [
        "Thomas Pickering", "Under Secretary of State, 1997–2000",
        "Colin Powell", "Secretary of State, 2001–",
        "Ronald Reagan", "40th President of the United States, 1981–1989",
        "Janet Reno", "Attorney General, 1993–2001",
        "Condoleezza Rice", "National Security Advisor, 2001–",
        "Bill Richardson", "Ambassador to the United Nations, 1997–1998",
    ])
    // And no name runs into the next: read as columns, seven of them ran together in one block.
    #expect(!text.contains("Thomas Pickering Colin Powell"))
    #expect(!text.contains("Condoleezza Rice Bill Richardson"))
    // The page as PDFKit actually hands it over is unchanged: its one merged row bridges the
    // gutter, so no cut was ever made there and none is made now.
    var asRead: [ConversionWarning] = []
    #expect(LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &asRead)
        .contains { $0.text == "Janet Reno Attorney General, 1993–2001" })
}

/// Three rows at least, each on its own row, none of them numbered, and a column of prose on the
/// other side of the white (#283).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/283"))
func aStackOfCellsIsThreeUnnumberedRowsBesideAColumnOfProse() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 10), image: nil)
    }
    func page(rows: Int, name: Double = 100, office: Double = 130,
              marker: String = "") -> [LayoutReconstructor.Element] {
        (0..<rows).flatMap { row -> [LayoutReconstructor.Element] in
            let y = 700 - Double(row) * 13
            return [line("\(marker)A name the page sets in its left column, row \(row)", x: 40, y: y, width: name),
                    line("\(marker)The office that name held, set in the column beside it", x: 300, y: y, width: office)]
        }
    }
    // Three rows of a name against an office: cells beside a column of prose, read across.
    #expect(LayoutReconstructor.ordered(page(rows: 3), bodySize: 10).map { $0.rect.minX }
            == [40, 300, 40, 300, 40, 300])
    // Two rows state no stack, and the page is cut at its gutter as it always was.
    #expect(LayoutReconstructor.ordered(page(rows: 2), bodySize: 10).map { $0.rect.minX }
            == [40, 40, 300, 300])
    // A column of prose is a column however its rows line up: neither side is a stack of cells
    // once each holds two lines of a column's own measure.
    #expect(LayoutReconstructor.ordered(page(rows: 3, name: 130), bodySize: 10).map { $0.rect.minX }
            == [40, 40, 40, 300, 300, 300])
    // Two stacks of cells beside each other are two columns, and reading them across would take
    // each apart. The 9/11 report's own staff pages set a name over the post they held down both
    // sides of the page, and every one of those names is short, on its own row, and beside a line
    // of the other column.
    #expect(LayoutReconstructor.ordered(page(rows: 3, office: 100), bodySize: 10).map { $0.rect.minX }
            == [40, 40, 40, 300, 300, 300])
    // And a grid the page numbered states its own order. What to do with Wallace's two-per-row
    // exercise grids is an owner decision taken in #195 and scoped in #219 item 4, which names
    // the contract and the test it has to move with; until it lands, a numbered cell keeps the
    // reading it has.
    #expect(LayoutReconstructor.ordered(page(rows: 3, marker: "1) "), bodySize: 10).map { $0.rect.minX }
            == [40, 40, 40, 300, 300, 300])
}
