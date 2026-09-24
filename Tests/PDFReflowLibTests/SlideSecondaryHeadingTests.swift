import CoreGraphics
import CryptoKit
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Three 720×405 slides derived from Earthdata slide 10's display geometry (title at 30 pt),
// with a 22-pt secondary heading over 16-pt prose. The source itself has no unambiguous
// second-tier heading, so the fixture states that typography explicitly on each slide.
private let twoLevelDeckSHA256 = "35015a04814cc750c73eeeba3b8fa459ab5f27c3783c9b92f8ff4e8faada5fdb"

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/175"))
func slideSecondaryHeadingsRequireBodyBeneathTheirOwnEdge() throws {
    let url = fixtureURL("earthdata-two-level-derived.pdf")
    let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    #expect(hash == twoLevelDeckSHA256)
    let source = try PDFPageSource(url: url)
    let page = try PageReader.read(pageIndex: 0, from: source, limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    let title = SlideDeck.title(in: page)
    let body = PageTypography(page: page).body
    #expect(title.map(\.text) == ["Mission Overview"])
    #expect(SlideDeck.secondaryHeadings(in: page, title: title, body: body).map(\.text) == ["Storage Strategy"])

    var withLabel = page
    withLabel.lines.append(TextLine(text: "Archive", rect: CGRect(x: 500, y: 150, width: 85, height: 22), fontSize: 22))
    #expect(SlideDeck.secondaryHeadings(in: withLabel, title: title, body: body).map(\.text) == ["Storage Strategy"])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: withLabel, images: [],
        context: .init(slideDeck: true), warnings: &warnings)
    #expect(blocks.contains { if case let .heading(_, text, level) = $0.content {
        return level == 3 && text.text == "Storage Strategy"
    }; return false })
    #expect(!blocks.contains { if case let .heading(_, text, _) = $0.content {
        return text.text == "Archive"
    }; return false })

    // Actual Earthdata labels and 28-pt callouts are not a subordinate heading tier.
    for name in ["earthdata-sparse-2", "earthdata-7", "earthdata-10", "earthdata-11"] {
        let slide = try SourceLayoutFixture.load(name).content()
        #expect(SlideDeck.secondaryHeadings(in: slide, title: SlideDeck.title(in: slide),
                                            body: PageTypography(page: slide).body).isEmpty,
                Comment(rawValue: name))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/175"))
func twoLevelSlideDeckWritesH3AndNavigationAnchors() async throws {
    let source = fixtureURL("earthdata-two-level-derived.pdf")
    let dir = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("deck.epub")
    let report = try await PDFConverter().convert(from: source, to: output)
    #expect(report.reflowedPageCount == 3)
    let archive = try Archive(url: output, accessMode: .read)
    let body = String(decoding: try archive.entryData("EPUB/chapter-1.xhtml"), as: UTF8.self)
    let nav = String(decoding: try archive.entryData("EPUB/nav.xhtml"), as: UTF8.self)
    for (page, title, secondary) in [(1, "Mission Overview", "Storage Strategy"),
                                     (2, "Service Design", "Processing Layers"),
                                     (3, "Delivery Plan", "Release Schedule")] {
        #expect(body.contains("<h2 id=\"heading-\(page)-0\">\(title)</h2>"))
        #expect(body.contains("<h3 id=\"heading-\(page)-1\">\(secondary)</h3>"))
        #expect(nav.contains("#heading-\(page)-0\">\(title)</a>"))
        #expect(nav.contains("#heading-\(page)-1\">\(secondary)</a>"))
    }
    #expect(body.contains("<p>The archive keeps data near analysis services."))
    #expect(!body.contains("<h3 id=\"heading-1-2\""))
}
