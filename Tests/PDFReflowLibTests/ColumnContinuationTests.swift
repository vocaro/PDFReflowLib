import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func faaSafetyTeamParagraphContinuesPastItsFigure() throws {
    let fixture = try SourceLayoutFixture.load("faa-column-continuation")
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    let page = fixture.content()
    var warnings: [ConversionWarning] = []
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "figure-\($0.offset)") }
    let blocks = LayoutReconstructor.blocks(page: page, images: images,
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    let paragraph = try #require(blocks.firstIndex { $0.text.contains("The FAA Safety Team (FAASTeam) exemplifies this commitment.") })
    #expect(blocks[paragraph].text.contains("The FAA is dedicated"))
    let picture = try #require(blocks.firstIndex { if case .image = $0.content { true } else { false } })
    #expect(paragraph < picture)
    #expect(blocks.contains { $0.text.contains("Figure 1-13. Atlanta Flight Standards District Office") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func resumingAParagraphPreservesTheFigureCaptionAndStyles() throws {
    var assembler = BlockAssembler(page: 1, body: 10, hyphens: HyphenContext())
    assembler.append(TextLine(content: InlineText("The FAA", style: .bold), rect: CGRect(x: 40, y: 100, width: 100, height: 10), fontSize: 10), as: .prose)
    let suspended = assembler.suspendProse()
    let handle = try #require(suspended)
    assembler.appendImage("picture")
    assembler.append(TextLine(text: "Figure 1. Office.", rect: CGRect(x: 40, y: 20, width: 100, height: 8), fontSize: 8), as: .prose)
    let resumed = assembler.resumeProse(handle, with: TextLine(text: "Safety Team continues.", rect: CGRect(x: 200, y: 500, width: 100, height: 10), fontSize: 10))
    #expect(resumed)
    let blocks = assembler.finish()
    #expect(blocks.count == 3)
    #expect(blocks[0].text == "The FAA Safety Team continues.")
    #expect(blocks[2].text == "Figure 1. Office.")
    if case let .paragraph(text) = blocks[0].content {
        #expect(text.elements.contains { if case let .text(value, style) = $0 { value == "The FAA" && style.contains(.bold) } else { false } })
    } else { Issue.record("Expected a paragraph") }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/160"))
func onlyAnOpenProseColumnCanResumeAcrossItsFigure() {
    func line(_ text: String, x: CGFloat = 40, y: CGFloat, size: CGFloat = 10) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: 180, height: size)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: size))
    }
    let original = [line("A full line of ordinary prose", y: 286),
        line("A second full line of ordinary prose", y: 274),
        line("The sentence carries its last words", y: 262),
        LayoutReconstructor.Element(rect: CGRect(x: 40, y: 100, width: 180, height: 140), image: "figure"),
        line("Figure 1. A caption.", y: 80, size: 8),
        line("into the next column.", x: 240, y: 700),
        line("Another line follows the continuation", x: 240, y: 688),
        line("The column continues with more prose", x: 240, y: 676)]
    let roles: [LineRole?] = original.map { $0.line == nil ? nil : .prose }
    #expect(ColumnContinuation.pairs(original, roles: roles, body: 10) == [5: 2])
    var ended = original
    ended[2] = line("This sentence ended.", y: 262)
    #expect(ColumnContinuation.pairs(ended, roles: roles, body: 10).isEmpty)
    var headings = roles
    headings[5] = .heading
    #expect(ColumnContinuation.pairs(original, roles: headings, body: 10).isEmpty)
    var spanning = original
    spanning[3].rect.size.width = 380
    #expect(ColumnContinuation.pairs(spanning, roles: roles, body: 10).isEmpty)
    var sameColumn = original
    sameColumn[5] = line("A new paragraph beneath the figure", y: 50)
    #expect(ColumnContinuation.pairs(sameColumn, roles: roles, body: 10).isEmpty)
    var unrelated = original
    unrelated[4] = line("An intervening paragraph is a boundary", y: 80)
    #expect(ColumnContinuation.pairs(unrelated, roles: roles, body: 10).isEmpty)
}
