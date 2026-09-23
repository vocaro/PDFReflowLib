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

// MARK: - Every measure a page takes of a sideways line (#276)

/// The same layout set sideways: each rectangle turned a quarter clockwise about the page's
/// origin and carried back onto the page, with every line carrying that turn.
///
/// `uprightRect` then gives back the rectangle the upright page had, moved by one page width in
/// x — and every rule here compares differences, so that move says nothing. This is the whole
/// claim #276 makes: a page turned is read the way the page is.
private func turnedClockwise(_ lines: [TextLine], pageWidth: CGFloat) -> [TextLine] {
    lines.map { line in
        let turned = QuarterTurn.counterclockwise.upright(line.rect)
        var sideways = line
        sideways.rect = CGRect(x: turned.minX, y: turned.minY + pageWidth,
                               width: turned.width, height: turned.height)
        sideways.turn = .clockwise
        return sideways
    }
}

/// The same rectangles carried by upright lines: the reading the library made before #263, and
/// the control for every claim below.
private func asUprightLines(_ lines: [TextLine]) -> [TextLine] {
    lines.map { var line = $0; line.turn = .upright; return line }
}

/// A page that exercises the measures #276 names: a stated leading, a list of entries the page
/// hangs its wraps under, and a title of two display lines stacked on one edge.
private enum HungList {
    static let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let body: CGFloat = 10
    static var lines: [TextLine] {
        var lines = [
            TextLine(text: "A List of the Illustrations", rect: CGRect(x: 60, y: 730, width: 180, height: 20),
                     fontSize: 20),
            TextLine(text: "Printed in This Report", rect: CGRect(x: 60, y: 706, width: 150, height: 20),
                     fontSize: 20),
        ]
        // A column of prose on one edge, stepping at fourteen points: what states the leading.
        var y: CGFloat = 660
        for index in 1...6 {
            lines.append(TextLine(text: "A line of the report's own prose, number \(index), filling its measure",
                                  rect: CGRect(x: 60, y: y, width: 300, height: 12), fontSize: 10))
            y -= 14
        }
        // Three entries, each filling its measure and wrapping onto a hung second line.
        y -= 28
        let entries = ["The first illustration the report prints, with a title long enough that it",
                       "The second illustration the report prints, whose title also runs past the",
                       "The third illustration the report prints, whose title runs past the measure"]
        let wraps = ["fills its measure and wraps", "measure it is set to", "in the same way"]
        for (entry, wrap) in zip(entries, wraps) {
            lines.append(TextLine(text: entry, rect: CGRect(x: 60, y: y, width: 300, height: 12), fontSize: 10))
            lines.append(TextLine(text: wrap, rect: CGRect(x: 95, y: y - 14, width: 160, height: 12), fontSize: 10))
            y -= 42
        }
        return lines
    }
}

/// Every group measure the page takes reads the frame its own writing runs in, so a page set
/// sideways states the same leading, the same ordinary line height, the same hung entries and the
/// same marker column as the page set upright (#276).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/276"))
func aPageSetSidewaysStatesWhatTheSamePageSetUprightStates() {
    let upright = HungList.lines
    let sideways = turnedClockwise(upright, pageWidth: HungList.bounds.width)
    // The page's own leading, which it states four times over.
    #expect(LayoutReconstructor.statedLeading(upright) == 14)
    #expect(LayoutReconstructor.statedLeading(sideways) == 14)
    // The ordinary line height at each size.
    #expect(LayoutReconstructor.ordinaryLineHeights(in: upright)
            == LayoutReconstructor.ordinaryLineHeights(in: sideways))
    // The entries the page hangs its wraps under: three, the same three.
    #expect(LayoutReconstructor.hangingEntries(in: upright, body: HungList.body).count == 3)
    #expect(LayoutReconstructor.hangingEntries(in: sideways, body: HungList.body).count == 3)
    // The title's two display lines stack, whichever way the page set them.
    #expect(LayoutReconstructor.stacksUnderHeading(upright[1], after: upright[0]))
    #expect(LayoutReconstructor.stacksUnderHeading(sideways[1], after: sideways[0]))
    // And the marker column of an entry: the edge it stands on and the margin its column reaches.
    let first = upright[2], turnedFirst = sideways[2]
    let column = LayoutReconstructor.markerColumn(of: first, in: upright, body: HungList.body)
    let turnedColumn = LayoutReconstructor.markerColumn(of: turnedFirst, in: sideways, body: HungList.body)
    #expect(column.onMajorityEdge == turnedColumn.onMajorityEdge)
    #expect(column.setsAList == turnedColumn.setsAList)
    #expect((column.justifiedRight == nil) == (turnedColumn.justifiedRight == nil))
}

