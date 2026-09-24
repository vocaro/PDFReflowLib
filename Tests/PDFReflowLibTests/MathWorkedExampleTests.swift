import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func wallaceWorkedRootsKeepTheSourceNotesBesideEachMathRow() throws {
    let fixture = try SourceLayoutFixture.load("algebra-289")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 289)
    let source = URL(fileURLWithPath: "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")
    let document = try #require(PDFDocument(url: source))
    let reference = try #require(document.page(at: 288)?.pageRef)
    let glyphs = try NativeTextReader.withExtractionLock { MathRecognizer.glyphs(on: reference) }
    let content = fixture.content()
    let body = LayoutReconstructor.bodySize(content.lines)
    let crops = LayoutReconstructor.graphicsWithLabels(content)
    let first = try #require(crops.first { 550 < $0.minY && $0.minY < 560 })
    let rows = try #require(MathRecognizer.workedRows(in: first, page: glyphs,
        graphics: content.graphics, lines: content.lines, body: body))
    #expect(rows.map(\.node) == [
        .squareRoot(.number("75")),
        .squareRoot(.row([.number("25"), .operator("⋅"), .number("3")])),
        .row([.squareRoot(.number("25")), .operator("⋅"), .squareRoot(.number("3"))]),
        .row([.number("5"), .squareRoot(.number("3"))]),
    ])
    #expect(rows.map(\.note) == [
        "75 is divisible by 25, a perfect square", "Split into factors",
        "Product rule, take the square root of 25", "Our Solution",
    ])
    #expect(rows.allSatisfy { $0.rect.maxX < 232 })

    let third = try #require(crops.first { 70 < $0.minY && $0.minY < 85 })
    let later = try #require(MathRecognizer.workedRows(in: third, page: glyphs,
        graphics: content.graphics, lines: content.lines, body: body))
    #expect(later.count == 7)
    #expect(later.last?.note == "Multiply")

    // Example 379's text line does not reconcile with the complete source glyph crop.
    // Its equation and notes stay together in the original image until that can be proven.
    let middle = try #require(crops.first { 330 < $0.minY && $0.minY < 345 })
    #expect(MathRecognizer.workedRows(in: middle, page: glyphs,
                                      graphics: content.graphics, lines: content.lines, body: body) == nil)
    var missingNote = glyphs
    missingNote.glyphs.removeAll { first.contains($0.center) && $0.minX > 232 && $0.text == "O" }
    #expect(MathRecognizer.workedRows(in: first, page: missingNote,
                                      graphics: content.graphics, lines: content.lines, body: body) == nil)
    let crossedNote = content.graphics.map { bar in
        first.contains(bar) && bar.midY > 620
            ? CGRect(x: bar.minX, y: bar.minY, width: 45, height: bar.height) : bar
    }
    #expect(MathRecognizer.workedRows(in: first, page: glyphs, graphics: crossedNote,
                                      lines: content.lines, body: body) == nil)
}
