import CoreGraphics
import Foundation

/// Bounded page-bottom footnote layout: a typographic separator line drawn as dash
/// characters, then smaller-type note lines to the end of the page, each note opening with
/// a raised numeric marker. Not a reference-to-note ownership detector.
enum FootnoteDetector {
    struct Note {
        /// Element indices of the note's lines in reading order.
        var range: ClosedRange<Int>
        /// The raised digits opening the note; nil for the continuation of the previous
        /// page's last note, which is admitted only when that page ended in a note.
        var marker: Int?
    }

    struct Layout {
        /// The separator's element index; every element after it belongs to a note.
        var separator: Int
        var notes: [Note]
    }

    /// A line of three or more dash-like characters and nothing else (em/en dashes,
    /// horizontal bars, underscores, hyphens). `* * *` section breaks do not qualify.
    static func isSeparator(_ line: TextLine) -> Bool {
        line.text.range(of: "^[\\u{2014}\\u{2015}\\u{2013}_-]{3,}$", options: .regularExpression) != nil
    }

    /// The raised digits that open a note: the line's first run is a superscript holding one
    /// to three digits, optionally followed by a space, and nothing else.
    static func marker(of text: InlineText) -> Int? {
        guard case let .text(value, style)? = text.elements.first, style.contains(.superscript),
              text.elements.count > 1 else { return nil }
        let digits = value.trimmingCharacters(in: .whitespaces)
        guard (1...3).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(digits), number > 0 else { return nil }
        return number
    }

    /// The separator must follow at least three lines of a larger body size; every element
    /// after it must be an untagged proportional text line at most 90% of that size, in one
    /// column, at close line spacing. Markers on the page must count up from the first.
    /// Any other layout keeps the existing spatial reconstruction.
    static func layout(in elements: [LayoutReconstructor.Element], page: PageContent,
                       continuesNote: Bool) -> Layout? {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage,
              let separator = elements.firstIndex(where: { $0.line.map(isSeparator) == true }),
              separator > 0, separator + 1 < elements.count,
              let rule = elements[separator].line else { return nil }
        var lines: [TextLine] = []
        for element in elements[(separator + 1)...] {
            guard let line = element.line, element.image == nil, !line.monospaced,
                  line.structure == nil, !isSeparator(line) else { return nil }
            lines.append(line)
        }
        let above = elements[..<separator].compactMap(\.line)
        let body = LayoutReconstructor.bodySize(above)
        guard body >= 4, above.filter({ Int($0.fontSize.rounded()) == Int(body) }).count >= 3 else { return nil }
        let size = LayoutReconstructor.bodySize(lines)
        guard size >= 4, size <= body * 0.9, lines.allSatisfy({ $0.fontSize <= body * 0.9 }),
              rule.fontSize <= body * 1.1 else { return nil }
        let edge = rule.rect.minX
        var notes: [Note] = []
        var expected: Int?
        var previous = rule
        for (offset, line) in lines.enumerated() {
            let gap = previous.rect.minY - line.rect.maxY
            guard gap >= -size * 0.2, gap <= size * 0.8,
                  line.rect.minX >= edge - size * 0.25, line.rect.minX <= edge + size * 3 else { return nil }
            let index = separator + 1 + offset
            if let number = marker(of: line.content) {
                if let expected { guard number == expected else { return nil } }
                expected = number + 1
                notes.append(Note(range: index...index, marker: number))
            } else if notes.isEmpty {
                guard continuesNote else { return nil }
                notes.append(Note(range: index...index, marker: nil))
            } else {
                notes[notes.count - 1].range = notes[notes.count - 1].range.lowerBound...index
            }
            previous = line
        }
        return notes.isEmpty ? nil : Layout(separator: separator, notes: notes)
    }

    /// A note's text with the marker run holding only its digits, so its trailing space
    /// is ordinary text rather than part of the superscript.
    static func normalizedMarker(_ text: InlineText) -> InlineText {
        guard case let .text(value, style)? = text.elements.first, style.contains(.superscript),
              value.last?.isWhitespace == true else { return text }
        let digits = String(value.reversed().drop(while: \.isWhitespace).reversed())
        var result = text
        result.elements.replaceSubrange(0...0, with: [.text(digits, style), .text(" ", [])])
        return result
    }
}
