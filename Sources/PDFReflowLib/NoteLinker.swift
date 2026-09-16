import Foundation

/// Links raised reference markers to the notes they cite, after every join and without
/// changing any text. A marker is a superscript run of one to three digits in a body
/// paragraph. Its page (the block's page, advanced by inline boundaries before it) selects
/// the scope: a page-bottom footnote with that number on the same page first, otherwise the
/// chapter endnote with that number in the page's chapter. A marker whose chapter is unknown,
/// a number with no note in scope, and a number that two notes claim in one scope stay plain
/// superscripts. Equal numbers are never joined across chapters.
enum NoteLinker {
    struct Summary: Equatable {
        var markers = 0
        var linked = 0
        /// Markers on pages outside any validated chapter, with no page note of that number.
        var unscoped = 0
        /// Markers whose scope holds no note of that number.
        var missing = 0
        /// Markers whose number two notes claim in the same scope.
        var ambiguous = 0
        var ambiguousNotes = 0
    }

    /// `chapter` maps a physical page to its validated chapter number, or nil.
    @discardableResult
    static func link(_ blocks: inout [ReflowBlock], chapter: (Int) -> Int?) -> Summary {
        var notes: Set<NoteKey> = [], ambiguous: Set<NoteKey> = []
        for block in blocks {
            guard let key = block.note else { continue }
            if !notes.insert(key).inserted { ambiguous.insert(key) }
        }
        var summary = Summary(ambiguousNotes: ambiguous.count)
        for index in blocks.indices {
            // Notes cite no notes; only body paragraphs carry references.
            guard blocks[index].note == nil, case let .paragraph(text) = blocks[index].content else { continue }
            var page = blocks[index].page
            var elements: [InlineText.Element] = []
            var changed = false
            for element in text.elements {
                if case let .sourcePage(number) = element { page = number }
                guard case let .text(value, style) = element, style.contains(.superscript),
                      let (leading, digits, trailing) = marker(value), let number = Int(digits) else {
                    elements.append(element)
                    continue
                }
                summary.markers += 1
                let scope = chapter(page)
                let candidates = [NoteKey(number: number, scope: .page(page))]
                    + (scope.map { [NoteKey(number: number, scope: .chapter($0))] } ?? [])
                guard let key = candidates.first(where: notes.contains) else {
                    if scope == nil { summary.unscoped += 1 } else { summary.missing += 1 }
                    elements.append(element)
                    continue
                }
                guard !ambiguous.contains(key) else {
                    summary.ambiguous += 1
                    elements.append(element)
                    continue
                }
                summary.linked += 1
                changed = true
                // Whitespace around the digits is ordinary text, not an empty raised run.
                let plain = style.subtracting([.superscript, .subscript])
                if !leading.isEmpty { elements.append(.text(leading, plain)) }
                elements.append(.noteReference(digits, plain, key))
                if !trailing.isEmpty { elements.append(.text(trailing, plain)) }
            }
            if changed { blocks[index].content = .paragraph(InlineText(elements: elements)) }
        }
        return summary
    }

    /// One to three digits, optionally surrounded by whitespace that stays ordinary text.
    static func marker(_ value: String) -> (leading: String, digits: String, trailing: String)? {
        let leading = String(value.prefix(while: \.isWhitespace))
        let trailing = String(value.reversed().prefix(while: \.isWhitespace).reversed())
        let digits = String(value.dropFirst(leading.count).dropLast(trailing.count))
        guard (1...3).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }),
              digits.first != "0" else { return nil }
        return (leading, digits, trailing)
    }
}
