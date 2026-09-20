import Foundation
import CoreGraphics

enum LayoutReconstructor {
    static func vocabulary(in pages: [PageContent]) -> Set<String> {
        var result: Set<String> = []
        for page in pages { addVocabulary(of: page, to: &result) }
        return result
    }

    /// Hyphen repair consults every page's words; accumulating them per page lets extraction
    /// release the page itself. `skippingLines` withholds the page's margin candidates, whose
    /// words count only once the furniture plan says the reader keeps them (#184).
    static func addVocabulary(of page: PageContent, skippingLines skipped: Set<Int> = [],
                              to vocabulary: inout Set<String>) {
        for (index, line) in page.lines.enumerated() where !skipped.contains(index) {
            vocabulary.formUnion(words(of: line))
        }
    }

    /// One line's vocabulary words.
    static func words(of line: TextLine) -> [String] {
        line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
    }

    static func stripFurniture(_ pages: inout [PageContent]) -> [ConversionWarning] {
        FurnitureDetector.strip(&pages)
    }

    /// A short rule between a compact mathematical term above it and a term starting directly
    /// beneath it is a fraction bar, whose numerator and denominator belong in one crop, not an
    /// underline (#36, ported from the coordination branch, #229). Label underlines have worded
    /// prose above them. PDFKit can merge a denominator with the annotation or the next
    /// numerator beside it, so terms are matched by extent.
    static func isFractionBar(_ rule: CGRect, in lines: [TextLine], body: CGFloat) -> Bool {
        guard isThinRule(rule) else { return false }
        let numerator = lines.contains { line in
            !line.monospaced && line.text.count <= 40
                && line.text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil
                && line.rect.maxY > rule.maxY && line.rect.minY <= rule.maxY + body * 1.2
                && line.rect.maxX > rule.minX && line.rect.minX < rule.maxX
        }
        return numerator && lines.contains { line in
            !line.monospaced && line.text.count <= 40
                && line.rect.minY < rule.minY && line.rect.maxY >= rule.minY - body * 1.2
                && line.rect.minX >= rule.minX - body * 0.5 && line.rect.minX <= rule.maxX
                && line.rect.width >= rule.width * 0.15
        }
    }

    /// The text line a thin rule underlines: the rule lies within the line's horizontal extent
    /// and at or just below its baseline region, not up in the ascenders of the line beneath
    /// (#36, ported from the coordination branch, #229).
    static func underlinedLine(_ rule: CGRect, in lines: [TextLine]) -> TextLine? {
        guard isThinRule(rule), !isFractionBar(rule, in: lines, body: max(4, bodySize(lines))) else { return nil }
        return lines.filter { line in
            rule.minX >= line.rect.minX - 3 && rule.maxX <= line.rect.maxX + 3
                && rule.midY >= line.rect.minY - 3 && rule.midY <= line.rect.minY + line.rect.height * 0.5
        }.min { $0.rect.width < $1.rect.width }
    }

    /// A band across the page's full measure, flush against its top or bottom edge: the page's own
    /// furniture — a footer or header background — rather than a figure that owns the text near it.
    ///
    /// Dietary Guidelines page 2 paints such a band from the foot of the page up to y=80.12 and
    /// prints its four notes from y=77.49 to y=85.45. A figure would have a claim on text that
    /// overlaps it; this band has none, and growing to swallow the lines it grazed took two of the
    /// four notes out of the book (#246). Every other kind of region keeps the whole-line growth
    /// of #36, including a fraction bar's terms, whose middles lie outside their seed by
    /// construction.
    static func isEdgeBand(_ seed: CGRect, bounds: CGRect) -> Bool {
        seed.width >= bounds.width * 0.9
            && (seed.minY <= bounds.minY + 1 || seed.maxY >= bounds.maxY - 1)
    }

    /// Whether a finished crop takes a line out of the reflowed text. A crop's edge grazes the
    /// rectangle of the line beyond it without covering its glyphs, so a crop takes the lines whose
    /// middle it holds (#169, #246).
    static func takes(_ crop: CGRect, _ line: TextLine) -> Bool {
        crop.intersects(line.rect) && crop.minY <= line.rect.midY && line.rect.midY <= crop.maxY
    }

    /// Whether a seed region captures a text line. Tall PDFKit line rectangles include leading,
    /// so a thin rule touches the rectangles of the lines above and below without crossing
    /// their glyphs; it captures only text it actually strikes through (#36).
    private static func captures(_ seed: CGRect, _ line: TextLine) -> Bool {
        guard seed.intersects(line.rect) else { return false }
        guard isThinRule(seed) else {
            return takes(seed, line)
        }
        let core = line.rect.insetBy(dx: 0, dy: line.rect.height * 0.25)
        return seed.midY >= core.minY && seed.midY <= core.maxY
    }

