import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func imageBackedTextPDF(invisible: Bool) -> Data {
    let mode = invisible ? 3 : 0
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> /XObject << /Im 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("""
        q 400 0 0 500 0 0 cm /Im Do Q
        BT /F1 12 Tf \(mode) Tr 40 420 Td (Ordinary prose should reflow across) Tj 0 -14 Td (the source line break without becoming code.) Tj ET
        BT /F1 18 Tf \(mode) Tr 40 380 Td (Noisy size is not a heading.) Tj ET
        """),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
        "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length 7 >>\nstream\nFFFFFF>\nendstream",
    ])
}

@Test func invisibleCourierLayerDoesNotInventCodeOrHeadings() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let input = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book.epub")
    try imageBackedTextPDF(invisible: true).write(to: input)
    var options = ConversionOptions(); options.ocr = .never
    let report = try await PDFConverter().convert(from: input, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    let html = try archive.chapter()
    #expect(!html.contains("<pre>"))
    #expect(!html.contains("<h2"))
    #expect(html.contains("Ordinary prose should reflow across the source line break"))
    #expect(report.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(report.imageCount >= 1 && report.recognizedPageCount == 0)
}

@Test func visibleCourierAndRealHeadingsKeepTheirSemantics() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let input = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book.epub")
    try imageBackedTextPDF(invisible: false).write(to: input)
    var options = ConversionOptions(); options.ocr = .never
    _ = try await PDFConverter().convert(from: input, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    let html = try archive.chapter()
    #expect(html.contains("<pre>"))
    #expect(html.contains("<h2"))
}

@Test(arguments: ["warren-50", "warren-910"])
func warrenSyntheticFontsCannotDeclareCodeOrHeadings(name: String) throws {
    var page = try SourceLayoutFixture.load(name).content()
    // Source stream inspection confirms exclusively mode-3 text over full-page scan images.
    page.hasSyntheticTextStyle = true
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: ["communist", "evidence"], warnings: &warnings)
    #expect(!blocks.contains { if case .heading = $0.content { return true }; return false })
    let preformatted = blocks.compactMap { block -> String? in
        if case let .preformatted(text) = block.content { return text.text }; return nil
    }
    // Source points 10/11 retain the existing list representation, not arbitrary prose lines.
    if name == "warren-50" {
        #expect(preformatted.count == 2)
        #expect(preformatted.allSatisfy { $0.hasPrefix("10.") || $0.hasPrefix("11.") })
    } else { #expect(preformatted.isEmpty) }
    let text = blocks.map(\.text).joined(separator: " ")
    if name == "warren-50" {
        #expect(text.contains("Communist Party"))
        #expect(text.contains("bis known contacts witb")) // Do not invent spelling corrections.
    } else { #expect(text.contains("De Mohrenschildt, Jeanne")) }
}

@Test func invisibleTextClassificationRespectsSavedStateAndForms() throws {
    func inspect(_ body: String, form: String? = nil) throws -> GraphicsReader.Result {
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >> /Contents 4 0 R >>",
            testPDFStream(body), "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
        ]
        if let form {
            objects.append("<< /Type /XObject /Subtype /Form /BBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> >> /Length \(form.utf8.count) >>\nstream\n\(form)\nendstream")
        }
        let document = try #require(PDFDocument(data: testPDF(objects: objects)))
        let page = try #require(document.page(at: 0)?.pageRef)
        return GraphicsReader.read(page)
    }
    let hidden = "BT /F1 12 Tf 3 Tr 40 400 Td (Hidden) Tj ET"
    let visible = "BT /F1 12 Tf 0 Tr 40 380 Td (Visible) Tj ET"
    #expect(try inspect(hidden).hasOnlyInvisibleText)
    #expect(try !inspect(hidden + visible).hasOnlyInvisibleText)
    #expect(try !inspect("q " + hidden + " Q BT /F1 12 Tf (Visible) Tj ET").hasOnlyInvisibleText)
    #expect(try inspect(hidden + " q 0 Tr Q BT (Hidden too) Tj ET").hasOnlyInvisibleText)
    #expect(try inspect("/Fm Do", form: hidden).hasOnlyInvisibleText)
    #expect(try !inspect("/Fm Do " + visible, form: hidden).hasOnlyInvisibleText)
    #expect(try !inspect(hidden + " /Fm Do", form: visible).hasOnlyInvisibleText)
    #expect(try !inspect("BT 9 Tr (Invalid) Tj ET").hasOnlyInvisibleText)
    #expect(try !inspect("BT 7 Tr (Clipping text) Tj ET").hasOnlyInvisibleText)
}
