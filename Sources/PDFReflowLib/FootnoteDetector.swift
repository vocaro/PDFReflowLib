import CoreGraphics
import Foundation

/// Bounded page-bottom footnote layout. Two separators are recognized: a typographic rule
/// drawn as dash characters, and, where a document draws none, the white space and type-size
/// drop that set a block of marked notes off from the body (#61). In both forms the notes run
/// to the foot of the page and each opens with a raised marker. Not a reference-to-note
/// ownership detector.
enum FootnoteDetector {
    /// A note's printed marker. Table notes are lettered as well as numbered (`eEstimated.`),
    /// so a marker is not always a number; only numbers carry a `NoteKey`.
    enum Marker: Equatable {
        case number(Int)
        case letter(String)
    }

    struct Note: Equatable {
        /// Element indices of the note's lines in reading order.
        var range: ClosedRange<Int>
        /// The raised marker opening the note; nil for the continuation of the previous
        /// page's last note, which is admitted only when that page ended in a note.
        var marker: Marker?
    }

    struct Layout: Equatable {
        /// A drawn dash separator's element index, dropped from the output; nil when the
        /// notes are set off by white space alone and no element has to be removed.
        var separator: Int?
        /// Every element of the note area, in reading order. Elements outside it stay body.
        var range: ClosedRange<Int>
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
        guard case let .number(value)? = noteMarker(of: text) else { return nil }
        return value
    }

    /// The raised marker that opens a note: the line's first run is a superscript holding
    /// either one to three digits or a single letter, optionally followed by a space, and the
    /// note's text follows it in the same line.
    static func noteMarker(of text: InlineText) -> Marker? {
        guard case let .text(value, style)? = text.elements.first, style.contains(.superscript),
              text.elements.count > 1 else { return nil }
        let printed = value.trimmingCharacters(in: .whitespaces)
        if printed.count == 1, let character = printed.first, character.isLetter, character.isASCII {
            return .letter(printed)
        }
        guard (1...3).contains(printed.count), printed.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(printed), number > 0 else { return nil }
        return .number(number)
    }

    /// A text line that can belong to a note area: ordinary proportional prose with no
    /// structure tag, no preserved image or table, and not a separator of its own.
    private static func noteLine(_ element: LayoutReconstructor.Element) -> TextLine? {
        guard let line = element.line, element.image == nil, element.table == nil, !element.boundary,
              !line.monospaced, line.structure == nil, !isSeparator(line) else { return nil }
        return line
    }

    /// Page-wide refusals shared by both separators. A recognized (OCR) page, a synthetic text
    /// style or a page kept as an image carries no reliable raised markers or type sizes.
    private static func admissible(_ page: PageContent) -> Bool {
        !page.recognized && !page.hasSyntheticTextStyle && !page.requiresPageImage
    }

    /// The body size above a note area, and whether enough body lines establish it.
    private static func bodySize(above start: Int, in elements: [LayoutReconstructor.Element]) -> CGFloat? {
        let above = elements[..<start].compactMap(\.line)
        let body = LayoutReconstructor.bodySize(above)
        guard body >= 4, above.filter({ Int($0.fontSize.rounded()) == Int(body) }).count >= 3 else { return nil }
        return body
    }

    /// Walks a note area's lines into notes: each marker opens one, marker-less lines continue
    /// the open one, and numbers count up. `edge` is the left edge the lines must share and
    /// `size` their body size; `first` is the geometry the first line's gap is measured from.
    /// Returns nil when the spacing, the edges or the marker sequence refuse the area.
    private static func notes(in lines: [TextLine], from start: Int, edge: CGFloat, size: CGFloat,
                              below first: CGRect, continuesNote: Bool) -> [Note]? {
        var notes: [Note] = []
        var expected: Int?
        var previous = first
        for (offset, line) in lines.enumerated() {
            let gap = previous.minY - line.rect.maxY
            guard gap >= -size * 0.2, gap <= size * 0.8,
                  line.rect.minX >= edge - size * 0.25, line.rect.minX <= edge + size * 3 else { return nil }
            let index = start + offset
            if let marker = noteMarker(of: line.content) {
                if case let .number(number) = marker {
                    if let expected { guard number == expected else { return nil } }
                    expected = number + 1
                }
                notes.append(Note(range: index...index, marker: marker))
            } else if notes.isEmpty {
                guard continuesNote else { return nil }
                notes.append(Note(range: index...index, marker: nil))
            } else {
                notes[notes.count - 1].range = notes[notes.count - 1].range.lowerBound...index
            }
            previous = line.rect
        }
        // A raised letter is a note marker only beside a counted-up numbered series: USGS
        // table notes open with `e` for estimated before notes 1, 2, 3. Letters on their own
        // are not evidence of a note list, whatever separator stands above them.
        let markers = notes.compactMap(\.marker)
        if markers.contains(where: { if case .letter = $0 { true } else { false } }),
           !markers.contains(where: { if case .number = $0 { true } else { false } }) { return nil }
        return notes.isEmpty ? nil : notes
    }

