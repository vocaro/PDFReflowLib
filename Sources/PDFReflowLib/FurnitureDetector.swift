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
        /// Every physical-page offset the line's boundary numbers imply: what it states about
        /// where its page stands in the source's own numbering. `430 APPENDIX` on physical page
        /// 448 states -18, and so does a bare `429` on physical page 447.
        var offsets: Set<Int> = []
        /// The other lines of the stacked band this line belongs to, if any; it is removed
        /// only when all of them are.
        var dependsOn: [Int] = []
    }

    /// A bare number standing alone in a page's outer foot margin, set apart from the body, and
    /// the offset it states between its own value and the physical page it stands on. Held apart
    /// from the run candidates because nothing about where it stands removes it: only an offset
    /// the document has already established elsewhere does (#271).
    fileprivate struct DropFolio {
        var pageIndex: Int
        var lineIndex: Int
        var offset: Int
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
        fileprivate var dropFolios: [DropFolio] = []
        fileprivate var syntheticOccurrences: [String: Int] = [:]
        fileprivate var overprints: [Int: [Int: Set<Int>]] = [:]
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
        fileprivate var overprints: [Int: [Int: Set<Int>]] = [:]
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
            for (original, copies) in overprints[pageIndex] ?? [:] where removed.contains(original) {
                removed.formUnion(copies)
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

    /// The page image this page is printed on, where its sheet is larger than the page.
    ///
    /// Some books are typeset on a page of their own and printed centred on a larger sheet: a
    /// Supreme Court slip opinion sets a six-by-nine page on US Letter, inset 156.24 points on
    /// the left and 156.13 on the right of a 612-point sheet, page after page. The margin its
    /// running head stands in is that page's margin, not the paper's, and read against the paper
    /// the head is nowhere near a margin at all — so all 210 of *Loper Bright*'s heads survived,
    /// none of them ever a candidate for `resolve` to weigh (#289).
    ///
    /// What says a page is printed this way is **the symmetry and the depth of its side insets**.
    /// Both must reach a seventh of the sheet and the two must agree within a fiftieth of it,
    /// which separates a page image from an ordinary margin by a wide gap on this corpus:
    /// *Loper Bright* is inset 156.24 and 156.13 on 612 — a quarter of the sheet, agreeing to a
    /// tenth of a point — while the 9/11 report is 39.7 and 44.2 on 396, the FAA handbook 72.0
    /// and 35.9 on 594, and *The Fed Explained* 58.8 and 92.7 on 612. None of those is both deep
    /// enough and even enough to be a page rather than a margin, and each keeps the band it had.
    ///
    /// Read per page, because the evidence arrives one page at a time
    /// ([decision 0008](../../doc/decisions/0008-streamed-blocks-to-the-writer.md)). One page's
    /// own symmetry cannot remove anything by itself: what `resolve` removes still has to repeat,
    /// in the same place and at the same size, on neighbouring pages.
    static func typePage(of page: PageContent) -> CGRect? {
        guard !page.lines.isEmpty, page.bounds.width > 0, page.bounds.isFinite else { return nil }
        let printed = page.lines.dropFirst().reduce(page.lines[0].rect) { $0.union($1.rect) }
        guard printed.isFinite, printed.height > 0 else { return nil }
        let width = page.bounds.width
        let left = printed.minX - page.bounds.minX, right = page.bounds.maxX - printed.maxX
        guard left >= width / 7, right >= width / 7, abs(left - right) <= width / 50 else { return nil }
        return printed
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
        // A shadow/knockout copy is not content inward of a running foot. Keep every
        // extracted line, but let a proved furniture removal own its coincident copies.
        // This tolerance never removes body text or changes the general overprint reader.
        var originals: [Int: Int] = [:]
        for index in page.lines.indices {
            if let original = page.lines.indices.first(where: {
                $0 < index && sameFurnitureImpression(page.lines[$0], page.lines[index])
            }) {
                originals[index] = originals[original] ?? original
                ledger.overprints[pageIndex, default: [:]][originals[index]!, default: []].insert(index)
            }
        }
        let height = page.bounds.height
        func position(_ value: CGFloat) -> CGFloat { (value - page.bounds.minY) / height }

        /// The clear space a margin row keeps from the content it is set apart from.
        func separation(_ line: TextLine) -> CGFloat { max(line.rect.height, height * 0.012) }
        /// Where the top of the candidate band stands, as a share of the sheet. Ordinarily the
        /// top tenth of the paper, which is where a book prints its running head.
        ///
        /// A book printed on a **page image smaller than its sheet** states its own margin
        /// somewhere else, and `typePage` reads where. A Supreme Court slip opinion is typeset on
        /// a page centred on US Letter and inset 156 points on each side, so *Loper Bright*'s text
        /// runs from 0.21 to 0.85 of the sheet and its running head — the outermost row of every
        /// page, set apart from the body by twenty-one points, repeating on page after page —
        /// never reached the top tenth of the paper. All 210 of that book's heads survived,
        /// because none of them was ever a candidate for `resolve` to weigh (#289).
        ///
        /// The foot is left exactly as it was. Its band is already narrower on purpose — a
        /// lower-margin number takes part in the whitespace cuts around an illustrated row, and
        /// widening it changes reading order in *Our Flag* even where the number is furniture —
        /// and this rule has no evidence about that.
        func inBand(_ line: TextLine, top: Bool) -> Bool {
            guard top else { return position(line.rect.midY) <= 0.07 }
            guard let type = typePage(of: page), type.height > 0 else {
                return position(line.rect.midY) >= 0.90
            }
            return (line.rect.midY - type.minY) / type.height >= 0.90
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
                index != lineIndex && !sameFurnitureImpression(other, line) && (top ? other.rect.midY < line.rect.midY : other.rect.midY > line.rect.midY)
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
            guard originals[lineIndex] == nil, !recorded.contains(lineIndex) else { return }
            let line = page.lines[lineIndex]
            let words = words(line)
            recorded.insert(lineIndex)
            ledger.note(lineIndex, onPageAt: pageIndex)
            for copy in ledger.overprints[pageIndex]?[lineIndex] ?? [] { ledger.note(copy, onPageAt: pageIndex) }
            // Bare folios use measured glyph height: fallback extraction estimates
            // fontSize from that height, whereas native extraction reads font attributes.
            let folio = isFolio(words)
            let candidate = Candidate(pageIndex: pageIndex, lineIndex: lineIndex, number: page.number,
                                      isTop: top, position: position(line.rect.midY),
                                      fontSize: folio ? line.rect.height : line.fontSize,
                                      typeSize: line.fontSize,
                                      isFolio: folio, offsets: offsets(words, pageNumber: page.number),
                                      dependsOn: dependsOn)
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

        // A source-painted header band can be taller than the ordinary margin window.
        // Its entire text is one candidate, not an invitation to consume rows below it.
        // Recurrence still proves every row, so a changing project-status row keeps the band.
        if let band = page.headerBackdrop {
            let members = page.lines.indices.filter { band.contains(page.lines[$0].rect) }
            let rest = page.lines.indices.filter { !members.contains($0) }
            if (2...8).contains(members.count), members.allSatisfy({ measurable(page.lines[$0]) }),
               !rest.isEmpty, rest.allSatisfy({ page.lines[$0].rect.maxY < band.minY }),
               let inward = members.map({ page.lines[$0].rect.minY }).min(),
               let bodyTop = rest.map({ page.lines[$0].rect.maxY }).max(),
               inward - bodyTop >= members.map({ separation(page.lines[$0]) }).min()! {
                for index in members {
                    record(index, top: true, dependsOn: members.filter { $0 != index })
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

        /// The row behind a running head, where a book sets its head in two.
        ///
        /// A Supreme Court slip opinion prints `Cite as: 603 U. S. ____ (2024)` over
        /// `Opinion of the Court` two leadings apart, so neither row is stacked on the other and
        /// only the outer one is an outermost row: `recordStack` will not take them as a band,
        /// and every other rule asks `outermost`. 111 of *Loper Bright*'s heads stayed for that
        /// reason after the outer row went (#289).
        ///
        /// So a line is admitted where **everything further out than it is already a candidate**,
        /// it stands in the same band, and it is set apart from the body. One row deep and no
        /// more: the outward set is read against the candidates the outermost-row loop found, so
        /// a third row sees the second and is refused, and nothing in this corpus prints one.
        ///
        /// It is asked half the white an outermost row must keep, because a row behind a head is
        /// bounded by the head above it as well as by the body below, and this page gives it
        /// 9.53 points of a 10.81-point line where its own body lines touch. What settles that it
        /// is furniture is not its margin but its recurrence: `resolve` still removes it only
        /// where its words and its place repeat on neighbouring pages, which is the whole of the
        /// evidence a head behind a head has.
        ///
        /// The **head only**. At the foot this would reach a line standing over a folio, and the
        /// folio-offset signature would then group it across pages although its words differ
        /// page by page: `Caption 1` over `4-1` and `Caption 2` over `4-2` normalize to one
        /// `Caption #(offset=0)`. That is what
        /// `chapterPageFoliosSurviveNearbyFigureTextWithoutEnteringProse` pins, and #289 is a
        /// head in any case.
        func recordSecondRow() {
            let top = true
            let outermostCandidates = recorded
            guard !outermostCandidates.isEmpty else { return }
            for (lineIndex, line) in page.lines.enumerated() where !recorded.contains(lineIndex) {
                guard inBand(line, top: top), measurable(line) else { continue }
                let outward = page.lines.indices.filter { index in
                    let other = page.lines[index]
                    return top ? other.rect.midY > line.rect.midY + line.rect.height * 0.4
                               : other.rect.midY < line.rect.midY - line.rect.height * 0.4
                }
                guard !outward.isEmpty, outward.allSatisfy(outermostCandidates.contains),
                      let gap = inwardGap(lineIndex, top: top),
                      isFolio(words(line)) || gap >= separation(line) * 0.5 else { continue }
                record(lineIndex, top: top)
            }
        }
        recordSecondRow()

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
            // a slide's two-line title stands lower, and the body must not be read as a head. Read
            // against the page image where the sheet carries one, for the reason `inBand` is
            // (#289).
            let inward = blockEdge(stack, top: top)
            let type = typePage(of: page)
            let edge = type.map { $0.height > 0 ? (inward - $0.minY) / $0.height : position(inward) }
                ?? position(inward)
            guard top ? edge >= 0.875 : edge <= 0.125 else { return }
            let ordered = stack.sorted()
            for lineIndex in ordered where !recorded.contains(lineIndex) {
                record(lineIndex, top: top, dependsOn: ordered.filter { $0 != lineIndex })
            }
        }
        recordStack(top: true)
        recordStack(top: false)

        /// A **drop folio**: the page number a book prints at the foot of an opening page, where
        /// the running head that carries it on every other page is suppressed. It repeats on no
        /// three neighboring pages — no two opening pages are neighbors — and it stands lower
        /// than the 7% footer band, so neither the runs nor a slot can reach it, and it arrives
        /// as a paragraph holding nothing but a number (#271).
        ///
        /// What the page states about it is collected here and weighed in `resolve`: a bare
        /// number, alone on its line, standing further out at the foot than any other line, set
        /// apart from the body by its own separation, inside the outer tenth — the same depth the
        /// header band uses, because a folio dropped to the foot may be set lower than a running
        /// foot. The narrow 7% footer band stays as it is: this path removes nothing on position
        /// alone, so it disturbs no whitespace cut around an illustrated row.
        for (lineIndex, line) in page.lines.enumerated()
        where position(line.rect.midY) <= 0.10 && measurable(line)
            && outermost(line, top: false) && isFolio(words(line)) {
            guard let gap = inwardGap(lineIndex, top: false), gap >= separation(line) else { continue }
            for offset in offsets(words(line), pageNumber: page.number) {
                ledger.dropFolios.append(DropFolio(pageIndex: pageIndex, lineIndex: lineIndex, offset: offset))
            }
            ledger.note(lineIndex, onPageAt: pageIndex)
        }
    }

    static func resolve(_ ledger: Ledger) -> Plan {
        var plan = Plan()
        plan.overprints = ledger.overprints
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
        admitDropFolios(&plan, dropFolios: ledger.dropFolios, unique: unique)
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

    /// A book states where each page stands in its own numbering, and the furniture it has
    /// already lost says so page after page: the 9/11 report's running head reads `430 APPENDIX`
    /// on physical page 448, one of 546 pages stating the same offset of -18. On a chapter- or
    /// appendix-opening page that head is suppressed and the number is dropped to the foot
    /// instead, where it repeats on no three neighboring pages — no two opening pages are
    /// neighbors — and so reaches the reader as a paragraph holding nothing but a number (#271).
    ///
    /// The evidence is the document's own numbering, not the shape of the line: a bare number in
    /// the outer foot margin goes only where its value is exactly the folio its page would carry
    /// under an offset the removed furniture establishes, on at least six pages and at least a
    /// quarter of the document's, the same floor the margin slot asks of a place. So a numbered
    /// answer, a table cell or a figure number at the foot of a page stays — it would have to
    /// state this book's own page number to be taken for one — and a book whose furniture states
    /// no offset, or none often enough, keeps every number it prints.
    ///
    /// A stacked band is not admitted, for the reason a slot does not admit one: its rows are
    /// held together by their own separation, and this evidence speaks for one line.
    private static func admitDropFolios(_ plan: inout Plan, dropFolios: [DropFolio],
                                        unique: [Int: [Int: Candidate]]) {
        guard !dropFolios.isEmpty else { return }
        var pages: [Int: Set<Int>] = [:]
        for (pageIndex, lines) in unique {
            for (lineIndex, candidate) in lines where plan.native[pageIndex]?.contains(lineIndex) == true {
                for offset in candidate.offsets { pages[offset, default: []].insert(pageIndex) }
            }
        }
        let floor = max(6, (plan.pageCount + 3) / 4)
        let established = Set(pages.filter { $0.value.count >= floor }.keys)
        guard !established.isEmpty else { return }
        for folio in dropFolios where established.contains(folio.offset)
            && unique[folio.pageIndex]?[folio.lineIndex]?.dependsOn.isEmpty != false {
            plan.native[folio.pageIndex, default: []].insert(folio.lineIndex)
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
        if let band = page.headerBackdrop,
           !kept.contains(where: { band.contains($0.rect) }) {
            page.graphics.removeAll { band.insetBy(dx: -2, dy: -2).contains($0) }
            page.pictures.removeAll { band.insetBy(dx: -2, dy: -2).contains($0) }
        }
        page.lines = kept
        return ConversionWarning(code: .furnitureRemoved, page: page.number,
                                 message: "Repeated header or footer omitted from the reflowed text.")
    }

    private static func sameFurnitureImpression(_ a: TextLine, _ b: TextLine) -> Bool {
        a.text == b.text && abs(a.fontSize - b.fontSize) <= 0.1
            && abs(a.rect.minX - b.rect.minX) <= 0.5 && abs(a.rect.maxX - b.rect.maxX) <= 0.5
            && abs(a.rect.minY - b.rect.minY) <= 0.5 && abs(a.rect.maxY - b.rect.maxY) <= 0.5
    }

    /// The whitespace-separated, lowercased words of a line.
    private static func words(_ line: TextLine) -> [String] {
        line.text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every physical-page offset a line's boundary numbers imply on the page it stands on.
    ///
    /// Only the first and last word can be a page number; internal digits (9/11, a chapter
    /// number, a date) stay significant, exactly as the group signatures treat them. A
    /// `chapter-page` word states the offset of its page half. This is the same reading the
    /// `#(offset=)` signatures take, kept as a value so a candidate carries what it states.
    private static func offsets(_ words: [String], pageNumber: Int) -> Set<Int> {
        guard !words.isEmpty else { return [] }
        var result: Set<Int> = []
        for index in Set([0, words.count - 1]) {
            var values: [Int] = []
            if let value = Int(words[index]), value >= 0 { values.append(value) }
            let parts = words[index].split(separator: "-", omittingEmptySubsequences: false)
            if parts.count == 2, !parts[0].isEmpty, let value = Int(parts[1]), value >= 0 {
                values.append(value)
            }
            for value in values {
                let (offset, overflow) = value.subtractingReportingOverflow(pageNumber)
                if !overflow { result.insert(offset) }
            }
        }
        return result
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
