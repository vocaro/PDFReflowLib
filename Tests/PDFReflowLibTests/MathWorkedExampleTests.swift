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
    let page = try #require(document.page(at: 288))
    let reference = try #require(page.pageRef)
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

    // Example 379's fourth note prints the ﬃ ligature. The text line and its source
    // glyph must agree after the same compatibility normalization on both sides.
    let middle = try #require(crops.first { 330 < $0.minY && $0.minY < 345 })
    let intermediate = try #require(MathRecognizer.workedRows(in: middle, page: glyphs,
                                      graphics: content.graphics, lines: content.lines, body: body))
    var rasterOptions = ConversionOptions()
    rasterOptions.rasterDPI = 144
    for row in intermediate.dropFirst() {
        var inkRows: [Int] = []
        _ = try PageRasterizer.image(page: page, rect: row.rect, options: rasterOptions) {
            bytes, width, height, stride in
            for y in 0..<height where (0..<width).contains(where: { x in
                let offset = y * stride + x * 4
                return bytes[offset] < 120 && bytes[offset + 1] < 120 && bytes[offset + 2] < 120
            }) { inkRows.append(y) }
        }
        // Source ink leaves a blank band above each equation. A taller fallback crop
        // used to bring the preceding row's ink into its first pixels.
        #expect(inkRows.first.map { $0 >= 5 } == true)
    }
    #expect(intermediate.map(\.node) == [
        .row([.number("5"), .squareRoot(.number("63"))]),
        .row([.number("5"), .squareRoot(.row([.number("9"), .operator("⋅"), .number("7")]))]),
        .row([.number("5"), .squareRoot(.number("9")), .operator("⋅"), .squareRoot(.number("7"))]),
        .row([.number("5"), .operator("⋅"), .number("3"), .squareRoot(.number("7"))]),
        .row([.number("15"), .squareRoot(.number("7"))]),
    ])
    #expect(intermediate.map(\.note) == [
        "63 is divisible by 9, a perfect square", "Split into factors",
        "Product rule, take the square root of 9", "Multiply coeﬃcients", "Our Solution",
    ])
    var missingLigature = glyphs
    missingLigature.glyphs.removeAll { middle.contains($0.center) && $0.text == "ﬃ" }
    #expect(MathRecognizer.workedRows(in: middle, page: missingLigature,
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
