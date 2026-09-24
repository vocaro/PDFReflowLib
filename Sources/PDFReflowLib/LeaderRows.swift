import CoreGraphics
import Foundation

/// Reunite an entry and its detached page locator only when a painted horizontal leader
/// connects them. A repeated, aligned locator column distinguishes contents from figure labels.
/// The resulting native row retains both pieces' styles and links, and its original full
/// measure lets crop ownership recognize a row reaching into decorative corner artwork.
enum LeaderRows {
    static func joined(_ page: PageContent, paints: [GraphicsReader.Paint]) -> [TextLine] {
        let lines = page.lines
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage,
              lines.count <= 2_000, paints.count <= 8_000 else { return lines }
        let rules = paints.filter { paint in
            guard !paint.image, paint.strokeOnly == true, paint.vertices.count == 2,
                  abs(paint.vertices[0].y - paint.vertices[1].y) <= 0.5 else { return false }
            return LayoutReconstructor.isThinRule(paint.rect)
        }.map(\.rect)
        guard !rules.isEmpty else { return lines }
        func locator(_ line: TextLine) -> Bool {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.range(of: #"^(?:[ivxlcdmIVXLCDM]{1,8}|[A-Z]?[0-9]{1,3}-[0-9]{1,3})$"#,
                              options: .regularExpression) != nil
        }
        func eligible(_ line: TextLine) -> Bool {
            line.turn == .upright && !line.monospaced && line.structure == nil
                && !page.tables.contains { $0.rect.intersects(line.rect) }
        }
        var pairs: [(entry: Int, number: Int)] = []
        for number in lines.indices where eligible(lines[number]) && locator(lines[number]) {
            let value = lines[number], size = max(4, value.fontSize)
            guard value.rect.width <= size * 4 else { continue }
            let entries = lines.indices.filter { entry in
                let label = lines[entry]
                guard entry != number, eligible(label), !locator(label),
                      label.text.filter(\.isLetter).count >= 4,
                      abs(label.fontSize - value.fontSize) <= size * 0.1,
                      abs(label.rect.midY - value.rect.midY) <= size * 0.25,
                      label.rect.maxX < value.rect.minX - size else { return false }
                return rules.contains { rule in
                    rule.midY >= label.rect.minY && rule.midY <= label.rect.maxY
                        && abs(rule.minX - label.rect.maxX) <= size
                        && abs(rule.maxX - value.rect.minX) <= size
                        && rule.width >= size * 2
                }
            }
            if entries.count == 1 { pairs.append((entries[0], number)) }
        }
        let accepted = pairs.filter { pair in
            let value = lines[pair.number]
            return pairs.filter { other in
                abs(lines[other.number].rect.maxX - value.rect.maxX) <= value.fontSize * 0.3
            }.count >= 3
        }
        guard !accepted.isEmpty else { return lines }
        var replacements: [Int: TextLine] = [:], removed = Set<Int>()
        for pair in accepted {
            guard replacements[pair.entry] == nil, !removed.contains(pair.number) else { continue }
            let entry = lines[pair.entry], number = lines[pair.number]
            var content = entry.content
            content.append(InlineText(" "))
            content.append(number.content)
            var joined = TextLine(content: content, rect: entry.rect.union(number.rect),
                                  fontSize: entry.fontSize, monospaced: entry.monospaced,
                                  wraps: entry.wraps, turn: entry.turn)
            joined.readingRect = (entry.readingRect ?? entry.rect).union(number.readingRect ?? number.rect)
            joined.structure = entry.structure
            replacements[pair.entry] = joined
            removed.insert(pair.number)
        }
        return lines.indices.compactMap { removed.contains($0) ? nil : replacements[$0] ?? lines[$0] }
    }
}
