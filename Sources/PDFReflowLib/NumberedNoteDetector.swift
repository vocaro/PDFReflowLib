import Foundation

/// Bounded native endnote layout: the notes of one chapter, each opening with its printed
/// number, on a page headed `NOTES TO CHAPTER N`. It supplies note numbers and their chapter
/// scope; reference-to-note ownership is decided later by `NoteLinker`.
enum NumberedNoteDetector {
    struct Layout: Equatable {
        struct Note: Equatable {
            var number: Int
            var chapter: Int
        }
        /// Element index → index of the first element of its paragraph.
        var paragraphs: [Int: Int] = [:]
        /// Paragraph start index → the note that paragraph opens. A note's further
        /// paragraphs have no entry.
        var notes: [Int: Note] = [:]
    }

    /// The chapter named by a top-margin `NOTES TO CHAPTER N` running head, with an optional
    /// folio on either side. `NOTES TO CHAPTERS 9-10` names no single chapter.
    static func chapter(on page: PageContent) -> Int? {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return nil }
        for line in page.lines {
            guard line.rect.midY >= page.bounds.minY + page.bounds.height * 0.9 else { continue }
            var words = line.text.split(whereSeparator: \.isWhitespace)
            func number(_ text: Substring) -> Bool {
                !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
            }
            if words.first.map(number) == true { words.removeFirst() }
            guard (4...5).contains(words.count), words[0] == "NOTES", words[1] == "TO",
                  words[2] == "CHAPTER", number(words[3]), let chapter = Int(words[3]), chapter > 0,
                  words.count == 4 || number(words[4]) else { continue }
            return chapter
        }
        return nil
    }

    static func hasHeading(on page: PageContent) -> Bool { chapter(on: page) != nil }

    /// Element indices map to a note's first element. Refuse the page if any later content
    /// breaks the sequence, typography, close line spacing or first-line indentation pattern.
    /// Preceding content may be a previous page's continuation and remains spatial prose.
    static func groups(in elements: [LayoutReconstructor.Element], page: PageContent,
                       headingEvidence: Bool = false) -> [Int: Int] {
        layout(in: elements, page: page, chapter: headingEvidence ? 0 : nil)?.paragraphs ?? [:]
    }

    /// A note opens with its number (up to three digits; a year is not a note), a period and
    /// a letter, opening quote or bracket.
    static func number(of line: TextLine) -> Int? {
        guard line.text.range(of: "^[1-9][0-9]{0,2}\\.\\s*[\\p{L}\\p{Pi}\\p{Ps}\"]", options: .regularExpression) != nil,
              let end = line.text.firstIndex(of: ".") else { return nil }
        return Int(line.text[..<end])
    }

    /// The first note start: the first numbered line on the left edge most numbered lines
    /// share (the note indent), so a dedented `5.This` continuation or a year ahead of the run
    /// does not set the indent. Ties go to the more indented edge.
    static func firstStart(in elements: [LayoutReconstructor.Element]) -> Int? {
        let numbered = elements.indices.compactMap { index -> (index: Int, line: TextLine)? in
            guard let line = elements[index].line, number(of: line) != nil else { return nil }
            return (index, line)
        }
        var edges: [(x: CGFloat, first: Int, count: Int)] = []
        for start in numbered {
            let size = start.line.fontSize
            if let edge = edges.indices.first(where: { abs(edges[$0].x - start.line.rect.minX) <= size * 0.25 }) {
                edges[edge].count += 1
            } else {
                edges.append((start.line.rect.minX, start.index, 1))
            }
        }
        return edges.max { $0.count == $1.count ? $0.x < $1.x : $0.count < $1.count }?.first
    }

    /// `chapter` is the running head's chapter (0 when a caller supplies heading evidence
    /// without a number); nil reads it from the page. Notes start at the indented left edge
    /// with consecutive numbers; their wrapped lines dedent to one shared edge. An unnumbered
    /// line at the indent is a further paragraph of the current note (page 469's note 1, page
    /// 473's note 66). A larger line `N Title` naming the next chapter, followed by note 1,
    /// switches the scope mid-page (page 484: chapter 1's note 241, then chapter 2's notes).
    static func layout(in elements: [LayoutReconstructor.Element], page: PageContent,
                       chapter: Int? = nil) -> Layout? {
        analyze(elements, page: page, chapter: chapter).layout
    }

    static func analyze(_ elements: [LayoutReconstructor.Element], page: PageContent,
                        chapter: Int? = nil) -> (layout: Layout?, reason: String) {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return (nil, "page fallback") }
        guard let heading = chapter ?? self.chapter(on: page) else { return (nil, "no heading") }
        guard elements.allSatisfy({ $0.image == nil }) else { return (nil, "image") }
        guard let first = firstStart(in: elements), let initial = elements[first].line else {
            return (nil, "no numbered start")
        }
        let size = initial.fontSize
        guard size.isFinite, size >= 4 else { return (nil, "size") }
        var layout = Layout()
        var start = first, expected = number(of: initial)!, count = 0, chapter = heading
        var continuationX: CGFloat?
        var previous: TextLine?
        for index in first..<elements.count {
            guard let line = elements[index].line, !line.monospaced, line.structure == nil else {
                return (nil, "element \(index): monospaced or tagged")
            }
            let atIndent = abs(line.rect.minX - initial.rect.minX) <= size * 0.25
            if abs(line.fontSize - size) > size * 0.1 {
                // The next chapter's opening heading between its predecessor's last note and
                // its own note 1: larger type, dedented, number then title.
                guard let before = previous, count >= 1, line.fontSize > size, !atIndent,
                      line.rect.minX >= initial.rect.minX - size * 3,
                      opensChapter(line, number: chapter + 1),
                      before.rect.minY - line.rect.maxY <= size * 4,
                      index + 1 < elements.count, let next = elements[index + 1].line,
                      number(of: next) == 1, abs(next.rect.minX - initial.rect.minX) <= size * 0.25,
                      line.rect.minY - next.rect.maxY <= size * 1.5 else {
                    return (nil, "element \(index): size")
                }
                chapter += 1
                expected = 1
                // The heading's spacing was checked above; note 1 needs no further gap test.
                previous = nil
                continue
            }
            if let previous {
                let gap = previous.rect.minY - line.rect.maxY
                guard gap >= -size * 0.2, gap <= size * 0.8 else { return (nil, "element \(index): gap") }
            }
            if atIndent, let value = number(of: line) {
                guard value == expected else { return (nil, "element \(index): expected \(expected), found \(value)") }
                guard line.text.filter(\.isLetter).count >= 4 else { return (nil, "element \(index): short") }
                expected += 1
                count += 1
                start = index
                layout.notes[start] = .init(number: value, chapter: chapter)
            } else if atIndent {
                // A further paragraph of the current note, never a list item or a lone number.
                guard previous != nil, count >= 1, line.text.filter(\.isLetter).count >= 10,
                      line.text.range(of: "^(?:[•*−-]|[A-Za-z][.)]|[0-9]+[.)])\\s", options: .regularExpression) == nil
                else { return (nil, "element \(index): indented non-note") }
                start = index
            } else {
                // A wrapped citation line at the shared dedented edge may open with `p. 11`
                // or an initial (`E. Booker`); bullets and `a)` items do not wrap a note.
                let indent = initial.rect.minX - line.rect.minX
                guard let previous, previous.wraps != false,
                      indent >= size * 0.8, indent <= size * 3,
                      previous.rect.width >= size * 12,
                      line.text.range(of: "^(?:[•*−-]|[A-Za-z]\\))\\s", options: .regularExpression) == nil,
                      continuationX.map({ abs($0 - line.rect.minX) <= size * 0.25 }) ?? true else {
                    return (nil, "element \(index): continuation geometry")
                }
                continuationX = line.rect.minX
            }
            layout.paragraphs[index] = start
            previous = line
        }
        guard count >= 3 else { return (nil, "fewer than three notes") }
        guard continuationX != nil else { return (nil, "no dedented continuation") }
        return (layout, "accepted")
    }

    /// `2 The Foundation of the New Terrorism`: the chapter number, whitespace, then a title
    /// with letters.
    static func opensChapter(_ line: TextLine, number: Int) -> Bool {
        let words = line.text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, Int(words[0]) == number else { return false }
        return words.dropFirst().joined().filter(\.isLetter).count >= 3
    }
}
