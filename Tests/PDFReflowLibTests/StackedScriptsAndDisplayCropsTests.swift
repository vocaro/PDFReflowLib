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

// #163. The IEEEtran paper (`ntrs-20190030725-dasc-2019`) sets its symbols with stacked indices in
// Computer Modern. PDFKit ends a line where a subscript moves back under its superscript, so each
// such symbol cut its sentence into up to twenty one-token paragraphs; its displays came out partly
// as crops and partly as text, with TeX's brace and bracket pieces as characters between them.
// Extraction rejoins the pieces (`NativeTextReader.joiningStackedScripts`) and measures scripts on
// the line's type; layout crops a display by its delimiters and by its equation number.
//
// Fixtures are native extraction from the checksum-pinned document, captured before these rules
// (`dasc-3` for #163); every expected phrase was read against the rendered source page.

private let dascSHA256 = "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa"

private func runs(_ values: [(String, Double, Double)]) -> NSAttributedString {
    let value = NSMutableAttributedString(string: "")
    for (text, size, offset) in values {
        value.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { ScriptFont(name: "Helvetica", size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
        ]))
    }
    return value
}

private func html(_ values: [(String, Double, Double)], lineType: Bool = true) -> String {
    EPUBTextEncoder.inline(NativeTextReader.inlineText(from: runs(values), measuresScriptsOnLineType: lineType))
}

/// A fixture page as extraction now hands it to layout: the captured lines, rejoined at their stacked
/// scripts against the page's painted bars.
private func sourcePage(_ page: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("dasc-\(page)")
    #expect(fixture.sourceSHA256 == dascSHA256)
    var content = fixture.styledContent()
    let bars = (fixture.paints ?? []).map { CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]) }
        .filter(NativeTextReader.isBar)
    content.lines = NativeTextReader.joiningStackedScripts(content.lines, rules: bars)
    return content
}

private func reflow(_ page: PageContent) -> (blocks: [ReflowBlock], crops: [CGRect]) {
    let crops = LayoutReconstructor.classifiedGraphics(page).map(\.rect)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
                                            vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    return (blocks, crops)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [InlineText] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text } else { nil } }
}

private func text(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { block in
        switch block.content {
        case let .paragraph(text), let .preformatted(text), let .footnote(text), let .heading(_, text, _): text.text
        case let .listItem(item): item.text.text
        default: nil
        }
    }
}

private func line(_ text: InlineText, _ rect: CGRect, _ size: CGFloat) -> TextLine {
    TextLine(content: text, rect: rect, fontSize: size)
}

private func styled(_ parts: [(String, TextStyle)]) -> InlineText {
    InlineText(elements: parts.map { .text($0.0, $0.1) })
}

// MARK: - Scripts measured on the line's type

@Test func stackedSuperscriptsAreMeasuredOnTheLinesType() {
    // Page 5's `STAⁿ` raises its 6.97-point `n` 5.42 points and the nested `i` 8.43: past three
    // quarters of their own sizes, within three quarters of the 9.96-point line's and of `n`'s.
    #expect(html([("Step 2. For each STA", 9.96, 0), ("n", 6.97, 5.42), ("i", 4.98, 8.43)]) == "Step 2. For each STA<sup>ni</sup>")
    // Page 6's `STA^{r_f(k)}`: `(k)` follows PDFKit's space after the script `f`, and continues it.
    #expect(html([("computed STA", 9.96, 0), ("r", 6.97, 5.46), ("f ", 4.98, 4.40), ("(k)", 6.97, 5.46)])
        == "computed STA<sup>rf (k)</sup>")
    // `(k),j` carries its own nested `k`: a carrier smaller than the line's type is a script, not a base.
    #expect(html([("window A", 9.96, 0), ("r", 6.97, 5.46), ("f ", 4.98, 4.40), ("(k),j", 6.97, 5.46), ("k", 4.98, 4.40)])
        == "window A<sup>rf (k),jk</sup>")
    // A script on another baseline than the script before it is a separate script, never merged into
    // it: Wallace page 178's `(a²)³` raises `2` 4.32 points and the outer `3` 7.44.
    #expect(html([("a", 12, 0), ("2 ", 8, 4.32), ("3 ", 8, 7.44), ("This means we have a", 12, 0), ("2 ", 8, 4.32),
                  ("three times", 12, 0)]) == "a<sup>2 </sup>3 This means we have a<sup>2 </sup>three times")
    #expect(html([("a", 12, 0), ("2", 8, 4.32), ("3", 8, 7.44)]) == "a<sup>2</sup>3")
    // A fraction's numerator stands a word space from the text before it, and keeps its reading.
    #expect(html([("describe slope as the fraction ", 12, 0), ("rise", 8, 6.24)]) == "describe slope as the fraction rise")
    // A line a fraction's bar crosses measures each script on its own size, as before.
    #expect(html([("the solution", 12, 0), ("x− 5", 8, 6.24)]) == "the solution<sup>x− 5</sup>")
    #expect(html([("the solution", 12, 0), ("x− 5", 8, 6.24)], lineType: false) == "the solutionx− 5")
}

