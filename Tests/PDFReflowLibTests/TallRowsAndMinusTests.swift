import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Lines whose rectangles an inline expression makes tall, and a joined row that opens with a
// minus sign (#109). Fixtures are native extraction from the checksum-pinned Wallace source;
// expected text was read from the rendered source pages.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

private func sourceBlocks(_ name: String) throws -> [ReflowBlock] {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == algebraSHA256, "\(name) source identity")
    var page = fixture.styledContent()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    return reflow(page)
}

private func reflow(_ page: PageContent, crops: Bool = true) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    let regions = crops ? LayoutReconstructor.graphicsWithLabels(page) : []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { $0.text } else { nil } }
}

// MARK: - Tall inline-expression lines

// Wallace's minus and times glyphs drop a line's rectangle 8.5 points below its type, and a
// radical's bar raises it, so the line overlaps its neighbour by 6.1 points against 4.8 points of
// tolerance. Each continuation below used to open a paragraph of its own.
@Test func sourceTallInlineExpressionLinesKeepTheirParagraphs() throws {
    let page180 = paragraphs(try sourceBlocks("algebra-180"))
    #expect(page180.contains("As we multiply exponents its important to remember these properties apply to exponents, not bases. An expressions such as 53 does not mean we multipy 5 by 3, rather we multiply 5 three times, 5 × 5 × 5 = 125. This is shown in the next example."))
    #expect(!page180.contains("example."))

    let page318 = paragraphs(try sourceBlocks("algebra-318"))
    let cycle = try #require(page318.first { $0.hasPrefix("With this definition, the square root of a negative number") })
    #expect(cycle.contains("Then if we multiply both sides of the equation again by i, the equation becomes i4 =− i2 =− (− 1) = 1, or simply i4 = 1. Multiplying again by i gives i5 = i. One more time gives i6 = i2 =− 1. And if this pattern continues we see a cycle forming, the exponents on i change we cycle through simplified answers of i,− 1,− i, 1. As there are 4 diﬀerent possible answers in this cycle,"))
    #expect(cycle.hasSuffix("we can simplify any exponent on i by learning just the following four values:"))
    // The World View Note, set off by added space, still opens its own paragraphs (#71).
    #expect(page318.contains { $0.hasPrefix("World View Note: When mathematics was first used") && $0.hasSuffix("made up negative numbers when they found use for them.") })
    #expect(page318.contains { $0.hasPrefix("In mathematics, when the current number system does not provide the tools to") })

    let page9 = paragraphs(try sourceBlocks("algebra-9"))
    let careful = try #require(page9.first { $0.hasPrefix("A few things to be careful of when working with integers.") })
    #expect(careful.contains("The second problem is a multiplication problem because there is nothing between the 3 and the parenthesis."))
    #expect(careful.contains("the we keep the negative,− 3 + (− 7) =− 10, but if the signs match on multiplication"))
    #expect(careful.hasSuffix("the answer is positive, (− 3)(− 7) = 21."))
    #expect(!page9.contains("21."))

    let page120 = paragraphs(try sourceBlocks("algebra-120"))
    #expect(page120.contains { $0.hasSuffix("Graph starts at− 4 and goes down or less. Square bracket means less than or equal to") })
    #expect(!page120.contains("equal to"))
}

// Page 321: the radicand `− 1`, which PDFKit extracts apart from its radical, joins its row, and the
// row reads as prose in its paragraph instead of a preserved list line.
@Test func sourceMinusRadicandRowReadsAsProse() throws {
    let blocks = try sourceBlocks("algebra-321")
    #expect(paragraphs(blocks).first == "Dividing with complex numbers also has one thing we need to be careful of. If i is − 1 √ , and it is in the denominator of a fraction, then we have a radical in the denominator! This means we will want to rationalize our denominator so there are no i’s. This is done the same way we rationalized denominators with square roots.")
    #expect(!preformatted(blocks).contains { $0.hasPrefix("−") })
    #expect(!paragraphs(blocks).contains { $0.hasPrefix("√ ,") || $0.hasPrefix("denominator!") })

    // Only a minus sign is exempt: the same piece reading as a numbered marker still may not turn
    // the row into a list line, so the row stays as PDFKit split it.
    let fixture = try SourceLayoutFixture.load("algebra-321")
    var page = fixture.styledContent()
    page.lines.removeAll { $0.text == String(fixture.page) }
    let radicand = try #require(page.lines.firstIndex { $0.text == "− 1" })
    page.lines[radicand] = TextLine(text: "2) 1", rect: page.lines[radicand].rect, fontSize: page.lines[radicand].fontSize)
    let marked = reflow(page)
    #expect(!preformatted(marked).contains { $0.contains("and it is in the denominator") })
    #expect(paragraphs(marked).contains { $0.contains("If i is √ , and it is in the denominator of a fraction") })
    #expect(!marked.contains { $0.text.contains("2) 1 √") })
}

