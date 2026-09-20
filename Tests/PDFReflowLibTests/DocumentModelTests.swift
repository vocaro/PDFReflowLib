import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private let pageBounds = CGRect(x: 0, y: 0, width: 600, height: 800)

private func line(_ text: String, x: Double, y: Double, width: Double = 200,
                  size: Double = 12, mono: Bool = false) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size), fontSize: size, monospaced: mono)
}

@Test func semanticLayoutRecoversColumnsAndHeadingWithoutMarkup() throws {
    let page = PageContent(number: 1, bounds: pageBounds, lines: [
        line("A <heading> & title", x: 40, y: 750, width: 500, size: 24),
        line("Left begins", x: 40, y: 700), line("Right begins", x: 340, y: 700),
        line("left ends.", x: 40, y: 680), line("right ends.", x: 340, y: 680),
    ], graphics: [])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.count == 3)
    guard case let .heading(_, title, _) = try #require(blocks.first).content else {
        Issue.record("Expected a semantic heading"); return
    }
    #expect(title.text == "A <heading> & title")
    #expect(blocks.dropFirst().map(\.text) == ["Left begins left ends.", "Right begins right ends."])
    #expect(warnings.isEmpty)
}

@Test func semanticCodePreservesIndentationAndLiteralSourceMarkup() throws {
    let page = PageContent(number: 1, bounds: pageBounds, lines: [
        line("if value < 3:", x: 40, y: 700, mono: true),
        line("print(value)", x: 68.8, y: 680, mono: true),
    ], graphics: [])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    try #require(blocks.count == 1)
    guard case let .preformatted(text) = blocks[0].content else {
        Issue.record("Expected preformatted code"); return
    }
    #expect(text.text == "if value < 3:\n    print(value)")
    #expect(try EPUBTextEncoder.payload(blocks[0], imagePaths: [:]) == "if value &lt; 3:\n    print(value)")
}

@Test func trimmingStyledTextKeepsInteriorWhitespace() {
    let text = InlineText(elements: [.text("  ", .bold), .text(" one ", .bold), .text("two  ", .italic)])
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(trimmed == InlineText(elements: [.text("one ", .bold), .text("two", .italic)]))
}

@Test func pageContinuationIsTestableWithoutPDFOrEPUB() {
    let previous = PageContent(number: 1, bounds: pageBounds,
        lines: [line("A contin-", x: 40, y: 40)], graphics: [])
    let current = PageContent(number: 2, bounds: pageBounds,
        lines: [line("uation follows.", x: 40, y: 740)], graphics: [])
    var blocks = [ReflowBlock(content: .sourcePage(1), page: 1),
                  ReflowBlock(content: .paragraph(InlineText("A contin-", style: .bold)), page: 1)]
    var warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage([.init(content: .paragraph(InlineText("uation follows.")), page: 2)],
        page: current, previousPage: previous, to: &blocks, vocabulary: ["continuation"], warnings: &warnings)
    #expect(blocks.count == 2)
    #expect(blocks.last?.text == "A continuation follows.")
    #expect(blocks.flatMap(\.sourcePages) == [1, 2])
    #expect(blocks.last?.page == 1)
    // An intervening figure prevents a prose join; its source boundary remains a block.
    LayoutReconstructor.appendPage([LayoutReconstructor.imageBlock(assetID: "diagram", page: 3)],
        page: PageContent(number: 3, bounds: pageBounds, lines: [], graphics: []),
        previousPage: current, to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks.suffix(2).first?.content == .sourcePage(3))
    #expect(blocks.flatMap(\.sourcePages) == [1, 2, 3])
}

@Test func semanticFiguresReferenceAssetsRatherThanOutputPaths() {
    let rect = CGRect(x: 40, y: 300, width: 200, height: 100)
    let page = PageContent(number: 4, bounds: pageBounds,
        lines: [line("Detached label", x: 50, y: 350)], graphics: [rect])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(rect, "opaque-id")], vocabulary: [], warnings: &warnings)
    #expect(blocks == [ReflowBlock(content: .image(.init(assetID: "opaque-id",
        alternativeText: "Preserved region from page 4", caption: "Preserved region from page 4")), page: 4)])
}

