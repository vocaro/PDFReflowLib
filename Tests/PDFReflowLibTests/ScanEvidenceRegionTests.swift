import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Inline images (#37). `CGPDFScanner` reports `BI … ID … EI` as one `EI` with the image stream.

private func inlinePage(_ content: String, extra: String = "") throws -> GraphicsReader.Result {
    let document = try #require(PDFDocument(data: testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /XObject << /Fm 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        testPDFStream("40 0 0 20 0 0 cm BI /W 1 /H 1 /IM true /BPC 1 ID \u{0}\nEI", extra: "/Type /XObject /Subtype /Form /BBox [0 0 100 100]"),
    ])))
    return GraphicsReader.read(try #require(document.page(at: 0)?.pageRef))
}

@Test func anInlineImageIsThePaintedUnitSquareUnderItsTransform() throws {
    let mask = try inlinePage("q 30 0 0 60 100 200 cm BI /W 1 /H 1 /IM true /BPC 1 ID \u{0}\nEI Q")
    #expect(!mask.unsupported)
    #expect(mask.inlineImages == [CGRect(x: 100, y: 200, width: 30, height: 60)])
    #expect(mask.regions == [CGRect(x: 100, y: 200, width: 30, height: 60)])
    #expect(mask.covers.isEmpty)
    // Unfiltered samples containing the bytes `EI` are delimited by their computed length.
    let raw = try inlinePage("q 20 0 0 10 50 50 cm BI /W 2 /H 1 /CS /G /BPC 8 ID EI\nEI Q")
    #expect(!raw.unsupported && raw.inlineImages == [CGRect(x: 50, y: 50, width: 20, height: 10)])
    #expect(raw.covers.map(\.rect) == [CGRect(x: 50, y: 50, width: 20, height: 10)])
    let hex = try inlinePage("q 10 0 0 10 5 5 cm BI /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode ID 00112233445566778899AABB> EI Q")
    #expect(!hex.unsupported && hex.inlineImages.count == 1)
    let indexed = try inlinePage("q 10 0 0 10 5 5 cm BI /W 4 /H 1 /CS [/I /RGB 1 <000000FFFFFF>] /BPC 1 ID \u{50}\nEI Q")
    #expect(!indexed.unsupported && indexed.inlineImages.count == 1)
    // Inside a form, the form's own transform applies.
    let form = try inlinePage("q 1 0 0 1 60 70 cm /Fm Do Q")
    #expect(!form.unsupported && form.inlineImages == [CGRect(x: 60, y: 70, width: 40, height: 20)])
}

@Test(arguments: [
    "q 10 0 0 10 5 5 cm BI /H 1 /IM true ID \u{0}\nEI Q",                     // no width
    "q 10 0 0 10 5 5 cm BI /W 0 /H 1 /IM true ID \u{0}\nEI Q",                // empty
    "q 10 0 0 10 5 5 cm BI /W 4 /H 4 /CS /G /BPC 8 ID \u{1}\u{2}\nEI Q",      // truncated samples
    "q 10 0 0 10 5 5 cm BI /W 90000 /H 90000 /CS /RGB /BPC 8 ID \u{1}\nEI Q", // huge, tiny data
    "q 10 0 0 10 5 5 cm BI /W 1 /H 1 /BPC 8 ID \u{1}\nEI Q",                  // no colour space
    "q 10 0 0 10 5 5 cm BI /W 1 /H 1 /CS /CS0 /BPC 8 ID \u{1}\nEI Q",         // resource colour space
    "q 10 0 0 10 5 5 cm BI /W 1 /H 1 /CS /G /BPC 3 ID \u{1}\nEI Q",           // invalid depth
    "q 10 0 0 10 5 5 cm BI /W 1 /H 1 /IM true /BPC 8 ID \u{1}\nEI Q",         // mask depth
    "q 10 0 0 10 5 5 cm EI Q",                                                // no image
])
func aMalformedInlineImageKeepsThePageImage(content: String) throws {
    #expect(try inlinePage(content).unsupported)
}

// MARK: - Scanned page with Paper Capture evidence

private let proseText = "The detailed solution of the classical equations of motion during a collision is quite complicated"

