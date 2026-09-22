import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The 9/11 report's physical page 50, in the geometry PDFKit reports for it: the running head, the
// three heading rows of the two flight timelines, and PDFKit's own rectangle for every character
// of them. Every number below was measured from `corpus/cache/GPO-911REPORT.pdf`; see
// `measurements/flight-label-row-cut-at-the-gutter/record.md`.

/// A character of the heading rows: its own box, as `PDFPage.characterBounds(at:)` gives it.
private func box(_ x: ClosedRange<CGFloat>, _ y: ClosedRange<CGFloat>) -> CGRect {
    CGRect(x: x.lowerBound, y: y.lowerBound,
           width: x.upperBound - x.lowerBound, height: y.upperBound - y.lowerBound)
}

/// A run of type laid evenly across `x` on one baseline, for the rows whose own characters the cut
/// never reads — only their rectangles decide anything.
private func glyphs(_ count: Int, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> [CGRect] {
    guard count > 0 else { return [] }
    let width = (x.upperBound - x.lowerBound) / CGFloat(count)
    return (0..<count).map {
        box((x.lowerBound + width * CGFloat($0))...(x.lowerBound + width * CGFloat($0 + 1)), y)
    }
}

/// `(AA 11)             (UA 175)`, the row PDFKit hands back as one line spanning the gutter, with
/// the box it gives each of the sixteen characters. The one space between the two cells runs
/// 78.02 to 196.39 — 118.37 points, against the 4.50 the same line sets between its own words.
private let mergedLabelText = "(AA 11) (UA 175)"
private let mergedLabelBoxes: [CGRect] = [
    box(40.40...43.46, 526.33...535.51), box(43.46...51.69, 528.50...535.51),
    box(51.69...59.78, 528.50...535.51), box(59.78...64.28, 528.50...528.50),
    box(64.28...68.97, 528.50...535.51), box(68.97...74.23, 528.50...535.51),
    box(74.23...78.02, 526.33...535.51), box(78.02...196.39, 528.50...528.50),
    box(196.39...199.43, 526.33...535.51), box(199.43...207.58, 528.35...535.34),
    box(207.58...215.17, 528.50...535.51), box(215.17...219.67, 528.50...528.50),
    box(219.67...224.18, 528.50...535.51), box(224.18...229.89, 528.33...535.34),
    box(229.89...235.15, 528.33...535.53), box(235.15...238.55, 526.33...535.51),
]

/// Page 50 as PDFKit reads its head: the running head, the two flight names read apart, the label
/// row merged across the gutter, and the two routes read apart.
private func flightHeadings(merged: String = mergedLabelText,
                            mergedBoxes: [CGRect] = mergedLabelBoxes)
    -> (texts: [String], boxes: [[CGRect]], rects: [CGRect]) {
    let lines: [(String, [CGRect], CGRect)] = [
        ("32 THE 9/11 COMMISSION REPORT", glyphs(29, x: 39.98...269.70, y: 564.75...571.14),
         CGRect(x: 39.66, y: 562.53, width: 230.34, height: 8.61)),
        ("American Airlines Flight 11 ", glyphs(28, x: 39.76...195.72, y: 539.75...547.11),
         CGRect(x: 39.66, y: 537.25, width: 136.12, height: 9.89)),
        ("United Airlines Flight 175", glyphs(26, x: 195.72...321.24, y: 539.58...547.11),
         CGRect(x: 195.67, y: 537.25, width: 126.35, height: 9.89)),
        (merged, mergedBoxes, CGRect(x: 39.66, y: 526.00, width: 199.63, height: 9.89)),
        ("Boston to Los Angeles ", glyphs(22, x: 39.87...195.87, y: 514.86...524.14),
         CGRect(x: 39.66, y: 514.92, width: 88.30, height: 9.21)),
        ("Boston to Los Angeles", glyphs(21, x: 195.87...283.76, y: 514.86...524.14),
         CGRect(x: 195.67, y: 514.92, width: 88.30, height: 9.21)),
    ]
    return (lines.map(\.0), lines.map(\.1), lines.map(\.2))
}

// MARK: - The row the page states two cells for

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func theFlightLabelRowIsCutAtTheEdgeItsNeighborsState() throws {
    let page = flightHeadings()
    #expect(ColumnGutterCut.suspected(texts: page.texts, rects: page.rects))
    let cuts = ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects)
    #expect(cuts.keys.sorted() == [3])
    let cut = try #require(cuts[3])
    let pieces = try #require(ColumnGutterCut.split(cut, from: nil, text: mergedLabelText))
    #expect(pieces.left.text == "(AA 11)")
    #expect(pieces.right.text == "(UA 175)")
    // PDFKit's own outer edges are kept, and only the inner one — the edge the merge got wrong —
    // is read from the characters.
    #expect(abs(cut.left.minX - 39.66) < 0.01)
    #expect(abs(cut.left.maxX - 78.02) < 0.01)
    #expect(abs(cut.right.minX - 196.39) < 0.01)
    #expect(abs(cut.right.maxX - 239.29) < 0.01)
    // The row is unchanged: each piece keeps the line's own baseline and height.
    #expect(cut.left.minY == cut.right.minY)
    #expect(abs(cut.left.height - 9.89) < 0.01)
}

