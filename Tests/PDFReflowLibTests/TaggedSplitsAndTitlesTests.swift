import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #89: once FAA pages with text-free forms apply their tags (#75), a paragraph the source tags in
// two pieces must still read as one paragraph where the page sets it as one, including where one
// piece's group falls back beside a figure. #90: tagged run-in titles are headings placed above
// their paragraphs, and lettered appendix folios are furniture. The `faa-N-tagged` fixtures carry
// the tags the pipeline applies to each line; expected text was read against rendered pages.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func faa(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("faa-\(number)-tagged")
    #expect(fixture.sourceSHA256 == faaSHA256)
    return fixture.styledContent()
}

/// The FAA handbook's label styles, counted from the fixture pages' own evidence as the pipeline
/// counts them across the book: 10-point bold (pages 54, 127, 360, 416) and 11-point bold italic
/// (45, 54, 114, 153). The 12-point bold section style appears on two of these pages; the book
/// repeats it throughout (HeadingPlacementTests counts it from pages 33, 49 and 201).
private func faaLabelStyles() throws -> Set<LayoutReconstructor.LabelStyle> {
    var pages: [LayoutReconstructor.LabelStyle: Int] = [:]
    for number in [27, 45, 54, 55, 72, 96, 114, 127, 152, 153, 360, 416, 429] {
        for style in LayoutReconstructor.labelEvidence(on: try faa(number)) { pages[style, default: 0] += 1 }
    }
    let section = TextLine(content: InlineText("Human Factors", style: .bold), rect: .init(x: 0, y: 0, width: 90, height: 16), fontSize: 12)
    return LayoutReconstructor.labelStyles(from: pages).union([LayoutReconstructor.LabelStyle(section, body: 10)])
}

/// A fixture page without its foot folio (`2-15`), as furniture removal hands it to layout.
private func withoutFolio(_ page: PageContent) -> PageContent {
    var copy = page
    copy.lines.removeAll { $0.rect.maxY < page.bounds.height * 0.07 && $0.text.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil }
    return copy
}

/// The pipeline's reconstruction pass: preserved regions, per-page blocks, cross-page joins.
/// `crops: false` reflows a page whose full-page background the pipeline keeps as a reference
/// image instead (FAA chapter openers such as page 72).
private func reconstruct(_ pages: [PageContent], labelStyles: Set<LayoutReconstructor.LabelStyle> = [],
                         headingStyles: Set<LayoutReconstructor.LabelStyle> = [], crops: Bool = true) -> [ReflowBlock] {
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    var previous: PageContent?
    var previousRegions: [CGRect] = []
    for page in pages {
        let regions = crops ? LayoutReconstructor.graphicsWithLabels(page) : []
        let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings,
                                                    labelStyles: labelStyles, headingStyles: headingStyles)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous,
            previousImages: previousRegions, to: &blocks, vocabulary: [], warnings: &warnings)
        previous = page
        previousRegions = regions
    }
    return blocks
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

/// One paragraph holds both phrases, in order.
private func joined(_ blocks: [ReflowBlock], _ end: String, _ next: String) -> Bool {
    paragraphs(blocks).contains { $0.range(of: end + " " + next) != nil }
}

/// Two paragraphs: one ends with `end`, a later one opens with `next`.
private func separate(_ blocks: [ReflowBlock], _ end: String, _ next: String) -> Bool {
    let texts = paragraphs(blocks)
    guard let upper = texts.firstIndex(where: { $0.hasSuffix(end) }) else { return false }
    return texts[(upper + 1)...].contains { $0.hasPrefix(next) }
}

// MARK: - Paragraphs tagged in pieces (#89)

