import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Ordinary text that opens with a number, a year or an initial read as a preformatted list item
// (#146), and a Word paper's numbered section titles and heading-tagged references (#154).
// Fixtures are native extraction from checksum-pinned sources; every expected phrase was read
// against the rendered pages, not converter output.

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"
private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"
private let ntrsSHA256 = "a98e4fcdea40b8ea7023880dd88966f04198b4ec311fced0bb9ebb2dec45fe6d"
private let flagSHA256 = "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8"

private func page(_ name: String, _ sha256: String, styled: Bool = false) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256)
    return styled ? fixture.styledContent() : fixture.content()
}

private func reconstruct(_ page: PageContent, neighbours: [PageContent] = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
        neighbouringMarkers: neighbours.flatMap(LayoutReconstructor.listMarkers(on:)))
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { $0.text } else { nil } }
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

/// A line standing for a marker the neighbouring page prints, at the given type size.
private func neighbour(_ text: String, size: CGFloat) -> PageContent {
    PageContent(number: 0, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                lines: [TextLine(text: text, rect: CGRect(x: 60, y: 400, width: 300, height: size), fontSize: size)], graphics: [])
}

// MARK: A lonely marker continues the open sentence

// Fed page 92's ragged column: `…since the Federal Reserve was established in` / `1913. At that
// time, cash and checks…`. No other marker on the page continues `1913.`.
@Test func yearAfterAnOpenRaggedLineContinuesItsParagraph() throws {
    let fed = try page("fed-92", fedSHA256)
    let blocks = reconstruct(fed)
    #expect(paragraphs(blocks).contains { $0.contains("the Federal Reserve was established in 1913. At that time, cash and checks") })
    #expect(!preformatted(blocks).contains { $0.hasPrefix("1913.") })
    // Negative control: a neighbouring page's `1912.` item makes `1913.` part of a list again.
    let listed = reconstruct(fed, neighbours: [neighbour("1912. An earlier item", size: 10)])
    #expect(preformatted(listed).contains { $0.hasPrefix("1913. At that time") })
    // A marker in other type is no sibling.
    let unrelated = reconstruct(fed, neighbours: [neighbour("1912. An earlier item", size: 14)])
    #expect(!preformatted(unrelated).contains { $0.hasPrefix("1913.") })
}

// 9/11 page 179: `…he and Atta first met at a mosque in Hamburg in` / `1995. The two men…`. The
// column's measure ends at 356.6 points, but five lines stand at 359.5. The styled page carries the
// raised note marker (`1998.67`) that sets the indented opening line above apart.
@Test func yearInAJustifiedColumnContinuesItsParagraph() throws {
    let blocks = reconstruct(try page("911-179", gpo911SHA256, styled: true))
    #expect(paragraphs(blocks).contains { $0.contains("met at a mosque in Hamburg in 1995. The two men became close friends") })
    #expect(preformatted(blocks).isEmpty)
}

// The justified test reads the edge most lines share, so a marker another marker continues still
// joins prose whose previous line fills that edge, while a few lines standing past it do not raise
// the edge out of reach.
@Test func justifiedEdgeIsTheSharedEdgeNotTheFurthestLine() {
    func line(_ text: String, _ index: Int, width: Double, x: Double = 60) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: 700 - Double(index) * 14, width: width, height: 12), fontSize: 12)
    }
    var lines = [
        line("Justified prose that runs the whole measure of its column and continues onto", 0, width: 460),
        line("the next line, which also reaches the measure, as does the following one by", 1, width: 460),
        line("the committee, whose report was accepted in the session that ended on June", 2, width: 460),
        line("2. The committee then adjourned, and a further line runs past the measure.", 3, width: 464),
        line("And this line also stands a few points past the shared edge of the column.", 4, width: 464),
        line("A closing short line.", 5, width: 140),
    ]
    // A real list elsewhere on the page gives `2.` siblings, so only the edge test can join it.
    lines.append(line("1. First item of a separate list", 8, width: 200))
    lines.append(line("3. Third item of that list", 9, width: 180))
    lines[6].rect.origin.y -= 40
    lines[7].rect.origin.y -= 40
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    let blocks = reconstruct(page)
    #expect(paragraphs(blocks).contains { $0.contains("ended on June 2. The committee then adjourned") })
    #expect(preformatted(blocks) == ["1. First item of a separate list", "3. Third item of that list"])
    // Negative control: the line before `2.` stops short of the shared edge; the item stays a list item.
    var short = page
    short.lines[2].rect.size.width = 400
    #expect(preformatted(reconstruct(short)).contains { $0.hasPrefix("2. The committee") })
}

