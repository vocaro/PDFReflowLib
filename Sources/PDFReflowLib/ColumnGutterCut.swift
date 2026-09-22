import CoreGraphics
import Foundation

/// A line PDFKit merged across the gutter between two columns, and where the page says to cut it
/// (#270).
///
/// The 9/11 report sets two flight timelines side by side on physical pages 50 and 51, each under
/// three heading rows: the airline and flight number, the flight's short name in brackets, and its
/// route. PDFKit reads the first and third of those rows as two lines, one per column, and hands
/// the second back as a single line spanning both:
///
/// ```
/// y=537.25  x= 39.66 w=136.12  'American Airlines Flight 11'
/// y=537.25  x=195.67 w=126.35  'United Airlines Flight 175'
/// y=526.00  x= 39.66 w=199.63  '(AA 11) (UA 175)'     <- one line, both columns
/// y=514.92  x= 39.66 w= 88.30  'Boston to Los Angeles'
/// y=514.92  x=195.67 w= 88.30  'Boston to Los Angeles'
/// ```
///
/// A line that bridges the gutter cannot be separated by any whitespace cut downstream, and it
/// stands on the left column's own edge directly above the left column's route, which the ordinary
/// column-and-leading test then joins to it. The book read `(AA 11) (UA 175) Boston to Los Angeles`
/// and stranded the right column's route.
///
/// **The page's own shows do not divide this row.** `NativeSpacingReader.read` returns the whole
/// heading row as *one* show — page 50 draws `(AA 11)             (UA 175)` from x=39.66 to
/// x=242.95 in a single text-showing operation, with the gutter inside its own advance — so the
/// ink `TableReader` reads (#210) is one unbroken range across the gutter and its `corridors` find
/// nothing here. The division has to come from the characters.
///
/// **What the page states is its neighbours.** The rows directly above and below the merged one
/// each hold exactly two pieces standing on the same two left edges, 39.66 and 195.67. The merged
/// line begins on the first of those edges and runs past the second, and the second falls inside a
/// run of white 118.37 points across — twenty-six times the 4.50-point space the same line sets
/// between its own words. Three rows that agree on two edges, of which the middle one is read as a
/// single piece, are three rows of two cells, and the middle is cut at the edge the outer two
/// state.
///
/// **A heading group, and no more.** The three rows are the whole of what the page states here:
/// neither the row two above nor the row two below stands on the same pair of edges. Where a page
/// states its columns over four rows or more, the reading already holds divided pieces for them and
/// the ordering rules can see the columns; dividing one more row there changes how the whole page
/// is read, and on this book's own page 451 it does exactly that (#283).
///
/// **What refuses the cut.** A line genuinely set across a gutter — a headline, a caption over both
/// columns — reads as one piece for the same reason, and must keep its reading. It is refused by
/// the white: a spanning line puts its words *through* the gutter, so the white at the column edge
/// is the ordinary space it sets everywhere else, while a merged row leaves the gutter empty. The
/// measured condition is a run of white at least three times the widest other run of the line, and
/// at least twice the line's own characters are tall.
///
/// Everything here is decided from the page's own reading, as #264's margin rule is: which
/// characters stand where, and what rectangle PDFKit gives each of them. The correction belongs
/// where the box is formed, because nothing downstream can divide a line.
enum ColumnGutterCut {
    /// Where a merged line divides.
    struct Cut: Equatable {
        /// UTF-16 length of the line the cut was measured against. A repair that rewrote the line
        /// between the reading and the cut leaves the offsets meaning something else, and the cut
        /// is declined rather than made at the wrong character.
        var length: Int
        /// UTF-16 offset the left column's piece ends at, and the offset the right column's piece
        /// opens at. The white between them belongs to neither.
        var keep: Int
        var offset: Int
        /// The rectangle each piece stands in: PDFKit's own outer edge for the line, and the
        /// piece's own characters for the inner one, which is the only edge the merge got wrong.
        var left: CGRect
        var right: CGRect
    }

    /// Whether a page is worth measuring character by character, decided from the line geometry
    /// extraction already holds. A page that merges no row pays one pass over its lines.
    ///
    /// This is the whole geometric shape but for the white: a row of one piece, between two rows of
    /// two pieces standing on the same edges and nothing beyond them, reaching past the second of
    /// them. What it costs to be wrong is a page measured and then left alone, because `read`
    /// decides the cut on the characters themselves.
    static func suspected(texts: [String?], rects: [CGRect]) -> Bool {
        !edges(texts: texts.map { $0 ?? "" }, rects: rects).isEmpty
    }

