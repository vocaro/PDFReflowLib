import CoreGraphics
import CoreText
import Foundation
#if os(macOS)
import AppKit
private typealias RowFont = NSFont
#else
import UIKit
private typealias RowFont = UIFont
#endif

/// The PDFKit lines that are pieces of one printed row of stacked scripts, or of a row PDFKit
/// ended at a raised note number, read back as that row (#303, #314).
///
/// `selectionsByLine` breaks a row where its glyphs step back to the left or down among small
/// sizes, which is what stacked scripts do. DASC page 5 sets `STA` with `n` raised, `i` raised
/// from `n`, an inner `h` lowered from `n` and the outer `h` under `n`, and PDFKit returns that one
/// row as `Step 2. For each STAni`, `h` and `h occurring in the computed schedules`. Each became a
/// line, so the script levels were written in three paragraphs, and `inlineText`, which reads
/// one line's runs, could not read them together.
///
/// It also breaks a row at a full stop that a note number follows, where the page sets the
/// number by a text matrix of its own: the 9/11 report's page 145 comes back as
/// `…to the Washington Times.` and `105 This made it`, Loper Bright's page 13 as
/// `…the F/V Persistence.` and `1`. The number opened a paragraph of its own, or stayed a plain
/// digit, and the sentence was broken in two.
///
/// A row grows from a *host*: a line whose largest glyphs (those above 90% of its largest size)
/// share one baseline and include a letter or a digit. Another line is the next piece of the
/// host's row when all of these hold, and the first such line in PDFKit's order is taken each time:
/// - **It opens with a script.** Its first glyph run is set at a script's size, between 45% and
///   90% of the host's, and stands off the row's baseline by more than max(0.5, 12% of its own
///   size). Any larger glyphs it holds are the host's size and, measured, on the host's baseline
///   within max(0.5, 12% of the host's size); they are then placed exactly on it. A piece with no
///   such glyphs is placed by measurement alone, and only where both rectangles are measured.
/// - **It lies within the row's scripts.** Every script glyph stands at most half the host's size
///   below the baseline, and above it at most 85% of the host's size where it is set at 60% of it
///   or more (a first level), or 135% where it is smaller, which is as high as a third level
///   stands: DASC page 6 sets `N` over `n` over `A` 12.08 points up a 9.96-point line.
/// - **It carries on from scripts, or is a note mark.** The row ends in script glyphs, or the
///   piece is scripts alone standing at two levels (DASC page 2's `N` with `f` under it, after
///   `n`), or the row ends in a body glyph and the scripts the piece opens with, before any
///   body-size glyph, all stand above the baseline at one level: a note number, alone or with the
///   words printed after it on the row (#314).
/// - **It continues the row.** It starts no further right than the row's end plus
///   max(1, 25% of the host's size), and no further left than the row's end less the scripts that
///   close the row, counted at one em a character and at most four ems: a subscript set under a
///   superscript starts back under it. No other line sets body-size glyphs on the row's baseline
///   in between, except a stop: a line of one or two punctuation marks at the row's size, on its
///   baseline and starting at its end, is the row's next character, and is taken with the piece
///   that follows it (NOAA page 145 comes back as `…W/m²`, `.` and `² Since NCA4, the`).
/// - **Nothing is painted among the scripts.** No painted mark at most 6 points tall lies within
///   the reach of the scripts, over the width from where the closing scripts may start to where
///   the piece starts: that is a fraction's bar, a radical's vinculum, an overline or a table's
///   rule, and the glyphs around it are not scripts. Beside a note mark, a mark that lies wholly
///   under the baseline is the row's own underline and does not count. No mark at most 6 points
///   wide and taller than that stands up through the row as far as the piece reaches: that is a
///   table's column rule, and the two are cells.
///
/// A number that opens a line, as a note at the page foot opens with its own, starts at no row's
/// end, and is never a piece of the line above it.
///
/// A line that comes before the host in PDFKit's order can be a piece only if it holds nothing
/// but script glyphs within the reach of a neighbouring line's scripts, since PDFKit sometimes
/// returns a raised group before the row it belongs to (DASC page 2's `tt` with its
/// superscripts). Everything else keeps the order PDFKit gave it. Once a row is joined its
/// baseline is known, and every offset in it, the host's too, is measured from that baseline.
/// A line holding right-to-left letters, an attachment or a monospaced font takes no part.
///
/// The baseline a line's offsets are measured from is read from its rectangle: PDFKit bounds
/// each run by its font's descent and ascent at its offset, so the lowest run's descent under
/// the rectangle's bottom is the line's reference. The run's font here is PDFKit's substitute,
/// whose metrics can differ from the page's own font; a line whose top and bottom disagree about
/// its reference by more than 30% of its size holds something its runs do not account for (a
/// tall bracket, a neighbour's glyph), and is not measured.
enum SplitScriptRows {
    typealias Item = (semantic: String, bounds: CGRect, attributed: NSAttributedString?)

