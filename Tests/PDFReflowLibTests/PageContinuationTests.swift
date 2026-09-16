import Foundation
import Testing
@testable import PDFReflowLib

// Paragraphs continue across source pages past figures, columns, tags and page folios, and a
// folio never absorbs the continuation (#45). Source pages come from checksum-pinned corpus
// documents; every expected phrase was read against the rendered page, not converter output.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"
private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"
private let replaySHA256 = "1e8172e4a347bdf6722dacc38755f6fb3299866336b8153f51b2c13f3ac6109a"
private let reportSHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

/// The pipeline's reconstruction pass over already-stripped pages: preserved regions from the
/// page's graphics and formulas, per-page blocks, then the cross-page join.
private func reconstruct(_ pages: [PageContent]) -> [ReflowBlock] {
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    var previous: PageContent?
    var previousRegions: [CGRect] = []
    for page in pages {
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous,
            previousImages: previousRegions, to: &blocks, vocabulary: [], warnings: &warnings)
        previous = page
        previousRegions = regions
    }
    return blocks
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
}

private func joined(_ blocks: [ReflowBlock], _ phrase: String) -> ReflowBlock? {
    blocks.first { if case .paragraph = $0.content { return $0.text.contains(phrase) } else { return false } }
}

/// The public pipeline removes running headers before reconstruction; fixtures keep every line.
private func sourcePage(_ name: String, sha256: String, dropping furniture: [String] = []) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256)
    var page = fixture.content()
    for line in furniture { #expect(page.lines.contains { $0.text == line }, "missing \(line)") }
    page.lines.removeAll { furniture.contains($0.text) }
    return page
}

@Test func faaColumnParagraphContinuesBelowTheFigureAtTheHeadOfTheNextPage() throws {
    // Page 24 ends its right column mid-sentence; page 25's left column opens with the AIM cover
    // figure and its caption before the continuation. Both pages keep their printed folios.
    let first = try sourcePage("faa-24", sha256: faaSHA256)
    let second = try sourcePage("faa-25", sha256: faaSHA256)
    #expect(first.lines.contains { $0.text == "1-9" } && second.lines.contains { $0.text == "1-10" })
    let blocks = reconstruct([first, second])
    let paragraph = try #require(joined(blocks,
        "such as health and medical facts, flight safety, a pilot/controller glossary of terms used in the system"))
    #expect(paragraph.page == 24 && paragraph.sourcePages == [25])
    #expect(blocks.contains { $0.content == .sourcePage(24) } && !blocks.contains { $0.content == .sourcePage(25) })
    // The folio stays a separate block on its page; the figure and caption follow the paragraph.
    let folio = try #require(blocks.firstIndex { $0.text == "1-9" })
    let index = try #require(blocks.firstIndex { $0 == paragraph })
    #expect(folio < index && blocks[folio].page == 24)
    #expect(blocks[(index + 1)...].contains { if case .image = $0.content { return $0.page == 25 } else { return false } })
    // The AIM cover and its caption are preserved as one region; the text below the caption is the join.
    #expect(!paragraphs(blocks).contains { $0.contains("Aeronautical Information Manual. safety, a pilot") })
    #expect(paragraphs(blocks).contains { $0.hasPrefix("Order forms are provided at the beginning of the manual") })
}

@Test func fedParagraphContinuesPastAFullWidthFigureAtTheFootOfThePage() throws {
    let first = try sourcePage("fed-11", sha256: fedSHA256, dropping: ["Overview of the Federal Reserve System 3"])
    let second = try sourcePage("fed-12", sha256: fedSHA256, dropping: ["4 The Fed Explained: What the Central Bank Does"])
    let blocks = reconstruct([first, second])
    let paragraph = try #require(joined(blocks,
        "the effective conduct of monetary policy began to require increased collaboration and coordination"))
    #expect(paragraph.page == 11 && paragraph.sourcePages == [12])
    // Figure 1.3 keeps page 11 and precedes the paragraph it followed in print.
    let index = try #require(blocks.firstIndex { $0 == paragraph })
    let figures = blocks[..<index].filter { if case .image = $0.content { return true } else { return false } }
    #expect(!figures.isEmpty && figures.allSatisfy { $0.page == 11 })
    #expect(!blocks[(index + 1)...].contains { $0.page == 11 })
    // The rest of page 12 keeps its own paragraphs.
    #expect(paragraphs(blocks).contains { $0.hasPrefix("The Depository Institutions Deregulation and Monetary Control Act of 1980") })
}

