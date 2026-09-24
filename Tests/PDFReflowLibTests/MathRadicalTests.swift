import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func wallaceSquareRootExercisesUseTheirGlyphAndVinculum() throws {
    let fixture = try SourceLayoutFixture.load("algebra-291")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 291)
    let source = URL(fileURLWithPath: "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")
    let document = try #require(PDFDocument(url: source))
    let reference = try #require(document.page(at: 290)?.pageRef)
    let glyphs = try NativeTextReader.withExtractionLock { MathRecognizer.glyphs(on: reference) }
    let content = fixture.content()
    let body = LayoutReconstructor.bodySize(content.lines)
    let crop = try #require(LayoutReconstructor.graphicsWithLabels(content).first {
        $0.minX < 100 && $0.height > 500 && $0.width < 120
    })
    let slices = try #require(MathRecognizer.radicalExerciseSlices(in: crop, page: glyphs,
        graphics: content.graphics, lines: content.lines, body: body))
    #expect(slices.count >= 10)
    #expect(abs(slices.map(\.height).reduce(0, +) - crop.height) < 0.01)
    let parsed = slices.flatMap { MathRecognizer.rows(in: $0, page: glyphs,
        graphics: content.graphics, lines: content.lines, body: body) ?? [] }
    let first = try #require(parsed.first { $0.label == "1)" })
    #expect(first.node == .squareRoot(.number("245")))
    #expect(parsed.contains { $0.label == "3)" && $0.node == .squareRoot(.number("36")) })
    #expect(parsed.contains { $0.label == "5)" && $0.node == .squareRoot(.number("12")) })

    let firstRow = try #require(slices.first { slice in
        MathRecognizer.rows(in: slice, page: glyphs, graphics: content.graphics,
                            lines: content.lines, body: body)?.contains { $0.label == "1)" } == true
    })
    // The source line reads `1) 245 √`; only the glyph positions and painted bar establish
    // `1) √245`. Neither a text-only root nor an unrelated long rule may become MathML.
    #expect(content.lines.contains { $0.text == "1) 245 √" })
    var missingRoot = glyphs
    missingRoot.glyphs.removeAll { $0.text == "√" && firstRow.contains($0.center) }
    #expect(MathRecognizer.rows(in: firstRow, page: missingRoot, graphics: content.graphics,
                                lines: content.lines, body: body) == nil)
    let firstBar = try #require(content.graphics.first { firstRow.contains($0) })
    #expect(MathRecognizer.rows(in: firstRow, page: glyphs,
                                graphics: content.graphics.filter { $0 != firstBar },
                                lines: content.lines, body: body) == nil)
    let longRules = content.graphics.map { rect in
        crop.contains(rect) ? CGRect(x: rect.minX, y: rect.minY, width: body * 8, height: rect.height) : rect
    }
    #expect(MathRecognizer.radicalExerciseSlices(in: crop, page: glyphs, graphics: longRules,
                                                 lines: content.lines, body: body) == nil)
}
