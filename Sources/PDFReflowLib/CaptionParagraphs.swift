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
        var result = labeledGroups(lines: lines, pictures: pictures, body: body)
        var claimed = result.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
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
    /// A numbered caption or a photograph caption with explicit credits supplies semantic
    /// evidence independently of the page's modal type size. An opening label can use a
    /// smaller font than its continuation; retain the native runs rather than splitting there.
    private static func labeledGroups(lines: [TextLine], pictures: [CGRect], body: CGFloat) -> [Group] {
        let candidates = lines.indices.filter {
            let line = lines[$0]
            return (line.structure?.headingLevel ?? 0) == 0 && line.turn == .upright && !line.monospaced
                && line.fontSize >= body * 0.6 && line.fontSize <= body * 1.2
        }.sorted { lines[$0].rect.minY > lines[$1].rect.minY }
        var claimed: Set<Int> = [], result: [Group] = []
        for first in candidates where !claimed.contains(first) {
            let opening = lines[first]
            let numbered = opening.text.range(of: #"^Figure\s+[0-9]"#, options: .regularExpression) != nil
            let photographic = opening.text.range(of: #"^\((?:top|bottom|left|right)[ ;,)]"#, options: .regularExpression) != nil
            guard numbered || photographic else { continue }
            var run = [first], step: CGFloat?
            while run.count < 40 {
                let previous = lines[run.last!]
                if run.count > 1 && previous.rect.width < run.map({ lines[$0].rect.width }).max()! * 0.75 { break }
                let next = candidates.first { index in
                    let line = lines[index], size = max(line.fontSize,previous.fontSize)
                    let drop = previous.rect.minY - line.rect.minY
                    return !claimed.contains(index) && !run.contains(index)
                        && line.structure?.group == opening.structure?.group
                        && !LayoutReconstructor.isCaption(line.text)
                        && abs(line.fontSize - previous.fontSize) <= (run.count == 1 ? size * 0.15 : 0.1)
                        && abs(line.rect.minX - opening.rect.minX) <= size * 0.5
                        && drop >= size * 0.7 && drop <= size * 1.7
                        && (step == nil || abs(drop - step!) <= 1)
                }
                guard let next else { break }
                step = previous.rect.minY - lines[next].rect.minY
                run.append(next)
            }
            let writing = run.map { lines[$0] }, rect = union(writing.map(\.rect))
            if let tag = opening.structure {
                guard run.count == tag.lineCount,
                      lines.filter({ $0.structure?.group == tag.group }).count == run.count,
                      writing.compactMap({ $0.structure?.order }) == writing.compactMap({ $0.structure?.order }).sorted()
                else { continue }
            }
            guard run.count >= 3, writing.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).count >= 20,
                  writing.dropLast().allSatisfy({ $0.rect.width >= rect.width * 0.75 }),
                  numbered || writing.contains(where: { $0.text.localizedCaseInsensitiveContains("photo credit") }),
                  pictures.contains(where: { picture in
                      let horizontal = min(picture.maxX,rect.maxX) - max(picture.minX,rect.minX)
                      let vertical = min(picture.maxY,rect.maxY) - max(picture.minY,rect.minY)
                      let below = picture.minY - opening.rect.maxY
                      let beside = max(rect.minX - picture.maxX,picture.minX - rect.maxX)
                      return horizontal >= rect.width * 0.5 && below >= -body && below <= body * 2
                          || vertical >= min(rect.height,picture.height) * 0.5 && beside >= 0 && beside <= body * 4
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
