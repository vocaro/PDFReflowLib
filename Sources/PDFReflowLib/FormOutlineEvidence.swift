import CoreGraphics
import Foundation

/// Outlines whose heading tiers span pages, as on the US Courts Pro Se form (#197, #211).
/// Candidate extraction is page-local; validation compares their marker columns and styles
/// across the document. Lowercase markers remain list items.
enum FormOutlineEvidence {
    struct Candidate: Equatable {
        var page: Int
        var indices: [Int]
        var text: String
        var rect: CGRect
        var marker: String
        var tier: Int?
        var body: CGFloat
        var bold: Bool
    }

    private static func titleCase(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.count <= 10 && words.allSatisfy { word in
            let letters = word.drop { !$0.isLetter }
            return letters.filter(\.isLetter).count < 4 || letters.first?.isUppercase == true
        }
    }

    private static func bold(_ line: TextLine) -> Bool {
        line.content.elements.allSatisfy { element in
            guard case let .text(value, style) = element else { return true }
            return style.contains(.bold) || value.allSatisfy(\.isWhitespace)
        }
    }

    private static func roman(_ value: String) -> Bool {
        let pairs: [(Character, Int)] = [("I", 1), ("V", 5), ("X", 10), ("L", 50), ("C", 100)]
        let values = Dictionary(uniqueKeysWithValues: pairs)
        let characters = Array(value)
        guard !characters.isEmpty, characters.allSatisfy({ values[$0] != nil }) else { return false }
        var total = 0
        for i in characters.indices {
            let here = values[characters[i]]!
            total += i + 1 < characters.count && here < values[characters[i + 1]]! ? -here : here
        }
        guard (1...399).contains(total) else { return false }
        var number = total, canonical = ""
        for (symbol, amount) in [("C", 100), ("XC", 90), ("L", 50), ("XL", 40),
                                 ("X", 10), ("IX", 9), ("V", 5), ("IV", 4), ("I", 1)] {
            while number >= amount { canonical += symbol; number -= amount }
        }
        return canonical == value
    }

