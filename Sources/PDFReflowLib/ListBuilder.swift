import Foundation

/// Turns verified list-shaped blocks into real list items (#292), as the document streams past.
///
/// Reconstruction reads a line that opens with a list marker as a preformatted block and records
/// on it that it did (`ReflowBlock.listEvidence`); every join then grows the block in that
/// representation. This pass decides which of those blocks are items of a real list, under the
/// rules the owner ruled on for #194 and #195:
///
/// - **Bulleted items** (`•`, `-`, `+`, `*`): a run of at least two with one glyph, each reading
///   as words past its marker. `−` is not a bullet: Wallace's derivation rows open with it and
///   some read as words (`− 7+6x Our Solution`), so a run of them would list a worked example.
///   An elision (`* * *`) is not a bullet either.
/// - **Numbered items** (`1.`, `2)`): a run of at least two whose printed numbers ascend by
///   exactly one. A `1` always opens a new run. A run with a gap or a step back stays
///   preformatted, because an `<ol>` would print numbers the source does not have; a run whose
///   first printed number is not 1 keeps that number as the list's `start`.
/// - **A transcription of a scan** (recognized, or an inherited invisible text layer) offers
///   numbered items only, held to the same rules wherever they occur: the Blue Book's
///   questionnaire and the Warren report's conclusions list where their numbers run on by one.
///   Its bullets are recognition of table rules and headers (`- Per Cent`) and stay as they are.
/// - **No one-item lists.** A marked line with nothing list-shaped on its page or the pages beside
///   it becomes a paragraph that keeps its printed marker, and so does an accepted item that other
///   blocks set apart from the rest of its run. Everything else keeps its preformatted form and
///   printed marker: lettered items, contents entries, reference lists, exercise sets, answer keys,
///   numbered section titles, a note's asterisk and recognition debris.
///
/// A `+` bullet is read from the block's text rather than from reconstruction's marker reading,
/// because reconstruction reads `+` as the operator it is in every other book: a paragraph that
/// opens with `+`, a space and a word, and reads as words, is a candidate of the `+` family (the
/// dietary guidelines set their top-level items so, and reconstruction joins each one whole).
///
/// Items are flat (#219 item 3). A candidate of another family between two items of a run — the
/// 9/11 brief's bullets under its numbered paragraphs, the guidelines' `-` items under a `+` —
/// leaves the run intact but ends its list element, and the pieces on either side are judged as
/// any piece is; nesting is not in the model.
///
/// The pass streams (decision 0008). A block is held only while its verdict can still change. A
/// run chains a candidate to the latest candidate of its family on the same page or the page
/// before, so a run whose last member stands two pages back cannot grow, and by then every
/// list-shaped neighbour within a page of a marked line has arrived; a run is decided one page
/// later still, so that a marked line's numbered sibling two pages on is seen. What a decision
/// reads from further back — the numbered entries an answer key sets around a run, the nearest
/// numbered line before a marked one — travels as a count or a marker, never as blocks.
struct ListBuilder {
    struct Marker: Equatable {
        /// A bullet glyph, or a number's punctuation.
        enum Family: Hashable { case bullet(Character), number(Character) }
        var family: Family
        /// The printed marker without its trailing space (`•`, `12.`).
        var printed: String
        /// The printed number of a numbered marker.
        var value: Int?
        /// Characters the marker and the space after it occupy at the start of the text.
        var length: Int
    }

    static let bullets: Set<Character> = ["•", "-", "+", "*"]

    /// The marker opening `text`, when it is one this pass can make a list of.
    static func marker(_ text: String) -> Marker? {
        if let first = text.first, bullets.contains(first) {
            let rest = text.dropFirst()
            guard let space = rest.first, space.isWhitespace else { return nil }
            let body = rest.drop(while: \.isWhitespace)
            if first == "*", body.first == "*" { return nil }
            if first == "+", !opensWithPlusBullet(text) { return nil }
            return Marker(family: .bullet(first), printed: String(first), value: nil, length: text.count - body.count)
        }
        // A number of one to three digits (a year is no item number) with its punctuation and a
        // space.
        guard let range = text.range(of: "^[0-9]{1,3}[.)]\\s+", options: .regularExpression) else { return nil }
        let token = text[range].trimmingCharacters(in: .whitespaces)
        guard let punctuation = token.last, let value = Int(token.dropLast()) else { return nil }
        return Marker(family: .number(punctuation), printed: token, value: value,
                      length: text.distance(from: text.startIndex, to: range.upperBound))
    }

