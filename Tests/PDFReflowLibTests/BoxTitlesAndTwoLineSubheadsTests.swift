import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #100: the Fed's narrow sidebars open with an 8-point demibold title over 8-point text; PDFKit
// names both fonts `Helvetica`, so only the box's spacing sets the title apart, and every such
// title ran into the box's first paragraph. #102: the FAA handbook's untagged sub-headings set over
// two lines in a recurring bold style ran into their paragraph, and page 6's contents entries
// `A = Aircraft` and `V = EnVironment` seeded a formula crop. Fixtures are captured from the
// checksum-pinned sources; expected text was read against rendered pages.

private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"
private let reportSHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func page(_ name: String) throws -> PageContent {
    try SourceLayoutFixture.load(name).styledContent()
}

private func reflow(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                      vocabulary: [], warnings: &warnings, labelStyles: labelStyles)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

/// The block after the heading `title`, which must exist.
private func opening(after title: String, in blocks: [ReflowBlock]) throws -> String {
    let index = try #require(blocks.firstIndex { if case .heading = $0.content { $0.text == title } else { false } },
                             "no heading \(title) in \(headings(blocks))")
    return try #require(blocks.indices.contains(index + 1) ? blocks[index + 1].text : nil)
}

private func words(_ blocks: [ReflowBlock]) -> String {
    blocks.map(\.text).joined().filter { !$0.isWhitespace }
}

// MARK: - #100 box titles

@Test func fedSidebarTitleOnPage27OpensItsBox() throws {
    for name in ["fed-27-tagged", "fed-63-tagged"] { #expect(try SourceLayoutFixture.load(name).sourceSHA256 == fedSHA256) }
    let page27 = try page("fed-27-tagged")
    let blocks = reflow(page27)
    let title = "A fresh look at the monetary policy framework"
    #expect(try opening(after: title, in: blocks).hasPrefix("In 2019, the Fed launched a comprehensive"))
    #expect(!blocks.contains { $0.text.hasPrefix(title + " In 2019") })
    #expect(blocks.first { $0.text == title }?.headingSize == 8)
    // The defect: set in the box's text size with no bold run, the title is neither heading size
    // nor a section label, so only the box title rule separates it (the page's body is 10 points).
    let line = try #require(page27.lines.first { $0.text == title })
    #expect(line.fontSize < 10 && !LayoutReconstructor.LabelStyle(line, body: 10).bold)
    #expect(!LayoutReconstructor.sectionLabels(in: page27.lines, body: 10, headingThreshold: 12.5, page: page27,
                                               recordingSubheadings: true).contains(line))
    #expect(LayoutReconstructor.boxTitles(in: page27.lines, page: page27) == [line])
    // Without a tint there is no box and no box title.
    var untinted = page27
    untinted.tints = []
    #expect(LayoutReconstructor.boxTitles(in: untinted.lines, page: untinted).isEmpty)
}

@Test func fedSidebarTitlesOnOneOrTwoLinesAreHeadings() throws {
    for (name, cases) in [
        ("fed-22", [("More on Federal Reserve Advisory Councils", "For a current roster of Federal Reserve advisory")]),
        ("fed-36", [("Clear usage of forward guidance", "In 2008, the FOMC lowered the target range"),
                    ("Unprecedented actions to foster maximum employment and stable prices", "The Federal Reserve responded aggressively")]),
        ("fed-37", [("Large-Scale Asset Purchase (LSAP) programs supported credit for households and businesses",
                     "From the end of 2008 through October 2014")]),
        ("fed-63-tagged", [("Regular reporting on FSOC activities", "The Financial Stability Oversight Council (FSOC) meets"),
                           ("Central banks around the world", "The central bank concept dates to 1668")]),
    ] {
        let blocks = reflow(try page(name))
        for (title, text) in cases {
            #expect(try opening(after: title, in: blocks).hasPrefix(text), "\(name): \(title)")
        }
    }
}

