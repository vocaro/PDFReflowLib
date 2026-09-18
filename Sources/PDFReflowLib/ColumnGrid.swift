import CoreGraphics
import Foundation

/// Borderless tables whose columns only their alignment draws (#150, #137): Census's numeric
/// tables under a header and a rule, and FAA page 410's VOR/VORTAC service volumes. No rule
/// separates their cells, no band shades their rows and their headings are not in capitals, so
/// neither `ShadedTableDetector` nor `BorderlessTableDetector` reads them, and PDFKit returns most
/// of their rows as one line (`rnkswp05 0.8861 0.9620`).
///
/// The evidence is the column itself. A table's body is a run of baselines at no more than 1.8
/// ems' leading, in one size, whose pieces fall into columns:
///
/// - Columns are the ink between channels at least 0.6 em wide that stay clear through every
///   baseline of the body, and at least twice as wide as any gap inside a cell. Where numbers stand
///   a word space apart (Census Table 8's `0.114 0.081 1.407`), a column whose last piece on every
///   baseline is a number, those numbers sharing a right edge, splits off that stack of numbers.
/// - Every column is flush left or flush right down the body, and at most fifteen ems wide.
/// - A baseline with text in the first column opens a row; one without continues the open row
///   (a wrapped cell, and the value set on its last line: FAA's `Within the conterminous 48
///   states` / `only, between 14,500 and 17,999'` `100`), continuing at most one cell that already
///   holds text. Every row then fills every column, and there are at least three.
/// - One column holds a single number in every row; no column opens every row with a list marker
///   (a bullet or `a)`), and no baseline holds dot leaders.
/// - A header stands directly above the body: one to three baselines at the body's leading and
///   size, inside the table's width. Its lowest row places text in at least two columns, with a
///   heading over every numeric column, and does not read as a body row (first-column text over
///   numbers), so a body row heads nothing while years may head their columns. A higher
///   row's text ending on a column's flush edge, as the heading beneath it does, continues that
///   heading (`Distance` above `(Miles)`); other text spans the columns of the row below that lie
///   nearer it than any other heading in its row (`d Metric` over `Ascore Dscore Sscore`).
/// - The grid ends at its edges: text within two ems of them on half its body's baselines, and
///   nowhere above or below, continues it (a label column too wide to be one).
///
/// Candidates are three or more pieces ending in a number at one right edge (`regions`). Worked
/// examples beside their comments, contents lists, glossaries and rosters have no numeric column or
/// no header and keep their reflow (see `measurements/aligned-column-tables`). Pieces are glyph
/// words during extraction (`NativeTextReader`, which splits the rows PDFKit merged) and lines
/// during layout (`BorderlessTableDetector.alignedTables`), which read the same grid.
enum ColumnGrid {
    /// Text on one baseline: a word measured from its glyphs, or a whole line.
    struct Piece: Equatable {
        var rect: CGRect
        var text: String
        var size: CGFloat
        /// The caller's index for the piece (its line, or its word within a line).
        var id = 0
    }

    /// Where a piece belongs: its table row (header rows first) and the columns it spans.
    struct Placement: Equatable {
        var row: Int
        var columns: Range<Int>
    }

    /// A table read from baselines: `placements` runs parallel to the baselines given, one entry
    /// per piece, nil outside the table.
    struct Grid: Equatable {
        var columns: Int
        var headerRows: Int
        var rows: Int
        var placements: [[Placement?]]
    }

    static let channel: CGFloat = 0.6
    static let widestCell: CGFloat = 15
    static let flush: CGFloat = 0.25
    static let leading: CGFloat = 1.8
    static let minimumRows = 3
    static let maximumHeaderRows = 3

