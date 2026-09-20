import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func policyFixture(_ name: String) -> URL {
    fixtureURL("\(name).pdf")
}
private actor PolicyProgress {
    var events: [ConversionProgress] = []
    func add(_ event: ConversionProgress) { events.append(event) }
}

@Test func referencePoliciesPreserveTextAndHonestWarnings() async throws {
    for policy in [ConversionOptions.ReferenceImagePolicy.automatic, .always, .never] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("scan.pdf"), output = dir.appendingPathComponent("book.epub")
        try textLayerPDF("Existing transcription.").write(to: input)
        var options = ConversionOptions(); options.referenceImages = policy
        let report = try await PDFConverter().convert(from: input, to: output, options: options)
        let archive = try Archive(url: output, accessMode: .read)
        let text = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
        #expect(text.contains("Existing transcription."))
        #expect(report.reflowedPageCount == 1)
        #expect(report.imageCount == (policy == .never ? 0 : 1))
        let warning = try #require(report.warnings.first { $0.code == .unverifiedTextLayer })
        #expect(warning.message.contains("accompanying") == (policy != .never))
        #expect(report.warnings.contains { $0.code == .referenceImageOmitted } == (policy == .never))
        #expect(text.contains("Original page 1") == (policy != .never))
    }
}

@Test func referenceOmissionKeepsFallbacksAndFreshOCRWarnings() async throws {
    for ocr in [ConversionOptions.OCRPolicy.automatic, .never] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        var options = ConversionOptions(); options.referenceImages = .never; options.ocr = ocr
        options.fullPageImageEncoding = .jpeg(quality: 0.9)
        let output = dir.appendingPathComponent("book.epub")
        let report = try await PDFConverter().convert(from: policyFixture("scanned"), to: output, options: options)
        if ocr == .automatic {
            #expect(report.recognizedPageCount == 1)
            #expect(report.reflowedPageCount == 1)
            #expect(report.warnings.contains { $0.code == .referenceImageOmitted })
            #expect(report.warnings.contains { $0.code == .ocrUsed && $0.message.contains("references are disabled") })
        } else {
            #expect(report.imageCount == 1)
            #expect(report.reflowedPageCount == 0)
            #expect(report.warnings.contains { $0.code == .pageImageFallback })
            #expect(!report.warnings.contains { $0.code == .referenceImageOmitted })
            let archive = try Archive(url: output, accessMode: .read)
            #expect(try archive.entryData("EPUB/images/image-1.jpg").starts(with: [0xff, 0xd8]))
        }
    }
}

@Test func alwaysReferencesDoNotDuplicateFallbacksOrDiscardCrops() async throws {
    for name in ["prose", "graphics", "rotated"] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        var options = ConversionOptions(); options.referenceImages = .always
        let result = try await PDFReflowLibPipeline.reconstruct(from: policyFixture(name), options: options,
            workspace: dir, progress: { _ in })
        #expect(result.book.assets.count == (name == "prose" ? 3 : name == "graphics" ? 4 : 1))
        if name == "rotated" { #expect(result.warnings.filter { $0.code == .pageImageFallback }.count == 1) }
        if name == "graphics" {
            #expect(result.book.blocks.contains { $0.text.contains("Text after the table") })
        }
    }
}

@Test func pageAndRegionCodecsAreIndependentAndEPUBMediaTypesMatchBytes() async throws {
    for pageJPEG in [false, true] {
        for regionJPEG in [false, true] {
            let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            var options = ConversionOptions(); options.referenceImages = .always
            options.fullPageImageEncoding = pageJPEG ? .jpeg(quality: 0.9) : .png
            options.regionImageEncoding = regionJPEG ? .jpeg(quality: 0.95) : .png
            let output = dir.appendingPathComponent("book.epub")
            let report = try await PDFConverter().convert(from: policyFixture("graphics"), to: output, options: options)
            #expect(report.imageCount == 4)
            let archive = try Archive(url: output, accessMode: .read)
            let opf = String(decoding: try archive.entryData("EPUB/package.opf"), as: UTF8.self)
            let html = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
            #expect(html.contains("Text before the illustrated region"))
            #expect(html.contains("Text after the table"))
            for index in 1...4 {
                let jpeg = index == 4 ? pageJPEG : regionJPEG
                let path = "images/image-\(index).\(jpeg ? "jpg" : "png")"
                let bytes = try archive.entryData("EPUB/" + path)
                #expect(bytes.starts(with: jpeg ? [0xff, 0xd8] : [137, 80, 78, 71]))
                let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
                let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(image.width > 0 && image.height > 0)
                #expect(opf.contains("href=\"\(path)\" media-type=\"image/\(jpeg ? "jpeg" : "png")\""))
                #expect(html.contains("src=\"\(path)\""))
            }
        }
    }
}

@Test func smallestEncodingHandlesCleanAndNoisyImagesWithoutResizingOrExtraAssets() throws {
    for noisy in [false, true] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        var seed: UInt32 = 17
        var pixels = [UInt8](repeating: 255, count: 256 * 256 * 4)
        if noisy {
            for i in stride(from: 0, to: pixels.count, by: 4) {
                seed = seed &* 1664525 &+ 1013904223
                let gray = UInt8(truncatingIfNeeded: seed >> 24)
                pixels[i] = gray; pixels[i+1] = gray; pixels[i+2] = gray
            }
        }
        let data = Data(pixels)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let result = try PageRasterizer.encode(image, at: dir.appendingPathComponent("asset"),
            encoding: .smallest(jpegQuality: 0.9))
        #expect(result.format == (noisy ? .jpeg : .png))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        let source = try #require(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 256 && decoded.height == 256)
    }
}

@Test func finalEPUBCapAndEntryBudgetAreSeparateAndFailuresCleanUp() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for finalCap in [true, false] {
        var options = ConversionOptions()
        options.maximumOutputBytes = finalCap ? .max : 1
        options.maximumEPUBBytes = finalCap ? 1 : nil
        let output = dir.appendingPathComponent("fail.epub"), log = PolicyProgress()
        do {
            _ = try await PDFConverter().convert(from: policyFixture("prose"), to: output, options: options) {
                await log.add($0)
            }
            Issue.record("Expected a size-limit failure")
        } catch ConversionError.resourceLimit(let reason) {
            if finalCap { #expect(reason == "final EPUB file bytes") }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        let events = await log.events
        #expect(!events.contains { $0.stage == .completed || $0.fractionCompleted == 1 })
    }
    var options = ConversionOptions(); options.maximumOutputBytes = .max; options.maximumEPUBBytes = 1_048_576
    let output = dir.appendingPathComponent("pass.epub")
    _ = try await PDFConverter().convert(from: policyFixture("prose"), to: output, options: options)
    #expect(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize! <= 1_048_576)
}

@Test func invalidEncodingAndFinalCapsFailBeforeWork() async throws {
    for quality in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
        for region in [false, true] {
            let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            var options = ConversionOptions()
            if region { options.regionImageEncoding = .smallest(jpegQuality: quality) }
            else { options.fullPageImageEncoding = .jpeg(quality: quality) }
            await #expect(throws: ConversionError.self) {
                try await PDFConverter().convert(from: policyFixture("prose"), to: dir.appendingPathComponent("out.epub"), options: options)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }
    }
    for limit: Int64 in [0, -1] {
        var options = ConversionOptions(); options.maximumEPUBBytes = limit
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: ConversionError.self) {
            try await PDFConverter().convert(from: policyFixture("prose"), to: dir.appendingPathComponent("out.epub"), options: options)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}
