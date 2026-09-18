import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Paragraphs a box cuts (#177): a box at the foot of a page between a paragraph and its
// continuation on the next page (the Fed's pages 47→48 and 98→99), and a paragraph wrapped
// around a box inset into its column (page 28). Fixtures are native extraction from the
// checksum-pinned Fed; every expected phrase was read on the rendered source page.

private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"

private func fedPage(_ name: String, dropping furniture: [String]) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == fedSHA256, "\(name) source identity")
    var page = fixture.styledContent()
    for line in furniture { #expect(page.lines.contains { $0.text == line }, "missing \(line)") }
    page.lines.removeAll { furniture.contains($0.text) }
    return page
}

/// The two pages reflowed and appended in order, as the pipeline does, with the crops it would cut.
private func appended(_ first: PageContent, _ second: PageContent, vocabulary extra: Set<String>) -> [ReflowBlock] {
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    let vocabulary = LayoutReconstructor.vocabulary(in: [first, second]).union(extra)
    var previous: (page: PageContent, regions: [CGRect])?
    for page in [first, second] {
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                                    vocabulary: vocabulary, warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous?.page,
                                       previousImages: previous?.regions ?? [], to: &blocks, vocabulary: vocabulary,
                                       warnings: &warnings)
        previous = (page, regions)
    }
    return blocks
}

private let head = "The Fed Explained: What the Central Bank Does"

// MARK: - A box at the page's foot

@Test func sourceParagraphContinuesPastABoxAtThePageFoot() throws {
    // Page 47 ends `…The vast major-` above Box 3.5, whose heading, paragraphs, Table A and note
    // fill the rest of the page; page 48 opens `ity of the Federal Reserve’s assets…`. The book
    // prints `majority` elsewhere.
    let page47 = try fedPage("fed-47", dropping: ["Conducting Monetary Policy 43"])
    let page48 = try fedPage("fed-48", dropping: ["44", head])
    let blocks = appended(page47, page48, vocabulary: ["majority"])
    let joined = try #require(blocks.first { $0.text.contains("The vast majority of the Federal Reserve’s assets are securities holdings") })
    #expect(joined.page == 47 && joined.sourcePages == [48])
    #expect(joined.text.hasPrefix("Finally, the Federal Reserve’s actions"))
    #expect(!blocks.contains { $0.text.hasPrefix("ity of the Federal Reserve") })
    // The box keeps its blocks, on page 47, ahead of the paragraph it interrupted, as a figure does.
    let box = try #require(blocks.firstIndex { $0.text.hasPrefix("Box 3.5. Gauging Monetary Policy") })
    let table = try #require(blocks.firstIndex { if case .table = $0.content { true } else { false } })
    let paragraph = try #require(blocks.firstIndex(of: joined))
    #expect(box < table && table < paragraph && blocks[box].page == 47 && blocks[table].page == 47)

    // Page 98 ends `…That is, all institu-` above figure 6.6's box: its title, the chart and its
    // `Source:` note, a paragraph of its own. Page 99 opens `tions dealing with…`.
    let page98 = try fedPage("fed-98", dropping: ["94", head])
    let page99 = try fedPage("fed-99", dropping: ["95", "Fostering Payment and Settlement System Safety and Efficiency"])
    let figure = appended(page98, page99, vocabulary: ["institutions"])
    let continued = try #require(figure.first { $0.text.contains("That is, all institutions dealing with the Federal Reserve directly") })
    #expect(continued.page == 98 && continued.sourcePages == [99])
    let note = try #require(figure.firstIndex { $0.text.hasPrefix("Source: Commercial automated clearinghouse") })
    #expect(note < figure.firstIndex(of: continued)!)
}

