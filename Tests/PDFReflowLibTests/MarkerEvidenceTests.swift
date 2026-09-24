import CoreGraphics
import Testing
@testable import PDFReflowLib

/// What a point after a line's first token means is the page's to say, not the token's (#171).
///
/// #39 reads a marker-leading line that arrives *after* an open paragraph and decides whether it
/// wraps into it. The line that arrives with nothing running on it had no such reading: every one
/// of them opened a preformatted item, so a name's initial, a page reference and a citation came
/// out as list markers. The evidence these tests state is the page's own — how many of the lines
/// it stands on that edge it marks — and, for the rows of a table it sets without rules, whether
/// the numbers it ends its rows with are a column or a coincidence.
private func reconstruct(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { return $0.text } else { return nil } }
}

/// The 9/11 report's staff pages stand twenty-five names on one edge and open four of them with
/// an initial. A list marks its items; a column that marks four lines in twenty-five is a column
/// of names, and `T. Graham Giusti` is one of them.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func anInitialInAColumnOfNamesIsNoMarker() throws {
    let fixture = try SourceLayoutFixture.load("911-14")
    #expect(fixture.sourceSHA256 == report911SHA256)
    let page = fixture.content()
    let giusti = try #require(page.lines.first { $0.text == "T. Graham Giusti" })
    let typography = PageTypography(page: page)
    let column = LayoutReconstructor.markerColumn(of: giusti, in: page.lines, body: typography.body)
    #expect(column.setsAList == false)
    // The page's own evidence: the edge carries far more names than markers.
    let edge = page.lines.filter {
        Int($0.fontSize.rounded()) == Int(giusti.fontSize.rounded())
            && abs($0.rect.minX - giusti.rect.minX) < typography.body * 0.5
    }
    #expect(edge.count >= MarkerColumn.shortestUnmarkedRun)
    #expect(edge.count { LayoutReconstructor.isList($0.text) } * 4 <= edge.count)

    let blocks = reconstruct(page)
    #expect(preformatted(blocks).isEmpty)
    #expect(paragraphs(blocks).contains { $0.contains("T. Graham Giusti Security Officer") })
    for name in ["L. Christine Healey", "C. Michael Hurley", "R. William Johnstone"] {
        #expect(paragraphs(blocks).contains { $0.contains(name) })
    }
}

/// The FAA handbook's page 18 opens a paragraph on `P. E. Fansler,` and wraps two more lines under
/// it on the column's own edge. The opening line kept its own preformatted block and the two wraps
/// were stranded in a paragraph of their own; they are one paragraph.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func anInitialOpeningAParagraphTakesTheWrapsOnItsOwnEdge() throws {
    let fixture = try SourceLayoutFixture.load("faa-18")
    #expect(fixture.sourceSHA256 == faaSHA256)
    let blocks = reconstruct(fixture.content())
    #expect(preformatted(blocks).isEmpty)
    let opening = try #require(paragraphs(blocks).first { $0.hasPrefix("P. E. Fansler,") })
    #expect(opening.contains("approached Tom Benoist of the Benoist Aircraft Company"))
    #expect(opening.hasSuffix("about starting a flight route from St."))
}

/// Loper Bright's page 64 opens on `U. S. 134 (1944),`, the rest of a sentence the page before
/// began, and then indents `Echoing themes` to open the next paragraph. The citation is not an
/// item; neither is it the same paragraph as what follows it, and a first-line indent of one body
/// is inside the one and a half bodies the ordinary column test allows, so the paragraph a line
/// like this opens takes only the wraps standing on its own edge.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func aCitationOpeningAPageIsNeitherAnItemNorTheParagraphBelowIt() throws {
    let fixture = try SourceLayoutFixture.load("loper-64")
    #expect(fixture.sourceSHA256 == loperSHA256)
    let blocks = reconstruct(fixture.content())
    #expect(preformatted(blocks).isEmpty)
    #expect(paragraphs(blocks).contains("U. S. 134 (1944), the Court returned to its time-worn path."))
    #expect(paragraphs(blocks).contains { $0.hasPrefix("Echoing themes that had run throughout our law") })
}

