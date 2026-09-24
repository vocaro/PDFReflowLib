import CoreGraphics
import Foundation

/// A bibliography that prints citation numbers in their own narrow column and hangs each
/// reference on the text edge beside it. The page's repeated numbers and bibliographic text
/// establish the entry boundary; a wrapped author's initial is ordinary continuation (#219).
enum NumberedBibliography {
    private struct Edges: Hashable {
        var marker: Int
        var entry: Int
    }

    static func evidence(in lines: [TextLine], body: CGFloat) -> (openings: Set<CGRect>, edge: CGFloat)? {
        let marker = #"^[0-9]{1,4}\.$"#
        var pairs: [(number: Int, marker: TextLine, entry: TextLine)] = []
        for line in lines where !line.monospaced && line.turn == .upright {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard text.range(of: marker, options: .regularExpression) != nil,
                  let number = Int(text.dropLast()),
                  let entry = LayoutReconstructor.pieceBeside(line, in: lines),
                  entry.turn == .upright, !entry.monospaced,
                  entry.rect.width >= body * 12 else { continue }
            let indent = entry.rect.minX - line.rect.minX
            guard indent >= body * 0.5 && indent <= body * 3 else { continue }
            pairs.append((number, line, entry))
        }
        let grouped = Dictionary(grouping: pairs) { pair in
            Edges(marker: Int((pair.marker.rect.minX / max(body * 0.25, 1)).rounded()),
                  entry: Int((pair.entry.rect.minX / max(body * 0.25, 1)).rounded()))
        }
        for group in grouped.values.sorted(by: { $0.count > $1.count }) where group.count >= 3 {
            let ordered = group.sorted { $0.marker.rect.midY > $1.marker.rect.midY }
            guard zip(ordered, ordered.dropFirst()).allSatisfy({ $0.0.number < $0.1.number }) else { continue }
            let edge = ordered.map(\.entry.rect.minX).reduce(0, +) / CGFloat(ordered.count)
            let top = ordered[0].marker.rect.maxY
            let bottom = ordered.last!.marker.rect.minY
            let run = lines.filter { $0.turn == .upright && $0.rect.midY <= top && $0.rect.midY >= bottom }
            let openings = Set(ordered.map(\.marker.rect))
            let entries = Set(ordered.map(\.entry.rect))
            let wraps = run.filter {
                abs($0.rect.minX - edge) <= body * 0.25 && !entries.contains($0.rect)
            }
            guard !wraps.isEmpty else { continue }
            let citationEvidence = run.count {
                $0.text.range(of: #"\b(?:19|20)[0-9]{2}:|https?://|doi\.org/"#,
                               options: .regularExpression) != nil
            }
            guard citationEvidence >= 2 else { continue }
            return (openings, edge)
        }
        return nil
    }

    /// Some reference pages print the number and author on one line, then hang every later
    /// line to the right. The source must repeat that edge and citation syntax before a line
    /// starting with an initial, a word, or even a page number can extend the entry (#219).
    static func inlineWraps(in lines: [TextLine], body: CGFloat) -> Set<CGRect> {
        guard body.isFinite, body >= 4 else { return [] }
        let marker = #"^[1-9][0-9]{0,3}\.\s+\S"#
        let citation = #"\b(?:19|20)[0-9]{2}:|https?://|doi\.org/"#
        let starts = lines.filter { $0.turn == .upright && !$0.monospaced
            && $0.text.range(of: marker, options: .regularExpression) != nil }
        let groups = Dictionary(grouping: starts) {
            Int(($0.rect.minX / max(body * 0.25, 1)).rounded())
        }
        for group in groups.values.sorted(by: { $0.count > $1.count }) where group.count >= 3 {
            let ordered = group.sorted { $0.rect.midY > $1.rect.midY }
            let numbers = ordered.compactMap { Int($0.text.prefix(while: \.isNumber)) }
            guard numbers.count == ordered.count,
                  zip(numbers, numbers.dropFirst()).allSatisfy({ $0.0 < $0.1 }),
                  ordered.count(where: { $0.text.range(of: citation, options: .regularExpression) != nil }) >= 2
            else { continue }
            let edge = ordered.map(\.rect.minX).reduce(0, +) / CGFloat(ordered.count)
            var wraps: Set<CGRect> = []
            for index in ordered.indices {
                let opening = ordered[index]
                let floor = index + 1 < ordered.count ? ordered[index + 1].rect.midY : -CGFloat.infinity
                var previous = opening
                for line in lines.filter({ $0.rect.midY < opening.rect.midY && $0.rect.midY > floor })
                    .sorted(by: { $0.rect.midY > $1.rect.midY }) {
                    let inset = line.rect.minX - edge
                    guard line.turn == .upright, !line.monospaced,
                          inset >= body * 0.75, inset <= body * 2.5,
                          opening.hasSize(line.fontSize), previous.hasSize(line.fontSize),
                          previous.rect.minY > line.rect.minY,
                          previous.rect.minY - line.rect.minY <= body * 1.6 else { break }
                    wraps.insert(line.rect)
                    previous = line
                }
            }
            if wraps.count >= 3 { return wraps }
        }
        return []
    }
}
