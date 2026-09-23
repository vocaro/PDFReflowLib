import CoreGraphics
import Foundation
import PDFKit

/// Reads the tables a page draws as cells, from the white the page leaves between its columns
/// (#210).
///
/// `TableRegionDetector` answers two other questions about the same pages, and neither is this
/// one. `underlinedColumnRegions` decides that a borderless statistical table should be preserved
/// as a picture (#36); `rowBlocks` decides that a table whose cells arrive inside one line per
/// printed row should keep its printed rows rather than join into a paragraph (#137). Both leave
/// the association a table exists to state — which value stands under which heading — in the
/// source rendering. This reader recovers that association, and where it succeeds the crop is not
/// made and the rows are not text.
///
/// **A table's columns are the white that runs down all of its rows.** A printed row's ink is the
/// run of its own shows, from the content stream, merged where they touch: the page's own record
/// of where it put glyphs, which is finer than the lines PDFKit hands back and does not depend on
/// where PDFKit chose to break a row. An x range that no row of a block puts ink in is a corridor,
/// and a block of rows with at least two corridors down it is divided into at least three columns.
/// Every row is then read against those columns rather than against its own gaps, which is what
/// makes the widest row divide correctly: `Employment, mine and plant, number 11,000 11,400 12,000
/// 12,600 13,000` leaves only 5.6 points between its values, two thirds of what the rows above
/// leave, and no per-row threshold divides both it and them.
///
/// **A cell's text is what the page reads inside the cell.** `PDFPage.selection(for:)` answers
/// with the characters in a rectangle, so the reader asks the page rather than dividing a line's
/// string at its spaces — which cannot be done, because `1.7¢/kg on lead content.` is one cell
/// with spaces in it and `United States 1,130 1,100 882 890 47,000` is six cells with the same
/// spaces between them. Every table is checked afterwards against the lines it covers: unless the
/// cells account for every non-space character of those lines, the table is declined and the page
/// keeps the reading it had. A table cannot lose a cell, and this is what enforces it.
///
/// **What is not a table.** Three conditions keep running prose out, each measured:
///
/// - *Three columns at least.* Two columns of prose facing each other across a gutter are a page's
///   layout, not a table, and the gutter is one corridor.
/// - *No column of prose.* A cell is set to its content and a column of prose is set to the
///   measure, so a column holding three or more cells of five words or longer that fill it is the
///   page's own text. Page 416 of the FAA handbook prints its NDB table in the right column of a
///   two-column page, and on geometry alone the left column's prose rows and the table's rows form
///   one four-column grid; this is what separates them.
/// - *A column of values.* A table read here is a numeric one: some column other than the first
///   must hold at least three cells and be at least two-thirds numbers. The USGS tariff table's
///   `2603.00.0010` column carries it while its `1% ad valorem.` column does not, which is the
///   right way round.
///
/// A block is also a block only while its rows keep one leading and one type size, which is what
/// separates a table from the paragraph above it: the USGS summaries set their tables at the body's
/// 11.0-point leading and leave 21.7 points above the first row.
enum TableReader {
    /// Every table the page draws. `shows` are the page's own text-showing operations, `rules`
    /// its thin painted rules, and `page` answers for the text inside a cell.
    ///
    /// Asking the page for a cell's text is a PDFKit text read, so the whole reading is taken
    /// inside the extraction gate (#21). The gate is not recursive: a caller never wraps this.
    static func tables(on page: PDFPage, lines: [TextLine], shows: [NativeSpacingReader.Evidence],
                       rules: [CGRect], filledCells: [CGRect] = []) throws -> [PageTable] {
        let rows = printedRows(lines)
        guard rows.count >= 4 else { return [] }
        let inks = rows.map { ink(of: $0, shows: shows) }
        return try NativeTextReader.withExtractionLock {
            var result: [PageTable] = []
            var index = 0
            while index < rows.count {
                guard let block = block(from: index, rows: rows, inks: inks) else { index += 1; continue }
                if let table = read(block, rows: rows, inks: inks, rules: rules, on: page) {
                    result.append(table)
                }
                index = block.upperBound
            }
            // Existing table ownership is retained: replacing a larger admitted table with a
            // painted subgrid can return its remaining lines to a crop and lose readable text.
            let painted = PaintedCellTableReader.tables(lines: lines, cells: filledCells) {
                page.selection(for: $0)?.string ?? ""
            }
            result += painted.filter { table in !result.contains { $0.rect.intersects(table.rect) } }
            return result.sorted { ($0.rect.maxY, -$0.rect.minX) > ($1.rect.maxY, -$1.rect.minX) }
        }
    }

