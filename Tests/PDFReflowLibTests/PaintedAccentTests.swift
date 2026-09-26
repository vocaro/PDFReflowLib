import CoreGraphics
import CryptoKit
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// A bar painted over or under one glyph is that glyph's overline or underline (#302): the line
// carries it as a combining macron, and the bar seeds no crop. Fraction bars, a radical's
// vinculum and underlines of words are not accents and are treated as before.

/// Helvetica's advance widths for codes 32–126, in thousandths of an em.
let helveticaWidths: [Int] = [
    278, 278, 355, 556, 556, 889, 667, 222, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556,
    278, 278, 584, 584, 584, 556, 1015,
    667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667,
    944, 667, 667, 611,
    278, 278, 278, 469, 556, 222,
    556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500,
    722, 500, 500, 500,
    334, 260, 334, 584,
]

/// How far `text` set in Helvetica at `size` advances.
func helveticaAdvance(_ text: String, size: CGFloat) -> CGFloat {
    text.unicodeScalars.reduce(0) { $0 + CGFloat(helveticaWidths[Int($1.value) - 32]) } * size / 1000
}

/// A one-page PDF over `content`, with Helvetica as `/F1` and Symbol's radical sign (code 214)
/// as `/F2`, both with their widths, read the way the pipeline reads a page.
func accentFixturePage(_ content: String) throws -> PageContent {
    let widths = helveticaWidths.map(String.init).joined(separator: " ")
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 32 /LastChar 126 /Widths [\(widths)] >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Symbol /FirstChar 214 /LastChar 214 /Widths [549] >>",
        testPDFStream(content),
    ])
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("accents.pdf")
    try data.write(to: url)
    return try PageReader.read(pageIndex: 0, from: PDFPageSource(url: url), limit: 10_000,
                               options: ConversionOptions(), structure: nil).content
}

