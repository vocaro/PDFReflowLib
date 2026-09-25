import Foundation

/// Only a repeated numeric note sequence and explicit printed-page labels establish a
/// reference target. OCR letters are never turned into digits, and overlapping scopes or
/// duplicate numbers refuse a link. Reconstruction and the writer can still reject a target.
struct NoteLinker {
    struct Entry {
        var id: String
        var number: Int
        var pages: ClosedRange<Int>
    }
    private var entries: [Int: [Entry]] = [:]
    private var entryCount = 0

    mutating func collect(_ page: PageContent) {
        guard entryCount < 100_000,
              let heading = page.lines.first(where: { $0.text.contains("NOTES TO PAGES") }),
              let range = heading.text.range(of: #"[0-9]+\s*[-–]\s*[0-9]+"#, options: .regularExpression),
              let first = Int(heading.text[range].split(whereSeparator: { $0 == "-" || $0 == "–" })[0].trimmingCharacters(in: .whitespaces)),
              let last = Int(heading.text[range].split(whereSeparator: { $0 == "-" || $0 == "–" })[1].trimmingCharacters(in: .whitespaces)),
              first > 0, last >= first,
              let plan = ScannedEndnotes.plan(page.lines.map { .init(rect: $0.rect, line: $0) },
                                              page: page, headingEvidence: false) else { return }
        let starts = plan.groups.keys.filter { plan.groups[$0] == $0 }.sorted()
        let lines = starts.map { plan.elements[$0].line! }
        let numbers = lines.map { ScannedEndnotes.marker($0.text).flatMap { Int($0.dropLast()) } }
        guard lines.count >= 3 else { return }
        for index in 1..<(lines.count - 1) {
            guard let number = numbers[index], number > 0,
                  numbers[index - 1] == number - 1, numbers[index + 1] == number + 1 else { continue }
            entries[number, default: []].append(.init(id: ScannedEndnotes.identifier(page: page.number, line: lines[index]),
                                 number: number, pages: first...last))
            entryCount += 1
        }
    }

    func target(number: Int, printedPage: Int) -> String? {
        let matches = entries[number, default: []].filter { $0.pages.contains(printedPage) }
        return matches.count == 1 ? matches[0].id : nil
    }

    func applying(to block: ReflowBlock, pageLabels: [Int: String]) -> ReflowBlock {
        // Physical page offsets are not proof of the page numbers an endnote head names.
        guard block.note == nil, let label = pageLabels[block.page],
              let printedPage = Int(label), case let .paragraph(text) = block.content else { return block }
        var output = block
        var changed = text
        for index in text.elements.indices {
            guard index > 0, case let .text(value, style) = text.elements[index],
                  style.contains(.superscript), !style.contains(.subscript),
                  !value.isEmpty, value.count <= 4, value.allSatisfy(\.isNumber),
                  let number = Int(value), let id = target(number: number, printedPage: printedPage),
                  case let .text(before, _) = text.elements[index - 1],
                  before.range(of: #"\p{L}{3,}[.,;:!?)]?$"#, options: .regularExpression) != nil,
                  before.suffix(30).range(of: #"[=+×÷]"#, options: .regularExpression) == nil else { continue }
            if index + 1 < text.elements.count, case let .text(after, _) = text.elements[index + 1],
               let next = after.first, next.isLetter || next.isNumber { continue }
            changed.elements[index] = .link(.note(id), InlineText(value, style: style))
        }
        output.content = .paragraph(changed)
        return output
    }
}