    /// The separator must follow at least three lines of a larger body size; every element
    /// after it must be an untagged proportional text line at most 90% of that size, in one
    /// column, at close line spacing. Markers on the page must count up from the first.
    /// Any other layout keeps the existing spatial reconstruction.
    static func layout(in elements: [LayoutReconstructor.Element], page: PageContent,
                       continuesNote: Bool) -> Layout? {
        ruled(in: elements, page: page, continuesNote: continuesNote)
            ?? unruled(in: elements, page: page)
    }

    private static func ruled(in elements: [LayoutReconstructor.Element], page: PageContent,
                              continuesNote: Bool) -> Layout? {
        guard admissible(page),
              let separator = elements.firstIndex(where: { $0.line.map(isSeparator) == true }),
              separator > 0, separator + 1 < elements.count,
              let rule = elements[separator].line else { return nil }
        var lines: [TextLine] = []
        for element in elements[(separator + 1)...] {
            guard let line = noteLine(element) else { return nil }
            lines.append(line)
        }
        guard let body = bodySize(above: separator, in: elements) else { return nil }
        let size = LayoutReconstructor.bodySize(lines)
        guard size >= 4, size <= body * 0.9, lines.allSatisfy({ $0.fontSize <= body * 0.9 }),
              rule.fontSize <= body * 1.1,
              let notes = notes(in: lines, from: separator + 1, edge: rule.rect.minX, size: size,
                                below: rule.rect, continuesNote: continuesNote) else { return nil }
        return Layout(separator: separator, range: (separator + 1)...(elements.count - 1), notes: notes)
    }

    /// Table notes printed with no rule above them (USGS Mineral Commodity Summaries, #61).
    /// Without a drawn separator the evidence must be entirely typographic, so this form is
    /// admitted only for a block that reads unmistakably as a note list: a run of small lines
    /// closing the page, every line at most 90% of the body size and sharing one left edge at
    /// the body's own column, set off from the last body line by at least the gap that already
    /// breaks a paragraph and by more than the block's own leading, with at least two notes
    /// whose markers are raised and whose numbers count up. A continuation from the previous
    /// page is never admitted here: with no separator, a marker-less first line is prose.
    /// Only page furniture — at most two body-size lines, such as a running foot the document
    /// is too short to repeat — may follow the block.
    private static func unruled(in elements: [LayoutReconstructor.Element], page: PageContent) -> Layout? {
        // The area opens at the first marked line on the page, and only when no marked line
        // precedes it: a body line opening with a raised marker is not a note area's start.
        guard admissible(page), let opening = elements.indices.first(where: { index in
            guard let line = noteLine(elements[index]), noteMarker(of: line.content) != nil else { return false }
            return elements[..<index].allSatisfy { noteLine($0).map { noteMarker(of: $0.content) == nil } ?? true }
        }), opening > 0, let body = bodySize(above: opening, in: elements),
              // The block must sit directly under body prose, not under an image or a table, so
              // the white space above it is measured against the line it is set off from.
              let above = elements[opening - 1].line else { return nil }
        var lines: [TextLine] = []
        var end = opening - 1
        for index in opening..<elements.count {
            guard let line = noteLine(elements[index]), line.fontSize <= body * 0.9 else { break }
            lines.append(line)
            end = index
        }
        // Only page furniture may follow: body-size lines, never an image, a table or prose.
        let trailing = elements[(end + 1)...]
        guard lines.count >= 2, trailing.count <= 2, trailing.allSatisfy({ element in
            noteLine(element).map { $0.fontSize >= body * 0.85 } ?? false
        }) else { return nil }
        let size = LayoutReconstructor.bodySize(lines)
        guard size >= 4, size <= body * 0.9 else { return nil }
        // The block sits at the body's own left edge, below the body, and is set off from it by
        // at least the gap that already breaks a paragraph and by more than its own leading.
        let edge = lines.map(\.rect.minX).min() ?? 0
        let column = elements[..<opening].compactMap(\.line)
            .filter { Int($0.fontSize.rounded()) == Int(body) }.map(\.rect.minX).min()
        guard let column, abs(edge - column) <= body * 1.5,
              let first = lines.first, first.rect.maxY <= above.rect.minY else { return nil }
        let gap = above.rect.minY - first.rect.maxY
        let leading = zip(lines, lines.dropFirst()).map { $0.rect.minY - $1.rect.maxY }.max() ?? 0
        // `notes` measures each line's gap from the one above it; the block's own first gap is
        // the white-space separator checked here, so it is handed a zero-gap reference.
        guard gap >= body * 0.9, gap >= leading + size * 0.5,
              let notes = notes(in: lines, from: opening, edge: edge, size: size,
                                below: CGRect(x: edge, y: first.rect.maxY, width: 0, height: 0),
                                continuesNote: false),
              notes.filter({ $0.marker != nil }).count >= 2 else { return nil }
        return Layout(separator: nil, range: opening...end, notes: notes)
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
