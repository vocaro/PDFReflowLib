import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func textLayerPDF(_ text: String, imageSize: Int = 300, invisible: Bool = true) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /XObject << /Im 5 0 R >> /Font << /F1 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("q \(imageSize) 0 0 \(imageSize) 0 0 cm /Im Do Q BT /F1 12 Tf \(invisible ? 3 : 0) Tr 20 240 Td (\(text)) Tj ET"),
        testPDFStream("FFFFFF>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding /ToUnicode 7 0 R >>",
        testPDFStream("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        /CMapName /AttachmentTest def /CMapType 2 def
        1 begincodespacerange <00> <FF> endcodespacerange
        1 beginbfchar <7E> <FFFC> endbfchar
        endcmap CMapName currentdict /CMap defineresource pop end end
        """),
    ])
}

@Test func attachmentPlaceholdersAreNotSemanticTextAndStylesSurvive() throws {
    for (raw, expected) in [("~~", ""), ("Before~after", "Before after"), ("~Before after~", "Before after")] {
        let document = try #require(PDFDocument(data: textLayerPDF(raw)))
        let page = try #require(document.page(at: 0))
        #expect(page.string?.contains("\u{FFFC}") == true) // Prove the extraction defect is exercised.
        for styled in [true, false] {
            let lines = try NativeTextReader.lines(on: page, limit: 1000, includeStyle: styled)
            #expect(lines.map(\.text).joined() == expected)
            if !expected.isEmpty && styled {
                #expect(lines.flatMap { $0.content.elements }.contains {
                    if case let .text(value, style) = $0 { return value.contains("Before") && style.contains(.bold) }
                    return false
                })
            }
        }
    }
}

@Test func textlessAttachmentScansUseOCRPolicyWithoutClaimingReflow() async throws {
    for policy in [ConversionOptions.OCRPolicy.automatic, .never] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("source.pdf")
        try textLayerPDF("~~").write(to: pdf)
        var options = ConversionOptions(); options.ocr = policy
        let result = try await PDFReflowLibPipeline.reconstruct(from: pdf, options: options,
            workspace: dir.appendingPathComponent("work"), progress: { _ in })
        #expect(result.reflowedPageCount == 0)
        #expect(result.document.blocks.allSatisfy { $0.text.isEmpty })
        #expect(result.document.assets.count == 1)
        #expect(result.warnings.contains { $0.code == .pageImageFallback && $0.page == 1 })
        #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
        if policy == .automatic {
            #expect(result.recognizedPageCount == 1)
            #expect(result.warnings.contains { $0.code == .ocrUsed })
        } else {
            #expect(result.recognizedPageCount == 0)
        }
    }
}

@Test func inheritedTextGetsReviewWarningAndSourceImageWithoutDiscardingProse() async throws {
    for imageSize in [60, 300] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
        try textLayerPDF("Existing~transcription.", imageSize: imageSize).write(to: pdf)
        let report = try await PDFConverter().convert(from: pdf, to: epub)
        #expect(report.reflowedPageCount == 1)
        #expect(report.recognizedPageCount == 0)
        #expect(report.imageCount == 1)
        let warnings = report.warnings.filter { $0.code == .unverifiedTextLayer }
        #expect(warnings.count == (imageSize == 300 ? 1 : 0))
        if let warning = warnings.first {
            #expect(warning.page == 1)
            #expect(warning.message.contains("Check the accompanying source-page image"))
            let decoded = try JSONDecoder().decode(ConversionWarning.self, from: JSONEncoder().encode(warning))
            #expect(decoded == warning)
        }
        let archive = try Archive(url: epub, accessMode: .read)
        let entry = try #require(archive["EPUB/chapter-1.xhtml"])
        var bytes = Data(); _ = try archive.extract(entry) { bytes += $0 }
        let html = String(decoding: bytes, as: UTF8.self)
        #expect(html.contains("Existing transcription."))
        #expect(!html.contains("\u{FFFC}"))
        #expect(html.contains("<img "))
    }
}
