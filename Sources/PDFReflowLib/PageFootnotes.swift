import Foundation

/// Footnotes the page sets at its own foot, and the raised numbers in its text that refer to them
/// (#299).
///
/// This is reference-to-note ownership, which `NumberedNoteDetector` is explicitly not: that one
/// lays out a page of endnotes and links nothing. Every piece of evidence here is the page's own.
/// A note opens with a number and is set smaller than the text; the notes lie below every line
/// of the body's size and every line that refers to them; their numbers run on by one
/// down each column and across the columns; and each number is raised exactly once in the text
/// above, as a reference — after a word, with nothing but punctuation or space after it, and no
/// arithmetic nearby. A page that falls short anywhere keeps its notes as ordinary paragraphs.
enum PageFootnotes {
    struct Note: Equatable {
        var number: Int
        /// The opening line, then the lines that continue it, top to bottom.
        var lines: [TextLine]
    }

    struct Plan: Equatable {
        var page: Int
        var notes: [Note]

        /// The note a line belongs to, as an index into `notes`.
        func note(containing line: TextLine) -> Int? {
            notes.firstIndex { $0.lines.contains(line) }
        }

        func identifier(of note: Int) -> String { PageFootnotes.identifier(page: page, number: notes[note].number) }
    }

    /// The anchor of footnote `number` on physical page `page`. Physical pages and a page's own
    /// numbers are unique, so the identifier is too; the `fn` keeps it apart from a scanned
    /// endnote's, which is digits throughout.
    static func identifier(page: Int, number: Int) -> String { "note-fn-\(page)-\(number)" }

    /// The page's footnotes, or nil when the page does not establish them.
    ///
    /// `lines` are the lines that still reflow, after crops have taken theirs; `body` is the
    /// page's body size.
    static func plan(page: PageContent, lines: [TextLine], body: CGFloat) -> Plan? {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage,
              body.isFinite, body >= 4 else { return nil }
        // A note opens with its number and is set smaller than the text it annotates. A line
        // states the size of its first glyph, which on a note is the raised number (3.5 points on
        // the Dietary Guidelines' page 2, 4.08 on the Fed's figure note, both with a line 8 points
        // high), so the notes' lines are matched to one another by their height, not that size.
        let openings = lines.compactMap { line -> (number: Int, line: TextLine)? in
            guard !line.monospaced, line.fontSize < body * 0.9, let number = marker(of: line) else { return nil }
            return (number, line)
        }
        guard let height = openings.first?.line.rect.height, height.isFinite, height > 0 else { return nil }
        func noteHeight(_ line: TextLine) -> Bool { abs(line.rect.height - height) <= height * 0.2 }
        guard openings.allSatisfy({ noteHeight($0.line) }) else { return nil }
        // Down each column, then across the columns, the numbers run on by one. A column is a run
        // of openings whose left edges stand within two body sizes of the one before; the page's
        // own measure is far wider than that.
        var columns: [[(number: Int, line: TextLine)]] = []
        for opening in openings.sorted(by: { $0.line.rect.minX < $1.line.rect.minX }) {
            if let edge = columns.last?.last?.line.rect.minX, opening.line.rect.minX - edge <= body * 2 {
                columns[columns.count - 1].append(opening)
            } else {
                columns.append([opening])
            }
        }
        let reading = columns.flatMap { $0.sorted { $0.line.rect.minY > $1.line.rect.minY } }
        guard reading.indices.allSatisfy({ reading[$0].number == reading[0].number + $0 }) else { return nil }
        // Each note gathers the small lines of its height that hang beneath it in its column; any
        // other such line below the notes' top is something the plan cannot account for.
        let top = reading.map(\.line.rect.maxY).max()!
        var notes = reading.map { Note(number: $0.number, lines: [$0.line]) }
        let rest = lines.filter { line in
            !line.monospaced && line.fontSize < body * 0.9 && noteHeight(line)
                && line.rect.maxY <= top + height * 0.25 && !reading.contains { $0.line == line }
        }.sorted { $0.rect.minY > $1.rect.minY }
        for line in rest {
            guard let owner = notes.indices.first(where: { index in
                let last = notes[index].lines.last!
                let gap = last.rect.minY - line.rect.maxY
                return last.overlapsHorizontally(line) && gap >= -height * 0.5 && gap <= height
            }) else { return nil }
            notes[owner].lines.append(line)
        }
        let noteLines = notes.flatMap(\.lines)
        let band = noteLines.map(\.rect).reduce(CGRect.null) { $0.union($1) }
        // The notes are the foot of the page: every line of the body's size stands above them.
        // A page whose running footer is still among its lines has not been cleared of its
        // furniture, and is refused here rather than guessed at.
        guard !lines.contains(where: { line in
            !noteLines.contains(line) && line.hasSize(body) && line.rect.minY < band.maxY - height * 0.25
        }) else { return nil }
        // Each number is raised exactly once, as a reference, in a line above the notes.
        let numbers = Set(notes.map(\.number))
        var raised: [Int: Int] = [:]
        for line in lines where !noteLines.contains(line) {
            for number in references(in: line.content) where numbers.contains(number) {
                guard line.rect.minY >= band.maxY - height * 0.25 else { return nil }
                raised[number, default: 0] += 1
            }
        }
        guard notes.allSatisfy({ raised[$0.number] == 1 }) else { return nil }
        return Plan(page: page.number, notes: notes)
    }

