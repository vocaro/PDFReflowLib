import CoreGraphics
import Foundation

/// Turns verified list-shaped blocks into real list items (#194), once the document is complete.
///
/// Reconstruction reads a line that opens with a list marker as a preformatted block and records
/// where its marker line stood (`ReflowBlock.listEvidence`); every join then grows the block in
/// that representation. This pass decides which of those blocks are items of a real list. Two
/// kinds are converted, as the survey in `measurements/semantic-lists/record.md` recommends:
///
/// - **Bulleted items** (`•`, `-`, `+`, `*`): a run of at least two, each reading as item text.
/// - **Numbered items** (`1.`, `2)`): a run of at least two whose printed numbers ascend by one.
///   A `1` always opens a new run. A run with a gap or a step back stays preformatted: an `<ol>`
///   would print numbers the source does not have. So does a run whose every item stands alone
///   between other blocks (numbered section titles, not a list). A transcription of a scan offers
///   numbered items only, under the same rules (#195).
///
/// A marker line with nothing list-shaped on its page or the pages beside it becomes a paragraph
/// that keeps its printed marker (#195). Everything else keeps its preformatted form and printed
/// marker: lettered items, a minus sign (which opens derivation rows), bullets in transcriptions of
/// scans, contents entries, reference lists, exercise sets and answer keys.
///
/// A *run* chains each candidate to the latest candidate of its family (one bullet glyph; numbers
/// with one punctuation, one or two apart as `LayoutReconstructor.ListMarker.isSibling` reads them)
/// on the same page or the previous one, whatever blocks stand between; candidates of another
/// family between them are nested items, and any other list-shaped block ends every run. A *list
/// element* is the stretch of accepted items with nothing but page boundaries and other items
/// between them; within it, a marker set deeper nests, and a change of run or kind at one depth
/// opens a new list. Where the PDF tags its lists (`L`, `LI`, `Lbl`), the tags decide depth and
/// list identity.
enum ListBuilder {
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

    /// The marker opening `text`, when it is one this pass can make a list of. A minus sign
    /// (`−`) is not one: every such line in the corpus is a row of a displayed derivation (#109).
    /// An elision (`* * *`) is not a bullet.
    static func marker(_ text: String) -> Marker? {
        if let first = text.first, bullets.contains(first) {
            let rest = text.dropFirst()
            guard let space = rest.first, space.isWhitespace else { return nil }
            let body = rest.drop(while: \.isWhitespace)
            if first == "*", body.first == "*" { return nil }
            return Marker(family: .bullet(first), printed: String(first), value: nil, length: text.count - body.count)
        }
        // A number of one to three digits (a year is no item number) with its punctuation and a
        // space, or PDFKit's tight `10.August` (see `LayoutReconstructor.isTightMarker`).
        guard let range = text.range(of: "^[0-9]{1,3}[.)](?:\\s+|(?=\\p{Lu}))", options: .regularExpression)
        else { return nil }
        let token = text[range].trimmingCharacters(in: .whitespaces)
        guard let punctuation = token.last, let value = Int(token.dropLast()) else { return nil }
        if punctuation == ")" && text[range].last?.isWhitespace != true { return nil }
        return Marker(family: .number(punctuation), printed: token, value: value,
                      length: text.distance(from: text.startIndex, to: range.upperBound))
    }

    /// Whether an item's text, past its marker, reads as words rather than a term, a value or
    /// recognition debris: letters in words of three or more make up at least a third of it.
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

    /// A candidate: a block whose content and evidence could make it a list item.
    private struct Candidate {
        var index: Int
        var marker: Marker
        var evidence: ReflowBlock.ListEvidence
        var page: Int
        var run = 0
    }