    private static let numberPattern = try! NSRegularExpression(pattern: #"^[-−–+]?[$(]?\d(?:[\d.,:/]*\d)?[%′'’)]?$"#)
    private static let markerPattern = try! NSRegularExpression(pattern: #"^(?:\(?\d{1,3}[.)]|\(?[A-Za-z][.)]|[•●○◦▪■□►▸–—-])$"#)

    /// A number as a table sets it: digits with separators, a sign, a currency or percent sign,
    /// a closing parenthesis or prime. A sentence's closing period is not part of one.
    static func isNumber(_ text: String) -> Bool {
        numberPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func isMarker(_ text: String) -> Bool {
        markerPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func lastToken(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
    }

    /// Baselines of pieces, top to bottom, each sorted left to right.
    static func baselines(_ pieces: [Piece]) -> [[Piece]] {
        var rows: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.rect.minY > $1.rect.minY || $0.rect.minY == $1.rect.minY && $0.rect.minX < $1.rect.minX }) {
            if let last = rows.last?.first, abs(last.rect.minY - piece.rect.minY) <= 1.5 {
                rows[rows.count - 1].append(piece)
            } else { rows.append([piece]) }
        }
        return rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }

    /// A candidate table: the baselines within reach of a stack of numbers ending pieces at one
    /// right edge on at least three baselines, restricted to the pieces of the window around it.
    struct Region {
        var rows: [[Piece]]
        /// The pieces on those baselines outside the window.
        var beside: [Piece] = []
    }

    /// Candidate regions on a page. `capped` windows are runs of columns of pieces each at most
    /// fifteen ems wide (layout, where cells are already separate lines, so a page column of prose
    /// beside the table is left out); uncapped windows are the one column of pieces holding the
    /// stack (extraction, where a merged row spans the table).
    static func regions(in pieces: [Piece], capped: Bool) -> [Region] {
        let rows = baselines(pieces)
        struct Stack { var edge: CGFloat; var size: CGFloat; var members: [Piece] }
        var stacks: [Stack] = []
        for row in rows {
            // In layout a stack is made of cells; a justified prose line ending in a number at the
            // table's edge is not one.
            for piece in row where isNumber(lastToken(piece.text))
                && (!capped || piece.rect.width <= max(4, piece.size) * widestCell) {
                let em = max(4, piece.size)
                if let index = stacks.lastIndex(where: { stack in
                    abs(stack.edge - piece.rect.maxX) <= em * flush && abs(stack.size - piece.size) <= em * 0.15
                        && stack.members.last!.rect.minY - piece.rect.minY <= em * leading * 2
                        && stack.members.last!.rect.minY - piece.rect.minY > 1.5
                }) {
                    stacks[index].members.append(piece)
                } else {
                    stacks.append(Stack(edge: piece.rect.maxX, size: piece.size, members: [piece]))
                }
            }
        }
        var regions: [Region] = []
        var covered: [CGRect] = []
        for stack in stacks where stack.members.count >= minimumRows {
            let em = max(4, stack.size)
            let top = stack.members.first!.rect.minY + em * leading * CGFloat(maximumHeaderRows)
            let bottom = stack.members.last!.rect.minY - em * leading * 2
            let reach = rows.filter { $0[0].rect.minY <= top + 0.5 && $0[0].rect.minY >= bottom - 0.5 }
            // Columns of the stack's own baselines: ink between channels at least 0.6 em wide. A
            // title or heading above the stack does not decide the window.
            let span = rows.filter { $0[0].rect.minY <= stack.members.first!.rect.minY + 0.5
                && $0[0].rect.minY >= stack.members.last!.rect.minY - 0.5 }
            // A band also records its widest piece: in layout a band of cells qualifies, however
            // many columns a word space apart it holds, and a band holding a prose line does not.
            var bands: [(minX: CGFloat, maxX: CGFloat, widest: CGFloat)] = []
            for piece in span.flatMap({ $0 }).sorted(by: { $0.rect.minX < $1.rect.minX }) {
                if let last = bands.last, piece.rect.minX - last.maxX < em * channel {
                    bands[bands.count - 1] = (last.minX, max(last.maxX, piece.rect.maxX), max(last.widest, piece.rect.width))
                } else { bands.append((piece.rect.minX, piece.rect.maxX, piece.rect.width)) }
            }
            guard let home = bands.firstIndex(where: { $0.minX <= stack.edge && $0.maxX >= stack.edge - 0.5 }) else { continue }
            var first = home, last = home
            if capped {
                func cells(_ band: Int) -> Bool { bands[band].widest <= em * widestCell }
                while first > 0, cells(first - 1) { first -= 1 }
                while last + 1 < bands.count, cells(last + 1) { last += 1 }
            }
            let window = CGRect(x: bands[first].minX, y: bottom, width: bands[last].maxX - bands[first].minX, height: top - bottom + em)
            guard !covered.contains(where: { $0.intersects(window) && $0.contains(CGPoint(x: stack.edge - 0.5, y: stack.members[0].rect.midY)) }) else { continue }
            covered.append(window)
            func inside(_ piece: Piece) -> Bool { piece.rect.maxX > window.minX + 0.25 && piece.rect.minX < window.maxX - 0.25 }
            let kept = reach.map { $0.filter(inside) }.filter { !$0.isEmpty }
            regions.append(Region(rows: kept, beside: reach.flatMap { $0.filter { !inside($0) } }))
        }
        return regions
    }

    // MARK: - Body

    private struct Body {
        var bands: [(minX: CGFloat, maxX: CGFloat)]
        var flushLeft: [Bool]
        var flushRight: [Bool]
        /// Each baseline's pieces' columns, and each baseline's table row within the body.
        var columns: [[Int]]
        var rowOfBaseline: [Int]
        var rows: Int
        /// The columns holding one number in every row.
        var numeric: [Bool]
    }

    private static func body(_ rows: ArraySlice<[Piece]>, em: CGFloat) -> Body? {
        let rows = Array(rows)
        // Dot leaders join an entry to its value (a contents list, Our Flag's size chart), which
        // `TableRegionDetector` preserves; they are not cells.
        guard !rows.contains(where: { row in
            let text = row.map(\.text).joined(separator: " ")
            return text.contains(". . .") || text.contains("....")
        }) else { return nil }
        // Wide channels: clear through every baseline, at least 0.6 em.
        var bands: [(minX: CGFloat, maxX: CGFloat)] = []
        for piece in rows.flatMap({ $0 }).sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let last = bands.last, piece.rect.minX - last.maxX < em * channel {
                bands[bands.count - 1].maxX = max(last.maxX, piece.rect.maxX)
            } else { bands.append((piece.rect.minX, piece.rect.maxX)) }
        }
        var wide = Array(repeating: true, count: max(0, bands.count - 1))
        func inside(_ piece: Piece, _ band: (minX: CGFloat, maxX: CGFloat)) -> Bool {
            piece.rect.minX >= band.minX - 0.5 && piece.rect.maxX <= band.maxX + 0.5
        }
        // A stack of numbers a word space apart: the last piece of every baseline in a column is a
        // number, the numbers share a right edge, and other text on those baselines ends before
        // the stack begins.
        var index = 0
        while index < bands.count {
            let perRow = rows.map { $0.filter { inside($0, bands[index]) } }.filter { !$0.isEmpty }
            let lasts = perRow.map { $0[$0.count - 1] }
            let rest = perRow.flatMap { $0.dropLast() }
            if perRow.allSatisfy({ $0.count >= 2 }), lasts.allSatisfy({ isNumber($0.text) }),
               let right = lasts.map(\.rect.maxX).max(), let rightLeast = lasts.map(\.rect.maxX).min(),
               right - rightLeast <= em * flush,
               let restEnd = rest.map(\.rect.maxX).max(), let start = lasts.map(\.rect.minX).min(), restEnd < start {
                let band = bands[index]
                bands[index] = (band.minX, restEnd)
                bands.insert((start, band.maxX), at: index + 1)
                wide.insert(false, at: index)
                continue
            }
            index += 1
        }
        guard bands.count >= 2, bands.allSatisfy({ $0.maxX - $0.minX <= em * widestCell }) else { return nil }
        func column(_ piece: Piece) -> Int? { bands.firstIndex { inside(piece, $0) } }
        var columns: [[Int]] = []
        for row in rows {
            let placed = row.compactMap(column)
            guard placed.count == row.count else { return nil }
            columns.append(placed)
        }
        // A wide channel is at least twice the widest gap inside a cell.
        var inCell: CGFloat = 0
        for (row, placed) in zip(rows, columns) {
            for index in row.indices.dropLast() where placed[index] == placed[index + 1] {
                inCell = max(inCell, row[index + 1].rect.minX - row[index].rect.maxX)
            }
        }
        for gap in wide.indices where wide[gap] && bands[gap + 1].minX - bands[gap].maxX < inCell * 2 { return nil }
        // Rows: first-column text opens one; a baseline without continues it, adding to at most
        // one cell that already holds text.
        var filled: [[Bool]] = []
        var rowOfBaseline: [Int] = []
        for placed in columns {
            let present = Set(placed)
            if present.contains(0) {
                filled.append(bands.indices.map(present.contains))
            } else {
                guard !filled.isEmpty else { return nil }
                let open = filled[filled.count - 1]
                guard present.filter({ open[$0] }).count <= 1 else { return nil }
                for column in present { filled[filled.count - 1][column] = true }
            }
            rowOfBaseline.append(filled.count - 1)
        }
        guard filled.count >= minimumRows, filled.allSatisfy({ $0.allSatisfy { $0 } }) else { return nil }
        // Every column flush left or flush right.
        var flushLeft: [Bool] = [], flushRight: [Bool] = []
        for band in bands.indices {
            let cells = zip(rows, columns).compactMap { row, placed -> (CGFloat, CGFloat)? in
                let mine = row.indices.filter { placed[$0] == band }
                guard !mine.isEmpty else { return nil }
                return (mine.map { row[$0].rect.minX }.min()!, mine.map { row[$0].rect.maxX }.max()!)
            }
            let left = cells.map(\.0).max()! - cells.map(\.0).min()! <= em * flush
            let right = cells.map(\.1).max()! - cells.map(\.1).min()! <= em * flush
            guard left || right else { return nil }
            flushLeft.append(left); flushRight.append(right)
        }
        // A numeric column: one number in every row. No column of list markers.
        func cells(_ band: Int) -> [[Piece]] {
            var result = [[Piece]](repeating: [], count: filled.count)
            for (baseline, (row, placed)) in zip(rows, columns).enumerated() {
                for index in row.indices where placed[index] == band { result[rowOfBaseline[baseline]].append(row[index]) }
            }
            return result
        }
        func opensWithMarker(_ cell: [Piece]) -> Bool {
            cell.first?.text.split(whereSeparator: \.isWhitespace).first.map { isMarker(String($0)) } ?? false
        }
        let numeric = bands.indices.map { band in cells(band).allSatisfy { $0.count == 1 && isNumber($0[0].text) } }
        guard numeric.contains(true), !bands.indices.contains(where: { band in cells(band).allSatisfy(opensWithMarker) })
        else { return nil }
        return Body(bands: bands, flushLeft: flushLeft, flushRight: flushRight, columns: columns,
                    rowOfBaseline: rowOfBaseline, rows: filled.count, numeric: numeric)
    }

    // MARK: - Header

    private static func centre(_ pieces: ArraySlice<Piece>) -> CGFloat {
        (pieces.map(\.rect.minX).min()! + pieces.map(\.rect.maxX).max()!) / 2
    }

    /// A header baseline's cells: runs of pieces less than 0.6 em apart, each divided where its
    /// pieces' centres fall over different columns and every part is centred on its column
    /// within half an em (Census's `d metric l metric`, `Ascore Dscore Sscore`).
    private static func groups(_ row: [Piece], bands: [(minX: CGFloat, maxX: CGFloat)], em: CGFloat) -> [Range<Int>] {
        var segments: [Range<Int>] = []
        var start = 0
        for index in row.indices.dropFirst() where row[index].rect.minX - row[index - 1].rect.maxX >= em * channel {
            segments.append(start..<index); start = index
        }
        segments.append(start..<row.count)
        func nearest(_ x: CGFloat) -> Int {
            bands.indices.min { a, b in
                max(0, bands[a].minX - x, x - bands[a].maxX) < max(0, bands[b].minX - x, x - bands[b].maxX)
            }!
        }
        var result: [Range<Int>] = []
        for segment in segments {
            var parts: [Range<Int>] = []
            var partStart = segment.lowerBound
            for index in segment.dropFirst() where nearest(row[index].rect.midX) != nearest(row[index - 1].rect.midX) {
                parts.append(partStart..<index); partStart = index
            }
            parts.append(partStart..<segment.upperBound)
            let centred = parts.allSatisfy { part in
                let band = bands[nearest(centre(row[part]))]
                return abs(centre(row[part]) - (band.minX + band.maxX) / 2) <= em * 0.5
            }
            result += parts.count >= 2 && centred ? parts : [segment]
        }
        return result
    }

    /// The column a header cell aligns with: its left edge on a flush-left column's, or its right
    /// edge on a flush-right column's.
    private static func aligned(_ pieces: ArraySlice<Piece>, _ body: Body, em: CGFloat) -> Int? {
        let minX = pieces.map(\.rect.minX).min()!, maxX = pieces.map(\.rect.maxX).max()!
        return body.bands.indices.first { band in
            body.flushRight[band] && abs(maxX - body.bands[band].maxX) <= em * flush
                || body.flushLeft[band] && abs(minX - body.bands[band].minX) <= em * flush
        }
    }

    /// Header rows above a body, top to bottom, each a list of (piece range, columns); a row
    /// whose cells all continue the headings beneath it is merged into that row.
    private static func header(_ above: [[Piece]], body: Body, bodyTop: CGFloat, em: CGFloat)
        -> [[(pieces: Range<Int>, columns: Range<Int>, baseline: Int)]]? {
        let bands = body.bands
        let left = bands[0].minX - em, right = bands[bands.count - 1].maxX + em
        var rows: [[(pieces: Range<Int>, columns: Range<Int>, baseline: Int)]] = []
        var below = bodyTop
        for baseline in above.indices.reversed() {
            guard rows.count < maximumHeaderRows else { break }
            let row = above[baseline]
            let y = row.map(\.rect.minY).min()!
            guard y - below > 0, y - below <= em * leading,
                  row.allSatisfy({ abs($0.size - em) <= em * 0.15 && $0.rect.minX >= left && $0.rect.maxX <= right }) else { break }
            let parts = groups(row, bands: bands, em: em)
            if rows.isEmpty {
                // The lowest header row: each cell in the column it aligns with or overlaps most,
                // cells in one column joined.
                var cells: [(pieces: Range<Int>, columns: Range<Int>, baseline: Int)] = []
                for part in parts {
                    let minX = row[part].map(\.rect.minX).min()!, maxX = row[part].map(\.rect.maxX).max()!
                    let overlaps = bands.map { min($0.maxX, maxX) - max($0.minX, minX) }
                    let chosen = aligned(row[part], body, em: em)
                        ?? (overlaps.max()! > 0 ? overlaps.indices.max { overlaps[$0] < overlaps[$1] }!
                            : bands.indices.min { abs((bands[$0].minX + bands[$0].maxX) / 2 - centre(row[part])) < abs((bands[$1].minX + bands[$1].maxX) / 2 - centre(row[part])) }!)
                    if let last = cells.last, last.columns.lowerBound == chosen {
                        cells[cells.count - 1].pieces = last.pieces.lowerBound..<part.upperBound
                    } else {
                        guard cells.last.map({ $0.columns.lowerBound < chosen }) ?? true else { return nil }
                        cells.append((part, chosen..<(chosen + 1), baseline))
                    }
                }
                // Every column of numbers has a heading, and the row does not read as a body row
                // (text in the first column, numbers over every column of numbers): a partial or
                // whole body row above the body heads nothing. Years head their columns (`2023`)
                // over an empty label heading.
                func heading(_ column: Int) -> ArraySlice<Piece>? {
                    cells.first { $0.columns.contains(column) }.map { row[$0.pieces] }
                }
                let numeric = body.numeric.indices.filter { body.numeric[$0] }
                guard cells.count >= 2, numeric.allSatisfy({ heading($0) != nil }),
                      heading(0) == nil || !numeric.allSatisfy({ heading($0)?.allSatisfy { isNumber($0.text) } == true })
                else { return nil }
                rows.insert(cells, at: 0)
            } else {
                // A higher row: a cell continues the heading beneath it when both end on that
                // column's flush edge, within a tenth of an em (`Distance` over `(Miles)`, both
                // on the distance column's right edge); the others share the columns beneath them
                // by nearest centre.
                let beneath = rows[0]
                let covered = Set(beneath.flatMap { Array($0.columns) })
                func continued(_ part: Range<Int>) -> Int? {
                    let minX = row[part].map(\.rect.minX).min()!, maxX = row[part].map(\.rect.maxX).max()!
                    let tight = em * 0.1
                    return beneath.first { cell in
                        guard cell.columns.count == 1 else { return false }
                        let column = cell.columns.lowerBound, band = bands[column]
                        let lower = above[cell.baseline][cell.pieces]
                        return body.flushRight[column] && abs(maxX - band.maxX) <= tight
                                && abs(lower.map(\.rect.maxX).max()! - band.maxX) <= tight
                            || body.flushLeft[column] && abs(minX - band.minX) <= tight
                                && abs(lower.map(\.rect.minX).min()! - band.minX) <= tight
                    }?.columns.lowerBound
                }
                var stacked: [(Range<Int>, Int)] = []
                var spanning: [Range<Int>] = []
                for part in parts {
                    if let column = continued(part) { stacked.append((part, column)) } else { spanning.append(part) }
                }
                let free = covered.subtracting(stacked.map(\.1)).sorted()
                var cells: [(pieces: Range<Int>, columns: Range<Int>, baseline: Int)] = stacked.map { ($0.0, $0.1..<($0.1 + 1), baseline) }
                let centres = spanning.map { centre(row[$0]) }
                var valid = true
                for (index, part) in spanning.enumerated() {
                    let mine = free.filter { column in
                        let middle = (bands[column].minX + bands[column].maxX) / 2
                        return centres.indices.min { abs(centres[$0] - middle) < abs(centres[$1] - middle) } == index
                    }
                    guard let first = mine.first, let last = mine.last, last - first + 1 == mine.count,
                          centres[index] >= bands[first].minX, centres[index] <= bands[last].maxX else { valid = false; break }
                    cells.append((part, first..<(last + 1), baseline))
                }
                guard valid else { break }
                cells.sort { $0.columns.lowerBound < $1.columns.lowerBound }
                guard zip(cells, cells.dropFirst()).allSatisfy({ $0.columns.upperBound <= $1.columns.lowerBound }) else { break }
                rows.insert(cells, at: 0)
            }
            below = y
        }
        return rows.isEmpty ? nil : rows
    }

    // MARK: - Grids

    /// The tables among baselines (top to bottom, each sorted left to right). `beside` are the
    /// pieces near those baselines outside them: a grid with text within two ems of its edge on at
    /// least half its body's baselines, text found only beside the table's own rows, continues past
    /// that edge (a label column too wide to be a column) and is no table. A page column beside a
    /// table runs on above or below it.
    static func grids(in rows: [[Piece]], beside: [Piece] = []) -> [Grid] {
        var result: [Grid] = []
        var start = 0
        while start < rows.count {
            let em = max(4, rows[start].map(\.size).max()!)
            func follows(_ upper: Int, _ lower: Int) -> Bool {
                let gap = rows[upper][0].rect.minY - rows[lower][0].rect.minY
                return gap > 1.5 && gap <= em * leading && rows[lower].allSatisfy { abs($0.size - em) <= em * 0.15 }
            }
            var found: (end: Int, body: Body)?
            var end = start
            while end + 1 < rows.count, follows(end, end + 1) {
                end += 1
                if end - start + 1 >= minimumRows, let body = body(rows[start...end], em: em) { found = (end, body) }
            }
            guard rows[start].allSatisfy({ abs($0.size - em) <= em * 0.15 }), let (last, body) = found,
                  let header = header(Array(rows[..<start]), body: body, bodyTop: rows[start][0].rect.minY, em: em)
            else { start += 1; continue }
            let placed = rows[start...last].flatMap { $0 }
            let minX = placed.map(\.rect.minX).min()!, maxX = placed.map(\.rect.maxX).max()!
            let top = header.first?.first.map { rows[$0.baseline][0].rect.minY } ?? rows[start][0].rect.minY
            let bottom = rows[last][0].rect.minY
            let near = beside.filter { $0.rect.maxX > minX - em * 2 && $0.rect.minX < maxX + em * 2 }
            let continued = rows[start...last].filter { row in near.contains { abs($0.rect.minY - row[0].rect.minY) <= 1.5 } }
            guard near.contains(where: { $0.rect.minY > top + 1.5 || $0.rect.minY < bottom - 1.5 })
                    || continued.count * 2 < last - start + 1 else { start += 1; continue }
            var placements = rows.map { [Placement?](repeating: nil, count: $0.count) }
            // A heading row whose every cell continues a cell of the row beneath (same columns)
            // shares that row's table row: `Distance` above `(Miles)` is one heading.
            var next = 0
            for (position, cells) in header.enumerated() {
                let baseline = cells[0].baseline
                for cell in cells {
                    for index in cell.pieces { placements[baseline][index] = Placement(row: next, columns: cell.columns) }
                }
                let stacks = position + 1 < header.count && cells.allSatisfy { cell in
                    header[position + 1].contains { $0.columns == cell.columns }
                }
                if !stacks { next += 1 }
            }
            let headerRows = next
            for baseline in start...last {
                for (index, column) in body.columns[baseline - start].enumerated() {
                    placements[baseline][index] = Placement(row: headerRows + body.rowOfBaseline[baseline - start], columns: column..<(column + 1))
                }
            }
            result.append(Grid(columns: body.bands.count, headerRows: headerRows, rows: headerRows + body.rows, placements: placements))
            start = last + 1
        }
        return result
    }
}
