import CoreGraphics
import Foundation
import PDFKit

/// A rectangular grid states cell associations even when its values are words. Unlike the
/// whitespace table reader, this requires painted row and column borders, not numeric content.
enum RuledTableReader {
    static func tables(on page: PDFPage, lines: [TextLine], paints: [GraphicsReader.Paint]) throws -> [PageTable] {
        try NativeTextReader.withExtractionLock {
            tables(lines: lines, paints: paints) { cell in
                page.selection(for: cell)?.string ?? ""
            }
        }
    }

    static func tables(lines: [TextLine], paints: [GraphicsReader.Paint], readCell: (CGRect) -> String) -> [PageTable] {
        let rectangles = paints.filter { $0.rectangular && $0.vertices.count == 4 }.map { paint in
            union(paint.vertices.map { CGRect(x: $0.x, y: $0.y, width: 0, height: 0) })
        }
        let rules = rectangles.filter {
            min($0.width, $0.height) <= 2 && max($0.width, $0.height) >= 12
        }
        guard rules.count >= 5, rules.count <= 1_000 else { return [] }
        let components = clusters(rules, distance: 2)
        return components.compactMap { hull in
                let fills = rectangles.filter { fill in fill.width > 12 && fill.height > 10
                    && hull.insetBy(dx: -2, dy: -30).contains(fill) && fill.height <= hull.height + 30
                    && !components.contains(where: { other in other != hull && other.intersects(fill) }) }
                let area = union([hull] + fills)
                let grid = rules.filter { area.insetBy(dx: -2, dy: -2).contains($0) }
                let horizontals = grid.filter { $0.width > $0.height }
                let verticals = grid.filter { $0.height > $0.width }
                func coordinates(_ values: [CGFloat]) -> [CGFloat] {
                    var result: [CGFloat] = []
                    for value in values.sorted() where result.last.map({ value - $0 > 1.5 }) ?? true {
                        result.append(value)
                    }
                    return result
                }
                let xs = coordinates(verticals.map(\.midX)), ys = coordinates(horizontals.map(\.midY) + fills.flatMap { [$0.minY, $0.maxY] }).reversed()
                let tops = Array(ys)
                guard (3...16).contains(xs.count), (3...80).contains(tops.count) else { return nil }
                let rect = CGRect(x: xs[0], y: tops.last!, width: xs.last! - xs[0], height: tops[0] - tops.last!)
                guard rect.width > 30, rect.height > 20 else { return nil }
                let own = lines.filter { rect.insetBy(dx: -1, dy: -1).contains($0.rect) }
                guard !own.isEmpty,
                      !paints.contains(where: { paint in
                          (paint.image || paint.shaded == true || (!paint.rectangular && !paint.vertices.isEmpty))
                              && rect.insetBy(dx: 3, dy: 3).intersects(paint.rect)
                      }) else { return nil }
                func edge(_ x: CGFloat, bottom: CGFloat, top: CGFloat) -> Bool {
                    if fills.contains(where: { fill in
                        (abs(fill.minX - x) <= 1.5 || abs(fill.maxX - x) <= 1.5)
                            && fill.minY <= bottom + 2 && fill.maxY >= top - 2
                    }) { return true }
                    let pieces = verticals.filter { abs($0.midX - x) <= 1.5 }.sorted { $0.minY < $1.minY }
                    var covered = bottom
                    for piece in pieces where piece.maxY >= covered - 2 {
                        if piece.minY > covered + 2 { return false }
                        covered = max(covered, piece.maxY)
                        if covered >= top - 2 { return true }
                    }
                    return false
                }
                var rows: [[PageTable.Cell]] = []
                for row in 0..<(tops.count - 1) {
                    let top = tops[row], bottom = tops[row + 1]
                    guard edge(xs[0], bottom: bottom, top: top), edge(xs.last!, bottom: bottom, top: top) else { return nil }
                    var cells: [PageTable.Cell] = [], column = 0
                    while column < xs.count - 1 {
                        var end = column + 1
                        while end < xs.count - 1 && !edge(xs[end], bottom: bottom, top: top) { end += 1 }
                        let cell = CGRect(x: xs[column] + 2, y: bottom + 2,
                                          width: xs[end] - xs[column] - 4, height: top - bottom - 4)
                        guard cell.width > 0, cell.height > 0 else { return nil }
                        let text = readCell(cell).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                        let native = own.filter { cell.insetBy(dx: -0.5, dy: -0.5).contains($0.rect) }
                            .sorted { abs($0.rect.midY - $1.rect.midY) < 1 ? $0.rect.minX < $1.rect.minX : $0.rect.midY > $1.rect.midY }
                        cells.append(PageTable.Cell(content: TableReader.nativeContent(native, plain: text), rect: cell, columns: end - column))
                        column = end
                    }
                    rows.append(cells)
                }
                let extracted = own.map(\.text).joined()
                let read = rows.flatMap { $0.map(\.text) }.joined()
                // Reading cells may change their order, but it may neither lose nor invent a
                // character. Every native character inside the grid must occur exactly once.
                func signature(_ text: String) -> [UInt32] {
                    text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(\.value).sorted()
                }
                guard signature(extracted) == signature(read), rows.allSatisfy({ !$0.allSatisfy { $0.text.isEmpty } }) else { return nil }
                let header = paints.contains { paint in
                    paint.filled && paint.rectangular && abs(paint.rect.minY - tops[1]) <= 3
                        && abs(paint.rect.maxY - tops[0]) <= 3 && paint.rect.width > 20
                        && paint.rect.intersects(rect)
                }
                return PageTable(rect: rect, rows: rows, headerRows: header ? 1 : 0)
        }
    }
}