@Test func aSelectionMeasuredFromItsScriptIsReadFromItsBase() {
    // Page 2's `f ni+1`: PDFKit measures the 9.96-point `n` 4.26 points down and `i+1` at zero.
    let pieces = NativeTextReader.inlineText(from: runs([("f ", 6.97, -7.08), ("n", 9.96, -4.26), ("i+1", 6.97, 0)]))
    #expect(pieces.elements.map { element -> TextStyle in
        if case let .text(_, style) = element { style } else { [] }
    } == [.subscript, [], .superscript])
    // Page 6's `ETA` carries a 9-point superscript of two words.
    #expect(html([("ETA", 9.96, -3.62), ("next node", 8.97, 0)]) == "ETA<sup>next node</sup>")
    // Controls: a run set before the larger one, and a run of words (the Fed's regulation letter).
    #expect(html([("V", 10, 0), ("SO", 11.5, -2)]) == "VSO")
    #expect(html([("F", 12, -2.744), ("Limitations on Interbank Liabilities ", 8, 0)]) == "FLimitations on Interbank Liabilities")
}

// MARK: - Pieces of a stacked script

@Test func aStackedScriptsPiecesRejoinTheirLine() {
    // Page 5's `Step 2. For each STA^{n^i_h}_h occurring …`: the base, the nested `h` PDFKit reads
    // alone, and the continuation that opens with the outer subscript.
    let base = line(styled([("Step 2. For each STA", []), ("ni", .superscript)]), CGRect(x: 312, y: 647.0, width: 95.6, height: 14.1), 9.96)
    let nested = line(InlineText("h"), CGRect(x: 404.9, y: 651.7, width: 4.1, height: 4.4), 4.98)
    let rest = line(styled([("h ", .subscript), ("occurring in the computed schedules", [])]),
                    CGRect(x: 400.0, y: 644.9, width: 163.0, height: 11.1), 6.97)
    let joined = NativeTextReader.joiningStackedScripts([base, nested, rest])
    #expect(joined.count == 1)
    #expect(joined.first?.text == "Step 2. For each STAnihh occurring in the computed schedules")
    #expect(joined.first.map { EPUBTextEncoder.inline($0.content) }
        == "Step 2. For each STA<sup>nih</sup><sub>h </sub>occurring in the computed schedules")
    #expect(joined.first?.fontSize == 9.96)
    // A bar across the stack makes it a fraction, which stays as it was.
    let bar = CGRect(x: 398, y: 651, width: 12, height: 4)
    #expect(NativeTextReader.joiningStackedScripts([base, nested, rest], rules: [bar]).count == 3)
    // Closing punctuation PDFKit cut after a script (page 5's `latter choice of Tk` and `.`).
    let tk = line(styled([("latter choice of T", []), ("k", .superscript)]), CGRect(x: 49, y: 544.9, width: 76.7, height: 10.6), 9.96)
    let period = line(InlineText("."), CGRect(x: 126.3, y: 544.9, width: 2.5, height: 8.9), 9.96)
    #expect(NativeTextReader.joiningStackedScripts([tk, period]).map(\.text) == ["latter choice of Tk."])
    // Controls: a raised note marker opening the next piece after plain text is `joinedRows`'
    // business; a line in the next column is no continuation; a body-size piece is no script.
    let prose = line(InlineText("that al-Qida was responsible for the Cole."), CGRect(x: 72, y: 500, width: 200, height: 10), 10)
    let marker = line(styled([("178", .superscript), (" In March 2001", [])]), CGRect(x: 272, y: 500, width: 80, height: 12), 6)
    #expect(NativeTextReader.joiningStackedScripts([prose, marker]).count == 2)
    let column = line(styled([("h ", .subscript), ("occurring", [])]), CGRect(x: 420, y: 644.9, width: 60, height: 11.1), 6.97)
    #expect(NativeTextReader.joiningStackedScripts([base, column]).count == 2)
    let body = line(InlineText("occurring in the computed schedules"), CGRect(x: 400, y: 644.9, width: 163, height: 11.1), 9.96)
    #expect(NativeTextReader.joiningStackedScripts([base, body]).count == 2)
}