@Test func boxTitleNeedsSpaceBeneathItsEdgeAndNoSentenceEnd() throws {
    // Page 63's second box breaks its paragraphs with the same space a title sets, but its first
    // paragraph ends a sentence: only the two titles are titles.
    let page63 = try page("fed-63-tagged")
    #expect(LayoutReconstructor.boxTitles(in: page63.lines, page: page63).map(\.text)
        == ["Regular reporting on FSOC activities", "Central banks around the world"])
    // The 9/11 report's page 348 sidebar: a two-line paragraph ending in a note marker over a
    // paragraph set on a first-line indent is no title.
    let report = try SourceLayoutFixture.load("911-348")
    #expect(report.sourceSHA256 == reportSHA256)
    let page348 = report.styledContent()
    #expect(!page348.tints.isEmpty)
    #expect(LayoutReconstructor.boxTitles(in: page348.lines, page: page348).isEmpty)
    let blocks348 = reflow(page348)
    #expect(!headings(blocks348).contains { $0.hasPrefix("FBI was aware") })
    // Neither line is a title, and the indent that proves it also opens the second paragraph: the
    // source ends `…allowed to depart.30` short of the measure and sets `The FBI interviewed…` one
    // em in, over lines that return to the box's edge (#159). Both paragraphs stay paragraphs, and
    // the first keeps its own two lines rather than swallowing the second.
    let sidebar = blocks348.filter { $0.text.hasPrefix("FBI was aware of the flights")
        || $0.text.hasPrefix("The FBI interviewed all persons") }
    #expect(sidebar.count == 2)
    #expect(sidebar.allSatisfy { if case .paragraph = $0.content { true } else { false } })
    #expect(sidebar.first?.text.hasSuffix("allowed to depart.30") == true)
    #expect(sidebar.last?.text.hasSuffix("on these flights.31") == true)
    // A box title at heading size is a heading already (Box 3.1) and is no box title here.
    let page32 = try page("fed-32")
    #expect(LayoutReconstructor.boxTitles(in: page32.lines, page: page32).isEmpty)
    #expect(headings(reflow(page32)).contains("Box 3.1. What Happens at an FOMC Meeting"))

    let page27 = try page("fed-27-tagged")
    let title = "A fresh look at the monetary policy framework"
    func titles(_ changed: PageContent) -> [String] { LayoutReconstructor.boxTitles(in: changed.lines, page: changed).map(\.text) }
    #expect(titles(page27) == [title])
    let index = try #require(page27.lines.firstIndex { $0.text == title })
    let beneath = try #require(page27.lines.firstIndex { $0.text.hasPrefix("In 2019, the Fed launched") })
    // Set at the box's own leading, the line is the paragraph's first line.
    var crowded = page27
    crowded.lines[index].rect.origin.y -= 3.6
    #expect(titles(crowded).isEmpty)
    // Sentence punctuation, a lowercase opening, and a list marker.
    for text in [title + ".", "a fresh look at the monetary policy framework", "• A fresh look at the monetary policy framework"] {
        var changed = page27
        changed.lines[index] = TextLine(text: text, rect: changed.lines[index].rect, fontSize: 8)
        #expect(titles(changed).isEmpty, "\(text)")
    }
    // The line beneath indented off the title's edge, or at another size.
    var indented = page27
    indented.lines[beneath].rect.origin.x += 12
    #expect(titles(indented).isEmpty)
    var larger = page27
    larger.lines[beneath].fontSize = 10
    #expect(titles(larger).isEmpty)
    // The title may outrun the ragged line beneath it (page 19), but not the box's measure.
    var ragged = page27
    ragged.lines[beneath].rect.size.width = 150
    #expect(titles(ragged) == [title])
    var wide = page27
    wide.lines[index].rect.size.width = 205
    #expect(titles(wide).isEmpty)
    // A two-line title keeps its lines at the box's leading or tighter (page 37's LSAP title).
    let page37 = try page("fed-37")
    let pair = ["Large-Scale Asset Purchase (LSAP) programs", "supported credit for households and businesses"]
    #expect(LayoutReconstructor.boxTitles(in: page37.lines, page: page37).map(\.text) == pair)
    var spread = page37
    let upper = try #require(page37.lines.firstIndex { $0.text == pair[0] })
    spread.lines[upper].rect.origin.y += 6
    #expect(LayoutReconstructor.boxTitles(in: spread.lines, page: spread).isEmpty)
    // Recognized and synthetic pages have no sizes to trust.
    var recognized = page27
    recognized.recognized = true
    #expect(titles(recognized).isEmpty)
    var synthetic = page27
    synthetic.hasSyntheticTextStyle = true
    #expect(titles(synthetic).isEmpty)
}