@Test func replayRightColumnContinuesInTheNextPageLeftColumn() throws {
    let first = try sourcePage("replay-1", sha256: replaySHA256)
    let second = try sourcePage("replay-2", sha256: replaySHA256,
        dropping: ["Conference’17, July 2017, Washington, DC, USA", "Ishaan Lagwankar and Sandeep S Kulkarni"])
    let blocks = reconstruct([first, second])
    let paragraph = try #require(joined(blocks, "when we replay the log, it is possible that the white LED event could be replayed"))
    #expect(paragraph.page == 1 && paragraph.sourcePages == [2])
    // The left column of page 1 ended earlier and stays where it was; page 2's left column follows the join.
    #expect(paragraphs(blocks).contains { $0.hasSuffix("computing them would be even higher.") })
    #expect(paragraph.text.contains("green LED event. This is also unacceptable."))
    #expect(paragraphs(blocks).contains { $0.contains("Hybrid logical clocks (HLC)") })
}

@Test func chapterOpeningFolioNeverAbsorbsTheContinuation() throws {
    // Page 126 opens chapter 4 with a bottom folio `108` that furniture removal keeps; the body
    // paragraph above it continues on page 127 after that page's running header.
    let first = try sourcePage("911-126", sha256: reportSHA256)
    let second = try sourcePage("911-127", sha256: reportSHA256,
        dropping: ["RESPONSES TO AL QAEDA’S INITIAL ASSAULTS", "109"])
    #expect(first.lines.contains { $0.text == "108" })
    let blocks = reconstruct([first, second])
    let paragraph = try #require(joined(blocks, "detected his money in aid to theYemeni terrorists who set a bomb in an attempt to kill"))
    #expect(paragraph.page == 126 && paragraph.sourcePages == [127])
    let folio = try #require(blocks.first { $0.text == "108" })
    #expect(folio.page == 126 && folio.sourcePages.isEmpty)
    #expect(!paragraphs(blocks).contains { $0.hasPrefix("108 ") })
    let index = try #require(blocks.firstIndex { $0 == paragraph })
    #expect(blocks.firstIndex { $0 == folio }! < index)
    #expect(paragraphs(blocks).contains { $0.contains("In 1996, the CIA set up a special unit") })
}

// Synthetic layouts: a 460-point justified column on a US Letter page.
private let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

private func column(_ texts: [String], x: Double = 60, top: Double, pitch: Double = 14, size: Double = 12,
                    widths: [Double]? = nil) -> [TextLine] {
    texts.enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: x, y: top - Double(index) * pitch, width: widths?[index] ?? 460, height: size),
                 fontSize: size)
    }
}

private let foot = [
    "The committee reviewed the position paper prepared during the previous session and",
    "recorded the objections raised by every delegate before the vote was called, noting",
    "that the earlier draft had been circulated without the appendix that described the",
    "sampling method in detail, and after a short adjournment the chair proposed that the",
]
private let head = [
    "report be accepted without amendment provided that the appendix was attached to the",
    "final version and circulated again to every member of the committee before the end",
    "of the month.",
]

private func continuationPages(firstExtra: [TextLine] = [], firstGraphics: [CGRect] = [],
                               secondExtra: [TextLine] = [], secondHead: [String] = head,
                               headTop: Double = 740) -> [PageContent] {
    [PageContent(number: 1, bounds: letter, lines: column(foot, top: 160) + firstExtra, graphics: firstGraphics),
     PageContent(number: 2, bounds: letter, lines: column(secondHead, top: headTop, widths: [460, 460, 90]) + secondExtra, graphics: [])]
}

@Test func figureLabelsAndCaptionBetweenTheHalvesDoNotBlockTheJoin() {
    let figure = CGRect(x: 60, y: 60, width: 460, height: 40)
    let label = TextLine(text: "Sample size", rect: CGRect(x: 200, y: 75, width: 50, height: 7), fontSize: 7)
    let caption = TextLine(text: "Figure 3. Objections recorded by delegation.", rect: CGRect(x: 60, y: 44, width: 220, height: 9), fontSize: 9)
    let blocks = reconstruct(continuationPages(firstExtra: [label, caption], firstGraphics: [figure]))
    let paragraph = joined(blocks, "the chair proposed that the report be accepted without amendment")
    #expect(paragraph?.sourcePages == [2])
    #expect(paragraphs(blocks).count == 2)
    // The figure and its caption stay on page 1, ahead of the paragraph they followed.
    let index = blocks.firstIndex { $0 == paragraph } ?? -1
    #expect(blocks[..<max(0, index)].contains { if case .image = $0.content { return $0.page == 1 } else { return false } })
    #expect(blocks[..<max(0, index)].contains { $0.text.hasPrefix("Figure 3.") && $0.page == 1 })
    #expect(!blocks[(index + 1)...].contains { $0.page == 1 })
}