/// The control. Carried by upright lines, the same sideways rectangles state none of it: the step
/// between two lines is measured across the writing, so the page states no leading at all, and
/// nothing is hung under anything (#276).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/276"))
func theSameRectanglesReadAsUprightStateNothing() {
    let sideways = turnedClockwise(HungList.lines, pageWidth: HungList.bounds.width)
    let flattened = asUprightLines(sideways)
    #expect(LayoutReconstructor.statedLeading(flattened) != 14)
    #expect(LayoutReconstructor.hangingEntries(in: flattened, body: HungList.body).isEmpty)
    #expect(!LayoutReconstructor.stacksUnderHeading(flattened[1], after: flattened[0]))
}

/// A table the page set sideways is a table: its rows step across the page, and `rowBlocks` reads
/// the run in the frame the writing runs in and hands back the page's own rectangles (#276).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/276"))
func aTableSetSidewaysIsReadAsATable() {
    // Four rows on one left edge, in one type size, stepping at one leading, each ending in a
    // figure on a column of figures — which is what states a column the page drew no rule for.
    var rows: [TextLine] = []
    var y: CGFloat = 700
    for index in 0..<4 {
        rows.append(TextLine(text: "Evaluation \(index)", rect: CGRect(x: 60, y: y, width: 70, height: 10),
                             fontSize: 10))
        rows.append(TextLine(text: "1\(index)", rect: CGRect(x: 150, y: y, width: 20, height: 10), fontSize: 10))
        rows.append(TextLine(text: "3\(index)", rect: CGRect(x: 220, y: y, width: 20, height: 10), fontSize: 10))
        y -= 14
    }
    let sideways = turnedClockwise(rows, pageWidth: 612)
    let upright = TableRegionDetector.rowBlocks(in: rows, body: 10)
    let turned = TableRegionDetector.rowBlocks(in: sideways, body: 10)
    #expect(!upright.isEmpty)
    #expect(turned.count == upright.count)
    // The region handed back is on the page, not in the turned frame: it covers the lines the
    // page actually set.
    let ink = sideways.dropFirst().reduce(sideways[0].rect) { $0.union($1.rect) }
    #expect(turned.allSatisfy { ink.insetBy(dx: -1, dy: -1).contains($0) })
    // The control: the same rectangles read as upright are twelve lines of one column, and state
    // no table at all.
    #expect(TableRegionDetector.rowBlocks(in: asUprightLines(sideways), body: 10).isEmpty)
}

