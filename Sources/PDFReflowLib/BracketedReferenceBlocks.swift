import Foundation

/// A source-labelled reference section with a repeated, ascending `[n]` run. The page's
/// reference heading and numbering establish the entries; line wraps and DOI rows do not
/// become headings or separate paragraphs just because their right edges are ragged (#171).
enum BracketedReferenceBlocks {
    private static func number(_ text: String) -> Int? {
        guard let match = text.range(of: #"^\[([1-9][0-9]{0,3})\]\s+\S"#,
                                     options: .regularExpression),
              let close = text[match].firstIndex(of: "]") else { return nil }
        return Int(text[text.index(after: text.startIndex)..<close])
    }

    private static func inline(_ content: ReflowBlock.Content) -> InlineText? {
        switch content {
        case let .paragraph(text), let .preformatted(text), let .heading(_, text, _): text
        default: nil
        }
    }

    static func joined(_ blocks: [ReflowBlock]) -> [ReflowBlock] {
        guard let heading = blocks.firstIndex(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "REFERENCES"
        }) else { return blocks }
        let after = heading + 1
        guard after < blocks.count else { return blocks }
        let boundary = blocks[after...].firstIndex(where: { block in
            let value = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return number(value) == nil && value.count <= 60 && value.count >= 3
                && value == value.uppercased() && value.rangeOfCharacter(from: .letters) != nil
        }) ?? blocks.count
        guard boundary > after else { return blocks }
        let openings = (after..<boundary).compactMap { index -> (Int, Int)? in
            number(blocks[index].text).map { (index, $0) }
        }
        guard openings.count >= 5, openings.first?.0 == after,
              zip(openings, openings.dropFirst()).allSatisfy({ $0.0.1 + 1 == $0.1.1 }),
              openings.count(where: {
                  blocks[$0.0].text.range(of: #"\b(?:19|20)[0-9]{2}\b"#,
                                                options: .regularExpression) != nil
              }) >= 3,
              blocks[after..<boundary].allSatisfy({ inline($0.content) != nil })
        else { return blocks }

        var result = Array(blocks[..<after])
        if case let .paragraph(label) = result[heading].content {
            result[heading].content = .heading(id: "references-\(result[heading].page)-\(heading)",
                                               text: label, level: 2)
        }
        if let acknowledgements = result[..<heading].lastIndex(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "ACKNOWLEDGEMENTS"
        }), case let .paragraph(label) = result[acknowledgements].content {
            result[acknowledgements].content = .heading(
                id: "acknowledgements-\(result[acknowledgements].page)-\(acknowledgements)",
                text: label, level: 2)
        }
        for (offset, opening) in openings.enumerated() {
            let end = offset + 1 < openings.count ? openings[offset + 1].0 : boundary
            var entry = blocks[opening.0]
            guard var text = inline(entry.content) else { return blocks }
            for index in (opening.0 + 1)..<end {
                guard let continuation = inline(blocks[index].content) else { return blocks }
                text.append(InlineText(" "))
                text.append(continuation)
            }
            entry.content = .paragraph(text)
            entry.listEvidence = nil
            result.append(entry)
        }
        result.append(contentsOf: blocks[boundary...])
        return result
    }
}