/// Page 51 states the same shape at its own measure, with the two rows agreeing on 200.71 and
/// 200.69 rather than on one number.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func theSecondPageIsCutAlthoughItsNeighborsDisagreeByATwentiethOfAPoint() throws {
    let texts = ["American Airlines Flight 77 ", "United Airlines Flight 93", "(AA 77) (UA 93)",
                 "Washington, D.C., to Los Angeles ", "Newark to San Francisco"]
    let rects = [CGRect(x: 44.70, y: 537.25, width: 136.12, height: 9.89),
                 CGRect(x: 200.71, y: 537.25, width: 120.85, height: 9.89),
                 CGRect(x: 44.70, y: 526.00, width: 194.14, height: 9.89),
                 CGRect(x: 44.70, y: 514.92, width: 137.46, height: 9.21),
                 CGRect(x: 200.69, y: 514.92, width: 100.42, height: 9.21)]
    let merged: [CGRect] = [
        box(45.44...48.50, 526.33...535.51), box(48.50...56.73, 528.50...535.51),
        box(56.73...64.82, 528.50...535.51), box(64.82...68.94, 528.50...528.50),
        box(68.94...73.99, 528.33...535.34), box(73.99...79.44, 528.33...535.34),
        box(79.44...83.07, 526.33...535.51), box(83.07...201.44, 528.50...528.50),
        box(201.44...204.47, 526.33...535.51), box(204.47...212.63, 528.35...535.34),
        box(212.63...220.22, 528.50...535.51), box(220.22...224.38, 528.50...528.50),
        box(224.38...229.36, 528.33...535.34), box(229.36...234.65, 528.50...535.51),
        box(234.65...238.10, 526.33...535.51),
    ]
    let boxes = [glyphs(28, x: 44.80...200.76, y: 539.58...547.11),
                 glyphs(25, x: 200.76...320.68, y: 539.58...547.11), merged,
                 glyphs(33, x: 46.06...200.93, y: 514.86...524.14),
                 glyphs(23, x: 200.93...300.77, y: 514.86...524.14)]
    let cut = try #require(ColumnGutterCut.read(texts: texts, boxes: boxes, rects: rects)[2])
    let pieces = try #require(ColumnGutterCut.split(cut, from: nil, text: texts[2]))
    #expect(pieces.left.text == "(AA 77)")
    #expect(pieces.right.text == "(UA 93)")
}

