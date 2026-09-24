import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func wallaceComplexFractionsRequireFiveProvenBarsAndEveryGlyph() throws {
    let fixture = try SourceLayoutFixture.load("algebra-262")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 262)
    let source = URL(fileURLWithPath: "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")
    let document = try #require(PDFDocument(url: source))
    let reference = try #require(document.page(at: 261)?.pageRef)
    let glyphs = try NativeTextReader.withExtractionLock { MathRecognizer.glyphs(on: reference) }
    let content = fixture.content()
    let body = LayoutReconstructor.bodySize(content.lines)
    let crop = try #require(LayoutReconstructor.graphicsWithLabels(content).first {
        490 < $0.minY && $0.minY < 505 && $0.width < 40
    })
    let row = try #require(MathRecognizer.rows(in: crop, page: glyphs, graphics: content.graphics,
                                                lines: content.lines, body: body)?.only)
    #expect(row.node == .fraction(
        .row([.fraction(.number("2"), .number("3")), .operator("−"),
              .fraction(.number("1"), .number("4"))]),
        .row([.fraction(.number("5"), .number("6")), .operator("+"),
              .fraction(.number("1"), .number("2"))]), display: true))
    #expect(row.rect == crop)

    let bars = content.graphics.filter { crop.contains($0) }
    #expect(bars.count == 5)
    let outer = try #require(bars.max(by: { $0.width < $1.width }))
    #expect(MathRecognizer.rows(in: crop, page: glyphs,
                                graphics: content.graphics.filter { $0 != outer },
                                lines: content.lines, body: body) == nil)
    let small = try #require(bars.first { $0 != outer })
    #expect(MathRecognizer.rows(in: crop, page: glyphs,
                                graphics: content.graphics.filter { $0 != small },
                                lines: content.lines, body: body) == nil)
    var missingGlyph = glyphs
    missingGlyph.glyphs.removeAll { crop.contains($0.center) && $0.text == "−" }
    #expect(MathRecognizer.rows(in: crop, page: missingGlyph, graphics: content.graphics,
                                lines: content.lines, body: body) == nil)
    let crossed = content.graphics.map { $0 == outer
        ? CGRect(x: outer.minX, y: outer.minY, width: small.width, height: outer.height) : $0 }
    #expect(MathRecognizer.rows(in: crop, page: glyphs, graphics: crossed,
                                lines: content.lines, body: body) == nil)
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
