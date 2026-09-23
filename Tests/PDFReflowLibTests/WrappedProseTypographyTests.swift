import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

@Test(arguments: [13, 46])
func wrappedProseKeepsItsBodySizeBesideRecoveredSmallText(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("fed-body-\(number)")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    #expect(fixture.page == number)
    // Exercise the typography after all source text has been released from decorative
    // crops. Neither the table cells nor footnotes are discarded to repair the estimate.
    var page = fixture.content()
    page.graphics = []; page.pictures = []
    let typography = PageTypography(page: page)
    #expect(typography.body == (number == 13 ? 7 : 8))
    #expect(typography.headingBody == 10)
    for line in page.lines where line.fontSize == 10 {
        #expect(LayoutReconstructor.role(of: line, on: page, in: page.lines, typography: typography,
                                         labels: [], judgesTitleWords: false) != .heading)
    }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [],
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    let opening = number == 13 ? "Despite the need for coordination" : "funds rate and other short-term"
    #expect(blocks.contains { block in
        if case .paragraph = block.content { return block.text.hasPrefix(opening) }
        return false
    })
    let small = number == 13 ? "capital surplus" : "reserve balance accounts"
    #expect(blocks.map(\.text).joined(separator: " ").contains(small))

    let title = TextLine(text: "Monetary Policy", rect: CGRect(x: 90, y: 725, width: 220, height: 17), fontSize: 14)
    let withTitle = PageTypography(pageLines: page.lines + [title], reflowableLines: page.lines + [title], documentBody: 10)
    #expect(LayoutReconstructor.role(of: title, on: page, in: page.lines + [title], typography: withTitle,
                                     labels: [], judgesTitleWords: false) == .heading)
}

@Test func wrappedProseFloorRequiresNativeParagraphEvidence() {
    let small = (0..<10).map { index in
        TextLine(text: "These smaller explanatory notes supply most of this page's text and remain readable.",
                 rect: CGRect(x: 30, y: 300 - index * 12, width: 300, height: 10), fontSize: 8)
    }
    let words = ["A larger paragraph begins with ordinary words here",
                 "and continues over several lines at one consistent",
                 "measure, with enough text to establish its own size",
                 "while the many smaller notes remain in the reading."]
    let larger = words.enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: 30, y: 600 - index * 16, width: 260, height: 12), fontSize: 10)
    }
    func threshold(_ lines: [TextLine], native: Bool = true) -> CGFloat {
        PageTypography(pageLines: small + lines, reflowableLines: small + lines, documentBody: nil,
                       nativeSizeEvidence: native).headingThreshold
    }
    #expect(threshold(larger) == 11)
    #expect(threshold(larger, native: false) == 10)
    #expect(threshold(Array(larger.prefix(3))) == 10)
    let bold = larger.map { TextLine(content: InlineText($0.text, style: .bold), rect: $0.rect, fontSize: $0.fontSize) }
    #expect(threshold(bold) == 10)
    var quoted = larger
    quoted[0] = TextLine(text: "“" + words[0], rect: larger[0].rect, fontSize: 10)
    #expect(threshold(quoted) == 10)
    var caption = larger
    caption[0] = TextLine(text: "Figure 1. " + words[0], rect: larger[0].rect, fontSize: 10)
    #expect(threshold(caption) == 10)
    var tagged = larger
    tagged[0].structure = TextStructure(group: 1, order: 1, headingLevel: 2, lineCount: 4)
    #expect(threshold(tagged) == 10)
    var rotated = larger
    for index in rotated.indices { rotated[index].turn = .clockwise }
    #expect(threshold(rotated) == 10)
}