@Test func documentRejectsUnresolvedAndDuplicateAssets() throws {
    var book = ReflowDocument(metadata: .init(title: "Book", language: "en"),
        blocks: [LayoutReconstructor.imageBlock(assetID: "figure", page: 1)], assets: [])
    #expect(throws: ReflowDocument.ValidationError.missingAsset("figure")) { try book.validate() }
    let asset = ReflowDocument.Asset(id: "figure", fileURL: URL(fileURLWithPath: "/unused/figure.png"))
    book.assets = [asset, asset]
    #expect(throws: ReflowDocument.ValidationError.duplicateAsset("figure")) { try book.validate() }
    book.assets = [asset]
    try book.validate()
    book.blocks = []
    #expect(throws: ReflowDocument.ValidationError.emptyDocument) { try book.validate() }
}

@Test func epubEscapesRawTextAndRendersSemanticStylesAndPageMarkers() {
    let content = InlineText(elements: [.text("<tag> & \"quote\"\u{0001}", [.bold, .italic]), .sourcePage(2)])
    #expect(EPUBTextEncoder.inline(content) == "<strong><em>&lt;tag&gt; &amp; &quot;quote&quot;</em></strong>"
        + "<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-2\" aria-label=\"2\"/>")
    #expect(content.text.contains("<tag>")) // Serialization cannot alter the semantic model.
}

@Test func epubWriterStreamsNeutralAssetsAndBuildsInlinePageNavigation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-model-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("unrelated-resource.bin")
    let bytes = Data([137, 80, 78, 71]) // Byte-stream control; real PNGs are covered by PDF fixture tests.
    try bytes.write(to: source)
    let book = ReflowDocument(metadata: .init(title: "Title <&>", language: "en", author: "A & B"), blocks: [
        .init(content: .sourcePage(1), page: 1),
        .init(content: .paragraph(InlineText(elements: [.text("conver", .bold), .sourcePage(2), .text("sion", [])])), page: 1),
        .init(content: .image(.init(assetID: "../logical-id", alternativeText: "A \"label\"", caption: "A & B")), page: 2),
    ], assets: [.init(id: "../logical-id", fileURL: source)])
    let saved = book
    let output = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: directory,
                                            progress: { _ in })
    let archive = try Archive(url: output, accessMode: .read)
    func data(_ name: String) throws -> Data { try archive.entryData(name) }
    #expect(try data("EPUB/images/image-1.png") == bytes)
    #expect(try Data(contentsOf: source) == bytes)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("EPUB/images").path))
    let chapter = String(decoding: try data("EPUB/chapter-1.xhtml"), as: UTF8.self)
    #expect(chapter.contains("<strong>conver</strong><span"))
    #expect(chapter.contains("/>sion</p>"))
    #expect(chapter.contains("alt=\"A &quot;label&quot;\""))
    #expect(!chapter.contains("logical-id"))
    let nav = String(decoding: try data("EPUB/nav.xhtml"), as: UTF8.self)
    #expect(nav.contains("chapter-1.xhtml#page-1"))
    #expect(nav.contains("chapter-1.xhtml#page-2"))
    #expect(book == saved)
}

@Test func realPDFCanBeReconstructedWithoutAnEPUBWriter() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-pipeline-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = fixtureURL("prose.pdf")
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: .init(), workspace: directory,
                                                        progress: { _ in })
    #expect(result.pageCount == 3)
    #expect(result.reflowedPageCount == 3)
    #expect(result.book.blocks.map(\.text).joined(separator: " ").contains("reliable conversion without"))
    #expect(result.book.blocks.flatMap(\.sourcePages) == [1, 2, 3])
    #expect(result.book.assets.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["assets"])
    try result.book.validate()
}