/// A 600×800 scan: a 1-bit page image whose ink draws prose rows, a framed figure with a curve,
/// a side label and an axis label beneath the frame, a caption row and a display equation with
/// its number, all transcribed by an invisible OCR layer except what the evidence boxes cover.
/// `evidence` lists inline-image boxes drawn inside an empty even-odd clip, as Paper Capture does.
private func scannedPage(evidence: [CGRect], extraInline: String = "") -> Data {
    let width = 300, height = 400 // two points per sample
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: 0.5, y: 0.5)
    context.setFillColor(gray: 0, alpha: 1)
    context.setStrokeColor(gray: 0, alpha: 1)
    let proseRows: [CGFloat] = [720, 706, 692, 678, 664, 280, 266, 252, 120, 106, 92]
    // Ink sits inside each OCR line's rectangle, as glyphs do.
    for y in proseRows { context.fill(CGRect(x: 60, y: y - 1, width: 480, height: 8)) }
    context.setLineWidth(4)
    context.stroke(CGRect(x: 160, y: 420, width: 280, height: 190))      // figure frame
    context.move(to: CGPoint(x: 170, y: 430))
    context.addCurve(to: CGPoint(x: 430, y: 600), control1: CGPoint(x: 260, y: 600), control2: CGPoint(x: 340, y: 430))
    context.strokePath()
    context.fill(CGRect(x: 144, y: 510, width: 10, height: 10))          // side label `v`, 6 points left of the frame
    context.fill(CGRect(x: 294, y: 386, width: 12, height: 10))          // axis label `x`, 20 points below the frame
    context.fill(CGRect(x: 180, y: 339, width: 110, height: 6))          // caption
    context.fill(CGRect(x: 200, y: 186, width: 160, height: 12))         // display equation
    context.fill(CGRect(x: 508, y: 188, width: 20, height: 8))           // its number
    let image = context.makeImage()!
    // Pack to one bit per sample, 1 = white.
    let pixels = CFDataGetBytePtr(image.dataProvider!.data)!
    var hex = ""
    for row in 0..<height {
        var byte = 0, bits = 0
        for column in 0..<width {
            byte = byte << 1 | (pixels[row * image.bytesPerRow + column] > 127 ? 1 : 0)
            bits += 1
            if bits == 8 { hex += String(format: "%02X", byte); byte = 0; bits = 0 }
        }
        if bits > 0 { hex += String(format: "%02X", byte << (8 - bits)) }
    }
    func line(_ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 10, scale: CGFloat = 100) -> String {
        "BT /F1 \(size) Tf 3 Tr \(scale) Tz 1 0 0 1 \(x) \(y) Tm (\(text)) Tj ET\n"
    }
    var text = ""
    // Justified to the prose ink's 480-point measure.
    for y in proseRows { text += line(proseText, 60, y, scale: 124.86) }
    text += line("v", 145, 510) + line("x", 295, 386)
    text += line("FIGURE 1. A synthetic trajectory.", 180, 340, size: 8)
    text += line("(1)", 508, 188)
    let boxes = evidence.map { box in
        "q \(box.width) 0 0 \(box.height) \(box.minX) \(box.minY) cm BI /W 1 /H 1 /IM true /BPC 1 ID \u{0}\nEI Q\n"
    }.joined()
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> /XObject << /Scan 6 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>",
        testPDFStream("q 600 0 0 800 0 0 cm /Scan Do Q\nq 0 0 600 800 re 0 0 600 800 re W* n\n" + boxes + extraInline + "Q\n" + text),
        testPDFStream(hex + ">", extra: "/Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /ASCIIHexDecode"),
    ])
}

/// Evidence as Paper Capture leaves it: two strips of the figure and the left half of the equation.
private let strips = [CGRect(x: 180, y: 440, width: 40, height: 80), CGRect(x: 330, y: 470, width: 60, height: 100),
                      CGRect(x: 196, y: 182, width: 90, height: 20)]

private func scanReconstruct(_ pdf: Data) async throws -> PDFReflowLibPipeline.Result {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("source.pdf")
    try pdf.write(to: url)
    var options = ConversionOptions(); options.ocr = .never
    return try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
}

