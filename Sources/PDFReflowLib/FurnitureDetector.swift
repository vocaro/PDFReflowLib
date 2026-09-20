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
        var isTop: Bool
        var position: CGFloat
        var fontSize: CGFloat
        /// The line's own type size, whatever `fontSize` was measured from. A bare folio weighs
        /// its glyph height against other folios, but the margin slot it stands in is a place and
        /// a type size the whole document keeps, so slots are compared in one unit.
        var typeSize: CGFloat
        var isFolio: Bool
        /// The other lines of the stacked band this line belongs to, if any; it is removed
        /// only when all of them are.
        var dependsOn: [Int] = []
    }

    /// One margin place a document keeps: an edge, a position in the page, and a type size.
    /// Running heads and feet hold theirs for the length of a book.
    fileprivate struct Slot {
        var isTop: Bool
        var position: CGFloat
        var fontSize: CGFloat
        var pages: Set<Int> = []

        func admits(_ candidate: Candidate) -> Bool {
            candidate.isTop == isTop && abs(candidate.position - position) <= 0.004
                && abs(candidate.typeSize - fontSize) <= max(0.5, fontSize * 0.1)
        }
    }

    /// Document-wide evidence without the pages themselves.
    struct Ledger {
        fileprivate var groups: [String: [Candidate]] = [:]
        fileprivate var syntheticOccurrences: [String: Int] = [:]
        fileprivate var pageCount = 0
        /// The margin lines each page offered, whether or not they are removed in the end. A
        /// caller that must set the margins apart from the body before the plan exists — the
        /// reference vocabulary does (#184) — reads them back here while it still has the page.
        private(set) var marginLines: [Int: Set<Int>] = [:]
        init() {}

        fileprivate mutating func note(_ lineIndex: Int, onPageAt pageIndex: Int) {
            marginLines[pageIndex, default: []].insert(lineIndex)
        }
    }

    /// Resolved removals. Applying them to a page consults only that page.
    struct Plan {
        fileprivate var native: [Int: Set<Int>] = [:]
        /// Per page, the lines of a stacked band each stacked line stands or falls with.
        fileprivate var dependencies: [Int: [Int: [Int]]] = [:]
        fileprivate var syntheticOccurrences: [String: Int] = [:]
        fileprivate var syntheticThreshold = Int.max
        fileprivate var pageCount = 0

        /// The native lines this plan takes off one page, needing only the page's index. What
        /// extraction has already released can still be asked what its margins lost (#184).
        /// A synthetic OCR layer is decided against the page itself and answers nothing here.
        func removals(onPageAt pageIndex: Int) -> Set<Int> {
            guard pageCount >= 3, var removed = native[pageIndex] else { return [] }
            // The lines of a stacked band go only all together: drop a dependent line until
            // every line left has the whole band it stands with.
            var settled = false
            while !settled {
                settled = true
                for (lineIndex, band) in dependencies[pageIndex] ?? [:]
                where removed.contains(lineIndex) && !band.allSatisfy(removed.contains) {
                    removed.remove(lineIndex)
                    settled = false
                }
            }
            return removed
        }
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
        let height = page.bounds.height
        func position(_ value: CGFloat) -> CGFloat { (value - page.bounds.minY) / height }

        /// The clear space a margin row keeps from the content it is set apart from.
        func separation(_ line: TextLine) -> CGFloat { max(line.rect.height, height * 0.012) }
        /// Whether the line stands in this edge's candidate band. The footer band is narrower:
        /// lower-margin numbers can participate in whitespace cuts around illustrated rows, and
        /// widening that band changes reading order in Our Flag even when the number is furniture.
        func inBand(_ line: TextLine, top: Bool) -> Bool {
            top ? position(line.rect.midY) >= 0.90 : position(line.rect.midY) <= 0.07
        }
        /// Whether the line can be weighed as margin text at all: measurable geometry and type,
        /// with words, and short enough that a repeated paragraph is not taken for furniture.
        func measurable(_ line: TextLine) -> Bool {
            line.rect.isFinite && line.fontSize > 0 && line.fontSize.isFinite
                && line.text.count < 100 && !words(line).isEmpty
        }
        /// Whether no line of the page stands further out than this one. Only the outermost row
        /// is eligible on its own; a caption or paragraph above a footer must not be removed
        /// merely because it also repeats.
        func outermost(_ line: TextLine, top: Bool) -> Bool {
            !page.lines.contains { other in
                top ? other.rect.midY > line.rect.midY + line.rect.height * 0.4
                    : other.rect.midY < line.rect.midY - line.rect.height * 0.4
            }
        }
        /// The clear space between the line and the nearest content inward of it, or nil when the
        /// line is the page's only text. A line must be set apart from inward content, not just
        /// happen to be the first or last line of a paragraph near the page edge.
        func inwardGap(_ lineIndex: Int, top: Bool) -> CGFloat? {
            let line = page.lines[lineIndex]
            return page.lines.enumerated().filter { index, other in
                index != lineIndex && (top ? other.rect.midY < line.rect.midY : other.rect.midY > line.rect.midY)
            }.map { top ? line.rect.minY - $0.element.rect.maxY : $0.element.rect.minY - line.rect.maxY }.min()
        }
        /// A block's inward boundary: the last edge its lines reach towards the body.
        func blockEdge(_ block: Set<Int>, top: Bool) -> CGFloat {
            top ? block.map { page.lines[$0].rect.minY }.min()!
                : block.map { page.lines[$0].rect.maxY }.max()!
        }

        var recorded: Set<Int> = []
        /// Files one line under every signature its words support, so `resolve` can find the runs.
        func record(_ lineIndex: Int, top: Bool, dependsOn: [Int] = []) {
            let line = page.lines[lineIndex]
            let words = words(line)
            recorded.insert(lineIndex)
            ledger.note(lineIndex, onPageAt: pageIndex)
            // Bare folios use measured glyph height: fallback extraction estimates
            // fontSize from that height, whereas native extraction reads font attributes.
            let folio = isFolio(words)
            let candidate = Candidate(pageIndex: pageIndex, lineIndex: lineIndex, number: page.number,
                                      isTop: top, position: position(line.rect.midY),
                                      fontSize: folio ? line.rect.height : line.fontSize,
                                      typeSize: line.fontSize,
                                      isFolio: folio, dependsOn: dependsOn)
            let edge = top ? "top:" : "bottom:"
            ledger.groups[edge + words.joined(separator: " "), default: []].append(candidate)
            let folioParts = folio ? words[0].split(separator: "-", omittingEmptySubsequences: false) : []
            if folioParts.count == 2, let value = Int(folioParts[1]) {
                let (offset, overflow) = value.subtractingReportingOverflow(page.number)
                if !overflow {
                    ledger.groups[edge + String(folioParts[0]) + "-#(offset=\(offset))", default: []].append(candidate)
                }
            }
            // A running foot may lead or close with a `chapter-page` number beside its words:
            // NOAA sets `2-14 | Climate Trends` at the body size in ordinary capitalization, so
            // nothing on one page separates it from prose and every page words it differently
            // (#184). Normalize the page half against the same consistent physical-page offset a
            // bare folio uses, and keep the chapter half and the words as they are.
            for index in Set([0, words.count - 1]) where words.count > 1 {
                let parts = words[index].split(separator: "-", omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[0].isEmpty, let value = Int(parts[1]), value >= 0 else { continue }
                let (offset, overflow) = value.subtractingReportingOverflow(page.number)
                guard !overflow else { continue }
                var normalized = words
                normalized[index] = String(parts[0]) + "-#(offset=\(offset))"
                ledger.groups[edge + normalized.joined(separator: " "), default: []].append(candidate)
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

        /// One outermost row, set apart from the body. A bare folio has its own numeric/position
        /// evidence; nearby figure labels must not stop a chapter-page number from being recognized.
        for (lineIndex, line) in page.lines.enumerated() {
            for top in [true, false]
            where inBand(line, top: top) && measurable(line) && outermost(line, top: top) {
                guard let gap = inwardGap(lineIndex, top: top),
                      isFolio(words(line)) || gap >= separation(line) else { continue }
                record(lineIndex, top: top)
            }
        }

        /// A running head or foot of several stacked rows. The IRS table's foot sets its
        /// continuation marker over the running foot, and a data sheet's head sets a division over
        /// a project title, closer together than a line height: no row of such a band is set apart
        /// from the next, so none is a candidate on its own. Where the outermost row was not
        /// recorded, the rows stacked on it (each nearer the stack than its own separation) form
        /// one block with it: a block of at most eight lines, inside the outer eighth of the page,
        /// is set apart from the body as one outermost row is, because the loop stops at the first
        /// row that stands clear. Every line of it is a candidate, removed only with all the
        /// others, so a block one page words differently stays whole on that page.
        func recordStack(top: Bool) {
            let all = Array(page.lines.indices)
            let outer = all.filter { outermost(page.lines[$0], top: top) }
            guard !outer.isEmpty, !outer.allSatisfy(recorded.contains),
                  outer.allSatisfy({ inBand(page.lines[$0], top: top) }) else { return }
            var stack = Set(outer)
            while true {
                let edge = blockEdge(stack, top: top)
                let stacked = all.filter { index in
                    let line = page.lines[index]
                    return !stack.contains(index)
                        && (top ? edge - line.rect.maxY : line.rect.minY - edge) < separation(line)
                }
                guard !stacked.isEmpty else { break }
                stack.formUnion(stacked)
                guard stack.count <= 8 else { return }
            }
            guard stack.count > outer.count, stack.count < all.count,
                  stack.allSatisfy({ measurable(page.lines[$0]) }) else { return }
            // The block may reach further inward than a single row, but not past the outer eighth:
            // a slide's two-line title stands lower, and the body must not be read as a head.
            let edge = position(blockEdge(stack, top: top))
            guard top ? edge >= 0.875 : edge <= 0.125 else { return }
            let ordered = stack.sorted()
            for lineIndex in ordered where !recorded.contains(lineIndex) {
                record(lineIndex, top: top, dependsOn: ordered.filter { $0 != lineIndex })
            }
        }
        recordStack(top: true)
        recordStack(top: false)
    }

    static func resolve(_ ledger: Ledger) -> Plan {
        var plan = Plan()
        plan.pageCount = ledger.pageCount
        guard ledger.pageCount >= 3 else { return plan }
        plan.syntheticOccurrences = ledger.syntheticOccurrences
        plan.syntheticThreshold = max(3, (ledger.pageCount + 1) / 2)
        /// Every candidate once, whichever signatures filed it.
        var unique: [Int: [Int: Candidate]] = [:]
        for group in ledger.groups.values {
            for candidate in group {
                unique[candidate.pageIndex, default: [:]][candidate.lineIndex] = candidate
            }
        }
        for group in ledger.groups.values {
            let ordered = group.sorted { $0.number < $1.number }
            var run: [Candidate] = []
            func finish() {
                guard run.count >= 3 else { return }
                for candidate in run {
                    plan.native[candidate.pageIndex, default: []].insert(candidate.lineIndex)
                    if !candidate.dependsOn.isEmpty {
                        plan.dependencies[candidate.pageIndex, default: [:]][candidate.lineIndex] = candidate.dependsOn
                    }
                }
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
        admitSlotEvidence(&plan, unique: unique)
        return plan
    }

    /// A running head keeps one place and one type size for the length of a book. Where the words
    /// change too often for a three-page run — a transition head over two chapters' notes, a
    /// chapter whose notes fill two pages, front matter naming its own part — the slot the
    /// document has already established supplies the evidence the words withhold (#10).
    ///
    /// Only a slot the book keeps on a quarter of its pages, and at least six, counts as
    /// established, and a line is admitted only where it stands in that same place at that same
    /// size, within the tolerances the run rule uses. The line must already be a candidate: an
    /// outermost margin row, set apart from the body, short and measurable. Page-local type size
    /// does not overrule the document here, and that is the point: a notes page sets its body
    /// smaller than the running head above it, so the head reads as a heading on that page alone.
    ///
    /// A stacked band is not admitted. Its rows are held together by their own separation rather
    /// than by a place the document keeps, and removing one band on slot evidence alone would
    /// reach further into the page than this evidence reaches.
    private static func admitSlotEvidence(_ plan: inout Plan, unique: [Int: [Int: Candidate]]) {
        // Slots accumulate in page-and-line order, so which candidate opens a slot — and therefore
        // where its tolerance is centered — does not depend on dictionary order.
        let ordered = unique.keys.sorted().flatMap { pageIndex in
            unique[pageIndex]!.keys.sorted().map { (pageIndex, $0, unique[pageIndex]![$0]!) }
        }
        var slots: [Slot] = []
        for (pageIndex, lineIndex, candidate) in ordered
        where plan.native[pageIndex]?.contains(lineIndex) == true {
            if let index = slots.firstIndex(where: { $0.admits(candidate) }) {
                slots[index].pages.insert(pageIndex)
            } else {
                slots.append(Slot(isTop: candidate.isTop, position: candidate.position,
                                  fontSize: candidate.typeSize, pages: [pageIndex]))
            }
        }
        let floor = max(6, (plan.pageCount + 3) / 4)
        let established = slots.filter { $0.pages.count >= floor }
        guard !established.isEmpty else { return }
        for (pageIndex, lineIndex, candidate) in ordered
        where candidate.dependsOn.isEmpty && plan.native[pageIndex]?.contains(lineIndex) != true
            && established.contains(where: { $0.admits(candidate) }) {
            plan.native[pageIndex, default: []].insert(lineIndex)
        }
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
            let removed = plan.removals(onPageAt: pageIndex)
            guard !removed.isEmpty else { return nil }
            kept = page.lines.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
            guard !kept.isEmpty else { return nil }
        }
        page.lines = kept
        return ConversionWarning(code: .furnitureRemoved, page: page.number,
                                 message: "Repeated header or footer omitted from the reflowed text.")
    }

    /// The whitespace-separated, lowercased words of a line.
    private static func words(_ line: TextLine) -> [String] {
        line.text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether the words are a bare page number, alone or as `chapter-page`.
    private static func isFolio(_ words: [String]) -> Bool {
        guard words.count == 1 else { return false }
        let parts = words[0].split(separator: "-", omittingEmptySubsequences: false)
        return (1...2).contains(parts.count) && parts.allSatisfy { Int($0) != nil }
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
