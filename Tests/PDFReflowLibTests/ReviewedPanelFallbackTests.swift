import Foundation
import CryptoKit
import ImageIO
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

/// The caller has reviewed a page whose panel order OCR cannot establish (#18). The option
/// replaces that page with a readable source image under every OCR policy, including `.always`.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/18"),
      arguments: [ConversionOptions.OCRPolicy.automatic, .always, .never])
func reviewedPanelPageBypassesOCRAndReportsLimitedReflow(policy: ConversionOptions.OCRPolicy) async throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = fixtureURL("columns.pdf")
    let output = directory.appendingPathComponent("panels.epub")
    var options = ConversionOptions()
    options.ocr = policy
    options.reviewedPanelImagePages = [1]
    let report = try await PDFConverter().convert(from: source, to: output, options: options)
    #expect(report.recognizedPageCount == 0)
    #expect(report.reflowedPageCount == 0)
    #expect(report.warnings.contains { $0.code == .reviewedPanelImage && $0.page == 1
        && $0.message.contains("does not reflow") && $0.message.contains("verified reading order") })
    #expect(report.warnings.contains { $0.code == .pageImageFallback && $0.page == 1 })
    #expect(!report.warnings.contains { $0.code == .ocrUsed })

    let archive = try Archive(url: output, accessMode: .read)
    let html = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(html.contains("<img"))
    #expect(!html.contains("LEFT FIRST begins the left column."))
    let image = try #require(archive.first { $0.path.hasPrefix("EPUB/images/") })
    let data = try archive.entryData(image.path)
    let sourceImage = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let raster = try #require(CGImageSourceCreateImageAtIndex(sourceImage, 0, nil))
    #expect(raster.width >= 1_000 && raster.height >= 1_000)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/18"))
func unselectedPageKeepsItsOrdinaryReflowAndOutOfRangeSelectionsFail() async throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = fixtureURL("columns.pdf")
    let output = directory.appendingPathComponent("normal.epub")
    var options = ConversionOptions()
    options.ocr = .never
    let report = try await PDFConverter().convert(from: source, to: output, options: options)
    #expect(report.reflowedPageCount == 1)
    #expect(!report.warnings.contains { $0.code == .reviewedPanelImage })
    let archive = try Archive(url: output, accessMode: .read)
    let html = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(html.contains("LEFT FIRST begins the left column."))

    options.reviewedPanelImagePages = [2]
    do {
        _ = try await PDFConverter().convert(from: source, to: directory.appendingPathComponent("invalid.epub"),
                                             options: options)
        Issue.record("Out-of-range reviewed page was accepted")
    } catch ConversionError.invalidOptions { }
}

/// CDC page 13 is the reviewed failure: its upper-right awakening dialogue must not be placed
/// after the lower-left response or promoted to a section heading. An image preserves the
/// printed order while the warning says the dialogue itself is not reflowable.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/18"))
func reviewedCDCPageThirteenKeepsTheReadableSourceImage() async throws {
    let url = URL(fileURLWithPath: "corpus/cache/cdc_6023_DS1.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let sourceData = try Data(contentsOf: url)
    let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
    #expect(digest == "d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3")
    let document = try #require(PDFDocument(data: sourceData))
    let page = try #require(document.page(at: 12))
    let excerpt = PDFDocument()
    excerpt.insert(page, at: 0)
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("cdc-13.pdf")
    #expect(excerpt.write(to: input))
    var options = ConversionOptions()
    options.ocr = .always
    options.reviewedPanelImagePages = [1]
    let output = directory.appendingPathComponent("cdc-13.epub")
    let report = try await PDFConverter().convert(from: input, to: output, options: options)
    #expect(report.recognizedPageCount == 0 && report.reflowedPageCount == 0)
    #expect(report.warnings.contains { $0.code == .reviewedPanelImage })
    let archive = try Archive(url: output, accessMode: .read)
    let html = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(!html.contains("OKAY, OKAY") && !html.contains("AND SEE WHAT"))
    let image = try #require(archive.first { $0.path.hasPrefix("EPUB/images/") })
    let data = try archive.entryData(image.path)
    let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let raster = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    #expect(raster.width == 1_530 && raster.height == 1_980)
}
