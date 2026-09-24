import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func wallaceSlopeFractionNeedsSourceProvenLoweredSubscripts() throws {
    let fixture = try SourceLayoutFixture.load("algebra-98")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 98)
    let document = try #require(PDFDocument(url: URL(fileURLWithPath:
        "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")))
    let reference = try #require(document.page(at: 97)?.pageRef)
    let source = fixture.content()
    let crop = try #require(LayoutReconstructor.graphicsWithLabels(source).first {
        539 < $0.minY && $0.minY < 540 && $0.width < 41
    })
    let glyphs = try NativeTextReader.withExtractionLock { MathRecognizer.glyphs(on: reference) }
    let body = LayoutReconstructor.bodySize(source.lines)
    func rows(_ page: MathRecognizer.PageGlyphs) -> [MathRecognizer.Row]? {
        MathRecognizer.rows(in: crop, page: page, graphics: source.graphics,
                            lines: source.lines, body: body)
    }
    let row = try #require(rows(glyphs)?.first)
    #expect(row.label == nil)
    #expect(row.node == .fraction(
        .row([.subscript(.identifier("y"), .number("2")), .operator("−"),
              .subscript(.identifier("y"), .number("1"))]),
        .row([.subscript(.identifier("x"), .number("2")), .operator("−"),
              .subscript(.identifier("x"), .number("1"))]), display: true))
    #expect(rows(glyphs)?.count == 1)
    #expect(glyphs.opaque.allSatisfy { !crop.contains($0) })

    var missingDigit = glyphs
    missingDigit.glyphs.removeAll { crop.contains($0.center) && $0.text == "2" && $0.baseline > 560 }
    #expect(rows(missingDigit) == nil) // The text line's printed digit no longer reconciles.
    var levelDigit = glyphs
    for index in levelDigit.glyphs.indices where crop.contains(levelDigit.glyphs[index].center)
        && levelDigit.glyphs[index].size < 10 {
        let digit = levelDigit.glyphs[index]
        levelDigit.glyphs[index].baseline = digit.baseline > 560 ? 567.81991 : 552.81993
    }
    #expect(rows(levelDigit) == nil) // A smaller but unlowered glyph is not a subscript.
    var uprightVariable = glyphs
    let variable = try #require(uprightVariable.glyphs.firstIndex {
        crop.contains($0.center) && $0.text == "x"
    })
    uprightVariable.glyphs[variable].mathItalic = false
    #expect(rows(uprightVariable) == nil)
    var opaque = glyphs
    opaque.opaque.append(crop.center)
    #expect(rows(opaque) == nil)
}

private extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
