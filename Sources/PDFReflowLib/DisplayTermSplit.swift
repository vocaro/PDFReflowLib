import CoreGraphics
import Foundation
import PDFKit

/// A line PDFKit ran from a sentence into the first term of a display beside it is two lines:
/// the sentence's words and the display's term (#302).
///
/// DASC's page 9 ends a sentence `we see that problem (12) has the form` and sets its display
/// to the right of `the form`, a fraction ½ first. The fraction's numerator shares the words'
/// row, so PDFKit returns `the form 1` as one line; the display's crop could not be cut around
/// it, took it whole, and `the form` left the text for the picture.
///
/// Nothing in running text leaves more than two ems between one glyph and the next, and a
/// script is set against the glyph it belongs to. So where a line's glyphs break by more than
/// two ems, and everything past the break is set smaller than the glyph before it and on another
/// baseline, what lies past the break is a display's term, not the line's. The glyphs are placed
/// by `GlyphPlacementReader`. Where the line's text divides is PDFKit's to say: its text of the
/// line up to the break must open the line's own, and what follows is the term.
enum DisplayTermSplit {
    typealias Glyph = GlyphPlacementReader.Glyph

    /// Where a line's glyphs break into its words and a display's term: the words' right edge,
    /// and the term's rectangle and size. Nil unless the line breaks that way.
    static func cut(_ line: TextLine, glyphs: [Glyph]) -> (wordsEnd: CGFloat, term: CGRect, termSize: CGFloat)? {
        guard line.turn == .upright, !line.monospaced else { return nil }
        let own = glyphs.filter { $0.inked && $0.maxX > $0.minX && line.rect.contains($0.center) }
            .sorted { $0.minX < $1.minX }
        guard own.count >= 2 else { return nil }
        var reach = own[0].maxX
        for index in own.indices.dropFirst() {
            let before = own[index - 1], first = own[index]
            defer { reach = max(reach, first.maxX) }
            guard first.minX - reach > before.size * 2 else { continue }
            let term = own[index...]
            guard term.allSatisfy({ $0.size <= before.size * 0.8 }),
                  abs(first.baseline - before.baseline) >= before.size * 0.2 else { return nil }
            let bottom = term.map { $0.baseline - $0.size * 0.25 }.min()!, top = term.map { $0.baseline + $0.size * 0.75 }.max()!
            let low = max(bottom, line.rect.minY), high = min(top, line.rect.maxY)
            guard high > low else { return nil }
            let rect = CGRect(x: first.minX, y: low, width: line.rect.maxX - first.minX, height: high - low)
            return (reach, rect, term.map(\.size).max()!)
        }
        return nil
    }

    /// `line` as its words and a display's term, given PDFKit's text of the line up to the
    /// break. That text must open the line's own, glyph for glyph once spaces are set aside, and
    /// be words; what the line holds past it is the term, which must hold something and carry no
    /// word. Otherwise nil.
    static func split(_ line: TextLine, wordsEnd: CGFloat, term: CGRect, termSize: CGFloat,
                      words: String) -> [TextLine]? {
        func bases(_ text: String) -> [Unicode.Scalar] { text.unicodeScalars.filter(PaintedAccents.isBase) }
        let left = bases(words), own = bases(line.text)
        guard !left.isEmpty, left.count < own.count, Array(own.prefix(left.count)) == left,
              words.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil,
              let (head, tail) = divided(line.content, afterBase: left.count),
              tail.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) == nil else { return nil }
        var first = TextLine(content: head.trimmingCharacters(in: .whitespaces),
                             rect: CGRect(x: line.rect.minX, y: line.rect.minY,
                                          width: max(0, wordsEnd - line.rect.minX), height: line.rect.height),
                             fontSize: line.fontSize, wraps: line.wraps, turn: line.turn)
        first.structure = line.structure
        var second = TextLine(content: tail.trimmingCharacters(in: .whitespaces), rect: term,
                              fontSize: termSize, turn: line.turn)
        second.structure = line.structure
        guard !first.text.isEmpty, !second.text.isEmpty else { return nil }
        return [first, second]
    }

    /// `text` in two after its `count`-th base scalar (`PaintedAccents.isBase`), or nil where that
    /// falls inside a link.
    static func divided(_ text: InlineText, afterBase count: Int) -> (InlineText, InlineText)? {
        var head = InlineText(), tail = InlineText()
        var remaining = count
        for element in text.elements {
            guard remaining > 0 else { tail.elements.append(element); continue }
            switch element {
            case let .text(value, style):
                var scalars = Array(value.unicodeScalars)[...]
                var taken: [Unicode.Scalar] = []
                while remaining > 0, let scalar = scalars.first {
                    taken.append(scalar)
                    scalars = scalars.dropFirst()
                    if PaintedAccents.isBase(scalar) { remaining -= 1 }
                }
                // A mark set on the last glyph of the words stays with it.
                while let scalar = scalars.first, !PaintedAccents.isBase(scalar), !scalar.properties.isWhitespace {
                    taken.append(scalar)
                    scalars = scalars.dropFirst()
                }
                head.elements.append(.text(String(String.UnicodeScalarView(taken)), style))
                if !scalars.isEmpty { tail.elements.append(.text(String(String.UnicodeScalarView(scalars)), style)) }
            case let .link(_, inner):
                let length = inner.text.unicodeScalars.filter(PaintedAccents.isBase).count
                guard length <= remaining else { return nil }
                remaining -= length
                head.elements.append(element)
            case .sourcePage:
                head.elements.append(element)
            }
        }
        tail.sourceDiscretionaryWord = text.sourceDiscretionaryWord
        return (head, tail)
    }

    /// The page's lines, each that runs from a sentence into a display's term split in two.
    static func separated(_ lines: [TextLine], glyphs: [Glyph], page: PDFPage) throws -> [TextLine] {
        // Each line is measured against the glyphs whose middles stand in its height alone.
        let inked = glyphs.filter { $0.inked && $0.maxX > $0.minX }.sorted { $0.center.y < $1.center.y }
        func band(_ rect: CGRect) -> ArraySlice<Glyph> {
            var low = 0, high = inked.count
            while low < high {
                let middle = (low + high) / 2
                if inked[middle].center.y < rect.minY { low = middle + 1 } else { high = middle }
            }
            var end = low
            while end < inked.count, inked[end].center.y <= rect.maxY { end += 1 }
            return inked[low..<end]
        }
        let cuts = lines.map { cut($0, glyphs: Array(band($0.rect))) }
        guard cuts.contains(where: { $0 != nil }) else { return lines }
        return try NativeTextReader.withExtractionLock {
            lines.indices.flatMap { index -> [TextLine] in
                let line = lines[index]
                guard let cut = cuts[index] else { return [line] }
                let rect = line.rect
                // PDFKit selects a character a rectangle holds more than half of; the break is
                // two ems wide, so reaching into it takes nothing from the term.
                guard let words = page.selection(for: CGRect(x: rect.minX, y: rect.minY,
                                                             width: cut.wordsEnd + (cut.term.minX - cut.wordsEnd) / 2 - rect.minX,
                                                             height: rect.height))?.string
                else { return [line] }
                return split(line, wordsEnd: cut.wordsEnd, term: cut.term, termSize: cut.termSize,
                             words: words) ?? [line]
            }
        }
    }
}
