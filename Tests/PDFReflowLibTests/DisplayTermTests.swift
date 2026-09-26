import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import PDFReflowLib

// A display's crop holds the whole display and none of the sentence beside it (#302): a line
// PDFKit ran from the sentence into the display's first term is split at the break, and a piece
// of the display's row that opens with an arrow joins the crop across the gap before it.

private typealias Glyph = GlyphPlacementReader.Glyph

/// DASC (corpus/cache/20190030725.pdf) page 9, measured from its content stream: `the form` in
/// 9.96-point type on the baseline 465.94, and the ½ that opens the display beside it, whose 1
/// stands at 6.97 points on 461.33 and whose 2 hangs on 453.97.
private let theForm: [Glyph] = [
    .init(minX: 311.98, maxX: 314.75, baseline: 465.94, size: 9.96),
    .init(minX: 314.75, maxX: 319.73, baseline: 465.94, size: 9.96),
    .init(minX: 319.73, maxX: 324.15, baseline: 465.94, size: 9.96),
    .init(minX: 324.15, maxX: 327.64, baseline: 465.94, size: 9.96, inked: false),
    .init(minX: 327.64, maxX: 330.96, baseline: 465.94, size: 9.96),
    .init(minX: 330.96, maxX: 335.94, baseline: 465.94, size: 9.96),
    .init(minX: 335.94, maxX: 339.26, baseline: 465.94, size: 9.96),
    .init(minX: 339.26, maxX: 347.01, baseline: 465.94, size: 9.96),
    .init(minX: 380.36, maxX: 384.33, baseline: 461.33, size: 6.97),
    .init(minX: 380.36, maxX: 384.33, baseline: 453.97, size: 6.97),
    .init(minX: 385.52, maxX: 391.22, baseline: 457.41, size: 9.96),
]

/// PDFKit's line for the two: `the form` and the numerator, the numerator as a lowered run.
private let mergedLine = TextLine(content: InlineText(elements: [.text("the form ", []), .text("1", .subscript)]),
                                  rect: CGRect(x: 311.98, y: 459.98, width: 72.35, height: 12.72), fontSize: 9.96)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aSentenceRunIntoADisplaysTermIsTwoLines() throws {
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }
    let cut = try #require(DisplayTermSplit.cut(mergedLine, glyphs: theForm))
    #expect(near(cut.wordsEnd, 347.01))
    #expect(near(cut.term.minX, 380.36) && near(cut.term.maxX, 384.33))
    #expect(near(cut.term.minY, 459.98) && near(cut.term.maxY, 466.56))
    #expect(cut.termSize == 6.97)
    let lines = try #require(DisplayTermSplit.split(mergedLine, wordsEnd: cut.wordsEnd, term: cut.term,
                                                    termSize: cut.termSize, words: "the form"))
    #expect(lines.map(\.text) == ["the form", "1"])
    #expect(near(lines[0].rect.minX, 311.98) && near(lines[0].rect.maxX, 347.01))
    #expect(lines[0].rect.minY == mergedLine.rect.minY && lines[0].rect.maxY == mergedLine.rect.maxY)
    #expect(lines[0].fontSize == 9.96 && lines[1].fontSize == 6.97)
    // Each piece keeps its own run's style.
    #expect(lines[1].content.elements == [.text("1", .subscript)])
    // PDFKit's text up to the break must open the line's own and leave the term behind.
    #expect(DisplayTermSplit.split(mergedLine, wordsEnd: cut.wordsEnd, term: cut.term, termSize: cut.termSize,
                                   words: "the form 1") == nil)
    #expect(DisplayTermSplit.split(mergedLine, wordsEnd: cut.wordsEnd, term: cut.term, termSize: cut.termSize,
                                   words: "the farm") == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aSentenceBesideADisplayStaysOutOfItsCrop() throws {
    // DASC's shape from a page: a sentence ends `has the form` and its display starts 34 points
    // to the right with a ½ whose numerator shares the sentence's row. PDFKit reads
    // `we see that it has the form 1` as one line, and the ½'s crop took it whole.
    let x = 72 + helveticaAdvance("we see that it has the form", size: 10) + 34
    let width = helveticaAdvance("1", size: 7)
    let page = try accentFixturePage("""
        BT /F1 10 Tf 72 702 Td (Letting x be the vector, we see that problem twelve has) Tj ET
        BT /F1 10 Tf 72 686 Td (we see that it has the form) Tj ET
        BT /F1 7 Tf \(x) 690 Td (1) Tj ET
        BT /F1 7 Tf \(x) 682.6 Td (2) Tj ET
        \(x) 688.3 \(width) 0.4 re f
        BT /F1 10 Tf \(x + width + 1.2) 686 Td (x + qx) Tj ET
        BT /F1 10 Tf \(x) 676 Td (Gx < h) Tj ET
        BT /F1 10 Tf 72 662 Td (\\(there are no linear equality constraints\\), where) Tj ET
        """)
    let words = try #require(page.lines.first { $0.text == "we see that it has the form" })
    #expect(!page.lines.contains { $0.text.contains("form 1") })
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try #require(crops.count == 1)
    #expect(!LayoutReconstructor.takes(crops[0], words))
    #expect(page.lines.contains { $0.text == "1" && LayoutReconstructor.takes(crops[0], $0) })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func onlyASmallerTermOnItsOwnBaselinePastTwoEmsIsADisplays() {
    func line(_ text: String, _ width: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 100, y: 496, width: width, height: 14), fontSize: 10)
    }
    let words = (0..<6).map { Glyph(minX: 100 + CGFloat($0) * 5, maxX: 105 + CGFloat($0) * 5, baseline: 500, size: 10) }
    // An exponent set against its base stays on the line.
    #expect(DisplayTermSplit.cut(line("aaaaaa2", 36),
        glyphs: words + [Glyph(minX: 130, maxX: 134, baseline: 504, size: 7)]) == nil)
    // A word at the line's own size across a column gap is the next column's, not a term.
    #expect(DisplayTermSplit.cut(line("aaaaaa2", 90),
        glyphs: words + [Glyph(minX: 186, maxX: 190, baseline: 500, size: 10)]) == nil)
    // A smaller run on the line's own baseline (a small-capital tail, a price in smaller type).
    #expect(DisplayTermSplit.cut(line("aaaaaa2", 90),
        glyphs: words + [Glyph(minX: 186, maxX: 190, baseline: 500, size: 7)]) == nil)
    // Anything past the break at the line's own size makes it no display's term.
    #expect(DisplayTermSplit.cut(line("aaaaaa2b", 96),
        glyphs: words + [Glyph(minX: 186, maxX: 190, baseline: 504, size: 7),
                         Glyph(minX: 191, maxX: 196, baseline: 500, size: 10)]) == nil)
    // The words must be words, and the term no word: a label and its term are both the
    // display's, and a word past the break is small type, not a display.
    let term = CGRect(x: 186, y: 498, width: 4, height: 7)
    let label = TextLine(text: "12 1", rect: CGRect(x: 100, y: 496, width: 90, height: 14), fontSize: 10)
    #expect(DisplayTermSplit.split(label, wordsEnd: 110, term: term, termSize: 7, words: "12") == nil)
    let note = TextLine(text: "the form see", rect: CGRect(x: 100, y: 496, width: 90, height: 14), fontSize: 10)
    #expect(DisplayTermSplit.split(note, wordsEnd: 140, term: term, termSize: 7, words: "the form") == nil)
}

