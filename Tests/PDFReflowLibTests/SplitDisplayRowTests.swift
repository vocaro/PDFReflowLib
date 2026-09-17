import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// A crop never keeps half a display row (#46, #48). PDFKit breaks a displayed equation's row at a
// raised exponent or a fraction, and the crop grown from the fraction bars stopped at the break, so
// the leading term reflowed beside the image as flattened text (`x2 +` on Wallace page 343's
// "Factor" line) and an answer entry was split between a marker stub and its fraction (`22)− 2,` on
// page 471). Fixtures are native extraction from the checksum-pinned Wallace book; the expected
// expressions and the labels were read from the rendered source pages.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

private func sourcePage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == algebraSHA256)
    var page = fixture.content()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    return page
}

private func reconstruct(_ name: String) throws -> (page: PageContent, blocks: [ReflowBlock], crops: [CGRect]) {
    let page = try sourcePage(name)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    return (page, blocks, crops)
}

private func expectCropped(_ result: (page: PageContent, blocks: [ReflowBlock], crops: [CGRect]), _ texts: [String],
                           sourceLocation: SourceLocation = #_sourceLocation) throws {
    for text in texts {
        let line = try #require(result.page.lines.first { $0.text == text },
                                "no source line \(text)", sourceLocation: sourceLocation)
        #expect(result.crops.contains { $0.intersects(line.rect) },
                "\(text) is outside every crop", sourceLocation: sourceLocation)
        #expect(!result.blocks.contains { $0.text.trimmingCharacters(in: .whitespaces) == text },
                "\(text) still reflows as its own block", sourceLocation: sourceLocation)
    }
}

// Page 343, the quadratic-formula derivation: the "Factor" row is x² + (b/a)x + b²/4a² = …, and its
// leading piece stands 0.53 pt clear of the crop that holds the rest. It belongs to the preserved
// equation, while the introductory sentence and the closing prose reflow as before (#46).
@Test func derivationLeadingTermJoinsItsEquationImage() throws {
    let result = try reconstruct("algebra-343")
    try expectCropped(result, ["x2 +"])
    #expect(!result.blocks.contains { $0.text.contains("x2 +") && !$0.text.contains("quadratic") })
    let texts = result.blocks.map(\.text)
    #expect(texts.contains { $0.contains("The general from of a quadratic is ax2 + bx + c = 0.") })
    #expect(texts.contains("Objective: Solve quadratic equations by using the quadratic formula."))
    #expect(texts.contains("Example 465."))
    #expect(texts.contains { $0.contains("This solution is a very important one to us.") })
    // The "Our Solution" line stays inside a preserved region, as the glyph contract requires.
    let solution = try #require(result.page.lines.first { $0.text.contains("x =− b ± b2") })
    #expect(result.crops.contains { $0.intersects(solution.rect) })
}

// Page 16, "0.2 Practice - Fractions": exercises 22, 23, 27, 28, 30 and 32 opened with a marker and
// a sign set against their fraction. Each is now one region; both instructions still reflow, and the
// instruction for the products follows every crop of the first exercise set (#48).
@Test func fractionExerciseMarkersJoinTheirOwnRegions() throws {
    let result = try reconstruct("algebra-16")
    try expectCropped(result, ["22) (− 2)(−", "23) (2)(−", "27) (−", "28) (−", "30) (− 2)(−", "32) (−"])
    let texts = result.blocks.map(\.text)
    #expect(texts.contains("0.2 Practice - Fractions"))
    #expect(texts.contains("Simplify each. Leave your answer as an improper fraction."))
    let product = try #require(texts.firstIndex(of: "Find each product."))
    let images = result.blocks.indices.filter { if case .image = result.blocks[$0].content { true } else { false } }
    #expect(images.filter { $0 < product }.count == 20)
    #expect(images.filter { $0 > product }.count == 16)
    // No entry is left as a bare marker-and-sign stub.
    #expect(!result.blocks.contains { $0.text.range(of: #"^[0-9]+\)\s*\(?\s*−?\s*$"#, options: .regularExpression) != nil })
}

