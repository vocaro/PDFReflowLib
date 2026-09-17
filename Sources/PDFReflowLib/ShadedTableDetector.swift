import CoreGraphics
import Foundation

/// Text tables drawn as shaded bands and the rules between them (#54): the Fed's entity/overview
/// and regulation tables. Band edges and horizontal rules that cross the block supply the rows;
/// the lines' shared left edges supply the columns. A row whose text starts in the first column
/// and either runs across the next column or sits on a full-width band of its own is a section
/// row; a first row with text in at least two columns is the header, and its cells may span the
/// empty columns beside them. Anything less regular (text outside the bands, a body line
/// straddling a column boundary, fewer than two columns or two body rows) is not a table here
/// and keeps its ordinary reflow. Numeric alignment and cell semantics beyond this grid are not
/// inferred.
enum ShadedTableDetector {
    struct Table: Equatable {
        struct Cell: Equatable {
            var lines: [TextLine]
            var span: Int
            /// A body row's first cell that names the row (#121); header-row cells are headers
            /// through their row.
            var header = false
        }
        struct Row: Equatable {
            var cells: [Cell]
            var header: Bool
        }
        var bounds: CGRect
        var columns: Int
        var rows: [Row]
        /// The table's caption inside its box, directly above its first row (#113): title lines
        /// set larger than the cells, then the description beneath them in the cells' size.
        /// Both are empty when the lines above the table do not read that way.
        var title: [TextLine] = []
        var description: [TextLine] = []
        var lines: [TextLine] { rows.flatMap { $0.cells.flatMap(\.lines) } }
        /// The caption and the cells: every line the table block reads.
        var ownedLines: [TextLine] { title + description + lines }
    }