    private static let baselineKey = NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)
    /// How far apart in PDFKit's order two pieces of one row are looked for.
    private static let window = 12

    private struct Run {
        let range: NSRange
        let size: Double
        let offset: Double
        /// Characters in the run, which bound its width at one em each.
        let characters: Int
        /// Characters in the run that are not whitespace.
        let glyphs: Int
        var hasGlyph: Bool { glyphs > 0 }
    }

    private struct Piece {
        let bounds: CGRect
        let runs: [Run]
        /// The page y the line's baseline offsets are measured from.
        let reference: Double
        /// Whether the rectangle's top agrees with its bottom about `reference`: a line whose
        /// rectangle also holds a glyph its runs do not (a tall bracket, a neighbour's script)
        /// can place a piece that is not moved onto body text only by guesswork.
        let measured: Bool
        /// The largest glyph size.
        let size: Double
        /// The offset every body-size glyph run shares, where they share one.
        let body: Double?
        var glyphRuns: [Run] { runs.filter(\.hasGlyph) }
    }

    /// A row being grown from its host.
    private struct Row {
        let host: Piece
        let size: Double
        let body: Double
        var bounds: CGRect
        /// Width allowed, at one em a character, for the scripts that close the row.
        var closingWidth = 0.0
        var members: [(index: Int, delta: Double)]
        var last: Int

        init(host: Piece, index: Int, body: Double) {
            self.host = host
            size = host.size
            self.body = body
            bounds = host.bounds
            members = [(index, 0)]
            last = index
            take(host.runs)
        }

        /// Takes `member`, which is `piece`, as the row's next piece.
        mutating func add(_ member: (index: Int, delta: Double), _ piece: Piece) {
            members.append(member)
            bounds = bounds.union(piece.bounds)
            last = max(last, member.index)
            take(piece.runs)
        }

        /// Carries the count of closing scripts on through a piece's runs.
        mutating func take(_ runs: [Run]) {
            for run in runs where run.hasGlyph {
                closingWidth = SplitScriptRows.isScript(run.size, of: size)
                    ? closingWidth + Double(run.characters) * run.size : 0
            }
        }
    }

    static func rejoin(_ items: [Item], marks: [CGRect]) -> [Item] {
        guard items.count > 1 else { return items }
        let pieces = items.map(piece)
        let painted = marks.filter { $0.isFinite && !$0.isNull }
        // A bar lies across the line; a post stands up it, as a ruled table's column rules do.
        let bars = painted.filter { $0.height <= 6 }
        let posts = painted.filter { $0.width <= 6 && $0.height > 6 }
        // A line holding only script-sized glyphs of a neighbour, within that neighbour's scripts:
        // it may be a piece of a row whose host PDFKit returns after it.
        let scriptOnly = pieces.indices.map { index -> Bool in
            guard let piece = pieces[index] else { return false }
            let neighbours = max(0, index - window)...min(pieces.count - 1, index + window)
            return neighbours.contains { other in
                guard other != index, let host = pieces[other], let body = host.body,
                      piece.measured, host.measured,
                      piece.glyphRuns.allSatisfy({ isScript($0.size, of: host.size) }),
                      piece.bounds.minX >= host.bounds.minX,
                      piece.bounds.minX <= host.bounds.maxX + host.size * 4 else { return false }
                return piece.glyphRuns.allSatisfy { run in
                    within(run.offset + piece.reference - host.reference - body, size: run.size, of: host.size)
                }
            }
        }
        var claimed = Array(repeating: false, count: items.count)
        var rows: [Int: Item] = [:]
        // Whether another line sets glyphs on the row's baseline, at its body size, between where
        // the row ends and where `candidate` starts: a stop PDFKit returned on its own after `m²`
        // is the row's next character, and a piece past it would be read before it.
        func interrupted(_ row: Row, by candidate: Int) -> Bool {
            let low = Double(min(row.bounds.maxX, items[candidate].bounds.minX)) + 0.3
            let high = Double(max(row.bounds.maxX, items[candidate].bounds.minX)) - 0.3
            guard high > low else { return false }
            let baseline = row.host.reference + row.body
            let lines = max(0, row.members[0].index - window)...min(items.count - 1, row.last + window)
            return lines.contains { index in
                guard index != candidate, !row.members.contains(where: { $0.index == index }),
                      let other = pieces[index], let lead = other.glyphRuns.first,
                      Double(other.bounds.maxX) > low, Double(other.bounds.minX) < high else { return false }
                return lead.size > row.size * 0.9
                    && abs(other.reference + lead.offset - baseline) <= max(0.5, row.size * 0.12)
            }
        }
        // The lines that may be `row`'s next piece, in PDFKit's order.
        func around(_ row: Row) -> [Int] {
            let start = row.members[0].index
            return (max(0, start - window)...min(items.count - 1, row.last + window)).filter { index in
                !claimed[index] && !row.members.contains(where: { $0.index == index })
            }
        }
        // The first line in PDFKit's order that is the next piece of `row`.
        func next(of row: Row) -> (index: Int, delta: Double)? {
            for index in around(row) {
                // A line PDFKit returned earlier that is not a stray script has been read on its own.
                guard index > row.members[0].index || scriptOnly[index], let piece = pieces[index],
                      let delta = continues(row, with: piece, bars: bars, posts: posts),
                      !interrupted(row, by: index) else { continue }
                return (index, delta)
            }
            return nil
        }
        // A stop PDFKit returned as a line of its own where the row ends, set at the row's size on
        // its baseline: NOAA page 145 comes back as `…W/m²`, `.` and `² Since NCA4, the` (#314).
        // It is the row's next character, and is taken only with the piece that follows it.
        func stop(after row: Row) -> (index: Int, delta: Double)? {
            let end = Double(row.bounds.maxX), baseline = row.host.reference + row.body
            let tolerance = max(0.5, row.size * 0.12)
            for index in around(row) where index > row.members[0].index {
                guard let piece = pieces[index], let lead = piece.glyphRuns.first,
                      piece.runs.allSatisfy({ $0.characters <= 2 }), piece.glyphRuns.count == 1,
                      items[index].semantic.allSatisfy({ $0.isPunctuation || $0.isWhitespace }),
                      abs(lead.size - row.size) <= max(0.5, row.size * 0.1),
                      abs(piece.reference + lead.offset - baseline) <= tolerance,
                      Double(piece.bounds.minX) >= end - 0.5,
                      Double(piece.bounds.minX) <= end + max(1, row.size * 0.25) else { continue }
                return (index, row.body - lead.offset)
            }
            return nil
        }
        for start in items.indices where !claimed[start] && !scriptOnly[start] {
            guard let host = pieces[start], let body = host.body else { continue }
            var row = Row(host: host, index: start, body: body)
            while true {
                if let piece = next(of: row) {
                    row.add(piece, pieces[piece.index]!)
                    continue
                }
                guard let stop = stop(after: row) else { break }
                var bridged = row
                bridged.add(stop, pieces[stop.index]!)
                guard let piece = next(of: bridged) else { break }
                row = bridged
                row.add(piece, pieces[piece.index]!)
            }
            guard row.members.count > 1 else { continue }
            for member in row.members { claimed[member.index] = true }
            // The row's own baseline is known now, so every offset is measured from it.
            rows[start] = joined(row.members.map { (items[$0.index], $0.delta - body) })
        }
        guard !rows.isEmpty else { return items }
        return items.indices.compactMap { index in rows[index] ?? (claimed[index] ? nil : items[index]) }
    }

    /// Whether a run of `size` is set at a script's size against a body of `body`: at most 90% of it,
    /// and at least 45%, which is below the smallest level TeX or a word processor sets. Text set
    /// smaller still beside a display initial or a chapter number is the line, not its scripts.
    private static func isScript(_ size: Double, of body: Double) -> Bool {
        size <= body * 0.9 && size >= body * 0.45
    }

    /// Whether some two of the runs stand apart by more than positioning noise: a stack.
    private static func standsAtTwoLevels(_ runs: [Run]) -> Bool {
        runs.contains { a in
            runs.contains { b in abs(a.offset - b.offset) > max(0.5, max(a.size, b.size) * 0.12) }
        }
    }

    /// Whether a piece opens with one level of scripts raised off the baseline of a row that
    /// ends in a body glyph: the scripts before its first body-size glyph all stand above the
    /// baseline, by more than positioning noise, at one height. That is a note number PDFKit
    /// ended the row's line at and returned as a line of its own (#314).
    private static func raisedMark(_ glyphs: [Run], delta: Double, of row: Row) -> Bool {
        let leading = glyphs.prefix { $0.size <= row.size * 0.9 }
        return row.closingWidth == 0 && !leading.isEmpty && !standsAtTwoLevels(Array(leading))
            && leading.allSatisfy { $0.offset + delta - row.body > max(0.5, $0.size * 0.12) }
    }

    /// Whether a script run of `size`, `offset` from the baseline of a row of `body`, lies within
    /// the reach of the row's scripts: at most half the body below it, and above it at most 85%
    /// where the run is set at 60% of the body or more, the size of a first level, or 135% where
    /// it is set smaller, which is as high as a third level stands (DASC page 6's `N` over `n`
    /// over `A`, 12.08 points over a 9.96-point line).
    private static func within(_ offset: Double, size: Double, of body: Double) -> Bool {
        offset >= -body * 0.5 && offset <= body * (size >= body * 0.6 ? 0.85 : 1.35)
    }

    /// The shift that moves `piece`'s offsets into the host's frame, when `piece` is the next piece
    /// of `row`; nil when it is not. `interrupted` in `rejoin` makes the one test that needs the
    /// other lines.
    private static func continues(_ row: Row, with piece: Piece, bars: [CGRect], posts: [CGRect]) -> Double? {
        let size = row.size
        let glyphs = piece.glyphRuns
        guard let first = glyphs.first, isScript(first.size, of: size), piece.size <= size * 1.1 else { return nil }
        var delta = piece.reference - row.host.reference
        // Body-size glyphs sit on the host's baseline: the measured shift must put them there,
        // and then puts them there exactly.
        let bodyRuns = glyphs.filter { $0.size > size * 0.9 }
        let tolerance = max(0.5, size * 0.12)
        if let lead = bodyRuns.first {
            guard bodyRuns.allSatisfy({ abs($0.size - size) <= max(0.5, size * 0.1)
                                        && abs($0.offset - lead.offset) <= tolerance }),
                  abs(lead.offset + delta - row.body) <= tolerance else { return nil }
            delta = row.body - lead.offset
        } else {
            guard piece.measured, row.host.measured else { return nil }
            delta = (delta * 100).rounded() / 100
        }
        guard abs(first.offset + delta - row.body) > max(0.5, first.size * 0.12),
              glyphs.allSatisfy({ $0.size > size * 0.9
                  || isScript($0.size, of: size) && within($0.offset + delta - row.body, size: $0.size, of: size) })
        else { return nil }
        // The piece carries on from scripts that close the row, or holds a stack of its own (DASC
        // page 2's `N` with `f` under it, after `n`), or is a note mark raised straight after the
        // row's last body glyph, with or without the words that follow it on the row (#314).
        let stacked = row.closingWidth > 0 || bodyRuns.isEmpty && standsAtTwoLevels(glyphs)
        guard stacked || raisedMark(glyphs, delta: delta, of: row) else { return nil }
        // Stacked scripts are short: the width a piece may start back under them is at most four
        // ems of the row's size, however many characters close the row.
        let start = piece.bounds.minX, end = row.bounds.maxX
        guard start <= end + max(1, size * 0.25),
              start >= end - min(row.closingWidth, size * 4) - 0.5 else { return nil }
        // A bar painted among the scripts, over the width where the piece meets the row and within
        // the reach of its scripts, makes them something else: a fraction's numerator and
        // denominator, a radicand under its vinculum, a term under an overline, or a cell under a
        // table's rule. Beside a single raised mark, a rule that lies wholly under the baseline is
        // the row's own underline, carried on to the glyph the mark follows: NOAA underlines its
        // links with a 4-point bar from the baseline down, as page 26 does under `Table 1.1.9.`
        // before its note 12 (#314). A fraction's bar stands above the baseline, at the axis.
        let baseline = row.host.reference + row.body
        let meeting = min(start, end - min(row.closingWidth, size * 4))
        let among = CGRect(x: meeting - 1, y: baseline - size * 0.5,
                           width: max(start + 1, end + 1) - (meeting - 1), height: size * 1.85)
        if bars.contains(where: { $0.intersects(among) && (stacked || Double($0.maxY) > baseline + tolerance) }) {
            return nil
        }
        // A rule standing up through the row between its first glyph and the piece's last is a
        // table's column rule: the two are cells, however close.
        let across = CGRect(x: row.bounds.minX, y: baseline - size * 0.5,
                            width: max(row.bounds.maxX, piece.bounds.maxX) - row.bounds.minX,
                            height: size * 1.85)
        if posts.contains(where: { $0.intersects(across) }) { return nil }
        return delta
    }

    private static func piece(_ item: Item) -> Piece? {
        // Right-to-left letters are shaped off the baseline inside words the page never raised
        // (#41), so their offsets say nothing about scripts.
        guard let attributed = item.attributed, attributed.length > 0,
              !attributed.string.contains("\u{FFFC}"), attributed.string == item.semantic,
              !attributed.string.unicodeScalars.contains(where: ArabicText.isRightToLeftLetter),
              item.bounds.isFinite, !item.bounds.isNull, item.bounds.width > 0, item.bounds.height > 0
        else { return nil }
        var runs: [Run] = []
        var lowest = Double.infinity, highest = -Double.infinity
        var usable = true
        let string = attributed.string as NSString
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, stop in
            guard let font = attributes[.font] as? RowFont else { usable = false; stop.pointee = true; return }
            let size = Double(font.pointSize), ascent = Double(font.ascender), descent = Double(font.descender)
            let offset = ((attributes[baselineKey] ?? attributes[.baselineOffset]) as? NSNumber)?.doubleValue ?? 0
            let name = font.fontName.lowercased()
            guard size.isFinite, size > 0, size <= 1_000, ascent.isFinite, descent.isFinite, offset.isFinite,
                  abs(offset) <= 1_000, !name.contains("courier"), !name.contains("mono")
            else { usable = false; stop.pointee = true; return }
            let text = string.substring(with: range)
            lowest = min(lowest, offset + descent)
            highest = max(highest, offset + ascent)
            let glyphs = text.filter { !$0.isWhitespace }.count
            runs.append(Run(range: range, size: size, offset: offset, characters: text.count,
                            glyphs: glyphs))
        }
        let glyphSizes = runs.filter(\.hasGlyph).map(\.size)
        guard usable, let size = glyphSizes.max(), lowest.isFinite, highest.isFinite else { return nil }
        let bottom = Double(item.bounds.minY) - lowest, top = Double(item.bounds.maxY) - highest
        let bodyRuns = runs.filter { $0.hasGlyph && $0.size > size * 0.9 }
        let tolerance = max(0.5, size * 0.12)
        // A line's body is its largest glyphs where they share one baseline and include a letter
        // or a digit: a display operator set large beside smaller text is no body.
        let body = bodyRuns.first.flatMap { lead in
            bodyRuns.allSatisfy { abs($0.offset - lead.offset) <= tolerance }
                && bodyRuns.contains { string.substring(with: $0.range).contains { $0.isLetter || $0.isNumber } }
                ? lead.offset : nil
        }
        return Piece(bounds: item.bounds, runs: runs, reference: bottom,
                     measured: abs(bottom - top) <= size * 0.3, size: size, body: body)
    }

    /// The pieces' text, one after another, each piece's offsets moved by its shift.
    private static func joined(_ members: [(item: Item, delta: Double)]) -> Item {
        let text = NSMutableAttributedString()
        var bounds = CGRect.null
        for (item, delta) in members {
            guard let attributed = item.attributed else { continue }
            bounds = bounds.union(item.bounds)
            guard delta != 0 else { text.append(attributed); continue }
            let moved = NSMutableAttributedString(attributedString: attributed)
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
                let offset = ((attributes[baselineKey] ?? attributes[.baselineOffset]) as? NSNumber)?.doubleValue ?? 0
                moved.addAttribute(baselineKey, value: NSNumber(value: offset + delta), range: range)
                if attributes[.baselineOffset] != nil {
                    moved.addAttribute(.baselineOffset, value: NSNumber(value: offset + delta), range: range)
                }
            }
            text.append(moved)
        }
        return (members.map(\.item.semantic).joined(), bounds, text)
    }
}