    /// The lines the page merged across its gutter, keyed by their index among the page's lines.
    ///
    /// `boxes[line][offset]` is PDFKit's own rectangle for the character at that UTF-16 offset of
    /// `texts[line]`, as #264's reading of a margin rule uses; `rects[line]` is the rectangle
    /// PDFKit gives the whole line.
    static func read(texts: [String], boxes: [[CGRect]], rects: [CGRect]) -> [Int: Cut] {
        guard texts.count == boxes.count, texts.count == rects.count else { return [:] }
        var cuts: [Int: Cut] = [:]
        for (line, edge) in edges(texts: texts, rects: rects) {
            let units = texts[line] as NSString
            guard units.length == boxes[line].count,
                  let cut = divide(units, boxes: boxes[line], rect: rects[line], at: edge)
            else { continue }
            cuts[line] = cut
        }
        return cuts
    }

    /// The line's two pieces, with the styled text cut to match. The cut is positional, and is made
    /// only while the text is still the one the boxes were read over, so a repair that rewrote the
    /// line between the reading and here cuts nothing.
    static func split(_ cut: Cut, from styled: NSAttributedString?, text: String)
        -> (left: (text: String, styled: NSAttributedString?),
            right: (text: String, styled: NSAttributedString?))? {
        let units = text as NSString
        guard units.length == cut.length, cut.keep > 0, cut.offset < units.length,
              cut.keep <= cut.offset else { return nil }
        let head = NSRange(location: 0, length: cut.keep)
        let tail = NSRange(location: cut.offset, length: units.length - cut.offset)
        guard let styled else {
            return ((units.substring(with: head), nil), (units.substring(with: tail), nil))
        }
        guard (styled.string as NSString).length == units.length, styled.string == text else { return nil }
        return ((units.substring(with: head), styled.attributedSubstring(from: head)),
                (units.substring(with: tail), styled.attributedSubstring(from: tail)))
    }

    // MARK: - The three rows

    /// The narrowest agreement two rows may state about one column edge and still be read as the
    /// same edge. Page 50 states 195.67 twice over; page 51 states 200.71 and 200.69.
    private static let tolerance: CGFloat = 1

    /// Every line standing alone in its printed row, between two rows of exactly two pieces that
    /// agree on both their left edges, which begins on the first edge and reaches past the second —
    /// paired with the second edge, which is where the page says the line divides.
    ///
    /// This is the geometric half of the rule, and the whole of `suspected`. It is internal because
    /// it is what the tests and the measurement probe read to separate the lines the page's shape
    /// offers from the ones its white admits: a line set across the gutter has this shape too.
    static func edges(texts: [String], rects: [CGRect]) -> [(line: Int, edge: CGFloat)] {
        let rows = printedRows(texts: texts, rects: rects)
        guard rows.count >= 3 else { return [] }
        var found: [(line: Int, edge: CGFloat)] = []
        for index in 1..<(rows.count - 1) {
            guard rows[index].count == 1, rows[index - 1].count == 2, rows[index + 1].count == 2 else { continue }
            let line = rows[index][0]
            let rect = rects[line]
            let above = rows[index - 1].map { rects[$0] }, below = rows[index + 1].map { rects[$0] }
            // The three rows are one group, not three rows of the page at large: each step down is
            // a leading, no more than twice the taller row's own height.
            let steps = [above[0].maxY - rect.maxY, rect.maxY - below[0].maxY]
            let heights = [max(above[0].height, rect.height), max(rect.height, below[0].height)]
            guard zip(steps, heights).allSatisfy({ $0 > 0 && $0 <= $1 * 2 }) else { continue }
            guard abs(above[0].minX - below[0].minX) <= tolerance,
                  abs(above[1].minX - below[1].minX) <= tolerance,
                  abs(rect.minX - (above[0].minX + below[0].minX) / 2) <= tolerance else { continue }
            let edge = (above[1].minX + below[1].minX) / 2
            guard rect.minX < edge, rect.maxX > edge else { continue }
            // The three rows are the whole of what the page states here. Where the same two edges
            // run on above or below the group, the pieces the reading already holds are enough for
            // the ordering rules to read those columns, and dividing one more row changes how the
            // whole page is read: the 9/11 report's table of names on page 451 sets twenty-three
            // rows on 44.70 and 152.70, of which PDFKit merges one, and dividing that one turns the
            // page from a list of names with their offices into one paragraph of names followed by
            // one of offices (#283).
            let beyond = [index - 2, index + 2].filter { rows.indices.contains($0) }
            guard beyond.allSatisfy({ outer in
                let pieces = rows[outer].map { rects[$0] }
                guard pieces.count == 2 else { return true }
                return abs(pieces[0].minX - above[0].minX) > tolerance
                    || abs(pieces[1].minX - edge) > tolerance
            }) else { continue }
            found.append((line, edge))
        }
        return found
    }