    /// Whether a text opens with the `+` bullet: a plus, a space, then a word of two letters or a
    /// percentage (`+ 100% fruit or vegetable juice`), and the rest reading as words. A row of a
    /// derivation that opens with a plus (`+ 21 + 21 Add 21 to both sides`, Wallace page 40) does
    /// not, and neither does recognition debris (`+ c ~ 50 50 ~`).
    static func opensWithPlusBullet(_ text: String) -> Bool {
        text.range(of: "^\\+\\s+(?:\\p{L}{2}|[0-9]+%)", options: .regularExpression) != nil
            && readsAsItem(String(text.dropFirst(2)))
    }

    /// Whether an item's text, past its marker, reads as words rather than a term, a value or
    /// recognition debris: letters in words of three or more make up at least 35% of it.
    static func readsAsItem(_ body: String) -> Bool {
        let characters = body.filter { !$0.isWhitespace }.count
        guard characters > 0 else { return false }
        var letters = 0, word = 0
        for character in body + " " {
            if character.isLetter { word += 1; continue }
            if word >= 3 { letters += word }
            word = 0
        }
        return letters > 0 && Double(letters) >= Double(body.count) * 0.35
    }

    /// `text` without its first `count` characters (the printed marker and its space). Page
    /// boundaries before them stay in place, and so does a link the marker opens inside.
    static func dropping(_ count: Int, from text: InlineText) -> InlineText {
        var remaining = count
        var elements: [InlineText.Element] = []
        for element in text.elements {
            guard remaining > 0 else { elements.append(element); continue }
            switch element {
            case .sourcePage:
                elements.append(element)
            case let .text(value, style):
                if value.count <= remaining { remaining -= value.count; continue }
                elements.append(.text(String(value.dropFirst(remaining)), style))
                remaining = 0
            case let .link(target, inner):
                let length = inner.text.count
                if length <= remaining { remaining -= length; continue }
                elements.append(.link(target, dropping(remaining, from: inner)))
                remaining = 0
            }
        }
        return InlineText(elements: elements)
    }

    // MARK: - Streaming

    /// A block the pass holds, with what it read of it on arrival.
    private struct Entry {
        var id: Int
        var block: ReflowBlock
        var candidate: Candidate?
        /// A list-shaped block: a marker-opened preformatted block, or a `+` paragraph.
        var shaped: Bool
        /// The page of the list-shaped block before this one, for a marked line's neighbours.
        var previousShapedPage: Int?
        /// The numbered marker of the nearest list-shaped block of the same family before this
        /// one, however far back, for the section-title exception.
        var previousSibling: Marker?
        /// The numbered entry the list-shaped block before this one reads as when it is no item,
        /// for a run that continues an apparatus.
        var previousEntry: Marker?
        /// The heading in force where this block arrived: the last heading block before it.
        var heading: String?
        var decided = false
    }

    private struct Candidate {
        var marker: Marker
        var recognized: Bool
        var run: Int
    }

    private struct Run {
        var family: Marker.Family
        var members: [Int]
        var lastPage: Int
        var lastValue: Int?
    }

    private var held: [Entry] = []
    private var nextID = 0
    private var runs: [Int: Run] = [:]
    private var runCount = 0
    /// The open run of each family, which the next candidate of that family may chain to.
    private var latest: [Marker.Family: Int] = [:]
    /// Numbered list-shaped blocks that read as no item, by page and punctuation: an answer key's
    /// or an exercise grid's entries. Counts, kept for every page.
    private var apparatus: [Int: [Character: Int]] = [:]
    private var lastShapedPage: Int?
    private var lastMarker: [Marker.Family: Marker] = [:]
    private var lastEntry: Marker?
    private var lastHeading: String?

    init() {}

    /// Whether a heading names a set of exercises: one of its words is *practice* or
    /// *exercise(s)*. The numbered problems under such a heading key the book's answers to
    /// them, and whether they are to be lists is decided after their reading order is (#219
    /// item 4); until then they keep their printed numbers as they are. The book's own heading
    /// is the evidence, as `NOTES TO CHAPTER` is for a notes apparatus: Wallace heads every
    /// exercise set `1.7 Practice - Variation`, and heads its worked procedures otherwise.
    static func namesExercises(_ heading: String) -> Bool {
        heading.split(whereSeparator: { !$0.isLetter }).contains { word in
            let lowered = word.lowercased()
            return lowered == "practice" || lowered == "exercise" || lowered == "exercises"
        }
    }

