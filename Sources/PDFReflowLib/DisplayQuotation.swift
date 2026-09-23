import CoreGraphics
import Foundation

/// A displayed quotation is a single reading unit, not one navigation heading per printed row.
/// The opening and closing quotation marks, several rows of display type, and a stable measure
/// identify it; size alone cannot distinguish a quotation from a heading.
enum DisplayQuotation {
    struct Group {
        var indices: Set<Int>
        var lines: [TextLine]
        var rect: CGRect { union(lines.map(\.rect)) }
    }

    static func groups(in lines: [TextLine], body: CGFloat, threshold: CGFloat) -> [Group] {
        guard lines.count <= 2_000 else { return [] }
        let displayed = lines.indices.filter {
            lines[$0].fontSize >= max(threshold, body * 1.2) && !lines[$0].monospaced
                && lines[$0].structure == nil
        }.sorted { lines[$0].rect.minY > lines[$1].rect.minY }
        var claimed: Set<Int> = []
        var groups: [Group] = []
        for opening in displayed where !claimed.contains(opening) {
            let first = lines[opening]
            guard first.text.first == "“" || first.text.first == "\"" else { continue }
            let closing: Character = first.text.first == "“" ? "”" : "\""
            var run = [opening]
            var closed = first.text.dropFirst().contains(closing)
            while !closed, run.count < 24, let last = run.last {
                let above = lines[last]
                let next = displayed.filter { index in
                    let line = lines[index]
                    let leading = above.rect.minY - line.rect.minY
                    return !claimed.contains(index) && !run.contains(index)
                        && abs(line.fontSize - first.fontSize) <= first.fontSize * 0.1
                        && abs(line.rect.minX - first.rect.minX) <= first.fontSize * 0.5
                        && leading >= first.fontSize * 0.7 && leading <= first.fontSize * 2
                }.min { lines[$0].rect.minY > lines[$1].rect.minY }
                guard let next else { break }
                run.append(next)
                closed = lines[next].text.contains(closing)
            }
            guard closed, run.count >= 3,
                  run.reduce(0, { $0 + lines[$1].text.split(whereSeparator: \.isWhitespace).count }) >= 20
            else { continue }
            // An attribution placed beneath the close belongs to the quotation too. Its dash,
            // size, leading and containment all have to agree with the displayed measure.
            let rect = union(run.map { lines[$0].rect })
            if let last = run.last, let attribution = displayed.first(where: { index in
                let line = lines[index]
                let gap = lines[last].rect.minY - line.rect.maxY
                return !claimed.contains(index) && (line.text.first == "—" || line.text.first == "–")
                    && abs(line.fontSize - first.fontSize) <= first.fontSize * 0.1
                    && gap >= -1 && gap <= first.fontSize && line.rect.minX >= rect.minX
                    && line.rect.maxX <= rect.maxX + 1
            }) { run.append(attribution) }
            let copies = Set(lines.indices.filter { index in
                run.contains { lines[$0].text == lines[index].text && lines[$0].rect == lines[index].rect }
            })
            claimed.formUnion(copies)
            groups.append(Group(indices: copies, lines: run.map { lines[$0] }))
        }
        return groups
    }
}
