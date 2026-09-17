import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #97: the FAA handbook's untagged 10-point italic titles are headings in the book's recurring
// italic title style, italic titles over bullet lists are headings, the PAVE checklist's
// `V = EnVironment` is a title rather than a formula crop, the blank last pages of appendix A and
// the glossary lose their folios, and contents entries with chapter or lettered folios read as
// contents entries. Fixtures are captured from the checksum-pinned source; expected text was
// read against rendered pages.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func faa(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("faa-\(number)-tagged")
    #expect(fixture.sourceSHA256 == faaSHA256)
    return fixture.styledContent()
}

/// The book's label styles, counted from the fixture pages' own evidence as the pipeline counts
/// them across the book: pages 45, 48, 228 and 447 set 10-point italic titles over 10-point body
/// text, and pages 45, 48 and 447 11-point bold italic ones (tags are no part of the evidence).
private func faaLabelStyles() throws -> Set<LayoutReconstructor.LabelStyle> {
    var pages: [LayoutReconstructor.LabelStyle: Int] = [:]
    for number in [45, 48, 228, 447] {
        for style in LayoutReconstructor.labelEvidence(on: try faa(number)) { pages[style, default: 0] += 1 }
    }
    return LayoutReconstructor.labelStyles(from: pages)
}

private let italicTitleStyle: LayoutReconstructor.LabelStyle = {
    let line = TextLine(content: InlineText("Drugs", style: .italic), rect: CGRect(x: 0, y: 0, width: 25, height: 11.3), fontSize: 10)
    return LayoutReconstructor.LabelStyle(line, body: 10)
}()

private func reconstruct(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings, labelStyles: labelStyles)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

/// The block after the heading `title`.
private func after(_ blocks: [ReflowBlock], _ title: String) -> ReflowBlock? {
    guard let index = blocks.firstIndex(where: { if case .heading = $0.content { $0.text == title } else { false } }),
          index + 1 < blocks.count else { return nil }
    return blocks[index + 1]
}

// MARK: - Untagged italic titles

@Test func theBooksItalicTitleStyleIsRecordedLikeItsBoldLabelStyles() throws {
    let styles = try faaLabelStyles()
    #expect(styles.contains(italicTitleStyle))
    // A bold line never carries the italic flag, so the bold and bold-italic label styles keep
    // one key between them, as before.
    let boldItalic = TextLine(content: InlineText("Assessing Risk", style: [.bold, .italic]),
                              rect: CGRect(x: 0, y: 0, width: 70, height: 13), fontSize: 11)
    let bold = TextLine(content: InlineText("Assessing Risk", style: .bold), rect: boldItalic.rect, fontSize: 11)
    #expect(LayoutReconstructor.LabelStyle(boldItalic, body: 10) == LayoutReconstructor.LabelStyle(bold, body: 10))
    #expect(!LayoutReconstructor.LabelStyle(boldItalic, body: 10).italic)
}

@Test func untaggedItalicTitlesInTheBooksItalicStyleAreHeadings() throws {
    let styles = try faaLabelStyles()
    // FAA page 447 (no usable tags): six titles over their paragraphs in the left column.
    let page447 = try faa(447)
    let blocks = reconstruct(page447, labelStyles: styles)
    for (title, opening) in [("Drugs", "Drugs can seriously degrade"), ("Exhaustion", "Pilots who become fatigued"),
                             ("Poor Physical Conditioning", "To overcome poor physical"), ("Alcohol", "Alcohol is a sedative"),
                             ("Tobacco", "Of all the self-imposed"), ("Hypoglycemia and Nutritional Deficiency", "Missing or postponing meals")] {
        #expect(headings(blocks).contains(title))
        #expect(after(blocks, title)?.text.hasPrefix(opening) == true, "\(title)")
    }
    // Reproducer: without the book's italic style each title opens its paragraph.
    let alone = reconstruct(page447)
    #expect(paragraphs(alone).contains { $0.hasPrefix("Drugs Drugs can seriously degrade") })
    #expect(!headings(alone).contains("Drugs"))
    // FAA page 228: `Southerly Turning Errors` heads the right column and `Acceleration Error`
    // follows a bracketed figure reference; without the style both open their paragraphs.
    let page228 = reconstruct(try faa(228), labelStyles: styles)
    #expect(after(page228, "Southerly Turning Errors")?.text.hasPrefix("When turning in a southerly direction") == true)
    #expect(after(page228, "Acceleration Error")?.text.hasPrefix("The magnetic dip and the forces of inertia") == true)
    #expect(paragraphs(reconstruct(try faa(228))).contains { $0.hasPrefix("Southerly Turning Errors When turning") })
    // Controls on the same page: the figure caption's italic text and the body's italic figure
    // references stay text.
    #expect(!headings(blocks).contains { $0.hasPrefix("Figure") || $0.contains("[Figure") })
}

// MARK: - Italic titles over lists and the PAVE mnemonic titles (page 48)

