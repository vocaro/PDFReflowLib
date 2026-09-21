import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import PDFReflowLib

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-embedded-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// A JPEG of `width` by `height` pixels, drawn as a photograph would be: a gradient, so the
/// encoder keeps every block rather than collapsing the image to one colour.
private func jpegData(width: Int, height: Int, gray: Bool = false) throws -> Data {
    let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
    let alpha = gray ? CGImageAlphaInfo.none : .noneSkipLast
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue))
    for x in 0..<width {
        context.setFillColor(gray: Double(x) / Double(width), alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

/// A one-page PDF placing `jpeg` over part of a 400 by 300 page, with `space` as the image's
/// colour space, `extra` merged into its dictionary, and a caption drawn beneath it. A `profile`
/// is written as object 7, which is what `/ColorSpace [/ICCBased 7 0 R]` names.
private func placingPDF(_ jpeg: Data, width: Int, height: Int, space: String = "/DeviceRGB",
                        extra: String = "", profile: Data? = nil) -> Data {
    let header = "<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) "
        + "/BitsPerComponent 8 /ColorSpace \(space) \(extra) /Filter /DCTDecode "
        + "/Length \(jpeg.count) >>\nstream\n"
    var image = Data(header.utf8)
    image.append(jpeg)
    image.append(Data("\nendstream".utf8))
    var bodies: [Data] = [
        Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
        Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
        Data(("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources "
              + "<< /XObject << /Im0 5 0 R >> /Font << /F1 6 0 R >> >> /Contents 4 0 R >>").utf8),
        Data(testPDFStream("q 300 0 0 200 50 80 cm /Im0 Do Q "
                           + "BT /F1 11 Tf 50 40 Td (A caption under the picture.) Tj ET").utf8),
        image,
        Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".utf8),
    ]
    if let profile {
        var stream = Data("<< /N 3 /Length \(profile.count) >>\nstream\n".utf8)
        stream.append(profile)
        stream.append(Data("\nendstream".utf8))
        bodies.append(stream)
    }
    var data = Data("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, body) in bodies.enumerated() {
        offsets.append(data.count)
        data.append(Data("\(index + 1) 0 obj\n".utf8))
        data.append(body)
        data.append(Data("\nendobj\n".utf8))
    }
    let start = data.count
    data.append(Data("xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets {
        data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size \(bodies.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8))
    return data
}

private func convert(_ data: Data, in directory: URL, name: String = "book",
                     options: ConversionOptions = ConversionOptions()) async throws -> Archive {
    let source = directory.appendingPathComponent(name + ".pdf")
    try data.write(to: source)
    let output = directory.appendingPathComponent(name + ".epub")
    _ = try await PDFConverter().convert(from: source, to: output, options: options)
    return try Archive(url: output, accessMode: .read)
}

/// The bytes of every image asset in a converted book, by archive path.
private func images(_ archive: Archive) throws -> [String: Data] {
    var found: [String: Data] = [:]
    for entry in archive where entry.path.hasPrefix("EPUB/images/") {
        found[entry.path] = try archive.entryData(entry.path)
    }
    return found
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/251"))
func aCropThatIsOnePlacedJPEGIsWrittenAsThatJPEG() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let jpeg = try jpegData(width: 1_200, height: 800)
    let archive = try await convert(placingPDF(jpeg, width: 1_200, height: 800), in: dir)
    let written = try images(archive)
    #expect(written.count == 1)
    let asset = try #require(written.values.first)
    // The source's own bytes, not a re-render: 1,200 by 800, where a 180 DPI redraw of a
    // 300 by 200 point placement would be 750 by 500.
    #expect(asset == jpeg)
    #expect(EmbeddedImageReader.jpegFrame(asset).map { [$0.width, $0.height] } == [1_200, 800])
    #expect(try archive.chapter().contains(".jpg"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/251"))
func anICCBasedImageCarriesItsProfileIntoTheExtractedFile() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let profile = try #require(CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?)
    let jpeg = try jpegData(width: 900, height: 600)
    let pdf = placingPDF(jpeg, width: 900, height: 600, space: "[/ICCBased 7 0 R]", profile: profile)
    let asset = try #require(try images(try await convert(pdf, in: dir)).values.first)
    #expect(EmbeddedImageReader.hasICCProfile(asset))
    #expect(asset.count > jpeg.count)
    // The picture itself is untouched: the segments are inserted, nothing is re-encoded.
    #expect(EmbeddedImageReader.jpegFrame(asset).map { [$0.width, $0.height] } == [900, 600])
    let source = try #require(CGImageSourceCreateWithData(asset as CFData, nil))
    #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/251"))
func everythingOutsideTheSafeSetKeepsTheRenderItAlwaysHad() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let jpeg = try jpegData(width: 900, height: 600)
    // A soft mask, a decode array, a colour space that needs resolving, and a stated size the
    // file's own header contradicts.
    for (name, space, extra) in [("masked", "/DeviceRGB", "/Mask [0 255 0 255 0 255]"),
                                 ("decoded", "/DeviceRGB", "/Decode [1 0 1 0 1 0]"),
                                 ("indexed", "[/Indexed /DeviceRGB 1 <FFFFFF000000>]", ""),
                                 ("cmyk", "/DeviceCMYK", "")] {
        let asset = try #require(try images(try await convert(
            placingPDF(jpeg, width: 900, height: 600, space: space, extra: extra),
            in: dir, name: name)).values.first)
        #expect(asset != jpeg, "\(name) must be rendered, not extracted")
    }
    // A dictionary that misstates the image's size is not trusted either.
    let mismatched = try #require(try images(try await convert(
        placingPDF(jpeg, width: 901, height: 600), in: dir, name: "mismatched")).values.first)
    #expect(mismatched != jpeg)
    // A client that asked for PNG regions asked for PNG.
    var options = ConversionOptions()
    options.regionImageEncoding = .png
    let rendered = try #require(try images(try await convert(
        placingPDF(jpeg, width: 900, height: 600), in: dir, name: "png", options: options)).values.first)
    #expect(rendered != jpeg)
    #expect(rendered.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/251"))
