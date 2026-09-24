import CryptoKit
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/175"))
func centeredEarthdataCoverIsDistinctFromAnOrdinarySlideOrReportPage() throws {
    let cover = try SourceLayoutFixture.load("earthdata-sparse-1")
    #expect(cover.sourceSHA256 == "f0a1ea3f5711228a9de2544fd1a94b05cfb8d9323fe3a4c253542f5a6ead5c94")
    #expect(SlideDeck.cover(in: cover.content()))
    for name in ["earthdata-10", "faa-91", "911-14"] {
        #expect(!SlideDeck.cover(in: try SourceLayoutFixture.load(name).content()),
                Comment(rawValue: name))
    }
}

/// A one-page extraction of `earthdata-two-level-derived.pdf` with only its page dictionary's
/// /Rotate changed to 90. The source is a small synthetic deck based on Earthdata's typography;
/// it contains no NASA insignia or raster from the original presentation (#175).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/175"))
func rotatedSparseSlideReflowsWhileOtherRotatedPagesKeepTheirFallback() async throws {
    let source = fixtureURL("earthdata-rotated-derived.pdf")
    let digest = SHA256.hash(data: try Data(contentsOf: source))
        .map { String(format: "%02x", $0) }.joined()
    #expect(digest == "d57fd11a78848e86003a1fad003699f3b44cead0c6cc42ac3ff65588591aed4d")
    let pageSource = try PDFPageSource(url: source)
    let page = try PageReader.read(pageIndex: 0, from: pageSource, limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    #expect(!page.requiresPageImage)
    #expect(SlideDeck.title(in: page).map(\.text) == ["Mission Overview"])

    let dir = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("rotated-slide.epub")
    let report = try await PDFConverter().convert(from: source, to: output)
    #expect(report.reflowedPageCount == 1)
    #expect(!report.warnings.contains { $0.code == .pageImageFallback })
    let archive = try Archive(url: output, accessMode: .read)
    let body = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(body.contains("Mission Overview"))
    #expect(body.contains("Storage Strategy"))
    #expect(body.contains("The archive keeps data near analysis services."))

    let ordinaryRotated = try PDFPageSource(url: fixtureURL("rotated.pdf"))
    let fallback = try PageReader.read(pageIndex: 0, from: ordinaryRotated, limit: 100_000,
                                       options: ConversionOptions(), structure: nil).content
    #expect(fallback.requiresPageImage)
}
