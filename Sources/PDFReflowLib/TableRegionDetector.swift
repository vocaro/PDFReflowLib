import CoreGraphics
import Foundation

/// Conservative preservation for numeric lookup tables separated by dot leaders. This is not
/// a semantic table parser: column associations remain in the source rendering.
enum TableRegionDetector {
    static func regions(in page: PageContent) -> [CGRect] {
        let rowPattern = #"^\s*[+−-]?\d[\d,]*(?:\.\d+)?\s*(?:\.\s*){3,}[+−-]?\d[\d\s.,/%×xX+−–:-]*$"#
        let rows = page.lines.filter {
            !$0.monospaced && $0.text.range(of: rowPattern, options: .regularExpression) != nil
        }.sorted { $0.rect.midY > $1.rect.midY }
        var groups: [[TextLine]] = []
        for row in rows {
            if let index = groups.indices.first(where: { index in
                let last = groups[index].last!
                let size = max(row.fontSize, last.fontSize)
                let gap = last.rect.minY - row.rect.maxY
                return abs(last.rect.minX - row.rect.minX) <= max(2, size * 0.6)
                    && abs(last.rect.maxX - row.rect.maxX) <= size * 2
                    && gap >= -size * 0.4 && gap <= size * 1.5
            }) {
                groups[index].append(row)
            } else { groups.append([row]) }
        }
        return groups.compactMap { rows in
            guard rows.count >= 3, let first = rows.first else { return nil }
            let rowBounds = union(rows.map(\.rect))
            // Require a nearby, similarly aligned textual header. A contents entry or a
            // prose ellipsis must not become a table merely because it contains dots.
            let headers = page.lines.filter { line in
                let gap = line.rect.minY - first.rect.maxY
                let words = line.text.split { !$0.isLetter }
                return words.count >= 2 && !line.monospaced
                    && gap >= 0 && gap <= first.fontSize * 3
                    && abs(line.rect.minX - rowBounds.minX) <= max(2, first.fontSize)
                    && line.rect.width >= rowBounds.width * 0.65
                    && line.rect.width <= rowBounds.width * 1.3
            }
            guard let header = headers.min(by: { $0.rect.minY < $1.rect.minY }) else { return nil }
            // An intervening paragraph breaks a row sequence even when its numbers align.
            guard !page.lines.contains(where: { line in
                rowBounds.intersects(line.rect) && !rows.contains(where: { $0.rect == line.rect && $0.text == line.text })
            }) else { return nil }
            return rowBounds.union(header.rect).insetBy(dx: -2, dy: -2).intersection(page.bounds)
        }
    }

    /// Borderless statistical tables underline their column headers instead of ruling cells.
    /// A row of at least three underlines, or one short piece underlined whole away from the
    /// left margin, marks a header; the table is the tightly leaded block around it whose rows
    /// carry numbers. A single label underline followed by prose is not a table (#36).
    static func underlinedColumnRegions(in page: PageContent) -> [CGRect] {
        let rules = page.graphics.filter(LayoutReconstructor.isThinRule)
        guard !rules.isEmpty else { return [] }
        var rows: [[TextLine]] = []
        for line in page.lines.sorted(by: { $0.rect.minY > $1.rect.minY }) {
            if let last = rows.last?.first, abs(last.rect.minY - line.rect.minY) <= 1.5 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        func baseline(_ row: [TextLine]) -> CGFloat { row.map(\.rect.minY).min()! }
        var regions: [CGRect] = []
        var covered = Set<Int>()
        for (index, row) in rows.enumerated() where !covered.contains(index) {
            // Equations are never column headers: a row of divisor bars beneath "8x = -24" is
            // a worked example, not a table.
            let underlines = rules.filter { rule in
                guard let line = LayoutReconstructor.underlinedLine(rule, in: page.lines), !line.text.contains("=") else { return false }
                return row.contains { $0.rect == line.rect && $0.text == line.text }
            }
            let columnHeaders = underlines.count >= 3
            let subheader = underlines.count == 1 && row.count == 1 && {
                let piece = row[0].rect, rule = underlines[0]
                return rule.width >= piece.width * 0.85 && piece.width <= page.bounds.width * 0.3
                    && piece.minX >= page.bounds.minX + page.bounds.width * 0.3
            }()
            guard columnHeaders || subheader else { continue }
            let leading = row.map(\.fontSize).max()! * 1.6
            var top = index, bottom = index
            while top > 0, baseline(rows[top - 1]) - baseline(rows[top]) <= leading { top -= 1 }
            while bottom + 1 < rows.count, baseline(rows[bottom]) - baseline(rows[bottom + 1]) <= leading { bottom += 1 }
            let below = rows[(index + 1)..<(bottom + 1)]
            guard below.count >= 3,
                  below.filter({ $0.contains { $0.text.contains { $0.isNumber } } }).count * 2 >= below.count else { continue }
            covered.formUnion(top...bottom)
            let block = rows[top...bottom].flatMap { $0.map(\.rect) }
                + rules.filter { rule in rows[top...bottom].contains { row in
                    row.contains { LayoutReconstructor.underlinedLine(rule, in: page.lines)?.rect == $0.rect } } }
            regions.append(union(block).insetBy(dx: -2, dy: -2).intersection(page.bounds))
        }
        return regions
    }
}