    // MARK: - Rows and their ink

    /// One printed row per baseline, top down, each row's pieces left to right. A raised note
    /// marker shares its row, which is why the rows are read from the lines rather than from the
    /// shows' own baselines: `Reserves` and the `6` above it are one printed row.
    private static func printedRows(_ lines: [TextLine]) -> [[TextLine]] {
        var rows: [[TextLine]] = []
        for line in lines.filter({ !$0.text.isEmpty }).sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            if let last = rows.last?.first, last.sharesRow(with: line) { rows[rows.count - 1].append(line) }
            else { rows.append([line]) }
        }
        for row in rows.indices { rows[row].sort { $0.rect.minX < $1.rect.minX } }
        return rows
    }

    /// The x ranges a printed row puts ink in: its shows, merged where they meet. A show whose
    /// glyph advances the reader could not total has no end and states nothing.
    private static func ink(of row: [TextLine], shows: [NativeSpacingReader.Evidence]) -> [ClosedRange<CGFloat>] {
        let low = row.map(\.rect.minY).min()!, high = row.map(\.rect.maxY).max()!
        let mine = shows.filter { show in
            guard let end = show.end, end > show.origin.x else { return false }
            return show.origin.y >= low - 0.5 && show.origin.y <= high
        }.sorted { $0.origin.x < $1.origin.x }
        var merged: [ClosedRange<CGFloat>] = []
        for show in mine {
            let range = show.origin.x...show.end!
            if let last = merged.last, range.lowerBound - last.upperBound <= 0.5 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        return merged
    }

    private static func size(of row: [TextLine]) -> CGFloat { row.map(\.fontSize).max() ?? 0 }
    private static func top(of row: [TextLine]) -> CGFloat { row.map(\.rect.maxY).max() ?? 0 }

    // MARK: - The block

    /// The run of rows starting at `start` that the page set as one block: one type size, and one
    /// leading, which the first step states and every later step keeps within a third of a body.
    /// A run of fewer than four rows is never a table, so the search moves on.
    private static func block(from start: Int, rows: [[TextLine]], inks: [[ClosedRange<CGFloat>]]) -> Range<Int>? {
        let body = size(of: rows[start])
        guard body > 0, !inks[start].isEmpty else { return nil }
        var end = start + 1
        var step: CGFloat?
        while end < rows.count {
            guard !inks[end].isEmpty, abs(size(of: rows[end]) - body) <= body * 0.1 else { break }
            let drop = top(of: rows[end - 1]) - top(of: rows[end])
            guard drop > 0, drop <= body * 2 else { break }
            if let step, abs(drop - step) > body * 0.35 { break }
            step = step ?? drop
            end += 1
        }
        return end - start >= 4 ? start..<end : nil
    }

    // MARK: - The columns

    /// The x ranges no row of the block puts ink in, at least `least` wide. Half a body is the
    /// narrowest corridor a table leaves between two of its columns when its widest row is set;
    /// a word space is a third of that.
    private static func corridors(_ range: Range<Int>, inks: [[ClosedRange<CGFloat>]],
                                  least: CGFloat) -> [ClosedRange<CGFloat>] {
        let low = range.compactMap { inks[$0].first?.lowerBound }.min() ?? 0
        let high = range.compactMap { inks[$0].last?.upperBound }.max() ?? 0
        guard high > low else { return [] }
        var white: [ClosedRange<CGFloat>] = [low...high]
        for row in range {
            var next: [ClosedRange<CGFloat>] = []
            for piece in white {
                var remaining = [piece]
                for mark in inks[row] {
                    var step: [ClosedRange<CGFloat>] = []
                    for part in remaining {
                        if mark.upperBound <= part.lowerBound || mark.lowerBound >= part.upperBound {
                            step.append(part); continue
                        }
                        if mark.lowerBound > part.lowerBound { step.append(part.lowerBound...mark.lowerBound) }
                        if mark.upperBound < part.upperBound { step.append(mark.upperBound...part.upperBound) }
                    }
                    remaining = step
                }
                next += remaining
            }
            white = next.filter { $0.upperBound - $0.lowerBound >= least }
            if white.isEmpty { return [] }
        }
        return white.sorted { $0.lowerBound < $1.lowerBound }
    }

    // MARK: - Reading one block

    private static func read(_ range: Range<Int>, rows: [[TextLine]], inks: [[ClosedRange<CGFloat>]],
                             rules: [CGRect], on page: PDFPage) -> PageTable? {
        let body = size(of: rows[range.lowerBound])
        // A heading the page set across several columns closes the corridors under it, which is
        // what a spanning heading is. Up to two such rows are lifted off the top of the block and
        // read against the columns the rows below state; more than two and the block is not a
        // table with a heading but a block whose rows do not agree.
        var best: (offset: Int, corridors: [ClosedRange<CGFloat>])?
        for offset in 0...min(2, range.count - 4) {
            let found = corridors((range.lowerBound + offset)..<range.upperBound, inks: inks, least: body * 0.5)
            if found.count > (best?.corridors.count ?? 1) { best = (offset, found) }
        }
        guard let (offset, corridors) = best, corridors.count >= 2 else { return nil }
        // The column boundaries: the middle of each corridor, between the block's own edges.
        let low = range.compactMap { inks[$0].first?.lowerBound }.min()!
        let high = range.compactMap { inks[$0].last?.upperBound }.max()!
        let edges = [low - 1] + corridors.map { ($0.lowerBound + $0.upperBound) / 2 } + [high + 1]
        let columns = edges.count - 1
        guard columns >= 3 else { return nil }

        var table = PageTable(rect: .null, rows: [], headerRows: 0)
        var byColumn: [[PageTable.Cell]] = Array(repeating: [], count: columns)
        for index in range {
            let row = rows[index]
            let low = row.map(\.rect.minY).min()!, high = row.map(\.rect.maxY).max()!
            var cells: [PageTable.Cell] = []
            // The column each cell opens in, which says whether the next mark belongs to the cell
            // already open or to a column after it.
            var opens: [Int] = []
            var next = 0
            for mark in inks[index] {
                let box = CGRect(x: mark.lowerBound, y: low,
                                 width: mark.upperBound - mark.lowerBound, height: high - low)
                let first = edges.firstIndex { mark.lowerBound < $0 }.map { $0 - 1 } ?? columns - 1
                let last = edges.lastIndex { mark.upperBound > $0 } ?? 0
                let start = max(0, min(first, columns - 1)), stop = max(start, min(last, columns - 1))
                // A mark inside the columns the open cell already covers is part of that cell: a
                // cell holds word spaces wide enough for the page to draw its words apart, and a
                // number the page draws in two instructions is still one number.
                if let open = cells.indices.last, !cells[open].rect.isNull,
                   opens[open] <= start, opens[open] + cells[open].columns > stop {
                    cells[open].rect = cells[open].rect.union(box)
                    continue
                }
                // A mark reaching back into a column already closed is not a grid.
                guard start >= next else { return nil }
                while next < start { cells.append(empty(columns: 1)); opens.append(next); next += 1 }
                cells.append(PageTable.Cell(content: InlineText(), rect: box, columns: stop - start + 1))
                opens.append(start)
                next = stop + 1
            }
            while next < columns { cells.append(empty(columns: 1)); opens.append(next); next += 1 }
            guard cells.reduce(0, { $0 + $1.columns }) == columns else { return nil }
            for cell in cells.indices where !cells[cell].rect.isNull {
                cells[cell].content = content(in: cells[cell].rect, row: row, on: page)
                byColumn[opens[cell]].append(cells[cell])
            }
            table.rows.append(cells)
            table.rect = table.rect.union(union(row.map(\.rect)))
        }
        table.headerRows = max(offset, headerRows(range, rows: rows, rules: rules, body: body))
        guard table.rows.count - table.headerRows >= 3 else { return nil }
        guard admits(table, byColumn: byColumn, edges: edges, rows: rows, range: range, body: body) else { return nil }
        join(wrappedLabelsIn: &table, width: edges[1] - edges[0])
        return table
    }

    /// A label too long for its column, which the page wrapped onto the row above its values.
    ///
    /// `Stocks, refined, held by U.S. producers, consumers, and metal` stands on its own printed
    /// row and `exchanges, yearend 118 117 84 127 70` on the next; they are one row of the table.
    /// A row states that it is the first half of one when it puts ink in no column but the first
    /// and that ink reaches the column's edge, which is why it wrapped. A group row holding only
    /// a label — `Production:`, `Exports:` — states the opposite: it stops a fifth of the way
    /// across, and it stays the row it is.
    private static func join(wrappedLabelsIn table: inout PageTable, width: CGFloat) {
        var row = table.rows.count - 1
        while row > table.headerRows {
            defer { row -= 1 }
            let above = table.rows[row - 1]
            guard let first = above.first, first.columns == 1, !first.rect.isNull,
                  first.rect.width >= width * 0.8, !first.text.isEmpty,
                  above.dropFirst().allSatisfy(\.rect.isNull),
                  let opening = table.rows[row].first, opening.columns == 1, !opening.text.isEmpty
            else { continue }
            table.rows[row][0].content = InlineText(elements:
                first.content.elements + InlineText(" ").elements + opening.content.elements)
            table.rows[row][0].rect = first.rect.union(opening.rect)
            table.rows.remove(at: row - 1)
            row -= 1
        }
    }

    private static func empty(columns: Int) -> PageTable.Cell {
        PageTable.Cell(content: InlineText(), rect: .null, columns: columns)
    }

    /// What a cell holds.
    ///
    /// Where the page's own extracted lines divide on the cell's edges — the label column of the
    /// USGS salient-statistics table is one line per row — the cell is those lines' content, which
    /// carries the spacing repair, the styles and the links the rest of the pipeline gives them.
    /// Where they do not, because one line spans several cells, the cell is the plain characters
    /// `PDFPage.selection(for:)` reads inside the rectangle. The rectangle is opened by half a
    /// point on each side so a glyph ending exactly on it is not dropped, and the answer is
    /// trimmed: a cell's trailing space is the page's setting, not its content.
    private static func content(in rect: CGRect, row: [TextLine], on page: PDFPage) -> InlineText {
        let query = rect.insetBy(dx: -0.5, dy: -0.5)
        let plain = (page.selection(for: query)?.string ?? "")
            .replacingOccurrences(of: "\u{FFFC}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inside = row.filter { $0.rect.minX >= query.minX && $0.rect.maxX <= query.maxX }
            .sorted { $0.rect.minX < $1.rect.minX }
        return nativeContent(inside, plain: plain)
    }

    /// Shared by ruled grids: preserve complete native line content whenever its characters
    /// account for the independently read cell selection.
    static func nativeContent(_ inside: [TextLine], plain: String) -> InlineText {
        guard !inside.isEmpty,
              compact(inside.map(\.text).joined(separator: " ")) == compact(plain) else {
            return InlineText(plain)
        }
        var joined = inside[0].content
        for line in inside.dropFirst() { joined.append(InlineText(" ")); joined.append(line.content) }
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How many rows at the top of the block the page set as its column headings: the last row
    /// among the block's first three under which the page paints a thin rule. A statistical table
    /// underlines its headings instead of ruling its cells, which is the same evidence #36 reads;
    /// only the first three rows are consulted, because a rule above a total row is not a heading.
    private static func headerRows(_ range: Range<Int>, rows: [[TextLine]], rules: [CGRect],
                                   body: CGFloat) -> Int {
        var count = 0
        for offset in 0..<min(3, range.count) {
            let row = rows[range.lowerBound + offset]
            let low = row.map(\.rect.minY).min()!
            // A rule underlining a row is drawn against the row's baseline, which stands inside
            // the box PDFKit reports: the USGS summaries' year headings are underlined 2.4 points
            // above the bottom of their own line box. The band is the bottom of the box and a
            // little either side of it, which no rule belonging to the row above or below reaches
            // at these leadings.
            let underlined = rules.contains { rule in
                rule.midY <= low + body * 0.3 && rule.midY >= low - body * 0.9
                    && row.contains { rule.maxX >= $0.rect.minX && rule.minX <= $0.rect.maxX }
            }
            if underlined { count = offset + 1 }
        }
        return count
    }

    // MARK: - What is not a table

    private static func admits(_ table: PageTable, byColumn: [[PageTable.Cell]], edges: [CGFloat],
                               rows: [[TextLine]], range: Range<Int>, body: CGFloat) -> Bool {
        // A column of prose: one whose cells fill it again and again. A table's widest labels
        // reach the column's edge too — three of the sixteen rows of the USGS salient-statistics
        // table run to within a tenth of it — so what says prose is not that some cells fill the
        // column but that most of them do. Every one of the six rows of the FAA handbook's left
        // text column fills it; three of twenty-four of the USGS label column do.
        for (index, cells) in byColumn.enumerated() {
            let width = edges[index + 1] - edges[index]
            let filled = cells.filter { !$0.text.isEmpty }
            let prose = filled.count { cell in
                cell.rect.width >= width * 0.85 && cell.text.split(separator: " ").count >= 5
            }
            if prose >= 3, prose * 2 >= filled.count { return false }
        }
        // A column of values: some column after the first, holding three cells at least, that is
        // two-thirds numbers.
        let values = byColumn.dropFirst().contains { cells in
            let filled = cells.filter { !$0.text.isEmpty }
            return filled.count >= 3 && filled.count(where: { isValue($0.text) }) * 3 >= filled.count * 2
        }
        guard values else { return false }
        // A row of labels: most rows name something in the first column.
        guard byColumn[0].count(where: { !$0.text.isEmpty }) * 2 >= table.rows.count else { return false }
        // A grid, not a scattering. A table fills its cells: the three USGS tables fill 78%, 90%
        // and 98% of theirs, and the algebra book's worked-example tables 60% to 85%, counting a
        // group row's empty value cells against them. Page 424 of that book letters a right
        // triangle — `A`, `B`, `x`, `63°`, `7.6` around the figure — and those labels stand on
        // four rows that divide at four columns and fill 7 cells of 16. A drawing's lettering is
        // not a table, and how little of the grid it fills is what says so.
        let cells = table.rows.reduce(0) { $0 + $1.count }
        let filled = table.rows.reduce(0) { $0 + $1.count { !$0.text.isEmpty } }
        guard filled * 2 >= cells else { return false }
        // A caption is not a cell. Page 207 of the FAA handbook sets `Figure 8-4. Look at the
        // chart…` over two printed rows beneath a three-row altimeter-setting table, in the
        // column beside it: the four rows divide at four columns and half their cells are
        // filled, and the caption became two cells of the table it captions. A block holding a
        // line the page opened as a figure or table label is that figure's, not a table.
        guard !table.rows.contains(where: { $0.contains { LayoutReconstructor.isCaption($0.text) } })
        else { return false }
        // The cells must account for the block's text. A table that lost a cell is not a table,
        // and the page keeps the reading it had.
        let read = table.rows.flatMap { $0.map(\.text) }.joined()
        let printed = range.flatMap { rows[$0].map(\.text) }.joined()
        return compact(read) == compact(printed)
    }

    /// Whether a cell holds a value rather than a phrase: a number, a dash standing for zero, or
    /// a number an estimate mark or a note marker is set against. `e740`, `(2)`, `7100,000` and
    /// `—` are values; `Korea, Republic of` and `1% ad valorem.` are not.
    static func isValue(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: " ()*†‡"))
        if stripped.isEmpty { return false }
        if stripped.allSatisfy({ "—–-\u{2014}\u{2013}".contains($0) }) { return true }
        guard stripped.contains(where: \.isNumber) else { return false }
        return stripped.count(where: \.isLetter) <= 1
    }

    /// A reading with its spacing removed, for comparing what the cells read against what the
    /// page printed. PDFKit's own line text and its answer inside a rectangle differ in their
    /// spaces — a rectangle holds no line break, and a line carries the space the reader repaired
    /// into it — and the table is judged on characters, not on where the spaces fell.
    private static func compact(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }
}
