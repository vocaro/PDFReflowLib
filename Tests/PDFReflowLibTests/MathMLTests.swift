import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// #190: a mathematical crop whose glyphs and bars prove its structure is written as MathML, with
// the row's crop as its fallback image; anything unproven keeps its crop. The geometry below is
// Wallace page 17's exercise 59 (`59) 3/5 + 5/4`) as its content stream sets it: a 12-point label
// and operator, 8-point terms, and bars GraphicsReader pads by two points.

private typealias Glyph = MathRecognizer.Glyph

private func run(_ text: String, x: CGFloat, baseline: CGFloat, size: CGFloat, advance: CGFloat? = nil,
                 mathItalic: Bool = false) -> [Glyph] {
    let width = advance ?? size * 0.49
    return text.enumerated().map { offset, character in
        Glyph(text: String(character), minX: x + CGFloat(offset) * width, maxX: x + CGFloat(offset + 1) * width,
              baseline: baseline, size: size, mathItalic: mathItalic)
    }
}

private func line(_ text: String, _ rect: CGRect) -> TextLine { TextLine(text: text, rect: rect, fontSize: 12) }

/// Exercise 59 and the lines PDFKit reads it as.
private struct Exercise {
    var glyphs = run("59)", x: 84.96, baseline: 417.10, size: 11.96)
        + run("3", x: 106.44, baseline: 423.34, size: 7.97, advance: 4.23)
        + run("5", x: 106.44, baseline: 412.30, size: 7.97, advance: 4.23)
        + run("+", x: 113.76, baseline: 417.10, size: 11.96, advance: 9.11)
        + run("5", x: 126.12, baseline: 423.34, size: 7.97, advance: 4.23)
        + run("4", x: 126.12, baseline: 412.30, size: 7.97, advance: 4.23)
    var bars = [CGRect(x: 103.84, y: 417.86, width: 9.4, height: 4), CGRect(x: 123.52, y: 417.86, width: 9.4, height: 4)]
    var lines = [line("59) 3", CGRect(x: 85.0, y: 414.1, width: 25.7, height: 15.2)),
                 line("5 + 5", CGRect(x: 106.4, y: 410.3, width: 23.9, height: 19.0)),
                 line("4", CGRect(x: 126.1, y: 410.3, width: 4.2, height: 8.0))]
    var crop = CGRect(x: 82, y: 406, width: 52, height: 26)

    func rows() -> [MathRecognizer.Row]? {
        MathRecognizer.rows(in: crop, page: .init(glyphs: glyphs), graphics: bars, lines: lines, body: 11.96)
    }
}

private func expression(_ row: MathRecognizer.Row) -> MathExpression {
    MathExpression(label: row.label, node: row.node, fallbackAssetID: "a")
}

@Test func barFractionsBesideAnOperatorReadAsMathML() throws {
    let rows = try #require(Exercise().rows())
    #expect(rows.count == 1)
    #expect(rows[0].label == "59)")
    let math = expression(rows[0])
    #expect(math.linearText == "3/5 + 5/4")
    #expect(EPUBTextEncoder.mathML(math.node)
        == "<mrow><mfrac><mn>3</mn><mn>5</mn></mfrac><mo>+</mo><mfrac><mn>5</mn><mn>4</mn></mfrac></mrow>")
    // The fallback image is the expression's own region, without its label.
    #expect(rows[0].rect.minX > 101)
    let markup = try EPUBTextEncoder.math(math, imagePaths: ["a": "images/image-1.png"])
    #expect(markup == "<p class=\"math\">59) <math xmlns=\"http://www.w3.org/1998/Math/MathML\" alttext=\"3/5 + 5/4\" "
        + "altimg=\"images/image-1.png\"><mfrac><mn>3</mn><mn>5</mn></mfrac><mo>+</mo><mfrac><mn>5</mn><mn>4</mn></mfrac></math></p>")
}

@Test func unprovenFractionEvidenceKeepsTheCrop() {
    // A numerator set off the bar's centre is no fraction the bar draws.
    var shifted = Exercise()
    shifted.glyphs[3].minX += 3; shifted.glyphs[3].maxX += 3
    #expect(shifted.rows() == nil)
    // A second bar across a term: a stacked fraction.
    var stacked = Exercise()
    stacked.bars.append(CGRect(x: 103.84, y: 427.5, width: 9.4, height: 4))
    #expect(stacked.rows() == nil)
    // A painted mark that is no thin rule (a box, an arrow) is unaccounted for.
    var boxed = Exercise()
    boxed.bars.append(CGRect(x: 90, y: 408, width: 8, height: 8))
    #expect(boxed.rows() == nil)
    // A line the content stream does not show (text in a form, an image) cannot be dropped.
    var unexplained = Exercise()
    unexplained.lines.append(line("x", CGRect(x: 90, y: 425, width: 4, height: 6)))
    #expect(unexplained.rows() == nil)
    // A show that does not decode glyph by glyph leaves the crop a picture.
    var opaque = Exercise()
    #expect(MathRecognizer.rows(in: opaque.crop, page: .init(glyphs: opaque.glyphs, opaque: [CGPoint(x: 118, y: 417)]),
                                graphics: opaque.bars, lines: opaque.lines, body: 11.96) == nil)
    // An operand a space apart from the one before it is a label that lost its bracket (Wallace
    // page 16's `33 (2)(3/2)`) or a column, not a product.
    opaque.glyphs = run("33", x: 84.96, baseline: 417.10, size: 11.96, advance: 5.85)
        + run("(2)", x: 100.68, baseline: 417.10, size: 11.96, advance: 4.6)
    opaque.bars = []
    opaque.lines = [line("33 (2)", CGRect(x: 85, y: 414, width: 30, height: 15))]
    #expect(opaque.rows() == nil)
    opaque.glyphs = run("33", x: 84.96, baseline: 417.10, size: 11.96, advance: 5.85)
        + run("(2)", x: 96.7, baseline: 417.10, size: 11.96, advance: 4.6)
    #expect(opaque.rows().map { $0.map { expression($0).linearText } } == ["33(2)"])
}

