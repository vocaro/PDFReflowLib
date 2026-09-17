import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Original minimal PDFs: one stroked polyline of `segments` `l` operators beside native prose.
// The reader accepts `m`, each `l` and `S`, so the page costs exactly `segments + 2` operations.
// FAA pages 226, 286, 288 and 302 draw dense vector illustrations of 101,594–183,417 operations
// beside prose that previously fell back to whole-page images.
private func densePDF(segments: Int, prose: Bool = true) -> Data {
    var content = "0 G 1 w 320 400 m\n"
    content.reserveCapacity(segments * 16 + 200)
    for index in 0..<segments {
        content += index % 2 == 0 ? "560 \(400 + index % 200) l\n" : "320 \(400 + index % 200) l\n"
    }
    content += "S\n"
    if prose {
        content += "BT /F1 11 Tf 50 700 Td (Prose beside a dense vector drawing reflows as text.) Tj ET\n"
        content += "BT /F1 11 Tf 50 300 Td (A second paragraph follows below the drawing.) Tj ET\n"
    }
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    var bytes = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (i, object) in objects.enumerated() {
        offsets.append(bytes.count)
        bytes.append(Data("\(i + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = bytes.count
    bytes.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() { bytes.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    bytes.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return bytes
}

private func readGraphics(_ data: Data) throws -> GraphicsReader.Result {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    return GraphicsReader.read(try #require(document.page(at: 1)))
}

@Test func denseDrawingWithinTheOperationBudgetIsAPaintedRegion() throws {
    // Above the former 100,000-operation limit, like FAA page 226's 183,417 operations.
    let result = try readGraphics(densePDF(segments: 183_415))
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 318, y: 398, width: 244, height: 203)])
}

@Test func operationBudgetIsExactAndExcessStillFallsBack() throws {
    #expect(GraphicsReader.operationBudget == 250_000)
    #expect(try !readGraphics(densePDF(segments: GraphicsReader.operationBudget - 2, prose: false)).unsupported)
    #expect(try readGraphics(densePDF(segments: GraphicsReader.operationBudget - 1, prose: false)).unsupported)
}

@Test func denseDrawingKeepsAdjacentProseReflowing() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("budget-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf")
    try densePDF(segments: 150_000).write(to: pdf)
    let result = try await PDFReflowLibPipeline.reconstruct(from: pdf, options: .init(),
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.reflowedPageCount == 1)
    #expect(!result.warnings.contains { $0.code == .unsupportedGraphics || $0.code == .pageImageFallback })
    let text = result.document.blocks.map(\.text).joined(separator: " ")
    #expect(text.contains("Prose beside a dense vector drawing reflows as text."))
    #expect(text.contains("A second paragraph follows below the drawing."))
    #expect(result.document.assets.count == 1) // The drawing is one preserved region, not a page image.
}

@Test func drawingOverTheOperationBudgetStillKeepsThePageImage() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("budget-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf")
    try densePDF(segments: GraphicsReader.operationBudget + 10).write(to: pdf)
    let result = try await PDFReflowLibPipeline.reconstruct(from: pdf, options: .init(),
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.reflowedPageCount == 0)
    #expect(result.warnings.contains { $0.code == .unsupportedGraphics && $0.page == 1 })
    #expect(result.warnings.contains { $0.code == .pageImageFallback && $0.page == 1 })
}
