import CoreGraphics
import Foundation

/// Reunite an entry and its detached page locator only when a painted horizontal leader
/// connects them. A repeated, aligned locator column distinguishes contents from figure labels.
/// The resulting native row retains both pieces' styles and links, and its original full
/// measure lets crop ownership recognize a row reaching into decorative corner artwork.
enum LeaderRows {
    static let maximumComparisons = 2_000_000

    static func joined(_ page: PageContent, paints: [GraphicsReader.Paint],
                       comparisonLimit: Int = maximumComparisons) -> [TextLine] {
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
        // Every potentially multiplicative geometry comparison shares one budget. Returning
        // the original array on exhaustion prevents a partially associated page from depending
        // on which row or rule happened to be visited first.
        var comparisons = 0
        func spend() -> Bool {
            guard comparisons < comparisonLimit else { return false }
            comparisons += 1
            return true
        }
        var numbers: [Int] = [], labels: [Int] = []
        for index in lines.indices {
            let line = lines[index]
            guard line.turn == .upright, !line.monospaced, line.structure == nil else { continue }
            var inTable = false
            for table in page.tables {
                guard spend() else { return lines }
                if table.rect.intersects(line.rect) { inTable = true; break }
            }
            guard !inTable else { continue }
            if locator(line) { numbers.append(index) }
            else if line.text.filter(\.isLetter).count >= 4 { labels.append(index) }
        }
        var pairs: [(entry: Int, number: Int)] = []
        for number in numbers {
            let value = lines[number], size = max(4, value.fontSize)
            guard value.rect.width <= size * 4 else { continue }
            var entries: [Int] = []
            for entry in labels {
                guard spend() else { return lines }
                let label = lines[entry]
                guard abs(label.fontSize - value.fontSize) <= size * 0.1,
                      abs(label.rect.midY - value.rect.midY) <= size * 0.25,
                      label.rect.maxX < value.rect.minX - size else { continue }
                var linked = false
                for rule in rules {
                    guard spend() else { return lines }
                    if rule.midY >= label.rect.minY && rule.midY <= label.rect.maxY
                        && abs(rule.minX - label.rect.maxX) <= size
                        && abs(rule.maxX - value.rect.minX) <= size
                        && rule.width >= size * 2 { linked = true; break }
                }
                guard linked else { continue }
                let bottom = max(label.rect.minY, value.rect.minY)
                let corridor = CGRect(x: label.rect.maxX, y: bottom,
                    width: value.rect.minX - label.rect.maxX,
                    height: min(label.rect.maxY, value.rect.maxY) - bottom)
                var obstructed = false
                for other in lines.indices where other != entry && other != number {
                    guard spend() else { return lines }
                    if lines[other].rect.intersects(corridor) { obstructed = true; break }
                }
                if !obstructed { entries.append(entry) }
            }
            if entries.count == 1 { pairs.append((entries[0], number)) }
        }
        var accepted: [(entry: Int, number: Int)] = []
        for pair in pairs {
            let value = lines[pair.number]
            var aligned = 0
            for other in pairs {
                guard spend() else { return lines }
                if abs(lines[other.number].rect.maxX - value.rect.maxX) <= value.fontSize * 0.3 {
                    aligned += 1
                    if aligned >= 3 { break }
                }
            }
            if aligned >= 3 { accepted.append(pair) }
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
