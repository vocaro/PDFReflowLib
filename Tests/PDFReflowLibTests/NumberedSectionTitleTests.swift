import CoreGraphics
import Testing
@testable import PDFReflowLib

/// Section titles a book numbers, where neither their size nor their weight reaches the library
/// (#297).
///
/// The Census report sets `2 Data Files` in 12-point bold over a 10.08-point body and
/// `2.1 Domingo-Ferrer and Mateo-Sanz` in bold at the body's size. PDFKit names every one of its
/// fonts `Helvetica` with no bold trait (#250), so the recurring-label rule never sees a style, and
/// a fifth over the body is under the quarter a title-sized line must clear. What the book states is
/// its numbering, and that is what reads them as headings.
private let censusSHA256 = "0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905"

/// Census page 3 as the extraction fixture holds it, which is PDFKit's reading before the index-glyph
/// decoder: every letter three on. The geometry and sizes are the fixture's own; the text of the
/// lines used here is the page as printed (`corpus/cache/rrs2002-01.pdf`, page 3, read against its
/// render), which is what the decoder gives the reconstruction.
private func censusPage3() throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("census-3")
    #expect(fixture.sourceSHA256 == censusSHA256)
    let printed = [
        "2 Data Files",
        "Two data ﬁles were used.",
        "2.1 Domingo-Ferrer and Mateo-Sanz",
        "We used the same subset of American Housing Survey 1993 public-used data that",
        "was used by [ 5]. The Data Extraction System (http://www.census.gov/DES)",
        "was used to select 13 variables and 1080 records. No records having missing",
        "values or zeros were used.",
        "2.2 Kim-Winkler",
        "The original unmasked ﬁle of 59,315 records is obtained by matching IRS income",
        "data to a ﬁle of the 1991 March CPS data. The ﬁelds from the matched ﬁle",
        "originating in the IRS ﬁle are as follows:",
        "1. Total income",
        "2. Adjusted gross income",
        "3. Wage and salary income",
    ]
    var page = fixture.content()
    #expect(page.lines.count >= printed.count)
    page.lines = zip(page.lines, printed).map { line, text in
        TextLine(text: text, rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
    }
    return page
}

/// A page of the same book opening with numbered titles over a paragraph, set as page 3 sets
/// them: a title's size, a clear gap, then body lines on the report's 12-point leading.
private func titledPage(_ number: Int, titles: [(String, CGFloat)]) -> PageContent {
    var y = 662.0
    var lines: [TextLine] = []
    for (title, size) in titles {
        lines.append(TextLine(text: title, rect: CGRect(x: 134.8, y: y, width: Double(title.count) * size * 0.5,
                                                         height: size * 1.2), fontSize: size))
        y -= 24
        for text in ["The masking methods and the scoring metrics are described in this part of",
                     "the report, with the variants that are specially developed for re-identiﬁcation",
                     "of masked ﬁles, and compared across the two data ﬁles used."] {
            lines.append(TextLine(text: text, rect: CGRect(x: 134.8, y: y, width: 345.9, height: 11.56),
                                  fontSize: 10.08))
            y -= 12
        }
        y -= 20
    }
    return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                       lines: lines, graphics: [])
}

/// The context a conversion of these pages resolves, through the extraction pass's own evidence.
private func context(of pages: [PageContent]) throws -> LayoutReconstructor.DocumentContext {
    var evidence = DocumentEvidence(chapterCandidates: [], language: "en")
    for (index, page) in pages.enumerated() {
        try evidence.collect(page, pageIndex: index, suppliesVocabulary: true, options: ConversionOptions())
    }
    return evidence.resolved(options: ConversionOptions()).context
}

