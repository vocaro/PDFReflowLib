import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func magazineCouponOutlineBoxesAreReadableMarks() throws {
    let fixture = try SourceLayoutFixture.load("usda-magazine-24")
    #expect(fixture.sourceSHA256 == "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761")
    let content = fixture.content()
    let found = DrawnCheckboxReader.read(lines: content.lines, paints: fixture.paints, regions: content.graphics)
    #expect(found.count == 1)
    let reading = try #require(found.first)
    #expect(reading.boxes.count == 2)
    #expect(reading.boxes.allSatisfy { $0.minX > 218 && $0.maxX < 234 })
    #expect(reading.regions.count == 1)
    #expect(reading.regions.allSatisfy(content.graphics.contains))
    // A framed NOAA figure has rectangular art and nearby prose, but no paired form marks.
    let noaa = try SourceLayoutFixture.load("noaa-701")
    #expect(DrawnCheckboxReader.read(lines: noaa.content().lines, paints: noaa.paints,
                                    regions: noaa.content().graphics).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func ruledLabelCheckboxesReachTheEPUBAsText() async throws {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            + "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("BT /F1 10 Tf 1 0 0 1 80 620 Tm (To stop mailing) Tj "
            + "1 0 0 1 80 600 Tm (To change address) Tj ET "
            + "0 0 0 RG 1 w 149 617 m 214 617 l S 220 616 12 8 re S "
            + "166 597 m 214 597 l S 220 596 12 8 re S"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("drawn-checkboxes.pdf")
    let output = directory.appendingPathComponent("drawn-checkboxes.epub")
    try data.write(to: source)
    let extracted = try PageReader.read(pageIndex: 0, from: PDFPageSource(url: source), limit: 1_000,
                                        options: ConversionOptions(), structure: nil)
    #expect(extracted.content.lines.count { $0.text == "☐" } == 2)
    #expect(extracted.content.graphics.isEmpty)
    _ = try await PDFConverter().convert(from: source, to: output)
    let chapter = String(decoding: try Archive(url: output, accessMode: .read)
        .entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(chapter.components(separatedBy: "☐").count - 1 == 2)
    #expect(chapter.contains("To stop mailing") && chapter.contains("To change address"))
}
