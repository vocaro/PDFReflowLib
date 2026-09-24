import Foundation
import Testing
@testable import PDFReflowLib

private func sourceListBlocks(_ name: String) throws -> [ReflowBlock] {
    let fixture = try SourceLayoutFixture.load(name)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: fixture.content(), images: [], vocabulary: [], warnings: &warnings)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func earthdataSlideSevenKeepsLetteredChildrenUnderThirdGoal() throws {
    let blocks = try sourceListBlocks("earthdata-7")
    let built = ListBuilder.build(blocks)
    let items = built.compactMap { block -> ReflowBlock.ListItem? in
        if case let .listItem(item) = block.content { return item }
        return nil
    }
    #expect(items.map(\.marker) == ["1.", "2.", "3.", "a.", "b."])
    #expect(items.map(\.level) == [0, 0, 0, 1, 1])
    #expect(items.map(\.kind) == [.ordered, .ordered, .ordered,
                                  .lettered(uppercase: false), .lettered(uppercase: false)])
    let entries = built.compactMap { block -> EPUBTextEncoder.ListEntry? in
        if case let .listItem(item) = block.content { return .init(block: block, item: item) }
        return nil
    }
    let markup = try EPUBTextEncoder.list(.ordered, start: 1, entries: entries, imagePaths: [:]).markup
    #expect(markup.contains("<li>Maximum analytics capability at minimum cost<ol type=\"a\"><li>Use capabilities within NASA"))
    #expect(markup.contains("</ol></li></ol>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func warrenScannedLetteredPagesDoNotInventListDepth() throws {
    // PDFKit's inherited OCR makes these pages one preformatted transcription. Geometry cannot
    // safely assign list depth until line roles recover independently; keep the transcription.
    for page in ["warren-529", "warren-572"] {
        let blocks = try sourceListBlocks(page)
        #expect(ListBuilder.build(blocks).allSatisfy { block in
            if case .listItem = block.content { return false }
            return true
        })
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func aStrayLetterOnTheSameSourceGeometryIsNotAList() throws {
    var page = try SourceLayoutFixture.load("earthdata-7").content()
    let index = try #require(page.lines.firstIndex { $0.text == "b." })
    let old = page.lines[index]
    page.lines[index] = TextLine(text: "z.", rect: old.rect, fontSize: old.fontSize)
    let a = try #require(page.lines.first { $0.text == "a." })
    let typography = PageTypography(page: page)
    #expect(!LayoutReconstructor.opensAloneAsMarker(a, in: page.lines, body: typography.body))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func earthdataActualPageDoesNotSplitLetteredRunAtPaintedPanel() throws {
    let url = URL(fileURLWithPath: "corpus/cache/20180003024.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let source = try PDFPageSource(url: url)
    let page = try PageReader.read(pageIndex: 6, from: source, limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let markers = ListBuilder.build(blocks).compactMap { block -> ReflowBlock.ListItem? in
        if case let .listItem(item) = block.content { return item }
        return nil
    }
    #expect(markers.map(\.marker) == ["1.", "2.", "3.", "a.", "b."])
    #expect(markers.map(\.level) == [0, 0, 0, 1, 1])
}
