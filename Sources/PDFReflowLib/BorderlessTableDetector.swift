import CoreGraphics
import Foundation

/// Borderless text tables with capital column headings (#121): FAA page 131's `CATEGORY` /
/// `LIMIT LOAD FACTOR` table, set in body type without rules or bands. Extraction has already
/// split rows PDFKit merged across the column gap (`NativeTextReader.splitBorderlessTables`);
/// this reads the lines as a grid.
///
/// The heading is two or more untagged lines on one baseline, all in capitals, each at most
/// fifteen ems wide and two to ten ems apart. The table's rows are the baselines beneath it,
/// each within 1.8 ems of the one above, among the lines overlapping the heading's width widened
/// by an em; the first line of another size, a tagged, monospaced or wider line ends them.
/// Each line belongs to the column whose heading it overlaps most (or lies nearest), and at
/// least an em of whitespace must separate every column's lines from the next column's, so
/// prose running across the gap is never a row. A baseline with text in two or more columns
/// starts a row; one with text in a single column continues the row above (a label on two
/// lines). Every body row fills every column, and there are at least two. Anything else keeps
/// its ordinary reflow. Row headers are not inferred: FAA tags these first cells `TD`.
enum BorderlessTableDetector {
    static func tables(in lines: [TextLine]) -> [ShadedTableDetector.Table] {
        func sameRow(_ a: TextLine, _ b: TextLine) -> Bool { abs(a.rect.minY - b.rect.minY) <= 1.5 }
        func usable(_ line: TextLine, size: CGFloat) -> Bool {
            line.structure == nil && !line.monospaced && abs(line.fontSize - size) <= size * 0.15
                && line.rect.width <= size * 15
        }
        var tables: [ShadedTableDetector.Table] = []
        var used: [TextLine] = []
        for first in lines.sorted(by: { $0.rect.minY > $1.rect.minY || $0.rect.minY == $1.rect.minY && $0.rect.minX < $1.rect.minX }) {
            let size = max(4, first.fontSize)
            guard !used.contains(first), usable(first, size: size), NativeTextReader.isCapitalHeading(first.text) else { continue }
            // The heading: capital lines to the right on the same baseline, each gap two to ten ems.
            var heading = [first]
            for line in lines.filter({ sameRow($0, first) && $0.rect.minX > first.rect.maxX }).sorted(by: { $0.rect.minX < $1.rect.minX }) {
                let gap = line.rect.minX - heading[heading.count - 1].rect.maxX
                guard usable(line, size: size), NativeTextReader.isCapitalHeading(line.text), gap >= size * 2, gap <= size * 10 else { break }
                heading.append(line)
            }
            guard heading.count >= 2 else { continue }
            let window = (heading[0].rect.minX - size, heading[heading.count - 1].rect.maxX + size)
            var rows: [[TextLine]] = []
            for line in lines.filter({ $0.rect.maxX > window.0 && $0.rect.minX < window.1 && $0.rect.minY < first.rect.minY - 1.5 })
                .sorted(by: { $0.rect.minY > $1.rect.minY }) {
                if let last = rows.last?.first, sameRow(last, line) { rows[rows.count - 1].append(line) } else { rows.append([line]) }
            }
            // Lines on the heading's own baseline that are not part of it end the search.
            guard !lines.contains(where: { sameRow($0, first) && !heading.contains($0) && $0.rect.maxX > window.0 && $0.rect.minX < window.1 }) else { continue }
            var body: [[TextLine]] = []
            var previous = first.rect.minY
            for row in rows {
                guard previous - row[0].rect.minY <= size * 1.8, row.allSatisfy({ usable($0, size: size) }) else { break }
                body.append(row)
                previous = row[0].rect.minY
            }
            // Columns by heading overlap, then an em of whitespace between neighbouring columns.
            func column(_ line: TextLine) -> Int {
                let overlaps = heading.map { min($0.rect.maxX, line.rect.maxX) - max($0.rect.minX, line.rect.minX) }
                if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 { return best }
                return heading.indices.min { abs(heading[$0].rect.midX - line.rect.midX) < abs(heading[$1].rect.midX - line.rect.midX) }!
            }
            var grid: [[[TextLine]]] = []
            for row in body {
                if Set(row.map(column)).count >= 2 {
                    var cells = [[TextLine]](repeating: [], count: heading.count)
                    for line in row { cells[column(line)].append(line) }
                    grid.append(cells)
                } else if !grid.isEmpty {
                    for line in row { grid[grid.count - 1][column(line)].append(line) }
                } else { break }
            }
            guard grid.count >= 2, grid.allSatisfy({ $0.allSatisfy { !$0.isEmpty } }) else { continue }
            let owned = grid.flatMap { $0.flatMap { $0 } } + heading
            let separated = (0..<(heading.count - 1)).allSatisfy { gap in
                let left = owned.filter { column($0) <= gap }.map(\.rect.maxX).max()!
                let right = owned.filter { column($0) > gap }.map(\.rect.minX).min()!
                return right - left >= size
            }
            guard separated else { continue }
            let result = ShadedTableDetector.Table(
                bounds: union(owned.map(\.rect)), columns: heading.count,
                rows: [.init(cells: heading.map { .init(lines: [$0], span: 1) }, header: true)]
                    + grid.map { .init(cells: $0.map { .init(lines: $0.sorted { $0.rect.minY > $1.rect.minY }, span: 1) }, header: false) })
            used += owned
            tables.append(result)
        }
        return tables
    }
}