@Test func aParagraphGroupContinuesTheUntaggedParagraphThatWrapsOntoIt() throws {
    // FAA page 114: `…nose-up effect of the horizontal tail surface.` closes a group that falls
    // back around figures 5-26 and 5-27; `Conclusion: with CG forward…` opens the next group at
    // ordinary leading on the same edge. Page 127: `…there is maximum thrust.` / `After liftoff,`.
    let page114 = reconstruct([try faa(114)])
    #expect(joined(page114, "nose-up effect of the horizontal tail surface.", "Conclusion: with CG forward"))
    // Controls on the same pages: paragraphs the source separates with space stay apart.
    #expect(separate(page114, "return to a safe flying attitude.", "The following is a simple demonstration"))
    let page127 = reconstruct([try faa(127)])
    #expect(joined(page127, "there is maximum thrust.", "After liftoff, as the speed"))
    #expect(separate(page127, "and keeps thrust at a maximum.", "After the takeoff climb is established"))
}

@Test func anUntaggedLineContinuesTheParagraphGroupThatWrapsOntoIt() throws {
    // FAA page 360: the group ending `…see and avoid other aircraft. [Figure 14-44]` wraps onto
    // `In addition to basic radar service, terminal radar service`, whose group crosses the figure.
    let blocks = reconstruct([try faa(360)])
    #expect(joined(blocks, "[Figure 14-44]", "In addition to basic radar service"))
    #expect(separate(blocks, "if known, are given.", "An example would be:"))
}

@Test func aJustifiedColumnIsWrapEvidenceWhereItsOnlySpaceSetsOffAHeading() throws {
    // FAA page 96: the figure crop takes the column's spaced paragraphs, leaving space only above
    // `A Third Dimension`; the column is justified, and `Manufacturers have developed…` continues.
    let blocks = reconstruct([try faa(96)])
    #expect(joined(blocks, "affected portion of the airfoil.", "Manufacturers have developed"))
}

@Test func codedReportsListsAndTableRowsStayApartAtTheirTagBoundaries() throws {
    // FAA page 462: acronyms at even leading, a ragged column whose longest entries fill it.
    let acronyms = reconstruct([try faa(462)])
    #expect(paragraphs(acronyms).contains("ARRA—American Recovery and Reinvestment Act of 2009"))
    #expect(paragraphs(acronyms).contains("ARSA—airport service radar area"))
    // FAA page 319: a TAF's change groups are separate lines of the report.
    let taf = reconstruct([try faa(319)])
    #expect(paragraphs(taf).contains("FM1500 16015G25KT P6SM SCT040 BKN250"))
    #expect(paragraphs(taf).contains { $0.hasPrefix("FM120400 1408KT") })
    // FAA page 416: NDB class rows fill the measure only because their numbers are right-aligned.
    let rows = reconstruct([try faa(416)])
    #expect(!paragraphs(rows).contains { $0.contains("Under 25 15 MH") })
}

// MARK: - Tagged titles (#90)

@Test func taggedTitlesInTheBooksBoldStylesAreHeadingsWhereverTheyStand() throws {
    let styles = try faaLabelStyles()
    // 10-point bold, 11-point bold italic and 12-point bold, each on at least three fixture pages.
    for (size, text) in [(10.0, "Risk"), (11.0, "Assessing Risk"), (12.0, "Human Factors")] {
        let line = TextLine(content: InlineText(text, style: .bold), rect: .init(x: 0, y: 0, width: 80, height: 12), fontSize: size)
        #expect(styles.contains(LayoutReconstructor.LabelStyle(line, body: 10)), "\(size)")
    }
    // FAA page 27 stacks two titles, each its own `P`: two headings, not one.
    let page27 = reconstruct([try faa(27)], labelStyles: styles)
    #expect(headings(page27).starts(with: ["Pilot and Aeronautical Information", "Notices to Airmen (NOTAMs)"]))
    // Reproducer: without the book's styles the page's own label test leaves both paragraphs.
    let alone = reconstruct([try faa(27)])
    #expect(!headings(alone).contains("Pilot and Aeronautical Information"))
    #expect(paragraphs(alone).contains("Pilot and Aeronautical Information"))
    // FAA page 72: `Introduction` directly under the chapter title opens the chapter's text.
    let opener = try faa(72)
    let page72 = reconstruct([opener], labelStyles: styles, headingStyles: LayoutReconstructor.headingEvidence(on: opener),
                             crops: false)
    #expect(headings(page72) == ["Chapter 3", "Aircraft Construction", "Introduction"])
    #expect(page72.drop { $0.text != "Introduction" }.dropFirst().first?.text.hasPrefix("An aircraft is a device") == true)
    // FAA page 429: an 11-point bold italic title over a 10-point italic one.
    let page429 = reconstruct([try faa(429)], labelStyles: styles)
    #expect(headings(page429).starts(with: ["Vestibular Illusions", "The Leans", "Coriolis Illusion"]))
}

