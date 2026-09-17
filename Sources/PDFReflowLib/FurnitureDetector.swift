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
        /// The outermost-row lines a second-row candidate sits beneath; it is removed only
        /// when all of them are.
        var dependsOn: [Int] = []
    }

    /// A margin candidate whose first or last word is a page number. `offset` is that number
    /// less the physical page, the quantity a folio keeps constant while its text changes.
    fileprivate struct FolioCandidate {
        var candidate: Candidate
        var edge: String
        /// The numeral system: two folios agree only when written the same way.
        var kind: String
        var offset: Int
        /// The line's own type size. `Candidate.fontSize` substitutes measured glyph height for
        /// a bare folio, which cannot be compared with a head line's font attribute.
        var typeSize: CGFloat
        /// The line is nothing but the folio.
        var bare: Bool
        /// Every other line of the page sharing this line's row.
        var rowMates: [Int]
    }

    /// Document-wide evidence without the pages themselves.
    struct Ledger {
        fileprivate var groups: [String: [Candidate]] = [:]
        fileprivate var folios: [FolioCandidate] = []
        fileprivate var syntheticOccurrences: [String: Int] = [:]
        fileprivate var pageCount = 0
        init() {}
    }

    /// Resolved removals. Applying them to a page consults only that page.
    struct Plan {
        fileprivate var native: [Int: Set<Int>] = [:]
        fileprivate var dependencies: [Int: [Int: [Int]]] = [:]
        /// Removed lines that are nothing but a page number, by page.
        fileprivate var bareFolios: [Int: Set<Int>] = [:]
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
        let height = page.bounds.height
        func position(_ line: TextLine) -> CGFloat { (line.rect.midY - page.bounds.minY) / height }
        // The top band is the outer fifth of the page: a slip opinion's running head sits at
        // 82–85% under a deep head margin, whereas report headers sit above 90%. Retain the
        // narrower footer band: lower-margin numbers can participate in whitespace cuts
        // around illustrated rows. Widening that band changes reading order in Our Flag
        // even when the removed number is furniture.
        func inBand(_ line: TextLine, top: Bool) -> Bool {
            top ? position(line) >= 0.80 : position(line) <= 0.07
        }
        /// The outermost row on the given edge among `lines`.
        func outermost(_ lineIndex: Int, top: Bool, among lines: [Int]) -> Bool {
            let line = page.lines[lineIndex]
            return !lines.contains { other in
                top ? page.lines[other].rect.midY > line.rect.midY + line.rect.height * 0.4
                    : page.lines[other].rect.midY < line.rect.midY - line.rect.height * 0.4
            }
        }
        var recorded: Set<Int> = []
        /// Records a short line separated from inward content by at least `separation`.
        func record(_ lineIndex: Int, top: Bool, separation: CGFloat, dependsOn: [Int] = []) {
            let line = page.lines[lineIndex]
            guard line.rect.isFinite, line.fontSize > 0, line.fontSize.isFinite else { return }
            let words = line.text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty, line.text.count < 100 else { return }
            // The line must be separated from inward content, not just happen to be
            // the first/last line of a paragraph near the page edge.
            let inward = page.lines.enumerated().filter { index, other in
                index != lineIndex && (top ? other.rect.midY < line.rect.midY : other.rect.midY > line.rect.midY)
            }.map { top ? line.rect.minY - $0.element.rect.maxY : $0.element.rect.minY - line.rect.maxY }
            let folioParts = words.count == 1 ? words[0].split(separator: "-", omittingEmptySubsequences: false) : []
            // A bare page number, chapter-prefixed (`5-17`) or lettered for an appendix, glossary or
            // index (`c-2`, #90): the prefix names the part and the last number counts its pages.
            let isFolio = (1...2).contains(folioParts.count) && folioParts.last.map({ Int($0) != nil }) == true
                && (folioParts.count == 1 || Int(folioParts[0]) != nil || isPartLetter(folioParts[0]))
            // A bare folio has its own numeric/position evidence. Nearby figure labels
            // must not stop a chapter-page number from being recognized, and neither must
            // their absence: a blank page whose only text is its folio (FAA `A-8`, `G-36`, the
            // last page of a lettered part) still numbers its page (#97).
            guard isFolio || inward.min().map({ $0 >= separation }) == true else { return }
            recorded.insert(lineIndex)
            // Bare folios use measured glyph height: fallback extraction estimates
            // fontSize from that height, whereas native extraction reads font attributes.
            let candidate = Candidate(pageIndex: pageIndex, lineIndex: lineIndex, number: page.number,
                                      position: position(line), fontSize: isFolio ? line.rect.height : line.fontSize,
                                      isFolio: isFolio, dependsOn: dependsOn)
            let edge = top ? "top:" : "bottom:"
            ledger.groups[edge + words.joined(separator: " "), default: []].append(candidate)
            // A boundary page number is evidence of its own: it tracks the physical page while
            // the rest of the line changes. Record every such reading; `resolve` decides.
            let mates = page.lines.indices.filter { other in
                other != lineIndex && abs(page.lines[other].rect.midY - line.rect.midY)
                    <= max(line.rect.height, page.lines[other].rect.height) * 0.4
            }
            // A numbered figure or table label also counts up with the pages it sits on. Its
            // number names the object, not the page, so it supplies no folio evidence.
            let caption = ["figure", "fig.", "table", "plate", "chart", "exhibit", "map", "box"]
                .contains(words[0])
            for index in Set([0, words.count - 1]) where !caption {
                guard let folio = folioValue(words[index]) else { continue }
                let (offset, overflow) = folio.value.subtractingReportingOverflow(page.number)
                guard !overflow else { continue }
                ledger.folios.append(FolioCandidate(candidate: candidate, edge: edge, kind: folio.kind,
                                                    offset: offset, typeSize: line.fontSize,
                                                    bare: words.count == 1, rowMates: mates))
            }
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
        let all = Array(page.lines.indices)
        for lineIndex in all {
            let line = page.lines[lineIndex]
            let top = position(line) >= 0.5
            // Only the outermost row is eligible; a caption or paragraph above a
            // footer must not be removed merely because it also repeats.
            guard inBand(line, top: top), outermost(lineIndex, top: top, among: all) else { continue }
            record(lineIndex, top: top, separation: max(line.rect.height, height * 0.012))
        }
        // A two-row running head: beneath an outermost top row made only of candidates, the
        // next row inward is also eligible when it stays within three of its line heights
        // of that row and keeps at least half a line height from the body. It is removed
        // only together with every line of the row above it.
        let outer = all.filter { inBand(page.lines[$0], top: true) && outermost($0, top: true, among: all) }
        guard !outer.isEmpty, outer.allSatisfy(recorded.contains),
              let outerBottom = outer.map({ page.lines[$0].rect.minY }).min() else { return }
        let rest = all.filter { !outer.contains($0) }
        for lineIndex in rest {
            let line = page.lines[lineIndex]
            guard inBand(line, top: true), line.rect.maxY <= outerBottom,
                  line.rect.maxY >= outerBottom - line.rect.height * 3,
                  outermost(lineIndex, top: true, among: rest) else { continue }
            record(lineIndex, top: true, separation: max(line.rect.height * 0.5, height * 0.006), dependsOn: outer)
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
                for candidate in run {
                    plan.native[candidate.pageIndex, default: []].insert(candidate.lineIndex)
                    if candidate.isFolio { plan.bareFolios[candidate.pageIndex, default: []].insert(candidate.lineIndex) }
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
        resolveFolios(ledger, into: &plan)
        return plan
    }

    /// A margin line whose boundary page number tracks the physical page is a running head even
    /// where its text changes from page to page (`554 NOTES TO CHAPTERS 9-10` on an isolated
    /// note page) and even where the head alternates over too few pages for a text run (a slip
    /// opinion's four-page concurrence). The evidence is an offset run: three or more nearby
    /// pages whose margin folios on one edge share a numeral system, the same offset from the
    /// physical page, the same height in the band and the same type size. Nothing but an
    /// already-recorded margin candidate can enter such a run, so this only decides candidates
    /// the separation, band and outermost-row rules have already admitted.
    ///
    /// A line that is nothing but a folio is never removed on this evidence alone: a chapter
    /// opening's lone page number is not a running head. One sharing its row with head text
    /// that is removed goes with that row, so a `folio + title` row does not lose half of itself.
    private static func resolveFolios(_ ledger: Ledger, into plan: inout Plan) {
        var groups: [String: [FolioCandidate]] = [:]
        for folio in ledger.folios {
            groups[folio.edge + folio.kind + ":\(folio.offset)", default: []].append(folio)
        }
        var established: [FolioCandidate] = []
        for group in groups.values {
            let ordered = group.sorted { $0.candidate.number < $1.candidate.number }
            var run: [FolioCandidate] = []
            func finish() {
                // Alternating heads put one page between two occurrences, so a run of three
                // means three pages, not three lines on one page.
                if Set(run.map(\.candidate.number)).count >= 3 { established += run }
            }
            for folio in ordered {
                if let first = run.first, let last = run.last {
                    let distance = folio.candidate.number - last.candidate.number
                    if !(0...2).contains(distance)
                        || abs(folio.candidate.position - first.candidate.position) > 0.04
                        || abs(folio.typeSize - first.typeSize) > max(0.5, first.typeSize * 0.1) {
                        finish()
                        run.removeAll(keepingCapacity: true)
                    }
                }
                run.append(folio)
            }
            finish()
        }
        for folio in established where !folio.bare {
            plan.native[folio.candidate.pageIndex, default: []].insert(folio.candidate.lineIndex)
            if !folio.candidate.dependsOn.isEmpty {
                plan.dependencies[folio.candidate.pageIndex, default: [:]][folio.candidate.lineIndex]
                    = folio.candidate.dependsOn
            }
        }
        for folio in established where folio.bare && !folio.rowMates.isEmpty {
            let removed = plan.native[folio.candidate.pageIndex] ?? []
            guard folio.rowMates.allSatisfy(removed.contains) else { continue }
            plan.native[folio.candidate.pageIndex, default: []].insert(folio.candidate.lineIndex)
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
            guard var removed = plan.native[pageIndex], !removed.isEmpty else { return nil }
            // A second header row goes only with the whole row above it.
            for (lineIndex, outer) in plan.dependencies[pageIndex] ?? [:]
            where !outer.allSatisfy(removed.contains) {
                removed.remove(lineIndex)
            }
            guard !removed.isEmpty else { return nil }
            kept = page.lines.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
            // A page is not emptied by furniture removal, except a blank page that carries nothing
            // but its folio (FAA `A-8` and `G-36`, the blank last pages of appendix A and the
            // glossary; #97): its page boundary survives without text.
            guard !kept.isEmpty || removed.isSubset(of: plan.bareFolios[pageIndex] ?? []) else { return nil }
        }
        page.lines = kept
        return ConversionWarning(code: .furnitureRemoved, page: page.number,
                                 message: "Repeated header or footer omitted from the reflowed text.")
    }

    /// A page number at a margin line's boundary: Arabic (`554`), chapter-prefixed (`5-3`, whose
    /// second part numbers the page inside its chapter) or a Roman numeral (`xiv`). The word is
    /// already lowercased. A single letter is not accepted: an initial is not a folio.
    static func folioValue(_ word: String) -> (kind: String, value: Int)? {
        if let value = Int(word), value >= 0, value <= 100_000 { return ("arabic", value) }
        let parts = word.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, let chapter = Int(parts[0]), let value = Int(parts[1]),
           chapter >= 0, value >= 0, value <= 100_000 {
            return ("chapter-\(chapter)", value)
        }
        // A lettered part's page (`c-2`, FAA appendix C), numbered like a chapter's (#90).
        if parts.count == 2, isPartLetter(parts[0]), let value = Int(parts[1]), value >= 0, value <= 100_000 {
            return ("part-\(parts[0])", value)
        }
        guard word.count >= 2, let value = romanValue(word) else { return nil }
        return ("roman", value)
    }

    /// One letter naming an appendix, glossary or index in a lettered page number (`c` in `c-2`).
    private static func isPartLetter(_ prefix: Substring) -> Bool {
        prefix.count == 1 && prefix.first!.isLetter && prefix.first!.isASCII
    }

    /// A Roman numeral in its one canonical spelling, bounded by the range front matter uses.
    /// Round-tripping the value rejects words that merely read as numerals (`did`, `civil`).
    private static func romanValue(_ word: String) -> Int? {
        let digits: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        var total = 0
        var highest = 0
        for character in word.reversed() {
            guard let value = digits[character] else { return nil }
            total += value < highest ? -value : value
            highest = max(highest, value)
        }
        guard (1...400).contains(total), romanText(total) == word else { return nil }
        return total
    }

    private static func romanText(_ value: Int) -> String {
        let table: [(Int, String)] = [(400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"),
                                      (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var remaining = value
        var text = ""
        for (weight, symbol) in table {
            while remaining >= weight {
                text += symbol
                remaining -= weight
            }
        }
        return text
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