/// The same source sentence continues across its page break: the reporter volume is the final
/// token on page 63 and the uppercase reporter abbreviation opens page 64. The three running-head
/// lines on each page are removed as the document furniture pass does before reconstruction.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func aReporterCitationContinuesAcrossThePageBreak() throws {
    let first = try SourceLayoutFixture.load("loper-63")
    let second = try SourceLayoutFixture.load("loper-64")
    #expect(first.sourceSHA256 == loperSHA256)
    #expect(second.sourceSHA256 == loperSHA256)
    var start = first.content(), next = second.content()
    start.lines.removeAll { $0.rect.minY > 640 }
    next.lines.removeAll { $0.rect.minY > 640 }
    let startBlocks = reconstruct(start), nextBlocks = reconstruct(next)
    #expect(paragraphs(startBlocks).last?.hasSuffix("Skidmore v. Swift & Co., 323") == true)
    #expect(paragraphs(nextBlocks).first == "U. S. 134 (1944), the Court returned to its time-worn path.")

    var blocks: [ReflowBlock] = [], warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(nextBlocks, page: next, previousPage: start, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    #expect(paragraphs(blocks).contains {
        $0.contains("Skidmore v. Swift & Co., 323 U. S. 134 (1944), the Court returned")
    })
    #expect(!blocks.contains { $0.content == .sourcePage(64) })
    #expect(paragraphs(blocks).contains { $0.hasPrefix("Echoing themes that had run") })
}

/// The FAA handbook's acknowledgments name a chapter at the end of every credit and set each
/// credit on its own line, so every row of that run ends in a digit and three of its twenty happen
/// to end within half a body of one another. Three rows out of twenty are not a column of numbers,
/// and nothing on that page is a table: the credits are prose, and the two that wrap keep their
/// second lines.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func creditsNamingTheirChapterAreNoTable() throws {
    let fixture = try SourceLayoutFixture.load("faa-5")
    #expect(fixture.sourceSHA256 == faaSHA256)
    let page = fixture.content()
    #expect(TableRegionDetector.rowBlocks(in: page.lines, body: PageTypography(page: page).body).isEmpty)
    let blocks = reconstruct(page)
    #expect(preformatted(blocks).isEmpty)
    let text = paragraphs(blocks).joined(separator: " ")
    #expect(text.contains("M. van Leeuwen (www.zap16.com) for image of Piaggio P-180 (Chapter 6)"))
    #expect(text.contains("for EMAS imagery and EMASMAX technical digrams (Chapter 14)"))
    #expect(text.contains("and EMAS arrested aircraft (Chapter 14)"))
}

/// The control the rule above must not break: a page that really does set a table without rules
/// keeps its printed rows. The 9/11 report's list of illustrations stands a page reference in one
/// column and its caption in another, and the report's flight timelines stand a time against each
/// entry; both are read from a cell the extractor kept apart, which this change does not touch.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func theRowsOfATableThePageSetsAreKept() throws {
    let illustrations = try SourceLayoutFixture.load("911-9")
    #expect(illustrations.sourceSHA256 == report911SHA256)
    let rows = preformatted(reconstruct(illustrations.content()))
    #expect(rows.count == 14)
    #expect(rows.first == "p. 15 FAA Air Traffic Control Centers")
    #expect(rows.last == "p. 413 Unity of effort in managing intelligence")

    let timeline = try SourceLayoutFixture.load("911-50")
    let entries = preformatted(reconstruct(timeline.content()))
    #expect(entries.contains("8:19 Flight attendant notifies AA of hijacking"))
    #expect(entries.contains("8:46:40 AA 11 crashes into 1 WTC (North Tower)"))

    // A column of numbers the page really does set: the USGS commodity summary's statistics, and
    // the IRS publication's earned-income table, both of which end row after row on one edge.
    for name in ["usgs-1", "p596-24"] {
        let fixture = try SourceLayoutFixture.load(name)
        let page = fixture.content()
        #expect(!TableRegionDetector.rowBlocks(in: page.lines, body: PageTypography(page: page).body).isEmpty)
    }
}

private let report911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"
private let loperSHA256 = "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e"
