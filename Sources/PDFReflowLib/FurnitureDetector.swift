import CoreGraphics
import Foundation

/// Repeated, separated margin lines on neighboring pages, including alternating sides.
/// Evidence is local to a chapter; document length does not set the frequency threshold.
enum FurnitureDetector {
    private struct Candidate {
        var pageIndex: Int
        var lineIndex: Int
        var number: Int
        var position: CGFloat
        var fontSize: CGFloat
        var isFolio: Bool
    }

    static func strip(_ pages: inout [PageContent]) -> [ConversionWarning] {
        guard pages.count >= 3 else { return [] }
        var warnings = stripSyntheticMargins(&pages)
        var groups: [String: [Candidate]] = [:]
        for (pageIndex, page) in pages.enumerated() {
            guard !page.hasSyntheticTextStyle, page.bounds.height > 0, page.bounds.isFinite else { continue }
            for (lineIndex, line) in page.lines.enumerated() {
                let position = (line.rect.midY - page.bounds.minY) / page.bounds.height
                let top = position >= 0.90
                // Retain the narrower footer band: lower-margin numbers can participate
                // in whitespace cuts around illustrated rows. Widening that band changes
                // reading order in Our Flag even when the removed number is furniture.
                guard top || position <= 0.07, line.rect.isFinite,
                      line.fontSize > 0, line.fontSize.isFinite else { continue }
                let words = line.text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
                guard !words.isEmpty, line.text.count < 100 else { continue }
                // Only the outermost row is eligible; a caption or paragraph above a
                // footer must not be removed merely because it also repeats.
                guard !page.lines.contains(where: { other in
                    top ? other.rect.midY > line.rect.midY + line.rect.height * 0.4
                        : other.rect.midY < line.rect.midY - line.rect.height * 0.4
                }) else { continue }
                // The line must be separated from inward content, not just happen to be
                // the first/last line of a paragraph near the page edge.
                let inward = page.lines.enumerated().filter { index, other in
                    index != lineIndex && (top ? other.rect.midY < line.rect.midY : other.rect.midY > line.rect.midY)
                }.map { top ? line.rect.minY - $0.element.rect.maxY : $0.element.rect.minY - line.rect.maxY }
                let folioParts = words.count == 1 ? words[0].split(separator: "-", omittingEmptySubsequences: false) : []
                let isFolio = (1...2).contains(folioParts.count) && folioParts.allSatisfy { Int($0) != nil }
                // A bare folio has its own numeric/position evidence. Nearby figure labels
                // must not stop a chapter-page number from being recognized.
                guard let gap = inward.min(), isFolio || gap >= max(line.rect.height, page.bounds.height * 0.012) else { continue }
                // Bare folios use measured glyph height: fallback extraction estimates
                // fontSize from that height, whereas native extraction reads font attributes.
                let candidate = Candidate(pageIndex: pageIndex, lineIndex: lineIndex, number: page.number,
                                          position: position, fontSize: isFolio ? line.rect.height : line.fontSize, isFolio: isFolio)
                let edge = top ? "top:" : "bottom:"
                groups[edge + words.joined(separator: " "), default: []].append(candidate)
                if isFolio, folioParts.count == 2, let value = Int(folioParts[1]) {
                    let (offset, overflow) = value.subtractingReportingOverflow(page.number)
                    if !overflow {
                        groups[edge + String(folioParts[0]) + "-#(offset=\(offset))", default: []].append(candidate)
                    }
                }
                // Normalize only a boundary page number, with a consistent physical-page
                // offset. Keep internal digits (9/11, chapter numbers, dates) meaningful.
                for index in Set([0, words.count - 1]) {
                    if let value = Int(words[index]), value >= 0 {
                        var normalized = words
                        let (offset, overflow) = value.subtractingReportingOverflow(page.number)
                        guard !overflow else { continue }
                        normalized[index] = "#(offset=\(offset))"
                        groups[edge + normalized.joined(separator: " "), default: []].append(candidate)
                        // A facing-page folio can move from before to after the same
                        // header. Share evidence across both sides without erasing
                        // internal chapter/date digits or reducing the three-page minimum.
                        if words.count > 1 {
                            var title = words
                            title.remove(at: index)
                            groups[edge + "folio(\(offset)):" + title.joined(separator: " "), default: []].append(candidate)
                        }
                    }
                }
            }
        }
        var removals: [Int: Set<Int>] = [:]
        for group in groups.values {
            let ordered = group.sorted { $0.number < $1.number }
            var run: [Candidate] = []
            func finish() {
                guard run.count >= 3 else { return }
                for candidate in run { removals[candidate.pageIndex, default: []].insert(candidate.lineIndex) }
            }
            for candidate in ordered {
                if let first = run.first, let last = run.last {
                    let distance = candidate.number - last.number
                    // Bare numeric folios can shift within the margin on revised pages;
                    // their page-number offset supplies evidence that prose headers lack.
                    let folios = first.isFolio && candidate.isFolio
                    if !(1...2).contains(distance)
                        || abs(candidate.position - first.position) > (folios ? 0.04 : 0.004)
                        || abs(candidate.fontSize - first.fontSize) > max(0.5, first.fontSize * (folios ? 0.25 : 0.1)) {
                        finish()
                        run.removeAll(keepingCapacity: true)
                    }
                }
                run.append(candidate)
            }
            finish()
        }
        for index in pages.indices {
            guard let removed = removals[index], !removed.isEmpty else { continue }
            let kept = pages[index].lines.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
            guard !kept.isEmpty else { continue }
            pages[index].lines = kept
            warnings.append(.init(code: .furnitureRemoved, page: pages[index].number,
                                  message: "Repeated header or footer omitted from the reflowed text."))
        }
        return warnings.sorted { ($0.page ?? 0) < ($1.page ?? 0) }
    }

    // Preserve the existing whole-document margin cleanup for synthetic OCR layers.
    // Their noisy fonts/geometry must not enter the native typography rule.
    private static func stripSyntheticMargins(_ pages: inout [PageContent]) -> [ConversionWarning] {
        guard pages.count >= 3 else { return [] }
        func key(_ line: TextLine, bounds: CGRect) -> String? {
            let edge: String
            if line.rect.midY > bounds.minY + bounds.height * 0.93 { edge = "top" }
            else if line.rect.midY < bounds.minY + bounds.height * 0.07 { edge = "bottom" }
            else { return nil }
            // Short edge text only; a repeated paragraph is not furniture.
            guard line.text.count < 100 else { return nil }
            return edge + ":" + line.text.lowercased().replacingOccurrences(
                of: "[0-9]+", with: "#", options: .regularExpression)
        }
        var occurrences: [String: Int] = [:]
        for page in pages where page.hasSyntheticTextStyle {
            for candidate in Set(page.lines.compactMap { key($0, bounds: page.bounds) }) {
                occurrences[candidate, default: 0] += 1
            }
        }
        var warnings: [ConversionWarning] = []
        for i in pages.indices where pages[i].hasSyntheticTextStyle {
            let bounds = pages[i].bounds
            let kept = pages[i].lines.filter { line in
                guard let candidate = key(line, bounds: bounds) else { return true }
                return occurrences[candidate, default: 0] < max(3, (pages.count + 1) / 2)
            }
            if !kept.isEmpty && kept.count != pages[i].lines.count {
                warnings.append(.init(code: .furnitureRemoved, page: pages[i].number,
                    message: "Repeated header or footer omitted from the reflowed text."))
                pages[i].lines = kept
            }
        }
        return warnings
    }

}