    /// Pieces of one visual row (PDFKit splits rows at wide gaps; superscripts are separate lines).
    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.5
    }

    private struct Region {
        var seed: CGRect
        var bounds: CGRect
        /// The ink a crop must keep: a thin rule's one-point stroke, otherwise the whole seed.
        var core: CGRect {
            isThinRule(seed) ? CGRect(x: seed.minX, y: seed.midY - 0.5, width: seed.width, height: 1) : seed
        }
    }

    /// `clusters` for regions: merged bounds carry the union of their seeds.
    private static func merged(_ regions: [Region]) -> [Region] {
        var result: [Region] = []
        for region in regions {
            var merged = region
            var previousCount = -1
            while previousCount != result.count {
                previousCount = result.count
                result.removeAll { existing in
                    if existing.bounds.insetBy(dx: -3, dy: -3).intersects(merged.bounds) {
                        merged.seed = merged.seed.union(existing.seed)
                        merged.bounds = merged.bounds.union(existing.bounds)
                        return true
                    }
                    return false
                }
            }
            result.append(merged)
        }
        return result
    }

    /// Whole-line expansion admits the lines a seed captures and the other pieces of their
    /// rows. Tightly leaded line rectangles overlap, so admitting every line that touches an
    /// admitted line would absorb a whole paragraph or column (#36). The crop is then trimmed
    /// away from lines it merely touches, because layout removes every intersecting line from
    /// prose; a line whose rectangle genuinely overlaps admitted text is admitted instead.
    /// Returns nil for a thin rule that lies inside text it does not strike through.
    private static func expanded(_ region: Region, page: PageContent) -> CGRect? {
        var admitted: [CGRect] = []
        while true {
            var bounds = admitted.reduce(region.seed) { $0.union($1.insetBy(dx: -2, dy: -2)) }
                .intersection(page.bounds)
            var changed = false
            for line in page.lines where !admitted.contains(line.rect) && bounds.intersects(line.rect) {
                guard captures(region.seed, line) || admitted.contains(where: { sameRow($0, line.rect) }) else { continue }
                admitted.append(line.rect)
                changed = true
            }
            if changed { continue }
            let kept = admitted.reduce(region.core) { $0.union($1) }
            for line in page.lines where !admitted.contains(line.rect) && bounds.intersects(line.rect) {
                let rect = line.rect
                let cuts = [
                    CGRect(x: bounds.minX, y: rect.maxY, width: bounds.width, height: bounds.maxY - rect.maxY),
                    CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: rect.minY - bounds.minY),
                    CGRect(x: rect.maxX, y: bounds.minY, width: bounds.maxX - rect.maxX, height: bounds.height),
                    CGRect(x: bounds.minX, y: bounds.minY, width: rect.minX - bounds.minX, height: bounds.height),
                ].filter { $0.width > 0 && $0.height > 0 && $0.contains(kept) }
                if let cut = cuts.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                    bounds = cut
                } else if admitted.isEmpty && isThinRule(region.seed) {
                    return nil
                } else if !isEdgeBand(region.seed, bounds: page.bounds) || takes(bounds, line) {
                    admitted.append(rect)
                    changed = true
                    break
                }
                // An edge band that cannot be cut around this line keeps its own extent instead of
                // growing into it. `takes` then leaves the line in the prose, so nothing is lost
                // either way, where growing would have buried it in the crop (#246).
            }
            if changed { continue }
            return bounds
        }
    }

    /// Expand crops to whole intersecting text lines so a label cannot be cut in half.
    static func graphicsWithLabels(_ page: PageContent) -> [CGRect] {
        // Displayed formulas have spatial meaning (superscripts, fractions, aligned terms)
        // that line concatenation cannot reproduce. Preserve recognizable formulas as crops.
        let formulas = page.lines.filter { line in
            guard !line.monospaced, line.text.count < 160 else { return false }
            let mathSymbols = line.text.rangeOfCharacter(from: CharacterSet(charactersIn: "∫∑∏√∂∇≈≠≤≥∞")) != nil
            return mathSymbols || statesAnEquation(line.text)
        }.map { $0.rect.insetBy(dx: -4, dy: -8) }
        // A rule underlining one text line is that text's decoration, not a figure. Rows of
        // column-header underlines are table evidence instead (#36).
        let tables = TableRegionDetector.underlinedColumnRegions(in: page)
        let body = max(4, bodySize(page.lines))
        let graphics = page.graphics.compactMap { rect -> CGRect? in
            guard isThinRule(rect) else { return rect }
            if tables.contains(where: { $0.contains(rect) }) { return nil }
            // A fraction bar keeps the terms it touches, as any intersecting graphic does.
            if isFractionBar(rect, in: page.lines, body: body) {
                return page.lines.filter { rect.intersects($0.rect) }.reduce(rect) { $0.union($1.rect) }
            }
            // A rule inside one line's box belongs to that line: a radical's vinculum or an
            // exercise bar keeps its short mathematical line; an underline beneath prose is
            // decoration. A rule outside every line stays an isolated graphic.
            guard let owner = page.lines.first(where: { line in
                rect.minX >= line.rect.minX - body && rect.maxX <= line.rect.maxX + body
                    && rect.midY >= line.rect.minY - 3 && rect.midY <= line.rect.maxY
            }) else { return rect }
            let mathematical = owner.text.count <= 40 && !owner.monospaced
                && owner.text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil
            return mathematical ? rect.union(owner.rect) : nil
        }
        let seeds = graphics + formulas + TableRegionDetector.regions(in: page)
            + FractionRegionDetector.regions(in: page, body: body) + tables
        var regions = clusters(seeds, distance: 3).map { Region(seed: $0, bounds: $0) }
        var previous: [CGRect] = []
        while regions.map(\.bounds) != previous {
            previous = regions.map(\.bounds)
            regions = regions.compactMap { region in
                expanded(region, page: page).map { Region(seed: region.seed, bounds: $0) }
            }
            // A merged bounding rectangle can newly intersect a label that neither component
            // touched. Expand again before rasterizing, or its text is removed from prose while
            // the image clips part of it (for example, a raised exponent beside a fraction).
            regions = merged(regions)
        }
        return regions.map(\.bounds)
    }

    /// Whether a line states an equation: an `=` with a term after it, over a line short enough
    /// that the page set the relation apart rather than running it into prose (#57).
    ///
    /// The term after the sign is what keeps a broken word out. `gpo-911-2004`'s text font maps
    /// the hyphen it prints at a line end to `=`, so every line that breaks a word ends in one,
    /// and the word count cannot tell such a line from a relation: PDFKit reports no space after
    /// a full stop in that book, so an eighty-two-character line of ordinary prose counts twelve
    /// words. On page 306 one such line seeded a crop that grew, line by line, over the whole
    /// paragraph below the stairwell figure, and the paragraph left the reflowed text entirely.
    /// An equation prefix that genuinely ends in `=` still reaches its fraction, through
    /// `FractionRegionDetector`'s own prefix rule, which has the painted bar as its evidence.
    static func statesAnEquation(_ text: String) -> Bool {
        // A web address is not a relation (#227). `gpo-911-2004`'s notes cite query strings
        // (`…print.php3?ReportID=145`), which hold an `=` and leave a note line at twelve words
        // or fewer; the notes pages paint nothing, so such a line was a page's only seed and its
        // crop grew over the whole column. The address is removed before the line is measured;
        // an `=` elsewhere on the line still states its relation.
        let measured = text.split(whereSeparator: \.isWhitespace).filter { !isWebAddress($0) }.joined(separator: " ")
        guard let sign = measured.lastIndex(of: "="),
              measured[measured.index(after: sign)...].contains(where: { !$0.isWhitespace }) else { return false }
        return measured.split(whereSeparator: \.isWhitespace).count <= 12
    }

    /// Whether a word is a web address: a scheme, a `www.` host, or a query string — a `?` or
    /// `&` joining a `name=value` pair (#227).
    static func isWebAddress(_ word: Substring) -> Bool {
        word.contains("://") || word.lowercased().hasPrefix("www.")
            || word.range(of: #"[?&][A-Za-z_][A-Za-z0-9_.-]*="#, options: .regularExpression) != nil
    }

    struct Element {
        var rect: CGRect
        var line: TextLine?
        var image: String?
    }

    /// Convenience for callers that do not report an abandoned cut.
    static func ordered(_ elements: [Element], bodySize: CGFloat) -> [Element] {
        var exhausted = false
        return ordered(elements, bodySize: bodySize, exhausted: &exhausted)
    }

    // Recursive whitespace cuts: columns first; a spanning heading is separated by a horizontal
    // cut before retrying columns. No page-wide y/x sort of interleaved column text.
    //
    // `exhausted` is set when the depth limit stops the cuts while a group still holds several
    // elements: that group is returned in the order it arrived in, which is extraction order,
    // not a reconstructed reading order. Reaching the limit needs 32 nested cuts, so it takes a
    // page of many blocks whose separating gaps do not decrease (an exactly leaded manuscript
    // or transcript); the deepest of the captured corpus pages cuts eleven levels. The page
    // reports it as `complexLayout` rather than leaving the fallback silent, as the tag phase
    // reports its own give-up (#224).
    static func ordered(_ elements: [Element], bodySize: CGFloat, depth: Int = 0,
                        exhausted: inout Bool) -> [Element] {
        guard elements.count > 1 else { return elements }
        guard depth < 32 else { exhausted = true; return elements }
        func gap(horizontal: Bool) -> CGFloat? {
            let intervals = elements.map { horizontal ? ($0.rect.minX, $0.rect.maxX) : ($0.rect.minY, $0.rect.maxY) }
                .sorted { $0.0 < $1.0 }
            var end = intervals[0].1
            var best: (CGFloat, CGFloat)?
            for interval in intervals.dropFirst() {
                let width = interval.0 - end
                if width > bodySize * (horizontal ? 0.75 : 1.1), width > (best?.0 ?? 0) {
                    let middle = (end + interval.0) / 2
                    // A narrow gutter is evidence for prose columns only when both sides
                    // contain substantial text lines. Short labels and numeric answer cells
                    // need row associations; the whitespace alone must not separate them.
                    if horizontal, width <= bodySize * 1.5 {
                        let left = elements.filter { $0.rect.maxX < middle }
                        let right = elements.filter { $0.rect.minX > middle }
                        let proseColumns = [left, right].allSatisfy { column in
                            column.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }.count >= 2
                        }
                        if !proseColumns { end = max(end, interval.1); continue }
                    }
                    best = (width, middle)
                }
                end = max(end, interval.1)
            }
            return best?.1
        }
        // A picture spanning the whole block separates what is printed above it from what is
        // printed below it (#137). The 9/11 report sets two flights' timelines side by side under
        // one map that runs across both of them: no vertical whitespace crosses the map, so no
        // column cut can be made while it is in the group, and the strip of white beneath it is
        // narrower than a line of leading, so no horizontal cut is made either — and the two
        // timelines interleave, row by row, in the order the page painted them. Cutting at the
        // picture puts each column back in its own group. Only a picture divides this way: every
        // line of a one-column page spans its block, and cutting at each of them would reach the
        // depth limit and report the page unread.
        let span = union(elements.map(\.rect))
        if let divider = elements.indices.first(where: { index in
            let rect = elements[index].rect
            guard elements[index].image != nil, rect.width >= span.width * 0.9 else { return false }
            let above = elements.indices.filter { $0 != index && elements[$0].rect.minY >= rect.maxY }
            let below = elements.indices.filter { $0 != index && elements[$0].rect.maxY <= rect.minY }
            // Everything else stands wholly above or wholly below: a picture with a line beside
            // it divides nothing, and its own label is already inside its crop.
            return !above.isEmpty && !below.isEmpty && above.count + below.count == elements.count - 1
        }) {
            let rect = elements[divider].rect
            return ordered(elements.filter { $0.rect.minY >= rect.maxY },
                           bodySize: bodySize, depth: depth + 1, exhausted: &exhausted)
                + [elements[divider]]
                + ordered(elements.filter { $0.rect.maxY <= rect.minY },
                          bodySize: bodySize, depth: depth + 1, exhausted: &exhausted)
        }
        if let x = gap(horizontal: true) {
            return ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1, exhausted: &exhausted)
                + ordered(elements.filter { $0.rect.minX > x }, bodySize: bodySize, depth: depth + 1, exhausted: &exhausted)
        }
        if let y = gap(horizontal: false) {
            return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1, exhausted: &exhausted)
                + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1, exhausted: &exhausted)
        }
        return elements.sorted {
            abs($0.rect.midY - $1.rect.midY) > bodySize * 0.4
                ? $0.rect.midY > $1.rect.midY : $0.rect.minX < $1.rect.minX
        }
    }

    static func bodySize(_ lines: [TextLine]) -> CGFloat {
        var weights: [Int: Int] = [:]
        addBodyWeights(of: lines, to: &weights)
        return bodySize(weights: weights) ?? 12
    }

    /// Characters per rounded type size, the evidence `bodySize` weighs; accumulated over a
    /// document's native pages it gives the document's body (#186).
    static func addBodyWeights(of lines: [TextLine], to weights: inout [Int: Int]) {
        for line in lines { weights[Int(line.fontSize.rounded()), default: 0] += line.text.count }
    }

    static func bodySize(weights: [Int: Int]) -> CGFloat? {
        // Two sizes can carry the same number of characters, and `max` over a Dictionary would
        // then decide by iteration order, which Swift seeds per process: the same book would
        // reflow differently from one run to the next, under an invariant that says it must not
        // (#140). A tie goes to the smaller size, which is the body rather than its display type.
        weights.max { ($0.value, -$0.key) < ($1.value, -$1.key) }.map { CGFloat($0.key) }
    }

    /// Small labels inside preserved images must not turn the surrounding prose into headings.
    /// Keep the page estimate when too little reflowable text remains to establish a body size.
    static func headingBodySize(_ lines: [TextLine], pageBody: CGFloat) -> CGFloat {
        establishedBodySize(lines).map { max(pageBody, $0) } ?? pageBody
    }

    /// The body size the lines establish: at least three lines and 200 characters in their
    /// commonest size.
    static func establishedBodySize(_ lines: [TextLine]) -> CGFloat? {
        let candidate = bodySize(lines)
        let matching = lines.filter { Int($0.fontSize.rounded()) == Int(candidate) }
        guard matching.count >= 3, matching.reduce(0, { $0 + $1.text.count }) >= 200 else { return nil }
        return candidate
    }

    /// The smallest heading size on a page whose reflowable text establishes no body of its own
    /// (#186). Such a page (a back cover, a cover) measures its display lines against type it
    /// barely sets: a mailing panel's return address and web line can be set larger than the
    /// small print around them yet still read well under the document's own running body. There a
    /// heading must also clear the document's body (`documentBody`, the size most of its native
    /// text is set in) as the page threshold clears the page's: a line the document's own body
    /// would not raise heads nothing on a page too bare to say otherwise. A page that establishes
    /// its body keeps its own measure.
    static func documentHeadingFloor(_ lines: [TextLine], documentBody: CGFloat?) -> CGFloat {
        guard let documentBody, establishedBodySize(lines) == nil else { return 0 }
        return documentBody * 1.1
    }

    /// Whether `line` is the next line of the heading `previous` opens: the same size, set
    /// directly beneath it at ordinary heading leading (the rectangles include PDFKit's leading,
    /// so they touch or overlap), sharing the left edge, the center or the right edge (#186).
    static func stacksUnderHeading(_ line: TextLine, after previous: TextLine) -> Bool {
        let size = max(previous.fontSize, line.fontSize)
        guard abs(previous.fontSize - line.fontSize) <= size * 0.1, !previous.sharesRow(with: line),
              line.rect.minY < previous.rect.minY, line.rect.maxY >= previous.rect.minY - size,
              previous.rect.minY - line.rect.minY <= size * 2.2 else { return false }
        return abs(previous.rect.minX - line.rect.minX) <= size * 0.6
            || abs(previous.rect.midX - line.rect.midX) <= size * 0.6
            || abs(previous.rect.maxX - line.rect.maxX) <= size * 0.6
    }

    /// A painted 1-pt rule after graphics padding: an underline or a separator, never a figure on
    /// its own (#218, ported unchanged from the coordination branch's `isThinRule`, #100).
    static func isThinRule(_ rect: CGRect) -> Bool {
        rect.height <= 6 && rect.width >= max(12, rect.height * 3)
    }

    /// A figure or table caption's opening label (#218, ported unchanged from the coordination
    /// branch's `isCaption`, #97): a caption is never the title of the text beneath it, and a
    /// sub-heading is never a caption's own label.
    private static func isCaption(_ text: String) -> Bool {
        text.range(of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil
    }

    /// The page's ordinary line height at a size: the median height of its lines of that size
    /// (#218, ported unchanged from the coordination branch).
    private static func ordinaryLineHeight(_ size: CGFloat, in lines: [TextLine]) -> CGFloat? {
        let heights = lines.filter { $0.hasSize(size) }.map(\.rect.height).sorted()
        return heights.isEmpty ? nil : heights[heights.count / 2]
    }

    /// The page's ordinary gap between wrapped lines at a size: the lower quartile, over lines of
    /// that size and ordinary height, of the gap to the nearest such line directly beneath on the
    /// same left edge (within half a body) inside the prose window (#218, ported unchanged from the
    /// coordination branch's `ordinaryLineGap`, #159).
    private static func ordinaryLineGap(_ size: CGFloat, in lines: [TextLine], body: CGFloat) -> CGFloat? {
        guard let height = ordinaryLineHeight(size, in: lines) else { return nil }
        let ordinary = lines.filter { $0.hasSize(size) && $0.rect.height <= height + body * 0.25 }
        let gaps = ordinary.compactMap { upper -> CGFloat? in
            ordinary.compactMap { lower -> CGFloat? in
                let gap = upper.rect.minY - lower.rect.maxY
                guard lower != upper, abs(upper.rect.minX - lower.rect.minX) <= body * 0.5,
                      gap >= -body * 0.4, gap < body * 0.9, lower.rect.midY < upper.rect.midY else { return nil }
                return gap
            }.min()
        }.sorted()
        return gaps.isEmpty ? nil : gaps[gaps.count / 4]
    }

    /// Whether the page opens its paragraphs on a first-line indent of `step`, in `size` (#218,
    /// ported unchanged from the coordination branch's `firstLineIndentRun`, #159). *Agricultural
    /// Research* indents each paragraph's first line ten points in a ten-and-a-half-point column and
    /// adds two points of space, so neither the leading nor the width of the line above says where a
    /// paragraph ends: only the indent does, and it needs the page's own evidence (at least two such
    /// steps) before it may separate a sub-heading from its paragraph.
    static func firstLineIndentRun(in lines: [TextLine], step: CGFloat, size: CGFloat) -> Bool {
        func sized(_ line: TextLine) -> Bool {
            !line.monospaced && line.hasSize(size)
        }
        let column = lines.filter(sized)
        func neighbor(of line: TextLine, above: Bool) -> TextLine? {
            let sharing = column.filter { other in
                line.sharesColumn(with: other) && !line.sharesRow(with: other)
                    && (above ? other.rect.minY >= line.rect.maxY - size * 0.4
                              : other.rect.maxY <= line.rect.minY + size * 0.4)
            }
            return above ? sharing.min { $0.rect.minY < $1.rect.minY }
                         : sharing.max { $0.rect.maxY < $1.rect.maxY }
        }
        var openings = 0
        for line in column {
            guard let above = neighbor(of: line, above: true),
                  above.rect.minY - line.rect.maxY < size * 0.9,
                  abs(line.rect.minX - above.rect.minX - step) <= size * 0.5,
                  let below = neighbor(of: line, above: false),
                  line.rect.minY - below.rect.maxY < size * 0.9 else { continue }
            if abs(below.rect.minX - line.rect.minX) <= size * 0.5 { return false }
            if abs(line.rect.minX - below.rect.minX - step) <= size * 0.5 { openings += 1 }
        }
        return openings >= 2
    }

    /// A section label's typography relative to its page: its size and the body's (to the half
    /// point), and whether every word is bold (#218, adapted from the coordination branch's
    /// `LabelStyle`, #63/#73/#97). `TextStyle` already carries the bold flag this reads from
    /// main's own font-resource reading, so unlike the branch's `boxTitles` (which reasons about
    /// tinted background regions main does not extract), this needs no prerequisite beyond main's
    /// existing text styling. The branch's `italic` field is not ported: #218's own motivating case
    /// (a bold sidebar title) never needs it, and every italic-specific guard it fed is left out
    /// with it, narrowing this port's risk of promoting an italic run inside ordinary prose.
    struct LabelStyle: Hashable {
        var size: Int
        var body: Int
        var bold: Bool

        init(_ line: TextLine, body: CGFloat) {
            size = Int((line.fontSize * 2).rounded())
            self.body = Int((body * 2).rounded())
            bold = line.content.elements.allSatisfy { element in
                guard case let .text(value, style) = element else { return true }
                return style.contains(.bold) || value.allSatisfy(\.isWhitespace)
            }
        }
    }

    /// A bold sub-heading the book sets at or near its body size, whose paragraph opens directly
    /// beneath it or past an intervening picture and its caption (#218; adapted from the
    /// coordination branch's `sectionLabels` and its `opens(beneath:)`/`pastFigure(_:)`, themselves
    /// built up across #43, #63, #73, #76, #90, #97, #100, #102, #159 and #186). Main has no heading
    /// tiers and no tinted-box detection (`page.tints`, #100's `boxTitles`), so only the bold,
    /// body-adjacent path is ported: *Agricultural Research*'s "Fighting Filth Flies" (#186's fifth
    /// and last #218 leftover) needs no italic label (#97), no two-line stacked title (#102), no
    /// hanging-entry title (#134) and no tinted box, and porting any of those without a corpus
    /// document to validate them against would only add untested false-positive surface to a
    /// function that runs on every page of every conversion.
    ///
    /// A candidate line stands under the heading threshold, at least 80% of the body's size, opens
    /// with a capital, a digit or a mark, ends no sentence, holds at least two letters and reads no
    /// list marker. Below 95% of the body (*Agricultural Research* heads its columns with
    /// nine-point bold lines over a ten-and-a-half-point body, #159) the label carries no size
    /// evidence of its own, so only a paragraph that opens on the page's own first-line indent
    /// counts as its text (`firstLineIndentRun`); at or above 95% the paragraph's own left edge is
    /// enough. The label must read wholly bold and, unless `recordingSubheadings` admits every bold
    /// candidate for `labelEvidence(on:)` to survey, its style must already recur elsewhere in the
    /// book (`styles`, from `labelStyles(from:)`), so a single bold run near body size cannot
    /// promote itself.
    static func sectionLabels(in lines: [TextLine], body: CGFloat, headingThreshold: CGFloat,
                              page: PageContent, styles: Set<LabelStyle> = [],
                              recordingSubheadings: Bool = false) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var labels: [TextLine] = []
        let bodyGap = ordinaryLineGap(body, in: lines, body: body)
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            guard line.fontSize < body * 1.15 else { continue }
            let smaller = line.fontSize < body * 0.95
            guard !line.monospaced, line.fontSize >= body * 0.8, line.fontSize < headingThreshold,
                  line.text.count >= 2, line.text.count < 200, !isList(line.text),
                  let first = line.text.first(where: { !"([\u{201C}\"'".contains($0) }),
                  first.isUppercase || first.isNumber,
                  let last = line.text.last, !".,;:".contains(last),
                  line.text.contains(where: \.isLetter) else { continue }
            let column = lines.filter { line.sharesColumn(with: $0) }
            let above = column.filter { $0.rect.minY >= line.rect.maxY - body * 0.25 }
                .min { $0.rect.minY < $1.rect.minY }
            let clearance = smaller ? min(body * 0.8, (bodyGap ?? 0) + body * 0.5) : body * 0.8
            if let above, above.rect.minY - line.rect.maxY < clearance { continue }
            let style = LabelStyle(line, body: body)
            guard style.bold, recordingSubheadings || styles.contains(style) else { continue }
            let prose = column.filter { $0.fontSize < body * 1.1 }.map(\.rect.width).max() ?? 0
            guard prose > 0, line.rect.width <= prose * 0.9 else { continue }
            func nearestBelow(_ title: TextLine) -> TextLine? {
                lines.filter { title.sharesColumn(with: $0) && $0.rect.maxY <= title.rect.minY + body * 0.4 }
                    .max(by: { $0.rect.maxY < $1.rect.maxY })
            }
            // The line opening the text a title heads past a picture set directly beneath it
            // (#186, #218): *Agricultural Research*'s `Fighting Filth Flies` heads a sidebar over
            // the sidebar's photograph and its caption, well above the sidebar's first line. The
            // picture (no thin rule) stands within four fifths of a body of the title's foot and
            // spans the title's left edge; everything in the title's measure between the picture
            // and the opening is set smaller than the body (its caption and credit); and the
            // opening stands within four bodies of the last of them, since a caption the picture's
            // crop takes is no line here. A caption's own label is no title of the text beneath.
            func pastFigure(_ title: TextLine) -> TextLine? {
                guard !isCaption(title.text), let figure = page.graphics.filter({ graphic in
                          !isThinRule(graphic) && graphic.minX <= title.rect.minX + body * 0.5
                              && graphic.maxX >= title.rect.maxX && graphic.maxY <= title.rect.minY + body * 0.4
                              && title.rect.minY - graphic.maxY < body * 0.8
                      }).max(by: { $0.maxY < $1.maxY }) else { return nil }
                let beneath = lines.filter { title.sharesColumn(with: $0) && $0.rect.maxY <= figure.minY + body * 0.4 }
                    .sorted { $0.rect.maxY > $1.rect.maxY }
                guard let opening = beneath.firstIndex(where: { $0.fontSize >= body * 0.9 }) else { return nil }
                let foot = beneath[..<opening].map(\.rect.minY).min() ?? figure.minY
                return foot - beneath[opening].rect.maxY < body * 4 ? beneath[opening] : nil
            }
            func opens(_ title: TextLine, with below: TextLine) -> Bool {
                guard below.hasSize(body), !LabelStyle(below, body: body).bold else { return false }
                // The paragraph can open on the column's own first-line indent instead of on the
                // title's edge. The page's indent pattern is the evidence, as it is for the
                // paragraph break itself; a wider step is another block, not this title's text.
                let indent = below.rect.minX - title.rect.minX
                let onIndent = indent >= body * 0.5 && indent < body * 1.5
                    && firstLineIndentRun(in: lines, step: indent, size: below.fontSize)
                let paragraph = (smaller ? onIndent : abs(indent) <= body * 0.5 || onIndent)
                    && below.rect.width > title.rect.width
                return paragraph
            }
            // Whether `line`'s paragraph opens directly beneath it, or past the picture set
            // beneath it (#186, #218).
            func opens(beneath title: TextLine) -> Bool {
                if let direct = nearestBelow(title), title.rect.minY - direct.rect.maxY < body * 0.8,
                   opens(title, with: direct) { return true }
                return pastFigure(title).map { opens(title, with: $0) } ?? false
            }
            if opens(beneath: line) { labels.append(line) }
        }
        // Three or more labels ending in folios are a table of contents, not section labels.
        let folio = #"\s(?:\d{1,4}|[ivxlc]+(?:[–-][ivxlc]+)?)$"#
        let entries = labels.filter { $0.text.range(of: folio, options: .regularExpression) != nil }
        return entries.count >= 3 ? labels.filter { !entries.contains($0) } : labels
    }

    /// The label styles one page's sub-body-sized bold lines establish, in `sectionLabels`'s own
    /// evidence-recording mode (#218, adapted from the coordination branch's `labelEvidence(on:)`,
    /// #97). `labelStyles(from:)` keeps the styles that recur across the whole document, so a
    /// single bold run near body size elsewhere in the book cannot promote itself into a heading.
    static func labelEvidence(on page: PageContent) -> Set<LabelStyle> {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        let typography = PageTypography(page: page)
        return Set(sectionLabels(in: page.lines, body: typography.body, headingThreshold: typography.headingThreshold,
                                 page: page, recordingSubheadings: true).map { LabelStyle($0, body: typography.body) })
    }

    /// A style is the book's recurring sub-heading typography once its narrow bold labels appear on
    /// at least three pages (#218, adapted from the coordination branch's `labelStyles(from:)`,
    /// #97/#100).
    static func labelStyles(from pages: [LabelStyle: Int]) -> Set<LabelStyle> {
        Set(pages.filter { $0.value >= 3 }.keys)
    }

    /// What every page's reconstruction shares: how line-end hyphens are decided, the declared
    /// language, the document's body size and recurring sub-heading styles (#186, #218), and the
    /// pages whose numbered-note heading extraction recognized.
    struct DocumentContext: Sendable {
        var hyphens = HyphenContext()
        var language = "en"
        var documentBody: CGFloat?
        var labelStyles: Set<LabelStyle> = []
        var numberedNotePages: Set<Int> = []
    }

    /// One type size, to the half point: the grain at which two lines of a page are set in the
    /// same display type. `LabelStyle` already reads a page's typography at this grain.
    private static func sizeKey(_ size: CGFloat) -> Int { Int((size * 2).rounded()) }

    /// The paragraph-tagged groups a page's own tags contradict, each with the heading level to
    /// read it at.
    ///
    /// The rule above believes a paragraph role over visible typography wherever the page's tags
    /// name a heading at all, because a page that uses `H` roles is a page whose producer knew
    /// how to state one. That reading fails where a producer states one only part of the time.
    /// The Fed's book loses headings both ways — its `RoleMap` sends `Sub_Title`, `Title` and
    /// `Table_Sub_Head` to `P` — and page 21 (printed 13) shows the loss at its sharpest: the
    /// page draws three fourteen-point sub-headings over a ten-point body and tags two of them
    /// `H4` and the third, "Advisory Councils", `P`. One page, one type size, two roles. The
    /// page has not chosen between them; it has contradicted itself, and its own `H4` at that
    /// size is the evidence of which reading the producer meant.
    ///
    /// So a paragraph-tagged group is read as a heading only where the page's tags call that
    /// exact size a heading elsewhere on the page, and only where every line of the group also
    /// reads as a heading by the page's typography. One line of the group set in ordinary prose
    /// refuses the whole group, so the rule can never swallow a paragraph, and the level is the
    /// shallowest the page's own tags give that size, so the promoted heading nests as the
    /// sibling of the headings it is set like rather than at the spatial path's fixed level 2.
    ///
    /// Size alone, without the page's own tagged heading at that size, is not enough: it would
    /// promote Our Flag page 3's imprint ("JOINT COMMITTEE ON PRINTING", "WASHINGTON : 2003")
    /// and the Fed cover's "PUBLIC EDUCATION & OUTREACH", which no page tags as a heading and
    /// which head nothing. Across the corpus's seven documents with tagged pages this rule
    /// promotes exactly one group, and the FAA handbook — whose 171 headings the rule above
    /// protects — cannot reach it at all, because no FAA page's tags name a heading (#67, #91).
    static func contradictedHeadingGroups(_ elements: [Element], roles: [LineRole?]) -> [Int: Int] {
        var tagged: [Int: Int] = [:]
        for element in elements {
            guard let line = element.line, let tag = line.structure, tag.headingLevel > 0 else { continue }
            let key = sizeKey(line.fontSize)
            tagged[key] = min(tagged[key] ?? tag.headingLevel, tag.headingLevel)
        }
        guard !tagged.isEmpty else { return [:] }
        var promoted: [Int: Int] = [:]
        var lengths: [Int: Int] = [:]
        var refused: Set<Int> = []
        for (index, element) in elements.enumerated() {
            guard let line = element.line, let tag = line.structure, tag.headingLevel == 0 else { continue }
            guard roles[index] == .heading, let level = tagged[sizeKey(line.fontSize)] else {
                refused.insert(tag.group)
                continue
            }
            promoted[tag.group] = min(promoted[tag.group] ?? level, level)
            lengths[tag.group, default: 0] += line.text.count + 1
        }
        // `structuredOrder` already refuses a tagged heading of 200 characters or more as too
        // long to be one; a promotion must not reach past that ceiling either.
        return promoted.filter { !refused.contains($0.key) && lengths[$0.key, default: 0] < 200 }
    }

    /// One page's logical blocks: its typography is read once, every line outside a tagged or
    /// numbered-note group is classified by `role(of:)`, and `BlockAssembler` builds the blocks.
    static func blocks(page: PageContent, images: [(CGRect, String)], context: DocumentContext,
                       warnings: inout [ConversionWarning]) -> [ReflowBlock] {
        // A crop takes every line it intersects, except a wrapped paragraph the page prints over
        // one of its own pictures, which is the book's prose and no cut can free (#239).
        let overPicture = PageDiagnosis.proseOverPictures(lines: page.lines, pictures: page.pictures,
                                                          crops: images.map(\.0), bounds: page.bounds,
                                                          language: context.language)
        let lines = page.lines.enumerated().filter { index, line in
            overPicture.contains(index) || !images.contains { takes($0.0, line) }
        }.map(\.element)
        let typography = PageTypography(pageLines: page.lines, reflowableLines: lines, documentBody: context.documentBody)
        // A bold sub-heading set at or near body size, whose paragraph opens beneath it directly or
        // past an intervening picture and caption (#218).
        let labels = sectionLabels(in: lines, body: typography.body, headingThreshold: typography.headingThreshold,
                                   page: page, styles: context.labelStyles)
        // A recognized line in an English book is a heading only if it reads as words: a table
        // cell or a reading of handwriting set large is not a title, and every heading is a
        // navigation entry (#7).
        let judgesTitleWords = page.recognized && EnglishText.isDeclared(context.language)
        var exhausted = false
        let spatial = ordered(lines.map { Element(rect: $0.readingRect ?? $0.rect, line: $0) }
            + images.map { Element(rect: $0.0, image: $0.1) }, bodySize: typography.body, exhausted: &exhausted)
        if exhausted {
            warnings.append(.init(code: .complexLayout, page: page.number,
                message: "Whitespace cuts reached their depth limit before separating this page's content; "
                    + "what remained keeps the order it was extracted in, which may not be its reading order."))
        }
        let elements = structuredOrder(spatial, page: page.number, warnings: &warnings)
        let noteGroups = NumberedNoteDetector.groups(in: elements, page: page,
                                                     headingEvidence: context.numberedNotePages.contains(page.number))
        var assembler = BlockAssembler(page: page.number, body: typography.body, hyphens: context.hyphens)
        // A page whose tags never name a heading has not said that its display lines are not
        // headings; it has said only what they contain and in what order. Producers routinely
        // give every heading style a paragraph role — the FAA handbook's RoleMap sends
        // `AC_heading_1`...`AC_heading_5` to `P` — so believing a paragraph role there costs the
        // page its navigation for nothing. Where the page's tags do name a heading, every role
        // they give is believed over visible typography, as before (#67).
        let tagsNameHeading = elements.contains { ($0.line?.structure?.headingLevel ?? 0) > 0 }
        // Rows of a table the page set without rules keep their breaks rather than joining into
        // one paragraph (#137, #210). The evidence is the page's own stated column boundary, so
        // it is read from the lines that still reflow, after the crops have taken theirs.
        let rows = TableRegionDetector.rowBlocks(in: lines, body: typography.body)
        let roles = elements.map { element in
            element.line.map { line -> LineRole in
                let role = role(of: line, on: page, in: lines, typography: typography,
                                labels: labels, judgesTitleWords: judgesTitleWords)
                // A heading standing in the block, and monospaced text that keeps its own
                // breaks already, are left as they read.
                guard role != .heading, role != .code,
                      let block = rows.first(where: { $0.insetBy(dx: -1, dy: -1).contains(line.rect) })
                else { return role }
                // A line set in from the block's own left edge is a cell that wrapped, not the
                // next row.
                return .tableRow(continuation: line.rect.minX > block.minX + typography.body * 0.6)
            }
        }
        let contradicted = contradictedHeadingGroups(elements, roles: roles)
        for (index, element) in elements.enumerated() {
            if let group = noteGroups[index], let line = element.line {
                assembler.appendNote(group: group, line)
            } else if let path = element.image {
                assembler.appendImage(path)
            } else if let line = element.line, let spatial = roles[index] {
                if var tag = line.structure {
                    if let level = contradicted[tag.group] { tag.headingLevel = level }
                    // A row of a table the page's own geometry states keeps its break even where
                    // the tags name the cell a paragraph: the FAA handbook tags one wrapped cell
                    // of its service-volume table and leaves the other six rows untagged, and
                    // believing that one tag would strand it as prose beside its own table
                    // (#137). What the tags name a heading is still a heading.
                    if tag.headingLevel == 0, case .tableRow = spatial {
                        assembler.append(line, as: spatial)
                    } else if tag.headingLevel > 0 || tagsNameHeading || spatial != .heading {
                        assembler.appendTagged(tag, line)
                    } else {
                        assembler.append(line, as: spatial)
                    }
                } else {
                    assembler.append(line, as: spatial)
                }
            }
        }
        let result = assembler.finish()
        warnings += assembler.warnings
        return result
    }

    /// Convenience for tests that supply the document context piecemeal.
    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], numberedNotePage: Bool = false,
                       language: String = "en", documentBody: CGFloat? = nil,
                       labelStyles: Set<LabelStyle> = []) -> [ReflowBlock] {
        let context = DocumentContext(hyphens: HyphenContext(vocabulary: vocabulary), language: language,
                                      documentBody: documentBody, labelStyles: labelStyles,
                                      numberedNotePages: numberedNotePage ? [page.number] : [])
        return blocks(page: page, images: images, context: context, warnings: &warnings)
    }

    /// Tags may reorder only complete groups inside an uninterrupted run of tagged text.
    /// Images and unassociated text are barriers, including content removed into image crops.
    static func structuredOrder(_ spatial: [Element], page: Int,
                                warnings: inout [ConversionWarning], depth: Int = 0) -> [Element] {
        var elements = spatial
        guard depth < 32 else {
            for index in elements.indices { elements[index].line?.structure = nil }
            return elements
        }
        if depth == 0 {
            let groups = Dictionary(grouping: elements.compactMap(\.line).filter { $0.structure != nil },
                by: { $0.structure!.group })
            let unsafe = Set(groups.compactMap { group, lines -> Int? in
                // Caption ownership and lists are outside this phase. A paragraph tag alone
                // must not detach a figure label or collapse significant item breaks.
                let captionOrList = lines.contains { isList($0.text) || $0.text.range(
                    of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil }
                let oversizedHeading = lines.first!.structure!.headingLevel > 0
                    && lines.reduce(0, { $0 + $1.text.count + 1 }) >= 200
                return captionOrList || oversizedHeading ? group : nil
            })
            if !unsafe.isEmpty {
                for index in elements.indices {
                    if let group = elements[index].line?.structure?.group, unsafe.contains(group) {
                        elements[index].line?.structure = nil
                    }
                }
                warnings.append(.init(code: .structureFallback, page: page,
                    message: "Caption, list or oversized heading tags require broader semantic validation; spatial reconstruction is retained."))
            }
        }
        var runs: [Int: Set<Int>] = [:]
        var counts: [Int: Int] = [:]
        var run = 0
        for element in elements {
            if let tag = element.line?.structure {
                runs[tag.group, default: []].insert(run)
                counts[tag.group, default: 0] += 1
            } else { run += 1 }
        }
        var rejected = false
        for index in elements.indices {
            if let tag = elements[index].line?.structure,
               runs[tag.group]?.count != 1 || counts[tag.group] != tag.lineCount {
                elements[index].line?.structure = nil
                rejected = true
            }
        }
        // Rejecting a group introduces another barrier. Repeat until groups cannot cross it.
        if rejected {
            if !warnings.contains(where: { $0.code == .structureFallback && $0.page == page }) {
                warnings.append(.init(code: .structureFallback, page: page,
                    message: "Tagged groups intersect preserved regions or unassociated text; their spatial layout is retained."))
            }
            return structuredOrder(elements, page: page, warnings: &warnings, depth: depth + 1)
        }
        var start = 0
        while start < elements.count {
            guard elements[start].line?.structure != nil else { start += 1; continue }
            var end = start + 1
            while end < elements.count && elements[end].line?.structure != nil { end += 1 }
            elements.replaceSubrange(start..<end, with: elements[start..<end].enumerated().sorted {
                let left = $0.element.line!.structure!, right = $1.element.line!.structure!
                return left.order == right.order ? $0.offset < $1.offset : left.order < right.order
            }.map(\.element))
            start = end
        }
        return elements
    }

    static func imageBlock(assetID: String, page: Int, reference: Bool = false) -> ReflowBlock {
        let caption = reference ? "Original page \(page)" : "Preserved region from page \(page)"
        return ReflowBlock(content: .image(.init(assetID: assetID, alternativeText: caption, caption: caption)), page: page)
    }

    /// Preserve the source boundary inside a continuing paragraph, without a format-specific marker.
    static func appendPage(_ pageBlocks: [ReflowBlock], page: PageContent, previousPage: PageContent?,
                           to blocks: inout [ReflowBlock], vocabulary: Set<String>,
                           warnings: inout [ConversionWarning]) {
        appendPage(pageBlocks, page: page, previousPage: previousPage, to: &blocks,
                   hyphens: HyphenContext(vocabulary: vocabulary), warnings: &warnings)
    }

    static func appendPage(_ pageBlocks: [ReflowBlock], page: PageContent, previousPage: PageContent?,
                           to blocks: inout [ReflowBlock], hyphens: HyphenContext,
                           warnings: inout [ConversionWarning]) {
        var remaining = pageBlocks
        if let last = blocks.last, let first = remaining.first, let previousPage,
           case let .paragraph(left) = last.content, case let .paragraph(right) = first.content,
           // Two validated paragraph identities that differ are two paragraphs, and never join.
           // One identity and no identity is not that: a page whose tags were not applied says
           // nothing about where its last paragraph ends, so the geometric rule decides, as it
           // did when neither page carried a tag (#67).
           last.structureGroup == first.structureGroup || last.structureGroup == nil || first.structureGroup == nil,
           first.text.first?.isLowercase == true, last.text.last.map({ !".!?:".contains($0) }) == true,
           previousPage.lines.last.map({ $0.rect.minY < previousPage.bounds.minY + previousPage.bounds.height * 0.2 }) == true,
           page.lines.first.map({ $0.rect.maxY > page.bounds.minY + page.bounds.height * 0.8 }) == true {
            blocks[blocks.count - 1].content = .paragraph(join(left, right, hyphens: hyphens,
                page: page.number, sourceBoundary: page.number, warnings: &warnings))
            remaining.removeFirst()
        } else {
            blocks.append(ReflowBlock(content: .sourcePage(page.number), page: page.number))
        }
        blocks += remaining
    }
}
