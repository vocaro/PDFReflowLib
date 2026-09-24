import Foundation
import CoreGraphics

/// Reads the two-column note apparatus identified by its own NOTES TO PAGES running head.
/// The scan's spelling is retained, including damaged markers; geometry can establish an
/// entry boundary without establishing the number to which a reference should link.
enum ScannedEndnotes {
    struct Plan {
        var elements: [LayoutReconstructor.Element]
        var groups: [Int: Int]
    }

    static func identifier(page: Int, line: TextLine) -> String {
        "note-\(page)-\(Int((line.rect.minX * 10).rounded()))-\(Int((line.rect.minY * 10).rounded()))"
    }

    static func hasHeading(_ page: PageContent) -> Bool {
        page.lines.contains {
            $0.rect.midY > page.bounds.minY + page.bounds.height * 0.9
                && $0.text.range(of: #"\bNOTES\s+TO\s+PAGES\s+\S+"#,
                                  options: .regularExpression) != nil
        }
    }

    static func marker(_ text: String) -> String? {
        guard let range = text.range(of: #"^[A-Za-z0-9]{1,4}\.\s+"#,
                                     options: .regularExpression) else { return nil }
        return text[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plan(_ elements: [LayoutReconstructor.Element], page: PageContent,
                     headingEvidence: Bool) -> Plan? {
        guard headingEvidence || hasHeading(page), !page.requiresPageImage,
              elements.allSatisfy({ $0.line != nil }), elements.count >= 25 else { return nil }
        let numbered = elements.compactMap { element -> TextLine? in
            guard let line = element.line, let token = marker(line.text),
                  Int(token.dropLast()) != nil else { return nil }
            return line
        }.sorted { $0.rect.minX < $1.rect.minX }
        guard numbered.count >= 20 else { return nil }
        let gaps = zip(numbered.indices, numbered.dropFirst()).map { index, next in
            (index, next.rect.minX - numbered[index].rect.minX)
        }
        guard let gap = gaps.max(by: { $0.1 < $1.1 }), gap.1 > page.bounds.width * 0.2 else { return nil }
        let samples = [Array(numbered[...gap.0]), Array(numbered[(gap.0 + 1)...])]
        guard samples.allSatisfy({ $0.count >= 8 }) else { return nil }
        let size = max(4, LayoutReconstructor.bodySize(numbered))
        let edges = samples.map { lines in lines.map(\.rect.minX).sorted()[lines.count / 2] }
        // A continuation can itself start with a citation such as `2039. 2042.`. It
        // stands on the dedented text edge, so it must not veto the repeated marker edge.
        guard samples.enumerated().allSatisfy({ column, lines in
            lines.count { abs($0.rect.minX - edges[column]) <= size * 0.7 } * 4 >= lines.count * 3
        }) else { return nil }
        let cut = (samples[0].map(\.rect.maxX).max()! + samples[1].map(\.rect.minX).min()!) / 2
        guard samples[0].allSatisfy({ $0.rect.maxX < cut }),
              samples[1].allSatisfy({ $0.rect.minX > cut }) else { return nil }
        let top = elements.compactMap(\.line).filter { line in marker(line.text) != nil
            && edges.contains(where: { edge in abs(line.rect.minX - edge) <= size * 0.7 })
        }.map(\.rect.maxY).max()!
        let bottom = numbered.map(\.rect.minY).min()!
        var above: [LayoutReconstructor.Element] = [], below: [LayoutReconstructor.Element] = []
        var columns: [[LayoutReconstructor.Element]] = [[], []]
        var dividers: [LayoutReconstructor.Element] = []
        for element in elements {
            let line = element.line!
            // Heading bands precede both columns; a bare folio follows both.
            if line.rect.minY > top + size * 0.3 { above.append(element); continue }
            if line.rect.maxY < bottom - size && line.text.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
                below.append(element); continue
            }
            if line.text.range(of: #"^(?:CHAPTER|APPENDIX)\s+[IVXLC0-9]+$"#, options: .regularExpression) != nil {
                dividers.append(element); continue
            }
            guard line.turn == .upright else { return nil }
            if line.rect.minX < cut && line.rect.maxX > cut {
                // Some inherited OCR rows merge text from both columns and report corrupted
                // character positions. Keep that row unlinked as its own boundary; it cannot
                // establish ownership in either note column. The source image remains available.
                dividers.append(element); continue
            }
            let column = line.rect.midX < cut ? 0 : 1
            columns[column].append(element)
        }
        func down(_ a: LayoutReconstructor.Element, _ b: LayoutReconstructor.Element) -> Bool {
            a.rect.midY == b.rect.midY ? a.rect.minX < b.rect.minX : a.rect.midY > b.rect.midY
        }
        var ordered = above.sorted(by: down)
        var ceiling = CGFloat.infinity
        for divider in dividers.sorted(by: down) {
            for column in columns {
                ordered += column.filter { $0.rect.midY < ceiling && $0.rect.midY > divider.rect.midY }.sorted(by: down)
            }
            ordered.append(divider)
            ceiling = divider.rect.midY
        }
        for column in columns { ordered += column.filter { $0.rect.midY < ceiling }.sorted(by: down) }
        ordered += below.sorted(by: down)
        var groups: [Int: Int] = [:]
        var opening: Int?
        let lower = above.count, upper = ordered.count - below.count
        for index in lower..<upper {
            let line = ordered[index].line!
            if dividers.contains(where: { $0.rect == line.rect }) { opening = nil; continue }
            let column = line.rect.midX < cut ? 0 : 1
            if marker(line.text) != nil && abs(line.rect.minX - edges[column]) <= size * 0.7 {
                opening = index
            } else if line.rect.minX < edges[column] - size * 2.5 {
                // Marginal scan debris is retained as separate text, never attached to a note.
                opening = nil
            } else if line.rect.minX > edges[column] - size * 0.3 {
                // A split punctuation/text piece on the preceding row belongs to that row.
                // A new line on the marker edge without a marker is not a proved wrap.
                let previous = index > lower ? ordered[index - 1].line : nil
                if previous.map({ line.sharesRow(with: $0)
                    && line.rect.minX >= $0.rect.maxX - size * 0.25
                    && line.rect.minX - $0.rect.maxX <= size }) != true {
                    opening = nil
                }
            }
            if let opening { groups[index] = opening }
        }
        guard Set(groups.values).count >= 20 else { return nil }
        return Plan(elements: ordered, groups: groups)
    }
}
