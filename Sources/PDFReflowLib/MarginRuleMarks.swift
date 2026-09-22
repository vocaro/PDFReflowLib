import CoreGraphics
import Foundation

/// A rule a page draws down its margin, which an inherited recognition read as a column of
/// letters (#264).
///
/// Project Blue Book paints such a rule down the outer margin of its pages, and the layer it
/// inherited read each segment of it as a capital `I` set in 30-point type. PDFKit puts that
/// letter in the same line as the type beside it, so a 7.8-point line of the list of
/// illustrations comes back in a 31.5-point box at a 31.5-point size, and the box overlaps the
/// rows above and below it. Every rule that reads a line's box then reads the mark's height
/// rather than the text's: on page 7 the wrap `I South Farwest Region . 54` (`y[645.9..677.4]`)
/// sorts *above* the entry it continues, `Figure 38 …of the` (`y[656.8..663.8]`).
///
/// This is not the thin-rule ownership of #207. That reads a rule the page *paints*, against the
/// printed row it strikes, and can only keep a painted region from claiming a line. A recognized
/// rule is painted nowhere: it is in the text layer, so by the time any ownership rule runs there
/// is no rule left to own — only a line whose rectangle is already wrong. The correction belongs
/// where the box is formed.
///
/// Everything here is decided from the page's own reading: which characters stand where the rule
/// does, and what rectangle PDFKit gives each of them. Nothing consults the page's ink.
enum MarginRuleMarks {
    /// The glyphs a recognition offers for a printed vertical rule. Nothing else is read as one,
    /// however tall it stands: a letter with a shape of its own is a letter.
    static let glyphs: Set<Character> = ["I", "l", "|"]

    /// A line the page's margin rule reached, and what the line is without it.
    struct Reading: Equatable {
        /// Characters to cut from the line's start, and from its end: the rule's own marks and
        /// the space a recognition sets between a mark and the type beside it, which carries the
        /// mark's size and would otherwise state it for the whole line (#183).
        var leading = 0
        var trailing = 0
        /// The rectangle the characters that remain stand in. Null where the line is the rule and
        /// nothing else, which carries no text and is dropped.
        var rect: CGRect
    }

    /// Whether a page is worth measuring character by character, decided from the line geometry
    /// extraction already holds. A page with no rule down its margin pays one pass over its lines.
    ///
    /// The test is deliberately loose — a rule glyph at one end of a line, standing in the outer
    /// twentieth of the page, on four lines or more. What it costs to be wrong is a page measured
    /// and then left alone, because `read` decides the rule on the characters themselves.
    static func suspected(texts: [String?], rects: [CGRect], bounds: CGRect) -> Bool {
        guard bounds.width > 0, texts.count == rects.count else { return false }
        let margin = bounds.width * 0.05
        var count = 0
        for (text, rect) in zip(texts, rects) {
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, rect.isFinite, !rect.isNull else { continue }
            if let first = trimmed.first, glyphs.contains(first), rect.minX <= bounds.minX + margin {
                count += 1
            } else if let last = trimmed.last, glyphs.contains(last), rect.maxX >= bounds.maxX - margin {
                count += 1
            }
            if count >= 4 { return true }
        }
        return false
    }

