import CoreGraphics
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func fedPanelBlocks(_ number: Int, sourceTags: Bool = true) throws -> [ReflowBlock] {
    let fixture = try SourceLayoutFixture.load("fed-panel-\(number)")
    var page = fixture.content()
    page.lines = page.lines.map { line in
        guard let attributed = fixture.attributedLines.first(where: { $0.text == line.text }) else { return line }
        return TextLine(content: NativeTextReader.inlineText(from: attributed.attributedString()), rect: line.rect,
                        fontSize: line.fontSize, monospaced: line.monospaced)
    }
    page = TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
    if sourceTags {
        struct CapturedTags: Decodable {
            struct Row: Decodable { var text: String; var rect: [Double]; var structure: TextStructure }
            var retainedStructures: [Row]?
        }
        let capture = try JSONDecoder().decode(CapturedTags.self,
            from: Data(contentsOf: fixtureURL("fed-panel-\(number)-layout.json")))
        for row in capture.retainedStructures ?? [] {
            let index = try #require(page.lines.firstIndex { line in
                line.text == row.text && abs(line.rect.minX - row.rect[0]) < 0.001
                    && abs(line.rect.minY - row.rect[1]) < 0.001
            }, "Missing captured tagged line: \(row.text)")
            page.lines[index].structure = row.structure
        }
    }
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element,"image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
}

@Test func fedSidePanelFollowsTheCompleteAdjacentParagraph() throws {
    let blocks = try fedPanelBlocks(35)
    let main = try #require(blocks.first { $0.text.hasPrefix("Committee policy statements.") })
    #expect(main.text.contains("In addition to the regular FOMC statements following every meeting"))
    #expect(main.text.hasSuffix("regarding monetary policy implementation in the longer-run."))
    #expect(!main.text.contains("Regular congressional testimony"))
    let bodyIndex = try #require(blocks.firstIndex { $0.text == main.text })
    let panelIndex = try #require(blocks.firstIndex { $0.text.contains("Regular congressional testimony") })
    let nextIndex = try #require(blocks.firstIndex { $0.text.hasPrefix("Collecting information from the public.") })
    #expect(bodyIndex < panelIndex && panelIndex < nextIndex)
    #expect(blocks.contains { $0.text.lowercased().filter(\.isLetter).contains("theboardsubmitsthemonetarypolicyreporttocongresssemiannually") })
}

@Test(arguments: [19,34,35,36,37,54,56,60,63,71,73,74,78,79,80,84,94,95])
func recoveredFedPanelsKeepPreviouslyCompleteParagraphs(number: Int) throws {
    struct Expected: Decodable { var baselineParagraphs: [String] }
    let expected = try JSONDecoder().decode(Expected.self,
        from: Data(contentsOf: fixtureURL("fed-panel-\(number)-layout.json")))
    func canonical(_ text: String) -> String { text.lowercased().filter(\.isLetter) }
    let actual = try fedPanelBlocks(number)
    let blocks = actual.map { canonical($0.text) }
    for paragraph in expected.baselineParagraphs {
        let words = canonical(paragraph)
        #expect(blocks.contains { $0.contains(words) }, "Page \(number): \(paragraph)")
    }
}

@Test func nativePanelGroupingPreservesMetadataAndRejectsMixedFigures() throws {
    let fixture = try SourceLayoutFixture.load("fed-panel-35")
    var page = fixture.content()
    page = TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
    let panel = try #require(page.nativeTextPanels?.first)
    var lines = page.lines
    let first = try #require(lines.firstIndex { panel.contains($0.rect) })
    let original = lines[first]
    let marked = TextLine(content: InlineText(elements: [.link(.external("https://example.org/panel"),
        InlineText(original.text, style: [.bold,.italic]))]), rect: original.rect, fontSize: original.fontSize,
        wraps: true)
    lines[first] = marked
    func elements(_ rows: [TextLine]) -> [LayoutReconstructor.Element] {
        LayoutReconstructor.ordered(rows.map { .init(rect: $0.rect,line: $0) }, bodySize: 10)
    }
    let ordered = NativeTextPanels.ordered(elements(lines), panels: [panel], body: 10, rightToLeft: false)
    let members = try #require(ordered.compactMap(\.nativePanel).first)
    #expect(members.contains(marked))
    #expect((ordered.compactMap(\.line) + ordered.compactMap(\.nativePanel).flatMap { $0 }).count == lines.count)
    let graphic = LayoutReconstructor.Element(rect: panel.insetBy(dx: 5,dy: 5), image: "figure")
    let table = LayoutReconstructor.Element(rect: panel.insetBy(dx: 5,dy: 5), table: PageTable(rect: panel,
        rows: [[.init(content: InlineText("a"),rect: panel)]]))
    for obstruction in [graphic,table] {
        #expect(NativeTextPanels.ordered(elements(lines)+[obstruction], panels: [panel], body: 10,
            rightToLeft: false).allSatisfy { $0.nativePanel == nil })
    }
    var sharedTag = lines
    let outside = try #require(sharedTag.firstIndex { !panel.contains($0.rect) })
    let tag = TextStructure(group: 91, order: 0, headingLevel: 0, lineCount: 2)
    sharedTag[first].structure = tag
    sharedTag[outside].structure = tag
    #expect(NativeTextPanels.ordered(elements(sharedTag), panels: [panel], body: 10,
        rightToLeft: false).allSatisfy { $0.nativePanel == nil })
    let mirrored = lines.map { row in var line = row; line.rect.origin.x = 612 - row.rect.maxX; return line }
    let mirroredPanel = CGRect(x: 612-panel.maxX,y: panel.minY,width: panel.width,height: panel.height)
    let rightToLeft = NativeTextPanels.ordered(elements(mirrored), panels: [mirroredPanel], body: 10, rightToLeft: true)
    #expect(rightToLeft.compactMap(\.nativePanel).count == 1)
    #expect(rightToLeft.compactMap(\.nativePanel).flatMap { $0 }.map(\.text) == members.map(\.text))
}


