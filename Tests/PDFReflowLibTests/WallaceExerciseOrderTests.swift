import Foundation
import Testing
@testable import PDFReflowLib

private func wallaceOrder(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    return LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
}

private func exerciseNumbers(_ blocks: [ReflowBlock]) -> [Int] {
    blocks.compactMap { block in
        let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^\d{1,3}\)"#, options: .regularExpression) != nil else { return nil }
        return Int(text.prefix(while: \.isNumber))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func wallaceExerciseRowsFollowTheirNumbersBeforeTheNextInstruction() throws {
    let fixture = try SourceLayoutFixture.load("algebra-10")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 10)
    let blocks = wallaceOrder(fixture.content())
    #expect(exerciseNumbers(blocks) == Array(1...44))
    let text = blocks.map(\.text)
    let instruction = try #require(text.firstIndex(where: { $0.hasPrefix("Find each product.") }))
    let thirty = try #require(text.firstIndex(where: { $0.hasPrefix("30)") }))
    let thirtyOne = try #require(text.firstIndex(where: { $0.hasPrefix("31)") }))
    #expect(thirty < instruction && instruction < thirtyOne)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func wallaceDiagramExercisesKeepEachPairInRowOrder() throws {
    let fixture = try SourceLayoutFixture.load("algebra-424")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 424)
    let blocks = wallaceOrder(fixture.content())
    #expect(exerciseNumbers(blocks) == Array(13...20))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func threeColumnAnswerKeysAndTwoColumnProseKeepTheirColumnOrder() throws {
    let key = try SourceLayoutFixture.load("algebra-478")
    #expect(key.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    // Source page 478's 9.2 key has three columns: 1–9, 10–17, then 18–24. The
    // expressions can grow into picture crops, so test the printed marker geometry here.
    let markers = key.content().lines.filter { line in
        line.rect.minY > 490 && line.text.range(of: #"^\d{1,2}\)"#, options: .regularExpression) != nil
    }.map { LayoutReconstructor.Element(rect: $0.rect, line: $0, image: nil) }
    let ordered = LayoutReconstructor.ordered(markers, bodySize: 12).compactMap { $0.line?.text }
    let nine = try #require(ordered.firstIndex(where: { $0.hasPrefix("9)") }))
    let ten = try #require(ordered.firstIndex(where: { $0.hasPrefix("10)") }))
    let eighteen = try #require(ordered.firstIndex(where: { $0.hasPrefix("18)") }))
    #expect(nine < ten && ten < eighteen)

    let prose = try SourceLayoutFixture.load("faa-91")
    #expect(prose.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    let paragraphs = wallaceOrder(prose.content()).map(\.text).joined(separator: " ")
    let right = try #require(paragraphs.range(of: "The computation of density altitude"))
    let left = try #require(paragraphs.range(of: "identify the same level."))
    #expect(left.lowerBound < right.lowerBound)
}
