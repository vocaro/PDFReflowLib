import Foundation
import Testing
@testable import PDFReflowLib

private let fedSummaryPages = [8, 14, 24, 50, 66, 88, 116]

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/214"), arguments: fedSummaryPages)
func fedOpenersKeepCompleteSummariesAsAsides(_ number: Int) throws {
    let fixture = try SourceLayoutFixture.load("fed-summary-\(number)")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    let page = fixture.content()
    let expected = page.lines.filter { $0.fontSize == 14 }.map(\.text).joined(separator: " ")
    let typography = PageTypography(page: page)
    let groups = DisplaySummary.groups(in: page.lines, body: typography.body,
                                      threshold: typography.headingThreshold)
    #expect(groups.count == 1)
    #expect(groups.first?.lines.map(\.text).joined(separator: " ") == expected)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let summaries = blocks.compactMap { block -> String? in
        if case let .aside(text) = block.content { return text.text }
        return nil
    }
    #expect(summaries == [expected])
    #expect(!headingTexts(blocks).contains { expected.contains($0) })
    #expect(!headingTexts(blocks).isEmpty)
    // The source's dotted contents remain outside the summary.
    #expect(paragraphTexts(blocks).contains { $0.contains("...") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/214"))
func displaySummaryNeedsTitleSentenceAndIsolatedContents() throws {
    let original = try SourceLayoutFixture.load("fed-summary-8").content()
    func found(_ lines: [TextLine]) -> Bool {
        !DisplaySummary.groups(in: lines, body: 10, threshold: 12.5).isEmpty
    }
    #expect(found(original.lines))
    #expect(!found(original.lines.filter { $0.fontSize <= 14 }))
    #expect(!found(original.lines.filter { !$0.text.contains("...") }))
    var plain = original.lines
    for i in plain.indices where plain[i].fontSize == 14 { plain[i].fontSize = 10 }
    #expect(!found(plain))
    var title = original.lines
    for i in title.indices where title[i].text == "system." {
        title[i] = TextLine(text: "System", rect: title[i].rect, fontSize: title[i].fontSize)
    }
    #expect(!found(title))
    var quote = original.lines
    let start = try #require(quote.firstIndex { $0.text.hasPrefix("The Federal Reserve performs") })
    quote[start] = TextLine(text: "“" + quote[start].text, rect: quote[start].rect, fontSize: quote[start].fontSize)
    #expect(!found(quote))
    var crowded = original.lines
    for i in crowded.indices where crowded[i].fontSize == 10 { crowded[i].rect.origin.y += 220 }
    #expect(!found(crowded))
    for synthetic in [false, true] {
        var page = original
        page.recognized = !synthetic
        page.hasSyntheticTextStyle = synthetic
        var warnings: [ConversionWarning] = []
        let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
        #expect(!blocks.contains { if case .aside = $0.content { true } else { false } })
    }
}
