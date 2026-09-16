import CoreGraphics
import Foundation

/// Repeated, separated margin lines on neighboring pages, including alternating sides.
/// Evidence is local to a chapter; document length does not set the frequency threshold.
///
/// Detection is phased so extraction can release each page: `collect` records one page's
/// margin candidates, `resolve` decides removals from the accumulated ledger, and `apply`
/// needs only the page it edits. `strip` runs the three phases over an in-memory array.
enum FurnitureDetector {
    fileprivate struct Candidate {
        var pageIndex: Int
        var lineIndex: Int
        var number: Int
        var position: CGFloat
        var fontSize: CGFloat
        var isFolio: Bool
    }

    /// Document-wide evidence without the pages themselves.
    struct Ledger {
        fileprivate var groups: [String: [Candidate]] = [:]
        fileprivate var syntheticOccurrences: [String: Int] = [:]
        fileprivate var pageCount = 0
        init() {}
    }

    /// Resolved removals. Applying them to a page consults only that page.
    struct Plan {
        fileprivate var native: [Int: Set<Int>] = [:]
        fileprivate var syntheticOccurrences: [String: Int] = [:]
        fileprivate var syntheticThreshold = Int.max
        fileprivate var pageCount = 0
    }

    static func strip(_ pages: inout [PageContent]) -> [ConversionWarning] {
        var ledger = Ledger()
        for (index, page) in pages.enumerated() { collect(page, pageIndex: index, into: &ledger) }
        let plan = resolve(ledger)
        var warnings: [ConversionWarning] = []
        for index in pages.indices {
            if let warning = apply(plan, to: &pages[index], pageIndex: index) { warnings.append(warning) }
        }
        return warnings.sorted { $0.page < $1.page }
    }

    static func collect(_ page: PageContent, pageIndex: Int, into ledger: inout Ledger) {
        ledger.pageCount += 1
        if page.hasSyntheticTextStyle {
            // Preserve the existing whole-document margin cleanup for synthetic OCR layers.
            // Their noisy fonts/geometry must not enter the native typography rule.
            for candidate in Set(page.lines.compactMap { syntheticKey($0, bounds: page.bounds) }) {
                ledger.syntheticOccurrences[candidate, default: 0] += 1
            }
            return
        }
        guard page.bounds.height > 0, page.bounds.isFinite else { return }
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
            ledger.groups[edge + words.joined(separator: " "), default: []].append(candidate)
            if isFolio, folioParts.count == 2, let value = Int(folioParts[1]) {
                let (offset, overflow) = value.subtractingReportingOverflow(page.number)
                if !overflow {
                    ledger.groups[edge + String(folioParts[0]) + "-#(offset=\(offset))", default: []].append(candidate)
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
                    ledger.groups[edge + normalized.joined(separator: " "), default: []].append(candidate)
                    // A facing-page folio can move from before to after the same
                    // header. Share evidence across both sides without erasing
                    // internal chapter/date digits or reducing the three-page minimum.
                    if words.count > 1 {
                        var title = words
                        title.remove(at: index)
                        ledger.groups[edge + "folio(\(offset)):" + title.joined(separator: " "), default: []].append(candidate)
                    }
                }
            }
        }
    }

    static func resolve(_ ledger: Ledger) -> Plan {
        var plan = Plan()
        plan.pageCount = ledger.pageCount
        guard ledger.pageCount >= 3 else { return plan }
        plan.syntheticOccurrences = ledger.syntheticOccurrences
        plan.syntheticThreshold = max(3, (ledger.pageCount + 1) / 2)
        for group in ledger.groups.values {
            let ordered = group.sorted { $0.number < $1.number }
            var run: [Candidate] = []
            func finish() {
                guard run.count >= 3 else { return }
                for candidate in run { plan.native[candidate.pageIndex, default: []].insert(candidate.lineIndex) }
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
        return plan
    }

    static func apply(_ plan: Plan, to page: inout PageContent, pageIndex: Int) -> ConversionWarning? {
        guard plan.pageCount >= 3 else { return nil }
        let kept: [TextLine]
        if page.hasSyntheticTextStyle {
            let bounds = page.bounds
            kept = page.lines.filter { line in
                guard let candidate = syntheticKey(line, bounds: bounds) else { return true }
                return plan.syntheticOccurrences[candidate, default: 0] < plan.syntheticThreshold
            }
            guard !kept.isEmpty, kept.count != page.lines.count else { return nil }
        } else {
            guard let removed = plan.native[pageIndex], !removed.isEmpty else { return nil }
            kept = page.lines.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
            guard !kept.isEmpty else { return nil }
        }
        page.lines = kept
        return ConversionWarning(code: .furnitureRemoved, page: page.number,
                                 message: "Repeated header or footer omitted from the reflowed text.")
    }

    private static func syntheticKey(_ line: TextLine, bounds: CGRect) -> String? {
        let edge: String
        if line.rect.midY > bounds.minY + bounds.height * 0.93 { edge = "top" }
        else if line.rect.midY < bounds.minY + bounds.height * 0.07 { edge = "bottom" }
        else { return nil }
        // Short edge text only; a repeated paragraph is not furniture.
        guard line.text.count < 100 else { return nil }
        return edge + ":" + line.text.lowercased().replacingOccurrences(
            of: "[0-9]+", with: "#", options: .regularExpression)
    }
}
