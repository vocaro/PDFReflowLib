import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private func fedPanelBlocks(_ number: Int) throws -> [ReflowBlock] {
    let fixture = try SourceLayoutFixture.load("fed-panel-\(number)")
    var page = fixture.content()
    page.lines = page.lines.map { line in
        guard let attributed = fixture.attributedLines.first(where: { $0.text == line.text }) else { return line }
        return TextLine(content: NativeTextReader.inlineText(from: attributed.attributedString()), rect: line.rect,
                        fontSize: line.fontSize, monospaced: line.monospaced)
    }
    page = TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
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

@Test(arguments: [19,34,35,36,37,54,56,60,63,71,73,74,78,79,80,94,95])
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
    var marked = TextLine(content: InlineText(elements: [.link(.external("https://example.org/panel"),
        InlineText(original.text, style: [.bold,.italic]))]), rect: original.rect, fontSize: original.fontSize,
        wraps: true)
    marked.structure = TextStructure(group: 91, order: 0, headingLevel: 0, lineCount: 3)
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
    sharedTag[outside].structure = marked.structure
    #expect(NativeTextPanels.ordered(elements(sharedTag), panels: [panel], body: 10,
        rightToLeft: false).allSatisfy { $0.nativePanel == nil })
    let mirrored = lines.map { row in var line = row; line.rect.origin.x = 612 - row.rect.maxX; return line }
    let mirroredPanel = CGRect(x: 612-panel.maxX,y: panel.minY,width: panel.width,height: panel.height)
    let rightToLeft = NativeTextPanels.ordered(elements(mirrored), panels: [mirroredPanel], body: 10, rightToLeft: true)
    #expect(rightToLeft.compactMap(\.nativePanel).count == 1)
    #expect(rightToLeft.compactMap(\.nativePanel).flatMap { $0 }.map(\.text) == members.map(\.text))
}
