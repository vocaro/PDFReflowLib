import CoreGraphics
import Testing
@testable import PDFReflowLib

/// The layout seams introduced by the 2026-09-19 review: a page's typography read once, a line's
/// role decided by one function, paragraphs assembled by one value, and hyphens decided by an
/// explicit context. Each rule is exercised on hand-made lines, without a page fixture.
private func line(_ text: String, x: CGFloat = 40, y: CGFloat, width: CGFloat = 300, size: CGFloat = 10,
                  monospaced: Bool = false, wraps: Bool? = nil, bold: Bool = false) -> TextLine {
    TextLine(content: InlineText(text, style: bold ? .bold : []), rect: CGRect(x: x, y: y, width: width, height: size * 1.2),
             fontSize: size, monospaced: monospaced, wraps: wraps)
}

private func page(_ lines: [TextLine], synthetic: Bool = false, recognized: Bool = false) -> PageContent {
    PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 400, height: 600), lines: lines, graphics: [],
                recognized: recognized, hasSyntheticTextStyle: synthetic)
}

/// Enough ten-point prose to establish a body: five lines, well over 200 characters.
private let prose: [TextLine] = (0..<5).map {
    line("The quick brown fox jumps over the lazy dog and keeps running across the field.", y: 500 - CGFloat($0) * 12)
}

@Test func typographyReadsThePageOnce() {
    let lines = prose + [line("Title", y: 560, size: 16)]
    let typography = PageTypography(pageLines: lines, reflowableLines: lines, documentBody: 11)
    #expect(typography.body == 10)
    #expect(typography.establishedBody == 10)
    #expect(typography.headingBody == 10)
    #expect(typography.documentFloor == 0)
    #expect(typography.headingThreshold == 12.5)

    // A page too sparse to establish a body takes the document's floor.
    let sparse = [line("Return address", y: 500, size: 9), line("www.example.org", y: 480, size: 9)]
    let bare = PageTypography(pageLines: sparse, reflowableLines: sparse, documentBody: 12)
    #expect(bare.establishedBody == nil)
    #expect(bare.documentFloor == 12 * 1.1)
    #expect(bare.headingThreshold == 12 * 1.1)
    #expect(PageTypography(page: page(sparse)).documentFloor == 0)

    // Text inside images is excluded from the heading body; a larger reflowable body raises it.
    let large = (0..<5).map { line("Twelve point body text that establishes itself with plenty of characters here.", y: 300 - CGFloat($0) * 14, size: 12) }
    let mixed = PageTypography(pageLines: prose + large, reflowableLines: large, documentBody: nil)
    #expect(mixed.body == 12 || mixed.body == 10)
    #expect(mixed.headingBody == max(mixed.body, 12))
    #expect(mixed.headingThreshold == max(mixed.body * 1.25, mixed.headingBody * 1.1))
    #expect(mixed.body == max(4, LayoutReconstructor.bodySize(prose + large)))
    #expect(mixed.headingBody == LayoutReconstructor.headingBodySize(large, pageBody: mixed.body))
}

