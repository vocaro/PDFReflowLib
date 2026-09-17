import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #159, read against renders of USDA ARS *Agricultural Research*, November/December 2012:
//
// - the running foot survived on eleven pages because a six-point photo credit, or the column's
//   own last line, stands eight points above it — nearer than the separation rule asks — although
//   the magazine rules the foot off on every page, and because two unsupported-graphics pages
//   report estimated type sizes that split the foot's run in half;
// - the columns' ten-point first-line indent is narrower than the drift the same-column test
//   allows, so every column read as one paragraph (page 9's three source paragraphs became one,
//   and the 9/11 report, Loper Bright, the IEEEtran paper and the acmart paper merged too);
// - the nine-point bold subheads are set *under* the ten-and-a-half point body, below the floor
//   sub-heading candidates must reach, and the paragraph beneath them opens on that indent rather
//   than on their own edge, so they stayed bold paragraphs or ran into their paragraph;
// - the six-point photo credits are read where they stand, which puts them at the top of the page
//   while the photograph they name is the last block.
//
// Fixtures are captured from the checksum-pinned sources; expected text and placement were read
// against 60 DPI Poppler renders of the pages.

private let usdaSHA256 = "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761"
private let flagSHA256 = "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8"

/// One magazine page with its running foot and folio already removed, as the pipeline reads it.
private func usdaPage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("usda-\(number)")
    #expect(fixture.sourceSHA256 == usdaSHA256)
    var pages = [fixture.styledContent()]
    _ = LayoutReconstructor.stripFurniture(&pages)
    return pages[0]
}

/// The same page with its furniture still in place.
private func usdaSourcePage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("usda-\(number)")
    #expect(fixture.sourceSHA256 == usdaSHA256)
    return fixture.styledContent()
}

/// The magazine's sub-heading style: nine-point bold over a ten-and-a-half point body.
/// The styles the page's own narrow labels establish, as the pipeline collects them across the
/// magazine before reconstruction.
private func subheadStyles(_ page: PageContent) -> Set<LayoutReconstructor.LabelStyle> {
    LayoutReconstructor.labelEvidence(on: page)
}

private func reflow(_ page: PageContent,
                    labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                      vocabulary: [], warnings: &warnings, labelStyles: labelStyles)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

/// The blocks' kinds and, for an image, its asset; enough to pin a credit's neighbours.
private func shape(_ blocks: [ReflowBlock]) -> [String] {
    blocks.map { block in
        switch block.content {
        case .image(let image): "image:\(image.assetID)"
        case .heading: "heading"
        case .paragraph(let text): "paragraph:\(text.text.prefix(24))"
        default: "other"
        }
    }
}

// MARK: - The ruled running foot

/// The foot and the folio of every magazine page, as the source sets them.
private func magazinePages() -> [PageContent] {
    (1...4).map { index in
        var page = PageContent(number: index, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                               lines: [], graphics: [CGRect(x: 34.5, y: 39, width: 544, height: 4)])
        page.lines = [
            TextLine(text: "Agricultural Research l November/December 2012",
                     rect: CGRect(x: 373.7, y: 24.6, width: 202.3, height: 12), fontSize: 9),
            TextLine(text: "PEGGY GREB (D269\(index)-1)",
                     rect: CGRect(x: 36, y: 44.9, width: 58.3, height: 7.3), fontSize: 6),
            TextLine(text: "Body line \(index) of the column.",
                     rect: CGRect(x: 36, y: 700, width: 172, height: 13.8), fontSize: 10.5),
        ]
        return page
    }
}

@Test func aRuleUnderTheColumnSeparatesTheFootFromTheCreditAboveIt() throws {
    var pages = magazinePages()
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.count == 4)
    for page in pages {
        #expect(page.lines.map(\.text) == ["PEGGY GREB (D269\(page.number)-1)", "Body line \(page.number) of the column."])
    }
    // Negative control: without the rule the eight points above the foot are all the evidence
    // there is, and the separation rule keeps the line, as it did before #159.
    var unruled = magazinePages()
    for index in unruled.indices { unruled[index].graphics = [] }
    let original = unruled
    #expect(LayoutReconstructor.stripFurniture(&unruled).isEmpty)
    #expect(zip(unruled, original).allSatisfy { $0.lines.map(\.text) == $1.lines.map(\.text) })
}

