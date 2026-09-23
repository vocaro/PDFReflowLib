import Foundation
import PDFKit

/// Conservative chapter hints. Arbitrary outline entries are not chapter semantics.
enum ChapterBoundaryReader {
    struct Candidate: Equatable, Codable {
        var number: Int
        var title: String
        var page: Int
        /// Preserve the printed numeral for source verification; nil is the original Arabic form.
        var marker: String? = nil
    }

    /// A consecutive Chapter 1...N sequence can sit at the root or under part containers.
    /// Roman numerals and punctuation are admitted only with the same complete source check.
    /// Children of a chapter remain section navigation, not additional chapter candidates.
    static func read(_ url: URL, password: ConversionOptions.Password? = nil) throws -> [Candidate] {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let document = SourceDocument.open(url, password: password), !document.isLocked,
                  let root = document.outlineRoot else { return [] }
            var candidates: [Candidate] = []
            var visits = 0
            func children(_ parent: PDFOutline, depth: Int) throws -> Bool {
                guard depth < 4, parent.numberOfChildren <= 10_000 - visits else { return false }
                for index in 0..<parent.numberOfChildren {
                    try Task.checkCancellation()
                    visits += 1
                    guard visits <= 10_000, let item = parent.child(at: index) else { return false }
                    guard let label = item.label, let parsed = parse(label) else {
                        // Only an explicit part groups chapter candidates. Unrelated outline
                        // trees (including remote/deep ones) cannot invalidate a root sequence.
                        if let label = item.label, label.count <= 512,
                           label.range(of: #"^Part\s+\S"#, options: [.regularExpression, .caseInsensitive]) != nil,
                           item.numberOfChildren > 0,
                           item.action == nil || item.action is PDFActionGoTo {
                            guard try children(item, depth: depth + 1) else { return false }
                        }
                        continue
                    }
                    guard item.action == nil || item.action is PDFActionGoTo,
                          let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination,
                          let page = destination.page, page.document === document else { return false }
                    let pageIndex = document.index(for: page)
                    guard pageIndex != NSNotFound, pageIndex < document.pageCount else { return false }
                    candidates.append(.init(number: parsed.number, title: parsed.title,
                                            page: pageIndex + 1, marker: parsed.marker))
                }
                return true
            }
            guard try children(root, depth: 0) else { return [] }
            return ordered(candidates) ? candidates : []
        }
    }

    static func ordered(_ candidates: [Candidate]) -> Bool {
        guard candidates.count >= 2 else { return false }
        return candidates.enumerated().allSatisfy { index, candidate in
            candidate.number == index + 1 && candidate.page > 0 &&
                (index == 0 || candidate.page > candidates[index - 1].page)
        }
    }

    private static func parse(_ label: String) -> (number: Int, title: String, marker: String?)? {
        guard label.count <= 512 else { return nil }
        let collapsed = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let match = collapsed.firstMatch(of: /^([Cc][Hh][Aa][Pp][Tt][Ee][Rr])\s+([1-9][0-9]*|[IVXLCDMivxlcdm]+)(?:[.:]\s*|\s+[-–—]\s+|\s+)(.+)$/) else { return nil }
        let numeral = String(match.2)
        let number = Int(numeral) ?? roman(numeral)
        let title = String(match.3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number, !title.isEmpty else { return nil }
        return (number, title, Int(numeral) == nil ? "chapter " + numeral.lowercased() : nil)
    }

    /// Reject noncanonical spellings such as IIX; the outline must state an actual numeral.
    private static func roman(_ value: String) -> Int? {
        let symbols: [(String, Int)] = [("M", 1000), ("CM", 900), ("D", 500), ("CD", 400),
            ("C", 100), ("XC", 90), ("L", 50), ("XL", 40), ("X", 10), ("IX", 9),
            ("V", 5), ("IV", 4), ("I", 1)]
        var rest = value.uppercased(), total = 0
        for (symbol, amount) in symbols {
            while rest.hasPrefix(symbol) { total += amount; rest.removeFirst(symbol.count) }
        }
        guard rest.isEmpty, total > 0, total <= 3999 else { return nil }
        var count = total, canonical = ""
        for (symbol, amount) in symbols {
            while count >= amount { canonical += symbol; count -= amount }
        }
        return canonical == value.uppercased() ? total : nil
    }

    /// Match complete, adjacent native lines in the upper half of a destination page.
    /// Require the chapter number and title together, not a title mentioned in body prose.
    static func matches(_ candidate: Candidate, page: PageContent) -> Bool {
        guard candidate.page == page.number, !page.recognized, !page.hasSyntheticTextStyle else { return false }
        let lines = page.lines.filter {
            $0.rect.isFinite && $0.rect.minY >= page.bounds.midY
        }.sorted { $0.rect.midY > $1.rect.midY }.prefix(6).map { normalize($0.text) }
        let marker = candidate.marker ?? "chapter \(candidate.number)"
        let title = normalize(candidate.title)
        guard !title.isEmpty else { return false }
        let separators = [" ", ": ", ":", ". ", ".", " – ", " — ", " - "]
        let openings = separators.map { marker + $0 + title }
        for start in lines.indices {
            // A publication prefix is allowed only on a standalone marker line. A prose
            // mention such as "See Chapter II: Beta" is not a printed chapter opening.
            guard lines[start] == marker || lines[start].hasSuffix(" " + marker)
                || separators.contains(where: { lines[start].hasPrefix(marker + $0) }) else { continue }
            for end in start..<min(lines.count, start + 5) {
                let joined = lines[start...end].joined(separator: " ")
                // A source can prefix the chapter marker with its publication title.
                if openings.contains(where: { joined == $0 || joined.hasSuffix(" " + $0) }) { return true }
            }
        }
        return false
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