@Test func lineRolesFollowTheHeadingRules() {
    let content = page(prose)
    let typography = PageTypography(page: content)
    func role(_ line: TextLine, on page: PageContent = content, labels: [TextLine] = [], lines: [TextLine]? = nil,
              judges: Bool = false) -> LineRole {
        LayoutReconstructor.role(of: line, on: page, in: lines ?? page.lines, typography: PageTypography(page: page),
                                 labels: labels, judgesTitleWords: judges)
    }
    #expect(role(line("Chapter One", y: 560, size: 13)) == .heading)
    #expect(role(line("Chapter One", y: 560, size: 12)) == .prose)
    #expect(role(line("1 Numbers head too", y: 560, size: 13)) == .heading)
    #expect(role(line(String(repeating: "long ", count: 45), y: 560, size: 13)) == .prose)
    // A lone lowercase display line heads nothing; stacked under a title of its size it is part of it.
    let lowercase = line("pages 2, 4-14", y: 540, size: 14)
    #expect(role(lowercase) == .prose)
    let title = line("From Insects", y: 556, size: 14)
    #expect(role(lowercase, lines: prose + [title, lowercase]) == .heading)
    #expect(role(line("let x = 1", y: 300, monospaced: true)) == .code)
    #expect(role(line("1. First item", y: 300)) == .markedLine(MarkerColumn(onMajorityEdge: true, justifiedRight: 340)))
    #expect(role(line("• Bullet", y: 300)) == .listItem)
    #expect(role(line("Plain prose", y: 300)) == .prose)
    // A recurring bold label is a heading whatever its size.
    let label = line("Fighting Filth Flies", y: 300, bold: true)
    #expect(role(label, labels: [label]) == .heading)
    // Synthetic typography supplies no heading or code evidence.
    let synthetic = page(prose, synthetic: true)
    #expect(role(line("Chapter One", y: 560, size: 13), on: synthetic) == .prose)
    #expect(role(line("let x = 1", y: 300, monospaced: true), on: synthetic) == .prose)
    #expect(role(line("1. First item", y: 300), on: synthetic)
        == .markedLine(MarkerColumn(onMajorityEdge: true, justifiedRight: 340)))
    _ = typography
}

@Test func recognizedTitlesMustReadAsWords() throws {
    guard EnglishText.lexiconContains("chapter") == true else { return }
    let recognized = page(prose, recognized: true)
    func role(_ text: String) -> LineRole {
        LayoutReconstructor.role(of: line(text, y: 560, size: 13), on: recognized, in: recognized.lines,
                                 typography: PageTypography(page: recognized), labels: [], judgesTitleWords: true)
    }
    #expect(role("Chapter One") == .heading)
    #expect(role("Xq zzv qpr") == .prose)
    // Without the English gate the same noise would be a heading.
    #expect(LayoutReconstructor.role(of: line("Xq zzv qpr", y: 560, size: 13), on: recognized, in: recognized.lines,
                                     typography: PageTypography(page: recognized), labels: [], judgesTitleWords: false) == .heading)
}

@Test func assemblerBreaksParagraphsOnGeometry() {
    func paragraphs(_ lines: [TextLine]) -> [String] {
        var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
        for line in lines { assembler.append(line, as: .prose) }
        return assembler.finish().map(\.text)
    }
    let first = line("First line of the", y: 500), second = line("paragraph continues", y: 488)
    #expect(paragraphs([first, second]) == ["First line of the paragraph continues"])
    // A gap of nine tenths of the body or more is a paragraph break.
    #expect(paragraphs([first, line("Next paragraph", y: 500 - 12 - 9)]) == ["First line of the", "Next paragraph"])
    // A different column breaks; so does a line the reader says does not wrap.
    #expect(paragraphs([first, line("Other column", x: 60, y: 488)]) == ["First line of the", "Other column"])
    #expect(paragraphs([line("Ends here.", y: 500, wraps: false), second]) == ["Ends here.", "paragraph continues"])
    // A short line ending a sentence closes its paragraph.
    #expect(paragraphs([line("The end.", y: 500, width: 100), second]) == ["The end.", "paragraph continues"])
    #expect(paragraphs([line("The end.", y: 500, width: 250), second]) == ["The end. paragraph continues"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func assemblerJoinsTwoPiecesOfOnePrintedRow() {
    func paragraphs(_ lines: [TextLine]) -> [String] {
        var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
        for line in lines { assembler.append(line, as: .prose) }
        return assembler.finish().map(\.text)
    }
    // PDFKit can report the end of a printed line as a line of its own, a word's width from the
    // line it ends. The two pieces are one paragraph.
    let opening = line("the line ends with the word", y: 500, width: 292)
    #expect(paragraphs([opening, line("told", x: 336, y: 500, width: 16)])
        == ["the line ends with the word told"])
    // A column gutter's width apart they are separate blocks: a table's two cells, or a running
    // header and the folio at the other end of its row.
    #expect(paragraphs([opening, line("told", x: 340, y: 500, width: 16)]).count == 2)
    #expect(paragraphs([opening, line("49", x: 347, y: 500, width: 10)]).count == 2)
    // A short line on its own row still opens its own block, whatever stands above it.
    #expect(paragraphs([opening, line("108", x: 40, y: 470, width: 14)]).count == 2)
    // Only what follows the line joins it; a piece to its left is another block.
    #expect(paragraphs([line("told", x: 336, y: 500, width: 16), opening]).count == 2)
}