private func evidenceRegions(_ pdf: Data) throws -> [CGRect]? {
    let document = try #require(PDFDocument(data: pdf))
    let page = try #require(document.page(at: 0))
    let bounds = page.bounds(for: .cropBox)
    let reference = try #require(page.pageRef)
    let graphics = GraphicsReader.read(reference)
    let lines = try NativeTextReader.lines(on: page, limit: 100_000, includeStyle: false)
    let ink = try #require(ScanEvidenceRegions.inkMap(reference, bounds: bounds))
    return ScanEvidenceRegions.regions(evidence: graphics.inlineImages, lines: lines, bounds: bounds, ink: ink)
}

@Test func paperCaptureEvidenceGrowsToTheWholeFigureAndDisplayRow() throws {
    let grown = try evidenceRegions(scannedPage(evidence: strips))
    let regions = try #require(grown)
    #expect(regions.count == 2)
    let figure = try #require(regions.first { $0.minY > 300 })
    // The frame, the curve, the side label and the axis label down to the caption, nothing more.
    #expect(figure.contains(CGRect(x: 158, y: 418, width: 284, height: 194)))
    #expect(figure.contains(CGRect(x: 144, y: 386, width: 10, height: 134)))
    #expect(figure.minY > 348 && figure.maxY < 664)
    let equation = try #require(regions.first { $0.maxY < 300 })
    #expect(equation.contains(CGRect(x: 200, y: 186, width: 328, height: 12)))
    #expect(equation.minY > 128 && equation.maxY < 252)
}

@Test func aScannedPageWithEvidenceReflowsAroundOneWholeFigure() async throws {
    let result = try await scanReconstruct(scannedPage(evidence: strips))
    #expect(result.reflowedPageCount == 1)
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(!result.warnings.contains { $0.code == .pageImageFallback || $0.code == .unsupportedGraphics })
    // One figure crop, one equation crop and the source-page reference.
    #expect(result.document.assets.count == 3)
    let text = result.document.blocks.map(\.text).joined(separator: "\n")
    #expect(text.contains("FIGURE 1. A synthetic trajectory."))
    #expect(!text.contains("(1)"))
    #expect(!result.document.blocks.contains { ["v", "x"].contains($0.text) })
    #expect(text.components(separatedBy: proseText).count - 1 == 11)
}

@Test func withoutEvidenceTheScannedPageKeepsOnlyItsReference() async throws {
    // Control: the same page with no inline images reflows exactly as before (#72).
    let result = try await scanReconstruct(scannedPage(evidence: []))
    #expect(result.reflowedPageCount == 1)
    #expect(result.document.assets.count == 1)
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer })
}

@Test func aMalformedInlineImageOnTheScanKeepsThePageImage() async throws {
    let truncated = "q 10 0 0 10 50 50 cm BI /W 4 /H 4 /CS /G /BPC 8 ID \u{1}\nEI Q\n"
    let result = try await scanReconstruct(scannedPage(evidence: strips, extraInline: truncated))
    #expect(result.warnings.contains { $0.code == .pageImageFallback })
    #expect(result.reflowedPageCount == 0)
}

@Test func aFigureThatCannotGrowWithoutReachingProseKeepsThePageImage() async throws {
    // Evidence above the caption that overlaps a prose row cannot be a whole figure crop.
    let overlapping = strips + [CGRect(x: 250, y: 600, width: 60, height: 80)]
    #expect(try evidenceRegions(scannedPage(evidence: overlapping)) == nil)
    let result = try await scanReconstruct(scannedPage(evidence: overlapping))
    #expect(result.warnings.contains { $0.code == .pageImageFallback })
}

@Test func anInlineImageOnABornDigitalPageIsAnOrdinaryRegion() async throws {
    // No scan and no OCR layer: the image is visible content, preserved as a crop beside the text.
    var content = ""
    for i in 0..<6 { content += "BT /F1 10 Tf 1 0 0 1 60 \(700 - i * 14) Tm (\(proseText)) Tj ET\n" }
    content += "q 120 0 0 60 100 500 cm BI /W 2 /H 1 /CS /G /BPC 8 ID \u{40}\u{80}\nEI Q\n"
    content += "BT /F1 10 Tf 1 0 0 1 60 460 Tm (\(proseText)) Tj ET\n"
    let result = try await scanReconstruct(testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>",
        testPDFStream(content),
    ]))
    #expect(result.reflowedPageCount == 1)
    #expect(!result.warnings.contains { [.pageImageFallback, .unsupportedGraphics, .unverifiedTextLayer].contains($0.code) })
    #expect(result.document.assets.count == 1)
}
