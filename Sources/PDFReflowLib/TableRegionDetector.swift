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
    /// carry numbers. A single label underline followed by prose is not a table (#36, ported
    /// from the coordination branch, #229).
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
                guard let line = LayoutReconstructor.underlinedLine(rule, in: page.lines),
                      !line.text.contains("=") else { return false }
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
                  below.filter({ $0.contains { $0.text.contains { $0.isNumber } } }).count * 2 >= below.count
            else { continue }
            covered.formUnion(top...bottom)
            let block = rows[top...bottom].flatMap { $0.map(\.rect) }
                + rules.filter { rule in rows[top...bottom].contains { row in
                    row.contains { LayoutReconstructor.underlinedLine(rule, in: page.lines)?.rect == $0.rect } } }
            regions.append(union(block).insetBy(dx: -2, dy: -2).intersection(page.bounds))
        }
        return regions
    }

    /// Blocks of lines the page set as the rows of a table, which keep their line breaks instead
    /// of joining into one paragraph (#137, #210).
    ///
    /// A table whose cells the extractor hands back inside one line per printed row — the FAA
    /// handbook's service-volume table, the 9/11 report's abbreviation list, the Census paper's
    /// Table 6 — is not a crop and is not prose. Every word of it is already read; only the
    /// printed row is lost, and losing the row is what makes the reading "Class Altitudes T
    /// 12,000' and below 25 L Below 18,000' 40". Keeping each printed row as its own block keeps
    /// the words and gives the rows back, which is what those issues ask for. It is not table
    /// markup: the column associations still live in the row's own text.
    ///
    /// A block is a run of at least three rows on one left edge, in one type size, stepping down
    /// at one leading. Ordinary wrapped prose has exactly that shape, so a run becomes rows only
    /// where the page states a column boundary of its own, in one of two ways:
    ///
    /// - **A cell the extractor kept apart.** PDFKit splits a printed row at a wide gap, so a row
    ///   whose first cell is short enough comes back as two lines side by side. Two such rows
    ///   agreeing on where the second cell starts state the boundary (`CAPPS` and `FDNY` on page
    ///   429 of the 9/11 report; five rows on page 430). Merged rows reaching across that
    ///   boundary are the proof that the two sides are one line of text and not two columns of a
    ///   two-column page, which never share a line.
    /// - **A column of numbers on a common right edge.** At least three rows ending on one right
    ///   edge with a digit, and two rows in three ending with a digit across the whole run: a
    ///   justified paragraph shares that right edge but does not end line after line in a number.
    ///
    /// A second cell is admitted only where it begins inside the width the run's own opening
    /// cells reach. The facing column of a two-column page begins past the far edge of every line
    /// on this side, so it is never taken for a cell; a wrapped cell, which begins well inside
    /// that width, keeps its place in the run.
    static func rowBlocks(in lines: [TextLine], body: CGFloat) -> [CGRect] {
        let candidates = lines.filter { !$0.monospaced && !$0.text.isEmpty }
        guard candidates.count >= 3 else { return [] }
        // One printed row per baseline, top down, each row's pieces left to right.
        var printed: [[Int]] = []
        for index in candidates.indices.sorted(by: { candidates[$0].rect.minY > candidates[$1].rect.minY }) {
            if let last = printed.indices.last, candidates[printed[last][0]].sharesRow(with: candidates[index]) {
                printed[last].append(index)
            } else { printed.append([index]) }
        }
        for row in printed.indices { printed[row].sort { candidates[$0].rect.minX < candidates[$1].rect.minX } }
        var rowOf: [Int: Int] = [:]
        for (row, pieces) in printed.enumerated() { for piece in pieces { rowOf[piece] = row } }
        var regions: [CGRect] = []
        var used: Set<Int> = []
        // Each line in turn anchors a run, topmost and leftmost first. A page that prints two
        // tables side by side shares their baselines, so the second table is anchored on its own
        // opening cell rather than on the row it happens to share.
        let anchors = candidates.indices.sorted {
            candidates[$0].rect.minY == candidates[$1].rect.minY
                ? candidates[$0].rect.minX < candidates[$1].rect.minX
                : candidates[$0].rect.minY > candidates[$1].rect.minY
        }
        for index in anchors where !used.contains(index) {
            let anchor = candidates[index]
            let start = rowOf[index]!
            let size = Int(anchor.fontSize.rounded())
            let edge = anchor.rect.minX
            // The opening cell of each row, and the width those cells reach, which grows as the
            // run is followed down the page.
            var leads: [Int] = []
            var reach = anchor.rect.maxX
            var step: CGFloat?
            for row in printed[start...] {
                guard let lead = row.first(where: { !used.contains($0)
                                                    && candidates[$0].rect.minX >= edge - body * 0.6
                                                    && Int(candidates[$0].fontSize.rounded()) == size }) else { break }
                let rect = candidates[lead].rect
                // The row opens on the run's edge, or it is a cell wrapped inside the block —
                // one that begins inside the width the run has reached so far. The facing column
                // of a two-column page begins past that width, and ends the run.
                guard abs(rect.minX - edge) <= body * 0.6
                        || (rect.minX > edge && rect.minX < reach) else { break }
                if let last = leads.last {
                    let drop = candidates[last].rect.minY - rect.minY
                    guard drop > 0, drop <= body * 2 else { break }
                    if let step, abs(drop - step) > body * 0.35 { break }
                    step = step ?? drop
                }
                leads.append(lead)
                reach = max(reach, rect.maxX)
            }
            guard leads.count >= 3 else { continue }
            let window = leads.map { candidates[$0].rect.maxX }.max()!
            let rows = leads.map { lead -> [Int] in
                [lead] + candidates.indices.filter { other in
                    other != lead && candidates[other].rect.minX >= candidates[lead].rect.maxX
                        && candidates[other].rect.minX < window
                        && candidates[lead].sharesRow(with: candidates[other])
                }.sorted { candidates[$0].rect.minX < candidates[$1].rect.minX }
            }
            guard statesAColumn(rows, in: candidates, body: body) else { continue }
            used.formUnion(rows.flatMap { $0 })
            regions.append(union(rows.flatMap { $0 }.map { candidates[$0].rect }))
        }
        return regions
    }

    /// Whether the page states a column boundary inside a run of rows: a cell the extractor kept
    /// apart on two rows that merged rows reach across, or a column of numbers on one right edge.
    private static func statesAColumn(_ rows: [[Int]], in lines: [TextLine], body: CGFloat) -> Bool {
        // A cell is set in the table's own type. The magazine column that runs beside a
        // photograph's caption also puts two pieces on one baseline, and it is the caption's
        // smaller type that says the second piece is another block of the page, not a cell.
        let split = rows.filter { row in
            row.count > 1 && Int(lines[row[1]].fontSize.rounded()) == Int(lines[row[0]].fontSize.rounded())
        }
        let whole = rows.filter { $0.count == 1 }
        if split.count >= 2, whole.count >= 2 {
            let edges = split.map { lines[$0[1]].rect.minX }.sorted()
            if let edge = edges.first, edges.last! - edge <= body * 0.6,
               whole.count(where: { lines[$0[0]].rect.maxX > edge + body }) >= 2 { return true }
        }
        func endsInDigit(_ row: [Int]) -> Bool {
            let text = lines[row.last!].text
            return text.reversed().drop(while: { "%*).\u{2019}'\"".contains($0) || $0.isWhitespace })
                .first?.isNumber == true
        }
        let numeric = rows.filter(endsInDigit)
        guard numeric.count * 3 >= rows.count * 2 else { return false }
        let right = numeric.map { lines[$0.last!].rect.maxX }
        return right.contains { edge in right.count(where: { abs($0 - edge) <= body * 0.5 }) >= 3 }
    }
}