    /// The number a note opens with: one to three digits standing at the head of the line and
    /// followed by space, or raised and followed by anything.
    static func marker(of line: TextLine) -> Int? {
        guard case let .text(head, style)? = line.content.elements.first,
              let match = head.range(of: #"^[1-9][0-9]{0,2}"#, options: .regularExpression) else { return nil }
        let after = head[match.upperBound...].unicodeScalars.first
            ?? line.content.elements.dropFirst().lazy.compactMap { element -> Unicode.Scalar? in
                if case let .text(text, _) = element { return text.unicodeScalars.first }
                return nil
            }.first
        let spaced = after.map { CharacterSet.whitespaces.contains($0) || CharacterSet.controlCharacters.contains($0) } ?? false
        guard spaced || (style.contains(.superscript) && after != nil),
              line.text.dropFirst(head.distance(from: head.startIndex, to: match.upperBound))
                .contains(where: \.isLetter) else { return nil }
        return Int(head[match])
    }

    /// The note numbers a run of text raises as references, in order.
    static func references(in text: InlineText) -> [Int] {
        text.elements.indices.compactMap { reference(in: text.elements, at: $0) }
    }

    /// The number the element at `index` raises as a note reference, if it is one: digits alone
    /// in a superscript run, straight after a word of three letters or more and whatever closing
    /// mark ends it, with no letter or digit straight after, and no arithmetic just before. An
    /// exponent — `x²`, `10³`, `(a + b)²` — fails on the word or on the arithmetic.
    static func reference(in elements: [InlineText.Element], at index: Int) -> Int? {
        guard index > 0, case let .text(run, style) = elements[index],
              style.contains(.superscript), !style.contains(.subscript) else { return nil }
        let digits = run.trimmingCharacters(in: .whitespaces)
        guard (1...3).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(digits), number > 0,
              case let .text(before, _) = elements[index - 1], !run.hasPrefix(" "),
              before.range(of: #"\p{L}{3,}[.,;:!?)\]”’"]{0,2}$"#, options: .regularExpression) != nil,
              before.suffix(30).range(of: #"[=+×÷^]"#, options: .regularExpression) == nil else { return nil }
        if index + 1 < elements.count, case let .text(after, _) = elements[index + 1],
           let next = after.first, next.isLetter || next.isNumber { return nil }
        return number
    }

    /// Where one of a note's lines stands in the reading order: the element that opens the note,
    /// which groups its lines in the assembler, and the note, as an index into the plan's.
    struct Member: Equatable {
        var opening: Int
        var note: Int
    }

    /// Each element that is a note's line, mapped to its note, when every note's lines run on
    /// unbroken in the reading order from its opening; nil otherwise, because a note the reading
    /// order splits would be written as two notes with one anchor.
    static func groups(in elements: [LayoutReconstructor.Element], plan: Plan) -> [Int: Member]? {
        var result: [Int: Member] = [:]
        var seen = Set<Int>()
        for (index, element) in elements.enumerated() {
            guard let line = element.line, let note = plan.note(containing: line) else { continue }
            if seen.contains(note) {
                guard let previous = result[index - 1], previous.note == note else { return nil }
                result[index] = previous
            } else {
                guard plan.notes[note].lines.first == line else { return nil }
                seen.insert(note)
                result[index] = Member(opening: index, note: note)
            }
        }
        return seen.count == plan.notes.count ? result : nil
    }

    /// The page's blocks with each reference linked to its note. Where the finished blocks do not
    /// raise every number exactly once — a join that merged a reference into its neighbour, say —
    /// nothing is linked and the notes stay ordinary paragraphs, so no note is left that a reader
    /// can reach only through a link that is not there.
    static func linking(_ blocks: [ReflowBlock], plan: Plan) -> [ReflowBlock] {
        let identifiers = Dictionary(uniqueKeysWithValues: plan.notes.indices.map {
            (plan.notes[$0].number, plan.identifier(of: $0))
        })
        var result = blocks
        var linked: [Int: Int] = [:]
        for index in result.indices where result[index].note == nil {
            func link(_ text: InlineText) -> InlineText {
                var output = text
                for position in text.elements.indices.reversed() {
                    guard let number = reference(in: text.elements, at: position),
                          let id = identifiers[number], case let .text(run, style) = text.elements[position] else { continue }
                    linked[number, default: 0] += 1
                    let digits = run.trimmingCharacters(in: .whitespaces)
                    var replacement: [InlineText.Element] = [.link(.note(id), InlineText(digits, style: style))]
                    if run.count > digits.count { replacement.append(.text(String(run.dropFirst(digits.count)), style)) }
                    output.elements.replaceSubrange(position...position, with: replacement)
                }
                return output
            }
            switch result[index].content {
            case let .paragraph(text): result[index].content = .paragraph(link(text))
            case let .quotation(text): result[index].content = .quotation(link(text))
            case let .aside(text): result[index].content = .aside(link(text))
            case let .preformatted(text): result[index].content = .preformatted(link(text))
            case .heading, .listItem, .table, .image, .sourcePage: break
            }
        }
        guard plan.notes.allSatisfy({ linked[$0.number] == 1 }) else {
            return blocks.map { block in
                var block = block
                if block.note?.kind == .footnote { block.note = nil }
                return block
            }
        }
        return result
    }
}
