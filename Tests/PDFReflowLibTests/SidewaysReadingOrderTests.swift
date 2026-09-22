import CoreGraphics
import Testing
@testable import PDFReflowLib

// A line the page letters sideways is ordered and joined along its own direction (#263). #130
// took the *size* of such a line off the quadrilateral Vision draws around it and left the order:
// every rule downstream still read the line's axis-aligned rectangle as though the writing ran
// along it. The geometry here is CDC `Preparedness 101: Zombie Pandemic`, physical page 17
// (392.15 x 613.2 points), captured with `tools/probes/capture-ocr-layout-fixture.swift`; none of
// it is converter output.

/// One recognized line, in the normalized lower-left coordinates Vision reads an image in.
private func recognized(_ text: String, box: CGRect, across: CGVector) -> OCRReader.Recognition.Line {
    OCRReader.Recognition.Line(text: text, box: box, wraps: nil, across: across)
}

/// The three lines of page 17's caption, in the page's own points, with the turn and the wrap the
/// reading states for each. The page letters them down the right-hand side of the panel: all
/// three reach the same top edge, and each stands a little to the left of the one before it.
private enum CDCPage17 {
    static let bounds = CGRect(x: 0, y: 0, width: 392.15, height: 613.2)
    static let body: CGFloat = 9

    static let first = line("SEVERAL DAYS LATER AT THE CENTERS FOR",
                            x: 355.11, y: 24.27, width: 8.94, height: 224.84, wraps: false)
    static let second = line("DISEASE CONTROL AND PREVENTION IN",
                             x: 342.33, y: 47.27, width: 10.22, height: 201.85, wraps: true)
    static let third = line("ATLANTA, GEORGIA...",
                            x: 332.11, y: 143.08, width: 8.94, height: 106.03, wraps: false)
    static let all = [first, second, third]

    /// The same three rectangles carried by upright lines: the reading the library made before,
    /// and the control for every claim below.
    static var asUpright: [TextLine] { all.map { TextLine(text: $0.text, rect: $0.rect, fontSize: $0.fontSize,
                                                          wraps: $0.wraps, turn: .upright) } }

    private static func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                             wraps: Bool) -> TextLine {
        // The type size is the thickness #130 measures: the box's width, because the page turned
        // the line a quarter clockwise.
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height),
                 fontSize: width, wraps: wraps, turn: .clockwise)
    }
}

private func order(_ lines: [TextLine], body: CGFloat = CDCPage17.body) -> [String] {
    LayoutReconstructor.ordered(lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) },
                                bodySize: body).map { $0.line?.text ?? "«picture»" }
}

private func assembled(_ lines: [TextLine], body: CGFloat = CDCPage17.body) -> [String] {
    var assembler = BlockAssembler(page: 17, body: body, hyphens: HyphenContext())
    for line in lines { assembler.append(line, as: .prose) }
    return assembler.finish().map(\.text)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/263"))
func theTurnIsReadOffTheSameOffsetTheTypeSizeIs() {
    // The offset runs from the foot of the line's quadrilateral to its head, so it points the way
    // the tops of the letters face. Page 17's caption faces right: the page turned it clockwise
    // and its writing runs down the page.
    let caption = recognized("SEVERAL DAYS LATER AT THE CENTERS FOR",
                             box: CGRect(x: 0.9055, y: 0.0396, width: 0.0228, height: 0.3667),
                             across: CGVector(dx: 0.0228, dy: 0))
    #expect(OCRReader.turn(of: caption, in: CDCPage17.bounds) == .clockwise)

    // A spine or a tall table's column head faces left: the page turned it counterclockwise and
    // its writing runs up.
    let spine = recognized("A TITLE DOWN THE SPINE",
                           box: CGRect(x: 0.05, y: 0.2, width: 0.0228, height: 0.5),
                           across: CGVector(dx: -0.0228, dy: 0))
    #expect(OCRReader.turn(of: spine, in: CDCPage17.bounds) == .counterclockwise)

    // Upright is upright, and half a right angle of skew is still upright — the same boundary the
    // type size is measured at (#130), so no page of ordinary writing is turned. A reading that
    // carries no quadrilateral, which is what a hand-made line in a test supplies, is upright too.
    for across in [CGVector(dx: 0, dy: 0.0125), CGVector(dx: 0.0002, dy: 0.0125),
                   CGVector(dx: -0.0002, dy: 0.0125), CGVector.zero] {
        let line = recognized("MEANWHILE BACK AT TODD AND JULIE'S.",
                              box: CGRect(x: 0.035, y: 0.952, width: 0.329, height: 0.0125), across: across)
        #expect(OCRReader.turn(of: line, in: CDCPage17.bounds) == .upright)
    }
    // The page is not square, so the offset is placed on the page before its direction is read:
    // 0.02 of a 392-point width is 7.8 points and 0.02 of a 613-point height is 12.3.
    #expect(OCRReader.turn(of: recognized("x", box: .zero, across: CGVector(dx: 0.02, dy: 0.02)),
                           in: CDCPage17.bounds) == .upright)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/263"))