// MARK: A lonely marker opens a paragraph that runs on flush

// 9/11 page 288: `2000. They decided that if Mihdhar was in the United States, he should be` /
// `found.75 They divided up the work.` on the same left edge.
@Test func yearOpeningAFlushParagraphIsNoListItem() throws {
    let blocks = reconstruct(try page("911-288", gpo911SHA256))
    #expect(paragraphs(blocks).contains { $0.contains("2000. They decided that if Mihdhar was in the United States, he should be found.") })
    #expect(preformatted(blocks).isEmpty)
}

// FAA page 18: `P. E. Fansler, a Florida businessman living in St. Petersburg,` opens a paragraph
// after space and wraps onto `approached Tom Benoist…` at the column edge.
@Test func initialsOpeningAParagraphAreNoListMarker() throws {
    let faa = try page("faa-18", faaSHA256)
    let blocks = reconstruct(faa)
    #expect(paragraphs(blocks).contains { $0.hasPrefix("P. E. Fansler, a Florida businessman living in St. Petersburg, approached Tom Benoist") })
    #expect(!preformatted(blocks).contains { $0.hasPrefix("P.") })
    // Negative control: `O.` and `Q.` on the neighbouring pages make `P.` a lettered item.
    let lettered = reconstruct(faa, neighbours: [neighbour("O. An earlier item", size: 10)])
    #expect(preformatted(lettered).contains { $0.hasPrefix("P. E. Fansler") })
}

// 9/11 pages 146–147: the Presidential Daily Brief's items `1.` (page 146) and `2.`, `3.` (page 147)
// wrap flush like paragraphs. The next page's markers keep `1.` a list item.
@Test func aListBrokenByThePageKeepsItsFirstItem() throws {
    let current = try page("911-146", gpo911SHA256)
    let next = try page("911-147", gpo911SHA256)
    let listed = reconstruct(current, neighbours: [next])
    #expect(preformatted(listed).contains { $0.hasPrefix("1. Reporting [—] suggests Bin Ladin") })
    // Negative control: without the next page the item has no sibling and reads as a paragraph.
    let alone = reconstruct(current)
    #expect(!preformatted(alone).contains { $0.hasPrefix("1. Reporting") })
    #expect(paragraphs(alone).contains { $0.hasPrefix("1. Reporting [—] suggests Bin Ladin") })
}

@Test func markerValuesAndSiblings() throws {
    let twelve = try #require(LayoutReconstructor.ListMarker("12. Text"))
    #expect(twelve.isSibling(of: try #require(LayoutReconstructor.ListMarker("13. More"))))
    #expect(twelve.isSibling(of: try #require(LayoutReconstructor.ListMarker("14. More"))))
    #expect(!twelve.isSibling(of: try #require(LayoutReconstructor.ListMarker("15. More"))))
    #expect(!twelve.isSibling(of: try #require(LayoutReconstructor.ListMarker("11) More"))))
    #expect(!twelve.isSibling(of: twelve))
    let b = try #require(LayoutReconstructor.ListMarker("b) item"))
    #expect(b.isSibling(of: try #require(LayoutReconstructor.ListMarker("a) item"))))
    #expect(!b.isSibling(of: try #require(LayoutReconstructor.ListMarker("A) item"))))
    // Bullets, tight answer markers, decimals and unspaced markers carry no marker.
    for text in ["• bullet", "1)− 2", "3.5 percent", "10.August 2001", "Plain text"] {
        #expect(LayoutReconstructor.ListMarker(text) == nil, Comment(rawValue: text))
    }
}

// MARK: Numbered section titles and heading tags (#154)