@Test(arguments: [true, false])
func nativePanelsDoNotOverrideTaggedOrder(tagPanel: Bool) {
    let panel = CGRect(x: 250, y: 600, width: 160, height: 60)
    var elements: [LayoutReconstructor.Element] = []
    for group in [2, 1] {
        for row in 0..<3 {
            var line = TextLine(text: "\(group == 1 ? "Sidebar" : "Body") row \(row) contains several complete words in a sentence.",
                rect: CGRect(x: group == 1 ? 260 : 40, y: 640 - Double(row) * 12,
                             width: group == 1 ? 140 : 180, height: 10), fontSize: group == 1 ? 8 : 10)
            if group == 2 || tagPanel {
                line.structure = TextStructure(group: group, order: group - 1, headingLevel: 0, lineCount: 3)
            }
            elements.append(.init(rect: line.rect, line: line))
        }
    }
    var warnings: [ConversionWarning] = []
    let structured = LayoutReconstructor.structuredOrder(elements, page: 1, warnings: &warnings)
    if tagPanel { #expect(structured.compactMap { $0.line?.structure?.group } == [1, 1, 1, 2, 2, 2]) }
    let actual = NativeTextPanels.ordered(structured, panels: [panel], body: 10, rightToLeft: false)
    if tagPanel { #expect(actual.allSatisfy { $0.nativePanel == nil }) }
    #expect(actual.flatMap { $0.nativePanel ?? [$0.line].compactMap { $0 } } == structured.compactMap(\.line))
    #expect(warnings.isEmpty)
}

@Test func nativePanelHeadingsHaveUniquePackagedNavigationAnchors() async throws {
    var lines = [TextLine(text: "Main document heading",
        rect: CGRect(x: 40, y: 750, width: 400, height: 24), fontSize: 24)]
    var panels: [CGRect] = []
    let panelTitles = (1...2).map { InlineText(elements: [.link(.external("https://example.org/panel/\($0)"),
        InlineText("Panel \($0) heading", style: [.bold, .italic]))]) }
    for index in 0..<2 {
        let top = 640 - Double(index) * 200
        for row in 0..<7 {
            lines.append(TextLine(text: "A complete body sentence has enough words to make this row read as prose.",
                rect: CGRect(x: 40, y: top - Double(row) * 12, width: 180, height: 10), fontSize: 10))
        }
        lines.append(TextLine(content: panelTitles[index],
            rect: CGRect(x: 260, y: top + 10, width: 140, height: 16), fontSize: 16))
        for row in 0..<4 {
            lines.append(TextLine(text: "The panel contains a complete explanation in ordinary prose on this line.",
                rect: CGRect(x: 260, y: top - 6 - Double(row) * 10, width: 140, height: 8), fontSize: 8))
        }
        panels.append(CGRect(x: 250, y: top - 46, width: 160, height: 76))
    }
    var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    page.nativeTextPanels = panels
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, documentBody: 10)
    let headings = blocks.compactMap { block -> (String, InlineText, Int)? in
        if case let .heading(id, text, level) = block.content { return (id, text, level) }
        return nil
    }
    #expect(headings.map { $0.1.text } == ["Main document heading"] + panelTitles.map(\.text))
    #expect(Array(headings.dropFirst()).map { $0.1 } == panelTitles)
    #expect(Set(headings.map { $0.0 }).count == 3)
    #expect(headings.allSatisfy { $0.2 == 2 })
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = ReflowDocument(metadata: .init(title: "Panel anchors", language: "en"), blocks: blocks, assets: [])
    let output = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: directory, progress: { _ in })
    let archive = try Archive(url: output, accessMode: .read)
    let chapter = try archive.entryText("EPUB/chapter-1.xhtml")
    let nav = try archive.entryText("EPUB/nav.xhtml")
    for (id, text, level) in headings {
        #expect(chapter.components(separatedBy: "id=\"\(id)\"").count - 1 == 1)
        #expect(chapter.contains("<h\(level) id=\"\(id)\">" + EPUBTextEncoder.inline(text) + "</h\(level)>"))
        #expect(nav.components(separatedBy: "chapter-1.xhtml#\(id)").count - 1 == 1)
    }
}


