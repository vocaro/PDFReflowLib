import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

/// The pinned US Courts PDF has page-content rules and widget annotations. Deleting only each
/// page's `/Annots` entry leaves these recorded text and paint rectangles intact; the no-widget
/// derivative exposes the printed form evidence by itself (#211).
private func noWidgetFormEvidence(_ page: Int) throws -> (PageContent, [CGRect]) {
    let name = "uscourts-\(page)"
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == "9fe218570d311b0deab9413e39efda41210e60f2a5221eb360d43912ce05a118")
    let data = try Data(contentsOf: fixtureURL("\(name)-layout.json"))
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let paints = (json["paints"] as! [[String: Any]]).map { item -> CGRect in
        let rect = item["rect"] as! [Double]
        return CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
    }
    return (fixture.content(), paints)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func noWidgetPrintedFormKeepsCrossedTextAndLongWritingAreas() throws {
    let (first, firstPaints) = try noWidgetFormEvidence(1)
    let firstBlanks = FormBlank.printed(paints: firstPaints, lines: first.lines, pageBounds: first.bounds)
    for y in [452.26, 572.68] {
        #expect(firstBlanks.contains { abs($0.rule.minY - y) < 0.1 && $0.field.height > 35 })
    }

    let (third, thirdPaints) = try noWidgetFormEvidence(3)
    let thirdBlanks = FormBlank.printed(paints: thirdPaints, lines: third.lines, pageBounds: third.bounds)
    #expect(thirdBlanks.contains { abs($0.rule.minY - 412.48) < 0.1 && $0.field.height > 60 })
    let thirdRows = FormBlankRows.joined(third.lines, blanks: thirdBlanks).map(\.text)
    #expect(thirdRows.contains("State of (name) ____."))
    #expect(thirdRows.contains("under the laws of the State of (name) ____,"))

    let (fourth, fourthPaints) = try noWidgetFormEvidence(4)
    let fourthBlanks = FormBlank.printed(paints: fourthPaints, lines: fourth.lines, pageBounds: fourth.bounds)
    for y in [235.48, 426.88] {
        #expect(fourthBlanks.contains { abs($0.rule.minY - y) < 0.1 && $0.field.height > 60 })
    }
    let fourthRows = FormBlankRows.joined(fourth.lines, blanks: fourthBlanks).map(\.text)
    #expect(fourthRows.contains("principal place of business in the State of (name) ____."))
    #expect(fourthRows.contains("Or is incorporated under the laws of (foreign nation) ____,"))
    #expect(fourthRows.contains("and has its principal place of business in (name) ____."))

    // The relief area started on page 4 and its closing rule is the first content on page 5.
    // No widget or prompt appears above the rule on page 5 itself.
    let (fifth, fifthPaints) = try noWidgetFormEvidence(5)
    let fifthBlanks = FormBlank.printed(paints: fifthPaints, lines: fifth.lines, pageBounds: fifth.bounds)
    #expect(fifthBlanks.contains { abs($0.rule.minY - 643.72) < 0.1 && $0.field.height > 50 })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func noWidgetAnswerAreaNeedsFormRows() throws {
    let (form, paints) = try noWidgetFormEvidence(4)
    let answerRule = paints.first { abs($0.minY - 235.48) < 0.1 && $0.width > 500 }!
    #expect(FormBlank.printed(paints: [answerRule], lines: form.lines,
                              pageBounds: form.bounds).isEmpty)
    let noaa = try SourceLayoutFixture.load("noaa-701")
    #expect(FormBlank.printed(paints: noaa.paints.map(\.rect), lines: noaa.content().lines,
                              pageBounds: noaa.content().bounds).isEmpty)
    let warren = try SourceLayoutFixture.load("warren-30")
    #expect(FormBlank.printed(paints: warren.paints.map(\.rect), lines: warren.content().lines,
                              pageBounds: warren.content().bounds).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func noWidgetPDFKitJoinedPeriodNeedsEmptyRuleSelection() throws {
    let (_, paints) = try noWidgetFormEvidence(4)
    // PDFKit on the annotation-stripped source joins the right period to the left phrase.
    // The original pinned paint rectangles remain exactly the same as the source capture.
    let joined = TextLine(text: "principal place of business in the State of (name).",
        rect: CGRect(x: 182.87846, y: 638.90742, width: 391.24644, height: 12.15576), fontSize: 10.98)
    let rules = paints.filter { abs($0.minY - 633.64) < 0.1 }
    let blank = FormBlank.printed(paints: rules, lines: [joined], emptyRuleInterior: { _ in true })
    #expect(blank.count == 1)
    #expect(abs(try #require(blank.first).rule.width - 172.72) < 0.1)
    #expect(FormBlank.printed(paints: rules, lines: [joined], emptyRuleInterior: { _ in false }).isEmpty)
}