@Test func sourceStackedIndicesKeepTheirSentences() throws {
    let two = paragraphs(reflow(try sourcePage(2)).blocks)
    for sentence in ["Estimated Times of Arrival: Each node nif in the route (1) of each flight f is supplied with an Estimated Time of Arrival (ETA): ETAniff , which is the nominal time.",
                     "A flight’s minimal and maximal times for traversing a link: For each flight f and each link nif ni+1f , we are given the minimal and maximal traversal times"] {
        #expect(two.contains { $0.text == sentence }, "\(sentence)")
    }
    #expect(two.contains { EPUBTextEncoder.inline($0).contains("time of arrival ETA<sup>n</sup><sub>f </sub>, which is the estimated time") })
    let five = paragraphs(reflow(try sourcePage(5)).blocks)
    #expect(five.contains { $0.text.hasPrefix("Step 2. For each STAnihh occurring in the computed schedules (6), i.e. for every flight h such that h<f and every node nih on the route of flight h") })
    #expect(five.contains { $0.text.hasSuffix("flight f can leave node nif some time within window Anif ,j1f and reach ni+1f") })
    #expect(five.contains { $0.text.contains("latter choice of Tk.") })
    // No piece of a stack is left as a paragraph of its own.
    for piece in ["h", "f", "ni", "i+1", "h−c", "."] {
        #expect(!five.contains { $0.text == piece }, "\(piece)")
    }
    // Control: the invariant's plain display stays the text it is.
    #expect(five.contains { $0.text == "S(1), S(2), ..., S(f−1) (6)" })
}

// MARK: - A display's undrawn delimiters

@Test func anUndrawnDelimiterLeavesTheProseLineAboveItsDisplay() {
    // Page 5: PDFKit counts display (8)'s left bracket, a `CMEX10` glyph with no character, in the
    // rectangle of `occurs on the route of f, compute the time window`, whose baseline is 613.36.
    let prose = TextLine(text: "occurs on the route of f, compute the time window",
                         rect: CGRect(x: 345.6, y: 597.8, width: 205.7, height: 22.5), fontSize: 9.96)
    let number = TextLine(content: styled([("f,h ", .subscript), (", (8)", [])]),
                          rect: CGRect(x: 499.5, y: 588.4, width: 63.5, height: 15.8), fontSize: 6.97)
    let opening = FontWeightReader.Show(origin: CGPoint(x: 345.63, y: 613.36), size: 9.96, font: 0, weight: .regular,
                                        text: "occurs", placed: true)
    let bracket = FontWeightReader.Show(origin: CGPoint(x: 388.23, y: 603.79), size: 9.96, font: 1, weight: .regular,
                                        text: nil, placed: true, mathExtension: true)
    let trimmed = NativeTextReader.trimmingUndrawnExtents([prose, number], shows: [opening, bracket])
    #expect(abs(trimmed[0].rect.minY - (613.36 - 9.96 * 0.3)) < 0.01)
    #expect(trimmed[0].rect.maxY == prose.rect.maxY)
    #expect(trimmed[1] == number)
    // Controls: no numbered display beneath, a delimiter the font names a character for, a glyph
    // outside the line's width, and a line whose own text is mathematics keep their rectangles.
    #expect(NativeTextReader.trimmingUndrawnExtents([prose], shows: [opening, bracket]) == [prose])
    var named = bracket
    named.text = "["
    #expect(NativeTextReader.trimmingUndrawnExtents([prose, number], shows: [opening, named])[0] == prose)
    var beyond = bracket
    beyond.origin.x = 560
    #expect(NativeTextReader.trimmingUndrawnExtents([prose, number], shows: [opening, beyond])[0] == prose)
    let terms = TextLine(text: "occurs on the route of f, compute the time window √",
                         rect: prose.rect, fontSize: 9.96)
    #expect(NativeTextReader.trimmingUndrawnExtents([terms, number], shows: [opening, bracket])[0] == terms)
    // TeX's maths extension fonts by name.
    #expect(FontWeightReader.isMathExtension(baseFont: "ABCDEF+CMEX10"))
    #expect(FontWeightReader.isMathExtension(baseFont: "LMMathExtension10-Regular"))
    #expect(!FontWeightReader.isMathExtension(baseFont: "CMMI10"))
}

// MARK: - Displays whole in their crops

@Test func delimiterColumnsAreTallPiecesAlone() {
    let brace = TextLine(text: "⎫ ⎪⎪⎪⎪⎬ ⎪⎪⎪⎪⎭", rect: CGRect(x: 507.1, y: 661.9, width: 8.9, height: 57.2), fontSize: 9.96)
    #expect(LayoutReconstructor.isDelimiterColumn(brace))
    #expect(LayoutReconstructor.isDelimiterColumn(TextLine(text: "⎫ ⎪⎪⎪⎪⎬ ⎪⎪⎪⎪⎭ (5)", rect: brace.rect, fontSize: 9.96)))
    // A short piece, a piece beside words, and a bracket of ordinary height are none.
    #expect(!LayoutReconstructor.isDelimiterColumn(TextLine(text: "⎫ ⎬", rect: brace.rect, fontSize: 9.96)))
    #expect(!LayoutReconstructor.isDelimiterColumn(TextLine(text: "⎛ ⎜⎝ STAni", rect: brace.rect, fontSize: 9.96)))
    #expect(!LayoutReconstructor.isDelimiterColumn(TextLine(text: "⎫⎪⎭", rect: CGRect(x: 0, y: 0, width: 8, height: 12), fontSize: 9.96)))
}