// Page 471: 7.7 answers 22 and 29 were emitted as `22)− 2,` and `29)−` before their fraction images.
// The thirty 7.8 dimensional-analysis answers, which are whole text entries, are the control (#48).
@Test func answerKeyFractionEntriesJoinTheirFractionImages() throws {
    let result = try reconstruct("algebra-471")
    try expectCropped(result, ["22)− 2,", "29)−"])
    let texts = result.blocks.map(\.text)
    for kept in ["21) 0, 5", "23) 4, 7", "28) 1", "33)− 10", "1) 12320 yd", "30) 621,200 mg; 1.42 lb"] {
        #expect(texts.contains(kept), "lost \(kept)")
    }
    #expect(texts.contains("Answers - Dimensional Analysis"))
}

// Page 424, right-triangle answers: the side length `13` and the vertex label `A` are drawn against
// their triangle and belong to it, while every exercise number stays a text entry of its own.
@Test func diagramLabelsJoinTheirDiagramButExerciseNumbersDoNot() throws {
    let result = try reconstruct("algebra-424")
    try expectCropped(result, ["13"])
    let texts = result.blocks.map(\.text)
    for number in 13...20 {
        #expect(texts.contains("\(number))"), "lost exercise number \(number))")
    }
}

// Controls on the rule itself, at Wallace page 340's measured geometry: the crop reaches x 113.4 and
// holds `− 3x +`, the rest of the row `x² − 3x + 9/4 = …`. Only a wordless piece that all but
// touches the crop and shares that row joins it.
@Test func onlyAnAdjoiningWordlessRowPieceJoinsACrop() {
    let crop = CGRect(x: 113.4, y: 260.4, width: 296.4, height: 163.1)
    let rowMate = CGRect(x: 115.4, y: 225.6 + 100, width: 34.9, height: 20.4)
    func piece(_ text: String, width: CGFloat = 11, gap: CGFloat, y: CGFloat = 234.7 + 100) -> TextLine {
        TextLine(text: text, rect: CGRect(x: crop.minX - gap - width, y: y, width: width, height: 12.7), fontSize: 12)
    }
    func joins(_ line: TextLine) -> Bool {
        LayoutReconstructor.adjoinsRow(line, bounds: crop, admitted: [rowMate])
    }
    // Page 340's own distance, and the widest measured across the gated corpus (page 471's `22)− 2,`).
    #expect(joins(piece("x2", gap: 0.008)))
    #expect(joins(piece("22)− 2,", width: 42.6, gap: 0.628)))
    #expect(joins(piece("x2 +", width: 22, gap: 0.53)))
    // A real word space separates two entries: NOAA's reference number `396.` stands 0.87 pt clear.
    #expect(!joins(piece("x2", gap: 0.87)))
    #expect(!joins(piece("21)", width: 16.3, gap: 1.965)))
    // A bare list marker is a separable entry number even where it touches.
    #expect(!joins(piece("41)", width: 16, gap: 0.008)))
    #expect(!joins(piece("396.", width: 20, gap: 0.008)))
    // An explanation set beside the derivation carries a word and reflows.
    #expect(!joins(piece("Factor", width: 33, gap: 0.008)))
    #expect(!joins(piece("Separate constant from variables", width: 162, gap: 0.008)))
    // A piece on another row, or inside the crop's own span, never joins.
    #expect(!joins(piece("x2", gap: 0.008, y: 120)))
    #expect(!joins(TextLine(text: "x2", rect: CGRect(x: 200, y: 334.7, width: 11, height: 12.7), fontSize: 12)))
    // A piece on the crop's right edge joins on the same terms.
    #expect(joins(TextLine(text: "+ 5", rect: CGRect(x: crop.maxX + 0.2, y: 334.7, width: 18, height: 12.7), fontSize: 12)))
    // Code and preformatted pieces keep their own representation.
    var monospaced = piece("x2", gap: 0.008)
    monospaced.monospaced = true
    #expect(!joins(monospaced))
    // With nothing of the row admitted there is no row to complete.
    #expect(!LayoutReconstructor.adjoinsRow(piece("x2", gap: 0.008), bounds: crop, admitted: []))
}