    static func candidates(on page: PageContent) -> [Candidate] {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return [] }
        let body = max(4, LayoutReconstructor.bodySize(page.lines))
        var result: [Candidate] = []
        for (index, line) in page.lines.enumerated() where !line.monospaced && line.turn == .upright
            && line.structure == nil && abs(line.fontSize - body) <= body * 0.1 && line.text.count < 120 {
            let pieces: [(Int, TextLine, String)]
            if line.text.range(of: #"^(?:[IVXLC]{1,6}|[A-Z]|[0-9]{1,2})\.$"#, options: .regularExpression) != nil {
                pieces = page.lines.enumerated().filter { other, title in
                    other != index && title.turn == .upright && title.structure == nil
                        && abs(title.rect.midY - line.rect.midY) <= body * 0.2
                        && title.rect.minX >= line.rect.maxX
                        && title.rect.minX - line.rect.maxX <= body * 3.5
                        && abs(title.fontSize - body) <= body * 0.1
                }.map { ($0.offset, $0.element, line.text + " " + $0.element.text) }
                    .sorted { $0.1.rect.minX < $1.1.rect.minX }
            } else {
                pieces = [(index, line, line.text)]
            }
            guard let (titleIndex, titleLine, combined) = pieces.first,
                  let match = combined.range(of: #"^(?:[IVXLC]{1,6}|[A-Z]|[0-9]{1,2})\.\s+"#,
                                                options: .regularExpression) else { continue }
            let marker = String(combined[match].prefix { $0 != "." })
            let title = String(combined[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let first = title.first, first.isUppercase, let last = title.last,
                  !".,;:".contains(last), title.contains(where: \.isLetter), titleCase(title) else { continue }
            let tier: Int?
            if marker.allSatisfy(\.isNumber) { tier = 2 }
            else if marker.count > 1 { tier = roman(marker) ? 0 : nil }
            else { tier = "IVXLC".contains(marker) ? nil : 1 }
            if marker.count > 1 && tier == nil { continue }
            let indices = titleIndex == index ? [index] : [index, titleIndex]
            result.append(Candidate(page: page.number, indices: indices, text: combined,
                                    rect: line.rect.union(titleLine.rect), marker: marker,
                                    tier: tier, body: body,
                                    bold: bold(line) && bold(titleLine)))
        }
        return result
    }

    /// Validates the outline once all pages have offered candidates. A page holding only one
    /// tier joins the outline when that tier's indentation matches the document's nested columns.
    static func established(_ candidates: [Candidate]) -> [Candidate] {
        var resolved = candidates
        for index in resolved.indices where resolved[index].tier == nil {
            let edge = resolved[index].rect.minX
            let romanAtEdge = resolved.contains { $0.tier == 0 && abs($0.rect.minX - edge) <= 2 }
            let letterInside = resolved.contains { $0.tier == 1 && $0.rect.minX >= edge + resolved[index].body }
            resolved[index].tier = romanAtEdge || letterInside ? 0 : 1
        }
        let tiers = Dictionary(grouping: resolved, by: { $0.tier! })
        guard tiers.count >= 2, resolved.contains(where: \.bold),
              let outer = tiers.keys.min(), (tiers[outer]?.count ?? 0) >= 2 else { return [] }
        for outer in tiers.keys {
            for inner in tiers.keys where inner > outer {
                guard let outerEdge = tiers[outer]!.map(\.rect.minX).max(),
                      let innerEdge = tiers[inner]!.map(\.rect.minX).min(),
                      outerEdge + resolved.map(\.body).min()! <= innerEdge else { return [] }
            }
        }
        return resolved
    }

    /// PDFKit separates a marker from its title at the outline's tab stop on some pages. Join
    /// that one validated pair before block roles and reading order are decided. Candidates
    /// from a cropped or otherwise absent row are ignored.
    static func joined(_ lines: [TextLine], candidates: [Candidate])
        -> (lines: [TextLine], headings: [TextLine], listItems: [TextLine]) {
        guard !candidates.isEmpty else { return (lines, [], []) }
        var result = lines
        var removed = Set<Int>()
        var headings: [TextLine] = []
        var listItems: [TextLine] = []
        func matches(_ line: TextLine, _ candidate: Candidate) -> Bool {
            abs(line.rect.minY - candidate.rect.minY) <= 1
                && abs(line.rect.minX - candidate.rect.minX) <= 1
        }
        for candidate in candidates {
            if let index = result.indices.first(where: { !removed.contains($0)
                && result[$0].text == candidate.text && matches(result[$0], candidate) }) {
                headings.append(result[index]); continue
            }
            let markerText = candidate.marker + "."
            let titleText = String(candidate.text.dropFirst(markerText.count))
                .trimmingCharacters(in: .whitespaces)
            guard let marker = result.indices.first(where: { !removed.contains($0)
                && result[$0].text == markerText && matches(result[$0], candidate) }),
                  let title = result.indices.first(where: { !removed.contains($0)
                      && result[$0].text == titleText && result[$0].sharesRow(with: result[marker])
                      && result[$0].rect.minX > result[marker].rect.maxX }) else { continue }
            var content = result[marker].content
            content.append(InlineText(" "))
            content.append(result[title].content)
            let merged = TextLine(content: content, rect: result[marker].rect.union(result[title].rect),
                                  fontSize: result[title].fontSize, wraps: false)
            result[marker] = merged
            removed.insert(title)
            headings.append(merged)
        }
        // The lowercase tier is a list beneath the outline's deepest numbered heading. Its
        // marker uses the next tab stop, and PDFKit can leave it alone on that row. Once the
        // document has established the outline, rejoin only markers indented beyond that tier.
        if let deepest = candidates.compactMap(\.tier).max(),
           let edge = candidates.filter({ $0.tier == deepest }).map(\.rect.minX).max(),
           let body = candidates.map(\.body).min() {
            for marker in result.indices where !removed.contains(marker)
                && result[marker].text.range(of: #"^[a-z]\.$"#, options: .regularExpression) != nil
                && result[marker].rect.minX >= edge + body {
                let peers = result.indices.filter { title in
                    title != marker && !removed.contains(title)
                        && result[title].sharesRow(with: result[marker])
                        && result[title].rect.minX >= result[marker].rect.maxX
                        && result[title].rect.minX - result[marker].rect.maxX <= body * 3.5
                        && abs(result[title].fontSize - result[marker].fontSize) <= body * 0.1
                }
                guard let title = peers.min(by: { result[$0].rect.minX < result[$1].rect.minX }),
                      result[title].text.first?.isUppercase == true else { continue }
                var content = result[marker].content
                content.append(InlineText(" "))
                content.append(result[title].content)
                result[marker] = TextLine(content: content, rect: result[marker].rect.union(result[title].rect),
                                          fontSize: result[title].fontSize, wraps: false)
                removed.insert(title)
                listItems.append(result[marker])
            }
        }
        return (result.indices.compactMap { removed.contains($0) ? nil : result[$0] }, headings, listItems)
    }
}