@Test func sourceCasesBracesKeepTheirDisplaysWhole() throws {
    let page = try sourcePage(3)
    let (blocks, crops) = reflow(page)
    // Displays (4) and (5): each one crop, holding its brace, terms, conditions, labels and number.
    for pieces in [["(4)", "at the first node", "in that order", "if n has been", "schedule-frozen"],
                   ["Bounds on travel time", "No passing on ni,ni+1 :", "is shared by the", "implies"]] {
        let held = pieces.map { phrase in page.lines.first { $0.text == phrase }?.rect }
        #expect(held.allSatisfy { $0 != nil }, "\(pieces)")
        #expect(crops.contains { crop in held.allSatisfy { $0.map { crop.intersects($0) } ?? false } }, "\(pieces)")
    }
    let reflowed = text(blocks).joined(separator: "\n")
    #expect(reflowed.unicodeScalars.allSatisfy { !LayoutReconstructor.delimiterPieces.contains($0) })
    for condition in ["at the first node", "if flights f1, f2", "consecutively,", "Bounds on travel time"] {
        #expect(!reflowed.contains(condition), "\(condition)")
    }
    // The prose around them stays text: the lines over and under each display.
    for prose in ["The formulas for these constraints are given in the corresponding parts of (4).",
                  "each of the nodes in the same order."] {
        #expect(reflowed.contains(prose), "\(prose)")
    }
}

@Test func sourceMatricesAndTheObjectiveAreCroppedWhole() throws {
    let (blocks, _) = reflow(try sourcePage(9))
    let reflowed = text(blocks)
    #expect(reflowed.joined().unicodeScalars.allSatisfy { !LayoutReconstructor.delimiterPieces.contains($0) })
    // No matrix row, vertical dot or row of the objective is left as text.
    for piece in [".", "1−1...", "−1 2−1...", "...−1 1", "2"] {
        #expect(!reflowed.contains(piece), "\(piece)")
    }
    #expect(!reflowed.contains { $0.hasPrefix("− 2 (sk−sk−1)") })
    // The sentences between the displays stay text, the one over display (12) whole.
    for prose in ["The problem of scheduling flight f can then be written as the Quadratic Program",
                  "The quadratic objective function is", "The quadratic part of this sum has the tridiagonal matricial",
                  "(there are no linear equality constraints), where"] {
        #expect(reflowed.contains(prose), "\(prose)")
    }
}

@Test func scriptDisplaysAreNumberedOrContinuedRows() {
    let measure = TextLine(text: "which is unavailable to flight f at that node because of the constraint",
                           rect: CGRect(x: 345.6, y: 660, width: 217.4, height: 8.9), fontSize: 9.96)
    func row(_ text: InlineText, x: CGFloat = 426.9) -> TextLine {
        TextLine(content: text, rect: CGRect(x: x, y: 693.4, width: 563.0 - x, height: 12), fontSize: 9.96)
    }
    // Page 5's display (7): terms with scripts and the equation number on the column's edge.
    let seven = row(styled([("−∞, ETA", []), ("n1f", .superscript), ("f", .subscript), (" , (7)", [])]))
    #expect(LayoutReconstructor.isScriptDisplay(seven, in: [measure, seven], body: 9.96))
    // The invariant (6) has no script and reads as text; a number short of the edge is no display's.
    let six = row(InlineText("S(1), S(2), ..., S(f−1) (6)"))
    #expect(!LayoutReconstructor.isScriptDisplay(six, in: [measure, six], body: 9.96))
    var short = seven
    short.rect.size.width -= 20
    #expect(!LayoutReconstructor.isScriptDisplay(short, in: [measure, short], body: 9.96))
    // Page 9's continued row of the objective carries a stacked index; Wallace's worked step does not.
    let continued = row(styled([("− 2 (s", []), ("k", .subscript), ("−s", []), ("k−1", .subscript), (") T", []),
                                ("nom", .superscript), ("k−1", .subscript), (" +", [])]), x: 356.5)
    #expect(LayoutReconstructor.isScriptDisplay(continued, in: [measure, continued], body: 9.96))
    let step = row(styled([("− 3x + 7 − 2x", []), ("2", .superscript), (" + 4x − 3", [])]), x: 356.5)
    #expect(!LayoutReconstructor.isScriptDisplay(step, in: [measure, step], body: 9.96))
}