@Test func aSeparatingRuleMustBeThinPageWideAndInsideTheGap() throws {
    // Each control replaces the page-wide hairline with a rule that cannot be the page's boundary:
    // one too tall to be a rule, one spanning half the measure, one above the credit rather than
    // between it and the foot, and one overlapping the foot's own line.
    for rule in [CGRect(x: 34.5, y: 39, width: 544, height: 20),
                 CGRect(x: 34.5, y: 39, width: 300, height: 4),
                 CGRect(x: 34.5, y: 60, width: 544, height: 4),
                 CGRect(x: 34.5, y: 30, width: 544, height: 4)] {
        var pages = magazinePages()
        for index in pages.indices { pages[index].graphics = [rule] }
        let original = pages
        #expect(LayoutReconstructor.stripFurniture(&pages).isEmpty, "\(rule)")
        #expect(zip(pages, original).allSatisfy { $0.lines.map(\.text) == $1.lines.map(\.text) })
    }
}

@Test func anEstimatedTypeSizeDoesNotSplitAFootsRun() throws {
    // Pages 20 and 21 of the magazine draw graphics the reader cannot reflow, so their lines carry
    // no font attributes and their sizes are the measured glyph heights: 11.98 against the nine
    // points every other page reports. Read as type sizes, those two pages split one run of
    // twenty-two into runs of eighteen, two and two, and pages 22 and 23 kept their foot.
    var pages = (1...6).map { index -> PageContent in
        var page = PageContent(number: index, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                               lines: [], graphics: [])
        page.lines = [
            TextLine(text: "Agricultural Research l November/December 2012",
                     rect: CGRect(x: 373.7, y: 24.6, width: 202.3, height: 12), fontSize: 9),
            TextLine(text: "Body line \(index) of the column.",
                     rect: CGRect(x: 36, y: 700, width: 172, height: 13.8), fontSize: 10.5),
        ]
        if index == 3 || index == 4 {
            page.requiresPageImage = true
            page.lines[0].fontSize = page.lines[0].rect.height
        }
        return page
    }
    #expect(LayoutReconstructor.stripFurniture(&pages).count == 6)
    #expect(pages.allSatisfy { $0.lines.count == 1 })
    // Negative control: a page that reports a real type size two thirds larger is different
    // typography and still splits the run, leaving neither part long enough.
    var mixed = (1...4).map { index -> PageContent in
        var page = PageContent(number: index, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                               lines: [], graphics: [])
        page.lines = [
            TextLine(text: "Agricultural Research l November/December 2012",
                     rect: CGRect(x: 373.7, y: 24.6, width: 202.3, height: 12),
                     fontSize: index == 2 ? 15 : 9),
            TextLine(text: "Body line \(index) of the column.",
                     rect: CGRect(x: 36, y: 700, width: 172, height: 13.8), fontSize: 10.5),
        ]
        return page
    }
    let original = mixed
    #expect(LayoutReconstructor.stripFurniture(&mixed).isEmpty)
    #expect(zip(mixed, original).allSatisfy { $0.lines.map(\.text) == $1.lines.map(\.text) })
}

@Test func sourceMagazineFeetGoWhileTheCreditsAndProseStay() throws {
    // Pages 15, 17 and 19 are the run: three neighbouring pages whose foot stands at one height
    // in one size. On every one of them the foot's nearest neighbour is nearer than a line
    // height — a photo credit on 17 and 19, the article's own last line on 15 — and only the
    // page-wide rule beneath the columns separates it.
    var pages = try [15, 17, 19].map { try usdaSourcePage($0) }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == [15, 17, 19])
    for (before, after) in zip(original, pages) {
        let foot = "Agricultural Research l November/December 2012"
        #expect(before.lines.contains { $0.text == foot })
        #expect(after.lines.map(\.text) == before.lines.filter { $0.text != foot && $0.text != "\(before.number)" }.map(\.text))
    }
}

