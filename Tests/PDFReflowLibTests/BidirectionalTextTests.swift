import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import PDFReflowLib

// Right-to-left paragraphs with embedded left-to-right runs (#41). The measured case is USCIS
// M-618-A, *Welcome to the United States* in Arabic: page 21 (printed 15) sets a paragraph about
// the permanent resident card with a form number, a telephone number, two web addresses and four
// parentheticals in it, and page 5 sets its contents with dot leaders. The rectangles and strings
// below are that book's own, read from its text layer; see
// measurements/right-to-left-runs-and-rows/record.md.

private func arabicLine(_ text: String, x: Double, y: Double, width: Double) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 15), fontSize: 12)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func reversedFormAndTelephoneNumbersAreRestoredToTheOrderTheWritingStates() {
    func ordered(_ text: String) -> String { ArabicText.logicalOrder(text, onRightToLeftPage: true) }
    // Page 21's four identifiers and its telephone number, as the reading hands them back.
    #expect(ordered("551-I) كإثبات لوضعهم القانوني") == "I-551) كإثبات لوضعهم القانوني")
    #expect(ordered("قيمة استمارة 485-I، وطلب تسجيل") == "قيمة استمارة I-485، وطلب تسجيل")
    #expect(ordered("تقديم الاستمارة 90-I. يمكنك") == "تقديم الاستمارة I-90. يمكنك")
    #expect(ordered("على رقم 3676-870-800-1. إذا") == "على رقم 1-800-870-3676. إذا")
    // A chain of words carries no number, so the page and the reading resolve its separators the
    // same way and nothing is touched: both of page 21's web addresses come back as they were.
    #expect(ordered("على الرابط www.uscis.gov أو الاتصال") == "على الرابط www.uscis.gov أو الاتصال")
    #expect(ordered("www.uscis.gov/uscis-elis. يرجى ملاحظة") == "www.uscis.gov/uscis-elis. يرجى ملاحظة")
    // Neither is a bracketed English term, or a number standing on its own.
    #expect(ordered("الأميركية [USCIS Forms Line] على") == "الأميركية [USCIS Forms Line] على")
    #expect(ordered("انظر الصفحة 19 للتعرف على") == "انظر الصفحة 19 للتعرف على")
    // Controls. A page written in the Latin alphabet, or in Chinese, is never reordered at all,
    // however its own identifiers and brackets are punctuated.
    #expect(ArabicText.logicalOrder("Form 551-I) issued 2015-09", onRightToLeftPage: false)
            == "Form 551-I) issued 2015-09")
    #expect(ArabicText.logicalOrder("提交表格 1040-SR 的特定", onRightToLeftPage: false) == "提交表格 1040-SR 的特定")
    #expect(!ArabicText.readsRightToLeft("提交表格 1040-SR 的特定"))
    #expect(!ArabicText.readsRightToLeft("Form I-551 and the Green Card"))
    // A page is judged from all of its lines together, so an English term that outweighs the
    // Arabic on one line of it says nothing about the page.
    #expect(!ArabicText.readsRightToLeft("الأميركية [USCIS Forms Line]"))
    #expect(ArabicText.readsRightToLeft(["الأميركية [USCIS Forms Line] على رقم 1-800-870-3676.",
                                         "بطاقة الإقامة الدائمة الخاصة بك، يتعين عليك تعبئة الاستمارة I-90"]))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func aLineWithNoRightToLeftLetterIsReadInTheOrderTheWritingStates() {
    // Page 21 closes a paragraph with `(USCIS).` on a line of its own. The page paints the stop
    // first and mirrors both brackets, and the reading, which finds no right-to-left letter to
    // take its base direction from, hands the characters back in that painted order.
    #expect(ArabicText.readsVisualOrder(".)USCIS("))
    #expect(ArabicText.logicalOrder(".)USCIS(", onRightToLeftPage: true) == "(USCIS).")
    // A line the page really did set left to right closes what it opens, and is left alone.
    #expect(!ArabicText.readsVisualOrder("[Permanent Resident Card]"))
    #expect(ArabicText.logicalOrder("[Permanent Resident Card]", onRightToLeftPage: true)
            == "[Permanent Resident Card]")
    #expect(ArabicText.logicalOrder("www.uscis.gov", onRightToLeftPage: true) == "www.uscis.gov")
    // Control: the same characters in a Latin book, where `b)` opens a list and `(` follows it.
    #expect(ArabicText.logicalOrder(".)USCIS(", onRightToLeftPage: false) == ".)USCIS(")
    #expect(ArabicText.logicalOrder("b) see (USCIS", onRightToLeftPage: false) == "b) see (USCIS")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func reorderingARunKeepsTheAttributesOfEveryCharacter() {
    let styled = NSMutableAttributedString(string: "م 551-I")
    let marker = NSAttributedString.Key("test.marker")
    styled.addAttribute(marker, value: "number", range: NSRange(location: 2, length: 3))
    styled.addAttribute(marker, value: "letter", range: NSRange(location: 6, length: 1))
    let ordered = ArabicText.logicalOrder(styled, onRightToLeftPage: true)
    #expect(ordered.string == "م I-551")
    #expect(ordered.attribute(marker, at: 2, effectiveRange: nil) as? String == "letter")
    #expect(ordered.attribute(marker, at: 3, effectiveRange: nil) == nil)
    #expect(ordered.attribute(marker, at: 4, effectiveRange: nil) as? String == "number")
    #expect(ordered.attribute(marker, at: 6, effectiveRange: nil) as? String == "number")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func anArabicLetterRaisedByItsOwnShapingIsNotAnInlineSuperscript() throws {
    func styled(_ pieces: [(String, Double)]) -> NSAttributedString {
        let value = NSMutableAttributedString()
        for (text, offset) in pieces {
            value.append(NSAttributedString(string: text, attributes: [
                .font: pdfKitGated { PlatformFont(name: "Helvetica", size: 12) }!,
                NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
            ]))
        }
        return value
    }
    // Page 21 raises the `ا` of `إذا` by 2.34 points on a twelve-point body, and the `ف` of
    // `للتعرف` by 1.52; both were written `<sup>` in the middle of their own words.
    let arabic = NativeTextReader.inlineText(from: styled([("القانون إذ", 0), ("ا", 2.34), (" طُلب منك ذلك", 0)]))
    #expect(!EPUBTextEncoder.inline(arabic).contains("<sup>"))
    #expect(arabic.text == "القانون إذا طُلب منك ذلك")
    // Control: a Latin exponent raised by the same evidence is still a superscript, and so is a
    // digit raised inside right-to-left text, which is how such text marks a note.
    let latin = NativeTextReader.inlineText(from: styled([("ax", 0), ("2", 2.34), (" + bx", 0)]))
    #expect(EPUBTextEncoder.inline(latin).contains("ax<sup>2</sup>"))
    let note = NativeTextReader.inlineText(from: styled([("الصفحة", 0), ("2", 2.34)]))
    #expect(EPUBTextEncoder.inline(note).contains("<sup>2</sup>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func aPrintedRowIsReadFromItsRightHandPieceAndJoinsWithoutASpace() {
    // Page 21's rows at y 578 and y 563: the extractor splits the second at the full stop, and
    // the reader takes the right-hand piece first.
    let opening = arabicLine("يتم إصدار بطاقة إقامة دائمة صالحة [Permanent Resident Card] للمقيمين الدائمين (استمارة",
                             x: 177, y: 578, width: 366)
    let right = arabicLine("I-551) كإثبات لوضعهم القانوني في الولايات المتحدة", x: 343, y: 563, width: 200)
    let left = arabicLine(". ويطلق بعض الأشخاص على هذه البطاقة", x: 184, y: 563, width: 158)
    let next = arabicLine("اسم “غرين كارد” [Green Card] أو البطاقة الخضراء.", x: 189, y: 548, width: 354)
    let page = PageContent(number: 21, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: [opening, left, right, next], graphics: [])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.count == 1)
    let text = blocks.map(\.text).joined()
    #expect(text.contains("الدائمين (استمارة I-551) كإثبات"))
    // The left-hand piece carries the stop that ends the sentence and the page's own space after
    // it, so the join adds none of its own.
    #expect(text.contains("الولايات المتحدة. ويطلق"))
    #expect(!text.contains("المتحدة . ويطلق"))
    #expect(text.contains("هذه البطاقة اسم “غرين كارد”"))
    // Control: the same four rectangles carrying Latin text read the other way round, and the
    // pieces of the split row join with a space as they always have.
    let latin = [
        TextLine(text: "A valid permanent resident card is issued to permanent residents (form",
                 rect: opening.rect, fontSize: 12),
        TextLine(text: "as proof of their status.", rect: left.rect, fontSize: 12),
        TextLine(text: "I-551)", rect: right.rect, fontSize: 12),
        TextLine(text: "Some people call this card a green card.", rect: next.rect, fontSize: 12),
    ]
    let latinBlocks = LayoutReconstructor.blocks(
        page: PageContent(number: 21, bounds: page.bounds, lines: latin, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(latinBlocks.map(\.text).joined().contains("as proof of their status. I-551)"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func aParagraphsLinesStandOnTheRightEdgeOfItsMeasure() {
    // Page 21 sets ten wrapped lines of one paragraph whose right edges stand within a point of
    // 543 and whose left edges are spread over 92 points. The column test that joins them has to
    // measure the edge the writing starts at, or every wrap opens a paragraph of its own.
    let measured: [(String, Double, Double)] = [
        ("وتم قبولك كمقيم دائم، فيتعين عليك سداد رسوم الهجرة في دائرة خدمات الجنسية", 177, 533),
        ("والهجرة الأميركية. ستقوم بسداد هذه الرسوم على الإنترنت من خلال نظام الهجرة", 196, 518),
        ("الإلكتروني في دائرة خدمات الجنسية والهجرة الأميركية (USCIS ELIS) على الرابط", 269, 503),
        ("التالي: www.uscis.gov/uscis-elis. يرجى ملاحظة أنك لن تحصل على بطاقة الإقامة", 285, 488),
    ]
    let lines = measured.map { text, x, y in arabicLine(text, x: x, y: y, width: 543 - x) }
    var warnings: [ConversionWarning] = []
    let page = PageContent(number: 21, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: lines, graphics: [])
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.count == 1)
    #expect(blocks[0].text.contains("(USCIS ELIS) على الرابط التالي: www.uscis.gov/uscis-elis."))
    // Control: Latin lines on the same four rectangles are read by their left edges, which stand
    // 19, 73 and 16 points apart, so the first two open paragraphs of their own and only the last
    // pair joins — exactly as they did before this rule existed.
    let latin = lines.enumerated().map { index, line in
        TextLine(text: "A paragraph line number \(index) of ordinary English prose.",
                 rect: line.rect, fontSize: 12)
    }
    let latinBlocks = LayoutReconstructor.blocks(
        page: PageContent(number: 21, bounds: page.bounds, lines: latin, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(latinBlocks.count == 3)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func contentsEntriesAreReadFromTheirTitlesAndKeepTheirOwnRows() {
    // Page 5's contents. The row at y 540 arrives as two pieces, its title on the right and its
    // leaders and page number on the left, and the run of entries is a table's rows only if the
    // column of page numbers is read at the end each row actually ends at.
    let leaders = String(repeating: ". ", count: 20)
    let entries = [
        arabicLine("حول هذا الدليل" + leaders + "7", x: 179, y: 556, width: 370),
        arabicLine("أين تتلقى المساعدة", x: 470, y: 540, width: 68),
        arabicLine(leaders + "8", x: 179, y: 540, width: 291),
        arabicLine("مصادر دائرة خدمات الجنسية والهجرة الأميركية (USCIS) على الإنترنت" + leaders + "10",
                   x: 179, y: 523, width: 359),
    ]
    let rows = TableRegionDetector.rowBlocks(in: entries, body: 12, rightToLeft: true)
    #expect(rows.count == 1)
    #expect(entries.allSatisfy { line in rows.contains { $0.insetBy(dx: -1, dy: -1).contains(line.rect) } })
    // The same run read left to right ends two of its three rows on a title rather than a page
    // number, which states no column, and the entries fall back to prose.
    #expect(TableRegionDetector.rowBlocks(in: entries, body: 12).isEmpty)
    // Each entry keeps its own block, and the title is read out before its own leaders and page
    // number. The split row opens at the block's edge although the piece that carries its title
    // begins 291 points in, because it is the printed row that is judged and not the piece.
    let page = PageContent(number: 5, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: entries, graphics: [])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.count == 3)
    #expect(blocks.map { $0.text.prefix(6) } == ["حول هذا", "أين تتل", "مصادر د"].map { $0.prefix(6) })
    #expect(blocks[1].text.hasSuffix("8"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/41"))
func aRightToLeftBlockStatesItsOwnBaseDirection() throws {
    func markup(_ text: String) throws -> String {
        try EPUBTextEncoder.piece(for: ReflowBlock(content: .paragraph(InlineText(text)), page: 1),
                                  imagePaths: [:]).markup
    }
    #expect(try markup("بطاقة الإقامة الدائمة (USCIS).").hasPrefix("<p dir=\"rtl\">"))
    // Controls: an English paragraph, and a Chinese one, state nothing.
    #expect(try markup("A valid permanent resident card.").hasPrefix("<p>"))
    #expect(try markup("提交表格 1040-SR 的特定").hasPrefix("<p>"))
    let heading = try EPUBTextEncoder.piece(
        for: ReflowBlock(content: .heading(id: "h", text: InlineText("جدول المحتويات"), level: 2), page: 5),
        imagePaths: [:]).markup
    #expect(heading == "<h2 id=\"h\" dir=\"rtl\">جدول المحتويات</h2>\n")
}