private func headings(_ page: PageContent, _ context: LayoutReconstructor.DocumentContext) -> [String] {
    var warnings: [ConversionWarning] = []
    return headingTexts(LayoutReconstructor.blocks(page: page, images: [], context: context, warnings: &warnings))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/297"))
func censusNumberedSectionAndSubsectionTitlesAreHeadings() throws {
    let page3 = try censusPage3()
    // The report's native pages number sections 1, 2, 4 and 7 (3, 5 and 6 fall on pages it must
    // recognize), and subsections 2.1, 2.2, 4.1 and 4.2.
    let book = [
        titledPage(2, titles: [("1 Introduction", 12)]),
        page3,
        titledPage(10, titles: [("4 Results", 12), ("4.1 Domingo Data Statistics", 10.08)]),
        titledPage(11, titles: [("4.2 Kim-Winkler Data Statistics", 10.08)]),
        titledPage(17, titles: [("7 References", 12)]),
    ]
    let resolved = try context(of: book)
    #expect(headings(page3, resolved) == ["2 Data Files", "2.1 Domingo-Ferrer and Mateo-Sanz", "2.2 Kim-Winkler"])
    #expect(headings(book[2], resolved) == ["4 Results", "4.1 Domingo Data Statistics"])
    #expect(headings(book[3], resolved) == ["4.2 Kim-Winkler Data Statistics"])
    // What the page read as before: neither size nor weight says any of them is a heading.
    #expect(headings(page3, LayoutReconstructor.DocumentContext()).isEmpty)
    // One book numbering one section is no outline: the numbering is the evidence.
    #expect(headings(page3, try context(of: [page3])).isEmpty)
    // The numbered list beneath `2.2` is not a title, and the paragraphs stay paragraphs.
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page3, images: [], context: resolved, warnings: &warnings)
    #expect(paragraphTexts(blocks).contains("Two data ﬁles were used."))
    #expect(!headingTexts(blocks).contains { $0.hasPrefix("1.") || $0.hasPrefix("Two") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/297"))
func anOutlineIsTheBooksOwnNumbering() {
    typealias Candidate = NumberedSectionTitles.Candidate
    func section(_ page: Int, _ number: Int, size: Int = 24) -> Candidate {
        Candidate(page: page, number: [number], size: size, body: 20)
    }
    func subsection(_ page: Int, _ number: [Int], size: Int = 20) -> Candidate {
        Candidate(page: page, number: number, size: size, body: 20)
    }
    let census = [section(2, 1), section(3, 2), subsection(3, [2, 1]), subsection(3, [2, 2]),
                  section(10, 4), subsection(10, [4, 1]), subsection(11, [4, 2]), section(17, 7)]
    let outline = NumberedSectionTitles.outline(from: census)
    #expect(outline.titles.count == 8)
    #expect(outline.contains(page: 3, number: [2, 1], size: 20))

    // Fewer than three sections, a sequence that does not start at 1, one that repeats a number
    // as a running head does, and one that jumps as a magazine's page numbers do are no outline.
    #expect(NumberedSectionTitles.outline(from: [section(2, 1), section(3, 2)]).titles.isEmpty)
    #expect(NumberedSectionTitles.outline(from: [section(2, 2), section(3, 3), section(4, 4)]).titles.isEmpty)
    #expect(NumberedSectionTitles.outline(from: [section(2, 1), section(3, 2), section(4, 2), section(5, 3)]).titles.isEmpty)
    #expect(NumberedSectionTitles.outline(from: [section(2, 1), section(2, 4), section(2, 18), section(2, 20)]).titles.isEmpty)
    // Sections set at the body's own size say nothing on their own.
    #expect(NumberedSectionTitles.outline(from: [section(2, 1, size: 20), section(3, 2, size: 20),
                                                 section(4, 3, size: 20)]).titles.isEmpty)

    // A subsection stands between the sections its number places it between: `5.1` before
    // section 5 has started is not one of this outline's, and a book with one subsection states no
    // subsection numbering at all.
    let sections = [section(2, 1), section(3, 2), section(9, 5), section(12, 6)]
    let misplaced = NumberedSectionTitles.outline(from: sections + [subsection(4, [5, 1]), subsection(10, [5, 2])])
    #expect(!misplaced.contains(page: 4, number: [5, 1], size: 20))
    #expect(!misplaced.contains(page: 10, number: [5, 2], size: 20))
    #expect(misplaced.titles.count == 4)
    let lone = NumberedSectionTitles.outline(from: sections + [subsection(10, [5, 1])])
    #expect(lone.titles.count == 4)
    // A two-level number set larger than the body is not this rule's subsection.
    let large = NumberedSectionTitles.outline(from: sections + [subsection(10, [5, 1], size: 24),
                                                                subsection(11, [5, 2], size: 24)])
    #expect(large.titles.count == 4)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/297"))
