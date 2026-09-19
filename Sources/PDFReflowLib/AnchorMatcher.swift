import CoreGraphics
import Foundation

/// Matches content-stream anchors (text-show origins) to the PDFKit line rectangles they fall in.
/// The tolerance and the caps are shared by every reader that associates its evidence with lines.
enum AnchorMatcher {
    /// A point this close to a line's edge still counts as inside it.
    static let tolerance: CGFloat = 0.75
    static let maximumAnchors = 10_000
    static let maximumComparisons = 2_000_000

    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    /// The one anchor whose point lies in `bounds`, provided that point lies in no other line's
    /// bounds either; nil when there is none, more than one, or the caps are exceeded. This is
    /// conservative association evidence: an ambiguous anchor rewrites nothing.
    static func uniqueAnchor<Anchor>(_ anchors: [Anchor], at point: KeyPath<Anchor, CGPoint>, in bounds: CGRect,
                                     among allBounds: [CGRect]) -> Anchor? {
        guard anchors.count <= maximumAnchors, allBounds.count <= maximumAnchors,
              anchors.count * allBounds.count <= maximumComparisons else { return nil }
        let matches = anchors.filter { contains(bounds, $0[keyPath: point]) }
        guard matches.count == 1, let match = matches.first,
              allBounds.filter({ contains($0, match[keyPath: point]) }).count == 1 else { return nil }
        return match
    }
}