@Test func italicTitlesOverTheirParagraphsAreHeadings() throws {
    // FAA page 45: `Likelihood of an Event` and `Severity of an Event`, 10-point italic, each over
    // its paragraph. Page 27's `NOTAM (D) Information` likewise.
    let page45 = reconstruct([try faa(45)])
    #expect(headings(page45).contains("Likelihood of an Event"))
    #expect(headings(page45).contains("Severity of an Event"))
    #expect(headings(reconstruct([try faa(27)])).contains("NOTAM (D) Information"))
}

@Test func titlesThatHeadAContinuedParagraphMoveWithItPastTheFigure() throws {
    let styles = try faaLabelStyles()
    // FAA pages 54–55: the two-line `PAVE Checklist: …` opens a paragraph that continues on page 55
    // below figure 2-10; page 152–153: `Coupled Ailerons and Rudder` above figure 6-7 (#63).
    for (pages, title, opening) in [([54, 55], "PAVE Checklist: Identify Hazards and Personal Minimums", "In the first step"),
                                    ([152, 153], "Coupled Ailerons and Rudder", "Coupled ailerons and rudder are linked")] {
        let blocks = reconstruct(try pages.map { withoutFolio(try faa($0)) }, labelStyles: styles)
        let index = try #require(blocks.firstIndex { $0.text == title })
        #expect(headings(blocks).contains(title))
        #expect(blocks[index + 1].text.hasPrefix(opening), "\(title)")
    }
}

@Test func contentsEntriesTableTitlesAndHeaderRowsAreNotTitles() throws {
    let styles = try faaLabelStyles()
    // FAA page 6: contents chapter labels over leader entries with chapter-prefixed folios.
    let contents = reconstruct([try faa(6)], labelStyles: styles)
    #expect(!headings(contents).contains { $0.hasPrefix("Chapter") || $0.contains("....") })
    // FAA page 15: `Appendix A` over an entry that wraps before its leader.
    let appendices = headings(reconstruct([try faa(15)], labelStyles: styles))
    #expect(!appendices.contains { $0.hasPrefix("Appendix") || $0.contains("....") })
    // FAA page 416: a centred table title and a bold header row spread over the table.
    let table = headings(reconstruct([try faa(416)], labelStyles: styles))
    #expect(!table.contains("NONDIRECTIONAL RADIO BEACON (NDB)"))
    #expect(!table.contains { $0.hasPrefix("Class") })
}

