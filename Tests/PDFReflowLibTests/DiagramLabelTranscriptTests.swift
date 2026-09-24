import Foundation
import Testing
@testable import PDFReflowLib

@Test func wallaceDiagramLabelsOverlayTheSourceWithoutVisibleCaptionDuplication() throws {
    let fixture = try SourceLayoutFixture.load("algebra-423")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    let marker = try #require(page.lines.first { $0.text.hasPrefix("7) sin") })
    let triangle = try #require(images.first { $0.0.contains(marker.rect) })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    let block = try #require(blocks.first { block in
        if case let .image(image) = block.content { return image.assetID == triangle.1 }
        return false
    })
    guard case let .image(image) = block.content else { return }
    let side = try #require(image.selectableLabels.first { $0.text == "16" })
    let sourceSide = try #require(page.lines.first { $0.text == "16" })
    #expect(abs(side.left - Double((sourceSide.rect.minX - triangle.0.minX) / triangle.0.width)) < 0.001)
    #expect(abs(side.top - Double((triangle.0.maxY - sourceSide.rect.maxY) / triangle.0.height)) < 0.001)
    #expect(image.caption == "Preserved region from page 423")
    let markup = try EPUBTextEncoder.payload(block, imagePaths: [triangle.1: "triangle.png"])
    #expect(markup.contains("class=\"source-diagram\""))
    #expect(markup.contains("class=\"diagram-label\""))
    #expect(markup.contains(">16</span>"))
    #expect(markup.contains(">7) sin θ</span>"))
    #expect(markup.contains("<figcaption>Preserved region from page 423</figcaption>"))
}

@Test func fractionCropDoesNotClaimDiagramLabelTranscript() {
    let labels = [TextLine(text: "7)", rect: CGRect(x: 20, y: 40, width: 10, height: 10), fontSize: 10),
                  TextLine(text: "16", rect: CGRect(x: 50, y: 25, width: 10, height: 10), fontSize: 10)]
    let bar = CGRect(x: 20, y: 35, width: 40, height: 3)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                           lines: labels, graphics: [bar])
    let labelsByImage = DiagramLabelTranscript.labels(page: page,
        images: [(CGRect(x: 15, y: 20, width: 50, height: 35), "bar")], body: 10)
    #expect(labelsByImage.isEmpty)
}

@Test func wallaceTriangleLabelsAllHaveNativeTextOverlays() throws {
    let fixture = try SourceLayoutFixture.load("algebra-427")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    let figures = blocks.compactMap { block -> ReflowBlock.Image? in
        if case let .image(image) = block.content { return image }
        return nil
    }
    #expect(images.count == 4)
    #expect(figures.count == 4)
    #expect(figures.allSatisfy { !$0.selectableLabels.isEmpty })
    #expect(figures.contains { image in
        image.selectableLabels.contains { $0.text == "18.1" }
            && image.selectableLabels.contains { $0.text == "A x" }
    })
    #expect(figures.allSatisfy { $0.caption == "Preserved region from page 427" })
}
