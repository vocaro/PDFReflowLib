import Foundation
import CoreGraphics

enum LayoutReconstructor {
    static func vocabulary(in pages: [PageContent]) -> Set<String> {
        var result: Set<String> = []
        for page in pages { addVocabulary(of: page, to: &result) }
        return result
    }

    /// Hyphen repair consults every page's words; accumulating them per page lets extraction
    /// release the page itself.
    static func addVocabulary(of page: PageContent, to vocabulary: inout Set<String>) {
        for line in page.lines {
            for word in line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
                vocabulary.insert(String(word))
            }
        }
    }

    static func stripFurniture(_ pages: inout [PageContent]) -> [ConversionWarning] {
        FurnitureDetector.strip(&pages)
    }

    /// A painted 1-pt rule after GraphicsReader's two-point padding: an underline, a
    /// column-header rule or a separator, never a figure on its own.
    static func isThinRule(_ rect: CGRect) -> Bool {
        rect.height <= 6 && rect.width >= max(12, rect.height * 3)
    }

    /// A short rule between a compact mathematical term above it and a term starting directly
    /// beneath it is a fraction bar, whose numerator and denominator belong in one crop, not an
    /// underline. Label underlines have worded prose above them. PDFKit can merge a denominator
    /// with the annotation or the next numerator beside it, so terms are matched by extent.
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
    /// and at or just below its baseline region, not up in the ascenders of the line beneath.
    static func underlinedLine(_ rule: CGRect, in lines: [TextLine]) -> TextLine? {
        guard isThinRule(rule), !isFractionBar(rule, in: lines, body: max(4, bodySize(lines))) else { return nil }
        return lines.filter { line in
            rule.minX >= line.rect.minX - 3 && rule.maxX <= line.rect.maxX + 3
                && rule.midY >= line.rect.minY - 3 && rule.midY <= line.rect.minY + line.rect.height * 0.5
        }.min { $0.rect.width < $1.rect.width }
    }

    /// Whether a seed region captures a text line. Tall PDFKit line rectangles include leading,
    /// so a thin rule touches the rectangles of the lines above and below without crossing
    /// their glyphs; it captures only text it actually strikes through.
    private static func captures(_ seed: CGRect, _ line: TextLine) -> Bool {
        guard seed.intersects(line.rect) else { return false }
        guard isThinRule(seed) else { return true }
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
                } else {
                    admitted.append(rect)
                    changed = true
                    break
                }
            }
            if changed { continue }
            return bounds
        }
    }

    /// An algorithm float set between rules (LaTeX `algorithm`/`algorithmic`): a caption line
    /// `Algorithm N …` directly beneath a thin rule, a second rule of the same extent directly
    /// beneath the caption, and a closing rule of that extent further down. The listing between
    /// the second and closing rules is one region, because its numbered lines, keywords and
    /// inline mathematics cannot reflow as prose or code without losing lines to separate crops
    /// (#43). The caption stays text; the top rule is the caption's decoration.
    static func algorithmFloats(in page: PageContent) -> (regions: [CGRect], decorations: [CGRect]) {
        let rules = page.graphics.filter { isThinRule($0) && $0.width >= 100 }
        guard !rules.isEmpty else { return ([], []) }
        let body = max(4, bodySize(page.lines))
        func sameExtent(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) <= 3 && abs(a.maxX - b.maxX) <= 3 }
        var regions: [CGRect] = [], decorations: [CGRect] = []
        for caption in page.lines where !caption.monospaced
            && caption.text.range(of: #"^Algorithm\s+\d+\b"#, options: .regularExpression) != nil {
            let box = caption.rect
            guard let top = rules.first(where: { rule in
                      rule.minX <= box.minX + 3 && rule.maxX >= box.maxX - 3
                          && rule.minY >= box.maxY - 1 && rule.minY <= box.maxY + body
                  }),
                  let upper = rules.first(where: { rule in
                      sameExtent(rule, top) && rule.maxY <= box.minY + 1 && rule.maxY >= box.minY - body
                  }),
                  let closing = rules.filter({ sameExtent($0, top) && $0.maxY < upper.minY })
                      .max(by: { $0.maxY < $1.maxY }) else { continue }
            // The rules' ink is at their midlines (GraphicsReader pads them by two points).
            regions.append(CGRect(x: top.minX, y: closing.midY - 1, width: top.width,
                                  height: upper.midY + 1 - (closing.midY - 1)))
            decorations.append(top)
        }
        return (regions, decorations)
    }

    /// Text rotated a quarter turn extracts as a line far taller than wide. One running along
    /// at least a quarter of the outer margin of a page whose other text runs horizontally is a
    /// stamp (arXiv's identifier), not content or a heading (#43). A short rotated line beside a
    /// photograph is its credit and keeps its paragraph; on a rotated page every line is tall,
    /// so nothing is a stamp.
    static func rotatedMarginLines(_ page: PageContent) -> [TextLine] {
        let horizontal = page.lines.filter { $0.rect.width >= $0.rect.height * 2 }.reduce(0) { $0 + $1.text.count }
        let vertical = page.lines.filter { $0.rect.height >= $0.rect.width * 2 }.reduce(0) { $0 + $1.text.count }
        guard vertical > 0, horizontal > vertical * 3 else { return [] }
        let margin = page.bounds.width * 0.12
        return page.lines.filter { line in
            line.text.filter { !$0.isWhitespace }.count >= 3 && line.rect.height >= line.rect.width * 3
                && line.rect.height >= page.bounds.height * 0.25
                && (line.rect.maxX <= page.bounds.minX + margin || line.rect.minX >= page.bounds.maxX - margin)
        }
    }

    /// A section label set only modestly larger than the body (acmart's 10.9-point bold
    /// small-caps `ABSTRACT` or `1 INTRODUCTION` over 9-point prose, the 9/11 report's 12-point
    /// `1.1 INSIDE THE FOUR FLIGHTS` over 10-point prose) sits below the 25% heading threshold
    /// and would otherwise open its paragraph (#43). Size alone is not evidence (an inherited
    /// OCR layer's prose can run 20% over a small reference body), so the line must also read
    /// as a label: it starts with a capital or a digit, does not end in sentence punctuation,
    /// has clear space above it or continues a label of the same size, and is either set in
    /// capitals or shorter than the column's prose lines. Recognized and synthetic pages have
    /// no typographic sizes to trust.
    static func sectionLabels(in lines: [TextLine], body: CGFloat, headingThreshold: CGFloat,
                              page: PageContent) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var labels: [TextLine] = []
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            // A list item (an answer-key entry, a contents line) keeps its list representation.
            guard !line.monospaced, line.fontSize >= body * 1.15, line.fontSize < headingThreshold,
                  line.text.count >= 2, line.text.count < 200, !isList(line.text),
                  let first = line.text.first, first.isUppercase || first.isNumber,
                  let last = line.text.last, !".,;:".contains(last),
                  // Words, or a dotted section number whose title PDFKit split off at the gap.
                  line.text.contains(where: \.isLetter)
                    || line.text.range(of: #"^\d+(?:\.\d+)+$"#, options: .regularExpression) != nil else { continue }
            let column = lines.filter { other in
                other != line && other.rect.minX < line.rect.maxX && other.rect.maxX > line.rect.minX
            }
            let above = column.filter { $0.rect.minY >= line.rect.maxY - body * 0.25 }
                .min { $0.rect.minY < $1.rect.minY }
            if let above, above.rect.minY - line.rect.maxY < body * 0.8,
               !(labels.contains(above) && abs(above.fontSize - line.fontSize) <= line.fontSize * 0.05) { continue }
            let letters = line.text.filter(\.isLetter)
            let capitals = letters.allSatisfy(\.isUppercase)
            let prose = column.filter { $0.fontSize < body * 1.1 }.map(\.rect.width).max() ?? 0
            if capitals || line.rect.width <= prose * 0.9 || prose == 0 { labels.append(line) }
        }
        // Three or more labels ending in folios are a table of contents, not section labels.
        let folio = #"\s(?:\d{1,4}|[ivxlc]+(?:[–-][ivxlc]+)?)$"#
        let entries = labels.filter { $0.text.range(of: folio, options: .regularExpression) != nil }
        return entries.count >= 3 ? labels.filter { !entries.contains($0) } : labels
    }

    /// A contents entry: a dot leader of four or more dots running to the line's end, with or
    /// without its folio (PDFKit can split the folio into a same-row line). Contents pages set
    /// their chapter entries at heading size, but a leader never ends a heading (#55).
    static func isContentsEntry(_ text: String) -> Bool {
        text.range(of: #"(?:\.\s*){4,}(?:\d{1,4}|[ivxlcdm]{1,8})?\s*$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether `line` is the next line of the heading `previous` opens: the same size, set
    /// directly beneath it at ordinary heading leading (the rectangles include PDFKit's
    /// leading, so they touch or overlap), sharing the left edge, the centre or the right edge.
    static func stacksUnderHeading(_ line: TextLine, after previous: TextLine) -> Bool {
        let size = max(previous.fontSize, line.fontSize)
        guard abs(previous.fontSize - line.fontSize) <= size * 0.1, !sameRow(previous.rect, line.rect),
              line.rect.minY < previous.rect.minY, line.rect.maxY >= previous.rect.minY - size,
              previous.rect.minY - line.rect.minY <= size * 2.2 else { return false }
        return abs(previous.rect.minX - line.rect.minX) <= size * 0.6
            || abs(previous.rect.midX - line.rect.midX) <= size * 0.6
            || abs(previous.rect.maxX - line.rect.maxX) <= size * 0.6
    }

    /// Terminal punctuation past closing quotes and brackets; a colon ends a heading's first
    /// line (`The Federal Open Market Committee:` / `Selection and Function`), not a sentence.
    private static func endsSentence(_ text: String) -> Bool {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        guard let ending = text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) else { return false }
        return ".!?".contains(ending)
    }

    /// A line that opens a heading of its own rather than continuing the one above it: a
    /// section number or a chapter label. Two same-size headings stacked without such a mark
    /// are the lines of one title.
    private static func opensHeading(_ text: String) -> Bool {
        text.range(of: #"^(?:\d+(?:\.\d+)+\.?\s|(?:Chapter|Part|Section|Appendix|Unit|Lesson)\s+(?:\d+|[IVXLC]+)\b)"#,
                   options: .regularExpression) != nil
    }

    /// The lines of one heading set over several lines merge into one heading: the next line
    /// stacks under the previous at the same size and alignment, the heading so far does not
    /// end a sentence, and the line does not open a numbered heading of its own (#55).
    static func continuesHeading(_ heading: String, with line: TextLine, after previous: TextLine) -> Bool {
        stacksUnderHeading(line, after: previous) && !endsSentence(heading) && !opensHeading(line.text)
    }

    /// A chapter opener's pull quote is set in display type between the body and the title,
    /// over several lines, and reads as a sentence: the run ends in terminal punctuation and
    /// carries at least eight words. It is prose, not one heading per printed line (#55). A
    /// multi-line title has no terminal punctuation; a one-line heading ending in a period
    /// stays a heading. `lines` are the page's lines in reading order and `candidates` names
    /// the heading-size and label lines among them.
    static func pullQuoteLines(in lines: [TextLine], candidates: (TextLine) -> Bool) -> [TextLine] {
        var quotes: [TextLine] = []
        var run: [TextLine] = []
        func close() {
            if run.count >= 2, let last = run.last, endsSentence(last.text),
               run.reduce(0, { $0 + wordCount($1.text) }) >= 8 { quotes += run }
            run = []
        }
        for line in lines {
            guard candidates(line) else { close(); continue }
            if let previous = run.last, !stacksUnderHeading(line, after: previous) { close() }
            run.append(line)
        }
        close()
        return quotes
    }

    /// Heading sizes ranked into tiers (7% apart), largest first.
    static func headingTiers(_ sizes: [CGFloat]) -> [CGFloat] {
        var tiers: [CGFloat] = []
        for size in sizes.sorted(by: >) where !(tiers.last.map { size >= $0 * 0.93 } ?? false) {
            tiers.append(size)
        }
        return tiers
    }

    /// Levels for headings, ranked document-wide once every page is reconstructed: the largest
    /// tier keeps the existing level 2 of the flat navigation model and each smaller tier is one
    /// level deeper (to 6), so a title outranks the author names beneath it and a chapter title
    /// outranks its section labels on every page alike (#43).
    ///
    /// A tagged heading keeps its validated level (#43), but only where that level is comparable
    /// with the ranking the rest of the document uses. A source whose heading hierarchy is only
    /// partly reconstructable otherwise contradicts itself: the Fed's chapter titles sit on
    /// image-backed pages, so their `H2` never reaches this stage, and their 16-point `H3`
    /// sections would become siblings of the 24-point chapter titles above them (#67).
    ///
    /// A validated level therefore yields only to a typographic heading that is larger than every
    /// heading the document tags at that level and already ranks at that level or deeper. A
    /// larger heading inside the tagged size range is a sibling the tags did not reach, not a
    /// contradiction: Our Flag tags `H3` from 9 to 21 points, so its untagged 20-point
    /// `"The Star-Spangled Banner"` does not demote `Flag Anatomy` at 18. A level that yields
    /// ranks all its headings by size, like every other heading.
    ///
    /// A heading contributes its size to the tiers exactly when it is ranked on them, so a
    /// validated level neither adds a tier the document does not otherwise use nor removes the
    /// one its own typography provides: the Fed's tagged section titles restore the tier their
    /// untagged siblings used to supply, while a book whose validated levels all hold ranks
    /// exactly as it did before any tag applied. One pass over the blocks' sizes; no page geometry.
    static func rankHeadingLevels(_ blocks: inout [ReflowBlock]) {
        func ranker(_ sizes: [CGFloat]) -> (CGFloat) -> Int {
            let tiers = headingTiers(sizes)
            return { value in min(6, 2 + (tiers.firstIndex { value >= $0 * 0.93 } ?? tiers.count)) }
        }
        let headings = blocks.compactMap { block -> (size: CGFloat, validated: Int?)? in
            guard let size = block.headingSize, case .heading = block.content else { return nil }
            return (size, block.taggedLevel)
        }
        var largestTagged: [Int: CGFloat] = [:]
        for heading in headings {
            if let validated = heading.validated { largestTagged[validated] = max(largestTagged[validated] ?? 0, heading.size) }
        }
        // Rank the typographic headings first, then see which validated levels that scale
        // contradicts; only those join it, and the final scale settles every ranked heading.
        let spatial = ranker(headings.filter { $0.validated == nil }.map(\.size))
        // Once a level yields, every deeper level yields with it: a validated level beneath one that
        // typography now ranks could otherwise land beside it (the Fed's 12-point `H5` beside its
        // re-ranked 14-point `H4`), so below the break the whole hierarchy is ranked by size.
        let firstYielding = largestTagged.compactMap { validated, largest -> Int? in
            headings.contains { $0.validated == nil && $0.size > largest * 1.07 && spatial($0.size) >= validated }
                ? validated : nil
        }.min()
        func yields(_ validated: Int) -> Bool { firstYielding.map { validated >= $0 } ?? false }
        let ranked = ranker(headings.filter { $0.validated.map(yields) ?? true }.map(\.size))
        for index in blocks.indices {
            guard let size = blocks[index].headingSize,
                  case let .heading(id, text, _) = blocks[index].content else { continue }
            var level = ranked(size)
            if let validated = blocks[index].taggedLevel, !yields(validated) { level = validated }
            blocks[index].content = .heading(id: id, text: text, level: level)
        }
    }

    /// Expand crops to whole intersecting text lines so a label cannot be cut in half.
    static func graphicsWithLabels(_ page: PageContent) -> [CGRect] {
        // Displayed formulas have spatial meaning (superscripts, fractions, aligned terms)
        // that line concatenation cannot reproduce. Preserve recognizable formulas as crops.
        let formulas = page.lines.filter { line in
            guard !line.monospaced, line.text.count < 160 else { return false }
            let mathSymbols = line.text.rangeOfCharacter(from: CharacterSet(charactersIn: "∫∑∏√∂∇≈≠≤≥∞")) != nil
            let equation = line.text.contains("=") && line.text.split(whereSeparator: \.isWhitespace).count <= 12
            return mathSymbols || equation
        }.map { $0.rect.insetBy(dx: -4, dy: -8) }
        // A rule underlining one text line is that text's decoration, not a figure. Rows of
        // column-header underlines are table evidence instead (#36).
        let tables = TableRegionDetector.underlinedColumnRegions(in: page)
        let floats = algorithmFloats(in: page)
        let body = max(4, bodySize(page.lines))
        let graphics = page.graphics.compactMap { rect -> CGRect? in
            guard isThinRule(rect) else { return rect }
            if tables.contains(where: { $0.contains(rect) }) || floats.decorations.contains(rect) { return nil }
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
            + FractionRegionDetector.regions(in: page) + tables + floats.regions
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

    struct Element {
        var rect: CGRect
        var line: TextLine?
        var image: String?
        /// Index into the page's shaded text tables.
        var table: Int?
        /// Marks the edge of a tinted box: paragraphs never join across it.
        var boundary = false
        /// A tinted box read as one float: its content is ordered on its own, and the box
        /// follows the lines beside it instead of interleaving with them.
        var box: [Element]?
    }

    // Recursive whitespace cuts: columns first; a spanning heading is separated by a horizontal
    // cut before retrying columns. No page-wide y/x sort of interleaved column text.
    static func ordered(_ elements: [Element], bodySize: CGFloat, depth: Int = 0) -> [Element] {
        guard elements.count > 1, depth < 32 else { return elements }
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
        if let x = gap(horizontal: true) {
            return ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX > x }, bodySize: bodySize, depth: depth + 1)
        }
        if let y = gap(horizontal: false) {
            return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
        }
        if let x = bulletColumns(elements, bodySize: bodySize) {
            return ordered(elements.filter { $0.rect.minX < x && $0.rect.maxX > x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.maxX <= x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX >= x }, bodySize: bodySize, depth: depth + 1)
        }
        // A floated box reads after the lines beside it and before the lines below it.
        func key(_ element: Element) -> CGFloat { element.box == nil ? element.rect.midY : element.rect.minY }
        return elements.sorted {
            abs(key($0) - key($1)) > bodySize * 0.4 ? key($0) > key($1) : $0.rect.minX < $1.rect.minX
        }
    }

    /// Bulleted columns the whitespace cuts cannot separate: their items are far shorter than
    /// the prose-column measure, and a label set over both columns spans the gutter, so no
    /// vertical band of whitespace runs the height of the group (Fed page 58's "Emergency
    /// lending facilities" panel, #64). The evidence is the markers themselves: two runs of at
    /// least two list markers, each run on its own left edge, with every line at or below the
    /// first marker wholly on one side of a gutter at least as wide as the whitespace test
    /// demands. Lines above the first marker are the columns' heading and read before them.
    /// Returns the gutter's x, or nil when the markers give no such reading.
    static func bulletColumns(_ elements: [Element], bodySize: CGFloat) -> CGFloat? {
        let markers = elements.filter { element in
            guard let line = element.line, !line.monospaced else { return false }
            return isList(line.text)
        }
        guard markers.count >= 4, let top = markers.map(\.rect.maxY).max() else { return nil }
        let edges = markers.map(\.rect.minX).sorted()
        // A marker column's own lines share a left edge; the next column starts a marker's
        // width away. Indices walk the sorted edges so three columns split one gutter at a time.
        for index in 1..<edges.count where edges[index] - edges[index - 1] > bodySize * 2 {
            let split = (edges[index - 1] + edges[index]) / 2
            let leading = markers.filter { $0.rect.minX < split }
            let trailing = markers.filter { $0.rect.minX > split }
            guard leading.count >= 2, trailing.count >= 2,
                  leading.allSatisfy({ $0.rect.minX <= edges[index - 1] + bodySize * 0.5 }),
                  trailing.allSatisfy({ $0.rect.minX >= edges[index] - bodySize * 0.5 }) else { continue }
            let items = elements.filter { $0.rect.minY < top }
            let left = items.filter { $0.rect.minX < split }, right = items.filter { $0.rect.minX > split }
            guard left.count + right.count == items.count,
                  let leadingEnd = left.map(\.rect.maxX).max(), let trailingStart = right.map(\.rect.minX).min(),
                  trailingStart - leadingEnd > bodySize * 0.75 else { continue }
            let gutter = (leadingEnd + trailingStart) / 2
            // Only a heading above the columns may span the gutter; a note or a rule beneath
            // them binds the columns together and leaves the group to the reading-order sort.
            guard elements.allSatisfy({ $0.rect.minY >= top || $0.rect.maxX <= gutter || $0.rect.minX >= gutter })
            else { continue }
            return gutter
        }
        return nil
    }

    /// Tinted boxes (sidebars, shaded tables with their titles) are read as units: the elements
    /// inside each box are ordered among themselves and the box takes one place in the page
    /// order, as its image did before the box reflowed (#54).
    static func boxed(_ elements: [Element], tints: [CGRect], bodySize: CGFloat) -> [Element] {
        var remaining = elements
        var boxes: [Element] = []
        for hull in clusters(tints, distance: 4) {
            let inside = remaining.filter { hull.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            guard inside.contains(where: { $0.line != nil }) else { continue }
            remaining.removeAll { element in inside.contains { $0.rect == element.rect && $0.line == element.line && $0.image == element.image } }
            boxes.append(Element(rect: hull.union(union(inside.map(\.rect))), box: ordered(inside, bodySize: bodySize)))
        }
        return ordered(remaining + boxes, bodySize: bodySize).flatMap { element -> [Element] in
            guard let content = element.box else { return [element] }
            let edge = Element(rect: element.rect, boundary: true)
            return [edge] + content + [edge]
        }
    }

    static func bodySize(_ lines: [TextLine]) -> CGFloat {
        var weights: [Int: Int] = [:]
        for line in lines { weights[Int(line.fontSize.rounded()), default: 0] += line.text.count }
        return CGFloat(weights.max { $0.value < $1.value }?.key ?? 12)
    }

    /// Small labels inside preserved images must not turn the surrounding prose into headings.
    /// Keep the page estimate when too little reflowable text remains to establish a body size.
    static func headingBodySize(_ lines: [TextLine], pageBody: CGFloat) -> CGFloat {
        let candidate = bodySize(lines)
        let matching = lines.filter { Int($0.fontSize.rounded()) == Int(candidate) }
        guard matching.count >= 3, matching.reduce(0, { $0 + $1.text.count }) >= 200 else {
            return pageBody
        }
        return max(pageBody, candidate)
    }

    /// `noteChapter` is the chapter named by this page's `NOTES TO CHAPTER N` running head,
    /// retained before furniture removal; nil for pages without one. `continuesNote` states
    /// that the previous page ended in a page-bottom footnote, so a marker-less note under
    /// this page's separator may continue it.
    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], noteChapter: Int? = nil,
                       continuesNote: Bool = false) -> [ReflowBlock] {
        let body = max(4, bodySize(page.lines))
        // A rotated stamp in the outer margin is furniture, never content or a heading.
        let stamps = rotatedMarginLines(page)
        if !stamps.isEmpty {
            warnings.append(.init(code: .furnitureRemoved, page: page.number,
                message: "Rotated margin text is omitted from the reflowed text."))
        }
        let lines = page.lines.filter { line in
            !stamps.contains(line) && !images.contains { $0.0.intersects(line.rect) }
        }
        let tables = ShadedTableDetector.tables(in: page, lines: lines)
        let tableLines = tables.flatMap(\.lines)
        let free = lines.filter { line in !tableLines.contains(line) }
        // Preserve existing modest-size headings, but reject candidates within 10% of the
        // supported reflowable body size. This only narrows the original page-size heuristic.
        // Small text inside reflowed boxes and tables does not lower the body estimate, so a
        // page whose sidebar outweighs its prose keeps that prose as paragraphs (#54).
        let boxes = clusters(page.tints, distance: 4)
        let outside = free.filter { line in !boxes.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }
        let reflowBody = headingBodySize(outside, pageBody: body)
        let headingThreshold = max(body * 1.25, reflowBody * 1.1)
        // A heading line is wider than tall unless it is one or two characters; rotated text
        // outside the margin keeps its paragraph representation.
        func isHeadingSize(_ line: TextLine) -> Bool {
            !page.hasSyntheticTextStyle && line.fontSize >= headingThreshold && line.text.count < 200
                && (line.rect.width >= line.rect.height || line.text.count <= 2)
        }
        // Labels are measured against the supported reflowable body, as the threshold is, so
        // small table text cannot make a page's ordinary prose read as labels.
        // A line's tag is not part of its typography, and reconstruction drops tags as it goes
        // (`structuredOrder`, the paragraph-type rule below), so compare labels without one.
        func untagged(_ line: TextLine) -> TextLine {
            var copy = line; copy.structure = nil; return copy
        }
        let labels = sectionLabels(in: free.map(untagged), body: reflowBody,
                                   headingThreshold: headingThreshold, page: page)
        // The page's own typography for a heading, before any tag is consulted. A contents entry
        // is never a heading; a multi-line display sentence is a pull quote (handled below).
        // Neither is a separated margin line that opens or closes with this page's number:
        // that is a running head, whatever furniture removal made of it (#62).
        func headingTypography(_ line: TextLine) -> Bool {
            (isHeadingSize(line) || labels.contains(untagged(line)))
                && !isContentsEntry(line.text) && !isHeaderLike(line, in: page, bothBands: true)
        }
        let spatial = boxed(free.map { Element(rect: $0.readingRect ?? $0.rect, line: $0) }
            + images.map { Element(rect: $0.0, image: $0.1) }
            + tables.enumerated().map { Element(rect: $0.element.bounds, table: $0.offset) },
            tints: page.tints, bodySize: body)
        var elements = structuredOrder(spatial, page: page.number, warnings: &warnings)
        // A validated `P` settles grouping and reading order, not typography. Sources tag their
        // own section titles as ordinary paragraphs (the Fed's `Contents`, the FAA handbook's
        // `History of Flight`), and reading the tag literally would silently drop a navigation
        // entry that every untagged page of the same book keeps. A paragraph group set entirely
        // in heading type therefore keeps its spatial reading, but only where it introduces
        // something: the next text in its own column is ordinary text that starts no further left
        // than the group does, as a section title and the body beneath it share a column edge.
        // (The next line in reading order can belong to the other column where untagged text
        // below falls back to spatial order, as on FAA page 194.) A cover title's publication
        // label (the Fed's `PUBLIC EDUCATION & OUTREACH`) is followed by the title itself, and a
        // title page's centred imprint (Our Flag's `JOINT COMMITTEE ON PRINTING`, 61 points right
        // of the line under it) heads nothing: both stay the paragraphs they are tagged as (#67).
        // A group that reads as a multi-line display sentence is a pull quote, not a title, even
        // above the text it introduces (the Fed's chapter openers, above each chapter's contents;
        // #72): its validated paragraph stands, as the spatial pull-quote rule would read it.
        let introduces = Set(Dictionary(grouping: elements.indices.filter {
            elements[$0].line?.structure?.headingLevel == 0
        }, by: { elements[$0].line!.structure!.group }).compactMap { group, indices -> Int? in
            let lines = indices.sorted().map { elements[$0].line! }
            guard lines.allSatisfy(headingTypography),
                  pullQuoteLines(in: lines, candidates: { _ in true }).count < lines.count,
                  let last = indices.max(),
                  let left = lines.map({ $0.rect.minX }).min(), let right = lines.map({ $0.rect.maxX }).max(),
                  let next = elements[(last + 1)...].lazy.compactMap(\.line)
                    .first(where: { $0.rect.minX < right && $0.rect.maxX > left }),
                  !headingTypography(next), left <= next.rect.minX + body else { return nil }
            return group
        })
        if !introduces.isEmpty {
            for index in elements.indices {
                if let group = elements[index].line?.structure?.group, introduces.contains(group) {
                    elements[index].line?.structure = nil
                }
            }
        }
        // Page-bottom footnotes end the page's reading order; the body is every element
        // outside the note area, whose drawn separator, when it has one, is not emitted.
        // A running foot the document is too short to repeat can follow an unruled note
        // block (#61); it stays body text, ahead of the notes as captions and folios are.
        let footnotes = FootnoteDetector.layout(in: elements, page: page, continuesNote: continuesNote)
        let bodyElements = elements.indices.filter { index in
            guard let footnotes else { return true }
            return !footnotes.range.contains(index) && index != footnotes.separator
        }
        let noteLayout = NumberedNoteDetector.layout(in: elements, page: page, chapter: noteChapter)
        let noteGroups = noteLayout?.paragraphs ?? [:]
        func isHeadingCandidate(_ line: TextLine) -> Bool {
            line.structure == nil && headingTypography(line)
        }
        let quotes = pullQuoteLines(in: bodyElements.compactMap { elements[$0].line }, candidates: isHeadingCandidate)
        var result: [ReflowBlock] = []
        var note: (Int, InlineText)?
        func flushNote() {
            if let (start, text) = note {
                let key = noteLayout?.notes[start].map { NoteKey(number: $0.number, scope: .chapter($0.chapter)) }
                result.append(ReflowBlock(content: .paragraph(text), note: key, page: page.number))
            }
            note = nil
        }
        var tagged: (TextStructure, InlineText, CGFloat)?
        func flushTagged() {
            guard let (tag, text, size) = tagged else { return }
            let content: ReflowBlock.Content = tag.headingLevel == 0 ? .paragraph(text)
                : .heading(id: "heading-\(page.number)-\(result.count)", text: text, level: tag.headingLevel)
            var block = ReflowBlock(content: content, structureGroup: tag.group, page: page.number)
            block.taggedLevel = tag.headingLevel
            // A tagged heading keeps its validated level, but its typography still belongs in the
            // document-wide scale: see `rankHeadingLevels`.
            if tag.headingLevel > 0 { block.headingSize = size }
            result.append(block)
            tagged = nil
        }
        var paragraph = InlineText()
        var previous: TextLine?
        var codeOrigin: CGFloat?
        // The vertical gap the open paragraph's last line was attached at: the leading a
        // section lead-in must exceed to read as added space (#60).
        var previousGap: CGFloat?
        func flush() {
            if !paragraph.elements.isEmpty {
                result.append(ReflowBlock(content: .paragraph(paragraph), page: page.number))
            }
            paragraph = InlineText()
            previous = nil
            previousGap = nil
        }
        // A wrapped body line can begin with an initial, a citation abbreviation or a year
        // followed by a period. It continues the open paragraph only when the previous line
        // fills its column without terminal punctuation, this line sits on the column's
        // majority left edge (or outdents from an indented opening line) with ordinary line
        // spacing, and at least three same-size lines establish the column's right edge.
        // Genuine list items follow short, terminal or separated lines, or open a block of their own.
        func continuesParagraph(_ line: TextLine) -> Bool {
            guard let prev = previous, prev.wraps != false, !paragraph.elements.isEmpty,
                  line.text.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression) != nil else { return false }
            let verticalGap = prev.rect.minY - line.rect.maxY
            guard verticalGap >= -body * 0.4, verticalGap < body * 0.9 else { return false }
            let indent = prev.rect.minX - line.rect.minX
            guard indent > -body * 0.5, indent < body * 1.5 else { return false }
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard let ending = prev.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?:;".contains(ending) else { return false }
            // The previous line reads as prose; exercise or formula lines mostly carry symbols.
            let words = prev.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count
            guard words >= 3 else { return false }
            let size = Int(line.fontSize.rounded())
            let column = lines.filter {
                !$0.monospaced && Int($0.fontSize.rounded()) == size && abs($0.rect.minX - line.rect.minX) < body * 1.5
            }
            // The candidate sits on the column's majority left edge, so an indented note or
            // hanging list marker beside dedented continuations does not qualify.
            let onEdge = column.filter { abs($0.rect.minX - line.rect.minX) < body * 0.5 }.count
            guard onEdge * 2 > column.count, let right = column.map(\.rect.maxX).max() else { return false }
            // A justified column: at least three lines agree on the right edge, and so does the
            // previous line. Ragged item lengths do not establish a margin.
            let justified = column.filter { $0.rect.maxX >= right - body * 0.25 }
            return justified.count >= 3 && prev.rect.maxX >= right - body * 0.25
        }
        // A list item's marker line opens the item; its wrapped lines are set in the hanging
        // indent under the item's text, at ordinary line spacing and no larger than the item.
        // The item closes at the next marker, a paragraph gap, a dedent to the marker's edge,
        // a heading, an image, a table or a box edge, each of which another branch takes
        // first, so this line joins the open item instead of opening a paragraph (#50, #64).
        func continuesListItem(_ line: TextLine, item: (marker: TextLine, last: TextLine, indent: CGFloat?, index: Int)) -> Bool {
            guard !isList(line.text), line.fontSize <= item.marker.fontSize + 0.5 else { return false }
            let verticalGap = item.last.rect.minY - line.rect.maxY
            guard verticalGap >= -body * 0.4, verticalGap < body * 0.9 else { return false }
            // The wrapped line starts past the marker, within the width a marker occupies;
            // a deeper indent is nested content and a dedent ends the item.
            let indent = line.rect.minX - item.marker.rect.minX
            guard indent > body * 0.25, indent <= body * 2.5 else { return false }
            // Once a wrapped line has established the item's hanging indent, the rest of the
            // item sits on that same edge however its sentences fall (Fed page 22's council
            // entries run to several sentences under one marker). The edge is measured from the
            // first wrapped line, so PDFKit's few points of jitter cannot accumulate.
            if let edge = item.indent { return abs(line.rect.minX - edge) <= body * 0.5 }
            // The first wrapped line continues a marker line that ran out of room mid-sentence.
            // A marker line that ends one is as likely to be the whole item, leaving the
            // indented line under it to open a paragraph (Loper Bright page 64's wrapped
            // citation, whose next paragraph opens on a first-line indent).
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard let ending = item.last.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?".contains(ending) else { return false }
            return true
        }
        // PDFKit can detach a body note marker that falls past a justified line's right edge
        // into its own tiny line. A one-to-three digit line below body size, starting where the
        // previous line ends and sitting raised inside that line's box, is its marker. A small
        // number on the same baseline (an OCR'd table cell) is not.
        func isDetachedMarker(_ line: TextLine, after prev: TextLine) -> Bool {
            guard !paragraph.elements.isEmpty, !page.recognized, !page.hasSyntheticTextStyle,
                  (1...3).contains(line.text.count),
                  line.text.utf8.allSatisfy({ (48...57).contains($0) }),
                  line.fontSize < body * 0.8, line.rect.minX >= prev.rect.maxX - 1,
                  line.rect.minX <= prev.rect.maxX + body * 0.5 else { return false }
            return line.rect.minY >= prev.rect.minY + prev.rect.height * 0.2
                && line.rect.maxY <= prev.rect.maxY + 1
        }
        // A bold run-in section label opens a paragraph even where the source sets less than
        // the ordinary paragraph spacing between its sections (the USGS Mineral Commodity
        // Summaries add 0.3 pt, #60). The evidence is typographic and positional together: the
        // line opens with a bold run that closes with a colon or is set in capitals, ordinary
        // text follows that label on the same line (a run-in, not a heading), the previous line
        // ends a sentence, the label starts at the column's majority left edge at body size,
        // and the source still added space — the gap is not negative and exceeds the leading
        // the paragraph has been wrapping at. Bold emphasis inside a paragraph fails all of
        // these: it follows an unfinished line, sits mid-measure and adds no space.
        func opensSection(_ line: TextLine, after prev: TextLine, gap: CGFloat, leading: CGFloat?) -> Bool {
            guard !page.hasSyntheticTextStyle, line.structure == nil, !line.monospaced,
                  abs(line.fontSize - body) <= body * 0.1,
                  gap >= 0, gap >= leading.map({ $0 + body * 0.2 }) ?? 0,
                  case let .text(value, style)? = line.content.elements.first,
                  style.contains(.bold) else { return false }
            let label = value.trimmingCharacters(in: .whitespaces)
            let letters = label.filter(\.isLetter)
            guard letters.count >= 3, label.hasSuffix(":") || letters.allSatisfy(\.isUppercase),
                  line.content.elements.dropFirst().contains(where: { element in
                      guard case let .text(rest, restStyle) = element else { return false }
                      return !restStyle.contains(.bold) && rest.contains { !$0.isWhitespace }
                  }) else { return false }
            // The sentence's own last character, past closing quotes and brackets and past a
            // raised reference marker: USGS sections end `… copper supply.5` before the next
            // lead-in, and the marker is not the sentence's punctuation.
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            var ending: Character?
            for element in prev.content.elements.reversed() {
                guard case let .text(value, style) = element else { continue }
                if style.contains(.superscript), value.allSatisfy({ $0.isNumber || $0.isWhitespace }) { continue }
                if let character = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) {
                    ending = character
                    break
                }
            }
            guard let ending, ".!?".contains(ending) else { return false }
            // A section opens flush with the column the paragraph above it fills, so a run-in
            // label indented inside an item or a note is not one.
            return abs(prev.rect.minX - line.rect.minX) <= body * 0.5
        }
        // The open heading's first line (the row PDFKit split) and its latest line (for the
        // line stacked beneath it).
        var headingRow: (first: TextLine, last: TextLine)?
        // The list item this page's reading order has open: its marker line, its latest line
        // and the block holding it. Every other branch closes it, as `codeOrigin` closes a
        // code block.
        var listItem: (marker: TextLine, last: TextLine, indent: CGFloat?, index: Int)?
        for index in bodyElements {
            let element = elements[index]
            let previousHeading = headingRow
            headingRow = nil
            let openItem = listItem
            listItem = nil
            if let group = noteGroups[index], let line = element.line {
                flushTagged()
                flush()
                codeOrigin = nil
                if note?.0 != group { flushNote() }
                if let current = note {
                    note = (group, join(current.1, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings))
                } else { note = (group, line.content) }
                continue
            }
            flushNote()
            if let path = element.image {
                flushTagged()
                flush()
                codeOrigin = nil
                result.append(imageBlock(assetID: path, page: page.number))
                continue
            }
            if let index = element.table {
                flushTagged()
                flush()
                codeOrigin = nil
                result.append(ReflowBlock(content: .table(tableBlock(tables[index], vocabulary: vocabulary,
                    page: page.number, warnings: &warnings)), page: page.number))
                continue
            }
            if element.boundary {
                flushTagged()
                flush()
                codeOrigin = nil
                continue
            }
            guard let line = element.line else { continue }
            if let tag = line.structure {
                flush()
                codeOrigin = nil
                if tagged?.0.group != tag.group { flushTagged() }
                if let current = tagged {
                    tagged = (current.0, join(current.1, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings), max(current.2, line.fontSize))
                } else { tagged = (tag, line.content, line.fontSize) }
                continue
            }
            flushTagged()
            if !line.monospaced { codeOrigin = nil }
            if isHeadingCandidate(line), !quotes.contains(line) {
                // PDFKit splits a heading row at a wide gap (a section number and its title);
                // the pieces form one heading, as do the lines of a title set over several
                // lines (#55).
                if let row = previousHeading, let last = result.indices.last,
                   case let .heading(id, text, level) = result[last].content,
                   sameRow(row.first.rect, line.rect) && abs(row.first.fontSize - line.fontSize) <= line.fontSize * 0.1
                    || continuesHeading(text.text, with: line, after: row.last) {
                    result[last].content = .heading(id: id, text: join(text, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings), level: level)
                    headingRow = (row.first, line)
                    continue
                }
                flush()
                // Level 2 until the document-wide ranking runs (`rankHeadingLevels`).
                var heading = ReflowBlock(content: .heading(id: "heading-\(page.number)-\(result.count)", text: line.content),
                    page: page.number)
                heading.headingSize = line.fontSize
                result.append(heading)
                headingRow = (line, line)
            } else if !page.hasSyntheticTextStyle && line.monospaced {
                flush()
                if let origin = codeOrigin, let last = result.last, case let .preformatted(previousText) = last.content {
                    let indent = min(80, max(0, Int(((line.rect.minX - origin) / (line.fontSize * 0.6)).rounded())))
                    var combined = previousText
                    combined.append(InlineText("\n" + String(repeating: " ", count: indent)))
                    combined.append(line.content)
                    result[result.count - 1].content = .preformatted(combined)
                } else {
                    codeOrigin = line.rect.minX
                    result.append(ReflowBlock(content: .preformatted(line.content), page: page.number))
                }
            } else if isList(line.text), !continuesParagraph(line) {
                flush()
                // Preserve significant breaks and native styles; do not rewrite list markers or code.
                result.append(ReflowBlock(content: .preformatted(line.content), page: page.number))
                listItem = (marker: line, last: line, indent: nil, index: result.count - 1)
            } else if let item = openItem, continuesListItem(line, item: item),
                      case let .preformatted(text) = result[item.index].content {
                result[item.index].content = .preformatted(join(text, line.content, vocabulary: vocabulary,
                    page: page.number, warnings: &warnings))
                listItem = (marker: item.marker, last: line, indent: item.indent ?? line.rect.minX, index: item.index)
            } else {
                if let prev = previous, isDetachedMarker(line, after: prev) {
                    paragraph.append(InlineText(line.text, style: .superscript))
                    continue
                }
                // The leading this line was attached at, for the next line's section test.
                var attachedGap: CGFloat?
                if let prev = previous {
                    let verticalGap = prev.rect.minY - line.rect.maxY
                    let sameColumn = abs(prev.rect.minX - line.rect.minX) < body * 1.5
                        && verticalGap >= -body * 0.4 && verticalGap < body * 0.9
                    let shortEnding = prev.rect.width < line.rect.width * 0.65
                        && prev.text.last.map { ".!?".contains($0) } == true
                    if prev.wraps == false || !sameColumn || shortEnding
                        || opensSection(line, after: prev, gap: verticalGap, leading: previousGap) {
                        flush()
                    } else { attachedGap = verticalGap }
                }
                if paragraph.elements.isEmpty { paragraph = line.content }
                else {
                    paragraph = join(paragraph, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings)
                }
                previous = line
                previousGap = attachedGap
            }
        }
        flushNote()
        flushTagged()
        flush()
        for note in footnotes?.notes ?? [] {
            var text = FootnoteDetector.normalizedMarker(elements[note.range.lowerBound].line!.content)
            for index in note.range.dropFirst() {
                text = join(text, elements[index].line!.content, vocabulary: vocabulary,
                    page: page.number, warnings: &warnings)
            }
            // Only a numbered note has an identity a reference can cite; a lettered table
            // note (`eEstimated.`) is cited from the table, which is preserved as an image.
            var key: NoteKey?
            if case let .number(number)? = note.marker { key = NoteKey(number: number, scope: .page(page.number)) }
            result.append(ReflowBlock(content: .footnote(text), note: key, page: page.number))
        }
        return result
    }

    /// A page's first note that opens without a marker continues the previous page's last
    /// note. The note keeps its position and the page's standalone boundary moves inside it,
    /// as it does for a continued paragraph, so the page's body follows the completed note.
    /// When `appendPage` has already joined the body across the page, the boundary sits in
    /// that paragraph and the note simply absorbs the continuation.
    static func joinContinuedFootnote(_ blocks: inout [ReflowBlock], page: Int,
                                      vocabulary: Set<String>, warnings: inout [ConversionWarning]) {
        guard let index = blocks.firstIndex(where: { $0.isFootnote && $0.page == page }),
              case let .footnote(rest) = blocks[index].content, FootnoteDetector.noteMarker(of: rest) == nil,
              let start = blocks[..<index].lastIndex(where: \.isFootnote),
              case let .footnote(left) = blocks[start].content,
              blocks[start].page == page - 1 || blocks[start].sourcePages.contains(page - 1) else { return }
        let marker = blocks[start..<index].firstIndex { $0.content == .sourcePage(page) }
        blocks[start].content = .footnote(join(left, rest, vocabulary: vocabulary, page: page,
            sourceBoundary: marker == nil ? nil : page, warnings: &warnings))
        blocks.remove(at: index)
        if let marker { blocks.remove(at: marker) }
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

    /// Cell lines join like paragraph lines (spaces, hyphen repair); a section row is one cell.
    static func tableBlock(_ table: ShadedTableDetector.Table, vocabulary: Set<String>, page: Int,
                           warnings: inout [ConversionWarning]) -> ReflowBlock.Table {
        let rows = table.rows.map { row in
            ReflowBlock.Table.Row(cells: row.cells.map { cell in
                ReflowBlock.Table.Cell(text: cell.lines.dropFirst().reduce(cell.lines.first?.content ?? InlineText()) {
                    join($0, $1.content, vocabulary: vocabulary, page: page, warnings: &warnings)
                }, span: cell.span)
            }, header: row.header)
        }
        return ReflowBlock.Table(columns: table.columns, rows: rows)
    }

    static func imageBlock(assetID: String, page: Int, reference: Bool = false) -> ReflowBlock {
        let caption = reference ? "Original page \(page)" : "Preserved region from page \(page)"
        return ReflowBlock(content: .image(.init(assetID: assetID, alternativeText: caption, caption: caption)), page: page)
    }

    /// Preserve the source boundary inside a continuing paragraph, without a format-specific marker.
    ///
    /// The join anchors are the last and first body paragraphs in reading order, past preserved
    /// images, figure captions and bare folios that furniture removal kept (#45). Those blocks
    /// stay on their page, ahead of the joined paragraph. Structure groups, geometry and the
    /// preserved regions of both pages supply the evidence; see `continuation`.
    static func appendPage(_ pageBlocks: [ReflowBlock], page: PageContent, images: [CGRect] = [],
                           previousPage: PageContent?, previousImages: [CGRect] = [],
                           to blocks: inout [ReflowBlock], vocabulary: Set<String>,
                           warnings: inout [ConversionWarning]) {
        var remaining = pageBlocks
        // Text inside a tinted box (a sidebar, a figure's title band) competes with a join anchor
        // only when it is body-sized, exactly as text inside a preserved image does (#54).
        let images = images + clusters(page.tints, distance: 4)
        let previousImages = previousImages + clusters(previousPage?.tints ?? [], distance: 4)
        if let previousPage,
           let anchors = continuation(from: blocks, previousPage: previousPage, previousImages: previousImages,
                                      to: remaining, page: page, images: images),
           let left = joinableText(blocks[anchors.previous].content),
           case let .paragraph(right) = remaining[anchors.next].content {
            var joined = blocks[anchors.previous]
            let text = join(left, right, vocabulary: vocabulary, page: page.number,
                sourceBoundary: page.number, warnings: &warnings)
            // A continued list item keeps its representation; only its text grows.
            if case .preformatted = joined.content { joined.content = .preformatted(text) }
            else { joined.content = .paragraph(text) }
            // Images, captions and folios keep their place ahead of the joined paragraph. A
            // page-bottom footnote follows it instead: its reference is inside that paragraph,
            // and note text must not precede its marker (#40). It then sits past the inline
            // boundary, so page navigation reaches it from the next page.
            let trailing = Array(blocks[(anchors.previous + 1)...])
            blocks.replaceSubrange(anchors.previous..., with: trailing.filter { !$0.isFootnote } + [joined]
                + trailing.filter(\.isFootnote))
            remaining.remove(at: anchors.next)
        } else {
            blocks.append(ReflowBlock(content: .sourcePage(page.number), page: page.number))
        }
        blocks += remaining
    }

    /// The previous page's last body paragraph continues in the next page's first body paragraph
    /// only when: neither block carries a different validated paragraph identity; the next text
    /// starts lowercase and the previous text lacks terminal punctuation (past closing quotes and
    /// superscript note markers); the previous paragraph's last line fills its column and reads
    /// as prose; the next paragraph's first line is not a retained running header; and no other
    /// prose lies below or right of that last line, or above or left of that first line. Text
    /// inside a preserved region counts as prose when it is body-sized and wide, so a figure that
    /// swallowed the real neighbour blocks the join instead of corrupting the text.
    private static func continuation(from blocks: [ReflowBlock], previousPage: PageContent, previousImages: [CGRect],
                                     to pageBlocks: [ReflowBlock], page: PageContent,
                                     images: [CGRect]) -> (previous: Int, next: Int)? {
        var previous = blocks.count - 1
        // A footnote continued onto the previous page starts on an earlier one, and a join
        // moves an earlier page's footnotes behind the paragraph that continued.
        while previous >= 0, blocks[previous].page == previousPage.number
                || blocks[previous].sourcePages.contains(previousPage.number)
                || (blocks[previous].isFootnote && blocks[previous].page < previousPage.number),
              isSkippable(blocks[previous], page: previousPage) { previous -= 1 }
        guard previous >= 0, let left = joinableText(blocks[previous].content),
              blocks[previous].page == previousPage.number
                || blocks[previous].sourcePages.contains(previousPage.number) else { return nil }
        var next = 0
        while next < pageBlocks.count, isSkippable(pageBlocks[next], page: page) { next += 1 }
        guard next < pageBlocks.count, case let .paragraph(right) = pageBlocks[next].content else { return nil }
        // Two validated identities are the author's evidence of separation, but only when one of
        // them is something other than a plain paragraph: a heading, a list item, a caption. Where
        // both are paragraphs the identities say nothing, because a source may tag each page's
        // fragment of one continuing paragraph as its own `P` — the Fed does that for six of its
        // paragraphs while 22 of its groups do span a page (#67). Those fall through to the
        // geometric rule below, which already refuses every other role. One untagged side, or a
        // side whose role no group vouches for, keeps the heuristic as before.
        if let leftGroup = blocks[previous].structureGroup, let rightGroup = pageBlocks[next].structureGroup,
           leftGroup != rightGroup,
           blocks[previous].taggedLevel != 0 || pageBlocks[next].taggedLevel != 0 { return nil }
        guard right.text.first?.isLowercase == true, !endsSentence(left),
              let last = lastLine(of: left.text, in: previousPage.lines),
              let first = firstLine(of: right.text, in: page.lines),
              !isHeaderLike(first, in: page), wordCount(first.text) >= 2,
              readsAsProse(last.text), readsAsProse(first.text),
              fillsColumn(last, in: previousPage.lines, body: max(4, bodySize(previousPage.lines))),
              endsColumn(last, in: previousPage, images: previousImages),
              opensColumn(first, in: page, images: images) else { return nil }
        // A code block is preformatted because its breaks are significant; a list item is
        // preformatted because its marker is. Only the item continues as running text.
        if case .preformatted = blocks[previous].content, last.monospaced { return nil }
        return (previous, next)
    }

    /// The text a page-crossing join may continue: a body paragraph, or the wrapped line of a
    /// list item whose marker opened it on the previous page and whose text runs on (Fed's
    /// advisory-council list, pages 21 to 22). A block holding a preserved line break keeps it.
    private static func joinableText(_ content: ReflowBlock.Content) -> InlineText? {
        switch content {
        case let .paragraph(text): return text
        case let .preformatted(text): return isList(text.text) && !text.text.contains("\n") ? text : nil
        default: return nil
        }
    }

    /// Preserved images, page-bottom footnotes, figure captions and bare folios in the margin
    /// do not carry body text.
    private static func isSkippable(_ block: ReflowBlock, page: PageContent) -> Bool {
        switch block.content {
        case .image, .footnote: return true
        case .paragraph: break
        case .heading, .preformatted, .table, .sourcePage: return false
        }
        let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCaption(text) { return true }
        return isFolio(text) && page.lines.contains {
            $0.text.trimmingCharacters(in: .whitespaces) == text && inMargin($0, of: page)
        }
    }

    private static func isCaption(_ text: String) -> Bool {
        text.range(of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil
    }

    /// An Arabic page number (optionally chapter-prefixed) or a Roman numeral.
    private static func isFolio(_ text: String) -> Bool {
        !text.isEmpty && text.range(of: "^(?:[0-9]+(?:-[0-9]+)?|m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3}))$",
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func inMargin(_ line: TextLine, of page: PageContent) -> Bool {
        guard page.bounds.height > 0 else { return false }
        let position = (line.rect.midY - page.bounds.minY) / page.bounds.height
        return position <= 0.1 || position >= 0.9
    }

    /// Terminal punctuation, looking past closing quotes or brackets and superscript note markers.
    private static func endsSentence(_ text: InlineText) -> Bool {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        for element in text.elements.reversed() {
            // A linked marker is a superscript too, though linking follows every join.
            guard case let .text(value, style) = element, !style.contains(.superscript),
                  let ending = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) else { continue }
            return ".!?:".contains(ending)
        }
        return true
    }

    /// Every join appends the right-hand line verbatim, so a paragraph's last line is a suffix of
    /// its text; its first line may have lost a line-ending hyphen to the join that followed.
    private static func lastLine(of text: String, in lines: [TextLine]) -> TextLine? {
        var best: (line: TextLine, length: Int)?
        for line in lines {
            let candidate = line.text.trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty, text.hasSuffix(candidate) else { continue }
            if let current = best, current.length > candidate.count
                || (current.length == candidate.count && current.line.rect.minY <= line.rect.minY) { continue }
            best = (line, candidate.count)
        }
        return best?.line
    }

    private static func firstLine(of text: String, in lines: [TextLine]) -> TextLine? {
        var best: (line: TextLine, length: Int)?
        for line in lines {
            var candidate = line.text.trimmingCharacters(in: .whitespaces)
            if let hyphen = candidate.last, hyphen == "-" || hyphen == "\u{00ad}", !text.hasPrefix(candidate) {
                candidate.removeLast()
            }
            guard !candidate.isEmpty, text.hasPrefix(candidate) else { continue }
            if let current = best, current.length > candidate.count
                || (current.length == candidate.count && current.line.rect.maxY >= line.rect.maxY) { continue }
            best = (line, candidate.count)
        }
        return best?.line
    }

    /// A short line in a margin band that opens or closes with a page number and is separated
    /// from the text beside it is a running head that furniture removal kept
    /// (`xiv COMMISSION STAFF`, `554 NOTES TO CHAPTERS 9-10`). A paragraph's short final line at
    /// the head of a page carries no folio. `bothBands` also reads the foot of the page, which
    /// the cross-page join rule has no reason to consult: it only ever asks about a page's first
    /// line. Whatever this accepts is margin furniture and never a heading (#62).
    static func isHeaderLike(_ line: TextLine, in page: PageContent, bothBands: Bool = false) -> Bool {
        let words = line.text.split(whereSeparator: \.isWhitespace)
        guard page.bounds.height > 0 else { return false }
        let position = (line.rect.midY - page.bounds.minY) / page.bounds.height
        let top = position >= 0.9
        guard top || (bothBands && position <= 0.1), line.text.count < 100,
              let first = words.first, let last = words.last,
              isFolio(String(first)) || isFolio(String(last)) else { return false }
        let inward = page.lines.filter {
            top ? $0.rect.midY < line.rect.midY - line.rect.height * 0.4
                : $0.rect.midY > line.rect.midY + line.rect.height * 0.4
        }
        let gaps = inward.map { top ? line.rect.minY - $0.rect.maxY : $0.rect.minY - line.rect.maxY }
        guard let gap = gaps.min() else { return true }
        return gap >= max(line.rect.height, page.bounds.height * 0.012)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count
    }

    /// Letters make up at least half of a prose line's ink; inherited OCR of a scanned table
    /// row (`0 6 lip&,, tJ.() w. a,g`) does not qualify as a join anchor.
    private static func readsAsProse(_ text: String) -> Bool {
        let ink = text.filter { !$0.isWhitespace }
        return !ink.isEmpty && ink.filter(\.isLetter).count * 2 >= ink.count
    }

    /// A paragraph cut by the page ends on a full prose line. The column is the same-size lines
    /// sharing the line's left edge (widening to indented neighbours, then the page, until three
    /// lines are found). A justified column, where most lines share the right edge, demands that
    /// edge; a ragged column accepts three quarters of its measure. A line-ending hyphen is
    /// continuation evidence on its own.
    private static func fillsColumn(_ last: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        let text = last.text.trimmingCharacters(in: .whitespaces)
        if let ending = text.last, ending == "-" || ending == "\u{00ad}" { return true }
        guard wordCount(text) >= 3, last.rect.width >= body * 12 else { return false }
        let size = Int(last.fontSize.rounded())
        let sized = lines.filter { Int($0.fontSize.rounded()) == size }
        guard let edges = [0.5, 1.5, CGFloat.infinity].lazy.map({ tolerance in
            sized.filter { abs($0.rect.minX - last.rect.minX) < body * tolerance }.map(\.rect.maxX).sorted(by: >)
        }).first(where: { $0.count >= 3 }) else { return false }
        let reaching = edges.filter { $0 >= edges[0] - body * 0.5 }.count
        if reaching * 5 >= edges.count * 3 { return last.rect.maxX >= edges[0] - body * 0.5 }
        return last.rect.width >= (edges[2] - last.rect.minX) * 0.75
    }

    /// Text that competes with a join anchor: a line at least `share` of the anchor's width,
    /// except captions and margin folios; inside a preserved region it must also be the
    /// anchor's size, so figure labels do not count but swallowed body text does.
    private static func isProse(_ other: TextLine, beside line: TextLine, share: CGFloat,
                                page: PageContent, images: [CGRect]) -> Bool {
        let text = other.text.trimmingCharacters(in: .whitespaces)
        guard other != line, !text.isEmpty, other.rect.width >= line.rect.width * share,
              !isCaption(text), !(isFolio(text) && inMargin(other, of: page)) else { return false }
        guard images.contains(where: { $0.intersects(other.rect) }) else { return true }
        return Int(other.fontSize.rounded()) == Int(line.fontSize.rounded())
    }

    /// Prose below the last line, even a short swallowed line, means the paragraph did not end
    /// the page; a column of prose to its right (lines as wide as the anchor, so a name column
    /// beside a hanging-indent entry does not count) means the anchor is not the last column.
    private static func endsColumn(_ last: TextLine, in page: PageContent, images: [CGRect]) -> Bool {
        // Page-bottom footnotes (smaller type under a dash separator) are not the body's continuation.
        let separator = page.lines.filter { FootnoteDetector.isSeparator($0) && $0.rect.midY < last.rect.minY }
            .map(\.rect.minY).max()
        return !page.lines.contains { other in
            if let separator, other.rect.midY < separator, other.fontSize <= last.fontSize * 0.9 { return false }
            let below = other.rect.midY < last.rect.minY && other.rect.maxX > last.rect.minX && other.rect.minX < last.rect.maxX
            let beside = other.rect.minX >= last.rect.maxX
            return below && isProse(other, beside: last, share: 0.5, page: page, images: images)
                || beside && isProse(other, beside: last, share: 0.9, page: page, images: images)
        }
    }

    private static func opensColumn(_ first: TextLine, in page: PageContent, images: [CGRect]) -> Bool {
        !page.lines.contains { other in
            let above = other.rect.midY > first.rect.maxY && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX
            let beside = other.rect.maxX <= first.rect.minX
            return above && isProse(other, beside: first, share: 0.5, page: page, images: images)
                || beside && isProse(other, beside: first, share: 0.9, page: page, images: images)
        }
    }

    /// A numeric parenthesis marker set tight against a minus sign (`1)− 2`, as the algebra
    /// answer keys extract) is also a list item; the period form stays space-delimited so
    /// dedented note continuations such as `5.This` keep their existing handling.
    private static func isList(_ text: String) -> Bool {
        text.range(of: "^(?:(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s|[0-9]+\\)−)", options: .regularExpression) != nil
    }

    private enum JoinOperation { case space, concatenate, removeHyphen }

    private static func joinOperation(_ left: String, _ right: String, vocabulary: Set<String>, page: Int,
                                      warnings: inout [ConversionWarning]) -> JoinOperation {
        if left.hasSuffix("\u{00ad}") { return .removeHyphen }
        guard left.hasSuffix("-"), right.first?.isLowercase == true else { return .space }
        let prefix = left.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()
        let suffix = right.prefix(while: { $0.isLetter })
        let joined = (String(prefix) + suffix).lowercased()
        let compound = (String(prefix) + "-" + suffix).lowercased()
        if vocabulary.contains(joined), !vocabulary.contains(compound) { return .removeHyphen }
        if !vocabulary.contains(compound), !warnings.contains(where: { $0.code == .uncertainHyphen && $0.page == page }) {
            warnings.append(.init(code: .uncertainHyphen, page: page,
                message: "An ambiguous line-ending hyphen is retained. Review source word joins."))
        }
        return .concatenate
    }

    static func join(_ left: String, _ right: String, vocabulary: Set<String>, page: Int,
                     warnings: inout [ConversionWarning]) -> String {
        switch joinOperation(left, right, vocabulary: vocabulary, page: page, warnings: &warnings) {
        case .space: left + " " + right
        case .concatenate: left + right
        case .removeHyphen: String(left.dropLast()) + right
        }
    }

    static func join(_ left: InlineText, _ right: InlineText, vocabulary: Set<String>, page: Int,
                     sourceBoundary: Int? = nil, warnings: inout [ConversionWarning]) -> InlineText {
        var result = left
        switch joinOperation(left.text, right.text, vocabulary: vocabulary, page: page, warnings: &warnings) {
        case .space: result.append(InlineText(" "))
        case .concatenate: break
        case .removeHyphen: result.removeLastCharacter()
        }
        if let sourceBoundary { result.elements.append(.sourcePage(sourceBoundary)) }
        result.append(right)
        return result
    }
}
