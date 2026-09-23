import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// A page's tags cannot demote a heading the rest of the book's tags rank as one (#294). The
// book's tagged heading sizes are gathered in the extraction pass (`HeadingRank`), and a
// paragraph-tagged display line on a page whose tags name a heading takes the rank's level where
// the page's own tags state none for its size, unless it stands over a larger display line.

/// The sizes IRS Publication 596's tags call headings, read over the whole book by the survey
/// behind `measurements/document-wide-heading-rank/record.md`: eighteen and seventeen points
/// `H1` on six pages each and fourteen `H2` on five, every one reaching PDFKit as plain
/// `Helvetica`. Fifteen points is set on the cover alone.
private let irsRank = HeadingRank(tiers: [.init(size: 36, bold: false, level: 1),
                                          .init(size: 34, bold: false, level: 1),
                                          .init(size: 28, bold: false, level: 2)])

/// *The Fed Explained*'s, from the same survey: sixteen points `H3` on 26 pages, fourteen `H4`
/// on 49 and twelve `H5` on 7.
private let fedRank = HeadingRank(tiers: [.init(size: 32, bold: false, level: 3),
                                          .init(size: 28, bold: false, level: 4),
                                          .init(size: 24, bold: false, level: 5)])

private func headings(_ blocks: [ReflowBlock]) -> [(String, Int)] {
    blocks.compactMap { if case let .heading(_, _, level) = $0.content { ($0.text, level) } else { nil } }
}

private func words(_ blocks: [ReflowBlock]) -> Int {
    blocks.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
}

/// Gives a fixture page's lines the roles the source's structure tree gives them, found by
/// text; a group's `lineCount` is the number of its lines, as `MarkedTextReader` records it.
private func tag(_ content: inout PageContent, _ roles: [(text: String, group: Int, level: Int)]) throws {
    for (order, role) in roles.enumerated() {
        let index = try #require(content.lines.firstIndex { $0.text == role.text })
        content.lines[index].structure = TextStructure(group: role.group, order: order, headingLevel: role.level,
                                                       lineCount: roles.filter { $0.group == role.group }.count)
    }
}

private func blocks(_ page: PageContent, rank: HeadingRank = HeadingRank()) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, headingRank: rank)
}

// MARK: - The IRS cover

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func aParagraphTagOnALineTheBookRanksAsAHeadingYields() throws {
    var content = try SourceLayoutFixture.load("irs-1").content()
    let spatial = blocks(content)
    // By typography alone the cover's two fifteen-point lines are both headings over a
    // ten-point body.
    #expect(headings(spatial).map(\.0).contains("596 号刊物"))
    #expect(headings(spatial).map(\.0).contains("目录"))
    // The source's structure tree, as `tools/capture_tag_fixture.py` reads it: element 6169
    // (`P`) owns `596 号刊物`, 6171 (`P`) `目录` and 6225 (`H1`) `未来进展`; the title and the
    // contents entries reach no line. The page's tags name a heading, so every role they give is
    // believed, and nothing on the page says what fifteen points means: both are paragraphs,
    // which is #243.
    try tag(&content, [("596 号刊物", 1, 0), ("目录", 5, 0), ("未来进展", 37, 1)])
    let tagged = blocks(content)
    #expect(!headings(tagged).map(\.0).contains("目录"))
    #expect(!headings(tagged).map(\.0).contains("596 号刊物"))
    #expect(headings(tagged).contains { $0 == ("未来进展", 1) })
    // The book ranks fifteen points between its fourteen-point `H2` and its seventeen-point
    // `H1`, so `目录` takes the `H2` level, and nothing else moves: not a heading, not a word.
    let ranked = blocks(content, rank: irsRank)
    #expect(headings(ranked).contains { $0 == ("目录", 2) })
    #expect(!headings(ranked).map(\.0).contains("596 号刊物"))
    #expect(headings(ranked).count == headings(tagged).count + 1)
    #expect(Set(headings(ranked).map(\.0)) == Set(headings(tagged).map(\.0)).union(["目录"]))
    #expect(words(ranked) == words(tagged) && words(tagged) == words(spatial))
    // The rank says the same of both fifteen-point lines; what separates them is what each
    // stands over: `596 号刊物` the thirty-one-point title, `目录` the contents entries.
    let masthead = try #require(content.lines.first { $0.text == "596 号刊物" })
    let contents = try #require(content.lines.first { $0.text == "目录" })
    #expect(irsRank.level(of: masthead) == 2 && irsRank.level(of: contents) == 2)
    #expect(LayoutReconstructor.standsOverLargerDisplay(masthead, among: content.lines))
    #expect(!LayoutReconstructor.standsOverLargerDisplay(contents, among: content.lines))
}

