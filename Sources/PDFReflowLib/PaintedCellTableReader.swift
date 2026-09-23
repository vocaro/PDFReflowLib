import CoreGraphics
import Foundation

/// A grid whose cells the PDF explicitly fills as adjacent rectangles (#215). Unlike a gap
/// between prose columns, every internal edge is painted in every row. This path admits text
/// tables and two-column tables; it declines partial grids, overlapping paint and empty cells.
/// A distinct header must precede the body: a short painted first row, or text labels over
/// numeric values. Three adjacent cells in a larger table are not enough to claim a new table.
enum PaintedCellTableReader {
    static func tables(lines: [TextLine], cells: [CGRect], read: (CGRect) -> String) -> [PageTable] {
        guard cells.count <= 2_000, lines.count <= 10_000 else { return [] }
        let body = max(4, LayoutReconstructor.bodySize(lines))
        var seen: Set<[Int]> = []
        let rectangles = cells.filter { rect in
            guard rect.isFinite, rect.width >= body * 1.5, rect.height >= body * 0.7 else { return false }
            let key = [rect.minX, rect.minY, rect.maxX, rect.maxY].map { Int(($0 * 2).rounded()) }
            return seen.insert(key).inserted
        }
        // Full-width background bands and boxes do not divide a row into cells.
        let byRow = Dictionary(grouping: rectangles) { rect in
            [Int((rect.minY * 2).rounded()), Int((rect.maxY * 2).rounded())]
        }
        let rows = byRow.values.compactMap { rects -> [CGRect]? in
            let row = rects.filter { outer in
                !rects.contains { inner in inner != outer && outer.contains(inner) }
            }.sorted { $0.minX < $1.minX }
            guard row.count >= 2, row.count <= 12,
                  zip(row, row.dropFirst()).allSatisfy({ abs($0.maxX - $1.minX) <= 0.75 }) else { return nil }
            return row
        }
        let byColumns = Dictionary(grouping: rows) { row in
            ([row[0].minX] + row.map(\.maxX)).map { Int(($0 * 2).rounded()) }
        }
        var result: [PageTable] = []
        for columns in byColumns.values {
            var groups: [[[CGRect]]] = []
            for row in columns.sorted(by: { $0[0].maxY > $1[0].maxY }) {
                if let above = groups.last?.last, abs(above[0].minY - row[0].maxY) <= 0.75 {
                    groups[groups.count - 1].append(row)
                } else { groups.append([row]) }
            }
            for grid in groups where grid.count >= 3 {
                let rect = grid.flatMap { $0 }.reduce(CGRect.null) { $0.union($1) }
                let owned = lines.filter { rect.insetBy(dx: -0.5, dy: -0.5).contains($0.rect) }
                // A line crossing the boundary belongs to material this grid cannot account for.
                guard !lines.contains(where: { line in
                    rect.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) && !owned.contains(line)
                }) else { continue }
                var readRows: [[PageTable.Cell]] = []
                var valid = true
                for row in grid {
                    var values: [PageTable.Cell] = []
                    for cell in row {
                        let plain = read(cell.insetBy(dx: 0.1, dy: 0.1))
                            .replacingOccurrences(of: "\u{FFFC}", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !plain.isEmpty else { valid = false; break }
                        let inside = owned.filter { cell.insetBy(dx: -0.5, dy: -0.5).contains($0.rect) }
                            .sorted { a, b in abs(a.rect.midY - b.rect.midY) > body * 0.4
                                ? a.rect.midY > b.rect.midY : a.rect.minX < b.rect.minX }
                        var content = InlineText(plain.replacingOccurrences(of: "\n", with: " "))
                        if !inside.isEmpty, compact(inside.map(\.text).joined()) == compact(plain) {
                            content = InlineText()
                            for line in inside {
                                if !content.text.isEmpty { content.append(InlineText(" ")) }
                                content.append(line.content)
                            }
                        }
                        values.append(PageTable.Cell(content: content, rect: cell))
                    }
                    if !valid { break }
                    readRows.append(values)
                }
                guard valid,
                      characters(readRows.flatMap { $0.map(\.text) }.joined())
                        == characters(owned.map(\.text).joined()) else { continue }
                // Painted cells establish the grid, not the role of its first row. All first-row
                // cells must be short labels containing letters before they become headers.
                let heights = grid.dropFirst().map { $0[0].height }.sorted()
                let compactHeader = grid[0][0].height <= heights[heights.count / 2] * 0.8
                let valuesBelow = readRows.dropFirst().count { row in
                    row.dropFirst().contains { $0.text.contains(where: \.isNumber) && !$0.text.contains(where: \.isLetter) }
                } >= 3
                let header = (compactHeader || valuesBelow) && readRows[0].allSatisfy {
                    $0.text.contains(where: \.isLetter) && $0.text.count < 100 && !$0.text.contains("•")
                }
                guard header else { continue }
                result.append(PageTable(rect: rect, rows: readRows, headerRows: 1))
            }
        }
        return result.sorted { ($0.rect.maxY, -$0.rect.minX) > ($1.rect.maxY, -$1.rect.minX) }
    }

    private static func compact(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }

    private static func characters(_ text: String) -> [Character: Int] {
        Dictionary(text.filter { !$0.isWhitespace }.map { ($0, 1) }, uniquingKeysWith: +)
    }
}
