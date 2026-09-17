import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// A list marker PDFKit splits from its item's text rejoins it (#69). Where the source tags the
// marker and the text as one paragraph group (the FAA handbook tags each bullet item, marker and
// text, as one `P`), the rejoined line must not invalidate that group: it stays complete, keeps
// its tag order and reads as the list item it is (#81).

/// One page, three `P` groups in tree order `first`, `second`, `third`. Groups 1 and 2 are bullet
/// items whose marker and text are separate shows (MCIDs 0–2 and 3–4); group 3 is closing prose.
/// `firstGroup` and `secondGroup` replace the kids of the two item groups.
private func objects(treeOrder: String = "[8 0 R 9 0 R 10 0 R]", firstGroup: String = "[0 1 2]",
                     secondGroup: String = "[3 4]", parents: String = "[8 0 R 8 0 R 8 0 R 9 0 R 9 0 R 10 0 R]") -> [String] {
    [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /MarkInfo << /Marked true >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream("""
        /P << /MCID 0 >> BDC BT /F1 10 Tf 1 0 0 1 45 700 Tm (x) Tj ET EMC
        /P << /MCID 1 >> BDC BT /F1 10 Tf 1 0 0 1 63 700 Tm (Alpha) Tj ET EMC
        /P << /MCID 2 >> BDC BT /F1 10 Tf 1 0 0 1 63 688 Tm (wraps) Tj ET EMC
        /P << /MCID 3 >> BDC BT /F1 10 Tf 1 0 0 1 45 668 Tm (x) Tj ET EMC
        /P << /MCID 4 >> BDC BT /F1 10 Tf 1 0 0 1 63 668 Tm (Beta) Tj ET EMC
        /P << /MCID 5 >> BDC BT /F1 10 Tf 1 0 0 1 36 643 Tm (Closing) Tj ET EMC
        """),
        "<< /Type /StructTreeRoot /K \(treeOrder) /ParentTree 7 0 R >>",
        "<< /Nums [0 \(parents)] >>",
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K \(firstGroup) >>",
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K \(secondGroup) >>",
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K [5] >>",
    ]
}

/// Independent geometry for the six explicit origins above: the marker pieces and their text
/// share a baseline 18 points apart, as FAA page 29's `•` (x 45) and item text (x 63) do.
private func lines(firstText: String = "Alpha item text that", marker: String = "•") -> [TextLine] {
    [TextLine(text: marker, rect: CGRect(x: 45, y: 697, width: 4, height: 12), fontSize: 10),
     TextLine(text: firstText, rect: CGRect(x: 63, y: 697, width: 150, height: 12), fontSize: 10),
     TextLine(text: "wraps onto a second line", rect: CGRect(x: 63, y: 685, width: 150, height: 12), fontSize: 10),
     TextLine(text: "•", rect: CGRect(x: 45, y: 665, width: 4, height: 12), fontSize: 10),
     TextLine(text: "Beta item", rect: CGRect(x: 63, y: 665, width: 60, height: 12), fontSize: 10),
     TextLine(text: "Closing prose paragraph.", rect: CGRect(x: 36, y: 640, width: 200, height: 12), fontSize: 10)]
}

private func reconstruct(_ objects: [String], lines input: [TextLine] = lines())
    throws -> (blocks: [ReflowBlock], warnings: [ConversionWarning]) {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("tagged-markers.pdf")
    try testPDF(objects: objects).write(to: url)
    let document = try #require(CGPDFDocument(url as CFURL))
    let page = try #require(document.page(at: 1))
    let tree = try StructureTreeReader.read(url)
    let tags = try #require(tree.pages[1])
    var lines = input
    #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
    #expect(MarkedTextReader.apply(tags, page: page, lines: &lines))
    // Every line, marker pieces included, carries its group before reconstruction.
    #expect(lines.allSatisfy { $0.structure != nil })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: .init(number: 1, bounds: page.getBoxRect(.cropBox), lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    return (blocks, warnings)
}

private func items(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { return text.text } else { return nil } }
}