/// The three measures the assembler takes of a pair of lines read the frame their own writing
/// runs in: a heading carrying on where the writing sets no space between the lines, an item
/// taking the rest of the word its page broke, and the rest of a printed row joining the piece
/// that opened it (#276, #263).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/276"))
func theAssemblerReadsASidewaysPageAsItReadsAnUprightOne() {
    func assembled(_ lines: [(TextLine, LineRole)]) -> [String] {
        var assembler = BlockAssembler(page: 1, body: 10, hyphens: HyphenContext(vocabulary: ["daylight"]))
        for (line, role) in lines { assembler.append(line, as: role) }
        return assembler.finish().map(\.text)
    }
    func turned(_ lines: [(TextLine, LineRole)]) -> [(TextLine, LineRole)] {
        zip(turnedClockwise(lines.map(\.0), pageWidth: 612), lines.map(\.1)).map { ($0, $1) }
    }
    // A heading the page sets in writing that puts no space between its lines, over two lines.
    let heading: [(TextLine, LineRole)] = [
        (TextLine(text: "\u{7B2C}\u{4E8C}\u{7AE0}\u{FF1A}\u{8CC7}\u{6599}\u{7684}",
                  rect: CGRect(x: 60, y: 700, width: 84, height: 14), fontSize: 14), .heading),
        (TextLine(text: "\u{6574}\u{7406}\u{8207}\u{5206}\u{6790}",
                  rect: CGRect(x: 60, y: 686, width: 70, height: 14), fontSize: 14), .heading),
    ]
    #expect(assembled(heading) == assembled(turned(heading)))
    #expect(assembled(heading).count == 1)
    #expect(assembled(asUprightLines(turned(heading).map(\.0)).map { ($0, LineRole.heading) }).count == 2)
    // An item the page broke mid-word, with the rest of the word on the line beneath it.
    let item: [(TextLine, LineRole)] = [
        (TextLine(text: "1. The report prints an item here that runs to the measure and then day-",
                  rect: CGRect(x: 60, y: 650, width: 300, height: 12), fontSize: 10), .listItem),
        (TextLine(text: "light carries it on beneath, which is the rest of the word.",
                  rect: CGRect(x: 60, y: 636, width: 250, height: 12), fontSize: 10), .prose),
    ]
    #expect(assembled(item) == assembled(turned(item)))
    #expect(assembled(item) == ["1. The report prints an item here that runs to the measure and then "
                                + "daylight carries it on beneath, which is the rest of the word."])
    #expect(assembled(asUprightLines(turned(item).map(\.0)).map { ($0, item[0].1) }).count == 2)
    // The rest of a printed row, standing along the writing from the piece that opened it.
    let row: [(TextLine, LineRole)] = [
        (TextLine(text: "Compass Locator", rect: CGRect(x: 60, y: 600, width: 90, height: 10),
                  fontSize: 10), .tableRow(continuation: false)),
        (TextLine(text: "Under 25", rect: CGRect(x: 170, y: 600, width: 50, height: 10),
                  fontSize: 10), .tableRow(continuation: false)),
    ]
    #expect(assembled(row) == assembled(turned(row)))
    #expect(assembled(row) == ["Compass Locator Under 25"])
}

/// A table's column headers are read across the writing, so the same header band is found on a
/// page set sideways and on the page set upright, and the rectangles handed back are the page's
/// own (#276, #257).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/276"))
func columnHeadersAreReadAcrossTheWriting() {
    let header = "Number Per Cent Number Per Cent Number Per Cent"
    var lines = [TextLine(text: "Evaluation", rect: CGRect(x: 60, y: 700, width: 60, height: 10), fontSize: 10),
                 TextLine(text: header, rect: CGRect(x: 150, y: 700, width: 200, height: 10), fontSize: 10)]
    var y: CGFloat = 686
    for index in 0..<3 {
        lines.append(TextLine(text: "Balloon \(index)", rect: CGRect(x: 60, y: y, width: 60, height: 10),
                              fontSize: 10))
        lines.append(TextLine(text: "1\(index) 2\(index) 3\(index)",
                              rect: CGRect(x: 150, y: y, width: 200, height: 10), fontSize: 10))
        y -= 14
    }
    func headers(_ page: [TextLine]) -> [CGRect] {
        TableRegionDetector.columnHeaders(
            in: PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                            lines: page, graphics: []), body: 10)
    }
    let sideways = turnedClockwise(lines, pageWidth: 612)
    #expect(headers(lines) == [lines[1].rect])
    #expect(headers(sideways) == [sideways[1].rect])
    // The control: read as upright, those rectangles state no column edge and no header.
    #expect(headers(asUprightLines(sideways)).isEmpty)
}
