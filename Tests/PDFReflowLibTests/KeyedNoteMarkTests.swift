import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// A note keyed to a mark the page itself prints is a note, not a heading, whatever size it
// reaches. The evidence is the page's own: the same glyph standing by itself, higher up, in the
// material the note explains (#259).

private let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)

/// IRS Publication 596's page 24, to the point. The EIC table's rows are set at 5.69 points, so
/// the page's heading threshold is 7.11; the legend in the footnote band beneath it is set at 8
/// and clears the threshold on size alone. Twice in the table's column headers the page prints
/// `★` by itself at 6.5 points, and the legend explains those two stars.
private func legendPage(keyed: Bool = true, legend: TextLine) -> PageContent {
    var lines = (0..<12).map { i in
        TextLine(text: "2,700 2,750 208 927 1,090 1,226 5,500 5,550 423 1,879 2,210 2,486",
                 rect: CGRect(x: 63.5, y: 150 + Double(i) * 7, width: 250, height: 9.62), fontSize: 5.69)
    }
    if keyed {
        lines.append(TextLine(text: "★", rect: CGRect(x: 115.99, y: 596.22, width: 6.5, height: 9.62),
                              fontSize: 6.5))
        lines.append(TextLine(text: "★", rect: CGRect(x: 381.99, y: 596.22, width: 6.5, height: 9.62),
                              fontSize: 6.5))
    }
    lines.append(legend)
    return PageContent(number: 24, bounds: bounds, lines: lines, graphics: [])
}

private let legendText = "★ 如果您的报税身份是已婚分别申报，并且您有资格申报 EIC，请使用此栏。"

private func legendLine(_ text: String = legendText, width: Double = 277.94) -> TextLine {
    TextLine(text: text, rect: CGRect(x: 54, y: 79.90, width: width, height: 11.84), fontSize: 8)
}

private func blocks(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func aLegendKeyedToAStarThePagePrintsIsNotAHeading() {
    let result = blocks(legendPage(legend: legendLine()))
    #expect(!headingTexts(result).contains { $0.hasPrefix("★") }, "\(headingTexts(result))")
    // Only the heading reading goes. The legend is still in the book, as text.
    #expect(result.contains { $0.text.contains("请使用此栏") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func aStarredLineOnAPageThatKeysNothingToItKeepsItsReading() {
    // The same band with the table's two stars gone: nothing on the page says the glyph marks
    // anything, so the line is read by its size, as every heading is. This is the whole of the
    // difference between the two readings — the glyph is identical.
    let result = blocks(legendPage(keyed: false, legend: legendLine()))
    #expect(headingTexts(result).contains { $0.hasPrefix("★") }, "\(headingTexts(result))")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func aShortDecoratedHeadingBeneathABareStarKeepsItsReading() {
    // A page can print a star and then head a section with one. A heading is short; a note keyed
    // to a mark runs on, so the rule asks the marked line to have filled its measure.
    let result = blocks(legendPage(legend: legendLine("★ 详细示例", width: 60)))
    #expect(headingTexts(result).contains("★ 详细示例"), "\(headingTexts(result))")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func aMarkThePageOnlyPrintsBelowTheLineKeysNothingToIt() {
    // A note explains a mark the page has already made. A star printed under the line is not the
    // reference the line annotates.
    var page = legendPage(legend: legendLine())
    for index in page.lines.indices where page.lines[index].text == "★" {
        page.lines[index].rect.origin.y = 40
    }
    #expect(headingTexts(blocks(page)).contains { $0.hasPrefix("★") }, "\(headingTexts(blocks(page)))")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func aSectionSignHeadingInAnOpinionIsNotDemotedByTheSectionSignsAroundIt() {
    // Loper Bright cites `§ 706` and `5 U. S. C. § 706` throughout, and the Court's opinions head
    // sections with a section sign. The glyph is everywhere on such a page, but never standing by
    // itself as a reference, so nothing is keyed to it and the heading is read by its size.
    var lines = (0..<8).map { i in
        TextLine(text: "statutory scheme, and the reviewing court shall decide all relevant questions of law",
                 rect: CGRect(x: 54, y: 600 - Double(i) * 14, width: 400, height: 12), fontSize: 10)
    }
    lines.append(TextLine(text: "the Administrative Procedure Act, 5 U. S. C. § 706, directs courts to decide",
                          rect: CGRect(x: 54, y: 470, width: 400, height: 12), fontSize: 10))
    lines.append(TextLine(text: "§ 706 and the scope of review it prescribes for questions of statutory construction",
                          rect: CGRect(x: 54, y: 440, width: 400, height: 17), fontSize: 14))
    let page = PageContent(number: 20, bounds: bounds, lines: lines, graphics: [])
    #expect(headingTexts(blocks(page)).contains { $0.hasPrefix("§ 706") },
            "\(headingTexts(blocks(page)))")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func theRestOfAKeyedNoteHangingUnderItIsNotAHeadingEither() {
    // What #256 reads for a bulleted item, read for a note whose mark the page keys: the second
    // line carries no mark, and the page states the relationship in the indent it hangs under.
    let keys = [TextLine(text: "★", rect: CGRect(x: 115.99, y: 596.22, width: 6.5, height: 9.62),
                         fontSize: 6.5)]
    let legend = legendLine(width: 523.06)
    let rest = TextLine(text: "并且您有资格申报 EIC，请使用此栏，而不是本页其余各栏。",
                        rect: CGRect(x: 66, y: 67.90, width: 422.80, height: 11.84), fontSize: 8)
    #expect(LayoutReconstructor.hangsUnderBullet(rest, in: [legend, rest], keyedIn: keys + [legend, rest]))
    // Without the page's own star, the legend marks nothing and nothing hangs under it.
    #expect(!LayoutReconstructor.hangsUnderBullet(rest, in: [legend, rest], keyedIn: [legend, rest]))
    // A line carrying a keyed mark of its own is the next note, not the rest of this one.
    let next = legendLine("★ 另一条图例说明，长度足以填满本栏的行宽，并且继续到下一行。", width: 422.80)
    #expect(!LayoutReconstructor.hangsUnderBullet(next, in: [legend, next], keyedIn: keys + [legend, next]))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/259"))
func onlyASingleNonAlphanumericGlyphBeforeAMeasureOfTextOpensAMark() {
    // The shape `NativeTextReader.sizeAfterListMarker` already reads when it refuses to let an
    // opening glyph state the line's size.
    #expect(LayoutReconstructor.openingMark(legendText) == "★")
    #expect(LayoutReconstructor.openingMark("† Footnote text") == "†")
    #expect(LayoutReconstructor.openingMark("§ 706 and the scope of review") == "§")
    // A number or a letter opens a heading in many books, and `1. Introduction` is one of them.
    #expect(LayoutReconstructor.openingMark("1. Introduction") == nil)
    #expect(LayoutReconstructor.openingMark("A. Appendix") == nil)
    #expect(LayoutReconstructor.openingMark("如果您的报税身份是已婚分别申报") == nil)
    // A quotation mark runs straight into its sentence, and a glyph with nothing after it marks
    // nothing — that is the reference itself.
    #expect(LayoutReconstructor.openingMark("“I PLEDGE ALLEGIANCE") == nil)
    #expect(LayoutReconstructor.openingMark("★") == nil)
    #expect(LayoutReconstructor.openingMark("★ ") == nil)
}
