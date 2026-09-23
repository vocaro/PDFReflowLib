import Foundation

/// A small-type paragraph next to a photograph has one reading footprint. Its printed rows
/// must not alternate with the larger body column beside it.
enum CaptionParagraphs {
    struct Group {
        var indices: Set<Int>
        var lines: [TextLine]
        var rect: CGRect { union(lines.map(\.rect)) }
    }
    static func groups(lines: [TextLine], pictures: [CGRect], body: CGFloat) -> [Group] {
        guard body > 0, lines.count <= 2_000, !pictures.isEmpty else { return [] }
        let small = lines.indices.filter { lines[$0].fontSize < body * 0.93
            && lines[$0].fontSize >= body * 0.6 && !lines[$0].monospaced
            && lines[$0].structure == nil && lines[$0].turn == .upright
        }.sorted { lines[$0].rect.minY > lines[$1].rect.minY }
        var claimed: Set<Int> = [], result: [Group] = []
        for first in small where !claimed.contains(first) {
            let opening = lines[first]
            var run = [first]
            while run.count < 20, let last = run.last,
                  lines[last].text.last.map({ !".!?".contains($0) }) == true {
                let next = small.first { index in
                    let line = lines[index], leading = lines[last].rect.minY - line.rect.minY
                    return !claimed.contains(index) && !run.contains(index)
                        && abs(line.fontSize - opening.fontSize) < 0.1
                        && abs(line.rect.minX - opening.rect.minX) <= opening.fontSize * 0.5
                        && leading >= opening.fontSize * 0.7 && leading <= opening.fontSize * 2
                }
                guard let next else { break }; run.append(next)
            }
            let writing = run.map { lines[$0] }, rect = union(writing.map(\.rect))
            let words = writing.map(\.text).joined(separator: " ").split { $0.isWhitespace || $0 == "-" }
            guard run.count >= 2, words.count >= 12,
                  writing.last?.text.last.map({ ".!?".contains($0) }) == true,
                  writing.dropLast().allSatisfy({ $0.rect.width >= rect.width * 0.75 }),
                  pictures.contains(where: { picture in
                      let horizontal = min(picture.maxX, rect.maxX) - max(picture.minX, rect.minX)
                      return horizontal >= rect.width * 0.5
                          && picture.insetBy(dx: 0, dy: -body * 2).intersects(rect)
                  }) else { continue }
            let indices = Set(lines.indices.filter { index in
                run.contains { lines[$0].text == lines[index].text && lines[$0].rect == lines[index].rect }
            })
            claimed.formUnion(indices)
            result.append(Group(indices: indices, lines: writing))
        }
        return result
    }
}
