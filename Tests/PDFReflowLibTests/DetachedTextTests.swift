import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

private func detachedPage(_ stream: String) throws -> (PDFDocument, PDFPage) {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 126 /Widths [\(Array(repeating: "500", count: 95).joined(separator: " "))] >>", testPDFStream(stream)])
    let document = try #require(PDFDocument(data: data))
    return (document, try #require(document.page(at: 0)))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/172"))
func detachedLabelsKeepTheirOwnSidesOfThePage() throws {
    let (document, page) = try detachedPage("BT /F 12 Tf 1 0 0 1 40 450 Tm (Left label) Tj 1 0 0 1 490 450 Tm (Right label) Tj ET")
    defer { withExtendedLifetime(document) {} }
    let lines = try NativeTextReader.lines(on: page, limit: 1000)
    #expect(lines.map(\.text) == ["Left label", "Right label"])
    try #require(lines.count == 2)
    #expect(lines[0].rect.maxX < 110)
    #expect(lines[1].rect.minX >= 489)
    #expect(lines.allSatisfy { line in
        line.content.elements.contains { element in
            if case let .text(_, style) = element { style.contains(.bold) } else { false }
        }
    })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/172"))
func ordinaryCellGapsDoNotBecomeDetachedLabels() throws {
    let (document, page) = try detachedPage("BT /F 12 Tf 1 0 0 1 40 450 Tm (Compass Locator) Tj 1 0 0 1 200 450 Tm (Under 25) Tj ET")
    defer { withExtendedLifetime(document) {} }
    let lines = try NativeTextReader.lines(on: page, limit: 1000)
    let text = lines.map(\.text).joined(separator: " ")
    #expect(text == "Compass Locator Under 25")
    try NativeTextReader.withExtractionLock {
        let shows = NativeSpacingReader.read(try #require(page.pageRef))
        let rect = CGRect(x: 40, y: 440, width: 220, height: 25)
        #expect(DetachedTextReader.pieces(text: text, rect: rect, size: 12, shows: shows,
                                        allBounds: [rect], pageWidth: 612, measure: { _, _, _ in nil }) == nil)
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/172"))
func rightAlignedLabelConjunctionContinuesItsLabel() {
    func read(_ a: String, _ b: String, gap: CGFloat = 2, shift: CGFloat = 0) -> [String] {
        var assembler = BlockAssembler(page: 1, body: 18, hyphens: HyphenContext())
        assembler.append(TextLine(text: a, rect: CGRect(x: 479, y: 460, width: 93, height: 18), fontSize: 18), as: .prose)
        assembler.append(TextLine(text: b, rect: CGRect(x: 507 + shift, y: 442 - gap, width: 65, height: 18), fontSize: 18), as: .prose)
        return assembler.finish().map(\.text)
    }
    #expect(read("Vegetables", "& Fruits") == ["Vegetables & Fruits"])
    #expect(read("Community", "& Recreation") == ["Community & Recreation"])
    #expect(read("Vegetables", "Other label") == ["Vegetables", "Other label"])
    #expect(read("Step 2", "& 3") == ["Step 2", "& 3"])
    #expect(read("Vegetables", "& Fruits", gap: 30) == ["Vegetables", "& Fruits"])
    #expect(read("Vegetables", "& Fruits", shift: 40) == ["Vegetables", "& Fruits"])
}

/// Captured from the checksum-pinned cover after native extraction; these are source lines,
/// not a reconstruction capture. Both labels must survive the page's real graphic geometry.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/172"))
func dietaryCoverLabelsReflowAsWholeLabels() throws {
    let fixture = try SourceLayoutFixture.load("dga-detached-cover")
    #expect(fixture.sourceSHA256 == "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472")
    let page = fixture.content()
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [],
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    for text in ["Protein, Dairy & Healthy Fats", "Vegetables & Fruits", "Whole Grains"] {
        #expect(blocks.contains { $0.hasReflowedText && $0.text == text })
    }
    #expect(!blocks.contains { $0.text.contains("& Healthy Fats & Fruits") })
}