// MARK: - First-line indents

@Test func sourceColumnsBreakAtTheirFirstLineIndent() throws {
    let page = try usdaPage(9)
    let texts = paragraphs(reflow(page))
    for opening in ["see which ones are more effective", "Only a few studies have addressed sand",
                    "Another laboratory looking for solutions"] {
        #expect(texts.contains { $0.hasPrefix(opening) }, "\(opening) in \(texts.map { $0.prefix(40) })")
    }
    // The first paragraph stops where the source does, and the second carries its own sentences.
    let first = try #require(texts.first { $0.hasPrefix("see which ones") })
    #expect(first.hasSuffix("insecticides to control the sand fly.”"))
    let second = try #require(texts.first { $0.hasPrefix("Only a few studies") })
    #expect(second.hasSuffix("responsible for resistance."))
}

@Test func anIndentOpensAParagraphOnlyWhereThePageRepeatsIt() {
    /// A column of `count` paragraphs, each opening `indent` points inside the measure.
    func column(indent: CGFloat, paragraphs count: Int, hanging: Bool = false) -> PageContent {
        var lines: [TextLine] = []
        var y: CGFloat = 700
        for paragraph in 0..<count {
            for line in 0..<3 {
                let first = hanging ? line > 0 : line == 0
                lines.append(TextLine(text: "Paragraph \(paragraph) line \(line) of ordinary prose here.",
                                      rect: CGRect(x: 36 + (first ? indent : 0), y: y,
                                                   width: 172 - (first ? indent : 0), height: 13.8),
                                      fontSize: 10.5))
                y -= 12.5
            }
        }
        return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: lines, graphics: [])
    }
    #expect(LayoutReconstructor.firstLineIndentRun(in: column(indent: 10, paragraphs: 3).lines,
                                                   step: 10, size: 10.5))
    // A hanging indent sets two lines in a row at the indent, so it is not a first-line indent.
    #expect(!LayoutReconstructor.firstLineIndentRun(in: column(indent: 10, paragraphs: 3, hanging: true).lines,
                                                    step: 10, size: 10.5))
    // One opening is a step, not a pattern; and the step must be the one asked about.
    #expect(!LayoutReconstructor.firstLineIndentRun(in: column(indent: 10, paragraphs: 2).lines,
                                                    step: 10, size: 10.5))
    #expect(!LayoutReconstructor.firstLineIndentRun(in: column(indent: 10, paragraphs: 3).lines,
                                                    step: 20, size: 10.5))
    // Lines of another size are neither neighbours nor evidence.
    #expect(!LayoutReconstructor.firstLineIndentRun(in: column(indent: 10, paragraphs: 3).lines,
                                                    step: 10, size: 20))
}

@Test func anIndentedLineContinuesItsParagraphWithoutThePagesPattern() {
    // One indented line inside a column that shows no other indent stays in its paragraph, as it
    // did before #159: the same-column test still allows a line to drift by a body and a half.
    var lines: [TextLine] = []
    var y: CGFloat = 700
    for index in 0..<6 {
        lines.append(TextLine(text: index == 3 ? "Drifted line of the same paragraph runs on here."
                                               : "Line \(index) of one paragraph running on here.",
                              rect: CGRect(x: index == 3 ? 46 : 36, y: y, width: 172, height: 13.8),
                              fontSize: 10.5))
        y -= 12.5
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: lines, graphics: [])
    #expect(paragraphs(reflow(page)).count == 1)
}

// MARK: - Sub-headings set under the body

