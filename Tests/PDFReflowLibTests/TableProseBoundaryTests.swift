import CoreGraphics
import Testing
@testable import PDFReflowLib

@Test func recoveredStaffRowsDoNotAbsorbTheFollowingCopyrightParagraph() throws {
    let fixture = try SourceLayoutFixture.load("usda-magazine-3")
    let page = TextBackdrop.compose(fixture.content(), graphics: .init(regions: fixture.content().graphics,
        unsupported: false, images: fixture.content().pictures, paints: fixture.paints))
    let rows = TableRegionDetector.rowBlocks(in: page.lines, body: 8.5)
    let copyright = page.lines.filter { $0.rect.minX < 40 && $0.rect.minY > 399 && $0.rect.minY < 431 }
    #expect(copyright.count == 4)
    #expect(copyright.allSatisfy { line in !rows.contains { $0.insetBy(dx: -1, dy: -1).contains(line.rect) } })
    let contact = try #require(page.lines.first { $0.text == "Art Director: BA Allen" })
    #expect(rows.contains { $0.contains(contact.rect) })
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    #expect(paragraphTexts(blocks).contains { $0.contains("Most information in this magazine is public property")
        && $0.contains("resolution digital photos are available at ars.usda.gov/ar.") })
    #expect(!blocks.contains { block in
        if case .preformatted = block.content { return block.text.contains("Most information") }
        return false
    })
}

@Test func wrappedTableCellsWithoutAParagraphGapKeepTheirRows() throws {
    let fixture = try SourceLayoutFixture.load("usda-magazine-3")
    var lines = fixture.content().lines.filter { $0.rect.minX < 240 && $0.rect.minY > 399 && $0.rect.minY < 510 }
    // Remove the paragraph gap. Geometry then gives no evidence to terminate the row block.
    for index in lines.indices where lines[index].rect.minY < 431 { lines[index].rect.origin.y += 2.2 }
    let first = try #require(lines.first { $0.text.hasPrefix("Most information") })
    #expect(TableRegionDetector.rowBlocks(in: lines, body: 8.5).contains { $0.contains(first.rect) })
}
