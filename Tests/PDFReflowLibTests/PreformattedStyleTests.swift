import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func fixedLine(_ content: InlineText, x: Double = 40, y: Double = 700,
                       mono: Bool = false) -> TextLine {
    TextLine(content: content, rect: CGRect(x: x, y: y, width: 400, height: 12),
             fontSize: 12, monospaced: mono)
}

private func fixedBlocks(_ lines: [TextLine]) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: PageContent(number: 1,
        bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
}

@Test func numberedAndBulletedLinesKeepNativeScriptsAndEmphasis() throws {
    for prefix in ["1. ", "2) ", "a) ", "• ", "− "] {
        let text = InlineText(elements: [.text(prefix + "x", .italic), .text("2", .superscript),
            .text(" + H", []), .text("2", .subscript), .text("O", .bold)])
        let block = try #require(fixedBlocks([fixedLine(text)]).first)
        #expect(block.text == text.text)
        #expect(try EPUBTextEncoder.payload(block, imagePaths: [:]) ==
            "<em>\(prefix)x</em><sup>2</sup> + H<sub>2</sub><strong>O</strong>")
    }
}

@Test func monospacedLinesKeepStylesIndentationAndLiteralMarkup() throws {
    let lines = [fixedLine(InlineText("if x < 2:", style: .bold), mono: true),
                 fixedLine(InlineText("print(\"<&>\")", style: .italic), x: 68.8, y: 680, mono: true)]
    let blocks = fixedBlocks(lines)
    try #require(blocks.count == 1)
    #expect(blocks[0].text == "if x < 2:\n    print(\"<&>\")")
    #expect(try EPUBTextEncoder.payload(blocks[0], imagePaths: [:]) ==
        "<strong>if x &lt; 2:</strong>\n    <em>print(&quot;&lt;&amp;&gt;&quot;)</em>")
}

@Test func unstyledListsStaySeparateAndKeepLiteralLineEndHyphens() throws {
    let blocks = fixedBlocks([fixedLine(InlineText("1. first-")),
                              fixedLine(InlineText("2. second <item>"), y: 680)])
    #expect(blocks.map(\.text) == ["1. first-", "2. second <item>"])
    #expect(try blocks.map { try EPUBTextEncoder.payload($0, imagePaths: [:]) } ==
        ["1. first-", "2. second &lt;item&gt;"])
}

@Test func proseAndCodeTransitionsDoNotJoinSeparateBlocks() throws {
    let blocks = fixedBlocks([fixedLine(InlineText("1. list item", style: .bold)),
                              fixedLine(InlineText("Ordinary prose.", style: .italic), y: 680),
                              fixedLine(InlineText("code < 2", style: .bold), y: 660, mono: true),
                              fixedLine(InlineText("2. another item"), y: 640)])
    #expect(blocks.map(\.text) == ["1. list item", "Ordinary prose.", "code < 2", "2. another item"])
    #expect(try EPUBTextEncoder.payload(blocks[1], imagePaths: [:]) == "<em>Ordinary prose.</em>")
}

@Test func algebraNumberedExerciseRetainsBothSourceExponents() throws {
    let page = try styledSourcePage("algebra-26")
    let regions = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions, vocabulary: [], warnings: &warnings)
    let exercise = try #require(blocks.first { $0.text.hasPrefix("80) ") })
    #expect(exercise.text == "80) (7a2 +7a)− (6a2 + 4a)")
    let payload = try EPUBTextEncoder.payload(exercise, imagePaths: [:])
    #expect(payload.components(separatedBy: "<sup>2 ").count - 1 == 2)
    #expect(!payload.contains("<sub>"))
}

@Test func styledPreformattedBlockSurvivesPackagingAndInlinePageNavigation() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let text = InlineText(elements: [.text("1. x", .bold), .text("2", .superscript),
        .text("\n    H", []), .sourcePage(2), .text("2", .subscript), .text("O <&>", .italic)])
    let book = ReflowDocument(metadata: .init(title: "Styled list", language: "en"), blocks: [
        .init(content: .sourcePage(1), page: 1), .init(content: .preformatted(text), page: 1),
    ], assets: [])
    let original = book
    let url = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: dir, progress: { _ in })
    let archive = try Archive(url: url, accessMode: .read)
    func read(_ path: String) throws -> String {
        let entry = try #require(archive[path]); var data = Data()
        _ = try archive.extract(entry) { data += $0 }
        return String(decoding: data, as: UTF8.self)
    }
    #expect(try read("EPUB/chapter-1.xhtml").contains("<pre>" + EPUBTextEncoder.inline(text) + "</pre>"))
    #expect(try read("EPUB/nav.xhtml").contains("chapter-1.xhtml#page-2"))
    #expect(book.blocks.flatMap(\.sourcePages) == [1, 2])
    #expect(book == original)
}

@Test func preformattedStylesCountTowardSpineBudgetWithoutLosingRuns() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    // Plain text fits the target, but the style wrappers take the combined body past it. Styles
    // alternate and share nothing: adjacent runs of one style are written as one element (#133),
    // and a run nested inside the style beside it joins that element too (#142).
    let text = InlineText(elements: (0..<4_000).map { .text("x", $0.isMultiple(of: 2) ? .bold : .italic) })
    let book = ReflowDocument(metadata: .init(title: "Styled packing", language: "en"), blocks: [
        .init(content: .sourcePage(1), page: 1),
        .init(content: .preformatted(text), page: 1), .init(content: .preformatted(text), page: 1),
    ], assets: [])
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: dir, progress: { _ in })
    let first = try String(contentsOf: dir.appendingPathComponent("EPUB/chapter-1.xhtml"), encoding: .utf8)
    let second = try String(contentsOf: dir.appendingPathComponent("EPUB/chapter-2.xhtml"), encoding: .utf8)
    for chapter in [first, second] {
        #expect(chapter.components(separatedBy: "<strong>x</strong>").count - 1 == 2_000)
        #expect(chapter.components(separatedBy: "<em>x</em>").count - 1 == 2_000)
        #expect(chapter.contains("<pre>"))
    }
}

private func styledSourcePage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    for i in page.lines.indices {
        if let source = fixture.attributedLines.first(where: { $0.text == page.lines[i].text }) {
            let line = page.lines[i]
            page.lines[i] = TextLine(content: NativeTextReader.inlineText(from: source.attributedString()),
                rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
        }
    }
    return page
}

@Test func faaBulletListsKeepVSpeedSubscriptsFromNativeRuns() throws {
    for (number, symbol) in [(211, "S0"), (212, "YSE")] {
        let page = try styledSourcePage("faa-\(number)")
        let regions = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
        var warnings: [ConversionWarning] = []
        let blocks = LayoutReconstructor.blocks(page: page, images: regions, vocabulary: [], warnings: &warnings)
        let bullet = try #require(blocks.first { $0.text.hasPrefix("•") && $0.text.contains("(V" + symbol + ")") })
        let html = try EPUBTextEncoder.payload(bullet, imagePaths: [:])
        #expect(html.contains("V<sub>\(symbol)</sub>"))
        #expect(!html.contains("<sup>"))
    }
}