    /// The lines a page's margin rule reached, keyed by their index among the page's lines.
    ///
    /// `boxes[line][offset]` is PDFKit's own rectangle for the character at that UTF-16 offset of
    /// `texts[line]`; `rects[line]` is the rectangle PDFKit gives the whole line, which is the one
    /// the rule damaged.
    ///
    /// A **mark** is a character that is one of `glyphs`, drawn at least two and a half times as
    /// tall as the page's own characters, at least twice as tall as it is wide — a segment of a
    /// rule, not a letter in a line of type — and standing in the outer twentieth of the page on
    /// one side. Four such characters sharing one column are a rule; three are not, because a
    /// display initial, a mathematical bar and a stray recognition are each one mark and none of
    /// them repeats down a margin.
    ///
    /// A line holding marks is measured by the characters that remain. A line holding none can
    /// still have been damaged, because PDFKit gives every piece of a printed row the height of
    /// the tallest piece in it: page 7's `56` stands in `y[632.6..637.9]` and is reported at
    /// `y[610.4..641.9]`, the box of the rule beside the entry it belongs to. Such a line is
    /// measured by its own characters where it shares its row with a line the rule reached and its
    /// reported box is at least twice as tall as the characters it holds — the whole type size the
    /// issue names. A line that is genuinely that tall keeps its box, because its characters are
    /// that tall too.
    static func read(texts: [String], boxes: [[CGRect]], rects: [CGRect], bounds: CGRect) -> [Int: Reading] {
        guard texts.count == boxes.count, texts.count == rects.count, bounds.width > 0 else { return [:] }
        guard let typical = median(boxes.flatMap { $0 }.filter(usable).map(\.height)), typical > 0 else {
            return [:]
        }
        let margin = bounds.width * 0.05
        var candidates: [(line: Int, offset: Int, box: CGRect, right: Bool)] = []
        for (line, text) in texts.enumerated() {
            let units = text as NSString
            for offset in 0..<min(units.length, boxes[line].count) {
                let box = boxes[line][offset]
                guard usable(box), box.height >= typical * 2.5, box.height >= box.width * 2,
                      let glyph = units.substring(with: NSRange(location: offset, length: 1)).first,
                      glyphs.contains(glyph) else { continue }
                if box.maxX <= bounds.minX + margin {
                    candidates.append((line, offset, box, false))
                } else if box.minX >= bounds.maxX - margin {
                    candidates.append((line, offset, box, true))
                }
            }
        }
        // One rule stands in one column. A mark away from the column its own side's marks share is
        // not part of it, and a side carrying fewer than four is no rule at all.
        var marked: [Int: Set<Int>] = [:]
        for right in [false, true] {
            let side = candidates.filter { $0.right == right }
            guard side.count >= 4, let low = median(side.map { $0.box.minX }),
                  let high = median(side.map { $0.box.maxX }) else { continue }
            let column = side.filter { $0.box.minX < high && $0.box.maxX > low }
            guard column.count >= 4 else { continue }
            for mark in column { marked[mark.line, default: []].insert(mark.offset) }
        }
        guard !marked.isEmpty else { return [:] }

        var readings: [Int: Reading] = [:]
        for (line, offsets) in marked {
            let units = texts[line] as NSString
            var leading = 0
            while leading < units.length, offsets.contains(leading) { leading += 1 }
            var trailing = 0
            while trailing < units.length - leading, offsets.contains(units.length - 1 - trailing) { trailing += 1 }
            // A mark inside a line is not a margin rule's — nothing stands between a margin and the
            // type beside it — so such a line is left exactly as it was read.
            guard offsets.count == leading + trailing else { continue }
            while leading < units.length - trailing, isSpace(units, leading) { leading += 1 }
            while trailing < units.length - leading, isSpace(units, units.length - 1 - trailing) { trailing += 1 }
            let kept = union(boxes[line], from: leading, to: units.length - trailing)
            readings[line] = Reading(leading: leading, trailing: trailing, rect: kept ?? .null)
        }
        let damaged = readings.keys.map { rects[$0] }
        for (line, text) in texts.enumerated() where readings[line] == nil {
            let length = (text as NSString).length
            guard length > 0, rects[line].isFinite, !rects[line].isNull,
                  damaged.contains(where: { TextLine.sameRow($0, rects[line]) }),
                  let box = union(boxes[line], from: 0, to: length),
                  box.height > 0, rects[line].height >= box.height * 2 else { continue }
            readings[line] = Reading(leading: 0, trailing: 0, rect: box)
        }
        return readings
    }

    /// The line's text without the marks the rule left in it, with the styled text cut to match.
    /// The cut is positional, and is made only while the text still opens and closes on what was
    /// read there, so a repair that rewrote the line between the reading and here cuts nothing.
    static func cut(_ reading: Reading, from styled: NSAttributedString?, text: String)
        -> (text: String, styled: NSAttributedString?) {
        let units = text as NSString
        guard reading.leading + reading.trailing > 0,
              reading.leading + reading.trailing <= units.length else { return (text, styled) }
        let kept = NSRange(location: reading.leading, length: units.length - reading.leading - reading.trailing)
        guard let styled else { return (units.substring(with: kept), nil) }
        guard (styled.string as NSString).length == units.length, styled.string == text else {
            return (text, styled)
        }
        return (units.substring(with: kept), styled.attributedSubstring(from: kept))
    }

    private static func isSpace(_ units: NSString, _ offset: Int) -> Bool {
        units.substring(with: NSRange(location: offset, length: 1)).first?.isWhitespace == true
    }

    private static func usable(_ box: CGRect) -> Bool {
        box.isFinite && !box.isNull && box.width > 0 && box.height > 0
    }

    private static func union(_ boxes: [CGRect], from: Int, to: Int) -> CGRect? {
        var result = CGRect.null
        for offset in max(0, from)..<min(to, boxes.count) where usable(boxes[offset]) {
            result = result.union(boxes[offset])
        }
        return result.isNull ? nil : result
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}