    /// The page's printed rows, top down, each row's line indices left to right. A row is what
    /// PDFKit's own line rectangles overlap in, which is the reading `TextLine.sameRow` states.
    private static func printedRows(texts: [String], rects: [CGRect]) -> [[Int]] {
        let usable = rects.indices.filter {
            !texts[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && rects[$0].isFinite && !rects[$0].isNull && rects[$0].width > 0 && rects[$0].height > 0
        }
        var rows: [[Int]] = []
        for index in usable.sorted(by: { rects[$0].maxY > rects[$1].maxY }) {
            if let last = rows.last?.first, TextLine.sameRow(rects[last], rects[index]) {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        for row in rows.indices { rows[row].sort { rects[$0].minX < rects[$1].minX } }
        return rows
    }

    // MARK: - The white in the line

    /// The line divided at the white holding `edge`, or nil where its own ink states nothing.
    ///
    /// The line's **ink** is the boxes of the characters that print: not its spaces, and not a
    /// character the reading gives no width — page 20 of the climate assessment carries a `U+0008`
    /// between a contents entry and its page number, which stands nowhere. The white is the x
    /// between one inking character and the next, which is the same reading of a page's columns
    /// `TableReader` takes from the content stream's shows (#210), here taken from the characters
    /// because the shows do not divide this row.
    private static func divide(_ units: NSString, boxes: [CGRect], rect: CGRect, at edge: CGFloat) -> Cut? {
        let inking = (0..<units.length).filter { !isSpace(units, $0) && usable(boxes[$0]) }
        guard inking.count >= 2 else { return nil }
        // A line whose characters PDFKit reports out of the order they stand in says nothing about
        // where its columns are: the algebra book's answer keys hand back a wrapped row whose text
        // returns to the left margin mid-line.
        guard zip(inking, inking.dropFirst()).allSatisfy({ boxes[$0].minX <= boxes[$1].minX }) else { return nil }
        guard let typical = median(inking.map { boxes[$0].height }), typical > 0 else { return nil }
        let gaps = zip(inking, inking.dropFirst()).map {
            (keep: $0 + 1, offset: $1, width: boxes[$1].minX - boxes[$0].maxX)
        }
        guard let found = gaps.first(where: { boxes[$0.keep - 1].maxX <= edge && boxes[$0.offset].minX >= edge })
        else { return nil }
        let widest = gaps.filter { $0.offset != found.offset }.map(\.width).max() ?? 0
        // A line set across the gutter runs its words through it, so the white at the column edge
        // is the space it sets everywhere else. Only white the page left there divides a row.
        guard found.width >= typical * 2, found.width >= widest * 3 else { return nil }
        // Nothing that prints is dropped: what stands between the two pieces is spaces and
        // characters the page gives no width at all.
        guard (found.keep..<found.offset).allSatisfy({ isSpace(units, $0) || !usable(boxes[$0]) }) else {
            return nil
        }
        // PDFKit's own outer edges are kept; only the inner edge, which the merge got wrong, is the
        // characters'.
        let inner = (left: boxes[found.keep - 1].maxX, right: boxes[found.offset].minX)
        return Cut(length: units.length, keep: found.keep, offset: found.offset,
                   left: CGRect(x: rect.minX, y: rect.minY, width: inner.left - rect.minX, height: rect.height),
                   right: CGRect(x: inner.right, y: rect.minY,
                                 width: rect.maxX - inner.right, height: rect.height))
    }

    private static func isSpace(_ units: NSString, _ offset: Int) -> Bool {
        units.substring(with: NSRange(location: offset, length: 1)).first?.isWhitespace == true
    }

    private static func usable(_ box: CGRect) -> Bool {
        box.isFinite && !box.isNull && box.width > 0 && box.height > 0
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}