@Test func swallowedProseBelowTheLastLineRefusesTheJoin() {
    // A preserved region that ate two body lines below the paragraph: joining would skip them.
    let swallowed = column(["appendix circulated to the delegates on the second day of the session and",
                            "adopted after a brief discussion of the sampling method described in the"], top: 88)
    let region = CGRect(x: 60, y: 74, width: 460, height: 30)
    let blocks = reconstruct(continuationPages(firstExtra: swallowed, firstGraphics: [region]))
    #expect(joined(blocks, "proposed that the report be accepted") == nil)
    #expect(blocks.contains { $0.content == .sourcePage(2) })
    // Without the region the same lines simply extend the paragraph and the join proceeds.
    let control = reconstruct(continuationPages(firstExtra: swallowed))
    #expect(joined(control, "described in the report be accepted") != nil)
}

@Test func shortHeadingLineAndListItemAtTheFootStaySeparate() {
    // A run-in heading in body type does not fill the measure.
    var heading = continuationPages()
    heading[0].lines = column(foot.map { $0 + "." }, top: 160)
        + [TextLine(text: "Moving to Departure Positions", rect: CGRect(x: 60, y: 84, width: 150, height: 12), fontSize: 12)]
    let blocks = reconstruct(heading)
    #expect(joined(blocks, "Departure Positions report be accepted") == nil)
    #expect(paragraphs(blocks).contains("Moving to Departure Positions"))
    // A numbered item that fills the line is preformatted and never a join anchor.
    var list = continuationPages()
    list[0].lines = column(["1. The committee reviewed the position paper prepared during the session and"], top: 90)
    #expect(joined(reconstruct(list), "session and report be accepted") == nil)
}

@Test func retainedRunningHeaderRefusesButAShortFinalLineJoins() {
    // `xiv PREFACE` starts lowercase, sits in the top band and is separated from the body below it.
    let header = TextLine(text: "xiv PREFACE", rect: CGRect(x: 60, y: 752, width: 100, height: 10), fontSize: 10)
    let pages = continuationPages(secondExtra: [header], headTop: 700)
    let blocks = reconstruct(pages)
    #expect(joined(blocks, "proposed that the xiv PREFACE") == nil)
    #expect(joined(blocks, "proposed that the report be accepted") == nil)
    // A paragraph whose last line is short and at the very top of the page still continues.
    let short = continuationPages(secondHead: ["final report.", "Another paragraph follows after a gap and is not part of the join."],
                                  headTop: 752)
    var pagesWithGap = short
    pagesWithGap[1].lines[1].rect.origin.y = 720
    pagesWithGap[1].lines[0].rect.size.width = 70
    let joinedShort = reconstruct(pagesWithGap)
    #expect(joined(joinedShort, "the chair proposed that the final report.") != nil)
    #expect(paragraphs(joinedShort).contains { $0.hasPrefix("Another paragraph follows") })
}

@Test func lineEndingHyphenAndRaggedColumnsStillJoin() {
    // A hyphenated last line is continuation evidence even in a ragged column.
    var hyphenated = continuationPages()
    hyphenated[0].lines = column(foot.dropLast() + ["sampling method in detail, and after a short adjournment the chair pro-"],
                                 top: 160, widths: [430, 452, 418, 440])
    #expect(joined(reconstruct(hyphenated), "the chair pro-report be accepted") != nil)
    // A ragged column accepts a last line that fills three quarters of its measure.
    var ragged = continuationPages()
    ragged[0].lines = column(foot, top: 160, widths: [440, 455, 420, 400])
    #expect(joined(reconstruct(ragged), "proposed that the report be accepted") != nil)
    ragged[0].lines = column(foot, top: 160, widths: [440, 455, 420, 300])
    #expect(joined(reconstruct(ragged), "proposed that the report be accepted") == nil)
}

