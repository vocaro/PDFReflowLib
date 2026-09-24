import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func wallaceComplexAnswerPageKeepsBothAnswerSections() throws {
    let fixture = try SourceLayoutFixture.load("algebra-479")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let title = try #require(page.lines.first { $0.text == "Answers - Quadratic Formula" })
    #expect(crops.allSatisfy { !$0.intersects(title.rect) })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let ordered = blocks.map { block in
        if case .image(let image) = block.content { return image.assetID }
        return block.text
    }
    let section = try #require(ordered.firstIndex(of: "9.4"))
    let heading = try #require(ordered.firstIndex(of: "Answers - Quadratic Formula"))
    let lastUpperLeft = try #require(ordered.firstIndex(of: "image-1"))
    let firstUpperRight = try #require(ordered.firstIndex(of: "image-3"))
    let lastUpperRight = try #require(ordered.firstIndex(of: "image-5"))
    let lowerLeft = try #require(ordered.firstIndex(of: "image-6"))
    let lowerLeftEnd = try #require(ordered.firstIndex(of: "image-2"))
    let lowerRight = try #require(ordered.firstIndex(of: "image-4"))
    let lowerRightEnd = try #require(ordered.firstIndex(of: "image-7"))
    #expect(lastUpperLeft < firstUpperRight && lastUpperRight < section)
    #expect(section < heading && heading < lowerLeft)
    #expect(lowerLeft < lowerLeftEnd && lowerLeftEnd < lowerRight && lowerRight < lowerRightEnd)
}
