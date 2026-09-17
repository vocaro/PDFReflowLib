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
        /// A numbered list inside the page's last note that is still open where the page ends,
        /// its last line running to the column's right edge (9/11 page 543's candidate list under
        /// note 107, whose item 6 continues on page 544). The next page may resume it.
        var openList: OpenList?
        /// The note the page's last line belongs to, which the next page may continue.
        var lastNote: Note?
        /// The page's first line continues the previous page's last note paragraph: it sits at
        /// the dedented wrap edge above the page's first note start (9/11 page 532's
        /// `“Alternate View: …` under note 2 of page 531). See `continuedNote` in `layout`.
        var continuesParagraph = false
    }

    /// A numbered list left open at a page's end: the note holding it, the item number the list
    /// expects next, and how far the items sit inside the note indent.
    struct OpenList: Equatable {
        var note: Layout.Note
        var next: Int
        var inset: CGFloat
    }

    /// The chapters named by a top-margin running head, with an optional folio on either side:
    /// `NOTES TO CHAPTER N` names `N...N`; `NOTES TO CHAPTERS N-M` (hyphen or en dash) names
    /// `N...M` only for consecutive chapters, a page that closes one chapter's notes and opens
    /// the next's (9/11 pages 572 and 578, #80).
    static func chapters(on page: PageContent) -> ClosedRange<Int>? {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return nil }
        for line in page.lines {
            guard line.rect.midY >= page.bounds.minY + page.bounds.height * 0.9 else { continue }
            var words = line.text.split(whereSeparator: \.isWhitespace)
            func number(_ text: Substring) -> Bool {
                !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
            }
            if words.first.map(number) == true { words.removeFirst() }
            guard (4...5).contains(words.count), words[0] == "NOTES", words[1] == "TO",
                  words.count == 4 || number(words[4]) else { continue }
            if words[2] == "CHAPTER", number(words[3]), let chapter = Int(words[3]), chapter > 0 {
                return chapter...chapter
            }
            let bounds = words[3].split(omittingEmptySubsequences: false) { $0 == "-" || $0 == "\u{2013}" }
            guard words[2] == "CHAPTERS", bounds.count == 2, number(bounds[0]), number(bounds[1]),
                  let first = Int(bounds[0]), let last = Int(bounds[1]), first > 0, last == first + 1 else { continue }
            return first...last
        }
        return nil
    }

    /// The first chapter a notes running head names.
    static func chapter(on page: PageContent) -> Int? { chapters(on: page)?.lowerBound }

    static func hasHeading(on page: PageContent) -> Bool { chapters(on: page) != nil }

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
    /// `lastChapter` is the second chapter a `NOTES TO CHAPTERS N-M` head names (nil reads it
    /// from the page when `chapter` is nil too): such a page must switch to that chapter.
    ///
    /// `continuing` is the previous page's `openList`. A page may resume that list (#87): see
    /// `resumption`. When the resumed reading refuses the page, the page is read on its own.
    ///
    /// `continuedNote` is the previous page's `lastNote`. The lines above the page's first note
    /// start are that note's text only when the first start is the next note of the same chapter
    /// and every one of those lines reads as note text: a wrapped line at the dedented edge the
    /// page's notes share, or an unnumbered line at the note indent opening a further paragraph,
    /// in the notes' type at their spacing. A first line at the dedented edge then continues the
    /// previous page's paragraph (`continuesParagraph`), whatever letter, digit or quote opens it;
    /// a line at the indent opens a further paragraph. When that reading refuses the page, the
    /// lines stay spatial prose as before.
    static func layout(in elements: [LayoutReconstructor.Element], page: PageContent,
                       chapter: Int? = nil, lastChapter: Int? = nil, continuing: OpenList? = nil,
                       continuedNote: Layout.Note? = nil) -> Layout? {
        analyze(elements, page: page, chapter: chapter, lastChapter: lastChapter, continuing: continuing,
                continuedNote: continuedNote).layout
    }

    static func analyze(_ elements: [LayoutReconstructor.Element], page: PageContent,
                        chapter: Int? = nil, lastChapter: Int? = nil,
                        continuing: OpenList? = nil, continuedNote: Layout.Note? = nil) -> (layout: Layout?, reason: String) {
        if let continuing {
            let resumed = analyze(elements, page: page, chapter: chapter, lastChapter: lastChapter, resume: continuing)
            if resumed.layout != nil { return resumed }
        }
        if let continuedNote {
            let continued = analyze(elements, page: page, chapter: chapter, lastChapter: lastChapter, resume: nil,
                                    continued: continuedNote)
            if continued.layout != nil { return continued }
        }
        return analyze(elements, page: page, chapter: chapter, lastChapter: lastChapter, resume: nil)
    }

    /// Where a page resumes the previous page's open list: the first line numbered as the item the
    /// list expects, at or before the page's first note start. Either the page's notes continue
    /// the chapter (the first start is the open note's successor) and the item sits the list's
    /// inset inside their indent (page 545's `10.` above note 108), or the page's first start is
    /// that item itself, numbered as the list expects and not as the chapter's next note (page
    /// 544's items 7–9, which would otherwise read as the chapter's notes 7–9). The note indent is
    /// then the item edge less the inset. A bulleted list is never resumed.
    static func resumption(_ elements: [LayoutReconstructor.Element], open: OpenList,
                           first: Int) -> (item: Int, indent: CGFloat)? {
        guard let initial = elements[first].line, let firstNumber = number(of: initial) else { return nil }
        let size = initial.fontSize
        guard let item = elements[...first].firstIndex(where: { element in
            guard let line = element.line, let marker = subItem(line) else { return false }
            return !marker.bullet && marker.first == open.next && abs(line.fontSize - size) <= size * 0.1
        }), let line = elements[item].line else { return nil }
        let indent = line.rect.minX - open.inset
        if item < first {
            guard firstNumber == open.note.number + 1, abs(indent - initial.rect.minX) <= size * 0.25 else { return nil }
        } else {
            guard firstNumber == open.next, open.next != open.note.number + 1 else { return nil }
        }
        return (item, indent)
    }

    private static func analyze(_ elements: [LayoutReconstructor.Element], page: PageContent,
                                chapter: Int?, lastChapter: Int?, resume: OpenList?,
                                continued continuedNote: Layout.Note? = nil) -> (layout: Layout?, reason: String) {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return (nil, "page fallback") }
        let read = chapter == nil ? chapters(on: page) : nil
        guard let heading = chapter ?? read?.lowerBound else { return (nil, "no heading") }
        let last = chapter == nil ? read?.upperBound : lastChapter
        guard elements.allSatisfy({ $0.image == nil }) else { return (nil, "image") }
        guard let firstNote = firstStart(in: elements), let initial = elements[firstNote].line else {
            return (nil, "no numbered start")
        }
        let size = initial.fontSize
        guard size.isFinite, size >= 4 else { return (nil, "size") }
        var layout = Layout()
        var first = firstNote, indentX = initial.rect.minX
        var expected = number(of: initial)!, count = 0, chapter = heading
        var continuationX: CGFloat?
        var previous: TextLine?
        // A list inside the current note: its items' edge, whether they are bullets, the next
        // item number, and the bullets' hanging edge once a wrapped line has set it.
        var sublist: (x: CGFloat, bullet: Bool, next: Int, wrapX: CGFloat?)?
        // The element that opened the current list (the page's first when resumed).
        var sublistStart = first
        // A resumed list continues the previous page's last note from the top of this page: every
        // line before the resumed item is that note's text, and the note is open without a start.
        var resumed = false
        if let open = resume {
            guard open.note.chapter == heading, let resumption = resumption(elements, open: open, first: firstNote),
                  let item = elements[resumption.item].line else { return (nil, "no resumed list") }
            first = 0
            sublistStart = 0
            indentX = resumption.indent
            expected = open.note.number + 1
            sublist = (item.rect.minX, false, open.next, nil)
            resumed = true
        }
        // The previous page's last note continues above this page's first start (see `layout`).
        var continued = false
        if let note = continuedNote, resume == nil {
            guard firstNote > 0, note.chapter == heading, number(of: initial) == note.number + 1 else {
                return (nil, "no continued note")
            }
            first = 0
            continued = true
        }
        var start = first
        for index in first..<elements.count {
            guard let line = elements[index].line, !line.monospaced, line.structure == nil else {
                return (nil, "element \(index): monospaced or tagged")
            }
            let atIndent = abs(line.rect.minX - indentX) <= size * 0.25
            if abs(line.fontSize - size) > size * 0.1 {
                // The next chapter's opening heading between its predecessor's last note and
                // its own note 1: larger type, dedented, number then title.
                guard let before = previous, count >= 1, line.fontSize > size, !atIndent,
                      line.rect.minX >= indentX - size * 3,
                      opensChapter(line, number: chapter + 1),
                      before.rect.minY - line.rect.maxY <= size * 4,
                      index + 1 < elements.count, let next = elements[index + 1].line,
                      number(of: next) == 1, abs(next.rect.minX - indentX) <= size * 0.25,
                      line.rect.minY - next.rect.maxY <= size * 1.5 else {
                    return (nil, "element \(index): size")
                }
                chapter += 1
                expected = 1
                sublist = nil
                // The heading's spacing was checked above; note 1 needs no further gap test.
                previous = nil
                continue
            }
            // A note's own list opens with its first item (a bullet at or inside the note indent,
            // or `1.` inside it) and may be set off by added space.
            let noteOpen = count >= 1 || resumed || continued
            // The page's first line of a continued note has its previous line on the previous page.
            let opensContinuedPage = continued && index == 0
            let marker = noteOpen ? subItem(line) : nil
            let opensSublist = sublist == nil && previous != nil && marker.map { marker in
                let inset = line.rect.minX - indentX
                return marker.bullet ? inset >= -size * 0.25 && inset <= size * 3
                    : marker.first == 1 && inset >= size && inset <= size * 3
            } == true
            // The note after a numbered list may be set off by the same added space that opened
            // the list (page 545's note 108 after item 10).
            let closesSublist = sublist?.bullet == false && atIndent && number(of: line) == expected
            if let previous {
                let gap = previous.rect.minY - line.rect.maxY
                guard gap >= -size * 0.2, gap <= (opensSublist || closesSublist ? size * 1.6 : size * 0.8) else {
                    return (nil, "element \(index): gap")
                }
            }
            if let marker, opensSublist {
                sublist = (line.rect.minX, marker.bullet, marker.last + 1, nil)
                sublistStart = index
                start = index
                layout.paragraphs[index] = start
                previous = line
                continue
            }
            if let open = sublist {
                let onItemEdge = abs(line.rect.minX - open.x) <= size * 0.25
                if onItemEdge, let marker, marker.bullet == open.bullet, open.bullet || marker.first == open.next {
                    // The list's next item.
                    sublist?.next = marker.last + 1
                    start = index
                    layout.paragraphs[index] = start
                    previous = line
                    continue
                }
                if !open.bullet, onItemEdge, marker == nil, line.text.filter(\.isLetter).count >= 10,
                   line.text.range(of: "^(?:[•*−-]|[A-Za-z][.)]|[0-9]+[.)])\\s", options: .regularExpression) == nil {
                    // A numbered item's further paragraph, set at the item edge (as the source
                    // continues note 107's list on page 544: `In December 1999, …` under item 9).
                    start = index
                    layout.paragraphs[index] = start
                    previous = line
                    continue
                }
                // A wrapped item line: numbered items wrap back to the note indent (and never
                // open the note the sequence expects there); bullets wrap to a hanging edge.
                let hanging = line.rect.minX - open.x
                let wraps = open.bullet
                    ? hanging > size * 0.25 && hanging <= size * 1.5
                        && open.wrapX.map { abs($0 - line.rect.minX) <= size * 0.25 } ?? true
                    : atIndent && number(of: line) != expected
                if wraps, previous?.wraps != false, marker == nil,
                   line.text.range(of: "^(?:[•*−-]|[A-Za-z]\\))\\s", options: .regularExpression) == nil {
                    if open.bullet { sublist?.wrapX = line.rect.minX }
                    layout.paragraphs[index] = start
                    previous = line
                    continue
                }
                sublist = nil
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
                guard previous != nil || opensContinuedPage, noteOpen, line.text.filter(\.isLetter).count >= 10,
                      line.text.range(of: "^(?:[•*−-]|[A-Za-z][.)]|[0-9]+[.)])\\s", options: .regularExpression) == nil
                else { return (nil, "element \(index): indented non-note") }
                start = index
            } else {
                // A wrapped citation line at the shared dedented edge may open with `p. 11`
                // or an initial (`E. Booker`); bullets and `a)` items do not wrap a note.
                let indent = indentX - line.rect.minX
                let wrapsPrevious = previous.map { $0.wraps != false && $0.rect.width >= size * 12 } ?? opensContinuedPage
                guard wrapsPrevious,
                      indent >= size * 0.8, indent <= size * 3,
                      line.text.range(of: "^(?:[•*−-]|[A-Za-z]\\))\\s", options: .regularExpression) == nil,
                      continuationX.map({ abs($0 - line.rect.minX) <= size * 0.25 }) ?? true else {
                    return (nil, "element \(index): continuation geometry")
                }
                continuationX = line.rect.minX
                if opensContinuedPage { layout.continuesParagraph = true }
            }
            layout.paragraphs[index] = start
            previous = line
        }
        // A resumed page continues its note and may hold no note start of its own.
        guard count >= 3 || resumed else { return (nil, "fewer than three notes") }
        // A two-chapter head is evidence only for a page that really opens the second chapter.
        if let last, last != heading, chapter != last { return (nil, "head names chapter \(last)") }
        guard continuationX != nil || resumed else { return (nil, "no dedented continuation") }
        // The list is left open only when its last line runs to the list's right edge (the widest
        // of at least two of its lines on this page; page 543 sets the list narrower than the
        // notes), so the item's text continues on the next page.
        let listEdges = elements[sublistStart...].compactMap { $0.line?.rect.maxX }
        if let open = sublist, !open.bullet, listEdges.count >= 2, let rightEdge = listEdges.max(), let end = previous,
           end.rect.maxX >= rightEdge - size * 0.5 {
            layout.openList = OpenList(note: .init(number: expected - 1, chapter: chapter), next: open.next,
                                       inset: open.x - indentX)
        }
        layout.lastNote = .init(number: expected - 1, chapter: chapter)
        return (layout, resumed ? "accepted resuming a list" : continued ? "accepted continuing a note" : "accepted")
    }

    /// A notes page keyed to a chapter other than the one its running head prints.
    struct Rescope: Equatable {
        var page: Int
        var printed: Int
        var chapter: Int
        var numbers: ClosedRange<Int>
    }

    /// Scope notes by numbering continuity where a running head misprints its chapter (#87): 9/11
    /// page 496 is headed `NOTES TO CHAPTER 4` but holds chapter 3's notes 93–112, between page
    /// 495's note 92 and page 497's note 113. Every condition must hold, so the printed head
    /// wins unless it is contradicted from both sides:
    /// - the page's head names one chapter M and every note on the page is keyed to M;
    /// - its first note is not note 1 and continues the last note of the previous physical page,
    ///   which is keyed to another chapter N;
    /// - chapter M's note 1 is on another page, and another page also claims one of this page's
    ///   numbers in M (the notes collide there);
    /// - chapter N claims none of this page's numbers yet.
    /// The page's notes are then keyed to N. Numbers restarting at 1 never move a page.
    /// `heads` maps a physical page to the chapters its `NOTES TO CHAPTER` head names.
    @discardableResult
    static func scopeByContinuity(_ blocks: inout [ReflowBlock], heads: [Int: ClosedRange<Int>]) -> [Rescope] {
        var byPage: [Int: [Int]] = [:]
        for index in blocks.indices {
            guard let key = blocks[index].note, case .chapter = key.scope else { continue }
            byPage[blocks[index].page, default: []].append(index)
        }
        func chapterOf(_ index: Int) -> Int? {
            if case let .chapter(chapter)? = blocks[index].note?.scope { return chapter }
            return nil
        }
        var decisions: [Rescope] = []
        for page in byPage.keys.sorted() {
            guard let head = heads[page], head.count == 1 else { continue }
            let printed = head.lowerBound
            guard let notes = byPage[page], notes.allSatisfy({ chapterOf($0) == printed }),
                  let firstKey = blocks[notes[0]].note, firstKey.number > 1,
                  let before = byPage[page - 1]?.last, let previous = blocks[before].note,
                  let chapter = chapterOf(before), chapter != printed, previous.number == firstKey.number - 1 else { continue }
            let numbers = Set(notes.compactMap { blocks[$0].note?.number })
            var printedElsewhere: Set<Int> = [], continuedChapter: Set<Int> = []
            for (other, indices) in byPage where other != page {
                for index in indices {
                    guard let key = blocks[index].note else { continue }
                    if chapterOf(index) == printed { printedElsewhere.insert(key.number) }
                    if chapterOf(index) == chapter { continuedChapter.insert(key.number) }
                }
            }
            guard printedElsewhere.contains(1), !printedElsewhere.isDisjoint(with: numbers),
                  continuedChapter.isDisjoint(with: numbers), let low = numbers.min(), let high = numbers.max() else { continue }
            for index in notes {
                blocks[index].note?.scope = .chapter(chapter)
            }
            decisions.append(.init(page: page, printed: printed, chapter: chapter, numbers: low...high))
        }
        return decisions
    }

    /// An item of a list inside a note: a bullet, or a number (`1.`, `4 and 5.`) followed by
    /// a capitalized word. `first` and `last` are the item's numbers (zero for a bullet).
    static func subItem(_ line: TextLine) -> (bullet: Bool, first: Int, last: Int)? {
        if line.text.hasPrefix("• "), line.text.filter(\.isLetter).count >= 4 { return (true, 0, 0) }
        guard let match = line.text.firstMatch(of: /^([1-9][0-9]{0,2})(?: and ([1-9][0-9]{0,2}))?\.\s*\p{Lu}/),
              let first = Int(match.1) else { return nil }
        let last = match.2.flatMap { Int($0) } ?? first
        return last == first || last == first + 1 ? (false, first, last) : nil
    }

    /// `2 The Foundation of the New Terrorism`: the chapter number, whitespace, then a title
    /// with letters.
    static func opensChapter(_ line: TextLine, number: Int) -> Bool {
        let words = line.text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, Int(words[0]) == number else { return false }
        return words.dropFirst().joined().filter(\.isLetter).count >= 3
    }
}
