import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/17"))
func fedScreenshotHasValidatedSingleImageAltButVectorChartDoesNot() throws {
    let source = URL(fileURLWithPath: "corpus/cache/the-fed-explained.pdf")
    let fixture = try SourceLayoutFixture.load("fed-126")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    let tree = try StructureTreeReader.read(source)
    let document = try #require(CGPDFDocument(source as CFURL))
    let screenshot = try #require(document.page(at: 126))
    let figures = try #require(tree.figures[126])
    let alt = try #require(figures[10])
    #expect(alt.contains("Federal Reserve Consumer Help"))
    #expect(StructureTreeReader.validates(ids: [10], owners: try #require(tree.figureOwners[126]), page: screenshot))
    let draws = MarkedImageReader.read(screenshot, ids: [10])
    let draw = try #require(draws[10])
    let image = try #require(fixture.content().pictures.first)
    let overlap = draw.intersection(image)
    #expect(overlap.width * overlap.height > image.width * image.height * 0.9)
    let pageSource = try PDFPageSource(url: source)
    let extracted = try PageReader.read(pageIndex: 125, from: pageSource, limit: 100_000,
                                        options: ConversionOptions(), structure: tree)
    #expect(extracted.content.taggedFigures.count == 1)
    #expect(extracted.content.taggedFigures[0].alternativeText == alt)
    let crops = LayoutReconstructor.graphicsWithLabels(extracted.content)
    let assets = crops.enumerated().map { ($0.element, "region-\($0.offset)") }
    let described = assets.compactMap { pair in
        PDFReflowLibPipeline.figureAlt(for: pair.1, images: assets,
                                      figures: extracted.content.taggedFigures)
    }
    #expect(described == [alt])
    #expect(PDFReflowLibPipeline.figureAlt(for: "missing", images: assets,
                                          figures: extracted.content.taggedFigures) == nil)

    // The page 102 line graph has a Figure/Alt with MCID 2, but that MCID draws an
    // outline path; the chart is painted by multiple marked sections. It owns no single
    // image crop and must retain the converter's ordinary preserved-region description.
    let chart = try #require(document.page(at: 102))
    #expect(tree.figures[102]?[2] != nil)
    #expect(MarkedImageReader.read(chart, ids: [2])[2] == nil)
    let chartPage = try PageReader.read(pageIndex: 101, from: pageSource, limit: 100_000,
                                        options: ConversionOptions(), structure: tree)
    #expect(chartPage.content.taggedFigures.isEmpty)
}