func anExtractedImageObeysTheOutputBudgetBeforeItIsCommitted() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let jpeg = try jpegData(width: 1_200, height: 800)
    var options = ConversionOptions()
    // Smaller than the source's own bytes; a 180 DPI render of a 300 by 200 point region is a
    // fraction of that and still fits, which is the fallback the budget is there to reach.
    options.maximumOutputBytes = Int64(jpeg.count) - 1
    let asset = try #require(try images(try await convert(placingPDF(jpeg, width: 1_200, height: 800),
                                                          in: dir, options: options)).values.first)
    #expect(asset != jpeg)
    #expect(asset.count < jpeg.count)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/251"))
func aJPEGsOwnHeaderIsReadBeforeItIsTrusted() throws {
    let jpeg = try jpegData(width: 64, height: 32)
    let frame = try #require(EmbeddedImageReader.jpegFrame(jpeg))
    #expect(frame.width == 64 && frame.height == 32 && frame.components == 3)
    let gray = try #require(EmbeddedImageReader.jpegFrame(try jpegData(width: 20, height: 10, gray: true)))
    #expect(gray.components == 1)
    #expect(EmbeddedImageReader.jpegFrame(Data([0xFF, 0xD8, 0xFF])) == nil)
    #expect(EmbeddedImageReader.jpegFrame(Data("not a picture".utf8)) == nil)
    // A profile is inserted once, as APP2 segments, and the picture's own bytes follow it.
    let profile = Data(repeating: 0x42, count: 1_000)
    let embedded = try #require(EmbeddedImageReader.insertingICCProfile(profile, into: jpeg))
    #expect(EmbeddedImageReader.hasICCProfile(embedded))
    #expect(!EmbeddedImageReader.hasICCProfile(jpeg))
    #expect(embedded.count == jpeg.count + 1_000 + 18)
    #expect(EmbeddedImageReader.jpegFrame(embedded).map { [$0.width, $0.height] } == [64, 32])
}