func onlyALineThatStandsApartIsANumberedTitle() {
    let body: CGFloat = 10
    /// Lines stacked on one left edge, top to bottom, `gaps[i]` points of white above line `i`.
    func stack(_ texts: [String], gaps: [Int: Double] = [:]) -> [TextLine] {
        var top = 700.0
        return texts.enumerated().map { index, text in
            if index > 0 { top -= 12 + (gaps[index] ?? 0) }
            return TextLine(text: text, rect: CGRect(x: 60, y: top - 12, width: Double(text.count) * 5, height: 12),
                            fontSize: 10)
        }
    }
    func title(_ lines: [TextLine]) -> [String]? {
        NumberedSectionTitles.titleLines(of: lines[1], in: lines, body: body)?.map(\.text)
    }
    let prose = "The masking methods are described in this part of the report and compared."
    // A title set apart above and below.
    #expect(title(stack([prose, "2.1 Rank Swapping", prose], gaps: [1: 12, 2: 6])) == ["2.1 Rank Swapping"])
    // One the page wraps onto a second line at its own leading: Replay Clocks' section 6.
    #expect(title(stack([prose, "6 REPRESENTATION OF REPCL AND ITS", "OVERHEAD", prose], gaps: [1: 12, 3: 6]))
            == ["6 REPRESENTATION OF REPCL AND ITS", "OVERHEAD"])

    // A bold run-in paragraph start carries on as its paragraph, one leading below.
    #expect(title(stack([prose, "2.1 Rank Swapping. The method exchanges values between records",
                         "whose ranks are close, as described in the report.", prose], gaps: [1: 12, 3: 6])) == nil)
    // A numbered paragraph wraps the same way, and so does one that happens to end mid-sentence.
    #expect(title(stack([prose, "3 Many records were masked with additive noise before", "they were compared.", prose],
                        gaps: [1: 12, 3: 6])) == nil)
    // Numbered list items stand one leading apart, with or without a point after the number.
    #expect(title(stack([prose, "1. Total income", "2. Adjusted gross income"], gaps: [1: 12])) == nil)
    #expect(title(stack(["1 Total income", "2 Adjusted gross income", "3 Wage and salary income"])) == nil)
    // Nothing above it but a line one leading up: the title must stand clear of it.
    #expect(title(stack([prose, "2.1 Rank Swapping", prose], gaps: [2: 6])) == nil)
    // A title with nothing beneath it heads nothing on this page.
    #expect(title(stack([prose, "2.1 Rank Swapping"], gaps: [1: 12])) == nil)

    // What reads as a numbered title at all: a number of one or two levels, no point after it,
    // then a capital and three letters, over at most a title's length.
    #expect(NumberedSectionTitles.number(of: "2.1 Domingo-Ferrer and Mateo-Sanz") == [2, 1])
    #expect(NumberedSectionTitles.number(of: "10 CONCLUSION AND FUTURE WORK") == [10])
    for text in ["1. Total income", "2 0.129 0.091 0.000", "3 million records were masked", "2.1.4 Deeper Levels",
                 "0 Preface", "(2.1) Equation", "Table 2.1 Results", "123 Main Street", "4 Aa",
                 "7 " + String(repeating: "Long ", count: 30)] {
        #expect(NumberedSectionTitles.number(of: text) == nil, "\(text)")
    }
    // A bold body line with no number is no numbered title however it stands.
    #expect(title(stack([prose, "Rank Swapping", prose], gaps: [1: 12, 2: 6])) == nil)
    // A title that ends a sentence is a sentence.
    #expect(title(stack([prose, "3 Methods.", prose], gaps: [1: 12, 2: 6])) == nil)
}
