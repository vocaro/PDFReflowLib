import CoreGraphics
import Foundation
import PDFKit
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif
@testable import PDFReflowLib

private func rasterTestPDF(offset: Bool, rotation: Int) -> Data {
    let x = offset ? 40 : 0, y = offset ? 50 : 0
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /CropBox [\(x) \(y) \(x + 200) \(y + 300)] /Rotate \(rotation) /Contents 4 0 R >>",
        testPDFStream("1 0 0 rg \(x + 20) \(y + 30) 40 60 re f"),
    ])
}

private func coloredBounds(_ image: CGImage, green: Bool = false) throws -> CGRect {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    var xs: [Int] = [], ys: [Int] = []
    for y in 0..<image.height {
        for x in 0..<image.width {
            let i = (y * image.width + x) * 4
            if pixels[i + (green ? 1 : 0)] > 220 && pixels[i + (green ? 0 : 1)] < 40 && pixels[i + 2] < 40 {
                xs.append(x); ys.append(y)
            }
        }
    }
    let x0 = try #require(xs.min()), y0 = try #require(ys.min())
    return CGRect(x: x0, y: y0, width: xs.max()! - x0 + 1, height: ys.max()! - y0 + 1)
}

@Test func wholePageRasterFillsTargetAtEveryRotationAndCropOrigin() throws {
    for offset in [false, true] {
        for rotation in [0, 90, 180, 270] {
            let document = try #require(PDFDocument(data: rasterTestPDF(offset: offset, rotation: rotation)))
            let page = try #require(document.page(at: 0))
            for dpi in [36.0, 180.0] {
                var options = ConversionOptions(); options.rasterDPI = dpi
                let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox),
                    options: options, applyRotation: true)
                let turned = rotation == 90 || rotation == 270
                let scale = dpi / 72
                #expect(image.width == Int((turned ? 300 : 200) * scale))
                #expect(image.height == Int((turned ? 200 : 300) * scale))
                // Expected top-left pixel coordinates of the original 40x60 red rectangle.
                let rect: CGRect
                switch rotation {
                case 90: rect = CGRect(x: 30, y: 20, width: 60, height: 40)
                case 180: rect = CGRect(x: 140, y: 30, width: 40, height: 60)
                case 270: rect = CGRect(x: 210, y: 140, width: 60, height: 40)
                default: rect = CGRect(x: 20, y: 210, width: 40, height: 60)
                }
                #expect(try coloredBounds(image) == rect.applying(CGAffineTransform(scaleX: scale, y: scale)))
            }
        }
    }
}

@Test func rasterKeepsAnnotationsAndHonorsPixelCeiling() throws {
    let document = try #require(PDFDocument(data: rasterTestPDF(offset: true, rotation: 90)))
    let page = try #require(document.page(at: 0))
    let annotation = PDFAnnotation(bounds: CGRect(x: 160, y: 240, width: 30, height: 40), forType: .square, withProperties: nil)
    annotation.color = .green; annotation.interiorColor = .green
    page.addAnnotation(annotation)
    var options = ConversionOptions(); options.maximumRasterPixels = 60_000
    let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox), options: options, applyRotation: true)
    #expect(image.width * image.height <= options.maximumRasterPixels)
    let bounds = try coloredBounds(image, green: true)
    #expect(abs(bounds.midX - 210) <= 1 && abs(bounds.midY - 135) <= 1)
    #expect(bounds.width >= 38 && bounds.height >= 28)
    annotation.shouldDisplay = false
    let hidden = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox), options: options, applyRotation: true)
    #expect(try coloredBounds(hidden) == CGRect(x: 30, y: 20, width: 60, height: 40))
}

@Test func annotationAndSourceCropShareCoordinatesWithoutPageRotation() throws {
    let document = try #require(PDFDocument(data: rasterTestPDF(offset: true, rotation: 90)))
    let page = try #require(document.page(at: 0))
    let annotation = PDFAnnotation(bounds: CGRect(x: 160, y: 240, width: 30, height: 40), forType: .square, withProperties: nil)
    annotation.color = .green; annotation.interiorColor = .green
    page.addAnnotation(annotation)
    var options = ConversionOptions(); options.rasterDPI = 144
    let image = try PageRasterizer.image(page: page, rect: CGRect(x: 150, y: 230, width: 50, height: 60), options: options)
    #expect(image.width == 100 && image.height == 120)
    #expect(try coloredBounds(image, green: true) == CGRect(x: 20, y: 20, width: 60, height: 80))
}

/// Counts pixels close to `color` (0-255 per channel), for annotations whose presence rather than
/// position is the question.
private func pixelCount(_ image: CGImage, near color: (UInt8, UInt8, UInt8)) throws -> Int {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return stride(from: 0, to: pixels.count, by: 4).count { i in
        abs(Int(pixels[i]) - Int(color.0)) < 40 && abs(Int(pixels[i + 1]) - Int(color.1)) < 40
            && abs(Int(pixels[i + 2]) - Int(color.2)) < 40
    }
}

/// Three square annotations in the source file: one ordinary, one Hidden (`/F 2`), one NoView
/// (`/F 32`). On macOS 27 PDFKit reports `shouldDisplay` false for NoView but true for Hidden,
/// so `shouldDisplay` alone would draw into the page image an annotation the file hides and no
/// reader of the PDF ever sees. Both flags are read from `/F` instead.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/170"))
func hiddenAndNoViewAnnotationsStayOutOfPageImages() throws {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Annots [5 0 R 6 0 R 7 0 R] >>",
        testPDFStream("1 0 0 rg 10 10 20 20 re f"),
        "<< /Type /Annot /Subtype /Square /Rect [20 100 60 140] /C [0 1 0] /IC [0 1 0] >>",
        "<< /Type /Annot /Subtype /Square /Rect [80 100 120 140] /F 2 /C [0 0 1] /IC [0 0 1] >>",
        "<< /Type /Annot /Subtype /Square /Rect [140 100 180 140] /F 32 /C [1 0 1] /IC [1 0 1] >>",
    ])
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: 0))
    #expect(page.annotations.count == 3)
    #expect(page.annotations.filter { $0.shouldDisplay }.count == 2)

    let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox), options: ConversionOptions())
    // The ordinary annotation and the page's own drawing are the positive controls: the rule must
    // remove the two the file hides, and nothing else.
    #expect(try pixelCount(image, near: (0, 255, 0)) > 1_000)
    #expect(try pixelCount(image, near: (255, 0, 0)) > 1_000)
    #expect(try pixelCount(image, near: (0, 0, 255)) == 0)
    #expect(try pixelCount(image, near: (255, 0, 255)) == 0)
}
