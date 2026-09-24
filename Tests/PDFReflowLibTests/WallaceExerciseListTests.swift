import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func wallaceTextExercisesUseTheirPrintedOrdinalsInRealLists() throws {
    let fixture = try SourceLayoutFixture.load("algebra-10")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    var warnings: [ConversionWarning] = []
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let built = ListBuilder.build(blocks)
    let items = built.compactMap { block -> ReflowBlock.ListItem? in
        if case let .listItem(item) = block.content { return item }
        return nil
    }
    #expect(items.compactMap(\.ordinal) == Array(1...44))
    #expect(items.allSatisfy { $0.kind == .ordered })
    func hasOrdinal(_ block: ReflowBlock, _ number: Int) -> Bool {
        if case let .listItem(item) = block.content { return item.ordinal == number }
        return false
    }
    let thirty = try #require(built.firstIndex { hasOrdinal($0, 30) })
    let instruction = try #require(built.firstIndex { $0.text.hasPrefix("Find each product.") })
    let thirtyOne = try #require(built.firstIndex { hasOrdinal($0, 31) })
    #expect(thirty < instruction && instruction < thirtyOne)
}