/// A 12-point Helvetica line at `y` with a 0.4-point bar over or under each named occurrence of
/// `a`, and a line of prose 16 points above and below it.
private func accentedLine(_ text: String, over: [Int] = [], under: [Int] = [], y: CGFloat = 686) -> String {
    let escaped = text.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
    var content = "BT /F1 12 Tf 72 \(y + 16) Td (Before the window opens we read on) Tj ET\n"
        + "BT /F1 12 Tf 72 \(y) Td (\(escaped)) Tj ET\n"
        + "BT /F1 12 Tf 72 \(y - 16) Td (and nothing else stands on this line) Tj ET\n"
    let starts = text.indices.filter { text[$0] == "a" }.map { helveticaAdvance(String(text[..<$0]), size: 12) + 72 }
    let width = helveticaAdvance("a", size: 12)
    for index in over { content += "\(starts[index]) \(y + 7.4) \(width) 0.4 re f\n" }
    for index in under { content += "\(starts[index]) \(y - 1.8) \(width) 0.4 re f\n" }
    return content
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aBarOverOrUnderOneGlyphReadsAsItsAccent() throws {
    // DASC (corpus/cache/20190030725.pdf) page 9 prints a time window's two ends as (a̱_k, ā_k):
    // each bar is a 0.4-point rule exactly the italic a's advance wide. Measured from its content
    // stream: the underlined a spans 202.68–207.95 on the baseline 255.37 at 9.96 points, its bar
    // 1.39 points below; the overlined one spans 217.28–222.55, its bar 5.69 points above. The
    // lines above and below stand on 267.33 and 243.42.
    let glyphs: [PaintedAccents.Glyph] = [
        .init(minX: 198.81, maxX: 202.68, baseline: 255.37, size: 9.96),  // (
        .init(minX: 202.68, maxX: 207.95, baseline: 255.37, size: 9.96),  // a
        .init(minX: 207.95, maxX: 212.19, baseline: 252.88, size: 6.97),  // k
        .init(minX: 212.85, maxX: 215.62, baseline: 255.37, size: 9.96),  // ,
        .init(minX: 217.28, maxX: 222.55, baseline: 255.37, size: 9.96),  // a
        .init(minX: 222.55, maxX: 226.78, baseline: 253.88, size: 6.97),  // k
        .init(minX: 198.87, maxX: 203.30, baseline: 267.33, size: 9.96),  // the line above
        .init(minX: 203.30, maxX: 206.07, baseline: 267.33, size: 9.96),
        .init(minX: 215.54, maxX: 219.96, baseline: 267.33, size: 9.96),
        .init(minX: 219.77, maxX: 224.75, baseline: 267.33, size: 9.96),
        .init(minX: 198.20, maxX: 201.51, baseline: 243.42, size: 9.96),  // the line below
        .init(minX: 201.51, maxX: 205.94, baseline: 243.42, size: 9.96),
    ]
    let under = CGRect(x: 200.68, y: 251.98, width: 9.27, height: 4)
    let over = CGRect(x: 215.28, y: 259.06, width: 9.27, height: 4)
    #expect(PaintedAccents.accent(under, glyphs: glyphs)?.scalar == PaintedAccents.underline)
    #expect(PaintedAccents.accent(under, glyphs: glyphs)?.glyph == glyphs[1])
    #expect(PaintedAccents.accent(over, glyphs: glyphs)?.scalar == PaintedAccents.overline)
    #expect(PaintedAccents.accent(over, glyphs: glyphs)?.glyph == glyphs[4])

    // Read from a page: the line carries both marks and neither bar is preserved.
    let page = try accentFixturePage(accentedLine("the window (a, a) closes here", over: [1], under: [0]))
    #expect(page.lines.map(\.text).contains("the window (a\u{0331}, a\u{0304}) closes here"))
    #expect(page.accents.count == 2)
    #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
    // The writer keeps the mark on its letter, so the text says ā where the page prints it.
    let line = try #require(page.lines.first { $0.text.hasPrefix("the window") })
    #expect(EPUBTextEncoder.inline(line.content).contains("(a\u{0331}, a\u{0304})"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aFractionBarIsNoAccent() throws {
    // DASC page 9's ½: 1 and 2 at 6.97 points on either side of a bar exactly their advance
    // wide. Each term alone stands to the bar as an accented glyph would; together they are a
    // fraction.
    let half: [PaintedAccents.Glyph] = [
        .init(minX: 380.36, maxX: 384.33, baseline: 461.33, size: 6.97),
        .init(minX: 380.36, maxX: 384.33, baseline: 453.97, size: 6.97),
        .init(minX: 385.52, maxX: 391.22, baseline: 457.41, size: 9.96),
    ]
    #expect(PaintedAccents.accent(CGRect(x: 378.36, y: 457.90, width: 7.97, height: 4), glyphs: half) == nil)
    // A display fraction a/b at body size: the numerator stands 0.43 em over the bar, the
    // denominator hangs 0.94 em under it.
    let display: [PaintedAccents.Glyph] = [
        .init(minX: 100, maxX: 105.27, baseline: 504.3, size: 10),
        .init(minX: 100, maxX: 105.27, baseline: 490.6, size: 10),
    ]
    #expect(PaintedAccents.accent(CGRect(x: 98, y: 498, width: 9.27, height: 4), glyphs: display) == nil)
    // Wallace page 12's 36/84: the bar spans two glyphs on each side.
    let wallace: [PaintedAccents.Glyph] = [
        .init(minX: 170.64, maxX: 176.49, baseline: 434.02, size: 11.96),
        .init(minX: 176.52, maxX: 182.37, baseline: 434.02, size: 11.96),
        .init(minX: 170.64, maxX: 176.49, baseline: 419.02, size: 11.96),
        .init(minX: 176.52, maxX: 182.37, baseline: 419.02, size: 11.96),
    ]
    #expect(PaintedAccents.accent(CGRect(x: 168.04, y: 427.46, width: 16.96, height: 4), glyphs: wallace) == nil)

    // From a page: an inline ½ keeps its crop and its line reads as it did.
    let x = 72 + helveticaAdvance("Take ", size: 12), width = helveticaAdvance("1", size: 8)
    let page = try accentFixturePage("""
        BT /F1 12 Tf 72 686 Td (Take ) Tj ET
        BT /F1 8 Tf \(x) 692 Td (1) Tj ET
        BT /F1 8 Tf \(x) 682 Td (2) Tj ET
        \(x) 689.8 \(width) 0.4 re f
        BT /F1 12 Tf \(x + width + 2) 686 Td (of the cake) Tj ET
        """)
    #expect(page.accents.isEmpty)
    #expect(!page.lines.contains { $0.text.unicodeScalars.contains { $0.properties.generalCategory == .nonspacingMark } })
    #expect(!LayoutReconstructor.graphicsWithLabels(page).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aRadicalsVinculumIsNoAccent() throws {
    // Wallace page 300 sets √ over one digit: the vinculum spans the radicand exactly as an
    // overline would, and the radical sign, whose baseline is the bar's own height, meets its
    // left end.
    let root: [PaintedAccents.Glyph] = [
        .init(minX: 161.64, maxX: 171.60, baseline: 632.74, size: 11.96),
        .init(minX: 171.60, maxX: 177.46, baseline: 622.78, size: 11.96),
    ]
    #expect(PaintedAccents.accent(CGRect(x: 169.24, y: 630.86, width: 10.24, height: 4), glyphs: root) == nil)
    // Without the sign, the same bar is the digit's overline.
    #expect(PaintedAccents.accent(CGRect(x: 169.24, y: 630.86, width: 10.24, height: 4),
                                  glyphs: [root[1]])?.scalar == PaintedAccents.overline)

    // From a page: Symbol's radical sign hangs from the bar over x.
    let sign = 72 + helveticaAdvance("so ", size: 12), radicand = sign + 549 * 12 / 1000
    let width = helveticaAdvance("x", size: 12)
    let page = try accentFixturePage("""
        BT /F1 12 Tf 72 686 Td (so ) Tj ET
        BT /F2 12 Tf \(sign) 695.4 Td (\\326) Tj ET
        BT /F1 12 Tf \(radicand) 686 Td (x is its root) Tj ET
        \(radicand) 695.2 \(width) 0.4 re f
        """)
    #expect(page.accents.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func anUnderlinedWordIsNoAccent() throws {
    // A rule under a whole word spans several glyphs; it is the word's underline (#235), read as
    // it always was.
    let text = "we read about it"
    let start = 72 + helveticaAdvance("we read ", size: 12), width = helveticaAdvance("about", size: 12)
    let page = try accentFixturePage(accentedLine(text) + "\(start) 684.2 \(width) 0.4 re f\n")
    #expect(page.accents.isEmpty)
    #expect(page.lines.map(\.text).contains(text))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aMarkGoesAfterTheCharacterPDFKitReadsUnderTheBar() throws {
    let line = TextLine(content: InlineText(elements: [
        .text("and (a", []), .text("k", .subscript), .text(",a", []), .text("k", .subscript), .text(") the", []),
    ]), rect: CGRect(x: 0, y: 0, width: 100, height: 10), fontSize: 10)
    // PDFKit's text up to the second a: the mark goes after it, in its own run.
    let second = try #require(PaintedAccents.marking(line, through: "and (ak,a", under: "a", with: PaintedAccents.overline))
    #expect(second.text == "and (ak,a\u{0304}k) the")
    // A mark already set is no glyph of PDFKit's, so the first a is still the fourth drawn.
    let both = try #require(PaintedAccents.marking(second, through: "and (a", under: "a", with: PaintedAccents.underline))
    #expect(both.text == "and (a\u{0331}k,a\u{0304}k) the")
    #expect(EPUBTextEncoder.inline(both.content) == "and (a\u{0331}<sub>k</sub>,a\u{0304}<sub>k</sub>) the")
    // Text that is not the line's own, or a character that is not a letter or a digit, marks nothing.
    #expect(PaintedAccents.marking(line, through: "or (a", under: "a", with: PaintedAccents.overline) == nil)
    #expect(PaintedAccents.marking(line, through: "and (ak,", under: ",", with: PaintedAccents.overline) == nil)
    #expect(PaintedAccents.marking(line, through: "and (ak,a", under: "k", with: PaintedAccents.overline) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func dascPageNineReadsItsTimeWindowsWithTheirBars() throws {
    let url = URL(fileURLWithPath: "corpus/cache/20190030725.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    #expect(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        == "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa")
    let page = try PageReader.read(pageIndex: 8, from: PDFPageSource(url: url), limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    // Rendered at 200 DPI: `node n to the next node on route, and (a̱_k, ā_k) the time window`.
    #expect(page.lines.contains { $0.text.contains("(a\u{0331}k,a\u{0304}k) the time window") })
    // h^T = [ā₁ ā₂ … ā_N −a̱₁ −a̱₂ … −a̱_N]: every bar of the row.
    #expect(page.lines.contains { $0.text.contains("[a\u{0304}1 a\u{0304}2... a\u{0304}N−a\u{0331}1−a\u{0331}2...−a\u{0331}N ]") })
    // No crop is a bar alone: each of the two in the running line had been a sliver of its own.
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(!crops.contains { $0.height < 5 })
    #expect(page.lines.filter { line in line.text.contains("the time window") }
        .allSatisfy { line in !crops.contains { LayoutReconstructor.takes($0, line) } })
}