/// The styled text follows the cut, so each piece keeps its own half of the line's runs, and a
/// repair that rewrote the line between the reading and the cut cuts nothing.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func eachPieceKeepsItsOwnStyledText() throws {
    let page = flightHeadings()
    let cut = try #require(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes,
                                                rects: page.rects)[3])
    let styled = NSMutableAttributedString(string: "(AA 11) ", attributes: [.obliqueness: 0.2])
    styled.append(NSAttributedString(string: "(UA 175)", attributes: [.obliqueness: 0.0]))
    let pieces = try #require(ColumnGutterCut.split(cut, from: styled, text: mergedLabelText))
    #expect(pieces.left.styled?.string == "(AA 11)")
    #expect(pieces.right.styled?.string == "(UA 175)")
    #expect(pieces.left.styled?.attribute(.obliqueness, at: 0, effectiveRange: nil) as? Double == 0.2)
    #expect(pieces.right.styled?.attribute(.obliqueness, at: 0, effectiveRange: nil) as? Double == 0.0)
    // A line a repair rewrote is no longer the line the boxes were read over.
    #expect(ColumnGutterCut.split(cut, from: nil, text: "(AA 11) and (UA 175)") == nil)
    #expect(ColumnGutterCut.split(cut, from: styled, text: mergedLabelText.lowercased()) == nil)
}

// MARK: - What refuses the cut

/// The control the fix exists for: a line the page genuinely sets across both columns. It has the
/// same shape — one piece in its row, between two rows of two — and it must keep its reading. What
/// separates it is the white: a spanning line puts its words *through* the gutter, so the space at
/// the column edge is the one it sets everywhere else.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aHeadlineSetAcrossBothColumnsIsNotCut() throws {
    // `The two flights that struck the towers` set from 39.66 across the gutter to 250.0, its words
    // 4.5 points apart, with a word space falling at the column edge the neighbors state.
    var boxes: [CGRect] = []
    var text = ""
    var x: CGFloat = 40.0
    for word in ["The", "two", "flights", "that", "struck", "the", "towers"] {
        for character in word {
            boxes.append(box(x...(x + 6.0), 528.50...535.51))
            text.append(character)
            x += 6.0
        }
        boxes.append(box(x...(x + 4.5), 528.50...528.50))
        text.append(" ")
        x += 4.5
    }
    var page = flightHeadings(merged: text, mergedBoxes: boxes)
    page.rects[3] = CGRect(x: 39.66, y: 526.00, width: x - 39.66, height: 9.89)
    // The page offers the shape: the line is the only piece of its row, between two rows of two.
    #expect(ColumnGutterCut.edges(texts: page.texts, rects: page.rects).map(\.line) == [3])
    // A word space at the gutter is still a word space.
    #expect(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects).isEmpty)
}

/// A line whose one wide gap is not where the page's columns are keeps its reading too: the white
/// has to hold the edge the rows above and below state, not merely be the widest in the line. Here
/// the line's own type runs through the gutter, which is what a caption set across both columns
/// does.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aWideGapAwayFromTheColumnEdgeIsNotCut() throws {
    let word = "flightsthatstruckthetowers"
    let text = "(AA 11) " + word
    var boxes = Array(mergedLabelBoxes[0...6])
    boxes.append(box(78.02...150.00, 528.50...528.50))
    boxes += glyphs(word.count, x: 150.00...240.00, y: 528.50...535.51)
    var page = flightHeadings(merged: text, mergedBoxes: boxes)
    page.rects[3] = CGRect(x: 39.66, y: 526.00, width: 200.34, height: 9.89)
    #expect(ColumnGutterCut.edges(texts: page.texts, rects: page.rects).map(\.line) == [3])
    #expect(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects).isEmpty)
}