    /// The whole document at once, for a caller that holds it.
    static func build(_ blocks: [ReflowBlock]) -> [ReflowBlock] {
        var builder = ListBuilder()
        var result: [ReflowBlock] = []
        for block in blocks { result += builder.accept(block) }
        return result + builder.finish()
    }

    /// Accepts the next block and returns the blocks whose verdict is final, in order.
    mutating func accept(_ block: ReflowBlock) -> [ReflowBlock] {
        var entry = Entry(id: nextID, block: block, shaped: false, heading: lastHeading)
        nextID += 1
        let plain = block.text
        var marker: Marker?
        var recognized = false
        switch block.content {
        case let .preformatted(text) where block.listEvidence != nil:
            entry.shaped = true
            recognized = block.listEvidence?.recognized ?? false
            if !text.text.contains("\n") { marker = Self.marker(plain) }
        case .paragraph where plain.hasPrefix("+") && Self.opensWithPlusBullet(plain):
            entry.shaped = true
            marker = Self.marker(plain)
        case .heading:
            lastHeading = plain
        default:
            break
        }
        if entry.shaped {
            entry.previousShapedPage = lastShapedPage
            entry.previousEntry = lastEntry
            if let marker { entry.previousSibling = lastMarker[marker.family] }
            lastShapedPage = block.page
            lastEntry = nil
            if let marker { lastMarker[marker.family] = marker }
            // A transcription of a scan offers numbered items only; a bullet in one is recognition
            // of a table rule or a header, which ends every run as any other list-shaped block
            // that is no item does.
            if let marker, !(recognized && marker.value == nil),
               Self.readsAsItem(String(plain.dropFirst(marker.length))) {
                entry.candidate = chain(marker, recognized: recognized, page: block.page, id: entry.id)
            } else {
                latest = [:]
                if let range = plain.range(of: "^[0-9]{1,3}[.)]", options: .regularExpression),
                   let punctuation = plain[range].last {
                    apparatus[block.page, default: [:]][punctuation, default: 0] += 1
                    if let value = Int(plain[range].dropLast()) {
                        lastEntry = Marker(family: .number(punctuation), printed: String(plain[range]),
                                           value: value, length: plain[range].count)
                    }
                }
            }
        }
        entry.decided = entry.candidate == nil
        held.append(entry)
        // Every block of the page before this one has arrived, so a run whose last member stands
        // two pages back can neither grow nor be read differently; a run is held one page more,
        // so that a marked line's numbered sibling on the second page after it is seen.
        settle(before: block.page - 3)
        return release()
    }

    /// Decides everything still held and returns it.
    mutating func finish() -> [ReflowBlock] {
        settle(before: Int.max)
        return release()
    }

    /// The run a candidate joins: the open run of its family whose last member is on this page
    /// or the one before, and, for a number, whose last printed number is one or two below or
    /// above this one. A `1` opens a new run; a gap of more than two is another list.
    private mutating func chain(_ marker: Marker, recognized: Bool, page: Int, id: Int) -> Candidate {
        if let open = latest[marker.family], var run = runs[open], page - run.lastPage <= 1 {
            let chains: Bool
            switch marker.family {
            case .bullet: chains = true
            case .number:
                if let value = marker.value, let before = run.lastValue, value != 1 {
                    chains = (1...2).contains(abs(value - before))
                } else { chains = false }
            }
            if chains {
                run.members.append(id)
                run.lastPage = page
                run.lastValue = marker.value
                runs[open] = run
                return Candidate(marker: marker, recognized: recognized, run: open)
            }
        }
        runCount += 1
        runs[runCount] = Run(family: marker.family, members: [id], lastPage: page, lastValue: marker.value)
        latest[marker.family] = runCount
        return Candidate(marker: marker, recognized: recognized, run: runCount)
    }

    private func position(_ id: Int) -> Int { id - (held.first?.id ?? 0) }

    /// Decides every run whose last member stands on a page at or before `page`: no candidate that
    /// could still join it can arrive, and every block of the page after it has.
    private mutating func settle(before page: Int) {
        for (id, run) in runs.sorted(by: { $0.key < $1.key }) where run.lastPage <= page {
            decide(run)
            runs[id] = nil
            if latest[run.family] == id { latest[run.family] = nil }
        }
    }

    private mutating func release() -> [ReflowBlock] {
        var released: [ReflowBlock] = []
        while let first = held.first, first.decided {
            released.append(first.block)
            held.removeFirst()
        }
        return released
    }