@Test func assemblerKeepsCodeIndentationAndListBreaks() {
    var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
    assembler.append(line("func run() {", x: 40, y: 300, monospaced: true), as: .code)
    assembler.append(line("return 1", x: 58, y: 288, monospaced: true), as: .code)
    assembler.append(line("}", x: 40, y: 276, monospaced: true), as: .code)
    assembler.append(line("Prose between.", y: 260), as: .prose)
    assembler.append(line("second block", x: 58, y: 240, monospaced: true), as: .code)
    assembler.append(line("• one", y: 220), as: .listItem)
    assembler.append(line("• two", y: 208), as: .listItem)
    let blocks = assembler.finish()
    #expect(blocks.map(\.text) == ["func run() {\n   return 1\n}", "Prose between.", "second block", "• one", "• two"])
    if case .preformatted = blocks[0].content {} else { Issue.record("code is preformatted") }
    if case .preformatted = blocks[3].content {} else { Issue.record("list items are preformatted") }
}

@Test func assemblerFlushesGroupsInOrderWithStableHeadingIdentifiers() {
    var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
    assembler.append(line("Title", y: 560, size: 14), as: .heading)
    assembler.appendNote(group: 1, line("1. A note that", y: 500))
    assembler.appendNote(group: 1, line("continues.", y: 488))
    assembler.appendNote(group: 2, line("2. Another.", y: 476))
    assembler.appendImage("image-4")
    let tag = TextStructure(group: 7, order: 1, headingLevel: 2)
    assembler.appendTagged(tag, line("Tagged", y: 300))
    assembler.appendTagged(tag, line("heading", y: 288))
    assembler.append(line("Prose", y: 200), as: .prose)
    let blocks = assembler.finish()
    #expect(blocks.map(\.text) == ["Title", "1. A note that continues.", "2. Another.", "", "Tagged heading", "Prose"])
    #expect(blocks[0].content == .heading(id: "heading-3-0", text: InlineText("Title"), level: 2))
    if case .heading(let id, let text, let level) = blocks[4].content {
        #expect(id == "heading-3-4" && text.text == "Tagged heading" && level == 2)
    } else { Issue.record("tagged heading") }
    #expect(blocks[4].structureGroup == 7)
    if case .image(let image) = blocks[3].content { #expect(image.assetID == "image-4") } else { Issue.record("image block") }
}

/// Two type sizes carrying the same weight must not let Dictionary iteration order, which Swift
/// seeds per process, decide a page's body size (#140).
@Test func bodySizeBreaksATieOnTheSmallerTypeDeterministically() {
    #expect(LayoutReconstructor.bodySize(weights: [10: 500, 12: 500]) == 10)
    #expect(LayoutReconstructor.bodySize(weights: [12: 500, 10: 500]) == 10)
    #expect(LayoutReconstructor.bodySize(weights: [9: 300, 11: 300, 24: 299]) == 9)
    // A clear winner still wins, whatever its size.
    #expect(LayoutReconstructor.bodySize(weights: [10: 499, 12: 500]) == 12)
    #expect(LayoutReconstructor.bodySize(weights: [:]) == nil)
    // Insertion order must never change the answer.
    for _ in 0..<64 {
        var weights: [Int: Int] = [:]
        for size in [8, 10, 12, 14, 18].shuffled() { weights[size] = 400 }
        #expect(LayoutReconstructor.bodySize(weights: weights) == 8)
    }
}

// MARK: - Marker-leading wrapped lines (#39, #238)

/// A wrapped body line can begin with an initial, a citation abbreviation or a year followed by a
/// point, which the list marker pattern also matches. Those lines belong to the paragraph above
/// them; a line that genuinely opens a list item still gets its own block. Every source page here
/// is a checksum-pinned extraction fixture, read against the printed page, never converter output.
private let loperBrightSHA256 = "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e"

private func reconstruct(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

private func reconstruct(_ lines: [TextLine]) -> [ReflowBlock] {
    reconstruct(PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                            lines: lines, graphics: []))
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { return $0.text } else { return nil } }
}

