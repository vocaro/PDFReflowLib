import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

/// The value printed under a widget is the only evidence that its appearance duplicates text.
/// A differently worded caption cannot stand in for a prefilled field (#151, #170).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/170"))
func prefilledFieldNeedsItsPageImageUnlessTheSameValueIsPrintedBeneathIt() throws {
    let field = "<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /F 4 "
        + "/V (Jane Q. Public) /Rect [72 400 270 418] >>"
    func page(_ printed: String) -> Data {
        testPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                + "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R /Annots [6 0 R] >>",
            testPDFStream("BT /F1 12 Tf 1 0 0 1 76 404 Tm (\(printed)) Tj ET"),
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            field,
        ])
    }
    for (printed, expectedVisible) in [("Jane Q. Public", 0), ("Name for Jane Q. Public", 1)] {
        let sourceData = page(printed)
        let document = try #require(PDFDocument(data: sourceData))
        let pdfPage = try #require(document.page(at: 0))
        let judged = try AnnotationEvidence.judge(pdfPage.annotations, on: pdfPage,
                                                   bounds: pdfPage.bounds(for: .cropBox))
        #expect(judged.visible == expectedVisible)
        #expect(judged.formFields == 1 - expectedVisible)
        let directory = try testPDFDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("field.pdf")
        try sourceData.write(to: url)
        let extracted = try PageReader.read(pageIndex: 0, from: PDFPageSource(url: url), limit: 1_000,
                                            options: ConversionOptions(), structure: nil)
        #expect(extracted.content.preservePageReference == (expectedVisible == 1))
        #expect(extracted.warnings.contains { if case .annotationsNotConverted = $0 { true } else { false } })
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/170"))
func checkboxWithNoPrintedGlyphSuppliesAReadableBox() async throws {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            + "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R /Annots [6 0 R] >>",
        testPDFStream("BT /F1 12 Tf 1 0 0 1 110 600 Tm (Jury Trial) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Annot /Subtype /Widget /FT /Btn /T (jury) /F 4 "
            + "/Rect [72 596 88 612] /V /Off /AS /Off >>",
    ])
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: 0))
    let judgment = try AnnotationEvidence.judge(page.annotations, on: page,
                                                bounds: page.bounds(for: .cropBox))
    #expect(judgment.boxes.count == 1)
    var lines = [TextLine(text: "Jury Trial", rect: CGRect(x: 110, y: 598, width: 75, height: 12), fontSize: 12)]
    AnnotationEvidence.markBoxes(judgment.boxes, in: &lines)
    #expect(lines.map(\.text).contains("☐"))

    // The mark must survive extraction, reconstruction and EPUB packaging beside its label.
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("checkbox.pdf")
    let output = directory.appendingPathComponent("checkbox.epub")
    try data.write(to: source)
    let report = try await PDFConverter().convert(from: source, to: output)
    let chapter = String(decoding: try Archive(url: output, accessMode: .read)
        .entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(chapter.contains("☐"))
    #expect(chapter.contains("Jury Trial"))
    #expect(report.warnings.contains { $0.code == .annotationsNotConverted })
}