/// One tagged italic line over a tagged body paragraph, on a page of justified prose.
private func italicTitlePage(_ title: String, italic: Bool = true, beneath: String = "Likelihood is nothing more than taking a situation and",
                             beneathX: CGFloat = 36) -> PageContent {
    func line(_ text: String, x: CGFloat = 36, y: CGFloat, width: CGFloat = 237, style: TextStyle = [], group: Int, count: Int = 1) -> TextLine {
        var line = TextLine(content: InlineText(text, style: style), rect: CGRect(x: x, y: y, width: width, height: 11.5), fontSize: 10)
        line.structure = TextStructure(group: group, order: group, headingLevel: 0, lineCount: count)
        return line
    }
    var lines = (0..<4).map { line("occurring and the consequence of that event, which the pilot then", y: 260 - CGFloat($0) * 12.5, group: 1, count: 4) }
    lines.append(line(title, y: 200, width: 90, style: italic ? .italic : [], group: 2))
    lines.append(line(beneath, x: beneathX, y: 185.5, group: 3, count: 3))
    lines += (1..<3).map { line("determining the probability of its occurrence in the flight ahead", y: 185.5 - CGFloat($0) * 12.5, group: 3, count: 3) }
    return PageContent(number: 45, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func italicTitleRuleNeedsTitleCaseNoClosingPunctuationAndABodyParagraphBeneath() {
    func isTitle(_ page: PageContent) -> Bool {
        var warnings: [ConversionWarning] = []
        return !headings(LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)).isEmpty
    }
    #expect(isTitle(italicTitlePage("Likelihood of an Event")))
    // Controls: not italic, a sentence, not title case, and a list line or an indent beneath.
    #expect(!isTitle(italicTitlePage("Likelihood of an Event", italic: false)))
    #expect(!isTitle(italicTitlePage("Likelihood of an Event.")))
    #expect(!isTitle(italicTitlePage("Likelihood of something")))
    #expect(!isTitle(italicTitlePage("Likelihood of an Event", beneath: "• What is the current ceiling and visibility?")))
    #expect(!isTitle(italicTitlePage("Likelihood of an Event", beneathX: 54)))
}

// MARK: - Lettered folios (#90)

/// FAA appendix C (pages 473–476): a 10-point foot folio `C-N`, alternating sides, over an 8-point
/// figure caption, geometry as extracted from each page.
private func appendixPage(_ number: Int, folio: String, x: CGFloat) -> PageContent {
    PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
        TextLine(text: folio, rect: CGRect(x: x, y: 33.7, width: 16.1, height: 12.3), fontSize: 10),
        TextLine(text: "Figure \(folio). Samples and explanations of standard airport signs.",
                 rect: CGRect(x: 36, y: 203.1, width: 259.8, height: 10.8), fontSize: 8),
    ], graphics: [])
}

@Test func letteredAppendixFoliosAreFurnitureAndNeverHeadings() throws {
    var pages = [473, 474, 475, 476].map { appendixPage($0, folio: "C-\($0 - 472)", x: $0.isMultiple(of: 2) ? 36 : 541.9) }
    // The heading floor: a lettered folio in the foot band is not a heading, whatever furniture
    // removal does (page 474's `C-2` was an `h6`).
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: pages[1], images: [], vocabulary: [], warnings: &warnings)
    #expect(headings(blocks).isEmpty)
    #expect(paragraphs(blocks).contains("C-2"))
    // Furniture: the four folios keep one offset from the physical page (−472); captions stay.
    let removed = LayoutReconstructor.stripFurniture(&pages)
    #expect(removed.map(\.page) == [473, 474, 475, 476])
    #expect(pages.allSatisfy { $0.lines.count == 1 && $0.lines[0].text.hasPrefix("Figure") })
    // The captured page 476 keeps every other line.
    let source = try faa(476)
    var sourcePages = [473, 474, 475].map { appendixPage($0, folio: "C-\($0 - 472)", x: $0.isMultiple(of: 2) ? 36 : 541.9) } + [source]
    _ = LayoutReconstructor.stripFurniture(&sourcePages)
    #expect(sourcePages[3].lines.map(\.text) == source.lines.filter { $0.text != "C-4" }.map(\.text))
    // Controls: letters that break the offset, and a two-letter prefix, are no run.
    var shifted = [473, 474, 475].map { appendixPage($0, folio: "C-\($0 % 5)", x: 36) }
    #expect(LayoutReconstructor.stripFurniture(&shifted).isEmpty)
    var model = [473, 474, 475].map { appendixPage($0, folio: "AB-\($0 - 472)", x: 36) }
    #expect(LayoutReconstructor.stripFurniture(&model).isEmpty)
}

@Test func folioReadingAcceptsLetteredPartPages() {
    #expect(FurnitureDetector.folioValue("c-2").map(\.kind) == "part-c")
    #expect(FurnitureDetector.folioValue("c-2").map(\.value) == 2)
    // A part letter and a chapter number never share a run.
    #expect(FurnitureDetector.folioValue("3-2")?.kind == "chapter-3")
    for word in ["ab-2", "c-", "-2", "c-x", "é-2"] {
        #expect(FurnitureDetector.folioValue(word) == nil, "\(word) is not a folio")
    }
}