@Test func italicTitlesOverBulletListsAndMnemonicTitlesAreHeadings() throws {
    let page = try faa(48)
    // Reproducer: `V = EnVironment` seeded a formula crop, whose label expansion took `Weather`.
    #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
    let blocks = reconstruct(page, labelStyles: try faaLabelStyles())
    #expect(headings(blocks).starts(with: ["V = EnVironment", "Weather", "Terrain", "Airport", "Airspace", "Nighttime",
                                          "E = External Pressures"]))
    #expect(after(blocks, "Weather")?.text.hasPrefix("Weather is a major environmental consideration.") == true)
    // Tagged titles directly over their bullets: the list follows its title.
    for title in ["Airport", "Airspace"] {
        guard case let .preformatted(text)? = after(blocks, title)?.content else {
            Issue.record("\(title) is not followed by its list"); continue
        }
        #expect(text.text.hasPrefix("•"))
    }
}

@Test func mnemonicTitleIsNotAFormulaButEquationsStillAre() {
    func line(_ text: String, style: TextStyle, y: CGFloat = 400) -> TextLine {
        TextLine(content: InlineText(text, style: style), rect: CGRect(x: 72, y: y, width: 90, height: 13), fontSize: 11)
    }
    #expect(LayoutReconstructor.isLetterMnemonic(line("V = EnVironment", style: [.bold, .italic])))
    #expect(LayoutReconstructor.isLetterMnemonic(line("A = Aircraft", style: .bold)))
    // Controls: an equation's terms, a plain-type definition, a two-letter product and a
    // multi-letter left side are not mnemonic titles.
    #expect(!LayoutReconstructor.isLetterMnemonic(line("A = Aircraft", style: [])))
    #expect(!LayoutReconstructor.isLetterMnemonic(line("F = Ma", style: .bold)))
    #expect(!LayoutReconstructor.isLetterMnemonic(line("E = mc2", style: .bold)))
    #expect(!LayoutReconstructor.isLetterMnemonic(line("TAS = CAS + 2%", style: .bold)))
    #expect(!LayoutReconstructor.isLetterMnemonic(line("V = Velocity x Time", style: .bold)))
    // A bold equation line still seeds its crop.
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: [line("F = Ma", style: .bold)], graphics: [])
    #expect(!LayoutReconstructor.graphicsWithLabels(page).isEmpty)
}

/// An untagged italic line over the given body text, on a page of justified 10-point prose.
private func untaggedTitlePage(_ title: String, italic: Bool = true, gapAbove: CGFloat = 13.7,
                               beneath: String = "Pilots who become fatigued during a night flight will not be",
                               beneathX: CGFloat = 72, beneathItalic: Bool = false) -> PageContent {
    func line(_ text: String, x: CGFloat = 72, y: CGFloat, width: CGFloat = 237, style: TextStyle = []) -> TextLine {
        TextLine(content: InlineText(text, style: style), rect: CGRect(x: x, y: y, width: width, height: 11.5), fontSize: 10)
    }
    let titleY: CGFloat = 500
    var lines = (0..<4).map { line("mentally alert and will respond more slowly to situations that", y: titleY + 11.3 + gapAbove + CGFloat($0) * 12.5) }
    lines.append(TextLine(content: InlineText(title, style: italic ? .italic : []),
                          rect: CGRect(x: 72, y: titleY, width: 60, height: 11.3), fontSize: 10))
    lines.append(line(beneath, x: beneathX, y: titleY - 14.5, width: 309 - beneathX, style: beneathItalic ? .italic : []))
    lines += (1..<4).map { line("requiring immediate action. Exhausted pilots tend to fixate on", y: titleY - 14.5 - CGFloat($0) * 12.5) }
    return PageContent(number: 447, bounds: CGRect(x: 0, y: 0, width: 594, height: 774), lines: lines, graphics: [])
}

@Test func untaggedItalicTitleNeedsTheStyleSpaceTitleCaseAndBodyOrAListBeneath() {
    let styles: Set<LayoutReconstructor.LabelStyle> = [italicTitleStyle]
    func isTitle(_ page: PageContent, styles: Set<LayoutReconstructor.LabelStyle> = [italicTitleStyle]) -> Bool {
        headings(reconstruct(page, labelStyles: styles)).contains { !$0.hasPrefix("mentally") }
    }
    #expect(isTitle(untaggedTitlePage("Exhaustion")))
    #expect(isTitle(untaggedTitlePage("Airport", beneath: "• What lights are available at the destination and", beneathX: 81)))
    // Controls: no recurring italic style; not italic; italic emphasis at ordinary leading inside
    // prose; a sentence; not title case; a caption; italic text beneath (a quotation); a nested
    // list deeper than 2.5 em.
    #expect(!isTitle(untaggedTitlePage("Exhaustion"), styles: []))
    #expect(!isTitle(untaggedTitlePage("Exhaustion", italic: false)))
    #expect(!isTitle(untaggedTitlePage("Exhaustion", gapAbove: 1)))
    #expect(!isTitle(untaggedTitlePage("Exhaustion.")))
    #expect(!isTitle(untaggedTitlePage("Exhaustion of pilots")))
    #expect(!isTitle(untaggedTitlePage("Figure 17-20 Stress")))
    #expect(!isTitle(untaggedTitlePage("Exhaustion", beneathItalic: true)))
    #expect(!isTitle(untaggedTitlePage("Airport", beneath: "• What lights are available at the destination and", beneathX: 110)))
    _ = styles
}

