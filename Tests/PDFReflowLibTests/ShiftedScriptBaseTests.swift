import CoreGraphics
import CoreText
import Foundation
import Testing
#if os(macOS)
import AppKit
private typealias ScriptFont = NSFont
#else
import UIKit
private typealias ScriptFont = UIFont
#endif
@testable import PDFReflowLib

// #144. Wallace page 255 sets the denominator `6a²b` 7.8 points below the comment beside it, and
// PDFKit measures both from the comment's baseline, so `6a` and `b` read as subscripts and the
// exponent (−4.32) as one too. The Supreme Court's Symbol bullets (pages 86–87) are raised 1.02 points
// beside 10.98-point text and read as superscripts. The fixtures' Symbol bullets are decoded (#155).

private func line(_ runs: [(String, Double, Double)]) -> NSAttributedString {
    let value = NSMutableAttributedString(string: "")
    for (text, size, offset) in runs {
        value.append(NSAttributedString(string: text, attributes: [
            .font: ScriptFont(name: "Helvetica", size: size)!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
        ]))
    }
    return value
}

private func html(_ runs: [(String, Double, Double)]) -> String {
    EPUBTextEncoder.inline(NativeTextReader.inlineText(from: line(runs)))
}

private func sourceHTML(_ fixture: String, _ text: String) throws -> String {
    let source = try #require(try SourceLayoutFixture.load(fixture).attributedLines.first { $0.text == text })
    return EPUBTextEncoder.inline(NativeTextReader.inlineText(from: source.attributedString()))
}

@Test func exponentsBesideAShiftedBaseAreMeasuredFromIt() throws {
    #expect(try sourceHTML("algebra-255", "6a2b First identify LCD") == "6a<sup>2</sup>b First identify LCD")
    // Synthetic: a lowered denominator and a raised numerator, each with its exponent, beside a comment.
    #expect(html([("6a", 12, -7.8), ("2", 8, -4.32), ("b ", 12, -7.8), ("First identify LCD", 12, 0)])
        == "6a<sup>2</sup>b First identify LCD")
    #expect(html([("x", 10, 6.48), ("2", 7, 10.08), (" and more", 10, 0)]) == "x<sup>2</sup> and more")
    #expect(html([("y", 10, 5), ("2", 7, 3), ("− y", 10, 5), ("1", 7, 3), (" is the slope", 10, 0)])
        == "y<sub>2</sub>− y<sub>1</sub> is the slope")
    // FAA page 262's `KE = ½ × m × v` (−5.00) and its exponent (−1.67).
    #expect(html([("KE = ½ × m × v", 10, -5), ("2", 7, -1.67)]) == "KE = ½ × m × v<sup>2</sup>")
}

@Test func basesOnTheSelectionBaselineAndSeparatedRunsAreUnchanged() {
    // Bases on the selection's baseline: offsets as stated.
    #expect(html([("H", 12, 0), ("2", 8, -3), ("O and x", 12, 0), ("2", 8, 4)]) == "H<sub>2</sub>O and x<sup>2</sup>")
    #expect(html([("8x", 12, -2.16), ("3", 8, 2.16)]) == "8x<sup>3</sup>")
    // A smaller run on the selection's baseline beside a larger shifted one is not measured from it
    // (the Fed's letter and name, #138, here without the space).
    #expect(html([("F", 12, -2.744), ("Limitations on Interbank Liabilities ", 8, 0)]) == "FLimitations on Interbank Liabilities")
    // A space between the runs: no base, the stated offsets stand.
    #expect(html([("6a ", 12, -7.8), ("2", 8, -4.32), (" First identify LCD", 12, 0)])
        == "<sub>6a 2</sub> First identify LCD")
    // A run after the script on another baseline than the base does not resume it.
    #expect(html([("6a", 12, -7.8), ("2", 8, -4.32), ("b", 12, 3), (" First identify LCD", 12, 0)])
        == "6a<sup>2b</sup> First identify LCD")
    // A raised run and a smaller run raised again on the same side (the BaselineStyleTests pair is on
    // opposite sides): offsets as stated.
    #expect(html([("x", 12, 0), ("raised", 12, 4), ("low", 8, -3)]) == "x<sup>raised</sup><sub>low</sub>")
    // A nested index (DASC page 5's `STA` with `n` raised and `i` raised again, #163): the base is itself a
    // smaller script of the run before it, so the stated offsets stand.
    #expect(html([("STA", 10, 0), ("n", 7, 3), ("i", 5, 5.5), (" occurring", 10, 0)]) == "STA<sup>n</sup>i occurring")
    // A run of the same size is no script of the run before it.
    #expect(html([("6a", 12, -7.8), ("2", 12, -4.32), (" First identify LCD", 12, 0)]) == "<sub>6a2</sub> First identify LCD")
}

