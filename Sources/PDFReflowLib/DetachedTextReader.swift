import Foundation

/// Separates labels set on opposite sides of a page but returned as one PDFKit line (#172).
/// Called only inside the native extraction gate. The content stream proposes gaps; rectangle
/// selections measure their ink because PDFKit's character boxes include the spanning space.
enum DetachedTextReader {
    struct Piece {
        var text: String
        var rect: CGRect
        var range: NSRange
    }

    static func pieces(text: String, rect: CGRect, size: CGFloat,
                       shows: [NativeSpacingReader.Evidence], allBounds: [CGRect],
                       pageWidth: CGFloat, measure: (CGRect, CGFloat, CGFloat) -> (String, CGRect)?) -> [Piece]? {
        let least = max(max(4, size) * 8, pageWidth * 0.25)
        guard rect.width > least else { return nil }
        let matches = shows.filter { rect.insetBy(dx: -0.75, dy: -0.75).contains($0.origin) }
        guard matches.count >= 2, matches.allSatisfy({ show in
            allBounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(show.origin) }.count == 1
        }) else { return nil }
        let ordered = matches.sorted { $0.origin.x < $1.origin.x }
        let cuts = zip(ordered, ordered.dropFirst()).compactMap { left, right -> CGFloat? in
            right.origin.x - left.origin.x > least ? right.origin.x - 0.5 : nil
        }
        guard !cuts.isEmpty else { return nil }
        let edges = [rect.minX] + cuts + [rect.maxX]
        var result: [Piece] = []
        let original = text as NSString
        var cursor = 0
        for (start, end) in zip(edges, edges.dropFirst()) {
            guard let (value, bounds) = measure(rect, start, end) else { return nil }
            let range = original.range(of: value, options: [], range: NSRange(location: cursor, length: original.length - cursor))
            guard range.location != NSNotFound,
                  original.substring(with: NSRange(location: cursor, length: range.location - cursor))
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            result.append(Piece(text: value, rect: bounds, range: range))
            cursor = NSMaxRange(range)
        }
        guard original.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              zip(result, cuts).allSatisfy({ $0.rect.maxX <= $1 + 1 }),
              zip(result.dropFirst(), cuts).allSatisfy({ $0.rect.minX >= $1 - 1 }),
              zip(result, result.dropFirst()).allSatisfy({ left, right in
                  let gap = right.rect.minX - left.rect.maxX
                  return gap >= least && gap >= left.rect.width + right.rect.width
              }) else { return nil }
        return result
    }

}