@Test func superscriptsNeedMathsItalicVariablesAndARaisedSmallerGlyph() throws {
    func page(_ glyphs: [Glyph], _ text: String) -> [MathRecognizer.Row]? {
        MathRecognizer.rows(in: CGRect(x: 80, y: 405, width: 80, height: 25), page: .init(glyphs: glyphs), graphics: [],
                            lines: [line(text, CGRect(x: 85, y: 414, width: 60, height: 15))], body: 11.96)
    }
    let base = run("4", x: 99.36, baseline: 417.10, size: 11.96, advance: 5.86)
        + run("a", x: 105.22, baseline: 417.10, size: 11.96, advance: 6.3, mathItalic: true)
    let squared = run("2", x: 111.6, baseline: 421.42, size: 7.97, advance: 4.23)
    let rest = run("+6=0", x: 118.0, baseline: 417.10, size: 11.96, advance: 7.0)
    let rows = try #require(page(base + squared + rest, "4a2+6=0"))
    #expect(expression(rows[0]).linearText == "4a^2 + 6 = 0")
    #expect(EPUBTextEncoder.mathML(rows[0].node).contains("<msup><mi>a</mi><mn>2</mn></msup>"))
    // A lowered glyph is a subscript, which is not proven here.
    var lowered = squared
    lowered[0].baseline = 413.5
    #expect(page(base + lowered + rest, "4a2+6=0") == nil)
    // An upright letter is a word, not a variable.
    var upright = base
    upright[1].mathItalic = false
    #expect(page(upright + squared + rest, "4a2+6=0") == nil)
}

@Test func signsAfterAnOperatorAreWrittenAsPrefixes() {
    let node = MathExpression.Node.row([.identifier("x"), .operator("="), .operator("\u{2212}"), .number("8")])
    #expect(EPUBTextEncoder.mathML(node) == "<mrow><mi>x</mi><mo>=</mo><mrow><mo>\u{2212}</mo><mn>8</mn></mrow></mrow>")
    #expect(MathExpression(node: node, fallbackAssetID: "a").linearText == "x = \u{2212}8")
    let display = MathExpression.Node.fraction(.number("36"), .number("84"), display: true)
    #expect(EPUBTextEncoder.mathML(display) == "<mstyle displaystyle=\"true\"><mfrac><mn>36</mn><mn>84</mn></mfrac></mstyle>")
    #expect(!MathRecognizer.valid([.operator("="), .number("8")]))
    #expect(!MathRecognizer.valid([.number("2"), .number("3")]))
    #expect(MathRecognizer.valid([.operator("\u{2212}"), .number("2")]))
}

@Test func epubWriterDeclaresMathMLOnlyWhereADocumentHoldsIt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-mathml-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("crop.bin")
    try Data([137, 80, 78, 71]).write(to: source)
    var image = ReflowBlock.Image(assetID: "a", alternativeText: "Mathematical expression")
    image.math = [MathExpression(label: "52)", node: .fraction(.number("27"), .number("3")), fallbackAssetID: "a")]
    let book = ReflowDocument(metadata: .init(title: "T", language: "en"), blocks: [
        .init(content: .sourcePage(1), page: 1),
        .init(content: .image(image), page: 1),
        .init(content: .sourcePage(2), page: 2),
        .init(content: .paragraph(InlineText("Prose")), page: 2),
    ], assets: [.init(id: "a", fileURL: source)], chapterStartPages: [2])
    let output = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: directory, progress: { _ in })
    let archive = try Archive(url: output, accessMode: .read)
    func text(_ name: String) throws -> String {
        let entry = try #require(archive[name]); var bytes = Data()
        _ = try archive.extract(entry) { bytes += $0 }
        return String(decoding: bytes, as: UTF8.self)
    }
    let chapter = try text("EPUB/chapter-1.xhtml")
    #expect(chapter.contains("<p class=\"math\">52) <math xmlns=\"http://www.w3.org/1998/Math/MathML\" alttext=\"27/3\" "
        + "altimg=\"images/image-1.png\"><mfrac><mn>27</mn><mn>3</mn></mfrac></math></p>"))
    #expect(!chapter.contains("<img"))
    let package = try text("EPUB/package.opf")
    #expect(package.contains("href=\"chapter-1.xhtml\" media-type=\"application/xhtml+xml\" properties=\"mathml\"/>"))
    #expect(package.contains("href=\"chapter-2.xhtml\" media-type=\"application/xhtml+xml\"/>"))
    // A fallback image the document does not carry fails validation.
    image.math[0].fallbackAssetID = "missing"
    let broken = ReflowDocument(metadata: book.metadata, blocks: [.init(content: .image(image), page: 1)], assets: book.assets)
    #expect(throws: ReflowDocument.ValidationError.missingAsset("missing")) { try broken.validate() }
}
