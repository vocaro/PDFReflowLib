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
        hole.takenBackSpaces = []
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

    /// The offsets in `extracted` where a show the line can hold in only one place draws a
    /// boundary PDFKit spells closed.
    ///
    /// The segmented walk reaches these two lines of *Beginning and Intermediate Algebra* from
    /// neither end, and each fails for its own reason (#260).
    ///
    /// Page 224 prints `1· 6and 2· 3` and its source reads `16and23`: seven characters against an
    /// `anchorLength` of twelve. `resynchronize` runs out of source before it can match twelve, so
    /// it returns nil at the first show the reader could not decode and the walk ends having
    /// applied nothing, although the boundary sits between two characters PDFKit also read.
    ///
    /// Page 223 is the walk's own opening, which is the one alignment taken on faith. PDFKit
    /// splits the printed row at a wide gap, so the show `66` drawn at x 251.04 has its first
    /// digit on the row above and this line holds `6and− 1, split the middle term`. The walk opens
    /// at source 0 against extracted 0, where the two `6`s match by coincidence, disagrees at the
    /// next character, resynchronizes to source 2 — which is the boundary — and drops it, because
    /// a boundary at a segment's opening stands against a disagreeing region's edge (#139 item 1).
    /// The alignment that is right, source 1 against extracted 0, is the one no test is applied
    /// to.
    ///
    /// Neither is answered by weakening the anchor, which is what #119 and #120 raised it for.
    /// Both are answered by not needing one: where a show's own text stands in exactly one place
    /// in PDFKit's reading of the line, there is nothing to align, because the characters are only
    /// there. Uniqueness is stronger evidence than any run of matching characters, and it is read
    /// per show rather than per line, so a line the walk owns keeps everything the walk gave it
    /// and gains only what it could not reach.
    ///
    /// PDFKit's own spaces are stepped over, as everywhere else here, so a show is placed against
    /// the marks of the line and not its spacing. A show of one mark is not placed: one character
    /// standing once in a line is a coincidence the line is too short to rule out.
    static func uniquelyPlacedInsertions(in extracted: [UInt16], spans: [(start: Int, text: [UInt16])],
                                         boundaries: Set<Int>) -> [Int] {
        let marks = extracted.indices.filter { !whitespace(extracted[$0]) }
        guard !marks.isEmpty else { return [] }
        var inserted: [Int] = []
        for span in spans {
            // A show carrying whitespace of its own would not line up mark for mark; the reading
            // of such a show is PDFKit's own spacing, which this rule has nothing to add to.
            guard span.text.count >= 2, span.text.count <= marks.count,
                  !span.text.contains(where: whitespace),
                  boundaries.contains(where: { $0 >= span.start && $0 < span.start + span.text.count })
            else { continue }
            var place: Int?
            for k in 0...(marks.count - span.text.count) {
                guard span.text.indices.allSatisfy({ extracted[marks[k + $0]] == span.text[$0] }) else { continue }
                if place != nil { place = nil; break }
                place = k
            }
            guard let k = place else { continue }
            for boundary in boundaries where boundary >= span.start && boundary < span.start + span.text.count {
                let offset = marks[k + boundary - span.start]
                guard offset > 0, !whitespace(extracted[offset - 1]) else { continue }
                inserted.append(offset)
            }
        }
        return inserted
    }

    /// The offsets in `extracted` where PDFKit spells a space across a boundary the page closes
    /// (#274, #316), each the one space between the two characters the closure separates. A
    /// closure is a character offset in `source`: the second of two marks the page draws against
    /// each other (#274), or a space glyph the page takes back (#316), every one of which between
    /// the two marks must be one.
    ///
    /// The segmented walk cannot own these lines, and the reason is the shape of the defect. A
    /// page sets a table row by carrying the text cursor from cell to cell with runs of space
    /// glyphs, and PDFKit reports one space for a run, so on such a row the *source* draws the
    /// whitespace the extraction does not. That walk skips only the extraction's own spaces, so it
    /// reads each run as a disagreement, and FAA page 416's row resynchronizes on nothing: the
    /// longest anchor left between `MH     Under 50         25` and `MH Under 50 2 5` is the nine
    /// characters of `Under 50 `, against an anchor length of twelve.
    ///
    /// So a removal is owned blind to whitespace on both sides: every non-blank character PDFKit
    /// read must be the next non-blank character the shows draw, in order, with nothing left over
    /// on PDFKit's side, and the closure itself must have exactly one space at it in the
    /// extraction. The shows may draw more than the line holds only where PDFKit split one printed
    /// row into lines that each hold part of a show — the Hebrew Shakespeare study's notes, whose
    /// number and text are one show and two PDFKit lines — and then the line's marks must stand in
    /// exactly one place among the shows' (#316). A ligature counts as the letters it joins, because
    /// PDFKit reads the study's `ﬁ` as `fi` (#316). That is stricter than the segmented walk, not
    /// looser — one character of the line the shows cannot account for supplies no removal at all,
    /// where the segmented walk would still apply what its other segments yielded. It also reaches
    /// no insertion: insertions keep the walk they already had.
    static func closedSpaces(in extracted: [UInt16], source: [UInt16], closures: Set<Int>) -> [Int] {
        guard !closures.isEmpty else { return [] }
        let sourceMarks = foldedMarks(source), extractedMarks = foldedMarks(extracted)
        guard !extractedMarks.isEmpty, extractedMarks.count <= sourceMarks.count else { return [] }
        // Where PDFKit's marks stand among the shows' marks: all of them, or the one run of them
        // they fill exactly, where PDFKit split one printed row into lines that each hold part of a
        // show (#316, the shape #139 answered for insertions).
        var start: Int?
        for k in 0...(sourceMarks.count - extractedMarks.count)
            where extractedMarks.indices.allSatisfy({ sourceMarks[k + $0].unit == extractedMarks[$0].unit }) {
            guard start == nil else { return [] }
            start = k
        }
        guard let start else { return [] }
        var removals: [Int] = []
        for rank in extractedMarks.indices.dropFirst() {
            // The closure separates two characters the page draws with nothing between them (#274),
            // or with nothing but space glyphs whose advance the page takes back, each of which is
            // itself a closure (#316).
            let before = sourceMarks[start + rank - 1].offset, after = sourceMarks[start + rank].offset
            guard after == before + 1 && closures.contains(after)
                || after > before + 1 && (before + 1..<after).allSatisfy(closures.contains) else { continue }
            let left = extractedMarks[rank - 1].offset, right = extractedMarks[rank].offset
            guard right == left + 2, extracted[left + 1] == 32 else { continue }
            removals.append(left + 1)
        }
        return removals
    }

    /// The non-blank UTF-16 units of a reading, each with the offset of the character it came from,
    /// and a Latin ligature standing for the letters it joins: PDFKit hands back the `ﬁ` a font's map
    /// names as `fi` on one line and keeps it on another (#316).
    static func foldedMarks(_ text: [UInt16]) -> [(unit: UInt16, offset: Int)] {
        var marks: [(unit: UInt16, offset: Int)] = []
        for (offset, unit) in text.enumerated() where !whitespace(unit) {
            if let letters = ligatureLetters[unit] {
                marks += letters.utf16.map { ($0, offset) }
            } else {
                marks.append((unit, offset))
            }
        }
        return marks
    }

    private static let ligatureLetters: [UInt16: String] = [
        0xFB00: "ff", 0xFB01: "fi", 0xFB02: "fl", 0xFB03: "ffi", 0xFB04: "ffl", 0xFB06: "st",
    ]

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