@Test func sourceSubheadsSmallerThanTheBodyAreHeadings() throws {
    let page19 = try usdaPage(19)
    // The magazine's own evidence: a nine-point bold label over its eleven-point measured body.
    #expect(subheadStyles(page19).contains { $0.size == 18 && $0.body == 22 && $0.bold && !$0.italic })
    #expect(headings(reflow(page19, labelStyles: subheadStyles(page19))).contains("A Range of Resistance"))
    // Negative control: without the book's recurring style the line is no sub-heading, and its
    // text stays in the reading order as the bold paragraph it was before #159.
    let plain = reflow(page19)
    #expect(!headings(plain).contains("A Range of Resistance"))
    #expect(paragraphs(plain).contains { $0.contains("A Range of Resistance") })
    // Page 17 heads its third column `Sensing Trees’ Water Needs` and its second
    // `How Much Pressure Can a` / `Leaf Take?`, a title over two lines. Every one is a heading.
    let page17 = try usdaPage(17)
    let found = headings(reflow(page17, labelStyles: subheadStyles(page17)))
    #expect(found.contains("Sensing Trees’ Water Needs"))
    #expect(found.contains { $0.hasPrefix("How Much Pressure Can a") })
    #expect(found.contains { $0.hasPrefix("Leaf Take?") || $0.hasSuffix("Leaf Take?") })
}

@Test func aSubheadUnderTheBodySizeNeedsBoldAndAnIndentedParagraph() throws {
    let page = try usdaPage(19)
    let index = try #require(page.lines.firstIndex { $0.text == "A Range of Resistance" })
    let original = page.lines[index]
    let opening = try #require(page.lines.firstIndex { $0.text.hasPrefix("As part of the study") })
    let pageStyles = subheadStyles(page)
    func labels(_ changed: PageContent, styles: Set<LayoutReconstructor.LabelStyle>? = nil) -> [String] {
        LayoutReconstructor.sectionLabels(in: changed.lines, body: 11, headingThreshold: 13.75,
                                          page: changed, styles: styles ?? pageStyles).map(\.text)
    }
    #expect(labels(page).contains("A Range of Resistance"))
    // Plain and italic type, and a size below four fifths of the body, each with its own style
    // supplied: a smaller line is a title only in bold, and only within the sub-heading band.
    for replacement in [
        TextLine(text: "A Range of Resistance", rect: original.rect, fontSize: 9),
        TextLine(content: InlineText("A Range of Resistance", style: .italic), rect: original.rect, fontSize: 9),
        TextLine(content: InlineText("A Range of Resistance", style: .bold), rect: original.rect, fontSize: 7),
    ] {
        var changed = page
        changed.lines[index] = replacement
        #expect(!labels(changed, styles: pageStyles.union([LayoutReconstructor.LabelStyle(replacement, body: 11)]))
            .contains("A Range of Resistance"), "\(replacement.fontSize)")
    }
    // The paragraph beneath must open on the page's first-line indent: flush with the title, or
    // stepped further than the column ever steps, it is not this title's text.
    for shift in [CGFloat(-10), 30] {
        var changed = page
        changed.lines[opening].rect.origin.x += shift
        #expect(!labels(changed).contains("A Range of Resistance"), "\(shift)")
    }
    // And the title needs its space: set at the column's own leading it is a line of the column.
    let above = try #require(page.lines.first { $0.text == "water channel." })
    var crowded = page
    crowded.lines[index].rect.origin.y = above.rect.minY - original.rect.height + 1.3
    #expect(!labels(crowded).contains("A Range of Resistance"))
}

// MARK: - Photo credits

@Test func sourceCreditsReadBesideTheirPhotograph() throws {
    let page = try usdaPage(17)
    let blocks = reflow(page, labelStyles: subheadStyles(page))
    let shapes = shape(blocks)
    // `DONG WANG (D2686-1)` is set a point and a half over the upper photograph, and
    // `PEGGY GREB (D2680-1)` three points under the lower one: each reads against its own picture.
    for (credit, above) in [("DONG WANG (D2686-1)", true), ("PEGGY GREB (D2680-1)", false)] {
        let index = try #require(shapes.firstIndex { $0 == "paragraph:\(credit.prefix(24))" }, "\(credit) \(shapes)")
        let neighbour = above ? index + 1 : index - 1
        #expect(shapes.indices.contains(neighbour) && shapes[neighbour].hasPrefix("image:"), "\(credit) \(shapes)")
    }
}

