import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

/// #132: a page that paints nothing contributes only its page boundary. Faint real content, a
/// scan of an empty sheet, annotations and text keep what they had.
private struct BlankPageFixture {
    /// Each page: content stream, extra page dictionary entries.
    var pages: [(content: String, extra: String)]

    var data: Data {
        // 1 catalog, 2 pages, 3 font, 4 near-white scan, 5 pure white scan, then page + contents pairs.
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [\(pages.indices.map { "\(6 + 2 * $0) 0 R" }.joined(separator: " "))] /Count \(pages.count) >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            testPDFStream("FBFCFAFB>", extra: "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
            testPDFStream("FFFFFFFF>", extra: "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        ]
        for (index, page) in pages.enumerated() {
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> "
                + "/XObject << /Faint 4 0 R /White 5 0 R >> >> /Contents \(7 + 2 * index) 0 R \(page.extra) >>")
            objects.append(testPDFStream(page.content))
        }
        return testPDF(objects: objects)
    }
}

private func prose(_ text: String) -> String { "BT /F1 12 Tf 72 700 Td (\(text)) Tj ET" }

private func reconstruct(_ fixture: BlankPageFixture, ocr: ConversionOptions.OCRPolicy = .never,
                         references: ConversionOptions.ReferenceImagePolicy = .automatic)
    async throws -> PDFReflowLibPipeline.Result {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("blank.pdf")
    try fixture.data.write(to: source)
    var options = ConversionOptions(); options.ocr = ocr; options.referenceImages = references
    return try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
}

private func images(on page: Int, _ result: PDFReflowLibPipeline.Result) -> Int {
    result.document.blocks.filter { if case .image = $0.content { $0.page == page } else { false } }.count
}

@Test func blankPagesKeepOnlyTheirBoundaryUnderEveryOCRPolicy() async throws {
    let fixture = BlankPageFixture(pages: [
        (prose("Text before the blank pages."), ""),
        ("", ""),                                          // an empty content stream (9/11 page 162)
        ("1 g 0 0 612 792 re f", ""),                      // white paint on white paper
        ("", "/Rotate 90"),                                // a rotated empty page
        (prose("Text after the blank pages."), ""),
    ])
    for policy in [ConversionOptions.OCRPolicy.never, .automatic, .always] {
        let result = try await reconstruct(fixture, ocr: policy)
        let sourcePages = result.document.blocks.compactMap { if case let .sourcePage(page) = $0.content { page } else { nil } }
        #expect(sourcePages == [1, 2, 3, 4, 5], "\(policy)")
        for page in 2...4 {
            #expect(images(on: page, result) == 0, "\(policy) page \(page)")
            #expect(!result.warnings.contains { $0.page == page }, "\(policy) page \(page)")
        }
        #expect(result.document.assets.isEmpty == (policy != .always), "\(policy)")
        #expect(result.recognizedPageCount == (policy == .always ? 2 : 0), "\(policy)")
        try result.document.validate()
    }
}

@Test func faintContentScansAnnotationsAndTextAreNeverBlank() async throws {
    let fixture = BlankPageFixture(pages: [
        ("0.97 g 100 100 200 200 re f", ""),               // a light tint, 247 of 255
        ("0 G 0.25 w 100 400 m 500 400 l S", ""),          // a quarter-point hairline
        ("q 612 0 0 792 0 0 cm /Faint Do Q", ""),          // a scan with almost no ink
        ("q 612 0 0 792 0 0 cm /White Do Q", ""),          // a scan of an empty sheet is still an image
        ("", "/Annots [<< /Type /Annot /Subtype /Square /Rect [100 100 300 300] /C [1 0 0] /Border [0 0 2] >>]"),
        ("0.99 g BT /F1 12 Tf 72 700 Td (Faint gray words.) Tj ET", ""),
    ])
    let result = try await reconstruct(fixture)
    for page in 1...5 {
        #expect(images(on: page, result) == 1, "page \(page)")
        #expect(result.warnings.contains { $0.page == page && ($0.code == .pageImageFallback || $0.code == .imageRegion) },
                "page \(page)")
    }
    #expect(result.document.blocks.map(\.text).joined().contains("Faint gray words."))
}

@Test func blankPageEvidenceNeedsBothTheDrawingAndTheRender() throws {
    func page(_ content: String) throws -> CGPDFPage {
        let document = try #require(PDFDocument(data: BlankPageFixture(pages: [(content, "")]).data))
        return try #require(document.page(at: 0)?.pageRef)
    }
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    // The render threshold: one level of rounding below white passes, three levels do not.
    #expect(BlankPageDetector.minimumChannel == 254)
    #expect(BlankPageDetector.rendersWhite(try page(""), bounds: bounds))
    #expect(BlankPageDetector.rendersWhite(try page("1 g 0 0 612 792 re f"), bounds: bounds))
    #expect(BlankPageDetector.rendersWhite(try page("0.9985 g 0 0 612 792 re f"), bounds: bounds))
    #expect(!BlankPageDetector.rendersWhite(try page("0.99 g 0 0 612 792 re f"), bounds: bounds))
    #expect(!BlankPageDetector.rendersWhite(try page("0 G 0.1 w 10 10 m 11 10 l S"), bounds: bounds))
    #expect(!BlankPageDetector.rendersWhite(try page("q 612 0 0 792 0 0 cm /Faint Do Q"), bounds: bounds))
    #expect(!BlankPageDetector.rendersWhite(try page("1 0.98 0.98 rg 0 0 612 792 re f"), bounds: bounds))
    // The drawing evidence: a white paint is no footprint, a tint and a white scan are.
    for (content, drawsNothing) in [("", true), ("1 g 0 0 612 792 re f", true), ("0.97 g 0 0 10 10 re f", false),
                                    ("q 612 0 0 792 0 0 cm /White Do Q", false), (prose("Words."), false)] {
        let graphics = GraphicsReader.read(try page(content))
        #expect(BlankPageDetector.drawsNothing(lines: [], graphics: graphics, annotations: 0) == drawsNothing, "\(content)")
    }
    #expect(!BlankPageDetector.drawsNothing(lines: [], graphics: GraphicsReader.read(try page("")), annotations: 1))
}

@Test func blankPageConvertsToAValidEPUBWithItsPageMarker() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let input = dir.appendingPathComponent("blank.pdf"), output = dir.appendingPathComponent("blank.epub")
    try BlankPageFixture(pages: [(prose("Only page with words."), ""), ("", "")]).data.write(to: input)
    let report = try await PDFConverter().convert(from: input, to: output, options: .init())
    #expect(report.imageCount == 0)
    #expect(report.warnings.isEmpty)
    let archive = try Archive(url: output, accessMode: .read)
    let entry = try #require(archive["EPUB/chapter-1.xhtml"])
    var bytes = Data(); _ = try archive.extract(entry) { bytes += $0 }
    let chapter = String(decoding: bytes, as: UTF8.self)
    #expect(chapter.contains("id=\"page-2\""))
    #expect(!chapter.contains("<img"))
}