    /// The caption rows directly above a table's first row, scanned upward: description lines in
    /// the cells' size, then title lines at least 15% larger. Each row holds one line, every line
    /// shares the title's left edge, and consecutive lines are no further apart than two body
    /// sizes. The scan stops at the first line that fits none of this (a box's own prose above
    /// the table), and yields no caption without a title line or with more description than a
    /// short introduction.
    static func caption(above lines: [TextLine], bodySize: CGFloat) -> (title: [TextLine], description: [TextLine]) {
        var title: [TextLine] = [], description: [TextLine] = []
        for line in lines.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            // A line sharing its height with another is a row of several cells or columns.
            guard !lines.contains(where: { $0 != line && $0.rect.minY < line.rect.midY && $0.rect.maxY > line.rect.midY }) else { break }
            let previous = (title.first ?? description.first)
            if let previous, line.rect.minY - previous.rect.maxY > bodySize * 2 { break }
            if line.fontSize >= bodySize * 1.15 {
                if let first = title.first ?? description.first, abs(first.rect.minX - line.rect.minX) > bodySize { break }
                if let first = title.first, abs(first.fontSize - line.fontSize) > 0.5 { break }
                title.insert(line, at: 0)
            } else if title.isEmpty, abs(line.fontSize - bodySize) <= bodySize * 0.1,
                      description.first.map({ abs($0.rect.minX - line.rect.minX) <= bodySize }) ?? true {
                description.insert(line, at: 0)
            } else { break }
        }
        guard !title.isEmpty, title.count <= 3, description.count <= 6 else { return ([], []) }
        return (title, description)
    }

    /// Row headers (#121): the first cell of each body row names that row when at least two body
    /// rows are labelled that way. A label holds a letter, differs from every other row's label,
    /// and has a value beside it in the same row; a row whose first cell is empty (Fed page 47's
    /// `U.S. Treasury, General Account`, on the liabilities side only) keeps an ordinary cell but
    /// does not cost the others theirs. Any labelled row without a value, or two rows with the same
    /// label, leaves every cell a data cell. Section rows (one spanning cell) and header rows are
    /// not body rows. The Fed tags every such first-column cell of the tables this detector reads
    /// `TH /Scope /Row` (pages 46, 47, 64, 82, 83, 109, 120, 121); page 97's single body row, whose
    /// first cell is a list of payment kinds under its column header, is tagged `TD`.
    /// PDFKit reports every Fed table font as the same face, so typography (a bold label column)
    /// cannot confirm it.
    static func rowHeaders(_ rows: [Table.Row]) -> [Table.Row] {
        let body = rows.indices.filter { !rows[$0].header && rows[$0].cells.count > 1 }
        let labelled = body.filter { !rows[$0].cells[0].lines.isEmpty }
        func label(_ index: Int) -> String {
            rows[index].cells[0].lines.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        guard labelled.count >= 2,
              labelled.allSatisfy({ index in rows[index].cells.dropFirst().contains { !$0.lines.isEmpty } }),
              labelled.allSatisfy({ label($0).contains(where: \.isLetter) }),
              Set(labelled.map(label)).count == labelled.count else { return rows }
        var result = rows
        for index in labelled { result[index].cells[0].header = true }
        return result
    }

    static func tables(in page: PageContent, lines: [TextLine]) -> [Table] {
        let body = max(4, LayoutReconstructor.bodySize(lines))
        return clusters(page.tints, distance: 4).compactMap { hull -> Table? in
            let cluster = page.tints.filter { hull.contains($0) }
            // The box drawn around the table is not one of its bands.
            let members = cluster.filter { tint in
                !(tint.width * tint.height >= hull.width * hull.height * 0.9
                  && cluster.contains { $0 != tint && tint.contains($0) })
            }
            guard members.count >= 2, let bandTop = members.map(\.maxY).max(),
                  let bandBottom = members.map(\.minY).min() else { return nil }
            // Row edges: every band edge, and every y where horizontal rules cover half the width.
            var rules: [(y: CGFloat, width: CGFloat)] = []
            for rule in page.separators where rule.width > rule.height && hull.insetBy(dx: -4, dy: -4).intersects(rule) {
                if let index = rules.firstIndex(where: { abs($0.y - rule.midY) <= 1.5 }) {
                    rules[index].width += rule.width
                } else { rules.append((rule.midY, rule.width)) }
            }
            let ruleEdges = rules.filter { $0.width >= hull.width * 0.5 }.map(\.y)
            // Rows reach beyond the bands only where rules subdivide the rest of the box; the
            // title and introduction above a table's first band stay outside it.
            let top = ruleEdges.contains { $0 > bandTop + 1.5 } ? hull.maxY : bandTop
            let bottom = ruleEdges.contains { $0 < bandBottom - 1.5 } ? hull.minY : bandBottom
            let edges = ([top, bottom] + members.flatMap { [$0.minY, $0.maxY] } + ruleEdges).filter { $0 >= bottom && $0 <= top }
            var boundaries: [CGFloat] = []
            for edge in edges.sorted(by: >) where boundaries.last.map({ $0 - edge > 1.5 }) ?? true {
                boundaries.append(edge)
            }
            let inside = lines.filter {
                hull.insetBy(dx: -2, dy: -2).contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY))
                    && $0.rect.midY <= top && $0.rect.midY >= bottom
            }
            guard !inside.isEmpty else { return nil }
            var rowLines: [[TextLine]] = []
            var rowRects: [CGRect] = []
            for (rowTop, rowBottom) in zip(boundaries, boundaries.dropFirst()) {
                let row = inside.filter { $0.rect.midY <= rowTop && $0.rect.midY > rowBottom }
                guard !row.isEmpty else { continue }
                rowLines.append(row)
                rowRects.append(CGRect(x: hull.minX, y: rowBottom, width: hull.width, height: rowTop - rowBottom))
            }
            guard rowLines.count >= 3, rowLines.reduce(0, { $0 + $1.count }) == inside.count else { return nil }
            // Columns: left edges shared by at least two rows and by half of them.
            var lefts: [(x: CGFloat, rows: Set<Int>)] = []
            for (index, row) in rowLines.enumerated() {
                for line in row {
                    if let existing = lefts.firstIndex(where: { abs($0.x - line.rect.minX) <= body }) {
                        lefts[existing].rows.insert(index)
                    } else { lefts.append((line.rect.minX, [index])) }
                }
            }
            var columns = lefts.filter { $0.rows.count >= max(2, rowLines.count / 2) }.map(\.x).sorted()
            func column(of line: TextLine) -> Int {
                columns.lastIndex(where: { $0 <= line.rect.minX + body }) ?? 0
            }
            // A line straddles when it runs past the start of the next column's text.
            func straddles(_ line: TextLine, _ index: Int) -> Bool {
                index + 1 < columns.count && line.rect.maxX > columns[index + 1] + body * 0.5
            }
            func ownBand(_ index: Int) -> Bool {
                let rowRect = rowRects[index]
                return members.contains { band in
                    band.width >= hull.width * 0.9 && band.minY <= rowRect.midY && band.maxY >= rowRect.midY
                        && !members.contains { $0 != band && $0.width < hull.width * 0.9 && $0.minY <= rowRect.midY && $0.maxY >= rowRect.midY }
                }
            }
            // A header may sit on one band per column instead of one band across the table (Fed
            // page 97's `Credit transfer` / `Debit transfer`, #121): at least two bands through
            // the row, each narrower than the table, side by side (overlapping by at most a body
            // size), together spanning 90% of its width. Every band holds some of the row's lines
            // and no other row's, and every line of the row lies on one of them, so the column
            // bands of a body beneath (which hold many rows) never qualify.
            func ownColumnBands(_ index: Int) -> Bool {
                let rowRect = rowRects[index]
                func centre(_ line: TextLine) -> CGPoint { CGPoint(x: line.rect.midX, y: line.rect.midY) }
                let bands = members.filter { $0.minY <= rowRect.midY && $0.maxY >= rowRect.midY }.sorted { $0.minX < $1.minX }
                guard bands.count >= 2, bands.allSatisfy({ $0.width < hull.width * 0.9 }),
                      zip(bands, bands.dropFirst()).allSatisfy({ $1.minX >= $0.maxX - body }),
                      bands[bands.count - 1].maxX - bands[0].minX >= hull.width * 0.9 else { return false }
                let others = rowLines.indices.filter { $0 != index }.flatMap { rowLines[$0] }
                return bands.allSatisfy { band in
                    rowLines[index].contains { band.contains(centre($0)) } && !others.contains { band.contains(centre($0)) }
                } && rowLines[index].allSatisfy { line in bands.contains { $0.contains(centre(line)) } }
            }
            // PDFKit can merge a narrow cell with the cell beside it into one line ("Y Bank
            // Holding Companies"). One pair of columns may read as one when such a line spans
            // exactly those two, as the source's spanning header does; a line running across
            // more columns is a figure grid this detector does not read.
            if columns.count >= 3 {
                for row in rowLines where Set(row.map { column(of: $0) }).count >= 2 {
                    if let crossed = row.first(where: { straddles($0, column(of: $0)) }) {
                        let index = column(of: crossed)
                        // A header cell may span further; it does not decide the body's columns.
                        guard index + 2 >= columns.count || crossed.rect.maxX <= columns[index + 2] + body * 0.5 else { continue }
                        columns.remove(at: index + 1)
                        break
                    }
                }
            }
            guard columns.count >= 2 else { return nil }
            enum Kind { case grid, section, outside }
            var kinds: [Kind] = []
            var assignments: [[(TextLine, Int)]] = []
            for (index, row) in rowLines.enumerated() {
                // Cell lines read column by column, top to bottom.
                func precedes(_ a: (TextLine, Int), _ b: (TextLine, Int)) -> Bool {
                    if a.1 != b.1 { return a.1 < b.1 }
                    if a.0.rect.midY != b.0.rect.midY { return a.0.rect.midY > b.0.rect.midY }
                    return a.0.rect.minX < b.0.rect.minX
                }
                let assigned = row.map { ($0, column(of: $0)) }.sorted(by: precedes)
                assignments.append(assigned)
                // A section row is one first-column line that runs across the columns or sits
                // on a full-width band of its own. Anything else that crosses a column boundary
                // (a title, an introduction) is outside the grid.
                let crossing = assigned.contains { straddles($0.0, $0.1) }
                if assigned.allSatisfy({ $0.1 == 0 }) && (crossing || ownBand(index)) {
                    kinds.append(assigned.count == 1 ? .section : .outside)
                } else {
                    kinds.append(crossing && index > 0 ? .outside : .grid)
                }
            }
            // The table is the run of grid rows with the section rows between them; a section
            // row is body-sized. Leading and trailing text outside that run reflows normally;
            // a crossing line inside it means the grid was misread.
            // A trailing line in one column ("(continued on next page)") is a note, not a row.
            var last = kinds.lastIndex(of: .grid)
            while let end = last, end > 0, kinds[end] == .grid, Set(assignments[end].map(\.1)).count == 1,
                  assignments[end].allSatisfy({ $0.1 > 0 }) {
                kinds[end] = .outside
                last = kinds[..<end].lastIndex(of: .grid)
            }
            guard let first = kinds.firstIndex(of: .grid), let last else { return nil }
            let sizes = (first...last).filter { kinds[$0] == .grid }.flatMap { rowLines[$0].map(\.fontSize) }.sorted()
            let bodySize = sizes[sizes.count / 2]
            // The header is the first grid row when it sits on a band of its own (or one band per
            // column) with text in two columns; a continuation page's first body row does not.
            // Section rows may precede the body only when there is no header.
            let spansTable = Set(assignments[first].map(\.1)).count >= 2 && first < last
            let columnBandHeader = spansTable && !ownBand(first) && ownColumnBands(first)
            let headerRow = spansTable && (ownBand(first) || columnBandHeader)
            var start = first
            while !headerRow, start > 0, kinds[start - 1] == .section,
                  abs(rowLines[start - 1][0].fontSize - bodySize) <= bodySize * 0.3 { start -= 1 }
            guard !(start...last).contains(where: { kinds[$0] == .outside
                || kinds[$0] == .section && abs(rowLines[$0][0].fontSize - bodySize) > bodySize * 0.3 }) else { return nil }
            var result: [Table.Row] = []
            for index in start...last {
                let assigned = assignments[index]
                if kinds[index] == .section {
                    result.append(.init(cells: [.init(lines: assigned.map(\.0), span: columns.count)], header: false))
                    continue
                }
                let header = index == first && headerRow
                var cells = [[TextLine]](repeating: [], count: columns.count)
                for (line, column) in assigned { cells[column].append(line) }
                if header {
                    // An empty header column belongs to the spanning header cell before it.
                    var merged: [Table.Cell] = []
                    for cell in cells {
                        if cell.isEmpty, !merged.isEmpty { merged[merged.count - 1].span += 1 }
                        else { merged.append(.init(lines: cell, span: 1)) }
                    }
                    result.append(.init(cells: merged, header: true))
                } else {
                    result.append(.init(cells: cells.map { .init(lines: $0, span: 1) }, header: false))
                }
            }
            // A header on column bands was read as the first body row before #121; it still counts
            // toward the two rows a table needs, so Fed page 97's header over one body row stays
            // a table and nothing else is newly accepted.
            let bodyRows = result.filter { (!$0.header || columnBandHeader) && $0.cells.count > 1 }
            guard bodyRows.count >= 2, bodyRows.contains(where: { $0.cells.filter { !$0.lines.isEmpty }.count >= 2 }) else { return nil }
            result = rowHeaders(result)
            let caption = caption(above: rowLines[..<start].flatMap { $0 }, bodySize: bodySize)
            return Table(bounds: union(Array(rowRects[start...last])), columns: columns.count, rows: result,
                         title: caption.title, description: caption.description)
        }
    }
}