// MARK: - Blank pages carrying only a lettered folio

/// FAA appendix A's last pages: a 10-point foot folio `A-N`, alternating sides, geometry as
/// extracted, over a figure label on every page but the blank last one.
private func appendixAPage(_ number: Int) -> PageContent {
    let folio = "A-\(number - 452)"
    let x: CGFloat = number.isMultiple(of: 2) ? 36 : 542.4
    var lines = [TextLine(text: folio, rect: CGRect(x: x, y: 33.7, width: 15.6, height: 12.3), fontSize: 10)]
    lines.append(TextLine(text: "All data are subject to change without prior notice.",
                          rect: CGRect(x: 233.2, y: 141.6, width: 177.2, height: 9.8), fontSize: 8))
    return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 594, height: 774), lines: lines, graphics: [])
}

@Test func aBlankPageLosesItsOnlyLineWhenThatLineIsAFolioOfTheRun() throws {
    // FAA pages 457–460: `A-5`…`A-7` over figure pages, then page 460, blank but for `A-8`.
    var pages = [457, 458, 459].map(appendixAPage) + [try faa(460)]
    #expect(pages[3].lines.map(\.text) == ["A-8"])
    let removed = LayoutReconstructor.stripFurniture(&pages)
    #expect(removed.map(\.page) == [457, 458, 459, 460])
    #expect(pages[3].lines.isEmpty)
    #expect(pages[..<3].allSatisfy { $0.lines.map(\.text) == ["All data are subject to change without prior notice."] })
    // FAA pages 510–512: the glossary's `G-34`, the captured `G-35` page and the blank `G-36`.
    let g34 = PageContent(number: 510, bounds: CGRect(x: 0, y: 0, width: 594, height: 774), lines: [
        TextLine(text: "G-34", rect: CGRect(x: 36, y: 33.7, width: 22.2, height: 12.3), fontSize: 10),
        TextLine(text: "Zulu time. See Coordinated Universal Time.", rect: CGRect(x: 72, y: 400, width: 200, height: 11.5), fontSize: 10),
    ], graphics: [])
    let g35 = try SourceLayoutFixture.load("faa-511").styledContent()
    var glossary = [g34, g35, try faa(512)]
    #expect(LayoutReconstructor.stripFurniture(&glossary).map(\.page) == [510, 511, 512])
    #expect(glossary[2].lines.isEmpty)
    #expect(glossary[1].lines.count == g35.lines.count - 1)
    // Controls: a blank page's lone folio that breaks the run's offset keeps its line, and a
    // blank page carrying a running head as well as its folio is not emptied (only a page whose
    // removed lines are all bare folios is), while the head and folio go on the pages with text.
    var broken = [457, 458, 459].map(appendixAPage) + [try faa(460)]
    broken[3].lines[0] = TextLine(text: "A-9", rect: broken[3].lines[0].rect, fontSize: 10)
    _ = LayoutReconstructor.stripFurniture(&broken)
    #expect(broken[3].lines.map(\.text) == ["A-9"])
    func headed(_ number: Int, text: Bool) -> PageContent {
        var page = appendixAPage(number)
        if !text { page.lines.removeLast() }
        page.lines.append(TextLine(text: "Appendix A", rect: CGRect(x: 250, y: 740, width: 50, height: 12.3), fontSize: 10))
        return page
    }
    var margin = [headed(457, text: true), headed(458, text: true), headed(459, text: true), headed(460, text: false)]
    _ = LayoutReconstructor.stripFurniture(&margin)
    #expect(margin[0].lines.map(\.text) == ["All data are subject to change without prior notice."])
    #expect(margin[3].lines.map(\.text) == ["A-8", "Appendix A"])
}

// MARK: - Contents entries with chapter and lettered folios

@Test func contentsEntriesEndingInChapterOrLetteredFoliosAreContentsEntries() throws {
    for text in ["Introduction To Flying..........................................1-1",
                 "Glossary...............................................................G-1",
                 "and Challenger 605.............................................A-1",
                 "Communication Procedures ...............................14-31",
                 "Preface....................................................................iii",
                 "Weight and Balance .......................................10-1"] {
        #expect(LayoutReconstructor.isContentsEntry(text), "\(text)")
    }
    // Controls: a folio without a leader, an ellipsis before prose, a two-letter prefix and a folio
    // with more parts are not contents entries.
    for text in ["Introduction To Flying 1-1", "Figure 1-1", "and so on... 1-1", "Model....AB-1", "Chapter....1-2-3"] {
        #expect(!LayoutReconstructor.isContentsEntry(text), "\(text)")
    }
    // Every leader entry on FAA contents pages 6 and 15 reads as one.
    for number in [6, 15] {
        let entries = try faa(number).lines.filter { $0.text.contains("....") }
        #expect(!entries.isEmpty)
        #expect(entries.filter { !LayoutReconstructor.isContentsEntry($0.text) }.map(\.text) == [], "page \(number)")
    }
}