    /// Whether only page boundaries stand between two held blocks — and, where `amongCandidates`,
    /// candidates of other families, which are the items of a list the page set inside this
    /// one's: those end a list element, but they do not set a run's items apart as prose does.
    private func contiguous(_ first: Int, _ second: Int, amongCandidates: Bool = false) -> Bool {
        ((position(first) + 1)..<position(second)).allSatisfy { index in
            if case .sourcePage = held[index].block.content { return true }
            return amongCandidates && held[index].candidate != nil
        }
    }

    private mutating func decide(_ run: Run) {
        let members = run.members.sorted()
        defer { for id in members { held[position(id)].decided = true } }
        guard members.count >= 2 else {
            paragraphIfLone(members[0])
            return
        }
        let candidates = members.map { held[position($0)].candidate! }
        if case let .number(punctuation) = run.family {
            let values = candidates.compactMap(\.marker.value)
            guard zip(values, values.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return }
            // Numbered items each standing alone between other blocks are numbered titles or
            // paragraphs, not a list's items. Items of another family between two of them are
            // the list the page set inside this one (the 9/11 brief's bullets under its numbered
            // paragraphs), which is no such evidence.
            guard zip(members, members.dropFirst()).contains(where: { contiguous($0, $1, amongCandidates: true) }) else { return }
            let texts = members.map { held[position($0)].block.text }
            let bodies = zip(texts, candidates).map { String($0.dropFirst($1.marker.length)) }
            // A contents list numbers its chapters too, but its entries end on their folios or
            // carry their sections' numbers (`5. AL QAEDA AIMS AT THE AMERICAN HOMELAND 145 5.1
            // Terrorist Entrepreneurs 145`, the 9/11 report's contents).
            let entries = texts.count {
                $0.range(of: "\\s[0-9]{1,4}(?:\\.[0-9]{1,2})?\\s*$|\\s[0-9]{1,2}\\.[0-9]{1,2}\\s+\\p{Lu}",
                         options: .regularExpression) != nil
            }
            guard entries * 2 < members.count else { return }
            // Numbered problems give quantities and ask for one: an exercise set, whose numbers tie
            // each problem to its answer rather than make a list (Wallace page 69's `1. When five is
            // added to three more than a certain number, the result is 19. What is the number?`).
            let problems = bodies.count { body in
                body.contains(where: \.isNumber) && (body.contains("?")
                    || body.range(of: "\\b(?:[Ff]ind|[Hh]ow (?:much|many|long|far|wide|old))\\b",
                                  options: .regularExpression) != nil)
            }
            guard problems * 2 <= members.count else { return }
            // A numbered reference list opens its entries on an author (`Mann, M.E.,`) and cites
            // the authors' year and a colon (`IPCC, 2021:`), a DOI or an address in them (the
            // climate assessment's chapter references): its numbers are citation targets, and its
            // wrapped entries are not yet whole (#219). Half such entries are enough, because an
            // entry wrapped before its year still opens on its first author. A dated item (`1.
            // January 2000: the CIA does not…`, 9/11 page 373) names no author.
            let references = zip(texts, bodies).count { text, body in
                text.range(of: ",\\s(?:1[89]|20)[0-9]{2}[a-z]?:\\s|https?://|doi\\.org/|\\bdoi:",
                           options: .regularExpression) != nil
                    || body.range(of: "^(?:\\p{Ll}+\\s)?\\p{Lu}[\\p{L}'’-]+(?:\\s\\p{Lu}[\\p{L}'’-]+)?,\\s+(?:\\p{Lu}\\.){1,3}[,\\s]",
                                  options: .regularExpression) != nil
            }
            guard references * 2 < members.count else { return }
            // A run among more numbered entries that read as no item (values, terms, expressions)
            // is part of that apparatus: an answer key's `46) All real numbers` beside `47)− 2`.
            let pages = Set(members.map { held[position($0)].block.page })
            let others = pages.reduce(0) { $0 + (apparatus[$1]?[punctuation] ?? 0) }
            guard others <= members.count else { return }
            // A run whose numbering the list-shaped block beside it continues is part of an
            // apparatus whose other entries read as no item, and stays as printed with them. In
            // a transcription, recognition garbles some entries of a notes apparatus into no item
            // while their numbers survive, so the readable entries between them form short runs
            // (the Warren report's page 897: `1. Martin Isaacs DE 1` to `3.`, then `4. Isaacs DE 1
            // : CE 1159.`); an exercise set opens on three conversions of figures and goes on in
            // words (Wallace page 285's `4. 1.35 km to centimeters` after `3.`). A list's run is
            // set off by other blocks or options (the Blue Book questionnaire's lettered answers).
            let first = held[position(members[0])]
            let after = held[(position(members[members.count - 1]) + 1)...].first(where: \.shaped)
                .flatMap { $0.candidate == nil ? Self.entryMarker($0.block.text) : nil }
            let continued = [(first.previousEntry, values[0] - 1), (after, values[values.count - 1] + 1)].contains { entry, expected in
                guard let entry, entry.family == run.family else { return false }
                return entry.value == expected
            }
            guard !continued else { return }
            // The numbered problems of an exercise set key the book's answers to them, and the
            // book's own heading says which numbered runs those are (#219 item 4).
            if let heading = first.heading, Self.namesExercises(heading) { return }
        }
        // A piece of a verified run that other blocks set apart on both sides is one item, not a
        // list: it is a paragraph keeping its printed marker, as a lone marked line is (#195): the
        // Blue Book questionnaire's `28.`, set apart from `22.`–`27.` by the lines left to write on.
        var piece: [Int] = []
        func closePiece() {
            defer { piece = [] }
            guard piece.count >= 2 else {
                if let only = piece.first { paragraph(only) }
                return
            }
            for (offset, id) in piece.enumerated() {
                let entry = held[position(id)]
                guard let candidate = entry.candidate else { continue }
                let text: InlineText
                switch entry.block.content {
                case let .preformatted(value), let .paragraph(value): text = value
                default: continue
                }
                held[position(id)].block.content = .listItem(.init(
                    text: Self.dropping(candidate.marker.length, from: text), marker: candidate.marker.printed,
                    ordinal: candidate.marker.value, kind: candidate.marker.value == nil ? .unordered : .ordered,
                    opensList: offset == 0))
                held[position(id)].block.listEvidence = nil
            }
        }
        for id in members {
            if let last = piece.last, !contiguous(last, id) { closePiece() }
            piece.append(id)
        }
        closePiece()
    }

