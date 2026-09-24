import CoreGraphics
import Testing
@testable import PDFReflowLib

@Test(arguments: [52, 62])
func aggregatePageArtworkPreservesConservativeNativeText(number: Int) throws {
    // Captured before ICC white was guessed: these are the source's actual painted
    // footprints, including the ICC fills whose white requires a profile transform.
    let fixture = try SourceLayoutFixture.load("noaa-aggregate-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    let original = fixture.content()
    #expect(original.graphics.contains { PageDiagnosis.coversPage($0, bounds: original.bounds) })
    #expect(!fixture.paints.contains { PageDiagnosis.coversPage($0.rect, bounds: original.bounds) })
    var page = TextBackdrop.compose(original, graphics: .init(regions: original.graphics,
        unsupported: false, images: original.pictures, paints: fixture.paints))
    #expect(page.graphics == original.graphics)
    PageDiagnosis.prepareExtracted(&page, evidence: PageEvidence(requiresPageImage: false,
        hasText: true, characters: page.lines.reduce(0) { $0 + $1.text.count }, replacementCharacters: 0,
        imageBackedText: page.graphics.contains { PageDiagnosis.coversPage($0, bounds: page.bounds) },
        damagedEncoding: false, implausibleLayer: nil, drawnText: false))
    #expect(page.preservePageReference)
    #expect(page.graphics.isEmpty)
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images,
        context: .init(language: "en", documentBody: 10), warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: " ")
    #expect(text.contains(number == 52
        ? "Losses due to floods are projected to increase disproportionately in US Census tracts"
        : "Box 1.3. Indigenous Ways of Life and Spiritual Health"))
}

@Test func aFlatBackdropCannotAuthorizeSplittingASeparatePageSizedPhotograph() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let lines = (0..<3).map { index in
        TextLine(text: "A complete native paragraph with several ordinary words on each row",
            rect: CGRect(x: 40, y: 300 - index * 14, width: 400, height: 14), fontSize: 10)
    }
    let original = PageContent(number: 1, bounds: bounds, lines: lines, graphics: [bounds], pictures: [bounds])
    let flat = GraphicsReader.Paint(rect: bounds, image: false, filled: true, rectangular: true, vertices: [])
    let image = GraphicsReader.Paint(rect: bounds, image: true, filled: false, rectangular: true, vertices: [])
    let result = TextBackdrop.compose(original, graphics: .init(regions: [bounds], unsupported: false,
        images: [bounds], paints: [flat, image]))
    #expect(result.graphics == original.graphics)
    #expect(result.nativeTextPanels == nil)
}