// MARK: - #102 two-line sub-headings

/// FAA's recurring sub-heading styles (#76): 10-point bold and 11-point bold italic over 10-point body.
private func faaStyle(_ size: CGFloat, italic: Bool = false, bold: Bool = true) -> LayoutReconstructor.LabelStyle {
    var style: TextStyle = []
    if bold { style.insert(.bold) }
    if italic { style.insert(.italic) }
    let line = TextLine(content: InlineText("Radius of Turn", style: style), rect: CGRect(x: 0, y: 0, width: 70, height: 13), fontSize: size)
    return LayoutReconstructor.LabelStyle(line, body: 10)
}

private let faaStyles: Set<LayoutReconstructor.LabelStyle> = [faaStyle(10), faaStyle(11, italic: true), faaStyle(10, italic: true, bold: false)]

@Test func faaTwoLineBoldSubheadingsAreOneHeading() throws {
    // Page 404's pair runs into its untagged paragraph; page 21's paragraph is tagged, so the pair
    // stayed apart but as a paragraph.
    for (name, first, second, text, runsIn) in [
        ("faa-21-tagged", "The Professional Air Traffic Controllers", "Organization (PATCO) Strike", "While preparing the NAS Plan, the FAA faced a strike", false),
        ("faa-404-tagged", "Use of Chart Supplement U.S. (formerly Airport/", "Facility Directory)", "Study available information about each airport", true),
    ] {
        #expect(try SourceLayoutFixture.load(name).sourceSHA256 == faaSHA256)
        let source = try page(name)
        let title = first + (first.hasSuffix("/") ? "" : " ") + second
        let blocks = reflow(source, labelStyles: faaStyles)
        #expect(try opening(after: title, in: blocks).hasPrefix(text), "\(name)")
        // Without the book's style both lines run into the paragraph, as before.
        let plain = reflow(source)
        #expect(!headings(plain).contains(title))
        #expect(plain.contains { runsIn ? $0.text.hasPrefix(title + " " + text) : $0.text == title && $0.headingSize == nil },
                "\(name) as before")
        #expect(words(blocks) == words(plain))
        // A pair is no style evidence of its own.
        let recorded = LayoutReconstructor.sectionLabels(in: source.lines, body: 10, headingThreshold: 12.5, page: source,
                                                         recordingSubheadings: true).map(\.text)
        #expect(!recorded.contains(first) && !recorded.contains(second))
    }
}

@Test func twoLineSubheadingNeedsOneStyleStackedOverItsParagraph() throws {
    let source = try page("faa-21-tagged")
    let first = try #require(source.lines.firstIndex { $0.text == "The Professional Air Traffic Controllers" })
    let second = try #require(source.lines.firstIndex { $0.text == "Organization (PATCO) Strike" })
    let body = try #require(source.lines.firstIndex { $0.text.hasPrefix("While preparing the NAS Plan") })
    func labels(_ page: PageContent, styles: Set<LayoutReconstructor.LabelStyle> = faaStyles) -> [String] {
        LayoutReconstructor.sectionLabels(in: page.lines, body: 10, headingThreshold: 12.5, page: page, styles: styles).map(\.text)
    }
    func replaced(_ index: Int, _ text: String, style: TextStyle, dx: CGFloat = 0, dy: CGFloat = 0, size: CGFloat = 10) -> PageContent {
        var changed = source
        changed.lines[index] = TextLine(content: InlineText(text, style: style),
                                        rect: source.lines[index].rect.offsetBy(dx: dx, dy: dy), fontSize: size)
        return changed
    }
    let pair = ["The Professional Air Traffic Controllers", "Organization (PATCO) Strike"]
    #expect(labels(source).filter(pair.contains) == pair)
    // Only a style the book repeats.
    #expect(labels(source, styles: [faaStyle(11, italic: true)]).filter(pair.contains).isEmpty)
    for (changed, note) in [
        (replaced(second, "Organization (PATCO) Strike.", style: .bold), "sentence end"),
        (replaced(second, "Organization (PATCO) Strike", style: []), "plain second line"),
        (replaced(second, "Organization (PATCO) Strike", style: .italic), "another style"),
        (replaced(second, "Organization (PATCO) Strike", style: .bold, dx: 20), "indented"),
        (replaced(second, "Organization (PATCO) Strike", style: .bold, size: 12), "another size"),
        (replaced(second, "• Organization (PATCO) Strike", style: .bold), "list item"),
        (replaced(body, source.lines[body].text, style: .bold), "bold beneath"),
        (replaced(body, source.lines[body].text, style: [], dx: 20), "paragraph off the edge"),
    ] {
        #expect(!labels(changed).contains(pair[0]), "\(note)")
    }
    // Two lines apart are no stacked title; neither is a pair run on from the paragraph above.
    var apart = source
    for index in [second, body] { apart.lines[index].rect.origin.y -= 14 }
    #expect(!labels(apart).contains(pair[0]))
    var crowded = source
    for index in [first, second, body] { crowded.lines[index].rect.origin.y += 12 }
    #expect(!labels(crowded).contains(pair[0]))
}