private func markers(_ texts: [String]) -> [String] {
    texts.filter { $0.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression) != nil }
}

/// Justified synthetic prose: a 460-point measure whose lines reach one right edge.
private func column(_ texts: [String], x: Double = 60, top: Double = 700, pitch: Double = 14,
                    widths: [Double]? = nil, indents: [Double]? = nil) -> [TextLine] {
    texts.enumerated().map { index, text in
        let width = widths?[index] ?? 460
        let indent = indents?[index] ?? 0
        return TextLine(text: text, rect: CGRect(x: x + indent, y: top - Double(index) * pitch,
                                                 width: width - indent, height: 12), fontSize: 12)
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/238"), arguments: [
    ("loper-60", "U. S. 967, 982–983 (2005). And those officials may even dis-",
     ["Telecommunications Assn. v. Brand X Internet Services, 545 U. S. 967, 982–983 (2005). And those officials may even dis-agree with",
      "a court’s past interpretation as well. Ibid. None of that is consistent with the APA’s clear mandate."]),
    ("loper-7", "2016. But because Chevron remains on the books, litigants must con-",
     ["has not deferred to an agency interpretation under Chevron since 2016. But because Chevron remains on the books, litigants must con-tinue to wrestle"]),
    ("loper-13", "F. 4th 359 (2022). The majority addressed various provi-",
     ["A divided panel of the D. C. Circuit affirmed. See 45 F. 4th 359 (2022). The majority addressed various provi-sions of the MSA"]),
    ("loper-2", "v. Moore, 95 U. S. 760, 763. “Respect,” though, was just that. The",
     ["who may well have drafted the laws at issue. United States v. Moore, 95 U. S. 760, 763. “Respect,” though, was just that. The views of the Executive Branch",
      "United States v. Morton Salt Co., 338 U. S. 632, 644, the Court often treated agency determinations of fact",
      "Skidmore v. Swift & Co., 323 U. S. 134, 140."]),
])
func citationLeadingWrappedLinesStayInTheirParagraph(name: String, wrapped: String, joined: [String]) throws {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == loperBrightSHA256)
    let page = fixture.content()
    #expect(page.lines.contains { $0.text == wrapped })
    let blocks = reconstruct(page)
    #expect(preformatted(blocks).isEmpty)
    for phrase in joined {
        #expect(paragraphs(blocks).contains { $0.contains(phrase) }, "missing \(phrase)")
    }
    // No page may lose words: every source character still stands in some block.
    let produced = blocks.map(\.text).joined(separator: " ").filter { !$0.isWhitespace }.sorted()
    #expect(produced == page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted())
}

/// The 9/11 report page #238 measures: restoring the word spaces the source draws turned
/// `W.Bush` into `W. Bush`, which then read as a list marker and cut the page's last printed
/// line — and the hyphenated word it ends on — out of the paragraph it belongs to.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/238"))
func theNineElevenReportKeepsAPresidentsInitialInItsParagraph() throws {
    let fixture = try SourceLayoutFixture.load("911-117")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    let page = fixture.content()
    let wrapped = "W. Bush, National Security Policy Directives. These documents and many oth-"
    #expect(page.lines.contains { $0.text == wrapped })
    let blocks = reconstruct(page)
    #expect(preformatted(blocks).isEmpty)
    #expect(paragraphs(blocks).contains {
        $0.contains("For President Clinton, they were to be Presidential Decision Directives; "
            + "for President George W. Bush, National Security Policy Directives.")
    })
    // The page's words all survive the join.
    let produced = blocks.map(\.text).joined(separator: " ").filter { !$0.isWhitespace }.sorted()
    #expect(produced == page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted())
}

