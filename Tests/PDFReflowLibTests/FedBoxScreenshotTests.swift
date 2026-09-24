import Foundation
import Testing
@testable import PDFReflowLib

/// The last line of each Federal Reserve box stands above its screenshot. The surrounding
/// box outline spans both, so the screenshot crop must stop before that prose line (#169).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/169"), arguments: [
    (126, "with the Federal Reserve."),
    (132, "other tools to achieve this goal."),
])
func fedBoxFinalLineReflowsOutsideTheScreenshot(page number: Int, phrase: String) throws {
    let fixture = try SourceLayoutFixture.load("fed-\(number)")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    let page = fixture.content()
    let line = try #require(page.lines.first { $0.text == phrase })
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(crops.count == 2) // running-head rule and the box's screenshot
    #expect(crops.allSatisfy { !LayoutReconstructor.takes($0, line) }, "page \(number): \(crops)")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "region-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    #expect(blocks.contains { $0.hasReflowedText && $0.text.contains(phrase) })
}

/// A NOAA boxed figure has prose both above and below its image. Its picture is narrower than
/// the whole box, so trimming the full crop to that picture would lose the box's own caption.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/169"))
func narrowerNOAABoxWithFigureCaptionKeepsItsFullCrop() throws {
    let fixture = try SourceLayoutFixture.load("noaa-701")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    let page = fixture.content()
    let picture = try #require(page.pictures.first)
    let crop = try #require(LayoutReconstructor.graphicsWithLabels(page).first { $0.contains(picture) })
    #expect(crop.maxY > picture.maxY + 100)
    #expect(crop.minY < picture.minY - 100)
}
