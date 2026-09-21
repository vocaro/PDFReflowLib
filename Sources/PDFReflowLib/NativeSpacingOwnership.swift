import Foundation

/// Partial-line ownership for the spacing reader (#139 item 1, specified in #225).
///
/// `NativeSpacingReader.wholeLineInsertions` owns a PDFKit line as a whole or not at all: it walks
/// the shows' text against PDFKit's, stops at the first non-whitespace disagreement, and requires
/// both walks to be exhausted, so one unaccounted character discards every boundary already
/// computed. That is what keeps the 9/11 appendix's `(a.k.a.` lines, its prose lines carrying a
/// character the shows cannot decode, and Wallace's digit-then-word lines beside a radical fused,
/// although the rules had already admitted their boundaries.
///
/// The walk here resynchronizes instead. The line is the maximal segments on which the shows and
/// PDFKit agree, separated by the regions where they do not; a boundary is applied only where the
/// characters on both sides of it matched within one segment, so a boundary inside a disagreeing
/// region, or against its edge, is dropped. Nothing else changes: no threshold moves, and no
/// boundary the whole-line walk would have applied is withheld. This is the safe direction to
/// relax against #119's hard constraint, because it admits only evidence the thresholds had
/// already accepted on a line the shows happened to own entirely.
extension NativeSpacingReader {
    /// The shows a PDFKit line's evidence is: the ones whose origin it owns (`anchoredShows`), and
    /// the ones another line's rectangle holds the origin of whose glyphs run on through this one.
    /// PDFKit splits one printed row at a wide gap, so a row drawn as a single show becomes two
    /// lines that each hold part of its text: the 9/11 appendix's `Ali Abdul Aziz Ali` beside
    /// `(a.k.a.Ammar al Baluchi) Pakistani;…` on page 452, and the FAA chart rows of #139. Each
    /// line then walks the same source text and `segmentedInsertions` gives it only the boundaries
    /// inside its own half, so the row is repaired once, not twice.
    ///
    /// A show reaches a line when its baseline sits inside that line's rectangle and its glyph
    /// advances (`end`, which only a fully measured show has) cross the line's own span. Its origin
    /// must still lie in exactly one line's rectangle, so nothing ambiguous is admitted.
    static func spanningShows(_ evidence: [Evidence], bounds: CGRect, allBounds: [CGRect]) -> [Evidence]? {
        guard let anchored = anchoredShows(evidence, bounds: bounds, allBounds: allBounds) else { return nil }
        let tolerance = AnchorMatcher.tolerance
        let spanning = evidence.filter { show in
            guard !AnchorMatcher.contains(bounds, show.origin), let end = show.end,
                  show.origin.y >= bounds.minY - tolerance, show.origin.y <= bounds.maxY + tolerance,
                  show.origin.x <= bounds.maxX + tolerance, end >= bounds.minX - tolerance else { return false }
            return allBounds.filter { AnchorMatcher.contains($0, show.origin) }.count == 1
        }
        return anchored + spanning
    }

    /// Non-whitespace characters that must agree before a disagreement counts as resolved. Shorter
    /// runs recur by chance inside ordinary prose, and a segment entered on one is not a segment.
    ///
    /// Eight was not enough, and the 9/11 appendix shows why: `Abu Bara al Yemeni (a.k.a.Abu al
    /// Bara al Ta’izi,…` is one row, and the walk that should skip 19 source characters to reach
    /// `(a.k.a.A` finds `Bara al ` after 16 instead, in the wrong half of the row, and resumes
    /// there. The two readings diverge at the ninth character, so twelve tells them apart (#120).
    static let anchorLength = 12
    /// How far either walk may skip to find that anchor, and how many times one line may resync.
    /// A line needing more than this is left to whatever its earlier segments already yielded.
    static let maximumResynchronization = 64
    static let maximumSegments = 64

    /// The offsets in `extracted` where the source draws a boundary that PDFKit spells closed,
    /// taking each maximal agreeing segment on its own. `extracted` keeps its own spaces: a
    /// boundary already spaced there inserts nothing.
    static func segmentedInsertions(in extracted: [UInt16], source: [UInt16], boundaries: Set<Int>) -> [Int]? {
        var inserted: [Int] = []
        var i = 0, j = 0, matched = 0, segments = 0
        while i < source.count, j < extracted.count {
            if source[i] == extracted[j] {
                // A boundary applies only between two characters of one segment: `matched` counts
                // the characters of the segment already walked, so zero means this one opens it.
                if matched > 0, boundaries.contains(i), j > 0, !whitespace(extracted[j - 1]) { inserted.append(j) }
                i += 1; j += 1; matched += 1
                continue
            }
            if whitespace(extracted[j]) { j += 1; continue }
            segments += 1
            guard segments <= maximumSegments,
                  let (next, nextExtracted) = resynchronize(source: source, at: i, extracted: extracted, at: j) else { break }
            i = next; j = nextExtracted; matched = 0
        }
        return inserted.isEmpty ? nil : inserted
    }

    /// Where the two walks agree again after a disagreement at `i` and `j`: the positions reached
    /// by the fewest skipped characters in all, and among those the fewest skipped in the source,
    /// from which `anchorLength` characters match with PDFKit's own spaces aside. Nil when no such
    /// anchor is within reach, which ends the line: what the segments before it yielded stands.
    static func resynchronize(source: [UInt16], at i: Int, extracted: [UInt16], at j: Int) -> (Int, Int)? {
        func anchors(_ start: Int, _ startExtracted: Int) -> Bool {
            var x = start, y = startExtracted, matched = 0
            while x < source.count, y < extracted.count, matched < anchorLength {
                if source[x] == extracted[y] { x += 1; y += 1; matched += 1; continue }
                if whitespace(extracted[y]) { y += 1; continue }
                return false
            }
            return matched == anchorLength
        }
        for total in 1...maximumResynchronization {
            for skipped in 0...total where i + skipped <= source.count && j + total - skipped <= extracted.count {
                if anchors(i + skipped, j + total - skipped) { return (i + skipped, j + total - skipped) }
            }
        }
        return nil
    }
}
