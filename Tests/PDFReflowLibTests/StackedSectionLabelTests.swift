import Foundation
import Testing
@testable import PDFReflowLib

@Test func stackedMagazineLabelStillNeedsRecurringStyleAndIndentedProse() throws {
    let fixture = try SourceLayoutFixture.load("usda-magazine-17")
    var page = fixture.content()
    page.lines = page.lines.map { line in
        guard let attributed = fixture.attributedLines.first(where: { $0.text == line.text }) else { return line }
        return TextLine(content: NativeTextReader.inlineText(from: attributed.attributedString()),
                        rect: line.rect, fontSize: line.fontSize)
    }
    let groups = StackedSectionLabels.groups(in: page.lines, body: 10.5)
    let title = try #require(groups.first { $0.line.text == "How Much Pressure Can a Leaf Take?" })
    #expect(title.indices == [59, 60])
    let style = LayoutReconstructor.LabelStyle(title.line, body: 10.5)
    func labels(_ lines: [TextLine], styles: Set<LayoutReconstructor.LabelStyle>) -> [TextLine] {
        LayoutReconstructor.sectionLabels(in: lines, body: 10.5, headingThreshold: 13,
                                           page: page, styles: styles)
    }
    #expect(title.indices.allSatisfy { labels(page.lines, styles: [style]).contains(page.lines[$0]) })
    #expect(labels(page.lines, styles: []).isEmpty)
    var unindented = page.lines
    unindented[61].rect.origin.x = unindented[62].rect.minX
    #expect(!labels(unindented, styles: [style]).contains(unindented[59]))
    var differentWeight = page.lines
    differentWeight[60] = TextLine(text: page.lines[60].text, rect: page.lines[60].rect, fontSize: 9)
    #expect(StackedSectionLabels.groups(in: differentWeight, body: 10.5).isEmpty)
    var distant = page.lines
    distant[60].rect.origin.y -= 10
    #expect(StackedSectionLabels.groups(in: distant, body: 10.5).isEmpty)
    var recognized = page
    recognized.recognized = true
    #expect(LayoutReconstructor.sectionLabels(in: recognized.lines, body: 10.5, headingThreshold: 13,
                                              page: recognized, styles: [style]).isEmpty)
}