func aTurnedRectangleStandsUprightAndAnUprightOneIsUntouched() {
    // The caption's first line runs down the page from y 249.11 to y 24.27, 8.94 points thick.
    // Turned upright it is 224.84 long and 8.94 tall, and it starts where the writing starts.
    let upright = QuarterTurn.clockwise.upright(CDCPage17.first.rect)
    #expect(upright.width == CDCPage17.first.rect.height)
    #expect(upright.height == CDCPage17.first.rect.width)
    // All three lines reach the same top edge on the page, to a hundredth of a point, which is
    // the one left edge they stand on once the page is turned — what a paragraph's lines share
    // and what the column test reads.
    #expect(CDCPage17.all.allSatisfy { abs(QuarterTurn.clockwise.upright($0.rect).minX - upright.minX) < 0.02 })
    // And the first line is the topmost, which the page's own rectangles said it was not.
    #expect(CDCPage17.all.map { QuarterTurn.clockwise.upright($0.rect).midY }.sorted(by: >)
        == CDCPage17.all.map { QuarterTurn.clockwise.upright($0.rect).midY })

    // A turn is a rotation, so it is exact and it is its own inverse twice over; an upright line
    // keeps its rectangle to the bit.
    let sample = CGRect(x: 12.5, y: -3.25, width: 100.125, height: 9.5)
    #expect(QuarterTurn.upright.upright(sample) == sample)
    #expect(QuarterTurn.counterclockwise.upright(QuarterTurn.clockwise.upright(sample)) == sample)
    #expect(CDCPage17.asUpright.allSatisfy { $0.uprightRect == $0.rect })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/263"))
func aSidewaysCaptionIsReadInTheOrderThePageLettersIt() {
    // Read as though the writing ran along the rectangles, the shortest line is the topmost and
    // comes first: `ATLANTA, GEORGIA...` was the page's opening block.
    #expect(order(CDCPage17.asUpright) == [CDCPage17.third.text, CDCPage17.second.text, CDCPage17.first.text])
    // Read along its own direction it is the caption the page letters.
    #expect(order(CDCPage17.all) == [CDCPage17.first.text, CDCPage17.second.text, CDCPage17.third.text])

    // The page is turned for a group, once the cuts have isolated it: a column of upright prose
    // printed beside the caption keeps the page's own reading, and the caption past the gutter
    // still keeps its own.
    let column = (0..<3).map {
        TextLine(text: "upright \($0)", rect: CGRect(x: 40, y: 220 - CGFloat($0) * 12, width: 180, height: 9),
                 fontSize: 9)
    }
    #expect(order(column + CDCPage17.all)
        == column.map(\.text) + [CDCPage17.first.text, CDCPage17.second.text, CDCPage17.third.text])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/263"))
