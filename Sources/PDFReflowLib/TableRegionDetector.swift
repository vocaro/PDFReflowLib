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
    ///   two-column page, which never share a line. A run the page filled to one measure states
    ///   no boundary this way, however: see `isSetToAMeasure` (#268).
    /// - **A column of numbers on a common right edge.** At least three rows ending on one right
    ///   edge with a digit, and two rows in three ending with a digit across the whole run: a
    ///   justified paragraph shares that right edge but does not end line after line in a number.
    ///
    /// A second cell is admitted only where it begins inside the width the run's own opening
    /// cells reach. The facing column of a two-column page begins past the far edge of every line
    /// on this side, so it is never taken for a cell; a wrapped cell, which begins well inside
    /// that width, keeps its place in the run.
    static func rowBlocks(in lines: [TextLine], body: CGFloat, rightToLeft: Bool = false) -> [CGRect] {
        // Where a row and a cell begin and end. Writing that runs right to left begins each of
        // them at its right edge, so the page number an entry ends on is the leftmost piece of
        // its printed row, not the rightmost (#41). Every comparison below is written through
        // these, and reads exactly as it did for a left-to-right page.
        func leading(_ rect: CGRect) -> CGFloat { rightToLeft ? rect.maxX : rect.minX }
        func trailing(_ rect: CGRect) -> CGFloat { rightToLeft ? rect.minX : rect.maxX }
        func isBefore(_ first: CGFloat, _ second: CGFloat) -> Bool { rightToLeft ? first > second : first < second }
        func advanced(_ edge: CGFloat, by distance: CGFloat) -> CGFloat { rightToLeft ? edge - distance : edge + distance }
        // A page's printed rows run along its writing. Where every line of the group was set at
        // one quarter turn, the run is read in that frame — a sideways table's rows step across
        // the page, not down it — by giving each line its own upright rectangle and reading it as
        // upright from there. The regions handed back are the page's own, because that is what a
        // crop is tested against (#276, #263).
        let original = lines.filter { !$0.monospaced && !$0.text.isEmpty }
        let frame = LayoutReconstructor.ownFrame(of: lines)
        let candidates = original.map { line -> TextLine in
            var upright = line
            upright.rect = frame(line)
            upright.turn = .upright
            return upright
        }
        guard candidates.count >= 3 else { return [] }
        // One printed row per baseline, top down, each row's pieces left to right.
        var printed: [[Int]] = []
        for index in candidates.indices.sorted(by: { candidates[$0].rect.minY > candidates[$1].rect.minY }) {
            if let last = printed.indices.last, candidates[printed[last][0]].sharesRow(with: candidates[index]) {
                printed[last].append(index)
            } else { printed.append([index]) }
        }
        for row in printed.indices {
            printed[row].sort { isBefore(leading(candidates[$0].rect), leading(candidates[$1].rect)) }
        }
        var rowOf: [Int: Int] = [:]
        for (row, pieces) in printed.enumerated() { for piece in pieces { rowOf[piece] = row } }
        var regions: [CGRect] = []
        var used: Set<Int> = []
        // Each line in turn anchors a run, topmost and leftmost first. A page that prints two
        // tables side by side shares their baselines, so the second table is anchored on its own
        // opening cell rather than on the row it happens to share.
        let anchors = candidates.indices.sorted {
            candidates[$0].rect.minY == candidates[$1].rect.minY
                ? isBefore(leading(candidates[$0].rect), leading(candidates[$1].rect))
                : candidates[$0].rect.minY > candidates[$1].rect.minY
        }
        for index in anchors where !used.contains(index) {
            let anchor = candidates[index]
            let start = rowOf[index]!
            let size = Int(anchor.fontSize.rounded())
            let edge = leading(anchor.rect)
            // The opening cell of each row, and the width those cells reach, which grows as the
            // run is followed down the page.
            var leads: [Int] = []
            var reach = trailing(anchor.rect)
            var step: CGFloat?
            for row in printed[start...] {
                guard let lead = row.first(where: { !used.contains($0)
                                                    && !isBefore(leading(candidates[$0].rect), advanced(edge, by: -body * 0.6))
                                                    && Int(candidates[$0].fontSize.rounded()) == size }) else { break }
                let rect = candidates[lead].rect
                // The row opens on the run's edge, or it is a cell wrapped inside the block —
                // one that begins inside the width the run has reached so far. The facing column
                // of a two-column page begins past that width, and ends the run.
                guard abs(leading(rect) - edge) <= body * 0.6
                        || (isBefore(edge, leading(rect)) && isBefore(leading(rect), reach)) else { break }
                if let last = leads.last {
                    let drop = candidates[last].rect.minY - rect.minY
                    guard drop > 0, drop <= body * 2 else { break }
                    if let step, abs(drop - step) > body * 0.35 { break }
                    // A table can share its font and margin with the paragraph below it.
                    // A larger baseline gap followed by four full-measure, wrapped prose
                    // rows ends the table; its numeric cells cannot confer row semantics on
                    // that paragraph. An indented wrapped cell does not supply this evidence.
                    if let step, leads.count >= 3, drop > step * 1.2,
                       abs(leading(rect) - edge) <= body * 0.3,
                       followsAsProse(lead, edge: edge, reach: reach, step: step) { break }
                    step = step ?? drop
                }
                leads.append(lead)
                reach = isBefore(reach, trailing(rect)) ? trailing(rect) : reach
            }
            guard leads.count >= 3 else { continue }
            let window = leads.map { trailing(candidates[$0].rect) }.max(by: isBefore)!
            let rows = leads.map { lead -> [Int] in
                [lead] + candidates.indices.filter { other in
                    other != lead && !isBefore(leading(candidates[other].rect), trailing(candidates[lead].rect))
                        && isBefore(leading(candidates[other].rect), window)
                        && candidates[lead].sharesRow(with: candidates[other])
                }.sorted { isBefore(leading(candidates[$0].rect), leading(candidates[$1].rect)) }
            }
            guard statesAColumn(rows, in: candidates, body: body, rightToLeft: rightToLeft) else { continue }
            used.formUnion(rows.flatMap { $0 })
            regions.append(union(rows.flatMap { $0 }.map { original[$0].rect }))
        }
        return regions

        func followsAsProse(_ first: Int, edge: CGFloat, reach: CGFloat, step: CGFloat) -> Bool {
            let start = rowOf[first]!
            guard start + 3 < printed.count else { return false }
            let size = candidates[first].fontSize
            var prose: [TextLine] = []
            for row in printed[start...start + 3] {
                let aligned = row.map { candidates[$0] }.filter {
                    abs(leading($0.rect) - edge) <= body * 0.3
                        && abs($0.fontSize - size) <= size * 0.05
                }
                guard aligned.count == 1, let line = aligned.first,
                      line.rect.width >= abs(reach - edge) * 0.75,
                      line.text.split(whereSeparator: { $0.isWhitespace }).count >= 5,
                      line.text.last?.isNumber != true,
                      !LayoutReconstructor.isList(line.text) else { return false }
                if let previous = prose.last {
                    guard line.text.first?.isLowercase == true,
                          abs(previous.rect.minY - line.rect.minY - step) <= max(1, step * 0.15)
                    else { return false }
                }
                prose.append(line)
            }
            return prose.last?.text.hasSuffix(".") == true
        }
    }

    /// The column headers of the tables a page draws: the lines the crop release rule leaves to
    /// their table rather than to the page's prose (#257).
    ///
    /// #255 stopped a crop from burying a line that reads as the book's own prose. The CIA Blue
    /// Book's crops preserve its statistical tables as pictures, and the lines that rule let out
    /// of them include those tables' column headers — `Number Per Cent Number Per Cent Nuntler
    /// Per Cent`, `Certain Doubtful Total Certain Doubtful Total` — which are every one of them
    /// an English word, so the word test admits them, and which beside the picture of their own
    /// table say nothing a reader can use.
    ///
    /// A header is read from two things together, because neither alone is enough.
    ///
    /// **The page set the line in a table's columns.** `rowBlocks` reads a table that still
    /// reflows, from a run of rows sharing one left edge, one type size and one leading. This
    /// book's tables offer none of that: its inherited text layer gives every printed row a size
    /// of its own — one table's rows come back at 5.6, 16.0, 9.0, 10.2 and 19.4 points — and the
    /// crop has taken the rows beneath in any case, leaving only the header band to judge. The
    /// evidence here is one row's own: the page kept its pieces apart as cells, each beginning at
    /// or after the one before it ends, and at least two other rows of the page begin a piece on
    /// the same column edge. `Evaluation | Certain Doubtful Total … | ertain Doubtful Total …`
    /// has that shape, on the edges every row of the table below stands on. A line of prose is
    /// one piece, so it states no edge; and where the extractor merges two printed lines into one
    /// row — this book paints a rule down its margin, and the tall rectangle that gives the line
    /// swallows the line below it — the second piece begins inside the first rather than after it.
    ///
    /// **The line prints one column label once per column.** Geometry alone is not enough, and
    /// the measurement says so: the magazine's three-column pages hand back their columns on
    /// shared baselines, so every row of running prose there holds pieces the page kept apart on
    /// an edge every other row states, and on geometry alone this rule buries 17,340 characters
    /// of that book's articles — two thirds of what #255 recovered from it. What a header row
    /// has and a row of prose has not is its own words: the table repeats one short label across
    /// its columns, which `printsOneColumnLabel` reads.
    static func columnHeaders(in page: PageContent, body: CGFloat) -> [CGRect] {
        // Read in the frame the page's own writing runs in, where every line of it stands at one
        // quarter turn: a column edge of a sideways table is an edge across the page. The
        // rectangles handed back are the page's own, because that is what the crop rule tests
        // (#276, #263).
        let frame = LayoutReconstructor.ownFrame(of: page.lines)
        let turned = page.lines.map { line -> TextLine in
            var upright = line
            upright.rect = frame(line)
            upright.turn = .upright
            return upright
        }
        let onPage = Dictionary(zip(turned.map(\.rect), page.lines.map(\.rect)),
                                uniquingKeysWith: { first, _ in first })
        let rows = printedRows(turned)
        guard rows.count >= 3 else { return [] }
        let starts = rows.map { $0.map(\.rect.minX) }
        var result: [CGRect] = []
        for (index, row) in rows.enumerated() {
            let cells = cells(of: row)
            guard cells.count >= 2 else { continue }
            let statesAnEdge = cells.dropFirst().contains { cell in
                starts.indices.count(where: { other in
                    other != index && starts[other].contains { abs($0 - cell.rect.minX) <= body }
                }) >= 2
            }
            guard statesAnEdge else { continue }
            result.append(contentsOf: row.filter { printsOneColumnLabel($0.text) }
                .compactMap { onPage[$0.rect] })
        }
        return result
    }

    /// Whether a line prints one group of words over and over, which is what a table's column
    /// header is: the same label set once under each column (#257).
    ///
    /// `Number Per Cent Number Per Cent Nuntler Per Cent Number Per Celt` is `Number Per Cent`
    /// four times, and `Certain Doubtful Total Certain Doubtful Total ertain Ooubtfut Total` is
    /// `Certain Doubtful Total` three times. The repetition is read against the first group and
    /// against the group before, because the recognizer spoils words one group at a time, and
    /// words are compared within an edit distance of half the shorter one, because it spoils
    /// letters within a word: `Nuntler` for `Number`, `Ooubtfut` for `Doubtful`. Four repeated
    /// words in five must agree, which no line of prose in the corpus manages — `10 lbs of nuts
    /// and 20 lbs of chocolate`, a worked exercise in Wallace's algebra, comes closest at three
    /// in four.
    ///
    /// The recognizer also moves the spaces themselves, and then no word has a counterpart to be
    /// near: page 151's `! lt>mber Per Cent Number Percent` broke `Number` into `lt` and `mber`
    /// and closed `Per Cent` up into `Percent`, and page 241's `I Number Per Cent Number PerCeat`
    /// did the second of those (#262). `repeatsItsLetters` reads the same repetition with the
    /// spaces taken out.
    static func printsOneColumnLabel(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count >= 4 else { return false }
        return repeatsAWord(words) || repeatsItsLetters(words)
    }

    /// The word-for-word reading of the repetition (#257).
    private static func repeatsAWord(_ words: [String]) -> Bool {
        for period in 1...(words.count - 2) {
            let repeated = words.count - period
            guard repeated >= 2 else { break }
            let agreeing = (period..<words.count).count { index in
                nearlyEqual(words[index], words[index % period])
                    || nearlyEqual(words[index], words[index - period])
            }
            if agreeing * 5 >= repeated * 4 { return true }
        }
        return false
    }

    /// Whether the line's letters, with the spaces the recognizer moved taken out, are one label
    /// printed once per column (#262).
    ///
    /// The line is read as its letters in order. For each number of columns it is cut into that
    /// many pieces of equal length, each cut moved to the nearest word boundary, and the pieces
    /// are compared as the words were — against the first and against the one before. A piece the
    /// recognizer broke in two or ran together still stands where the label stands, so
    /// `ltmberpercent` answers `numberpercent` and `inumberpercent` answers `numberperceat`,
    /// which word for word they cannot.
    ///
    /// Two things keep this as narrow as the word reading. A piece is a stretch of several words,
    /// so half of it is far more room than half of a word: the pieces agree within a fifth of the
    /// shorter, which over a label of three words is tighter than the word reading allows a
    /// single spoiled word inside it. And every word of the line must hold a letter, because a
    /// label is written in words — the IRS publication's `0 0 0 200` and Wallace's `3r + 6+ 3r
    /// =30` repeat their letters too, and they are a table's figures and an equation, not a
    /// heading.
    private static func repeatsItsLetters(_ words: [String]) -> Bool {
        guard words.allSatisfy({ $0.contains(where: \.isLetter) }) else { return false }
        let letters = Array(words.joined())
        var starts: [Int] = []
        var offset = 0
        for word in words { starts.append(offset); offset += word.count }
        for columns in 2...words.count {
            let width = Double(letters.count) / Double(columns)
            var cuts = [0]
            for column in 1..<columns {
                let target = Double(column) * width
                guard let cut = starts.dropFirst().filter({ $0 > cuts[cuts.count - 1] })
                    .min(by: { abs(Double($0) - target) < abs(Double($1) - target) }) else { break }
                cuts.append(cut)
            }
            guard cuts.count == columns else { continue }
            cuts.append(letters.count)
            let pieces = (0..<columns).map { Array(letters[cuts[$0]..<cuts[$0 + 1]]) }
            if (1..<columns).allSatisfy({ nearly(pieces[$0], pieces[0], oneLetterIn: 5)
                                          || nearly(pieces[$0], pieces[$0 - 1], oneLetterIn: 5) }) {
                return true
            }
        }
        return false
    }

    /// Whether two words are the same word, allowing for what a recognizer does to letters: an
    /// edit distance of at most half the shorter word, and a length difference no larger (#257).
    private static func nearlyEqual(_ a: String, _ b: String) -> Bool {
        nearly(Array(a), Array(b), oneLetterIn: 2)
    }

    /// Whether two runs of letters are the same run, within one spoiled letter in `divisor` of
    /// the shorter, in length as well as in content.
    private static func nearly(_ a: [Character], _ b: [Character], oneLetterIn divisor: Int) -> Bool {
        if a == b { return true }
        let allowed = max(1, min(a.count, b.count) / divisor)
        guard abs(a.count - b.count) <= allowed else { return false }
        return editDistance(a, b) <= allowed
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1]
            for (j, right) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// One printed row per baseline, top down, each row's pieces left to right.
    private static func printedRows(_ lines: [TextLine]) -> [[TextLine]] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.rect.minY > $1.rect.minY }) {
            if let last = rows.last?.first, last.sharesRow(with: line) {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        for row in rows.indices { rows[row].sort { $0.rect.minX < $1.rect.minX } }
        return rows
    }

    /// The pieces of a row the page set apart as cells: the leftmost, then each that begins at
    /// or after the cell before it ends. A piece beginning inside the one before it is another
    /// printed line the extractor put on this row, not a cell beside it.
    private static func cells(of row: [TextLine]) -> [TextLine] {
        var cells = [row[0]]
        for line in row.dropFirst() where line.rect.minX >= cells[cells.count - 1].rect.maxX {
            cells.append(line)
        }
        return cells
    }

    /// Whether the page states a column boundary inside a run of rows: a cell the extractor kept
    /// apart on two rows that merged rows reach across, or a column of numbers on one right edge.
    private static func statesAColumn(_ rows: [[Int]], in lines: [TextLine], body: CGFloat,
                                      rightToLeft: Bool = false) -> Bool {
        func leading(_ rect: CGRect) -> CGFloat { rightToLeft ? rect.maxX : rect.minX }
        func trailing(_ rect: CGRect) -> CGFloat { rightToLeft ? rect.minX : rect.maxX }
        func isBefore(_ first: CGFloat, _ second: CGFloat) -> Bool { rightToLeft ? first > second : first < second }
        // A cell is set in the table's own type. The magazine column that runs beside a
        // photograph's caption also puts two pieces on one baseline, and it is the caption's
        // smaller type that says the second piece is another block of the page, not a cell.
        let split = rows.filter { row in
            row.count > 1 && Int(lines[row[1]].fontSize.rounded()) == Int(lines[row[0]].fontSize.rounded())
        }
        let whole = rows.filter { $0.count == 1 }
        if split.count >= 2, whole.count >= 2,
           !isSetToAMeasure(rows, in: lines, body: body, rightToLeft: rightToLeft) {
            let edges = split.map { leading(lines[$0[1]].rect) }.sorted(by: isBefore)
            if let edge = edges.first, abs(edges.last! - edge) <= body * 0.6,
               whole.count(where: { isBefore(edge, trailing(lines[$0[0]].rect))
                                    && abs(trailing(lines[$0[0]].rect) - edge) > body }) >= 2 { return true }
        }
        func endsInDigit(_ row: [Int]) -> Bool { TableRegionDetector.endsInDigit(row, in: lines) }
        let numeric = rows.filter(endsInDigit)
        guard numeric.count * 3 >= rows.count * 2 else { return false }
        let right = numeric.map { trailing(lines[$0.last!].rect) }
        // A column of numbers is a column: the rows that end on the edge must be most of the run,
        // not three of them out of twenty. The FAA handbook's acknowledgments name a chapter at
        // the end of every credit and set each on its own line, so every row ends in a digit and
        // three of the twenty happen to end within half a body of one another; nothing about that
        // page is a table (#171).
        return right.contains { edge in
            let onEdge = right.count { abs($0 - edge) <= body * 0.5 }
            return onEdge >= 3 && onEdge * 2 >= rows.count
        }
    }

    /// Whether the page filled a run to one measure: the shape of a paragraph hung at an indent,
    /// which is not the shape of a table (#268).
    ///
    /// Replay Clocks sets its references with the citation number outdented and the entry hanging
    /// at an indent, and on geometry alone that is a two-column table: three of the eleven rows of
    /// page 10's last block hand back `[8]`, `[10]` and `[12]` as a cell of their own on one edge,
    /// and the rows the extractor merged — `[9] David L Mills. …` — reach across it. The 9/11
    /// report's flight timelines are set the same way, the time outdented and the entry hung, and
    /// they *are* a table; so are the report's list of illustrations, the Blue Book's contents,
    /// the FAA handbook's cruise table and the USGS statistics. Neither the share of rows the
    /// extractor split nor the share opening on the run's own left edge tells the two apart: both
    /// were measured under #171 and both released the references and the real tables together.
    ///
    /// What separates them is the other edge. A cell is set to its content, so a table's rows end
    /// where their words end and the run is ragged: one row in twenty-six reaches the far edge of
    /// the 9/11 timeline on page 50, one in twenty-four of page 51's, four in fifteen of the list
    /// of illustrations. A paragraph is set to a measure, so its lines end on that measure again
    /// and again and only the last line of each entry falls short: seven of the eleven reference
    /// rows end within a fifth of a body of 558.2, and the four that do not are the closing line
    /// of an entry. Most of a run's rows ending on one edge is therefore the page saying it filled
    /// them, and a filled run is prose.
    ///
    /// Unless that edge is a column of numbers, which is the reading `statesAColumn` already makes
    /// of a right edge and must keep: the NOAA chapter contents right-align `4-16`, `5-9`, `7-20`
    /// against the measure, so every row reaches it. An edge carried by numbers is a column; an
    /// edge carried by words is a measure.
    private static func isSetToAMeasure(_ rows: [[Int]], in lines: [TextLine], body: CGFloat,
                                        rightToLeft: Bool) -> Bool {
        func trailing(_ rect: CGRect) -> CGFloat { rightToLeft ? rect.minX : rect.maxX }
        func isBefore(_ first: CGFloat, _ second: CGFloat) -> Bool { rightToLeft ? first > second : first < second }
        let ends = rows.map { trailing(lines[$0.last!].rect) }
        guard let measure = ends.max(by: isBefore) else { return false }
        let filled = rows.indices.filter { abs(ends[$0] - measure) <= body * 0.2 }
        guard filled.count >= 3, filled.count * 2 > rows.count else { return false }
        return filled.count(where: { endsInDigit(rows[$0], in: lines) }) * 2 < filled.count
    }

    /// Whether a row ends in a number, reading past the punctuation a sentence or a note marker
    /// closes on.
    private static func endsInDigit(_ row: [Int], in lines: [TextLine]) -> Bool {
        let text = lines[row.last!].text
        return text.reversed().drop(while: { "%*).\u{2019}'\"".contains($0) || $0.isWhitespace })
            .first?.isNumber == true
    }
}