@Test func openingBulletsAreNeverScripts() throws {
    #expect(try sourceHTML("scotus-86", "• Under the Public Health Service Act, the Food and")
        == "• Under the Public Health Service Act, the Food and")
    #expect(html([("•", 7.98, 1.02), (" ", 7.98, 1.02), ("Under the Medicare program", 10.98, 0)]) == "• Under the Medicare program")
    #expect(html([(" ", 10.98, 0), ("▪", 7.98, -1.5), (" Item", 10.98, 0)]) == "▪ Item")
    // Controls: a raised note marker opening a line, a raised degree sign (Wallace's `29◦`), and a raised
    // bullet set against a word inside a line are still superscripts.
    #expect(html([("*", 7.98, 1.02), (" ", 7.98, 1.02), ("Note text", 10.98, 0)]) == "<sup>* </sup>Note text")
    #expect(html([("29", 12, 0), ("◦", 8, 4)]) == "29<sup>◦</sup>")
    #expect(html([("a", 10.98, 0), ("•", 7.98, 1.02), (" b", 10.98, 0)]) == "a<sup>•</sup> b")
}

@Test func aBulletStandingApartInsideALineIsNoScript() {
    // #186: a raised bullet a word space from the words on both sides separates them (the magazine's
    // back cover: a 6-point Monotype Sorts bullet raised one point between 11-point addresses). Until
    // #186 this was a control that stayed a superscript; nothing it is set against is its base.
    #expect(html([("a ", 10.98, 0), ("•", 7.98, 1.02), (" b", 10.98, 0)]) == "a • b")
    #expect(html([("ars.usda.gov/ar", 11, 0), (" ", 11, 0), ("●", 6, 1), (" ", 11, 0), ("Follow us", 11, 0)])
        == "ars.usda.gov/ar ● Follow us")
    // A bullet ending the line after a space stands apart too; one touching a word on either side does not.
    #expect(html([("a ", 10.98, 0), ("•", 7.98, 1.02)]) == "a •")
    #expect(html([("a ", 10.98, 0), ("•", 7.98, 1.02), ("b", 10.98, 0)]) == "a <sup>•</sup>b")
    // A raised letter standing apart is still a script: only bullets separate.
    #expect(html([("a ", 10.98, 0), ("l", 6, 1), (" b", 10.98, 0)]) == "a <sup>l</sup> b")
}

@Test func symbolBulletListsReflowAsListItems() throws {
    // NASA page 13: five Symbol bullets, three with a wrapped second line, read as five list items.
    let page = try SourceLayoutFixture.load("ntrs-13").styledContent()
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                            warnings: &warnings)
    let items = blocks.compactMap { block -> String? in
        if case let .preformatted(text) = block.content, text.text.hasPrefix("•") { text.text } else { nil }
    }
    #expect(items == [
        "• Peak bending moment due to lift, research model",
        "• Maximum resultant bending moment, research model",
        "• Normalized mean bending moment due to drag, proprietary model",
        "• Normalized peak bending moment due to lift, proprietary model",
        "• Normalized maximum resultant bending moment, proprietary model",
    ], "\(blocks.map(\.content))")
}
