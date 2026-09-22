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
    func overlapsHorizontally(_ other: TextLine) -> Bool {
        other.rect.minX < rect.maxX && other.rect.maxX > rect.minX
    }

    /// Another line of the same column: not this line, and overlapping it horizontally.
    func sharesColumn(with other: TextLine) -> Bool {
        other != self && overlapsHorizontally(other)
    }

    /// Pieces of one visual row: PDFKit splits rows at wide gaps, and superscripts are separate
    /// lines. The rectangles overlap vertically by at least half the shorter one's height.
    func sharesRow(with other: TextLine) -> Bool {
        TextLine.sameRow(rect, other.rect)
    }

    static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.5
    }

    /// This line's rectangle in the frame its own writing runs in (#263). A line the page set
    /// upright carries its own rectangle, to the bit.
    var uprightRect: CGRect { turn.upright(rect) }
}
