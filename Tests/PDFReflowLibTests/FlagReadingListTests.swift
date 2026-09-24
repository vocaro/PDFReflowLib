import Foundation
import Testing
@testable import PDFReflowLib

private let flag157SHA = "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8"

private func flag157Paragraphs(_ number: Int) throws -> [String] {
    let fixture = try SourceLayoutFixture.load("flag-\(number)")
    #expect(fixture.sourceSHA256 == flag157SHA)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: fixture.content(), images: [], vocabulary: [], warnings: &warnings)
        .compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/157"))
func ourFlagReadingListKeepsSameMarginEntriesSeparate() throws {
    let page53 = try flag157Paragraphs(53)
    #expect(page53.contains { $0.hasPrefix("Devine, Louise Lawrence.") && $0.hasSuffix("1968.") })
    #expect(page53.contains { $0.hasPrefix("Fradin, Dennis B.") && $0.hasSuffix("1988.") })
    #expect(page53.contains { $0.hasPrefix("Bennett, Mabel R. Old Glory:") && $0.hasSuffix("1970.") })

    let page54 = try flag157Paragraphs(54)
    #expect(page54.contains { $0.hasPrefix("Smith, Whitney.") && $0.hasSuffix("1975.") })
    #expect(page54.contains { $0.hasPrefix("The Star-Spangled Banner.-") && $0.hasSuffix("1975.") })
    #expect(page54.contains { $0.hasPrefix("Waller, Leslie.") && $0.hasSuffix("1960.") })
    #expect(page54.contains { $0.hasPrefix("Wannamaker, W.W.") && $0.hasSuffix("1971.") })
    #expect(page54.contains { $0.hasPrefix("Weil, Ann.") && $0.hasSuffix("1983.") })
    #expect(page54.contains { $0.hasPrefix("Werstein, Irving.") && $0.hasSuffix("1969.") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/157"))
func namesWithoutARepeatedDatedHangingListKeepTheirParagraphRules() throws {
    for name in ["911-14", "faa-5", "loper-64"] {
        let page = try SourceLayoutFixture.load(name).content()
        let evidence = LayoutReconstructor.bibliographyLines(in: page.lines,
            body: PageTypography(page: page).body)
        #expect(evidence.openings.isEmpty)
        #expect(evidence.wraps.isEmpty)
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/157"))
func ourFlagBeecherQuoteKeepsItsLastLineAndFollowingIntroductionSeparate() throws {
    let fixture = try SourceLayoutFixture.load("flag-12")
    #expect(fixture.sourceSHA256 == flag157SHA)
    var page = fixture.content()
    // PageReader's source tag probe finds one P group per quote line (61–67), while group 67
    // also owns the following Wilson introduction. Replay that contradiction on PDFKit's lines.
    let quote = ["“The stars upon it were like the bright morning stars of God,",
                 "and the stripes upon it were beams of morning light. As at early",
                 "dawn the stars shine forth even while it grows light, and then as",
                 "the sun advances that light breaks into banks and streaming lines",
                 "of color, the glowing red and intense white striving together, and",
                 "ribbing the horizon with bars effulgent, so, on the American flag,",
                 "stars and beams of many-colored light shine out together ....”"]
    for (order, text) in quote.enumerated() {
        let index = try #require(page.lines.firstIndex { $0.text == text })
        if order != 1 { // PDFKit's second quote line has no validated source tag.
            page.lines[index].structure = .init(group: 61 + order, order: 61 + order,
                                                headingLevel: 0, lineCount: order == 6 ? 2 : 1)
        }
    }
    let intro = try #require(page.lines.firstIndex {
        $0.text == "In a 1917 Flag Day message, President Wilson said:"
    })
    page.lines[intro].structure = .init(group: 67, order: 67, headingLevel: 0, lineCount: 2)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let text = blocks.compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
    #expect(text.contains {
        $0.hasPrefix("“The stars upon it") && $0.contains("on the American flag, stars and beams")
            && $0.hasSuffix("together ....”")
    })
    #expect(text.contains("In a 1917 Flag Day message, President Wilson said:"))
}
