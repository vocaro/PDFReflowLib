import Foundation

/// Coalesce short, aligned bold rows only for the existing section-label evidence test.
/// This establishes no heading on its own: the resulting line must still have a recurring
/// label style, clearance above it, and a body paragraph opening on the book's stated indent.
enum StackedSectionLabels {
    struct Group {
        let indices: [Int]
        let line: TextLine
    }

    /// Once every component has passed `sectionLabels`, emit one heading with its complete
    /// inline content. Merely giving both rows a heading role would make two navigation entries.
    static func coalescing(_ lines: [TextLine], labels: [TextLine], body: CGFloat)
        -> (lines: [TextLine], labels: [TextLine]) {
        let proven = groups(in: lines, body: body).filter { group in
            group.indices.allSatisfy { labels.contains(lines[$0]) }
        }
        let claimed = Set(proven.flatMap(\.indices))
        let originals = claimed.map { lines[$0] }
        return (lines.enumerated().filter { !claimed.contains($0.offset) }.map(\.element)
                    + proven.map(\.line),
                labels.filter { !originals.contains($0) } + proven.map(\.line))
    }

    static func groups(in lines: [TextLine], body: CGFloat) -> [Group] {
        guard body > 0, lines.count <= 2000 else { return [] }
        let candidates = lines.indices.filter {
            let line = lines[$0]
            return line.turn == .upright && !line.monospaced && line.structure == nil
                && line.fontSize >= body * 0.8 && line.fontSize < body * 0.95
                && LayoutReconstructor.readsWhollyBold(line) && line.text.contains(where: \.isLetter)
        }.sorted { lines[$0].rect.maxY > lines[$1].rect.maxY }
        var used: Set<Int> = []
        var groups: [Group] = []
        for first in candidates where !used.contains(first) {
            var indices = [first]
            while let last = indices.last, indices.count < 3,
                  lines[last].text.last.map({ !".!?;:".contains($0) }) == true {
                let matches = candidates.filter { index in
                    let line = lines[index]
                    let gap = lines[last].rect.minY - line.rect.maxY
                    return !used.contains(index) && !indices.contains(index)
                        && line.hasSize(lines[first].fontSize)
                        && abs(line.rect.minX - lines[first].rect.minX) < body * 0.2
                        && gap >= -0.5 && gap <= body * 0.4
                }
                guard matches.count == 1, let next = matches.first else { break }
                indices.append(next)
            }
            guard indices.count >= 2 else { continue }
            var content = lines[first].content
            for index in indices.dropFirst() {
                content.append(InlineText(" "))
                content.append(lines[index].content)
            }
            guard content.text.count < 200 else { continue }
            used.formUnion(indices)
            groups.append(Group(indices: indices, line: TextLine(content: content,
                rect: indices.reduce(CGRect.null) { $0.union(lines[$1].rect) },
                fontSize: lines[first].fontSize)))
        }
        return groups
    }
}
