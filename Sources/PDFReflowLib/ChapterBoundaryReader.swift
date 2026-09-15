import Foundation
import PDFKit

/// Conservative chapter hints. Arbitrary outline entries are not chapter semantics.
enum ChapterBoundaryReader {
    struct Candidate: Equatable, Codable {
        var number: Int
        var title: String
        var page: Int
    }

    /// Only a root-level, consecutive Arabic-numbered Chapter 1...N sequence is supported.
    /// PDFKit resolves both named destinations and local GoTo actions. Remote actions,
    /// duplicate/backward destinations, nested outlines and incomplete sequences are ignored.
    static func read(_ url: URL) throws -> [Candidate] {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: url), !document.isLocked,
                  let root = document.outlineRoot, root.numberOfChildren <= 10_000 else { return [] }
            var candidates: [Candidate] = []
            for index in 0..<root.numberOfChildren {
                try Task.checkCancellation()
                guard let item = root.child(at: index), let label = item.label,
                      let parsed = parse(label) else { continue }
                guard item.action == nil || item.action is PDFActionGoTo,
                      let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination,
                      let page = destination.page, page.document === document else { return [] }
                let pageIndex = document.index(for: page)
                guard pageIndex != NSNotFound, pageIndex < document.pageCount else { return [] }
                candidates.append(.init(number: parsed.number, title: parsed.title, page: pageIndex + 1))
            }
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

    private static func parse(_ label: String) -> (number: Int, title: String)? {
        guard label.count <= 512,
              let match = label.range(of: #"^Chapter\s+[1-9][0-9]*\s+"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let prefix = label[match].split(whereSeparator: \.isWhitespace)
        guard prefix.count == 2, let number = Int(prefix[1]) else { return nil }
        let title = String(label[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return (number, title)
    }

    /// Match complete, adjacent native lines in the upper half of a destination page.
    /// Require the chapter number and title together, not a title mentioned in body prose.
    static func matches(_ candidate: Candidate, page: PageContent) -> Bool {
        guard candidate.page == page.number, !page.recognized, !page.hasSyntheticTextStyle else { return false }
        let lines = page.lines.filter {
            $0.rect.isFinite && $0.rect.minY >= page.bounds.midY
        }.sorted { $0.rect.midY > $1.rect.midY }.prefix(6).map { normalize($0.text) }
        let marker = "chapter \(candidate.number)"
        let title = normalize(candidate.title)
        guard !title.isEmpty else { return false }
        for start in lines.indices {
            // A source can prefix the chapter marker with its publication title.
            guard lines[start] == marker || lines[start].hasSuffix(" " + marker) ||
                    lines[start].hasPrefix(marker + " ") else { continue }
            for end in start..<min(lines.count, start + 5) {
                let joined = lines[start...end].joined(separator: " ")
                if joined == marker + " " + title || joined.hasSuffix(" " + marker + " " + title) { return true }
            }
        }
        return false
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