private func fallbacks(_ warnings: [ConversionWarning]) -> [ConversionWarning] {
    warnings.filter { $0.code == .structureFallback }
}

@Test func aTaggedItemWithASplitMarkerKeepsItsGroupAsOneListItem() throws {
    let (blocks, warnings) = try reconstruct(objects())
    #expect(fallbacks(warnings).isEmpty)
    #expect(blocks.map(\.text) == ["• Alpha item text that wraps onto a second line", "• Beta item", "Closing prose paragraph."])
    #expect(items(blocks) == ["• Alpha item text that wraps onto a second line", "• Beta item"])
    // The blocks come from the validated groups, not from the spatial fallback.
    #expect(blocks.allSatisfy { $0.structureGroup != nil && $0.taggedLevel == 0 })
    #expect(Set(blocks.compactMap(\.structureGroup)).count == 3)
}

@Test func tagOrderStillOrdersRejoinedItems() throws {
    // Tree order second, first, third: only tags can put `Beta` before `Alpha`.
    let (blocks, warnings) = try reconstruct(objects(treeOrder: "[9 0 R 8 0 R 10 0 R]"))
    #expect(fallbacks(warnings).isEmpty)
    #expect(blocks.map(\.text) == ["• Beta item", "• Alpha item text that wraps onto a second line", "Closing prose paragraph."])
}

@Test func theRejoinedLineSortsAtTheEarlierPieceOrder() throws {
    // The marker is referenced first and the item's first text line last (MCIDs 0, 2, 1): the
    // joined line takes the marker's order, still opens the group, and the group stays one item.
    let (blocks, warnings) = try reconstruct(objects(firstGroup: "[0 2 1]"))
    #expect(fallbacks(warnings).isEmpty)
    #expect(items(blocks).first == "• Alpha item text that wraps onto a second line")
}

// MARK: - Negative controls: groups the exception must not accept

@Test func aGroupHoldingTwoRejoinedItemsStillFallsBack() throws {
    // Both items in one `P`: a paragraph would collapse the break between them.
    // Object 9 stays in the file but no longer belongs to the tree.
    let tree = objects(treeOrder: "[8 0 R 10 0 R]", firstGroup: "[0 1 2 3 4]", secondGroup: "[]",
                       parents: "[8 0 R 8 0 R 8 0 R 8 0 R 8 0 R 10 0 R]")
    let (blocks, warnings) = try reconstruct(tree)
    #expect(fallbacks(warnings).map(\.message).contains { $0.hasPrefix("Caption, list") })
    #expect(items(blocks) == ["• Alpha item text that wraps onto a second line", "• Beta item"])
    #expect(!blocks.contains { $0.structureGroup != nil && $0.text.contains("Alpha") })
}

@Test func aRejoinedItemThatDoesNotOpenItsGroupStillFallsBack() throws {
    // The group opens with the wrapped line (MCID 2 first, and spatially the marker is first):
    // tag order puts text ahead of the item's marker, so it is not one item.
    let (_, warnings) = try reconstruct(objects(firstGroup: "[2 0 1]"))
    #expect(fallbacks(warnings).map(\.message).contains { $0.hasPrefix("Caption, list") })
}

@Test func anUnsplitBulletInsideAParagraphGroupStillFallsBack() throws {
    // PDFKit kept the marker and text together (one line, no join): the #43 rule is unchanged.
    var input = lines(firstText: "Alpha item text that")
    input[0] = TextLine(text: "• Alpha item text that", rect: CGRect(x: 45, y: 697, width: 168, height: 12), fontSize: 10)
    input.remove(at: 1)
    // MCID 1's origin (63, 700) now falls inside the unsplit line as well, so both shows map to it.
    let (blocks, warnings) = try reconstruct(objects(), lines: input)
    #expect(fallbacks(warnings).map(\.message).contains { $0.hasPrefix("Caption, list") })
    #expect(!blocks.contains { $0.structureGroup != nil && $0.text.contains("Alpha") })
}