@Test func superscriptNoteMarkerDoesNotHideTerminalPunctuation() {
    var noted = continuationPages()
    let ending = InlineText(elements: [.text("sampling method in detail, and the chair adjourned the session.", []),
                                       .text("94", .superscript)])
    noted[0].lines[3] = TextLine(content: ending, rect: noted[0].lines[3].rect, fontSize: 12)
    #expect(joined(reconstruct(noted), "adjourned the session.94 report be accepted") == nil)
    // The same marker after an unfinished sentence keeps the join.
    let open = InlineText(elements: [.text("sampling method in detail, and after a short adjournment the chair", []),
                                     .text("94", .superscript)])
    noted[0].lines[3] = TextLine(content: open, rect: noted[0].lines[3].rect, fontSize: 12)
    #expect(joined(reconstruct(noted), "the chair94 report be accepted") != nil)
}

@Test func oneUntaggedSideKeepsTheHeuristicWhileTwoIdentitiesRefuse() {
    let pages = continuationPages()
    var warnings: [ConversionWarning] = []
    for (left, right, joins) in [(7, nil, true), (nil, 9, true), (7, 7, true), (7, 8, false)] as [(Int?, Int?, Bool)] {
        var blocks = [ReflowBlock(content: .sourcePage(1), page: 1),
                      ReflowBlock(content: .paragraph(InlineText(foot.joined(separator: " "))), structureGroup: left, page: 1)]
        LayoutReconstructor.appendPage(
            [ReflowBlock(content: .paragraph(InlineText(head.joined(separator: " "))), structureGroup: right, page: 2)],
            page: pages[1], previousPage: pages[0], to: &blocks, vocabulary: [], warnings: &warnings)
        #expect((blocks.count == 2) == joins, "groups \(String(describing: left))/\(String(describing: right))")
    }
}

/// One paragraph flowing across a page whose source tags each page's fragment as its own `P`
/// (#67). The wrap breaks a word, so the join is visible in the text as well as the block count.
private func taggedFragmentPages(secondRole: Int, secondMarker: String = "") -> [PageContent] {
    let tail = ["The committee reviewed the position paper prepared during the previous session",
                "and recorded every objection raised before the vote, noting the sampling condi-"]
    let start = [secondMarker + "tions, and the actions of the delegates, that the appendix described",
                 "in detail before the chair adjourned the session."]
    var first = column(tail, top: 160)
    for index in first.indices {
        first[index].structure = TextStructure(group: 11, order: index + 1, headingLevel: 0, lineCount: tail.count)
    }
    var second = column(start, top: 740, widths: [460, 300])
    for index in second.indices {
        second[index].structure = TextStructure(group: 12, order: index + 3, headingLevel: secondRole,
                                                lineCount: start.count)
    }
    return [PageContent(number: 1, bounds: letter, lines: first, graphics: []),
            PageContent(number: 2, bounds: letter, lines: second, graphics: [])]
}

@Test func twoParagraphIdentitiesFallThroughToGeometryWhileOtherRolesStaySeparate() {
    // Two different `P` groups are not the author's evidence of separation; the geometric rule
    // decides, and repairs the wrapped word.
    var warnings: [ConversionWarning] = []
    var blocks: [ReflowBlock] = []
    var previous: PageContent?
    for page in taggedFragmentPages(secondRole: 0) {
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: ["conditions"],
                                                    warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: previous, to: &blocks,
                                       vocabulary: ["conditions"], warnings: &warnings)
        previous = page
    }
    #expect(paragraphs(blocks).count == 1)
    #expect(joined(blocks, "noting the sampling conditions, and the actions of the delegates") != nil)

    // A validated heading on the far side keeps its own block, whatever the geometry says.
    for (role, marker) in [(3, ""), (0, "(2) ")] {
        var other: [ReflowBlock] = []
        var last: PageContent?
        for page in taggedFragmentPages(secondRole: role, secondMarker: marker) {
            let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: ["conditions"],
                                                        warnings: &warnings)
            LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: last, to: &other,
                                           vocabulary: ["conditions"], warnings: &warnings)
            last = page
        }
        #expect(joined(other, "noting the sampling conditions, and the actions") == nil, "role \(role)\(marker)")
    }
}

@Test func proseInAnotherColumnRefusesAColumnAnchorThatIsNotLast() {
    // The left column ends mid-sentence but the right column still carries prose below and
    // beside it, so the page has not ended there; the right column's own end joins instead.
    var pages = continuationPages()
    let left = column(foot, top: 160, widths: [237, 237, 237, 237])
    let right = column(["opening the right column with a sentence that", "ends here."], x: 330, top: 160,
                       widths: [237, 120])
    pages[0].lines = left + right
    let blocks = reconstruct(pages)
    #expect(joined(blocks, "the chair proposed that the report be accepted") == nil)
    #expect(blocks.contains { $0.content == .sourcePage(2) })
}