/// A page whose paragraph ends mid-sentence above a tinted box at its foot, and the next page.
/// `beside` sets the paragraph in a left column and the box in the right one, level with its foot.
private func footBoxPages(beside: Bool = false, proseBelowBox: Bool = false, nextInBox: Bool = false,
                          tinted: Bool = true) -> (PageContent, PageContent) {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let width: CGFloat = beside ? 200 : 420
    var lines = (0..<4).map { index in
        TextLine(text: "the paragraph runs on across the measure of line \(index + 1) and",
                 rect: CGRect(x: 90, y: 700 - CGFloat(index) * 16, width: width, height: 11.7), fontSize: 10)
    }
    lines.append(TextLine(text: "then it reaches the foot of its text where the reader must",
                          rect: CGRect(x: 90, y: 636, width: width + 1, height: 11.7), fontSize: 10))
    let (x, top): (CGFloat, CGFloat) = beside ? (322, 650) : (102, 600)
    lines += [
        TextLine(text: "Box 1. A Sidebar Title", rect: CGRect(x: x, y: top - 20, width: 150, height: 16), fontSize: 14),
        TextLine(text: "The sidebar explains something else in its own words.",
                 rect: CGRect(x: x, y: top - 44, width: 190, height: 11.7), fontSize: 10),
        TextLine(text: "Its second paragraph closes the box with a sentence.",
                 rect: CGRect(x: x, y: top - 70, width: 190, height: 11.7), fontSize: 10),
    ]
    if proseBelowBox {
        lines.append(TextLine(text: "and a paragraph set below the box carries on the page's own text further",
                              rect: CGRect(x: 90, y: 480, width: 420, height: 11.7), fontSize: 10))
    }
    var first = PageContent(number: 1, bounds: bounds, lines: lines, graphics: [])
    if tinted { first.tints = [CGRect(x: x - 14, y: top - 90, width: beside ? 206 : 436, height: 92)] }
    var second = PageContent(number: 2, bounds: bounds, lines: [
        TextLine(text: "turn the page to read on, since this sentence continues on the next page here.",
                 rect: CGRect(x: 90, y: 700, width: 420, height: 11.7), fontSize: 10),
        TextLine(text: "A new paragraph follows it on the second page and closes the example text.",
                 rect: CGRect(x: 90, y: 668, width: 420, height: 11.7), fontSize: 10),
    ], graphics: [])
    if nextInBox { second.tints = [CGRect(x: 88, y: 690, width: 436, height: 24)] }
    return (first, second)
}

@Test func onlyABoxBeneathTheParagraphAtThePageFootIsSteppedOver() {
    func joins(_ pages: (PageContent, PageContent)) -> Bool {
        appended(pages.0, pages.1, vocabulary: []).contains {
            $0.text.contains("where the reader must turn the page to read on")
        }
    }
    #expect(joins(footBoxPages()))
    // Controls. Without the tint the box's paragraphs are body text: its last one ends a sentence.
    #expect(!joins(footBoxPages(tinted: false)))
    // A box beside the paragraph, in the next column, rather than beneath its last line.
    #expect(!joins(footBoxPages(beside: true)))
    // Prose set below the box: the paragraph does not end the page.
    #expect(!joins(footBoxPages(proseBelowBox: true)))
    // The next page opens inside a box of its own: a sidebar, not the paragraph's continuation.
    #expect(!joins(footBoxPages(nextInBox: true)))
}

// MARK: - A box inset into the column

@Test func sourceParagraphWrapsAroundAnInsetBox() throws {
    // Page 28's `Short-term interest rates.` paragraph runs the full measure, narrows beside the
    // `Monetary policy: Easing and tightening defined` sidebar set into the column's left, and
    // returns to the full measure beneath it.
    let page = try fedPage("fed-28", dropping: ["24", head])
    let box = try #require(clusters(page.tints, distance: 4).first)
    func line(_ text: String) throws -> TextLine { try #require(page.lines.first { $0.text == text }) }
    let full = try line("panies—are affected by changes in the target range for the federal funds rate. Short-term interest")
    let beside = try line("rates would decline if the FOMC reduced its")
    let last = try line("ously expected. Conversely, short-term interest")
    let below = try line("rates would rise if the FOMC increased the federal funds rate target range, or if unfolding events")
    #expect(LayoutReconstructor.nextLineAroundInset(full, beside, page: page, body: 10, insets: [box]))
    #expect(LayoutReconstructor.nextLineAroundInset(last, below, page: page, body: 10, insets: [box]))
    #expect(!LayoutReconstructor.nextLineAroundInset(last, below, page: page, body: 10, insets: []))
    #expect(!LayoutReconstructor.nextLineInColumn(full, beside, page: page, body: 10))

    var warnings: [ConversionWarning] = []
    let vocabulary = LayoutReconstructor.vocabulary(in: [page]).union(["previously", "holders", "companies"])
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
    let paragraph = try #require(blocks.first { $0.text.hasPrefix("Short-term interest rates. Short-term interest rates—for example") })
    #expect(paragraph.text.contains("the federal funds rate. Short-term interest rates would decline if the FOMC reduced its"))
    #expect(paragraph.text.contains("lower than previously expected. Conversely, short-term interest rates would rise if the FOMC"))
    #expect(paragraph.text.hasSuffix("would soon be moved to a higher level than had been anticipated."))
    // The box keeps its title and text, after the paragraph.
    let title = try #require(blocks.firstIndex { $0.text == "Monetary policy: Easing and tightening defined" })
    #expect(title > blocks.firstIndex(of: paragraph)!)
    #expect(blocks.contains { $0.text.hasPrefix("The FOMC changes monetary policy primarily by raising") })
}

@Test func aWordBrokenAroundAnInsetBoxJoinsPastIt() throws {
    // Page 84 narrows `…These standards` / `require these institutions to maintain a mini-` beside
    // the `How do capital and liquidity differ?` sidebar, and `mum liquidity buffer…` returns to the
    // full measure beneath it. Reading order sets the sidebar between the narrowed lines and the
    // rest of the paragraph, so the broken word is joined past it, on the inset's geometry.
    let page = try fedPage("fed-84", dropping: ["80", head])
    var warnings: [ConversionWarning] = []
    let vocabulary = LayoutReconstructor.vocabulary(in: [page]).union(["minimum"])
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings).map(\.text)
    let paragraph = try #require(blocks.firstIndex {
        $0.contains("These standards require these institutions to maintain a minimum liquidity buffer based on")
    })
    #expect(!blocks.contains { $0.hasPrefix("mum liquidity buffer") })
    #expect(try #require(blocks.firstIndex { $0 == "How do capital and liquidity differ?" }) > paragraph)
}

