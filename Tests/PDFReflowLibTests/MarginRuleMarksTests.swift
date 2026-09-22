import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

/// Project Blue Book's page 7, in the geometry PDFKit reports for it: the crop box, the rule the
/// page draws down its left margin as the inherited recognition read it, and the lines beside it.
/// Every number below was measured from
/// `corpus/cache/CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf`; see
/// `measurements/margin-rule-read-as-letters/record.md`.
private let blueBookCrop = CGRect(x: 1.44, y: 1.2, width: 610.56, height: 785.52)

/// A line of type: `count` characters laid across `x`, each standing `height` tall on `baseline`.
/// The page's own characters run 4.6 to 4.9 points tall, which is what makes a 20.8-point mark a
/// rule rather than a letter.
private func glyphs(_ count: Int, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> [CGRect] {
    guard count > 0 else { return [] }
    let width = (x.upperBound - x.lowerBound) / CGFloat(count)
    return (0..<count).map {
        CGRect(x: x.lowerBound + width * CGFloat($0), y: y.lowerBound,
               width: width, height: y.upperBound - y.lowerBound)
    }
}

/// One segment of the rule the page draws down its left margin, as the recognition set it.
private func mark(y: ClosedRange<CGFloat>) -> CGRect {
    CGRect(x: 10.1, y: y.lowerBound, width: 9.3, height: y.upperBound - y.lowerBound)
}

/// The four rule segments that stand alone on page 7, above and below the list of illustrations.
private func ruleOnlyLines() -> [(text: String, boxes: [CGRect], rect: CGRect)] {
    [(760.8...781.6, CGRect(x: 9.6, y: 752.9, width: 10.5, height: 31.5)),
     (725.0...744.6, CGRect(x: 9.9, y: 717.6, width: 9.8, height: 29.6)),
     (331.9...352.8, CGRect(x: 9.6, y: 324.0, width: 10.5, height: 31.5)),
     (295.9...316.6, CGRect(x: 9.4, y: 288.1, width: 10.4, height: 31.2))]
        .map { (text: "I", boxes: [mark(y: $0.0)], rect: $0.1) }
}

/// Page 7 as PDFKit reads it: the four standing segments, the entry `Figure 38 …of the`, the wrap
/// the rule merged a mark into, the next entry with its own mark, and the page number that shares
/// that entry's printed row and takes the mark's height from it.
private func blueBookPageSeven() -> (texts: [String], boxes: [[CGRect]], rects: [CGRect]) {
    var lines = ruleOnlyLines()
    lines.append((text: "Figure 38 Comparison of Evaluation of Object Sightings in the Strategic Areas of the",
                  boxes: glyphs(83, x: 79.7...406.6, y: 657.04...663.37),
                  rect: CGRect(x: 79.6, y: 656.8, width: 327.2, height: 7.0)))
    lines.append((text: "I South Farwest Region . 54",
                  boxes: [mark(y: 653.77...674.61), CGRect(x: 20.97, y: 653.77, width: 107.4, height: 0)]
                      + glyphs(25, x: 128.35...537.5, y: 649.57...654.45),
                  rect: CGRect(x: 10.8, y: 645.9, width: 527.0, height: 31.5)))
    lines.append((text: "I Figure 39 Diagram of a Celestial Sphere.",
                  boxes: [mark(y: 618.2...639.1), CGRect(x: 20.9, y: 618.2, width: 58.8, height: 0)]
                      + glyphs(39, x: 79.7...242.4, y: 631.1...637.4),
                  rect: CGRect(x: 11.1, y: 610.4, width: 231.2, height: 31.5)))
    lines.append((text: "56", boxes: glyphs(2, x: 530.1...537.3, y: 632.6...637.9),
                  rect: CGRect(x: 529.8, y: 610.4, width: 7.7, height: 31.5)))
    return (lines.map(\.text), lines.map(\.boxes), lines.map(\.rect))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func blueBookMarginRuleIsCutFromTheLineItWasMergedInto() throws {
    let page = blueBookPageSeven()
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    // The wrap: the mark and the space that carries the mark's size are cut, and the line is
    // measured by the type that remains.
    let wrap = try #require(readings[5])
    #expect(wrap.leading == 2)
    #expect(wrap.trailing == 0)
    #expect(abs(wrap.rect.minY - 649.57) < 0.01)
    #expect(abs(wrap.rect.maxY - 654.45) < 0.01)
    #expect(abs(wrap.rect.minX - 128.35) < 0.01)
    #expect(MarginRuleMarks.cut(wrap, from: nil, text: page.texts[5]).text == "South Farwest Region . 54")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aWrapNoLongerSortsAboveTheEntryItContinues() throws {
    let page = blueBookPageSeven()
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    // As read, the wrap's box stands a whole type size above the entry's; corrected, beneath it.
    #expect(page.rects[5].midY > page.rects[4].midY)
    let entry = readings[4]?.rect ?? page.rects[4]
    let wrap = try #require(readings[5]).rect
    #expect(wrap.maxY < entry.minY)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aLineThatOnlyTheRuleDrewCarriesNoText() throws {
    let page = blueBookPageSeven()
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    for line in 0..<4 { #expect(readings[line]?.rect.isNull == true) }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aPageNumberTakesBackTheHeightTheRuleGaveItsRow() throws {
    let page = blueBookPageSeven()
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    // PDFKit gives every piece of a printed row the tallest piece's height, so the page number
    // beside an entry the rule reached is reported 31.5 points tall as well.
    let number = try #require(readings[7])
    #expect(number.leading == 0 && number.trailing == 0)
    #expect(abs(number.rect.minY - 632.6) < 0.01)
    #expect(abs(number.rect.height - 5.3) < 0.01)
    // The entry it belongs to keeps its own row, which is what puts them back together.
    let entry = try #require(readings[6]).rect
    #expect(TextLine.sameRow(entry, number.rect))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func theEntryTheRuleDidNotReachKeepsTheBoxItWasRead() throws {
    let page = blueBookPageSeven()
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings[4] == nil)
}

// MARK: - Positive controls

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aLineGenuinelyThatTallKeepsItsBox() throws {
    var page = blueBookPageSeven()
    // A 31.5-point display line standing where the page numbers do: its own characters are that
    // tall, so nothing about its box is the rule's.
    page.texts.append("VII")
    page.boxes.append(glyphs(3, x: 500.0...537.3, y: 610.4...641.9))
    page.rects.append(CGRect(x: 500.0, y: 610.4, width: 37.3, height: 31.5))
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings[8] == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func threeMarksAreNotARule() throws {
    var page = blueBookPageSeven()
    // The four standing segments go, leaving the page's only marks the two the entries carry and
    // one of its own: three marks in a column are a recognition's stray, not a rule.
    page.texts.removeFirst(3); page.boxes.removeFirst(3); page.rects.removeFirst(3)
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aTallNarrowLetterInsideTheMeasureIsNotARule() throws {
    var page = blueBookPageSeven()
    for line in 0..<4 {
        page.boxes[line] = [page.boxes[line][0].offsetBy(dx: 260, dy: 0)]
        page.rects[line] = page.rects[line].offsetBy(dx: 260, dy: 0)
    }
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aLetterWithAShapeOfItsOwnIsNotARule() throws {
    var page = blueBookPageSeven()
    for line in 0..<4 { page.texts[line] = "T" }
    page.texts[5] = "T South Farwest Region . 54"
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aWideMarkIsNotARule() throws {
    var page = blueBookPageSeven()
    for line in 0..<4 {
        page.boxes[line] = [CGRect(x: 10.1, y: page.boxes[line][0].minY, width: 16, height: 20.8)]
    }
    page.boxes[5][0] = CGRect(x: 10.1, y: 653.77, width: 16, height: 20.84)
    page.boxes[6][0] = CGRect(x: 10.1, y: 618.2, width: 16, height: 20.9)
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aMarkInsideALineLeavesThatLineAlone() throws {
    var page = blueBookPageSeven()
    // The same geometry, with the mark read one character in: nothing stands between a margin and
    // the type beside it, so this line is not the rule's and is left exactly as it was read.
    page.texts[5] = ".I South Farwest Region . 54"
    page.boxes[5].insert(CGRect(x: 9.0, y: 649.6, width: 1, height: 1), at: 0)
    let readings = MarginRuleMarks.read(texts: page.texts, boxes: page.boxes, rects: page.rects,
                                        bounds: blueBookCrop)
    #expect(readings[5] == nil)
    #expect(readings[6]?.leading == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aPageWithNoRuleIsNotEvenMeasured() throws {
    let texts = ["Figure 38 Comparison of Evaluation", "of Object Sightings", "54", "I"]
    let rects = [CGRect(x: 79.6, y: 656.8, width: 327.2, height: 7.0),
                 CGRect(x: 128.3, y: 645.9, width: 200, height: 7.0),
                 CGRect(x: 529.8, y: 645.9, width: 7.7, height: 7.0),
                 CGRect(x: 9.6, y: 600.0, width: 10.5, height: 31.5)]
    #expect(!MarginRuleMarks.suspected(texts: texts, rects: rects, bounds: blueBookCrop))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aPageThatDrawsARuleIsMeasured() throws {
    let page = blueBookPageSeven()
    #expect(MarginRuleMarks.suspected(texts: page.texts.map { $0 }, rects: page.rects,
                                      bounds: blueBookCrop))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aCutIsRefusedWhereTheTextIsNoLongerWhatWasRead() throws {
    let reading = MarginRuleMarks.Reading(leading: 2, trailing: 0,
                                          rect: CGRect(x: 128.35, y: 649.57, width: 409, height: 4.88))
    let styled = NSAttributedString(string: "South Farwest Region . 54")
    let result = MarginRuleMarks.cut(reading, from: styled, text: "I South Farwest Region . 54")
    #expect(result.text == "I South Farwest Region . 54")
    #expect(result.styled?.string == "South Farwest Region . 54")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/264"))
func aCutCarriesTheStyledTextWithIt() throws {
    let reading = MarginRuleMarks.Reading(leading: 2, trailing: 0,
                                          rect: CGRect(x: 128.35, y: 649.57, width: 409, height: 4.88))
    let styled = NSMutableAttributedString(string: "I South Farwest Region . 54")
    styled.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 2, length: 5))
    let result = MarginRuleMarks.cut(reading, from: styled, text: styled.string)
    #expect(result.text == "South Farwest Region . 54")
    #expect(result.styled?.string == "South Farwest Region . 54")
    #expect(result.styled?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1)
}