@Test func aCreditSharingItsRowWithACaptionStaysInReadingOrder() throws {
    // Our Flag page 11 sets `“Old Ironsides” in the War of 1812.` and
    // `Courtesy U.S. Naval Academy Museum` on one row beneath the engraving, caption left and
    // credit right. The row reads left to right where it stands, so neither moves.
    let fixture = try SourceLayoutFixture.load("flag-11")
    #expect(fixture.sourceSHA256 == flagSHA256)
    let page = fixture.styledContent()
    let texts = shape(reflow(page)).filter { $0.hasPrefix("paragraph:“Old Ironsides") || $0.hasPrefix("paragraph:Courtesy U.S. Naval") }
    #expect(texts == ["paragraph:“Old Ironsides” in the W", "paragraph:Courtesy U.S. Naval Acad"])
}

@Test func onlyASmallTagAgainstAPicturesEdgeIsACredit() {
    // One picture, one credit and one paragraph, with the credit read before the picture. The
    // page also carries the column the magazine sets, so the credit is the smallest type on it.
    let picture = CGRect(x: 360, y: 54.6, width: 216, height: 270)
    func moved(_ credit: TextLine) -> Bool {
        var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                               lines: [credit], graphics: [picture])
        for index in 0..<3 {
            page.lines.append(TextLine(text: "Body line \(index) of the column.",
                                       rect: CGRect(x: 36, y: 700 - CGFloat(index) * 12.5, width: 172, height: 13.8),
                                       fontSize: 10.5))
        }
        var blocks = [ReflowBlock(content: .paragraph(credit.content), page: 1),
                      ReflowBlock(content: .paragraph(InlineText("Body line 0 of the column.")), page: 1),
                      LayoutReconstructor.imageBlock(assetID: "image-0", page: 1)]
        LayoutReconstructor.attachEdgeCredits(&blocks, page: page, images: [(picture, "image-0")], body: 10.5)
        return blocks.last.map { if case .paragraph = $0.content { $0.text == credit.text } else { false } } == true
    }
    let tag = TextLine(text: "PEGGY GREB (D2687-1)",
                       rect: CGRect(x: 517, y: 44.1, width: 58.4, height: 7.3), fontSize: 6)
    #expect(moved(tag))
    // Each control changes one thing: the body's own size, a line running more than half the
    // picture's width, a whole body of space between the line and the picture's edge, a line
    // reaching outside the picture's measure, and a raised note marker opening the line.
    #expect(!moved(TextLine(text: tag.text, rect: tag.rect, fontSize: 10.5)))
    #expect(!moved(TextLine(text: tag.text, rect: CGRect(x: 400, y: 44.1, width: 150, height: 7.3), fontSize: 6)))
    #expect(!moved(TextLine(text: tag.text, rect: tag.rect.offsetBy(dx: 0, dy: -8), fontSize: 6)))
    #expect(!moved(TextLine(text: tag.text, rect: tag.rect.offsetBy(dx: -200, dy: 0), fontSize: 6)))
    let note = InlineText(elements: [.text("1", .superscript), .text(" Source of the figure.", [])])
    #expect(!moved(TextLine(content: note, rect: tag.rect, fontSize: 6)))
    // A thin rule is no picture: the magazine's foot rule runs a point under the same credit.
    var ruled = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                            lines: [tag], graphics: [CGRect(x: 34.5, y: 39, width: 544, height: 4)])
    ruled.lines.append(TextLine(text: "Body line of the column.",
                                rect: CGRect(x: 36, y: 700, width: 172, height: 13.8), fontSize: 10.5))
    var blocks = [ReflowBlock(content: .paragraph(tag.content), page: 1),
                  LayoutReconstructor.imageBlock(assetID: "rule", page: 1)]
    let before = blocks.map(\.text)
    LayoutReconstructor.attachEdgeCredits(&blocks, page: ruled,
                                          images: [(CGRect(x: 34.5, y: 39, width: 544, height: 4), "rule")], body: 10.5)
    #expect(blocks.map(\.text) == before)
}
