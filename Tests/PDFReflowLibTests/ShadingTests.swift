import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import PDFReflowLib

// Original minimal PDFs make clipping, resource lookup and transforms independently testable.
// No downloaded corpus or PDF authoring dependency is needed for these regressions.
private let axial = "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 0] /Extend [true true] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >>"
private func shadingPDF(_ content: String, shading: String = axial,
                        form: String = "/S sh", formBox: String = "[0 0 100 40]",
                        formMatrix: String = "[1 0 0 1 0 0]") -> Data {
    func stream(_ s: String, extra: String = "") -> String {
        "<< /Length \(s.utf8.count) \(extra) >>\nstream\n\(s)\nendstream"
    }
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Shading << /S 5 0 R >> /XObject << /Fm 6 0 R >> /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
        stream(content), shading,
        stream(form, extra: "/Type /XObject /Subtype /Form /BBox \(formBox) /Matrix \(formMatrix) /Resources << /Shading << /S 5 0 R >> >>"),
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

private func inspectShading(_ data: Data) throws -> GraphicsReader.Result {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    return GraphicsReader.read(try #require(document.page(at: 1)))
}

@Test func shadingUsesClippingAndRestoresGraphicsState() throws {
    let result = try inspectShading(shadingPDF("q 50 400 200 40 re W n /S sh Q q 300 200 100 30 re W* n /S sh Q"))
    #expect(!result.unsupported)
    #expect(result.regions.count == 2)
    #expect(result.regions.contains(CGRect(x: 48, y: 398, width: 204, height: 44)))
    #expect(result.regions.contains(CGRect(x: 298, y: 198, width: 104, height: 34)))
}

@Test func shadingRespectsTransformedFormBBoxAndRestoresParentClip() throws {
    let result = try inspectShading(shadingPDF(
        "q 2 0 0 2 50 300 cm /Fm Do Q q 400 100 50 30 re W n /S sh Q",
        formBox: "[100 40 0 0]", formMatrix: "[1 0 0 1 10 20]"))
    #expect(!result.unsupported)
    #expect(result.regions.contains { $0.contains(CGRect(x: 70, y: 340, width: 200, height: 80)) })
    #expect(result.regions.contains { $0.contains(CGRect(x: 400, y: 100, width: 50, height: 30)) })
    #expect(result.regions.allSatisfy { $0.width < 210 && $0.height < 90 })
}

@Test func radialShadingBBoxIntersectsClipInTransformedCoordinates() throws {
    let radial = "<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 0 50 50 50] /BBox [90 80 10 20] /Extend [true true] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >>"
    let result = try inspectShading(shadingPDF("q 2 0 0 2 50 100 cm 0 0 50 100 re W n /S sh Q", shading: radial))
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 68, y: 138, width: 84, height: 124)])
}

@Test func shadingClipCommitsAfterWhiteFillAndBoundsCurvedPaths() throws {
    let result = try inspectShading(shadingPDF("q 1 g 50 400 m 50 450 200 450 200 400 c 200 350 l h W f /S sh Q"))
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 48, y: 348, width: 154, height: 104)])
}

@Test func shadingRejectsMissingResourcesAndUnboundedRegions() throws {
    #expect(try inspectShading(shadingPDF("/Missing sh")).unsupported)
    // A gradient under the whole page is its background, not a reason to keep the page as an
    // image: it is recorded like any other paint, and the page-sized-graphic signal takes it
    // from there (#158, the magazine's boxed-title articles).
    let background = try inspectShading(shadingPDF("/S sh"))
    #expect(!background.unsupported)
    #expect(background.regions == [CGRect(x: 0, y: 0, width: 612, height: 792)])
    #expect(try inspectShading(shadingPDF("50 400 100 50 re W n /S sh", shading: "<< /ShadingType 99 >>")).unsupported)
    #expect(try inspectShading(shadingPDF("/S sh", shading: "<< /ShadingType 2 /BBox [0 0 100] >>")).unsupported)
    let empty = try inspectShading(shadingPDF("0 0 0 0 re W n /S sh"))
    #expect(!empty.unsupported && empty.regions.isEmpty)
}

@Test func gradientImageAndOverlaidLabelSurviveWhileAdjacentProseReflows() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shading-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf")
    try shadingPDF("""
    BT /F1 12 Tf 50 650 Td (Prose before the gradient.) Tj ET
    q 50 400 200 50 re W n /S sh Q
    BT /F1 12 Tf 100 420 Td (LABEL) Tj ET
    BT /F1 12 Tf 50 300 Td (Prose after the gradient.) Tj ET
    """).write(to: pdf)
    let result = try await PDFReflowLibPipeline.reconstruct(from: pdf, options: .init(),
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.reflowedPageCount == 1)
    #expect(!result.warnings.contains { $0.code == .unsupportedGraphics || $0.code == .pageImageFallback })
    let text = result.document.blocks.map(\.text).joined(separator: " ")
    #expect(text.contains("Prose before the gradient.") && text.contains("Prose after the gradient."))
    #expect(!text.contains("LABEL")) // The label belongs to the preserved, source-composited image.
    #expect(result.document.assets.count == 1)
    let asset = try #require(result.document.assets.first)
    let source = try #require(CGImageSourceCreateWithURL(asset.fileURL as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
    try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress, width: 100, height: 100,
            bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    let red = stride(from: 0, to: pixels.count, by: 4).filter { Int(pixels[$0]) > Int(pixels[$0 + 2]) + 60 }.count
    let blue = stride(from: 0, to: pixels.count, by: 4).filter { Int(pixels[$0 + 2]) > Int(pixels[$0]) + 60 }.count
    #expect(red > 100 && blue > 100) // A blank or solid-color crop cannot pass.
}
