import CoreGraphics
import Foundation

/// The geometric relations the layout rules ask of lines, written once. Each is a plain
/// predicate over rectangles and sizes; the thresholds are the ones the rules always used.
extension TextLine {
    /// Set within a tenth of `size`: the same type size, as far as layout is concerned.
    func hasSize(_ size: CGFloat) -> Bool {
        abs(fontSize - size) <= size * 0.1
    }

    /// The two lines share some horizontal extent: they stand in the same column, or one spans it.
    ///
    /// Across the writing, where both lines were set at one quarter turn: a sideways line's
    /// column runs down the page, and its own rectangle is as tall as the line is long, so on the
    /// page every sideways line of a caption overlaps every other (#276, #263). Two lines the page
    /// set at different turns have no common frame and are compared on the page, as before; for
    /// two upright lines this is the page.
    func overlapsHorizontally(_ other: TextLine) -> Bool {
        let (a, b) = turn == other.turn ? (uprightRect, other.uprightRect) : (rect, other.rect)
        return b.minX < a.maxX && b.maxX > a.minX
    }

    /// Another line of the same column: not this line, and overlapping it horizontally.
    func sharesColumn(with other: TextLine) -> Bool {
        other != self && overlapsHorizontally(other)
    }

    /// Pieces of one visual row: PDFKit splits rows at wide gaps, and superscripts are separate
    /// lines. The rectangles overlap vertically by at least half the shorter one's height.
    func sharesRow(with other: TextLine) -> Bool {
        turn == other.turn ? TextLine.sameRow(uprightRect, other.uprightRect)
                           : TextLine.sameRow(rect, other.rect)
    }

    static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.5
    }

    /// This line's rectangle in the frame its own writing runs in (#263). A line the page set
    /// upright carries its own rectangle, to the bit.
    var uprightRect: CGRect { turn.upright(rect) }
}
