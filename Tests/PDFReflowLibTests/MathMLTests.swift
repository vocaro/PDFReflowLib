import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func mathExpressionPackagesWithADeclaredFallback() async throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let crop = directory.appendingPathComponent("row.png")
    try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl8Vx8AAAAASUVORK5CYII=")!.write(to: crop)
    let expression = MathExpression(label: "1)", node: .squareRoot(.fraction(
        .number("1"), .subscript(.identifier("x"), .number("2")))), fallbackAssetID: "row",
        note: "Our Solution")
    let image = ReflowBlock.Image(assetID: "row", alternativeText: "formula", caption: "", link: nil,
                                  math: [expression])
    let book = ReflowDocument(metadata: .init(title: "Math", language: "en"),
                              blocks: [.init(content: .image(image), page: 1)],
                              assets: [.init(id: "row", fileURL: crop)])
    try book.validate()
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: directory,
                                   progress: { _ in })
    let chapter = try String(contentsOf: directory.appendingPathComponent("EPUB/chapter-1.xhtml"), encoding: .utf8)
    let package = try String(contentsOf: directory.appendingPathComponent("EPUB/package.opf"), encoding: .utf8)
    #expect(chapter.contains("<msqrt><mfrac><mn>1</mn><msub><mi>x</mi><mn>2</mn></msub></mfrac></msqrt>"))
    #expect(chapter.contains("altimg=\"images/image-1.png\""))
    #expect(chapter.contains("alttext=\"√(1/(x_2))\""))
    #expect(chapter.contains("</math> <span class=\"math-note\">Our Solution</span></p>"))
    #expect(package.contains("href=\"chapter-1.xhtml\" media-type=\"application/xhtml+xml\" properties=\"mathml\""))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func wallacePage17GlyphsRetainFractionEvidence() throws {
    let fixture = try SourceLayoutFixture.load("algebra-17")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let source = URL(fileURLWithPath: "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")
    let document = try #require(PDFDocument(url: source))
    let page = try #require(document.page(at: 16))
    let reference = try #require(page.pageRef)
    let glyphs = try NativeTextReader.withExtractionLock { MathRecognizer.glyphs(on: reference) }
    let crop = CGRect(x: 82, y: 406, width: 52, height: 26)
    #expect(glyphs.glyphs.contains { $0.text == "3" && crop.contains($0.center) })
    let content = fixture.content()
    let rows = MathRecognizer.rows(in: crop, page: glyphs, graphics: content.graphics,
                                   lines: content.lines, body: LayoutReconstructor.bodySize(content.lines))
    #expect(rows?.contains { MathExpression(label: $0.label, node: $0.node,
                                            fallbackAssetID: "row").linearText.contains("3/5") } == true)
}

private func mathGlyphs(_ text: String, x: CGFloat, baseline: CGFloat, size: CGFloat,
                        advance: CGFloat) -> [MathRecognizer.Glyph] {
    text.enumerated().map { offset, character in
        MathRecognizer.Glyph(text: String(character), minX: x + CGFloat(offset) * advance,
                             maxX: x + CGFloat(offset + 1) * advance, baseline: baseline, size: size)
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func fractionBarsRequireCompleteGlyphAndInkEvidence() throws {
    let glyphs = mathGlyphs("59)", x: 84.96, baseline: 417.10, size: 11.96, advance: 5.86)
        + mathGlyphs("3", x: 106.44, baseline: 423.34, size: 7.97, advance: 4.23)
        + mathGlyphs("5", x: 106.44, baseline: 412.30, size: 7.97, advance: 4.23)
        + mathGlyphs("+", x: 113.76, baseline: 417.10, size: 11.96, advance: 9.11)
        + mathGlyphs("5", x: 126.12, baseline: 423.34, size: 7.97, advance: 4.23)
        + mathGlyphs("4", x: 126.12, baseline: 412.30, size: 7.97, advance: 4.23)
    let bars = [CGRect(x: 103.84, y: 417.86, width: 9.4, height: 4),
                CGRect(x: 123.52, y: 417.86, width: 9.4, height: 4)]
    let lines = [TextLine(text: "59) 3", rect: CGRect(x: 85, y: 414.1, width: 25.7, height: 15.2), fontSize: 12),
                 TextLine(text: "5 + 5", rect: CGRect(x: 106.4, y: 410.3, width: 23.9, height: 19), fontSize: 12),
                 TextLine(text: "4", rect: CGRect(x: 126.1, y: 410.3, width: 4.2, height: 8), fontSize: 12)]
    let crop = CGRect(x: 82, y: 406, width: 52, height: 26)
    func read(_ bars: [CGRect], opaque: [CGPoint] = []) -> [MathRecognizer.Row]? {
        MathRecognizer.rows(in: crop, page: .init(glyphs: glyphs, opaque: opaque),
                            graphics: bars, lines: lines, body: 11.96)
    }
    let row = try #require(read(bars)?.first)
    #expect(MathExpression(label: row.label, node: row.node, fallbackAssetID: "row").linearText == "3/5 + 5/4")
    #expect(read(bars + [CGRect(x: 90, y: 408, width: 8, height: 8)]) == nil)
    #expect(read(bars, opaque: [CGPoint(x: 118, y: 417)]) == nil)
}
