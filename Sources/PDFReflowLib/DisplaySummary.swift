import CoreGraphics
import Foundation

/// An opener can set a complete summary between its larger title and its smaller contents.
/// Sentence punctuation, a repeated measure, and the isolated contents below distinguish this
/// display prose from a multiline title. Quoted displays have their own semantics (#214).
enum DisplaySummary {
    struct Group {
        var indices: Set<Int>
        var lines: [TextLine]
        var rect: CGRect { union(lines.map(\.rect)) }
    }

    static func groups(in lines: [TextLine], body: CGFloat, threshold: CGFloat) -> [Group] {
        guard lines.count <= 2_000, body >= 4 else { return [] }
        let displayed = lines.indices.filter {
            let line = lines[$0]
            return line.turn == .upright && !line.monospaced && line.rect.isFinite
                && line.fontSize >= max(threshold, body * 1.2)
        }.sorted { lines[$0].rect.midY > lines[$1].rect.midY }
        var claimed: Set<Int> = [], result: [Group] = []
        for opening in displayed where !claimed.contains(opening) {
            let first = lines[opening], size = first.fontSize
            guard first.text.first?.isUppercase == true else { continue }
            var run = [opening]
            while run.count < 12, let last = run.last {
                let above = lines[last]
                let next = displayed.filter { index in
                    let line = lines[index], leading = above.rect.minY - line.rect.minY
                    return !claimed.contains(index) && !run.contains(index)
                        && abs(line.fontSize - size) <= size * 0.1
                        && abs(line.rect.minX - first.rect.minX) <= size * 0.5
                        && leading >= size * 0.7 && leading <= size * 2
                }.max { lines[$0].rect.midY < lines[$1].rect.midY }
                guard let next else { break }
                run.append(next)
            }
            let text = run.map { lines[$0].text }.joined(separator: " ")
            guard run.count >= 3, run.count < 12, text.last == ".",
                  text.split(whereSeparator: \.isWhitespace).count >= 12 else { continue }
            let rect = union(run.map { lines[$0].rect })
            // PDFKit sometimes joins an oversized chapter numeral to its title. Its union can
            // overlap the summary vertically; the title's midpoint still stands above it.
            let above = lines.filter {
                $0.rect.midY > first.rect.maxY && $0.overlapsHorizontally(first)
            }.min { $0.rect.midY < $1.rect.midY }
            guard let above, above.fontSize >= size * 1.35,
                  above.rect.maxY - first.rect.maxY <= size * 8 else { continue }
            let below = lines.filter { $0.rect.maxY < rect.minY && $0.overlapsHorizontally(first) }
                .sorted { $0.rect.maxY > $1.rect.maxY }
            guard let nearest = below.first, rect.minY - nearest.rect.maxY >= size * 3,
                  below.count(where: {
                      $0.fontSize < size * 0.9 &&
                      $0.text.range(of: #"(?:\.\s*){3,}\d+\s*$"#, options: .regularExpression) != nil
                  }) >= 2 else { continue }
            let indices = Set(run)
            claimed.formUnion(indices)
            result.append(Group(indices: indices, lines: run.map { lines[$0] }))
        }
        return result
    }
}
