import CoreGraphics
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func sourceFractionProductsKeepTheirNumberAndWholeExpression() throws {
    let fixture = try SourceLayoutFixture.load("algebra-16")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let joined = MathExerciseRegionJoin.joined(regions, lines: page.lines,
        body: LayoutReconstructor.bodySize(page.lines))
    #expect(joined.count == regions.count)
    for label in [22, 23, 27, 28, 30, 32] {
        let stub = try #require(page.lines.first { $0.text.hasPrefix("\(label)) ") })
        #expect(!regions.contains { $0.contains(stub.rect) }, "\(label) already belongs to a crop")
        #expect(joined.contains { $0.contains(stub.rect) && $0.maxX > stub.rect.maxX + 10 },
                "\(label) is not attached to its fraction")
    }
    for label in [21, 24, 25, 26, 29, 31, 34, 35, 36] {
        let line = try #require(page.lines.first { $0.text.hasPrefix("\(label)) ") })
        #expect(joined.filter { $0.contains(line.rect) }.count == regions.filter { $0.contains(line.rect) }.count,
                "\(label) was already a whole math expression")
    }
    let instructions = try #require(page.lines.first { $0.text.hasPrefix("Find each product.") })
    #expect(!joined.contains { $0.intersects(instructions.rect) })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func exerciseFragmentJoinRefusesASecondNeighbourAndACompleteExpression() {
    let stub = TextLine(text: "22) (− 2)(−", rect: CGRect(x: 40, y: 100, width: 70, height: 18), fontSize: 12)
    let fragment = CGRect(x: 110.5, y: 101, width: 18, height: 18)
    let other = TextLine(text: "not part of expression", rect: CGRect(x: 50, y: 98, width: 45, height: 20), fontSize: 12)
    #expect(MathExerciseRegionJoin.joined([fragment], lines: [stub, other], body: 12) == [fragment])
    let complete = TextLine(text: "22) (− 2)(− 5/6)", rect: stub.rect, fontSize: 12)
    #expect(MathExerciseRegionJoin.joined([fragment], lines: [complete], body: 12) == [fragment])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func graphAnswersKeepTheirPrintedGraphAssociations() throws {
    let fixture = try SourceLayoutFixture.load("algebra-483")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: regions.enumerated().map { ($0.element, "graph-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    #expect(regions.count == 18)
    let labels = blocks.map(\.text).compactMap { text -> Int? in
        guard text.hasSuffix(")") else { return nil }
        return Int(text.dropLast())
    }
    #expect(labels == Array(1...18))
    for number in 1...18 {
        let index = try #require(blocks.firstIndex { $0.text == "\(number))" })
        guard case .image(let image) = blocks[index + 1].content else {
            Issue.record("Graph \(number) lost its immediately following image"); continue
        }
        #expect(image.assetID == "graph-\(number - 1)")
    }
    // Each source graph has a distinctive printed coordinate. Those marks must stay in the
    // region paired with its printed answer number, so reordering images alone fails the test.
    let distinctive = [
        "(0,-8) (1,-9)", "(0, -3) (1, -4)", "(3,-8)", "(3, -2)", "(0,-18)", "(-10,0)",
        "(0,-45)", "(-9,0)", "(2,9)", "(1,0) (2,1)", "(3,4)", "(0,-30)",
        "(0,-24)", "(-1,-8) (0,-6)", "(-2,-3)", "(0,45)", "(4,-5)", "(-2,-5)",
    ]
    for (offset, coordinate) in distinctive.enumerated() {
        let source = try #require(page.lines.first { $0.text == coordinate })
        #expect(regions[offset].intersects(source.rect), "Graph \(offset + 1) lost \(coordinate)")
    }
}
