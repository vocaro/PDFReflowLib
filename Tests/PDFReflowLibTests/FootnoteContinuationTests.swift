import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The rest of a bulleted item carries no marker of its own, because the marker is on the line
// above it. The page states the relationship in the indent it hangs under, and a line that hangs
// there is not a heading whatever size its text reaches (#256).

private let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)

/// IRS Publication 596's page 27, to the point: an EIC table whose rows are set at 5.69 points,
/// and beneath it the starred footnote band at 8, which is above the page's heading threshold of
/// 7.11. The star that says the band is notes is on the first of the footnote's two lines; the
/// second hangs 12 points in from it, one and a half of its own sizes, where the star's width
/// leaves the text.
private func footnotePage(continuation: TextLine) -> PageContent {
    var lines = (0..<12).map { i in
        TextLine(text: "2,700 2,750 208 927 1,090 1,226 5,500 5,550 423 1,879 2,210 2,486",
                 rect: CGRect(x: 63.5, y: 150 + Double(i) * 7, width: 250, height: 9.62), fontSize: 5.69)
    }
    lines.append(TextLine(text: "★ 如果您的报税身份是已婚分别申报，并且您有资格申报 EIC，请使用此栏。",
                          rect: CGRect(x: 54, y: 109.90, width: 277.94, height: 11.84), fontSize: 8))
    lines.append(TextLine(text: "* 如果您要从工作表中查找的金额至少为 19,100 美元, 但低于 19,104 美元，并且您没有任何持有效的 SSN 的合资格子女，则您",
                          rect: CGRect(x: 42, y: 97.90, width: 523.06, height: 11.84), fontSize: 8))
    lines.append(continuation)
    return PageContent(number: 27, bounds: bounds, lines: lines, graphics: [])
}

private let continuationText =
    "如果您要从工作表中查找的金额不低于 19,104 美元，并且您没有任何持有效的 SSN 的合资格子女，则您不能享受抵免。"

private func continuationLine(x: Double = 54, y: Double = 85.90, size: Double = 8) -> TextLine {
    TextLine(text: continuationText, rect: CGRect(x: x, y: y, width: 422.80, height: size * 1.48),
             fontSize: size)
}

private func blocks(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/256"))
func aFootnoteContinuationHangingUnderItsStarIsNotAHeading() {
    let result = blocks(footnotePage(continuation: continuationLine()))
    // The page really does put this band above its heading threshold, which is what the defect
    // was made of: the ★ legend beside the notes is 8-point text over a 5.69-point table, and it
    // is read as a heading here. This reduction of the page carries none of the table's column
    // headers, so nothing on it keys anything to that star; the whole page is read in
    // `KeyedNoteMarkTests`, where the two stars the headers print take the reading away (#259).
    #expect(headingTexts(result).contains { $0.hasPrefix("★") }, "\(headingTexts(result))")
    // What leaves the navigation is the note's own second line.
    #expect(!headingTexts(result).contains { $0.contains("不低于 19,104 美元") },
            "\(headingTexts(result))")
    // The page's own words are unchanged: the line is still in the book, as text.
    #expect(result.contains { $0.text.contains("不低于 19,104 美元") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/256"))
func aShortHeadingAtTheFootOfAPageIsStillAHeading() {
    // The positive control the rule has to survive: the same band, but the last line stands on
    // the column's own left edge rather than inside the star's hanging indent. A page that sets a
    // section title beneath a list has not made it part of the list.
    let heading = TextLine(text: "如何获取税务帮助",
                           rect: CGRect(x: 42, y: 85.90, width: 100, height: 11.84), fontSize: 8)
    #expect(headingTexts(blocks(footnotePage(continuation: heading))).contains("如何获取税务帮助"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/256"))
func onlyTheHangingIndentUnderALongMarkedLineTakesTheHeadingReading() {
    let marked = TextLine(text: "* 如果您要从工作表中查找的金额至少为 19,100 美元",
                          rect: CGRect(x: 42, y: 97.90, width: 523.06, height: 11.84), fontSize: 8)
    let line = continuationLine()
    #expect(LayoutReconstructor.hangsUnderBullet(line, in: [marked, line]))

    // A line standing on the marked line's own left edge opens something of its own, and one set
    // further in than the marker's width leaves is something else again — a sub-item, a quotation.
    #expect(!LayoutReconstructor.hangsUnderBullet(continuationLine(x: 42), in: [marked, line]))
    #expect(!LayoutReconstructor.hangsUnderBullet(continuationLine(x: 90), in: [marked, line]))
    // A measure further down the page is a block of its own, not a wrap.
    #expect(!LayoutReconstructor.hangsUnderBullet(continuationLine(y: 60), in: [marked, line]))
    // Another size is another thing: a title set over a list is not its last item.
    #expect(!LayoutReconstructor.hangsUnderBullet(continuationLine(size: 11), in: [marked, line]))
    // A short bulleted item above an indented one is two items. A line that wrapped is a line
    // that ran out of room, so the marked line must fill a measure — twelve of its own sizes.
    let short = TextLine(text: "* 短项目", rect: CGRect(x: 42, y: 97.90, width: 60, height: 11.84),
                         fontSize: 8)
    #expect(!LayoutReconstructor.hangsUnderBullet(line, in: [short, line]))
    // A line carrying a marker of its own is the next item, whatever it hangs under.
    let next = TextLine(text: "* 另一条脚注", rect: CGRect(x: 54, y: 85.90, width: 422.80, height: 11.84),
                        fontSize: 8)
    #expect(!LayoutReconstructor.hangsUnderBullet(next, in: [marked, next]))
    // Nothing hangs under a line the page never marked.
    let plain = TextLine(text: "如果您要从工作表中查找的金额至少为 19,100 美元",
                         rect: CGRect(x: 42, y: 97.90, width: 523.06, height: 11.84), fontSize: 8)
    #expect(!LayoutReconstructor.hangsUnderBullet(line, in: [plain, line]))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/256"))
func aHeadingBeneathAListOnAnOrdinaryPageKeepsItsReading() {
    // A Latin page whose list is followed, at the ordinary leading, by a title set larger: the
    // size evidence is the heading's own and no indent says otherwise.
    var lines = (0..<6).map { i in
        TextLine(text: "This is ordinary body prose establishing the page body size for the test.",
                 rect: CGRect(x: 54, y: 600 - Double(i) * 14, width: 400, height: 12), fontSize: 10)
    }
    lines.append(TextLine(text: "• an item long enough to fill the measure this column sets, and then to wrap",
                          rect: CGRect(x: 54, y: 200, width: 400, height: 16), fontSize: 14))
    lines.append(TextLine(text: "Recommendations",
                          rect: CGRect(x: 68, y: 182, width: 120, height: 16), fontSize: 14))
    let page = PageContent(number: 1, bounds: bounds, lines: lines, graphics: [])
    // Set inside the item's hanging indent, at its size and leading, it reads as the rest of it.
    #expect(!headingTexts(blocks(page)).contains("Recommendations"))
    // Moved out to the column's left edge, it is the heading the page drew.
    var moved = page
    moved.lines[moved.lines.count - 1].rect.origin.x = 54
    #expect(headingTexts(blocks(moved)).contains("Recommendations"))
}