@Test func loperBrightPageTwoKeepsItsFourSourceParagraphs() throws {
    let fixture = try SourceLayoutFixture.load("loper-2")
    var page = fixture.content()
    page.lines.removeAll { $0.text == "2 LOPER BRIGHT ENTERPRISES v. RAIMONDO" || $0.text == "Syllabus" }
    let body = paragraphs(reconstruct(page))
    let openings = ["that the final “interpretation of the laws”", "The Court recognized from the outset",
                    "During the “rapid expansion", "Occasionally during this period"]
    let endings = ["Decatur v. Paulding, 14 Pet. 497, 515.", "United States v. Dickson, 15 Pet. 141, 162.",
                   "Skidmore v. Swift & Co., 323 U. S. 134, 140.", "specific facts found by"]
    #expect(body.count == 4)
    for (index, paragraph) in body.enumerated() where index < 4 {
        #expect(paragraph.hasPrefix(openings[index]))
        #expect(paragraph.hasSuffix(endings[index]))
    }
}

@Test func authorInitialsAndYearsContinueJustifiedProse() {
    let lines = column([
        "The committee reviewed the position paper prepared during the previous session by",
        "A. Smith and B. Jones, who summarised the field work completed at the end of",
        "1998. The final report was accepted without amendment by all of the delegates",
        "v. the objections raised earlier, and the chair closed the meeting.",
    ], widths: [460, 460, 460, 300])
    let blocks = reconstruct(lines)
    #expect(preformatted(blocks).isEmpty)
    #expect(paragraphs(blocks).count == 1)
    #expect(paragraphs(blocks).first?.contains(
        "session by A. Smith and B. Jones, who summarised the field work completed at the end of 1998. The final") == true)
}

@Test func markersOpeningAnItemKeepTheirOwnBlock() {
    // A short introduction does not fill the measure, so what follows it opens items.
    let introduced = column(["The three factors are", "1. cost of the material", "2. delivery time", "3. warranty"],
                            widths: [180, 200, 150, 120])
    #expect(paragraphs(reconstruct(introduced)) == ["The three factors are"])
    #expect(preformatted(reconstruct(introduced)) == ["1. cost of the material", "2. delivery time", "3. warranty"])
    // A full line that ends a sentence — including one closed by a quote or a bracket — ends it.
    for ending in ["as follows:", "the steps.", "the steps.”", "the steps.)", "steps?", "steps!"] {
        let lines = column([
            "Justified prose that fills the whole measure of the column and then introduces",
            "another full line that also reaches the right margin before listing " + ending,
            "1. First step in the procedure that follows the introduction",
            "2. Second step in the procedure",
            "a. A lettered sub-step",
        ], widths: [460, 460, 300, 200, 150])
        #expect(paragraphs(reconstruct(lines)).count == 1, Comment(rawValue: ending))
        #expect(preformatted(reconstruct(lines)).map { String($0.prefix(2)) } == ["1.", "2.", "a."],
                Comment(rawValue: ending))
    }
    let base = [
        "Justified prose that fills the whole measure of the column and then continues",
        "with another full line that also reaches the right margin without any period",
        "1. First item that is not a wrapped continuation of the prose above it",
    ]
    // A paragraph gap before the marker.
    var gapped = column(base)
    gapped[2].rect.origin.y -= 12
    #expect(preformatted(reconstruct(gapped)).count == 1)
    // A marker indented past the text above it hangs a new item.
    #expect(preformatted(reconstruct(column(base, indents: [0, 0, 8]))).count == 1)
    // A line the reader says does not wrap.
    var unwrapped = column(base)
    unwrapped[1].wraps = false
    #expect(preformatted(reconstruct(unwrapped)).count == 1)
    // A marker beside a column whose lines do not share a right edge.
    #expect(preformatted(reconstruct(column(base, widths: [460, 300, 240]))).count == 1)
    // The same geometry without any of those signals joins.
    #expect(preformatted(reconstruct(column(base))).isEmpty)
    #expect(paragraphs(reconstruct(column(base))).count == 1)
}