@Test func leftFedPanelFollowsTheWiderContinuationOfItsAdjacentParagraph() throws {
    let blocks = try fedPanelBlocks(84, sourceTags: false)
    let paragraph = try #require(blocks.firstIndex { $0.text.hasPrefix("The Federal Reserve has established") })
    #expect(blocks[paragraph].text.contains("maintain a minimum liquidity buffer"))
    #expect(blocks[paragraph].text.hasSuffix("a firm to monitor its liquidity risk."))
    let panel = try #require(blocks.firstIndex { $0.text.contains("How do capital and liquidity differ?") })
    let following = try #require(blocks.firstIndex { $0.text.hasPrefix("The federal banking agencies established") })
    #expect(paragraph < panel && panel < following)
}

@Test(arguments: ["continued", "uppercase", "sentence", "detached", "remoteEdge", "imageBarrier", "textBarrier"])
func nativePanelWidensOnlyAcrossAnUninterruptedBrokenWord(variant: String) throws {
    let panel = CGRect(x: 10, y: 140, width: 90, height: 60)
    func row(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 10) -> LayoutReconstructor.Element {
        let line = TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size), fontSize: size)
        return .init(rect: line.rect, line: line)
    }
    var elements = [
        row("The adjacent paragraph contains several complete words.", x: 120, y: 170, width: 100),
        row("It continues at the same type size and leading.", x: 120, y: 154, width: 100),
    ]
    for n in 0..<3 {
        elements.append(row("This sidebar has its own complete explanation and separate reading order.",
            x: 15, y: 182 - CGFloat(n) * 12, width: 80, size: 8))
    }
    elements.append(row(variant == "sentence" ? "The paragraph ends here." : "This sentence ends in mini-",
        x: 120, y: 138, width: 100))
    if variant == "imageBarrier" {
        elements.append(.init(rect: CGRect(x: 230, y: 128, width: 20, height: 10), image: "separate-figure"))
    }
    if variant == "textBarrier" {
        elements.append(row("Unrelated text retains its position.", x: 250, y: 300, width: 180))
    }
    for n in 0..<3 {
        elements.append(row(n == 0 ? (variant == "uppercase" ? "Another paragraph starts here." : "mum and continues below the sidebar.")
            : "The wider paragraph continues to its own final row.",
            x: variant == "remoteEdge" ? 30 : 10,
            y: 122 - CGFloat(n) * 16 - (variant == "detached" ? 16 : 0), width: 210))
    }
    let actual = NativeTextPanels.ordered(elements, panels: [panel], body: 10, rightToLeft: false)
    let sidebar = try #require(actual.firstIndex { $0.nativePanel != nil })
    let wider = try #require(actual.firstIndex { $0.line?.text == "The wider paragraph continues to its own final row." })
    #expect((sidebar > wider) == (variant == "continued"))
    #expect(actual.compactMap(\.panelContinuationFrom).count == (variant == "continued" ? 1 : 0))
    #expect(actual.compactMap(\.line).count + actual.compactMap(\.nativePanel).flatMap { $0 }.count == (variant == "textBarrier" ? 10 : 9))
    #expect(actual.compactMap(\.image).count == (variant == "imageBarrier" ? 1 : 0))
}


@Test func unrelatedTaggedTextDoesNotDisableNativePanelParagraphs() throws {
    let withoutTag = try fedPanelBlocks(35, sourceTags: false)
    let withTag = try fedPanelBlocks(35)
    for phrase in ["Committee policy statements.", "Regular congressional testimony", "Collecting information from the public."] {
        let expected = try #require(withoutTag.first { $0.text.hasPrefix(phrase) })
        #expect(withTag.contains { $0.text == expected.text })
    }
}


@Test func retainedSourceTagsKeepFedPanelOutsideItsCompleteParagraph() throws {
    let blocks = try fedPanelBlocks(84)
    let paragraph = try #require(blocks.first { $0.text.hasPrefix("The Federal Reserve has established") })
    #expect(paragraph.text.contains("maintain a minimum liquidity buffer"))
    #expect(paragraph.text.hasSuffix("a firm to monitor its liquidity risk."))
    #expect(!paragraph.text.contains("How do capital"))
    let panel = try #require(blocks.firstIndex { $0.text.contains("How do capital and liquidity differ?") })
    let following = try #require(blocks.firstIndex { $0.text.hasPrefix("The federal banking agencies established") })
    #expect(panel < following)
}
