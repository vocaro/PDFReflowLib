import Foundation

/// Partial-line ownership for the spacing reader (#139 item 1, specified in #225; extended by #258
/// to the shows a line holds beside ones it does not).
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
    /// The shows a PDFKit line's evidence is: the ones whose origin it holds (`heldShows`), and
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
    static func spanningShows(_ evidence: [Evidence], bounds: CGRect, allBounds: [CGRect]) -> [Evidence] {
        let tolerance = AnchorMatcher.tolerance
        let spanning = evidence.filter { show in
            guard !AnchorMatcher.contains(bounds, show.origin), let end = show.end,
                  show.origin.y >= bounds.minY - tolerance, show.origin.y <= bounds.maxY + tolerance,
                  show.origin.x <= bounds.maxX + tolerance, end >= bounds.minX - tolerance else { return false }
            return allBounds.filter { AnchorMatcher.contains($0, show.origin) }.count == 1
        }
        return heldShows(evidence, bounds: bounds, allBounds: allBounds) + spanning
    }

    /// The shows whose origin this line's rectangle holds, with each one another line's rectangle
    /// holds too reduced to a hole: its place on the line, and nothing read from it.
    ///
    /// `anchoredShows` refuses the whole line instead, and a book that sets raised baselines has
    /// lines it refuses on every one of them. PDFKit's rectangle for a line carrying a superscript,
    /// an exponent or a stacked fraction grows to the height of what it carries, so it overlaps the
    /// rectangles of the rows drawn inside and beside it, and a show on any of those baselines then
    /// lies in two rectangles at once. Wallace page 281 reads `Convert 8cubic feet to yd3 Write
    /// 8ft3 as fraction, put it over 1` as one rectangle 69 points tall, holding the origins of
    /// eight shows that belong to the two fraction rows inside it; the line's own twelve shows,
    /// which spell its text exactly and place the `8|cubic` font change the rules already admit,
    /// supplied nothing at all (#258).
    ///
    /// A hole is what #120 already makes of a show the reader cannot decode: the segmented walk
    /// resynchronizes across it, and the show after it has no predecessor, so no boundary is ever
    /// computed against a character this line may not have drawn. The line therefore applies the
    /// evidence it unambiguously holds and reads nothing across the rest, which is the same
    /// direction #139 item 1 relaxed in and admits no gap #119's thresholds had not already
    /// accepted.
    static func heldShows(_ evidence: [Evidence], bounds: CGRect, allBounds: [CGRect]) -> [Evidence] {
        evidence.filter { AnchorMatcher.contains(bounds, $0.origin) }.map { show in
            allBounds.filter { AnchorMatcher.contains($0, show.origin) }.count == 1 ? show : hole(show)
        }
    }

    /// A show reduced to its place on the line: the origin that keeps its neighbors apart in the
    /// left-to-right walk, with no text, no measured end and no boundary of its own.
    static func hole(_ show: Evidence) -> Evidence {
        var hole = show
        hole.text = nil
        hole.unicode = nil
        hole.end = nil
        hole.spaceWidth = nil
        hole.smallGaps = []
        hole.wordSpaces = []
        hole.sentenceSpaces = []
        hole.sentenceCandidates = [:]
        return hole
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

    /// The offsets in `extracted` where PDFKit spells a space across a boundary the page closes
    /// (#274), each the one space between the two characters the closure separates.
    ///
    /// The segmented walk cannot own these lines, and the reason is the shape of the defect. A
    /// page sets a table row by carrying the text cursor from cell to cell with runs of space
    /// glyphs, and PDFKit reports one space for a run, so on such a row the *source* draws the
    /// whitespace the extraction does not. That walk skips only the extraction's own spaces, so it
    /// reads each run as a disagreement, and FAA page 416's row resynchronizes on nothing: the
    /// longest anchor left between `MH     Under 50         25` and `MH Under 50 2 5` is the nine
    /// characters of `Under 50 `, against an anchor length of twelve.
    ///
    /// So a removal is owned whole-line and blind to whitespace on both sides: every non-blank
    /// character the shows draw must be the next non-blank character PDFKit read, in order, with
    /// nothing left over on either side, and the closure itself must have no whitespace beside it
    /// in the source and exactly one space at it in the extraction. That is stricter than the
    /// segmented walk, not looser — one character of the line the shows cannot account for
    /// supplies no removal at all, where the segmented walk would still apply what its other
    /// segments yielded. It also reaches no insertion: insertions keep the walk they already had.
    static func closedSpaces(in extracted: [UInt16], source: [UInt16], closures: Set<Int>) -> [Int] {
        guard !closures.isEmpty else { return [] }
        let sourceMarks = source.indices.filter { !whitespace(source[$0]) }
        let extractedMarks = extracted.indices.filter { !whitespace(extracted[$0]) }
        guard sourceMarks.count == extractedMarks.count, !sourceMarks.isEmpty,
              zip(sourceMarks, extractedMarks).allSatisfy({ source[$0] == extracted[$1] }) else { return [] }
        var removals: [Int] = []
        for (rank, offset) in sourceMarks.enumerated() where closures.contains(offset) {
            // The closure separates two characters the page draws with nothing between them.
            guard rank > 0, sourceMarks[rank - 1] == offset - 1 else { continue }
            let before = extractedMarks[rank - 1], after = extractedMarks[rank]
            guard after == before + 2, extracted[before + 1] == 32 else { continue }
            removals.append(before + 1)
        }
        return removals
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