@Test func aRightEdgeNeedsThreeSupportingLines() {
    // Two lines alone do not establish a justified measure; the marker opens an item.
    let pair = column(["A single line of prose that happens to reach the right margin without",
                       "1. a period at the end"], widths: [460, 200])
    #expect(preformatted(reconstruct(pair)) == ["1. a period at the end"])
    // With a third full line on the page the same pair joins.
    let supported = column(["A single line of prose that happens to reach the right margin without",
                            "1. a period at the end, and then more prose that fills the measure again",
                            "and again with a third line that reaches the same right margin before",
                            "ending here with a period."], widths: [460, 460, 460, 200])
    #expect(preformatted(reconstruct(supported)).isEmpty)
    #expect(paragraphs(reconstruct(supported)).count == 1)
}

@Test func bulletsNeverContinueProse() {
    let lines = column([
        "Justified prose that fills the whole measure of the column and then continues",
        "• a bullet at the same left edge without a gap is still a list item, not prose",
        "− a minus-prefixed line is treated the same way as a bullet marker here",
        "- and so is a hyphen marker at the start of a line",
    ])
    #expect(preformatted(reconstruct(lines)).count == 3)
    #expect(paragraphs(reconstruct(lines)).count == 1)
}

@Test func anOutdentedMarkerJoinsOnlyBeneathAnIndentedOpeningLine() {
    // The Loper Bright page 13 geometry: an indented opening line, then a marker at the edge.
    let opening = column([
        "A divided panel of the circuit affirmed the judgment below. See 45",
        "F. 4th 359 (2022). The majority addressed various provisions of the",
        "statute and concluded that the text was not wholly unambiguous, and",
        "the dissent disagreed.",
    ], widths: [460, 460, 460, 180], indents: [12, 0, 0, 0])
    #expect(preformatted(reconstruct(opening)).isEmpty)
    #expect(paragraphs(reconstruct(opening)).count == 1)
    // A hanging indent reverses it: a dedented continuation line followed by an indented marker
    // is the next entry, not a wrap (#219 item 1 describes the same shape for bibliographies).
    let notes = column([
        "5. See the earlier discussion of the evidence, which fills the whole line and",
        "continues here at the dedented margin without ending in a period, pp. 40",
        "6. The next note begins at the indented margin like every other note start",
    ], indents: [12, 0, 12])
    #expect(preformatted(reconstruct(notes)).map { String($0.prefix(2)) } == ["5.", "6."])
}

/// Source pages whose marker-leading lines genuinely open items: Wallace's numbered exercises,
/// the Warren Commission's numbered points under a synthetic text style, and the Fed book's
/// numbered objectives and bulleted lists. Every one of them must keep its own block.
@Test func corpusListOpeningsKeepTheirOwnBlocks() throws {
    let algebra = try SourceLayoutFixture.load("algebra-26")
    let exercises = preformatted(reconstruct(algebra.content()))
    let numbered = markers(algebra.lines.map(\.text))
    #expect(numbered.count >= 20)
    #expect(numbered.allSatisfy { exercises.contains($0) })

    var warren = try SourceLayoutFixture.load("warren-50").content()
    warren.hasSyntheticTextStyle = true
    let points = preformatted(reconstruct(warren))
    #expect(markers(warren.lines.map(\.text)).allSatisfy { points.contains($0) })

    // Bulleted lists are never candidates at all.
    for name in ["fed-77", "fed-123"] {
        let bulleted = try SourceLayoutFixture.load(name)
        let items = bulleted.lines.map(\.text).filter { $0.hasPrefix("• ") }
        let blocks = preformatted(reconstruct(bulleted.content()))
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { blocks.contains($0) }, Comment(rawValue: name))
    }
}

// MARK: - A paragraph the page tags in part (#67, #238)