    /// The numbered entry a list-shaped block that is no item reads as, for the notes rule.
    private static func entryMarker(_ text: String) -> Marker? {
        guard let range = text.range(of: "^[0-9]{1,3}[.)]", options: .regularExpression),
              let punctuation = text[range].last, let value = Int(text[range].dropLast()) else { return nil }
        return Marker(family: .number(punctuation), printed: String(text[range]), value: value, length: text[range].count)
    }

    /// A marked line with no other list-shaped block on its page or the pages beside it has
    /// nothing to form a list with (#195): it becomes a paragraph that keeps its printed marker,
    /// rather than preformatted text or a one-item list (the CDC comic's `1) Get a Kit`). A number
    /// whose nearest numbered line of its family either way, however far back and as far ahead as
    /// the pass holds, is its sibling belongs to a sequence spread over the document, such as
    /// section titles (the Geltman paper's `3. Quantum Description` between `2.` on page 1 and
    /// `4.` on page 6), and stays as printed. So does a note's asterisk (`* Estimated`), which is
    /// not a bullet.
    private mutating func paragraphIfLone(_ id: Int) {
        let entry = held[position(id)]
        guard let candidate = entry.candidate, candidate.marker.family != .bullet("*") else { return }
        let page = entry.block.page
        if let previous = entry.previousShapedPage, page - previous <= 1 { return }
        if let next = held[(position(id) + 1)...].first(where: \.shaped), next.block.page - page <= 1 { return }
        if let value = candidate.marker.value {
            let after = held[(position(id) + 1)...].lazy.compactMap { other -> Marker? in
                guard other.shaped, let marker = Self.marker(other.block.text) ?? Self.entryMarker(other.block.text),
                      marker.family == candidate.marker.family else { return nil }
                return marker
            }.first
            let siblings = [entry.previousSibling, after].contains { other in
                other?.value.map { (1...2).contains(abs($0 - value)) } ?? false
            }
            if siblings { return }
        }
        paragraph(id)
    }

    /// The block as a paragraph that keeps its printed marker; a `+` paragraph is already one.
    private mutating func paragraph(_ id: Int) {
        guard case let .preformatted(text) = held[position(id)].block.content else { return }
        held[position(id)].block.content = .paragraph(text)
        held[position(id)].block.listEvidence = nil
    }
}