/// The three rows must be the whole of what the page states. The 9/11 report's table of names on
/// page 451 sets twenty-three rows on 44.70 and 152.70, of which PDFKit merges one; the reading
/// already holds divided pieces for the rest, and dividing that one turns the page from a list of
/// names with their offices into one paragraph of names followed by one of offices (#283). A row
/// with the same pair of edges running on above it, or below it, keeps its reading.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aRowInsideALongerRunOfTwoColumnRowsIsNotCut() throws {
    let page = flightHeadings()
    for outer in [0, 6] {
        var run = page
        // One more row of the same two columns, on the far side of a neighbor: page 451's shape.
        let y: CGFloat = outer == 0 ? 548.50 : 503.67
        run.texts.insert(contentsOf: ["Thomas Pickering ", "Under Secretary of State, 1997–2000"], at: outer)
        run.boxes.insert(contentsOf: [glyphs(17, x: 39.76...120.00, y: (y + 2.3)...(y + 9.2)),
                                      glyphs(34, x: 195.72...320.00, y: (y + 2.3)...(y + 9.2))], at: outer)
        run.rects.insert(contentsOf: [CGRect(x: 39.66, y: y, width: 74.54, height: 9.21),
                                      CGRect(x: 195.67, y: y, width: 149.36, height: 9.21)], at: outer)
        #expect(!ColumnGutterCut.suspected(texts: run.texts, rects: run.rects),
                Comment(rawValue: "a run beyond the group at index \(outer) was still cut"))
    }
}

/// A row whose neighbors state no second column — one piece each — offers nothing to cut at, and
/// the page is never measured character by character.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aRowBetweenTwoUndividedRowsIsNotCut() throws {
    var page = flightHeadings()
    page.texts.remove(at: 5)
    page.boxes.remove(at: 5)
    page.rects.remove(at: 5)
    #expect(!ColumnGutterCut.suspected(texts: page.texts, rects: page.rects))
    #expect(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects).isEmpty)
}

/// Two rows that do not agree on where the second column opens state no edge at all.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func neighborsThatDisagreeOnTheColumnEdgeStateNothing() throws {
    var page = flightHeadings()
    page.rects[5] = page.rects[5].offsetBy(dx: 6, dy: 0)
    #expect(!ColumnGutterCut.suspected(texts: page.texts, rects: page.rects))
}

/// Three rows of a page at large are not a group. The running head and the flight names stand
/// 25.28 points apart over an 8.61-point row, which is no leading.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aRowFarFromItsNeighborsIsNotCut() throws {
    var page = flightHeadings()
    page.rects[3] = page.rects[3].offsetBy(dx: 0, dy: -60)
    page.boxes[3] = page.boxes[3].map { $0.offsetBy(dx: 0, dy: -60) }
    #expect(!ColumnGutterCut.suspected(texts: page.texts, rects: page.rects))
}

/// A line whose characters PDFKit reports out of the order they stand in says nothing about where
/// its columns are. The algebra book's answer key, page 453, hands back a wrapped row whose text
/// returns to the left margin mid-line; so does page 12 of the Loper Bright opinion, whose font
/// map the reading cannot follow.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aLineWhoseCharactersRunBackwardsIsNotCut() throws {
    var boxes = mergedLabelBoxes
    boxes[0] = box(300.00...303.06, 526.33...535.51)
    let page = flightHeadings(mergedBoxes: boxes)
    #expect(ColumnGutterCut.edges(texts: page.texts, rects: page.rects).map(\.line) == [3])
    #expect(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects).isEmpty)
}

/// Nothing that prints is dropped: a character standing in the white between the two cells refuses
/// the cut rather than being cut away with the space.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aPrintedCharacterInsideTheWhiteRefusesTheCut() throws {
    var boxes = mergedLabelBoxes
    var text = mergedLabelText as NSString
    // A raised marker set in the gutter, which the line's own spaces would otherwise carry away.
    boxes.insert(box(130.00...134.00, 530.00...535.51), at: 8)
    text = text.replacingCharacters(in: NSRange(location: 8, length: 0), with: "*") as NSString
    let page = flightHeadings(merged: text as String, mergedBoxes: boxes)
    #expect(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects).isEmpty)
}

/// A page whose lines and characters do not line up supplies no boxes, and nothing is cut at a
/// guessed offset.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func aLineWithoutItsCharacterBoxesIsNotCut() throws {
    var page = flightHeadings()
    page.boxes[3] = []
    #expect(ColumnGutterCut.read(texts: page.texts, boxes: page.boxes, rects: page.rects).isEmpty)
}