/// DASC page 9's lines around the display `½xᵀPx + qᵀx ⟶ₓ min, Gᵀx ≤ h` once `the form` is its
/// own line, as `PageReader` now returns them, with the ½'s bar.
private func quadraticProgramPage(arrow: String = "−→x min,", arrowX: CGFloat = 452.65) -> PageContent {
    func line(_ text: String, _ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ size: CGFloat = 9.96) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), fontSize: size)
    }
    return PageContent(number: 9, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
        line("The quadratic part of this sum has the tridiagonal matricial", 311.98, 563.04, 633.98, 642.89),
        line("Letting x= [s1 s2 ... sN ]T , we see that problem (12) has", 321.94, 563.04, 475.05, 487.74),
        line("the form", 311.98, 347.01, 459.98, 472.70),
        line("1", 380.36, 384.33, 459.98, 466.56, 6.97),
        line("2 xT Px+ qT x", 380.36, 439.92, 452.62, 465.86, 6.97),
        line(arrow, arrowX, arrowX + 43.2, 452.62, 465.86),
        line("GT x≤h", 379.16, 417.99, 443.51, 453.90),
        line("(there are no linear equality constraints), where", 311.98, 506.36, 426.18, 435.09),
        line("For this problem class, the cvxopt Python module [1] has", 311.98, 563.04, 152.76, 161.67),
        line("a numerical quadratic programming solver that can be called", 311.98, 563.04, 140.81, 149.71),
    ], graphics: [CGRect(x: 378.36, y: 457.90, width: 7.97, height: 4)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aDisplaysCropHoldsItsArrowAndNotTheSentence() throws {
    let page = quadraticProgramPage()
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try #require(crops.count == 1)
    let taken = page.lines.filter { LayoutReconstructor.takes(crops[0], $0) }.map(\.text)
    #expect(taken == ["1", "2 xT Px+ qT x", "−→x min,", "GT x≤h"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func onlyAnArrowWithATermCarriesADisplayRowOn() throws {
    func taken(_ arrow: String, at x: CGFloat = 452.65) throws -> Bool {
        let page = quadraticProgramPage(arrow: arrow, arrowX: x)
        let crops = LayoutReconstructor.graphicsWithLabels(page)
        let line = try #require(page.lines.first { $0.text == arrow })
        return crops.contains { LayoutReconstructor.takes($0, line) }
    }
    #expect(try taken("⟶ min,"))
    #expect(try taken("↦ max,"))
    // Wallace sets `=` as a line of its own between two fractions, each its own crop read as
    // MathML; joining it carried one crop into the next and lost both to a picture.
    #expect(try !taken("="))
    // An arrow with nothing after it, a sentence, and a piece more than two bodies away.
    #expect(try !taken("→"))
    #expect(try !taken("→ which is the objective of this program"))
    #expect(try !taken("−→x min,", at: 462))
    #expect(LayoutReconstructor.opensWithArrow("−→x min,"))
    #expect(!LayoutReconstructor.opensWithArrow("x → 0"))
    #expect(!LayoutReconstructor.opensWithArrow("− 2x"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func dascPageNinesDisplayTakesTheArrowAndLeavesTheForm() throws {
    let url = URL(fileURLWithPath: "corpus/cache/20190030725.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    #expect(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        == "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa")
    let page = try PageReader.read(pageIndex: 8, from: PDFPageSource(url: url), limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let form = try #require(page.lines.first { $0.text == "the form" })
    let arrow = try #require(page.lines.first { $0.text.hasPrefix("−→") && $0.text.hasSuffix("min,") && $0.rect.minX > 400 })
    #expect(!crops.contains { LayoutReconstructor.takes($0, form) })
    let display = try #require(crops.first { LayoutReconstructor.takes($0, arrow) })
    // The same crop holds the ½, the rest of its row and the constraint beneath.
    for text in ["1", "Px+ q", "x≤h"] {
        #expect(page.lines.contains { $0.text.contains(text) && $0.rect.minX > 375 && LayoutReconstructor.takes(display, $0) })
    }
}