@Test func nextLineAroundAnInsetNeedsTheInsetToFillTheIndent() {
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [], graphics: [])
    func line(_ x: CGFloat, _ y: CGFloat, _ right: CGFloat = 512, size: CGFloat = 10) -> TextLine {
        TextLine(text: "a line of prose in the paragraph", rect: CGRect(x: x, y: y, width: right - x, height: 11.7), fontSize: size)
    }
    let box = CGRect(x: 88.5, y: 392, width: 211, height: 88.5)
    let full = line(90, 489), narrow = line(316, 473, 507)
    func around(_ last: TextLine, _ first: TextLine, _ insets: [CGRect] = [box], in page: PageContent = page) -> Bool {
        LayoutReconstructor.nextLineAroundInset(last, first, page: page, body: 10, insets: insets)
    }
    #expect(around(full, narrow))
    #expect(around(line(316, 377, 520), line(90, 361, 510)))
    // Controls: no inset; an inset too narrow to account for the indent; an inset over the wide
    // line; another type size; a line between; two lines too far apart; right edges far apart.
    #expect(!around(full, narrow, []))
    #expect(!around(full, narrow, [CGRect(x: 88.5, y: 392, width: 60, height: 88.5)]))
    #expect(!around(full, narrow, [CGRect(x: 88.5, y: 392, width: 211, height: 100)]))
    #expect(!around(full, line(316, 473, 507, size: 8)))
    var crowded = page
    crowded.lines = [line(316, 481, 400)]
    #expect(!around(full, narrow, in: crowded))
    #expect(!around(full, line(316, 450, 507)))
    #expect(!around(full, line(316, 473, 470)))
    // A column simply indented, with no inset beside it, is the column's own edge.
    #expect(!around(full, narrow, [CGRect(x: 520, y: 392, width: 60, height: 88.5)]))
}

// MARK: - A box read into a paragraph at a word boundary

@Test func aWordBoundaryBreakReachesPastABoxToTheColumnsNextLine() throws {
    // Page 34 sets the `The Fed’s commitment to its goals` sidebar into the right of the column;
    // reading order puts its title, quotation and credit between `…risks and uncertainties
    // attending the outlook,` and `and the reasons for the Committee’s deci-`, the column's next
    // line. No word is broken there, so only the column's geometry says the two are one paragraph.
    func reflowed(_ edit: (inout TextLine) -> Void = { _ in }) throws -> [String] {
        var page = try fedPage("fed-34", dropping: ["30", head])
        for index in page.lines.indices { edit(&page.lines[index]) }
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                          warnings: &warnings).map(\.text)
    }
    let phrase = "attending the outlook, and the reasons for the Committee’s decisions."
    let blocks = try reflowed()
    let paragraph = try #require(blocks.firstIndex { $0.contains(phrase) })
    #expect(blocks[paragraph].hasPrefix("FOMC meeting minutes."))
    // The box keeps its blocks and follows the paragraph.
    #expect(try #require(blocks.firstIndex { $0 == "The Fed’s commitment to its goals" }) > paragraph)
    // Controls on the same page: the anchor ending its sentence, and the continuation moved off
    // the column's edge.
    let closed = try reflowed { line in
        if line.text == "risks and uncertainties attending the outlook," {
            line = TextLine(text: "risks and uncertainties attending the outlook.", rect: line.rect, fontSize: line.fontSize)
        }
    }
    #expect(!closed.contains { $0.contains("attending the outlook. and the reasons") })
    let moved = try reflowed { line in
        if line.text.hasPrefix("and the reasons for the Committee") { line.rect.origin.x += 30 }
    }
    #expect(!moved.contains { $0.contains(phrase) })
}