@Test func twoLineItalicSubheadingReadsAsTitleCaseOverPlainText() throws {
    // No untagged two-line italic title survives in the corpus; the same page set in the FAA's
    // 10-point italic title style stands in for one, with italic emphasis, captions and sentences
    // as controls.
    let source = try page("faa-21-tagged")
    let first = try #require(source.lines.firstIndex { $0.text == "The Professional Air Traffic Controllers" })
    let second = try #require(source.lines.firstIndex { $0.text == "Organization (PATCO) Strike" })
    let body = try #require(source.lines.firstIndex { $0.text.hasPrefix("While preparing the NAS Plan") })
    func italic(_ firstText: String, _ secondText: String, bodyStyle: TextStyle = []) -> [String] {
        var changed = source
        changed.lines[first] = TextLine(content: InlineText(firstText, style: .italic), rect: source.lines[first].rect, fontSize: 10)
        changed.lines[second] = TextLine(content: InlineText(secondText, style: .italic), rect: source.lines[second].rect, fontSize: 10)
        changed.lines[body] = TextLine(content: InlineText(source.lines[body].text, style: bodyStyle), rect: source.lines[body].rect, fontSize: 10)
        return LayoutReconstructor.sectionLabels(in: changed.lines, body: 10, headingThreshold: 12.5, page: changed, styles: faaStyles).map(\.text)
    }
    #expect(italic("The Professional Air Traffic Controllers", "Organization (PATCO) Strike").contains("The Professional Air Traffic Controllers"))
    #expect(!italic("The professional air traffic controllers", "organization went on strike").contains("The professional air traffic controllers"))
    #expect(!italic("Figure 1-7. The Professional Air Traffic", "Controllers Organization").contains("Figure 1-7. The Professional Air Traffic"))
    #expect(!italic("The Professional Air Traffic Controllers", "Organization (PATCO) Strike", bodyStyle: .italic)
        .contains("The Professional Air Traffic Controllers"))
}

// MARK: - #102 contents entries are no formulas

@Test func faaContentsMnemonicEntriesStayText() throws {
    let page6 = try page("faa-6-tagged")
    let entries = ["A = Aircraft", "V = EnVironment", "E = External Pressures", "Human Factors"]
    let regions = LayoutReconstructor.graphicsWithLabels(page6)
    for entry in entries {
        let line = try #require(page6.lines.first { $0.text.hasPrefix(entry) && $0.text.contains("....") }, "\(entry)")
        #expect(LayoutReconstructor.isContentsEntry(line.text))
        #expect(!regions.contains { $0.intersects(line.rect) }, "\(entry) cropped")
    }
    let text = reflow(page6).map(\.text).joined(separator: "\n")
    for entry in entries { #expect(text.contains(entry), "\(entry) missing") }
    // A displayed equation keeps its crop.
    var display = page6
    let row = try #require(page6.lines.first { $0.text.hasPrefix("A = Aircraft") })
    display.lines = page6.lines.filter { $0 != row } + [TextLine(text: "A = πr²", rect: row.rect, fontSize: 10)]
    #expect(LayoutReconstructor.graphicsWithLabels(display).contains { $0.intersects(row.rect) })
}
