import Foundation

/// Bounded native endnote layout, not a reference-to-note ownership detector.
enum NumberedNoteDetector {
    static func hasHeading(on page: PageContent) -> Bool {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return false }
        return page.lines.contains { line in
            guard line.rect.midY >= page.bounds.minY + page.bounds.height * 0.9 else { return false }
            var words = line.text.split(whereSeparator: \.isWhitespace)
            func number(_ text: Substring) -> Bool {
                !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
            }
            if words.first.map(number) == true { words.removeFirst() }
            guard (4...5).contains(words.count), words[0] == "NOTES", words[1] == "TO",
                  words[2] == "CHAPTER", number(words[3]), Int(words[3]).map({ $0 > 0 }) == true else { return false }
            return words.count == 4 || number(words[4])
        }
    }

    /// Element indices map to a note's first element. Refuse the page if any later content
    /// breaks the sequence, typography, close line spacing or first-line indentation pattern.
    /// Preceding content may be a previous page's continuation and remains spatial prose.
    static func groups(in elements: [LayoutReconstructor.Element], page: PageContent,
                       headingEvidence: Bool = false) -> [Int: Int] {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage,
              headingEvidence || hasHeading(on: page),
              elements.allSatisfy({ $0.image == nil }) else { return [:] }
        func number(_ line: TextLine) -> Int? {
            guard line.text.range(of: "^[1-9][0-9]{0,3}\\.\\s*\\p{L}", options: .regularExpression) != nil,
                  let end = line.text.firstIndex(of: ".") else { return nil }
            return Int(line.text[..<end])
        }
        guard let first = elements.firstIndex(where: { $0.line.flatMap(number) != nil }),
              let initial = elements[first].line else { return [:] }
        let size = initial.fontSize
        guard size.isFinite, size >= 4 else { return [:] }
        var result: [Int: Int] = [:]
        var start = first, expected = number(initial)!, count = 0
        var continuationX: CGFloat?
        var previous: TextLine?
        for index in first..<elements.count {
            guard let line = elements[index].line, !line.monospaced, line.structure == nil,
                  line.hasSize(size) else { return [:] }
            if let previous {
                let gap = previous.rect.minY - line.rect.maxY
                guard gap >= -size * 0.2, gap <= size * 0.8 else { return [:] }
            }
            if abs(line.rect.minX - initial.rect.minX) <= size * 0.25, let value = number(line) {
                guard value == expected,
                      line.text.filter(\.isLetter).count >= 10 else { return [:] }
                expected += 1
                count += 1
                start = index
            } else {
                let indent = initial.rect.minX - line.rect.minX
                guard let previous, previous.wraps != false,
                      indent >= size * 0.8, indent <= size * 3,
                      previous.rect.width >= size * 12,
                      line.text.range(of: "^(?:[•*−-]|[A-Za-z][.)])\\s", options: .regularExpression) == nil,
                      continuationX.map({ abs($0 - line.rect.minX) <= size * 0.25 }) ?? true else { return [:] }
                continuationX = line.rect.minX
            }
            result[index] = start
            previous = line
        }
        return count >= 3 && continuationX != nil ? result : [:]
    }
}