/// Loper Bright page 13, with the page's own tags applied. The slip opinion's tags apply only in
/// part on every one of its pages, and here exactly one line of a nine-line paragraph — its
/// first — carries a `P` group; the other eight fall back to the spatial rules. The assembler
/// therefore receives one printed paragraph as a tagged line followed by untagged ones, and the
/// second of those untagged lines opens `F. 4th`, which reads as a list marker.
///
/// Every byte here is the source's: `loper-13-tags.json` replays page 13's content stream, fonts
/// and structure subtree, and `loper-13-layout.json` carries PDFKit's own lines for the page.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/67"),
      .bug("https://github.com/vocaro/PDFReflowLib/issues/238"))
func aParagraphTaggedOnlyOnItsFirstLineStaysOneParagraph() throws {
    let fixture = try SourceTagFixture.load("loper-13")
    let native = try SourceLayoutFixture.load("loper-13")
    #expect(fixture.sourceSHA256 == loperBrightSHA256)
    #expect(native.sourceSHA256 == loperBrightSHA256)
    let opening = "A divided panel of the D. C. Circuit affirmed. See 45"
    let wrapped = "F. 4th 359 (2022). The majority addressed various provi-"
    var content = native.content()
    try fixture.withPage { url, page in
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        // The page's tags apply in part: a show this reader cannot place costs its own group and
        // no more, which is what #67 opened and what leaves the page's lines interleaved.
        #expect(!MarkedTextReader.apply(tags, page: page, lines: &content.lines))
    }
    let tagged = content.lines.filter { $0.structure != nil }
    #expect(tagged.map(\.text) == [opening])
    #expect(tagged.first?.structure?.headingLevel == 0)
    let group = try #require(tagged.first?.structure?.group)
    #expect(content.lines.contains { $0.text == wrapped && $0.structure == nil })

    let blocks = reconstruct(content)
    // The wrapped line is not cut out of its paragraph, and no other line of the page is either.
    #expect(preformatted(blocks).isEmpty)
    #expect(paragraphs(blocks).contains { $0.contains(opening + " " + wrapped + "sions of the MSA") })
    // The source paragraph identity the tags stated travels with the block that carries it.
    #expect(blocks.filter { $0.structureGroup == group }.count == 1)
    // No page may lose words: every source character still stands in some block.
    let produced = blocks.map(\.text).joined(separator: " ").filter { !$0.isWhitespace }.sorted()
    #expect(produced == content.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted())
}

/// The assembler's half of the rule above, stated directly: one open paragraph, whether the tags
/// named it or the page's geometry did. A tagged paragraph takes the untagged lines that continue
/// it, including a marker-leading wrap; a tagged heading takes none of them.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/238"))
func anUntaggedLineContinuesATaggedParagraphButNeverATaggedHeading() {
    let lines = column([
        "The committee reviewed the position paper prepared during the previous session by",
        "A. Smith and B. Jones, who summarised the field work completed at the end of",
        "1998. The final report was accepted without amendment by all of the delegates.",
    ])
    let marked = LineRole.markedLine(MarkerColumn(onMajorityEdge: true, justifiedRight: 520))
    var assembler = BlockAssembler(page: 3, body: 12, hyphens: HyphenContext())
    assembler.appendTagged(TextStructure(group: 4, order: 1, headingLevel: 0, lineCount: 1), lines[0])
    assembler.append(lines[1], as: marked)
    assembler.append(lines[2], as: marked)
    let joined = assembler.finish()
    #expect(joined.count == 1)
    #expect(joined.first?.text == lines.map(\.text).joined(separator: " "))
    #expect(joined.first?.structureGroup == 4)

    var heading = BlockAssembler(page: 3, body: 12, hyphens: HyphenContext())
    heading.appendTagged(TextStructure(group: 5, order: 1, headingLevel: 2, lineCount: 1), lines[0])
    heading.append(lines[1], as: .prose)
    heading.append(lines[2], as: .prose)
    let split = heading.finish()
    #expect(split.count == 2)
    #expect(split.first?.content == .heading(id: "heading-3-0", text: lines[0].content, level: 2))
    #expect(split.first?.structureGroup == 5)
    #expect(split.last?.text == lines[1].text + " " + lines[2].text)
    #expect(split.last?.structureGroup == nil)
}