// NASA Word paper page 2: `2. TEST DESCRIPTION`, 12-point bold capitals over 10-point prose.
@Test func numberedSectionTitleIsAHeading() throws {
    let blocks = reconstruct(try page("ntrs-2", ntrsSHA256, styled: true))
    #expect(headings(blocks).contains("2. TEST DESCRIPTION"))
    #expect(!preformatted(blocks).contains { $0.hasPrefix("2. TEST") })
}

// 9/11 page 7, the contents: `11. FORESIGHT—AND HINDSIGHT` and `13. HOW TO DO IT? A DIFFERENT WAY
// OF` set their folios on the next line, but `10.` and `12.` continue their numbers.
@Test func numberedContentsEntriesAreNoHeadings() throws {
    let blocks = reconstruct(try page("911-7", gpo911SHA256, styled: true))
    #expect(!headings(blocks).contains { $0.hasPrefix("11.") || $0.hasPrefix("13.") })
    #expect(preformatted(blocks).contains { $0.hasPrefix("11. FORESIGHT") })
}

@Test func numberedTitleNeedsCapitalsOrBold() {
    func line(_ text: String, bold: Bool = false) -> TextLine {
        var value = TextLine(text: text, rect: CGRect(x: 60, y: 600, width: 200, height: 13), fontSize: 12)
        value.replaceContent(InlineText(text, style: bold ? .bold : []))
        return value
    }
    #expect(LayoutReconstructor.isNumberedTitle(line("2. TEST DESCRIPTION"), body: 10))
    #expect(LayoutReconstructor.isNumberedTitle(line("3. Quantum Description", bold: true), body: 10))
    #expect(!LayoutReconstructor.isNumberedTitle(line("3. Quantum Description"), body: 10))
    #expect(!LayoutReconstructor.isNumberedTitle(line("1) 6p− 42"), body: 10))
    #expect(!LayoutReconstructor.isNumberedTitle(line("1995. THE YEAR"), body: 10))
    #expect(!LayoutReconstructor.isNumberedTitle(line("1. “WE HAVE SOME PLANES” 1"), body: 10))
}

// NASA Word paper page 19 tags eight references, a DOI line and a wrapped reference line `H1`,
// in the references' 9-point type.
@Test func headingTagOnReferenceTextIsAParagraph() throws {
    let ntrs = try page("ntrs-19", ntrsSHA256, styled: true)
    let tagged = ntrs.lines.filter { ($0.structure?.headingLevel ?? 0) > 0 }.map(\.text)
    #expect(tagged.contains { $0.hasPrefix("[16] NASA Space Vehicle Design Criteria") })
    #expect(tagged.contains("doi: 10.1016/j.measurement.2016.05.078"))
    let blocks = reconstruct(ntrs)
    #expect(!headings(blocks).contains { $0.hasPrefix("[") || $0.hasPrefix("doi:") || $0.hasPrefix("Capabilities to Serve") })
    #expect(paragraphs(blocks).contains("[16] NASA Space Vehicle Design Criteria, Prelaunch Ground Wind Loads, NASA SP-8008, November 1965."))
    // Negative control: without the page's paragraph-tagged references in the same type, the tags
    // stand.
    var alone = ntrs
    alone.lines.removeAll { $0.structure?.headingLevel == 0 }
    #expect(headings(reconstruct(alone)).contains { $0.hasPrefix("[16] NASA Space Vehicle Design Criteria") })
}

// Our Flag page 18: body-size `§174. Time and occasions for display`, tagged as a heading, closes no
// sentence and stays one.
@Test func bodySizeTaggedTitleStaysAHeading() throws {
    let flag = try page("flag-18", flagSHA256, styled: true)
    #expect(flag.lines.contains { $0.text.hasPrefix("§174.") && ($0.structure?.headingLevel ?? 0) > 0 })
    let blocks = reconstruct(flag)
    #expect(headings(blocks).contains { $0.hasPrefix("§174. Time and occasions for display") })
    // Negative control: the same title given a closing period reads as a sentence.
    var sentence = flag
    for index in sentence.lines.indices where sentence.lines[index].text.hasPrefix("§174.") {
        let text = sentence.lines[index].text + " is governed by the provisions set out in this section."
        sentence.lines[index].replaceContent(InlineText(text))
    }
    #expect(!headings(reconstruct(sentence)).contains { $0.hasPrefix("§174.") })
}