    static func build(_ blocks: inout [ReflowBlock]) {
        paragraphLoneMarkedLines(&blocks)
        // Runs: a candidate continues the run of the latest candidate of its family, whatever other
        // blocks stand between, when that one is on this page or the previous one (and, for numbers,
        // a sibling). Candidates of other families between them are items nested in the run's
        // (the 9/11 report's daily brief sets bullets under its numbered paragraphs, pages 146-147);
        // any other list-shaped block ends every run.
        var candidates: [Candidate] = []
        var latest: [Marker.Family: Candidate] = [:]
        var runCount = 0
        // Numbered list-shaped blocks that are not candidates (a value, a term, an expression),
        // by page and punctuation: an answer key's or an exercise grid's entries.
        var apparatus: [Int: [Character: Int]] = [:]
        // Every list-shaped block, and the printed number of each numbered one that is no candidate.
        var listShaped: [Int] = []
        var numberedEntries: [Int: Marker] = [:]
        for (index, block) in blocks.enumerated() {
            guard case let .preformatted(text) = block.content, let evidence = block.listEvidence else { continue }
            let plain = text.text
            listShaped.append(index)
            // A transcription of a scan offers numbered items only: its "bullets" are recognition
            // of table rules and headers (the CIA report's `- Per Cent`), while its numbered items
            // are held to the same verified numbering as any other (the CIA questionnaire's `22.
            // Your full name:` to `28.`, #195).
            guard !plain.contains("\n"), !LayoutReconstructor.isContentsEntry(plain),
                  let marker = marker(plain), !(evidence.recognized && marker.value == nil),
                  readsAsItem(String(plain.dropFirst(marker.length))) else {
                latest = [:]
                if let range = plain.range(of: "^[0-9]{1,3}[.)]", options: .regularExpression), let punctuation = plain[range].last {
                    apparatus[block.page, default: [:]][punctuation, default: 0] += 1
                    let token = plain[range]
                    if let value = Int(token.dropLast()) {
                        numberedEntries[index] = Marker(family: .number(punctuation), printed: String(token), value: value, length: token.count)
                    }
                }
                continue
            }
            var candidate = Candidate(index: index, marker: marker, evidence: evidence, page: block.page)
            var run: Int?
            if let previous = latest[marker.family], (0...1).contains(block.page - previous.page) {
                switch marker.family {
                case .bullet: run = previous.run
                case .number:
                    if let value = marker.value, let before = previous.marker.value,
                       value != 1, (1...2).contains(abs(value - before)) { run = previous.run }
                }
            }
            if run == nil { runCount += 1 }
            candidate.run = run ?? runCount
            candidates.append(candidate)
            latest[marker.family] = candidate
        }
        guard !candidates.isEmpty else { return }

        // Contiguity: only page boundaries and blocks of `among` stand between two blocks.
        func contiguous(_ first: Int, _ second: Int, among: Set<Int>) -> Bool {
            ((first + 1)..<second).allSatisfy { index in
                if case .sourcePage = blocks[index].content { return true }
                return among.contains(index)
            }
        }
        let candidateIndices = Set(candidates.map(\.index))

        var accepted = Set<Int>()
        for members in Dictionary(grouping: candidates, by: \.run).values {
            let members = members.sorted { $0.index < $1.index }
            guard members.count >= 2 else { continue }
            if case .number = members[0].marker.family {
                let values = members.compactMap(\.marker.value)
                guard zip(values, values.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { continue }
                // Numbered items each standing alone between other blocks are numbered titles or
                // paragraphs, not a list's items.
                guard zip(members, members.dropFirst()).contains(where: { contiguous($0.index, $1.index, among: candidateIndices) }) else { continue }
                // A contents list numbers its chapters too, but its entries end on their folios or
                // carry their sections' numbers (`5. AL QAEDA AIMS AT THE AMERICAN HOMELAND 145 5.1
                // Terrorist Entrepreneurs 145`, the 9/11 report's contents).
                let entries = members.filter { member in
                    guard case let .preformatted(text) = blocks[member.index].content else { return false }
                    return text.text.range(of: "\\s[0-9]{1,4}(?:\\.[0-9]{1,2})?\\s*$|\\s[0-9]{1,2}\\.[0-9]{1,2}\\s+\\p{Lu}",
                                           options: .regularExpression) != nil
                }
                guard entries.count * 2 < members.count else { continue }
                // Numbered problems give quantities and ask for one: an exercise set, whose numbers
                // tie each problem to its answer rather than make a list (Wallace page 69's `1. When
                // five is added to three more than a certain number, the result is 19. What is the
                // number?`).
                let problems = members.filter { member in
                    guard case let .preformatted(text) = blocks[member.index].content else { return false }
                    let body = String(text.text.dropFirst(member.marker.length))
                    return body.contains(where: \.isNumber) && (body.contains("?")
                        || body.range(of: "\\b(?:[Ff]ind|[Hh]ow (?:much|many|long|far|wide|old))\\b", options: .regularExpression) != nil)
                }
                guard problems.count * 2 <= members.count else { continue }
                // A numbered reference list opens its entries on an author (`Mann, M.E.,`) and cites
                // the authors' year and a colon (`IPCC, 2021:`), a DOI or an address in them (the
                // climate assessment's chapter references): its numbers are citation targets, and its
                // wrapped entries are not yet whole (#195). Half such entries are enough: an entry
                // wrapped before its year can open on a two-word surname (NOAA page 1686's `381. Norooz
                // Oliaee, J.,`). A dated item (`1. January 2000: the CIA does not…`, 9/11 page 373)
                // names no author.
                let references = members.filter { member in
                    guard case let .preformatted(text) = blocks[member.index].content else { return false }
                    let body = String(text.text.dropFirst(member.marker.length))
                    return text.text.range(of: ",\\s(?:1[89]|20)[0-9]{2}[a-z]?:\\s|https?://|doi\\.org/|\\bdoi:",
                                           options: .regularExpression) != nil
                        // An entry wrapped before its year still opens on its first author.
                        || body.range(of: "^(?:\\p{Ll}+\\s)?\\p{Lu}[\\p{L}'’-]+(?:\\s\\p{Lu}[\\p{L}'’-]+)?,\\s+(?:\\p{Lu}\\.){1,3}[,\\s]",
                                      options: .regularExpression) != nil
                }
                guard references.count * 2 < members.count else { continue }
                // A run among more numbered entries that read as no item (values, terms, expressions)
                // is part of that apparatus: an answer key's `46) All real numbers` beside `47)− 2`.
                if case let .number(punctuation) = members[0].marker.family {
                    let others = Set(members.map(\.page)).reduce(0) { $0 + (apparatus[$1]?[punctuation] ?? 0) }
                    guard others <= members.count else { continue }
                    // In a transcription, recognition garbles some entries of a notes apparatus into no
                    // item while their numbers survive, so the readable entries between them form short
                    // runs (the Warren report's page 897: `1. Martin Isaacs DE 1` to `3.`, then `4. Isaacs
                    // DE 1 : CE 1159.`). A run whose numbering the list-shaped block beside it continues
                    // is part of that apparatus; a list's run is set off by other blocks or options (the
                    // CIA questionnaire's lettered answers).
                    if members.contains(where: \.evidence.recognized),
                       let first = listShaped.firstIndex(of: members[0].index),
                       let last = listShaped.firstIndex(of: members[members.count - 1].index) {
                        let continues = [(first - 1, -1), (last + 1, 1)].contains { position, step in
                            guard listShaped.indices.contains(position), let entry = numberedEntries[listShaped[position]],
                                  entry.family == members[0].marker.family, let value = entry.value,
                                  let end = (step < 0 ? members[0] : members[members.count - 1]).marker.value else { return false }
                            return value == end + step
                        }
                        guard !continues else { continue }
                    }
                }
            }
            accepted.formUnion(members.map(\.index))
        }
        guard !accepted.isEmpty else { return }
        // A lone item set deeper between two items of a list is that list's nested item: 9/11 page
        // 147 sets one bullet under the brief's second numbered paragraph.
        for (position, candidate) in candidates.enumerated() where !accepted.contains(candidate.index)
            && position > 0 && position + 1 < candidates.count {
            let before = candidates[position - 1], after = candidates[position + 1]
            guard accepted.contains(before.index), accepted.contains(after.index),
                  contiguous(before.index, candidate.index, among: candidateIndices),
                  contiguous(candidate.index, after.index, among: candidateIndices),
                  candidate.page == before.page, candidate.marker.value == nil,
                  setsDeeper(candidate.evidence, than: before.evidence) else { continue }
            accepted.insert(candidate.index)
        }

        // List elements, depth and openings. `stack` holds the list open at each depth.
        struct Level { var evidence: ReflowBlock.ListEvidence; var page: Int; var run: Int; var marker: Marker
            var edge: CGFloat { evidence.edge }
            var tag: ListTag? { evidence.tag }
        }
        var stack: [Level] = []
        var previousAccepted: Int?
        let items = candidates.filter { accepted.contains($0.index) }
        // An item on a page after its parent's marker is deeper when the parent list's next item,
        // on this page, stands left of it: the 9/11 brief's `1.` opens on page 146 and its bullets
        // follow on page 147, above `2.`.
        func nestsBeforeNextSibling(_ position: Int, of parent: Level) -> Bool {
            let item = items[position]
            for next in items[(position + 1)...] {
                guard contiguous(items[position].index, next.index, among: accepted) else { return false }
                guard next.marker.family != parent.marker.family else {
                    return next.page == item.page && setsDeeper(item.evidence, than: next.evidence)
                }
            }
            return false
        }
        for (position, candidate) in items.enumerated() {
            let evidence = candidate.evidence
            let em = max(evidence.fontSize, 1)
            let level = Level(evidence: evidence, page: candidate.page, run: candidate.run, marker: candidate.marker)
            let continues = previousAccepted.map { contiguous($0, candidate.index, among: accepted) } ?? false
            if !continues { stack = [] }
            var opens = true
            if stack.isEmpty {
                stack = [level]
            } else if let tag = evidence.tag, let above = stack[stack.count - 1].tag {
                // The document's own list structure: depth and list identity from the tags. A
                // producer that closes its list element at a page break opens another for the same
                // list on the next page (Loper Bright pages 86-87 tag its five bullets as two `L`s),
                // so across a page boundary the list continues at its depth.
                if tag.depth > above.depth {
                    stack.append(level)
                } else {
                    while stack.count > 1, let open = stack[stack.count - 1].tag, open.depth > tag.depth { stack.removeLast() }
                    opens = stack[stack.count - 1].tag?.list != tag.list && stack[stack.count - 1].page == candidate.page
                    stack[stack.count - 1] = level
                }
            } else {
                let top = stack[stack.count - 1]
                if candidate.page == top.page && setsDeeper(evidence, than: top.evidence)
                    || candidate.page != top.page && candidate.marker.family != top.marker.family
                    && nestsBeforeNextSibling(position, of: top) {
                    // A marker set deeper on the same page opens a list inside the open item.
                    stack.append(level)
                } else {
                    // A marker on an open level's edge returns to that level. Where the edges say
                    // nothing (the next column or page), a marker like an open level's does: the
                    // dietary guidelines' `+` items resume beside their `-` sub-items (#194).
                    let target = stack.lastIndex { open in
                        open.page == candidate.page && abs(open.edge - evidence.edge) <= em * 0.8
                    } ?? stack.lastIndex { $0.marker.family == candidate.marker.family } ?? stack.count - 1
                    stack.removeSubrange((target + 1)...)
                    let current = stack[target]
                    opens = !(current.run == candidate.run && current.marker.family == candidate.marker.family)
                    stack[target] = level
                }
            }
            previousAccepted = candidate.index
            guard case let .preformatted(text) = blocks[candidate.index].content else { continue }
            blocks[candidate.index].content = .listItem(.init(
                text: dropping(candidate.marker.length, from: text), marker: candidate.marker.printed,
                ordinal: candidate.marker.value,
                kind: candidate.marker.value == nil ? .unordered : .ordered,
                level: stack.count - 1, opensList: opens))
        }
    }

    /// A marked line with no other list-shaped block on its page or the pages beside it has nothing
    /// to form a list with (#195): it becomes a paragraph that keeps its printed marker, rather than
    /// preformatted text or a one-item list (the CDC comic's `1) Get a Kit`). A number whose nearest
    /// numbered line either way, however far, is its sibling belongs to a sequence spread over the
    /// document, such as section titles (the Geltman paper's `3. Quantum Description` between `2.`
    /// on page 1 and `4.` on page 6), and stays as printed. So does a note's asterisk (`* Estimated`),
    /// which is not a bullet.
    static func paragraphLoneMarkedLines(_ blocks: inout [ReflowBlock]) {
        let listShaped = blocks.indices.filter { index in
            guard case .preformatted = blocks[index].content else { return false }
            return blocks[index].listEvidence != nil
        }
        let markers = listShaped.map { index in
            blocks[index].text.contains("\n") ? nil : marker(blocks[index].text)
        }
        var lone: [Int] = []
        for (position, index) in listShaped.enumerated() {
            guard case let .preformatted(text) = blocks[index].content, let marker = markers[position] else { continue }
            let plain = text.text
            guard !LayoutReconstructor.isContentsEntry(plain), marker.family != .bullet("*"),
                  readsAsItem(String(plain.dropFirst(marker.length))) else { continue }
            let neighbours = [position - 1, position + 1].filter(listShaped.indices.contains).map { listShaped[$0] }
            guard !neighbours.contains(where: { abs(blocks[$0].page - blocks[index].page) <= 1 }) else { continue }
            if let value = marker.value {
                let before = markers[..<position].last { $0?.family == marker.family } ?? nil
                let after = markers[(position + 1)...].first { $0?.family == marker.family } ?? nil
                guard ![before, after].contains(where: { other in
                    other?.value.map { (1...2).contains(abs($0 - value)) } ?? false
                }) else { continue }
            }
            lone.append(index)
        }
        for index in lone {
            guard case let .preformatted(text) = blocks[index].content else { continue }
            blocks[index].content = .paragraph(text)
            blocks[index].listEvidence = nil
        }
    }

    /// Whether a marker is set deeper than an open item's, so it opens a list inside that item: right
    /// of the item's marker by more than 0.8 and at most five type sizes, or, where the item's
    /// marker was drawn and its text edge is known (#167), at most five type sizes past that edge.
    /// A browser indents a nested HTML list by the list's padding from the item's text, not its
    /// marker: the TechPort print sets its nested bullets 52.5 points (5.8 sizes) right of their
    /// parents' and 41 points right of the parents' text.
    static func setsDeeper(_ item: ReflowBlock.ListEvidence, than open: ReflowBlock.ListEvidence) -> Bool {
        let em = max(item.fontSize, 1)
        guard item.edge > open.edge + em * 0.8 else { return false }
        if item.edge <= open.edge + em * 5 { return true }
        guard let text = open.textEdge else { return false }
        return item.edge <= text + em * 5
    }

    /// `text` without its first `count` characters (the printed marker and its space). Page
    /// boundaries before them stay in place.
    static func dropping(_ count: Int, from text: InlineText) -> InlineText {
        var remaining = count
        var elements: [InlineText.Element] = []
        for element in text.elements {
            guard remaining > 0 else { elements.append(element); continue }
            switch element {
            case .sourcePage: elements.append(element)
            case let .text(value, style):
                if value.count <= remaining { remaining -= value.count; continue }
                elements.append(.text(String(value.dropFirst(remaining)), style))
                remaining = 0
            case let .noteReference(value, _, _):
                remaining = max(0, remaining - value.count)
            }
        }
        return InlineText(elements: elements)
    }
}
