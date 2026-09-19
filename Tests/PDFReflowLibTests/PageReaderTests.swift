import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// What `PageReader` can say about a page before any judgment of its text. An original PDF makes
// each condition independently, without a corpus download.

/// Page 1 paints only a white ground, page 2 sets a line of prose, page 3 fills one black
/// rectangle: a page that draws nothing, a page that draws text and a page that draws only
/// graphics.
private let emptyAndDrawnPages = testPDF(objects: [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 9 0 R >> >> /Contents 7 0 R >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 8 0 R >>",
    testPDFStream("1 1 1 rg 0 0 612 792 re f"),
    testPDFStream("BT /F1 12 Tf 1 0 0 1 72 720 Tm (An ordinary line of prose holds this page.) Tj ET"),
    testPDFStream("0 0 0 rg 120 300 300 220 re f"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
])

private func emptyPageWorkspace() throws -> (input: URL, directory: URL) {
    let directory = try testPDFDirectory()
    let input = directory.appendingPathComponent("empty.pdf")
    try emptyAndDrawnPages.write(to: input)
    return (input, directory)
}

@Test func aPageThatDrawsNothingIsReportedAsEmpty() async throws {
    let (input, directory) = try emptyPageWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Recognition of a blank raster reads nothing; the canned reader says so without Vision.
    let result = try await PDFReflowLibPipeline.reconstruct(from: input, options: .init(),
        workspace: directory.appendingPathComponent("work"),
        recognize: { _, _ in OCRReader.Result(lines: [], tables: []) }) { _ in }
    let empty = result.warnings.filter { $0.code == .emptyPage }
    #expect(empty.map(\.page) == [1])
    #expect(try #require(empty.first).message == "This page draws no text and no graphics; nothing is extracted from it.")
    // The blank page is still carried as an image; `emptyPage` says why that image is blank.
    #expect(result.warnings.contains { $0.code == .pageImageFallback && $0.page == 1 })
}

@Test func emptinessIsJudgedBeforeRecognitionAndUnderEveryPolicy() async throws {
    let (input, directory) = try emptyPageWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    for (index, policy) in [ConversionOptions.OCRPolicy.never, .automatic].enumerated() {
        var options = ConversionOptions(); options.ocr = policy
        let result = try await PDFReflowLibPipeline.reconstruct(from: input, options: options,
            workspace: directory.appendingPathComponent("work-\(index)"),
            // A recognizer that invents text cannot make the blank page non-empty: the page
            // never drew that text, so the judgment stands on what was extracted.
            recognize: { _, _ in OCRReader.Result(lines: [TextLine(text: "Invented reading",
                rect: CGRect(x: 40, y: 40, width: 200, height: 12), fontSize: 12)], tables: []) }) { _ in }
        #expect(result.warnings.filter { $0.code == .emptyPage }.map(\.page) == [1])
    }
}