func aSidewaysCaptionIsJoinedAlongItsOwnDirection() {
    // The three lines overlap across the page by more than half their height and stand 1.4 and
    // 2.5 points apart, inside the three quarters of a body a row's pieces may be apart, so two
    // of them were read as two pieces of one printed row and joined in the wrong order.
    #expect(assembled([CDCPage17.third, CDCPage17.second, CDCPage17.first].map {
        TextLine(text: $0.text, rect: $0.rect, fontSize: $0.fontSize, wraps: $0.wraps, turn: .upright)
    }) == [CDCPage17.third.text, CDCPage17.second.text + " " + CDCPage17.first.text])

    // Along the caption's own direction they stand one above the next and none of them shares a
    // row with another, so each joins the one beneath it exactly as far as the reading's own wrap
    // allows: Vision states no wrap after the first line and a wrap after the second.
    #expect(assembled(CDCPage17.all)
        == [CDCPage17.first.text, CDCPage17.second.text + " " + CDCPage17.third.text])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/263"))
func onlyAGroupThatAgreesOnOneSidewaysTurnIsTurned() {
    // The page is turned for the group, not for the line. An upright line standing among the
    // caption — one no cut can separate from it — leaves the whole group on the page, ordered by
    // the page's own rectangles exactly as it was before this issue.
    let upright = TextLine(text: "A LABEL INSIDE THE PANEL",
                           rect: CGRect(x: 300, y: 120, width: 60, height: 9), fontSize: 9)
    let onThePage = order(CDCPage17.asUpright + [upright])
    #expect(order(CDCPage17.all + [upright]) == onThePage)
    #expect(onThePage.prefix(3) == [CDCPage17.third.text, CDCPage17.second.text, CDCPage17.first.text])

    // So do two opposite turns: the page said the lines run two ways, which is not one frame.
    var opposed = CDCPage17.third
    opposed.turn = .counterclockwise
    #expect(order([CDCPage17.first, CDCPage17.second, opposed])
        == [opposed.text, CDCPage17.second.text, CDCPage17.first.text])

    // A group's turn says nothing about a single line: there is no order to put one line in, and
    // nothing beside it to join it to.
    #expect(QuarterTurn.shared(by: [CDCPage17.first], turn: { $0.turn }) == nil)
    #expect(QuarterTurn.shared(by: CDCPage17.all, turn: { $0.turn }) == .clockwise)
    #expect(QuarterTurn.shared(by: CDCPage17.asUpright, turn: { $0.turn }) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/263"))
func anUprightPageIsOrderedAndJoinedExactlyAsItWas() {
    // The positive control: two columns of upright prose, cut at the gutter and read down each
    // column, and a wrapped paragraph joined on its left edge. Every line here carries the turn a
    // natively extracted line and a hand-made one carry, and none of the geometry moves.
    let left = (0..<4).map {
        TextLine(text: "left \($0)", rect: CGRect(x: 72, y: 700 - CGFloat($0) * 12, width: 180, height: 10),
                 fontSize: 10, wraps: true)
    }
    let right = (0..<4).map {
        TextLine(text: "right \($0)", rect: CGRect(x: 300, y: 700 - CGFloat($0) * 12, width: 180, height: 10),
                 fontSize: 10, wraps: true)
    }
    #expect(order(left + right, body: 10) == left.map(\.text) + right.map(\.text))
    #expect(assembled(left, body: 10) == ["left 0 left 1 left 2 left 3"])
    // Two pieces of one printed row still join, and a row's pieces are still told from a column's
    // gutter by the three quarters of a body between them.
    let opening = TextLine(text: "told", rect: CGRect(x: 72, y: 700, width: 20, height: 10), fontSize: 10)
    let rest = TextLine(text: "him", rect: CGRect(x: 97, y: 700, width: 20, height: 10), fontSize: 10)
    #expect(assembled([opening, rest], body: 10) == ["told him"])
    let across = TextLine(text: "him", rect: CGRect(x: 300, y: 700, width: 20, height: 10), fontSize: 10)
    #expect(assembled([opening, across], body: 10) == ["told", "him"])
}