// Lines that open with a minus and are not joined rows keep their list-line representation: the
// license's minus bullets (page 2, the corpus's only U+2212 bullets, whose tall rectangles are
// another control for the overlap rule) and derivation steps (pages 9 and 120).
@Test func sourceMinusLinesOutsideJoinedRowsStayListLines() throws {
    let page2 = try sourceBlocks("algebra-2")
    let list = preformatted(page2)
    #expect(list.contains("− Your fair dealing or fair use rights, or other applicable copyright exceptions and"))
    #expect(list.contains("− The author’s moral rights;"))
    #expect(list.contains("− Rights other persons may have either in the work itself or in how the work is used"))
    #expect(list.filter { $0.hasPrefix("• ") }.count == 7)
    #expect(paragraphs(page2).contains("You are free:"))
    #expect(paragraphs(page2).contains("Under the following conditions:"))
    #expect(paragraphs(page2).contains("This is a human readable summary of the full legal code which can be read at the following URL: http://creativecommons.org/licenses/by/3.0/legalcode"))

    let page9 = preformatted(try sourceBlocks("algebra-9"))
    #expect(page9 == ["− 24 Our Solution", "− 2(− 6)", "− 5 Our Solution"])
    #expect(preformatted(try sourceBlocks("algebra-120")) == ["− 18 <− 12"])
}

@Test func minusSignBeforeANumberOrVariableIsNotABulletWord() {
    for text in ["− 1 √ , and it is", "− 3x− 3y=26", "− x +6y=16", "− 24 Our Solution", "−  b2 Our Solution"] {
        #expect(LayoutReconstructor.opensWithMinusSign(text), "\(text)")
    }
    for text in ["− Your fair dealing", "− The author’s moral rights;", "- 1 hyphen-minus", "−1", "• 1", "x − 1", "− (− 8)· 3"] {
        #expect(!LayoutReconstructor.opensWithMinusSign(text), "\(text)")
    }
}

// MARK: - Synthetic overlap geometry

/// Wallace's geometry: 12-point prose at 14.4-point leading in 12-point rectangles (a box gap of
/// 2.4 points). The third line's rectangle is `height` tall, extended below its type when `drop`
/// (Wallace's minus and times glyphs) and above it otherwise (a radical's bar). `nextShift` raises the
/// line beneath it; `laterShift` raises the two lines after that.
private func tallLinePage(height: CGFloat = 20.5, drop: Bool = true,
                          fourth: String = "example of the rule we will use in every one of the lessons that follow in this chapter",
                          nextShift: CGFloat = 0,
                          fifth: String = "and the next line of the same paragraph continues its sentence to the end of the measure",
                          laterShift: CGFloat = 0) -> PageContent {
    func rect(_ index: Int, height: CGFloat = 12, drop: Bool = true, shift: CGFloat = 0) -> CGRect {
        let bottom = 700 - CGFloat(index) * 14.4 + shift
        return CGRect(x: 85, y: drop ? bottom - (height - 12) : bottom, width: 425, height: height)
    }
    let lines = [
        TextLine(text: "In this lesson we discuss the rules for exponents, which apply in every problem below and", rect: rect(0), fontSize: 12),
        TextLine(text: "as we multiply exponents it is important to remember these properties apply to", rect: rect(1), fontSize: 12),
        TextLine(text: "exponents, not bases, so we multiply 5 three times, 5 × 5 × 5 = 125, as is shown in the", rect: rect(2, height: height, drop: drop), fontSize: 12),
        TextLine(text: fourth, rect: rect(3, shift: nextShift), fontSize: 12),
        TextLine(text: fifth, rect: rect(4, shift: laterShift), fontSize: 12),
        TextLine(text: "which closes the paragraph with an ordinary last line of its own that ends here.", rect: rect(5, shift: laterShift), fontSize: 12),
    ]
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 595, height: 842), lines: lines, graphics: [])
}

@Test func syntheticTallInlineLineKeepsItsParagraph() {
    // The rectangle dropped 8.5 points below the type (6.1 points of overlap with the line beneath),
    // or raised 8.5 points above it (6.1 points with the line above): one paragraph either way.
    #expect(paragraphs(reflow(tallLinePage(), crops: false)).count == 1)
    #expect(paragraphs(reflow(tallLinePage(drop: false), crops: false)).count == 1)
    // A rectangle more than twice the ordinary line is a display, not an inline expression.
    #expect(paragraphs(reflow(tallLinePage(height: 25), crops: false)).count == 2)
    // Overlap beyond the extra height is not explained by it.
    #expect(paragraphs(reflow(tallLinePage(nextShift: 8), crops: false)).count == 2)
    // Ordinary rectangles overlapping by 6.1 points stay apart, as before.
    #expect(paragraphs(reflow(tallLinePage(height: 12, nextShift: 8.5, laterShift: 8.5), crops: false)).count == 2)
}

// The tall line's gap is not the paragraph's leading: at ordinary spacing, a line after a sentence
// end that opens with a capital is a wrapped line, not one set off by added space (#71). The leading
// measured before the tall line carries over, so real added space still opens a paragraph.
@Test func syntheticTallLineGapIsNotTheParagraphLeading() {
    let sentence = "example. The rule is the same for every base and exponent we will use in this chapter."
    let capital = "Multiplying again gives the same pattern, and the line continues its sentence to the end"
    #expect(paragraphs(reflow(tallLinePage(fourth: sentence, fifth: capital), crops: false)).count == 1)
    #expect(paragraphs(reflow(tallLinePage(fourth: sentence, fifth: capital, laterShift: -8), crops: false)).count == 2)
}