// MARK: - Controls on real pages

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func aSeriesNameStandingOverTheTitleKeepsItsParagraphTag() throws {
    var content = try SourceLayoutFixture.load("fed-1").content()
    // Elements 4413 and 4414 (`P`) own the publication line and the series name; 4417 (`H1`)
    // owns the title's two spans.
    try tag(&content, [("PUBLIC EDUCATION & OUTREACH", 1, 0), ("The Fed Explained", 2, 1),
                       ("What the Central Bank Does", 2, 1), ("FEDERAL RESERVE SYSTEM PUBLICATION", 3, 0)])
    let label = try #require(content.lines.first { $0.text == "PUBLIC EDUCATION & OUTREACH" })
    // Fourteen points is the book's `H4` on forty-nine pages, so the rank has an opinion, and
    // the line stands over the forty-point title, so the rank is not asked.
    #expect(fedRank.level(of: label) == 4)
    #expect(LayoutReconstructor.standsOverLargerDisplay(label, among: content.lines))
    for rank in [HeadingRank(), fedRank] {
        let reflowed = blocks(content, rank: rank)
        #expect(headings(reflowed).map(\.1) == [1])
        #expect(headings(reflowed).first?.0.hasPrefix("The Fed Explained") == true)
        #expect(paragraphTexts(reflowed).contains("PUBLIC EDUCATION & OUTREACH"))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func aPageWhoseOwnTagsStateTheSizeStillDecidesForItself() throws {
    // Fed page 21 is the per-page contradiction (`contradicted-heading-tags`): the page's own
    // `H4` at fourteen points keeps "Advisory Councils", and the book's rank changes nothing
    // about it, because the page's own tags are read first.
    let fixture = try SourceTagFixture.load("fed-21")
    var content = try SourceLayoutFixture.load("fed-21").content()
    try fixture.withPage { url, page in
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(MarkedTextReader.apply(tags, page: page, lines: &content.lines))
    }
    let expected = ["FOMC Responsibilities", "Other Significant Entities Contributing to Federal Reserve Functions",
                    "Depository Institutions", "Advisory Councils"]
    let alone = blocks(content)
    let ranked = blocks(content, rank: fedRank)
    #expect(headings(alone).map(\.0) == expected && headings(ranked).map(\.0) == expected)
    #expect(headings(alone).map(\.1) == [4, 3, 4, 4] && headings(ranked).map(\.1) == [4, 3, 4, 4])
    #expect(words(alone) == words(ranked))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func aPageWhoseTagsNameNoHeadingIsNotAskedTheRank() throws {
    // The FAA handbook's RoleMap sends every heading style to `P`, so no page of it states a
    // heading and its rank is empty; that page's display lines keep the reading its typography
    // gives them (#67), and a rank with an opinion on their size changes nothing there either,
    // because the rule for a page whose tags name no heading decides before the rank is asked.
    let fixture = try SourceTagFixture.load("faa-81")
    let native = try SourceLayoutFixture.load("faa-81")
    var content = native.content()
    for i in content.lines.indices {
        if let source = native.attributedLines.first(where: {
            $0.text.trimmingCharacters(in: .whitespaces) == content.lines[i].text.trimmingCharacters(in: .whitespaces)
        }) {
            let line = content.lines[i]
            content.lines[i] = TextLine(content: NativeTextReader.inlineText(from: source.attributedString()),
                                        rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
        }
    }
    let body = LayoutReconstructor.bodySize(content.lines)
    let labels = Set(["Advantages of Composites", "Disadvantages of Composites"].compactMap { text in
        content.lines.first { $0.text == text }.map { LayoutReconstructor.LabelStyle($0, body: body) }
    })
    try fixture.withPage { url, page in
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(tags.values.allSatisfy { $0.headingLevel == 0 })
        #expect(MarkedTextReader.apply(tags, page: page, lines: &content.lines))
    }
    var tally = HeadingRank.Tally()
    tally.record(content, pageIndex: 80)
    #expect(HeadingRank(tally).tiers.isEmpty)
    let label = try #require(content.lines.first { $0.text == "Advantages of Composites" })
    let opinionated = HeadingRank(tiers: [.init(size: LayoutReconstructor.sizeKey(label.fontSize),
                                                bold: LayoutReconstructor.readsWhollyBold(label), level: 3)])
    #expect(opinionated.level(of: label) == 3)
    for rank in [HeadingRank(), opinionated] {
        var warnings: [ConversionWarning] = []
        let reflowed = LayoutReconstructor.blocks(page: content, images: [], vocabulary: [], warnings: &warnings,
                                                  labelStyles: labels, headingRank: rank)
        #expect(headingTexts(reflowed) == ["Advantages of Composites", "Disadvantages of Composites"])
    }
}

// MARK: - The rank itself

private func headedPage(_ number: Int, heading: String, size: CGFloat, level: Int, bold: Bool = false,
                        bodySize: CGFloat = 10) -> PageContent {
    var lines = (0..<8).map { i in
        TextLine(text: "Body prose that establishes the page's own size in enough characters to count.",
                 rect: CGRect(x: 40, y: 600 - CGFloat(i) * 14, width: 400, height: 12), fontSize: bodySize)
    }
    var title = TextLine(content: InlineText(heading, style: bold ? [.bold] : []),
                         rect: CGRect(x: 40, y: 700, width: 200, height: size * 1.2), fontSize: size)
    title.structure = TextStructure(group: 1, order: 0, headingLevel: level, lineCount: 1)
    lines.insert(title, at: 0)
    return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func aSizeRanksOnceThreePagesTagItAHeadingAtTheLevelTheyGiveItMostOften() {
    var tally = HeadingRank.Tally()
    tally.record(headedPage(1, heading: "One", size: 16, level: 2), pageIndex: 0)
    tally.record(headedPage(2, heading: "Two", size: 16, level: 2), pageIndex: 1)
    #expect(HeadingRank(tally).tiers.isEmpty)
    tally.record(headedPage(3, heading: "Three", size: 16, level: 3), pageIndex: 2)
    #expect(HeadingRank(tally).tiers == [.init(size: 32, bold: false, level: 2)])
    // Levels given equally often rank at the shallower.
    tally.record(headedPage(4, heading: "Four", size: 16, level: 3), pageIndex: 3)
    #expect(HeadingRank(tally).tiers == [.init(size: 32, bold: false, level: 2)])
    tally.record(headedPage(5, heading: "Five", size: 16, level: 3), pageIndex: 4)
    #expect(HeadingRank(tally).tiers == [.init(size: 32, bold: false, level: 3)])
    // A page counts once however many headings it sets, and a second size ranks on its own
    // pages, largest first.
    for page in 6...8 {
        tally.record(headedPage(page, heading: "Big", size: 24, level: 1), pageIndex: page - 1)
        tally.record(headedPage(page, heading: "Big again", size: 24, level: 1), pageIndex: page - 1)
    }
    #expect(HeadingRank(tally).tiers == [.init(size: 48, bold: false, level: 1), .init(size: 32, bold: false, level: 3)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func aTaggedHeadingSetAtTheBodySizeStatesNoDisplaySize() {
    // Our Flag tags nine-point lines `H` on two pages where nine is the body; its imprint is set
    // in nine, and must not find a tier waiting for it.
    var tally = HeadingRank.Tally()
    for page in 1...4 { tally.record(headedPage(page, heading: "Small", size: 10, level: 3), pageIndex: page - 1) }
    #expect(HeadingRank(tally).tiers.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func theRankSpeaksAtOrAboveItsFloorAndToTheWeightItRanked() {
    let rank = HeadingRank(tiers: [.init(size: 36, bold: false, level: 1), .init(size: 28, bold: false, level: 2),
                                   .init(size: 29, bold: true, level: 4)])
    func line(_ size: CGFloat, bold: Bool = false) -> TextLine {
        TextLine(content: InlineText("Title", style: bold ? [.bold] : []),
                 rect: CGRect(x: 40, y: 700, width: 100, height: size), fontSize: size)
    }
    #expect(rank.tiers.map(\.size) == [36, 29, 28])
    #expect(rank.level(of: line(13.5)) == nil)
    #expect(rank.level(of: line(14)) == 2)
    #expect(rank.level(of: line(15)) == 2)
    #expect(rank.level(of: line(18)) == 1)
    #expect(rank.level(of: line(30)) == 1)
    #expect(rank.level(of: line(14, bold: true)) == nil)
    #expect(rank.level(of: line(15, bold: true)) == 4)
    #expect(HeadingRank().level(of: line(30)) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/294")) func theRankPromotesOnlyOnAPageWhoseTagsNameAHeadingAndNeverALabelOverATitle() {
    func element(_ text: String, size: CGFloat, y: CGFloat, group: Int, level: Int) -> LayoutReconstructor.Element {
        var line = TextLine(text: text, rect: CGRect(x: 40, y: y, width: 300, height: size * 1.2), fontSize: size)
        line.structure = .init(group: group, order: group, headingLevel: level, lineCount: 1)
        return .init(rect: line.rect, line: line)
    }
    let rank = HeadingRank(tiers: [.init(size: 36, bold: false, level: 1), .init(size: 28, bold: false, level: 3)])
    // Sixteen points is a size no tag on this page calls a heading, and the book ranks it
    // beneath its eighteen-point `H1`; the twelve-point imprint line is under the floor.
    let page = [element("Chapter Title", size: 18, y: 700, group: 1, level: 1),
                element("A Section", size: 16, y: 640, group: 2, level: 0),
                element("Washington : 2003", size: 12, y: 600, group: 3, level: 0),
                element("The prose the section heads.", size: 10, y: 560, group: 4, level: 0)]
    let roles: [LineRole?] = [.heading, .heading, .heading, .prose]
    #expect(LayoutReconstructor.contradictedHeadingGroups(page, roles: roles).isEmpty)
    #expect(LayoutReconstructor.contradictedHeadingGroups(page, roles: roles, rank: rank) == [2: 3])
    // The same section, tagged a paragraph, on a page whose tags name no heading: the rule for
    // such a page decides, and the rank is never asked.
    let untagged = [element("A Section", size: 16, y: 640, group: 2, level: 0),
                    element("The prose the section heads.", size: 10, y: 560, group: 4, level: 0)]
    #expect(LayoutReconstructor.contradictedHeadingGroups(untagged, roles: [.heading, .prose], rank: rank).isEmpty)
    // A sixteen-point line standing over a thirty-point title is a label, and keeps its tag.
    let cover = [element("Chapter Title", size: 18, y: 700, group: 1, level: 1),
                 element("Series Name", size: 16, y: 640, group: 2, level: 0),
                 element("The Title", size: 30, y: 590, group: 3, level: 0)]
    #expect(LayoutReconstructor.contradictedHeadingGroups(cover, roles: [.heading, .heading, .heading], rank: rank) == [3: 1])
    // One line of a group set as prose still refuses the whole group.
    let mixed = [element("Chapter Title", size: 18, y: 700, group: 1, level: 1),
                 element("A Section", size: 16, y: 640, group: 2, level: 0),
                 element("that wraps into prose", size: 16, y: 620, group: 2, level: 0)]
    #expect(LayoutReconstructor.contradictedHeadingGroups(mixed, roles: [.heading, .heading, .prose], rank: rank).isEmpty)
}
