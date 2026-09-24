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
        line.text.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map { vocabularyWord(String($0)) }
    }

    /// A word as the hyphen vocabulary holds it and is asked about it: lowercased, with the
    /// typographic ligatures and other compatibility glyphs a font draws resolved to the letters
    /// they stand for (#123).
    ///
    /// Wallace's text font prints `different` with a U+FB00 `ﬀ`, so the book's own words held
    /// `diﬀerent` — 56 times — and never `different`, and the vocabulary had nothing to say about
    /// `dif-` + `ferent` on pages 50 and 218. A ligature is one glyph for letters the page means,
    /// and `precomposedStringWithCompatibilityMapping` is Unicode's own statement of which
    /// characters are typographic variants of which letters, so the book's words are counted as
    /// letters and the joins are looked up as letters.
    ///
    /// This normalizes the evidence, not the book: the ligature the page prints stays in the text
    /// the reader gets, exactly as extraction read it.
    static func vocabularyWord(_ word: String) -> String {
        word.precomposedStringWithCompatibilityMapping.lowercased()
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

    /// Whether `below` finishes a word `above` broke at its line end: the next line of the same
    /// column, close beneath it, opening in lowercase where the line above ended in a hyphen or a
    /// soft hyphen. It is the evidence `HyphenRepair` joins on, read before reconstruction (#59).
    static func continuesBrokenWord(from above: TextLine, to below: TextLine) -> Bool {
        guard above.text.hasSuffix("-") || above.text.hasSuffix("\u{00ad}"),
              below.text.first?.isLowercase == true,
              abs(below.rect.minX - above.rect.minX) <= max(above.fontSize, 4) * 0.25 else { return false }
        let gap = above.rect.minY - below.rect.maxY
        let size = max(above.fontSize, 4)
        return gap >= -size * 0.2 && gap <= size * 0.8
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

    /// Whether a crop reaches into a printed row from the side rather than holding it (#207).
    ///
    /// `takes` keeps a line whose middle row a crop holds, which is right for a picture's own
    /// lettering: a diagram's labels, a chart's axis and a legend's entries stand *inside* the
    /// artwork. A page can also print its own reading across a picture's footprint. Every
    /// contents page of `noaa-nca5-2023` sets its entries from the left margin to a page number
    /// at the right edge and places a decorative line drawing over the top right corner, so the
    /// ends of the first nine entries and the numbers they run to fall inside that drawing's
    /// rectangle. No cut frees them — the drawing stands in the middle of the rows — so the crop
    /// admitted each row whole and grew across the page, and pages 9–18 lost between 57% and 82%
    /// of their characters into pictures.
    ///
    /// A printed row is one thing, so the test is the row's rather than the line's: a crop
    /// reaches into a line when that line, or another piece of the same printed row standing to
    /// its left, begins more than a point outside the crop. Reading the row keeps the two halves
    /// of a released entry together, so `Key Message 4.1. Climate Change Will Continue to Cause
    /// Profound Change` does not reflow while the `4-6` it runs to stays behind in the picture.
    /// A table's column header is that table's whatever lies across it, exactly as #257 decided
    /// for the release a crop cannot cut around: the CIA report paints a rule in the margin of
    /// page 203's third table, across a header row that begins outside it, and the header labels
    /// the columns of the picture the crop preserves.
    static func reachesInto(_ crop: CGRect, _ line: TextLine, among lines: [TextLine],
                            pictures: [CGRect], bounds: CGRect, columnHeaders: [CGRect] = []) -> Bool {
        guard pictures.contains(where: {
            $0.intersects(crop) && !PageDiagnosis.coversPage($0, bounds: bounds)
        }) else { return false }
        guard !columnHeaders.contains(line.rect) else { return false }
        // The piece that straddles the crop's edge: it begins outside the crop and runs into it.
        func straddles(_ rect: CGRect) -> Bool { rect.minX < crop.minX - 1 && rect.maxX > crop.minX + 1 }
        if straddles(line.rect) { return true }
        // Or another piece of the same printed row does, standing to this line's left. A piece
        // that stands wholly outside the crop is a cell of its own and says nothing about this
        // one: the Replay Clocks paper sets six figures in three columns on two rows and gives
        // each its own sub-caption on a shared baseline, and `(a) 𝛼 = 20 messages/s, 𝑛= 32.` is
        // the left figure's lettering, not the beginning of a row the middle figure reaches into.
        return lines.contains { other in
            straddles(other.rect) && other.rect.maxX <= line.rect.minX && sameRow(other.rect, line.rect)
        }
    }

    /// Joins an inline fraction's denominator to the line its numerator ends, as `rise/run` (#53).
    ///
    /// Wallace page 137 sets `rise` over `run` inside a sentence. PDFKit merges the numerator into
    /// the prose line, so the bar is a rule at the end of a worded line — decoration by #36's
    /// reading — and the denominator reflows on its own as a stray line. Neither preserving the
    /// whole sentence in a crop nor leaving `run` adrift says what the page says.
    ///
    /// The evidence is the bar's own geometry: a fraction bar (`isFractionBar`) lying at the end
    /// of a line that reads as a sentence, with a short line beneath it inside the bar's own
    /// measure. A display fraction, whose numerator is a line of its own rather than the tail of a
    /// sentence, is not touched and keeps its crop.
    static func joinedInlineFractions(_ lines: [TextLine], rules: [CGRect], body: CGFloat) -> [TextLine] {
        // `isFractionBar` is a display fraction's test: it requires the term above the bar to
        // carry no word of three letters, so a numerator PDFKit has merged into a sentence never
        // satisfies it. That is exactly the case here, and the geometry below stands in for it.
        let bars = rules.map { $0.insetBy(dx: 2, dy: 0) }
        guard !bars.isEmpty else { return lines }
        var denominators: [Int: Int] = [:]   // denominator line -> numerator line
        for bar in bars {
            let above = lines.indices.filter { index in
                let rect = lines[index].rect
                return bar.midY >= rect.minY && bar.midY <= rect.maxY
                    && abs(rect.maxX - bar.maxX) <= max(body, 4)
                    && readsAsSentence(lines[index])
            }
            let below = lines.indices.filter { index in
                let rect = lines[index].rect
                // The denominator's PDFKit box reaches over the bar by a fraction of a point, so
                // it is its middle that must sit beneath it.
                return rect.midY < bar.minY && rect.midY >= bar.minY - body * 1.6
                    && rect.minX >= bar.minX - 2 && rect.maxX <= bar.maxX + 2
                    && lines[index].text.split(whereSeparator: \.isWhitespace).count <= 2
            }
            if let numerator = above.first, let denominator = below.first, above.count == 1, below.count == 1 {
                denominators[denominator] = numerator
            }
        }
        guard !denominators.isEmpty else { return lines }
        var result = lines
        for (denominator, numerator) in denominators.sorted(by: { $0.key > $1.key }) {
            var joined = result[numerator].content
            joined.append(InlineText("/"))
            joined.append(result[denominator].content)
            result[numerator] = TextLine(content: joined, rect: result[numerator].rect,
                                         fontSize: result[numerator].fontSize,
                                         monospaced: result[numerator].monospaced,
                                         wraps: result[numerator].wraps)
        }
        for index in denominators.keys.sorted(by: >) { result.remove(at: index) }
        return result
    }

    /// Whether a line is running prose rather than a term: four or more words of two letters or
    /// more. A figure's label, an axis title, a formula's terms and a legend are shorter than
    /// that, which is what lets a crop tell the book's own prose from a picture's writing (#255).
    static func readsAsSentence(_ line: TextLine) -> Bool { readsAsSentence(line.text) }

    static func readsAsSentence(_ text: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
    }

    /// Whether a seed region captures a text line. Tall PDFKit line rectangles include leading,
    /// so a thin rule touches the rectangles of the lines above and below without crossing
    /// their glyphs; it captures only text it actually strikes through (#36).
    private static func captures(_ seed: CGRect, _ line: TextLine, among lines: [TextLine],
                                 pictures: [CGRect], bounds: CGRect, columnHeaders: [CGRect]) -> Bool {
        guard seed.intersects(line.rect) else { return false }
        guard isThinRule(seed) else {
            return takes(seed, line) && !reachesInto(seed, line, among: lines, pictures: pictures, bounds: bounds,
                                                columnHeaders: columnHeaders)
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
    private static func merged(_ regions: [Region], protecting prose: [TextLine]) -> [Region] {
        var result: [Region] = []
        for region in regions {
            var merged = region
            var previousCount = -1
            while previousCount != result.count {
                previousCount = result.count
                result.removeAll { existing in
                    if existing.bounds.insetBy(dx: -3, dy: -3).intersects(merged.bounds),
                       !TextBackdrop.bridgesText(existing.bounds, merged.bounds, lines: prose) {
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
    private static func expanded(_ region: Region, page: PageContent, language: String,
                                 columnHeaders: [CGRect]) -> CGRect? {
        var admitted: [CGRect] = []
        while true {
            var bounds = admitted.reduce(region.seed) { $0.union($1.insetBy(dx: -2, dy: -2)) }
                .intersection(page.bounds)
            var changed = false
            for line in page.lines where !admitted.contains(line.rect) && bounds.intersects(line.rect)
                && !OutlinedInitial.reflows(line, on: page) {
                // The other pieces of an admitted row join it, unless the crop reaches into that
                // row from the side: a page number a released contents entry runs to is the
                // entry's, not the drawing's (#207). A thin rule is narrower than the line it
                // strikes by construction, so the row test is not its.
                guard PageBackdrop.reflows(line, on: page)
                        || captures(region.seed, line, among: page.lines, pictures: page.pictures,
                                 bounds: page.bounds, columnHeaders: columnHeaders)
                        || (admitted.contains(where: { sameRow($0, line.rect) })
                            && (isThinRule(region.seed)
                                || !reachesInto(region.seed, line, among: page.lines,
                                                pictures: page.pictures, bounds: page.bounds,
                                                columnHeaders: columnHeaders))) else { continue }
                admitted.append(line.rect)
                changed = true
            }
            if changed { continue }
            let kept = admitted.reduce(region.core) { $0.union($1) }
            for line in page.lines where !admitted.contains(line.rect) && bounds.intersects(line.rect)
                && !OutlinedInitial.reflows(line, on: page) {
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
                } else if releasesProse(line, language: language, columnHeaders: columnHeaders) {
                    // A line of the book's own prose is never admitted to a crop it only touches.
                    // Where no cut clears it, the crop keeps its own extent instead of growing
                    // into it, exactly as #246's edge band does: `takes` then leaves the line in
                    // the prose, so the picture loses nothing and the sentence is not buried
                    // (#255). Three quarters of the magazine's text was inside crops.
                } else if isThinRule(region.seed)
                            || !reachesInto(bounds, line, among: page.lines, pictures: page.pictures,
                                            bounds: page.bounds, columnHeaders: columnHeaders),
                          !isEdgeBand(region.seed, bounds: page.bounds) || takes(bounds, line) {
                    admitted.append(rect)
                    changed = true
                    break
                }
                // A crop never grows sideways into a row that begins outside it either: growing
                // is what carried `noaa-nca5-2023`'s corner drawing across its contents pages
                // (#207).
                // An edge band that cannot be cut around this line keeps its own extent instead of
                // growing into it. `takes` then leaves the line in the prose, so nothing is lost
                // either way, where growing would have buried it in the crop (#246).
            }
            if changed { continue }
            return bounds
        }
    }

    /// Whether a line a crop cannot cut around is the book's own prose, which a crop never
    /// admits (#255).
    ///
    /// A line written in the Latin alphabet, in a book that declares English, must also read as
    /// English words. The CIA report's crops sit over handwritten and typewritten tables whose
    /// text layer is noise, and admitting `0/iLE 1112£ E/(19U/,£r//?/Z/` to the prose recovers
    /// nothing a reader wants. A line carrying letters of another script is released on its
    /// shape alone: an English lexicon judges nothing about a Chinese or Arabic line, and the
    /// corpus lane converts those books at library defaults, which declares English for them.
    ///
    /// A table's column header is that table's, whatever it reads as, and is never released
    /// (#257). `Number Per Cent Number Per Cent Nuntler Per Cent` and `Certain Doubtful Total
    /// Certain Doubtful Total` are every one of them an English word, so the word test admits
    /// them; they label the columns of the tables the crop preserves as pictures, and beside the
    /// picture of their own table they say nothing a reader can use.
    /// `TableRegionDetector.columnHeaders` reads which lines those are.
    static func releasesProse(_ line: TextLine, language: String, columnHeaders: [CGRect] = []) -> Bool {
        guard readsAsSentence(line) else { return false }
        guard !columnHeaders.contains(line.rect) else { return false }
        guard EnglishText.isDeclared(language), EnglishText.foreignLetters(line.text) == 0 else { return true }
        return EnglishText.readsAsWords(line.text)
    }

    /// Expand crops to whole intersecting text lines so a label cannot be cut in half.
    static func graphicsWithLabels(_ page: PageContent, language: String = "en") -> [CGRect] {
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
            func decides(_ measure: CGRect, _ text: String, _ monospaced: Bool) -> CGRect? {
                let mathematical = text.count <= 40 && !monospaced
                    && text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil
                return mathematical ? rect.union(measure) : nil
            }
            if let owner = page.lines.first(where: { line in
                rect.minX >= line.rect.minX - body && rect.maxX <= line.rect.maxX + body
                    && rect.midY >= line.rect.minY - 3 && rect.midY <= line.rect.maxY
            }) {
                return decides(owner.rect, owner.text, owner.monospaced)
            }
            // A rule no single line owns can still lie inside the measure of the printed *row*
            // it strikes through (#207). PDFKit reads a contents entry and the page number it
            // runs to as one line where the entry is short and as two where it is long, and the
            // leader between them reaches from the entry's last word to the number. Read against
            // one line, such a leader ends far beyond that line's right edge and owns nothing,
            // so every long entry of `noaa-nca5-2023`'s contents pages seeded a figure that
            // buried the entry and its number; read against its row it is the same decoration as
            // the leader of a short entry, which the line test already claimed. Two pieces at
            // least, so this reaches only rows PDFKit read apart.
            // The row is what the rule stands in: the lines it strikes through that it also
            // touches or abuts. A page sets its columns further apart than a body, so the line
            // the other column happens to set on this baseline is not in this rule's row — the
            // Replay Clocks paper's algorithm rules would otherwise be owned by the prose beside
            // them, half a page away.
            let row = page.lines.filter { line in
                rect.midY >= line.rect.minY - 3 && rect.midY <= line.rect.maxY
                    && line.rect.maxX >= rect.minX - body && line.rect.minX <= rect.maxX + body
            }
            let measure = union(row.map(\.rect))
            guard row.count >= 2, rect.minX >= measure.minX - body, rect.maxX <= measure.maxX + body else {
                return rect
            }
            // A row can only take a rule *away* as decoration, never widen it: a row's measure
            // reaches across the page's columns, and unioning a mathematical rule with it carried
            // Wallace's crops over the exercise standing beside their own. A rule the row does not
            // claim stays the isolated graphic it already was.
            return decides(measure, row.map(\.text).joined(separator: " "),
                           row.contains(where: \.monospaced)) == nil ? nil : rect
        }
        // A table this page reads as cells is not a picture (#210). #36 preserved these tables
        // because nothing downstream could carry a cell; where `TableReader` divides one, the
        // seeds that would crop it are dropped and the rows reflow as a table instead.
        let read = page.tables.map { $0.rect.insetBy(dx: -body, dy: -body) }
        let seeds = (graphics + formulas + TableRegionDetector.regions(in: page)
            + FractionRegionDetector.regions(in: page, body: body) + tables)
            .filter { seed in !read.contains { $0.contains(seed) } }
        // The column headers of the tables this page draws, which a crop never releases to the
        // prose (#257). Read once: it is a property of the page, not of any one region.
        let columnHeaders = TableRegionDetector.columnHeaders(in: page, body: body)
        let protectedProse = TextBackdrop.paragraphs(page.lines).filter { !PageBackdrop.reflows($0, on: page) }
            + TextBackdrop.galleryGutters(page.lines, pictures: page.pictures)
        let seedsGrouped = page.backdropTextPanels != nil ? PageBackdrop.clustered(seeds)
            : TextBackdrop.clustersKeepingText(seeds, lines: protectedProse, distance: 3)
        var regions = seedsGrouped.map { Region(seed: $0, bounds: $0) }
        var previous: [CGRect] = []
        while regions.map(\.bounds) != previous {
            previous = regions.map(\.bounds)
            regions = regions.compactMap { region in
                expanded(region, page: page, language: language, columnHeaders: columnHeaders)
                    .map { Region(seed: region.seed, bounds: $0) }
            }
            // A merged bounding rectangle can newly intersect a label that neither component
            // touched. Expand again before rasterizing, or its text is removed from prose while
            // the image clips part of it (for example, a raised exponent beside a fraction).
            regions = merged(regions, protecting: protectedProse)
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
        /// A table the page draws, which takes its place in the reading order as a figure does
        /// and carries its own rows (#210).
        var table: PageTable?
        var aside: [TextLine]?
        var quotation: [TextLine]?
        var pictureCaption: [TextLine]?
        var caption: [TextLine]?
        var nativePanel: [TextLine]?
        /// Native wrapped body text reflows over this preserved crop. The artwork stays
        /// visible, but its bounds must not weave independently established prose columns.
        var proseBackdrop = false
        /// A source-proved broken word widens below a panel; geometry itself stays unchanged.
        var panelContinuationFrom: CGRect?
    }

    /// Convenience for callers that do not report an abandoned cut.
    static func ordered(_ elements: [Element], bodySize: CGFloat, rightToLeft: Bool = false) -> [Element] {
        var exhausted = false
        return ordered(elements, bodySize: bodySize, rightToLeft: rightToLeft, exhausted: &exhausted)
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
    static func ordered(_ elements: [Element], bodySize: CGFloat, rightToLeft: Bool = false, depth: Int = 0,
                        exhausted: inout Bool) -> [Element] {
        guard elements.count > 1 else { return elements }
        guard depth < 32 else { exhausted = true; return elements }
        // A group the page lettered sideways is read along its own direction (#263). Every cut
        // above has already separated it from the rest of the page, so inside it the page can be
        // turned: each rectangle is taken into the frame the group's own writing runs in, where
        // the same cuts and the same row-major sort put the caption's first line above its
        // second. The turn is one rotation applied to every member, so it changes no gap, no
        // shared edge and no overlap — only which axis each of them is measured on.
        //
        // The CDC graphic novel letters page 17's caption down the side of the panel at a quarter
        // clockwise, three lines whose rectangles all reach the same top edge and stand 1.4 and
        // 2.5 points apart across the page. Read as though the writing ran along them, the
        // shortest is the topmost and comes first and the other two overlap enough to be two
        // pieces of one printed row: `ATLANTA, GEORGIA...` was emitted before
        // `DISEASE CONTROL AND PREVENTION IN SEVERAL DAYS LATER AT THE CENTERS FOR`.
        if let turn = QuarterTurn.shared(by: elements, turn: { $0.line?.turn }) {
            // The turned copies say they stand upright, so a nested group of them cannot be
            // turned a second time; only the order they come back in is kept, and every element
            // this returns is the one the caller handed over.
            var slots: [CGRect: [Int]] = [:]
            let upright = elements.indices.map { index -> Element in
                var element = elements[index]
                element.rect = turn.upright(element.rect)
                if var line = element.line {
                    line.rect = turn.upright(line.rect)
                    line.readingRect = line.readingRect.map(turn.upright)
                    line.turn = .upright
                    element.line = line
                }
                slots[element.rect, default: []].append(index)
                return element
            }
            return ordered(upright, bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1,
                           exhausted: &exhausted)
                .map { elements[slots[$0.rect]!.removeFirst()] }
        }
        /// Whether one side of a candidate gutter holds nothing but the page numbers of the
        /// entries on the other side: every element is a text piece no wider than three bodies,
        /// standing on the row of a line beside it, and reading as a number.
        ///
        /// A page number a contents entry runs its leader out to belongs to that entry, however
        /// wide the white the leader crosses, and cutting there takes every entry away from its
        /// own number. Project Blue Book sets its contents and its list of illustrations as a
        /// label, a title and a page number at the right margin, and each band read out its
        /// entries and then their numbers — `Figure 3`, `Figure 4`, both titles, then `17`, `18`,
        /// `19`, `20` (#207, #277).
        ///
        /// A number a scanned layer misread is still that page's number: the same book hands back
        /// `ti6` for 66, in a column where every other entry reads as a figure. So a token of at
        /// most six characters that holds a digit and spells no word — no run of three letters —
        /// counts as one, and a word does not. This is deliberately narrow: what it refuses is a
        /// cut between entries and their numbers, and a page's second column is prose, which
        /// fails at its first line.
        ///
        /// Every measure here is the page's own, so a line the page lettered sideways is not one
        /// of these numbers: its rectangle is as tall as the line is long and as narrow as the
        /// line is thick, which is short and on every row beside it while being neither (#263).
        func pageNumbersAlone(_ side: [Element], beside rest: [Element]) -> Bool {
            func reads(_ text: String) -> Bool {
                let token = text.trimmingCharacters(in: .whitespaces)
                if token.range(of: #"^[0-9ivxlcdmIVXLCDM]+[.,]?$"#, options: .regularExpression) != nil {
                    return true
                }
                return token.count <= 6 && token.contains(where: \.isNumber)
                    && token.range(of: #"\p{L}{3}"#, options: .regularExpression) == nil
            }
            guard !side.isEmpty, !rest.isEmpty else { return false }
            return side.allSatisfy { element in
                guard element.image == nil, element.table == nil, let line = element.line,
                      line.turn == .upright, element.rect.width <= bodySize * 3,
                      reads(line.text) else { return false }
                return rest.contains { $0.line?.turn == .upright && sameRow($0.rect, element.rect) }
            }
        }

        /// Whether one side of a candidate gutter is a stack of cells standing on the rows of
        /// the lines beside them: three or more elements, no two of them on one row, each on the
        /// row of a line on the other side, not one of them a text line of the measure a column
        /// is set to, and not one of them opening a list marker of its own.
        ///
        /// Cutting there takes every cell out of its row. The 9/11 report's appendix of names
        /// sets a name against an office on twenty-three rows, and the white between the two is
        /// 29 points, four times what a cut needs; the page reads row by row today only because
        /// PDFKit hands one of those rows back whole and that undivided line bridges the gutter.
        /// Divide it — which is the correct reading of what the page prints, and what #270's rule
        /// does on its own geometry — and every name loses its office (#283).
        ///
        /// Three rows at least, and each on its own row: two cells beside two lines are a label
        /// and a heading, which the page-number rule above already reads where they are numbers,
        /// and one element is no stack at all.
        ///
        /// And the other side must be a column: two lines of the measure a column is set to, the
        /// same substance the narrow gutter asks of both sides. Cells beside prose are that
        /// prose's rows; **two stacks of cells beside each other are two columns**, and reading
        /// them across would take each apart. The 9/11 report's own staff pages set two columns
        /// of a name over the post they held — `Joanne M. Accolla` / `Staff Assistant` down one
        /// side and `Samuel M. W. Caspersen` / `Counsel` down the other — and every one of those
        /// names is short, on its own row, and beside a line of the other column. Without this the
        /// page reads `Joanne M. Accolla`, `Samuel M. W. Caspersen`, `Staff Assistant`, `Counsel`,
        /// which is neither column.
        ///
        /// A cell the page numbered is not read here at all. **A numbered grid states its own
        /// order**, and what to do with Wallace's two-per-row exercise grids — which are cells
        /// beside cells on this test and would be reordered by it — is an owner decision taken in
        /// #195 and scoped in #219 item 4, which names the contract and the test it has to move
        /// with. Until that lands, a side any of whose cells opens a marker keeps the reading it
        /// has.
        func cellStackBesideItsRows(_ side: [Element], beside rest: [Element]) -> Bool {
            guard side.count >= 3,
                  rest.count(where: { $0.line != nil && $0.rect.width >= bodySize * 12 }) >= 2,
                  !side.contains(where: { $0.line != nil && $0.rect.width >= bodySize * 12 })
            else { return false }
            for (index, element) in side.enumerated() {
                guard element.image == nil, element.table == nil, let line = element.line,
                      line.turn == .upright, !isList(line.text),
                      !side[(index + 1)...].contains(where: { sameRow($0.rect, element.rect) }),
                      rest.contains(where: { $0.line?.turn == .upright && sameRow($0.rect, element.rect) })
                else { return false }
            }
            return true
        }

        func gap(horizontal: Bool) -> CGFloat? {
            let intervals = elements.map { horizontal ? ($0.rect.minX, $0.rect.maxX) : ($0.rect.minY, $0.rect.maxY) }
                .sorted { $0.0 < $1.0 }
            var end = intervals[0].1
            var best: (CGFloat, CGFloat)?
            for interval in intervals.dropFirst() {
                let width = interval.0 - end
                if width > bodySize * (horizontal ? 0.75 : 1.1), width > (best?.0 ?? 0) {
                    let middle = (end + interval.0) / 2
                    if horizontal {
                        let left = elements.filter { $0.rect.maxX < middle }
                        let right = elements.filter { $0.rect.minX > middle }
                        // A narrow gutter is evidence for prose columns only when both sides
                        // contain substantial text lines. Short labels and numeric answer cells
                        // need row associations; the whitespace alone must not separate them.
                        if width <= bodySize * 1.5 {
                            let proseColumns = [left, right].allSatisfy { column in
                                column.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }.count >= 2
                            }
                            if !proseColumns { end = max(end, interval.1); continue }
                        }
                        // However wide the white between them, a column of page numbers standing
                        // on the rows of the entries beside it is not a column of the page: it is
                        // where each of those entries ran its leader out to (#207, #277).
                        if pageNumbersAlone(right, beside: left) || pageNumbersAlone(left, beside: right)
                            || cellStackBesideItsRows(right, beside: left)
                            || cellStackBesideItsRows(left, beside: right) {
                            end = max(end, interval.1); continue
                        }
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
                           bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
                + [elements[divider]]
                + ordered(elements.filter { $0.rect.maxY <= rect.minY },
                          bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
        }
        if let x = gap(horizontal: true) {
            // Writing that runs right to left reads the column on the right of the gutter first
            // (#41).
            let near = elements.filter { rightToLeft ? $0.rect.minX > x : $0.rect.maxX < x }
            let far = elements.filter { rightToLeft ? $0.rect.maxX < x : $0.rect.minX > x }
            return ordered(near, bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
                + ordered(far, bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
        }
        if let y = gap(horizontal: false) {
            return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
                + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
        }
        // Every straight cut has failed. A magazine page can still state its own blocks: a column
        // that runs on into a wider measure below, around an L-shaped picture frame, leaves no
        // straight gutter to cut at, and its columns are leaded so tightly that consecutive rows
        // overlap, so there is no whitespace band either. Sorting that page's lines interleaves
        // its columns row by row. Where the page states the run-on, its columns are ordered as
        // runs instead of as lines (#174).
        if let plan = PrintedColumns.plan(elements, body: bodySize) {
            let indices = rightToLeft ? Array(plan.columns.indices.reversed()) : Array(plan.columns.indices)
            return indices.flatMap { index in
                ordered(plan.before[index] ?? [], bodySize: bodySize, rightToLeft: rightToLeft,
                        depth: depth + 1, exhausted: &exhausted)
                    + ordered(plan.columns[index], bodySize: bodySize, rightToLeft: rightToLeft,
                              depth: depth + 1, exhausted: &exhausted)
                    + ordered(plan.after[index] ?? [], bodySize: bodySize, rightToLeft: rightToLeft,
                              depth: depth + 1, exhausted: &exhausted)
            }
        }
        if let runs = columnRuns(elements, bodySize: bodySize, rightToLeft: rightToLeft) { return runs.flatMap { $0 } }
        // Every straight cut, and the column runs, have failed, and the row-major sort below would
        // weave this block's columns together. One reading is still left: a picture across the
        // block's measure with everything else on one side of it. #137's cut above asks for
        // content on both sides, because a picture at the head or the foot of a block separates
        // nothing — but it carries the whole measure with it, so while it stands in the group no
        // gutter can be found past it either. The FAA handbook opens page 391 with exactly that,
        // a full-measure chart with nothing printed above it, over two columns that then
        // interleaved row by row (#160).
        //
        // A line set across the same measure directly against the picture's edge is that
        // picture's label, and bridges the columns exactly as the picture does: cutting at the
        // picture alone leaves the caption joining them, which is what page 341 does with
        // `Figure 14-6…`, a caption 7.7 points beneath a figure that spans both columns. The band
        // grows only from the picture's own two edges, so a one-column page, whose every line
        // spans its block, gives up at most the line above and the line below — never a chain of
        // them down the page.
        //
        // It is tried last because a page the other readings already describe must keep their
        // description: the handbook's appendix of abbreviations opens under a full-measure banner
        // and sets two columns of short entries beneath it, which `columnRuns` reads as two runs
        // and this cut would leave to the row-major sort, one entry of each column at a time.
        func divides(_ band: CGRect, _ members: [Int]) -> Bool {
            let rest = elements.indices.filter { !members.contains($0) }.map { elements[$0].rect }
            return rest.allSatisfy { $0.minY >= band.maxY || $0.maxY <= band.minY }
        }
        func band(around index: Int) -> (rect: CGRect, members: [Int])? {
            let seed = elements[index].rect
            guard elements[index].image != nil, seed.width >= span.width * 0.9 else { return nil }
            var rect = seed
            var members = [index]
            for other in elements.indices where other != index {
                let label = elements[other].rect
                guard elements[other].image == nil, label.width >= span.width * 0.9,
                      label.minY <= seed.maxY + bodySize, label.maxY >= seed.minY - bodySize
                else { continue }
                let grown = rect.union(label)
                guard divides(grown, members + [other]) else { continue }
                rect = grown
                members.append(other)
            }
            return divides(rect, members) ? (rect, members) : nil
        }
        if let divider = elements.indices.lazy.compactMap(band).first {
            let rect = divider.rect
            let members = divider.members.sorted { elements[$0].rect.midY > elements[$1].rect.midY }
            return ordered(elements.filter { $0.rect.minY >= rect.maxY },
                           bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
                + members.map { elements[$0] }
                + ordered(elements.filter { $0.rect.maxY <= rect.minY },
                          bodySize: bodySize, rightToLeft: rightToLeft, depth: depth + 1, exhausted: &exhausted)
        }
        return elements.sorted {
            abs($0.rect.midY - $1.rect.midY) > bodySize * 0.4
                ? $0.rect.midY > $1.rect.midY
                : (rightToLeft ? $0.rect.maxX > $1.rect.maxX : $0.rect.minX < $1.rect.minX)
        }
    }

    /// The column runs a group's elements form, in reading order, or nil when the group states no
    /// run-on measure and the line-by-line order stands (#174).
    ///
    /// A run is one column read from its top to its bottom: each element joins the run standing
    /// directly above it, sharing at least half of the narrower measure and separated by at most
    /// a body — the same adjacency a reader follows down a column, and the same one a line of the
    /// next column fails, because that line stands beside the run rather than beneath it.
    ///
    /// The runs are then placed by the row-major order this fallback already places lines by,
    /// read off each run's own rectangle. That is what "block-level" means here: the run, not the
    /// line, is what carries a position, so a column that reaches the foot of the page is read
    /// out before the column beside it rather than woven into it.
    static func columnRuns(_ elements: [Element], bodySize: CGFloat, rightToLeft: Bool = false) -> [[Element]]? {
        let top = elements.enumerated().sorted {
            $0.element.rect.maxY != $1.element.rect.maxY
                ? $0.element.rect.maxY > $1.element.rect.maxY
                : ($0.element.rect.minX != $1.element.rect.minX
                    ? $0.element.rect.minX < $1.element.rect.minX : $0.offset < $1.offset)
        }
        var runs: [[Element]] = []
        var arrival: [Int] = []
        for (offset, element) in top {
            let rect = element.rect
            var best: (run: Int, gap: CGFloat, overlap: CGFloat)?
            for (index, run) in runs.enumerated() {
                let last = run[run.count - 1].rect
                let overlap = min(last.maxX, rect.maxX) - max(last.minX, rect.minX)
                let gap = last.minY - rect.maxY
                guard overlap >= min(last.width, rect.width) * 0.5,
                      gap <= bodySize, gap >= -bodySize else { continue }
                if best == nil || gap < best!.gap || (gap == best!.gap && overlap > best!.overlap) {
                    best = (index, gap, overlap)
                }
            }
            if let best {
                runs[best.run].append(element)
            } else {
                runs.append([element])
                arrival.append(offset)
            }
        }
        // Every run must hold at least two elements. A run of one is not a column; it is an
        // element this chaining failed to place, and a decomposition that strands one is not a
        // description of the page. Every group whose rows the page means to be read across —
        // the report's two flight timelines, its index of names against descriptions, a
        // worksheet's exercise numbers, a table's footnote marker — leaves such a run behind,
        // and is left to the row-major order those rows need (#137, #174).
        // And every run must be a column of substantial text, or a picture with what belongs to
        // it. Two bodies-wide lines are the substance a narrow gutter already demands before it
        // may be cut at, for the same reason: a stack of short cells is a table's column, whose
        // rows the page means to be read across. The report's list of illustrations sets its
        // page numbers in one such stack against their titles in another, and the census report
        // its experiment names against their results.
        let substantial = runs.allSatisfy { run in
            run.contains { $0.image != nil }
                || run.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }.count >= 2
        }
        guard runs.count > 1, runs.allSatisfy({ $0.count > 1 }), substantial,
              markersKeepTheirItems(runs, bodySize: bodySize, rightToLeft: rightToLeft),
              statesRunOnMeasure(runs, bodySize: bodySize), standApart(runs) else { return nil }
        let placed = runs.indices.sorted { first, second in
            let a = union(runs[first].map(\.rect)), b = union(runs[second].map(\.rect))
            if abs(a.midY - b.midY) > bodySize * 0.4 { return a.midY > b.midY }
            // The run on the right is read first where the writing runs that way (#41).
            if rightToLeft { if a.maxX != b.maxX { return a.maxX > b.maxX } }
            else if a.minX != b.minX { return a.minX < b.minX }
            return arrival[first] < arrival[second]
        }
        return placed.map { runs[$0] }
    }

    /// Whether every marker the page hung clear of its item keeps that item in its own run.
    ///
    /// **A bullet is never a column of its own** (#261), so a stack of them describes no column
    /// of the page, whatever it chains onto. A page that hangs its bullets clear of short items
    /// sets a column of markers beside a column of item text, and the marker run only forms at
    /// all by chaining onto the paragraph that introduces the list — each marker stands within a
    /// body beneath the run's last line and overlaps its measure — from which it borrows the
    /// substance `columnRuns` demands. That is the same thing the substance test refuses, one
    /// step removed: the run holds no substantial line of its own.
    ///
    /// Read out as columns, every marker arrives before any of its items, and nothing downstream
    /// can put them back together: #261's rule joins a marker to the piece the page set beside it
    /// on its own printed row, and by the time the markers arrive their rows are gone. The FAA
    /// handbook's page 31 reached the reader as six `<pre>` blocks holding a bullet and nothing
    /// else, followed by one paragraph holding all six items run together, and page 239 did the
    /// same with the four items of its ELT inspection list (#279).
    ///
    /// The marker and its item must be a marker and its item, not two columns: this asks
    /// `opensAloneAsBullet`, whose `hangingIndentBound` is the measured gap between the indents a
    /// page hangs a bullet across and the gutters it sets a column at. The Blue Book's bullet
    /// 12.2 bodies from the piece beside it, and the Warren Commission's at 5.2 and 8.1, are
    /// columns and are left to be read as columns.
    private static func markersKeepTheirItems(_ runs: [[Element]], bodySize: CGFloat,
                                              rightToLeft: Bool) -> Bool {
        let lines = runs.flatMap { $0 }.compactMap(\.line)
        for (index, run) in runs.enumerated() {
            for element in run {
                guard let line = element.line,
                      opensAloneAsBullet(line, in: lines, body: bodySize, rightToLeft: rightToLeft),
                      let item = pieceBeside(line, in: lines, rightToLeft: rightToLeft)
                else { continue }
                // The item is in another run: reading the runs out would separate the two.
                if runs.indices.contains(where: { $0 != index && runs[$0].contains { $0.line == item } }) {
                    return false
                }
            }
        }
        return true
    }

    /// Whether the runs stand apart: no element of one may touch an element of another. Runs that
    /// never touch are columns, and reading one out whole before the next is what a reader does
    /// with them. Runs whose elements share a row are that row, however the chaining divided
    /// them — a worked example's annotation beside its own working, a figure's labels inside the
    /// paragraph that introduces them, a column the chaining split in two — and reading those out
    /// as columns would take each row apart. This is what a run-on measure, which widens across a
    /// gutter only where the column beside it has ended, never does (#174).
    private static func standApart(_ runs: [[Element]]) -> Bool {
        for (index, run) in runs.enumerated() {
            for other in runs.indices where other > index {
                let touches = run.contains { element in
                    runs[other].contains { $0.rect.intersects(element.rect) }
                }
                if touches { return false }
            }
        }
        return true
    }

    /// Whether some run widens, part way down, into the measure another run holds: the evidence
    /// that the group is blocks rather than rows. The widening must be substantial text — more
    /// than a body past the line above it, at least twelve bodies wide, the same substance a
    /// narrow gutter demands — and must be held by at least two of the run's elements, so that a
    /// single row spanning a table's columns is not read as a column running on (#174).
    private static func statesRunOnMeasure(_ runs: [[Element]], bodySize: CGFloat) -> Bool {
        for (index, run) in runs.enumerated() {
            for position in 1..<max(run.count, 1) {
                let above = run[position - 1].rect, below = run[position].rect
                guard run[position].line != nil, below.width >= bodySize * 12 else { continue }
                let sides = [(below.minX, min(above.minX, below.maxX)), (max(above.maxX, below.minX), below.maxX)]
                for (start, end) in sides where end - start > bodySize {
                    // The measure above must be one the run kept as well. A paragraph's last line
                    // is short and the next paragraph's first line is full, which widens a run
                    // exactly as a run-on does; the difference is that the run touched the
                    // narrower measure once and holds the wider one, where a column holds the
                    // narrower measure all the way down to where it runs on.
                    guard position >= 2, run[(position - 2)..<position].allSatisfy({
                        min($0.rect.maxX, end) - max($0.rect.minX, start) <= bodySize
                    }) else { continue }
                    // And the wider measure must be one the run keeps, not one line's overhang.
                    // A justified column's lines reach its edge within a fraction of a point, so
                    // "keeps" is all but a body of the widening, not the widening exactly.
                    guard run[position...].filter({
                        min($0.rect.maxX, end) - max($0.rect.minX, start) >= end - start - bodySize
                    }).count >= 2 else { continue }
                    // And it must be a measure another run holds: that is what no gutter can cut.
                    let crowded = runs.indices.contains { other in
                        other != index && runs[other].contains {
                            min($0.rect.maxX, end) - max($0.rect.minX, start) > bodySize
                        }
                    }
                    if crowded { return true }
                }
            }
        }
        return false
    }

    /// A group's rectangles in the frame its own writing runs in, where every line of it was set
    /// at one quarter turn, and on the page otherwise (#276).
    ///
    /// `#263` reads a sideways line's order and its paragraph joins this way, and every other
    /// measure the page takes of such a line read its axis-aligned rectangle as though the writing
    /// ran along it — which makes a sideways line's length a height and its thickness a width, so
    /// the step between two lines is a column position and the page's leading is nothing. A group
    /// measure is turned only where the whole group agrees on one turn, because a rotation about
    /// the page's origin is sound only where every rectangle a rule compares carries the same one;
    /// a group holding an upright line reads on the page, as before.
    static func ownFrame(of lines: [TextLine]) -> (TextLine) -> CGRect {
        guard QuarterTurn.shared(by: lines, turn: { $0.turn }) != nil else { return { $0.rect } }
        return { $0.uprightRect }
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

    /// The leading a page's own text states: the commonest distance between the tops of two
    /// vertically adjacent lines set at one size in one column, to the nearest half point, or nil
    /// where the page prints too few such pairs to state one (#123).
    ///
    /// Tops, not baselines and not the gap between the rectangles: PDFKit's line rectangle grows
    /// downwards by the descenders the line happens to carry, so on Wallace's page 64 the item
    /// `• More than often represents addition and is usually built backwards,` has a rectangle
    /// 20.46 points tall where the line beneath it has 11.98, and the gap between the two is
    /// negative although the page set them one line apart. The tops of two lines of one size are
    /// one ascent above their baselines, so their distance is the leading.
    ///
    /// The page's own leading is the measure of extra space, and pages differ: the same ten points
    /// of white is nothing under 24-point display type and a paragraph break under six-point
    /// footnotes.
    static func statedLeading(_ lines: [TextLine]) -> CGFloat? {
        let candidates = lines.filter { !$0.monospaced && !$0.text.isEmpty }
        let body = max(4, bodySize(lines))
        // In the frame the page's own writing runs in: on a page whose lines all stand at one
        // quarter turn, the step from one line to the next runs down the writing and not down the
        // page, and measured on the page it is a column position (#276, #263).
        let frame = ownFrame(of: candidates)
        var counts: [Int: Int] = [:]
        for line in candidates {
            // The nearest line below this one in its own column, at its own size: the line the
            // page would have set on its leading. A second column's lines stand elsewhere and
            // are never this line's neighbour.
            let below = candidates.filter {
                frame($0).maxY < frame(line).maxY && $0.hasSize(line.fontSize)
                    && abs(frame($0).minX - frame(line).minX) < body * 1.5
            }.max { frame($0).maxY < frame($1).maxY }
            guard let below else { continue }
            let step = frame(line).maxY - frame(below).maxY
            guard step > 0, step <= body * 3 else { continue }
            counts[Int((step * 2).rounded()), default: 0] += 1
        }
        // A tie goes to the closer spacing, so one page cannot reflow two ways from one run to the
        // next on Swift's per-process dictionary seed (#140), as `bodySize` is careful about too.
        guard let stated = counts.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }),
              stated.value >= minimumStatedLeadingEvidence else { return nil }
        return CGFloat(stated.key) / 2
    }

    /// How many pairs of lines must agree before a page has stated its leading. Four is the
    /// shortest run of prose that says anything: three wrapped lines of one paragraph and one
    /// more pair anywhere else on the page.
    static let minimumStatedLeadingEvidence = 4

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
        // Two lines the page set at one quarter turn stack along their own writing, not down the
        // page: what stands under a sideways heading is the line beside it (#276, #263).
        let (above, below) = previous.turn == line.turn
            ? (previous.uprightRect, line.uprightRect) : (previous.rect, line.rect)
        guard abs(previous.fontSize - line.fontSize) <= size * 0.1, !previous.sharesRow(with: line),
              below.minY < above.minY, below.maxY >= above.minY - size,
              above.minY - below.minY <= size * 2.2 else { return false }
        return abs(above.minX - below.minX) <= size * 0.6
            || abs(above.midX - below.midX) <= size * 0.6
            || abs(above.maxX - below.maxX) <= size * 0.6
    }

    /// A painted 1-pt rule after graphics padding: an underline or a separator, never a figure on
    /// its own (#218, ported unchanged from the coordination branch's `isThinRule`, #100).
    static func isThinRule(_ rect: CGRect) -> Bool {
        rect.height <= 6 && rect.width >= max(12, rect.height * 3)
    }

    /// A figure or table caption's opening label (#218, ported unchanged from the coordination
    /// branch's `isCaption`, #97): a caption is never the title of the text beneath it, and a
    /// sub-heading is never a caption's own label.
    static func isCaption(_ text: String) -> Bool {
        text.range(of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil
    }

    /// The page's ordinary line height at a size: the median height of its lines of that size
    /// (#218, ported unchanged from the coordination branch).
    private static func ordinaryLineHeight(_ size: CGFloat, in lines: [TextLine]) -> CGFloat? {
        let frame = ownFrame(of: lines)
        let heights = lines.filter { $0.hasSize(size) }.map { frame($0).height }.sorted()
        return heights.isEmpty ? nil : heights[heights.count / 2]
    }

    /// The height of an ordinary line of each type size the page sets: the lower quartile of the
    /// heights of its lines at that size, by rounded size.
    ///
    /// PDFKit gives a line the height of the tallest glyph on it rather than the line's own
    /// extent, so a line of running prose carrying one inline radical is reported 20.46 points
    /// high where its neighbours are 11.98 and its rectangle reaches six points into the line
    /// beneath it (#230, #213; drafted for Apple as
    /// `measurements/apple-feedback-line-heights/report.md`). The page's own lines say what an
    /// ordinary one of that size measures, and the lower quartile rather than the median because
    /// a page of mathematics sets more tall lines than short ones.
    static func ordinaryLineHeights(in lines: [TextLine]) -> [Int: CGFloat] {
        let frame = ownFrame(of: lines)
        var heights: [Int: [CGFloat]] = [:]
        for line in lines { heights[Int(line.fontSize.rounded()), default: []].append(frame(line).height) }
        return heights.compactMapValues { sizes in
            let sorted = sizes.sorted()
            return sorted.isEmpty ? nil : sorted[sorted.count / 4]
        }
    }

    /// The page's ordinary gap between wrapped lines at a size: the lower quartile, over lines of
    /// that size and ordinary height, of the gap to the nearest such line directly beneath on the
    /// same left edge (within half a body) inside the prose window (#218, ported unchanged from the
    /// coordination branch's `ordinaryLineGap`, #159).
    private static func ordinaryLineGap(_ size: CGFloat, in lines: [TextLine], body: CGFloat) -> CGFloat? {
        guard let height = ordinaryLineHeight(size, in: lines) else { return nil }
        let frame = ownFrame(of: lines)
        let ordinary = lines.filter { $0.hasSize(size) && frame($0).height <= height + body * 0.25 }
        let gaps = ordinary.compactMap { upper -> CGFloat? in
            ordinary.compactMap { lower -> CGFloat? in
                let gap = frame(upper).minY - frame(lower).maxY
                guard lower != upper, abs(frame(upper).minX - frame(lower).minX) <= body * 0.5,
                      gap >= -body * 0.4, gap < body * 0.9,
                      frame(lower).midY < frame(upper).midY else { return nil }
                return gap
            }.min()
        }.sorted()
        return gaps.isEmpty ? nil : gaps[gaps.count / 4]
    }

    /// The wrapped second line of each entry a page hangs, by the entry line it carries on (#160).
    ///
    /// Project Blue Book's list of illustrations sets each entry's title from its own left margin
    /// and hangs the wrap 48.5 points in, at 7.8-point type — six times the size, where
    /// `BlockAssembler.continuesParagraph` allows two lines of one column one and a half bodies.
    /// So thirty entries reflowed as sixty paragraphs, each cut where the page wrapped it, with
    /// the page numbers read afterwards in their own column and nothing between the halves.
    ///
    /// The indent alone proves nothing: a book that opens its paragraphs on a first-line indent
    /// sets the same two edges in the same alternation, and `firstLineIndentRun` reads the Blue
    /// Book's list as one. What separates them is what the entry line itself does. A paragraph
    /// ends on a short line that has run out of words; an entry that wrapped ran out of room. So
    /// the page must state all of this, and the rule speaks only where the column test is silent:
    ///
    /// - the wrap stands directly beneath the entry, at its size, on the page's own leading, and
    ///   set in further than the column window the ordinary test already covers;
    /// - the entry reads as a sentence, fills its measure — at least twelve of its own sizes —
    ///   and ends no sentence (past closing quotes and brackets), so it broke for want of room
    ///   and not because it was finished, which is what the last line of a paragraph above an
    ///   indented opening is;
    /// - the wrap carries at least two letters and stops a whole body short of the entry's right
    ///   edge, as the tail of an entry does and a justified opening line does not. Project Blue
    ///   Book's inherited layer merges the rule printed down its margin into the line beside it
    ///   (#216), which leaves both lines ending at the same margin and their boxes a type size
    ///   too tall; that is how page 22's hanging definitions looked like entries and their wraps;
    /// - the page hangs at least three entries on one and the same continuation edge, so a single
    ///   indented line is never read as a wrap.
    static func hangingEntries(in lines: [TextLine], body: CGFloat) -> [CGRect: CGRect] {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        // Every measure below — the step to the wrap, the indent it hangs at, the measure the
        // entry fills, the edge the page hangs them all on — runs along the writing, so on a page
        // whose lines all stand at one quarter turn it is read in that frame (#276, #263).
        let frame = ownFrame(of: lines)
        var candidates: [(wrap: TextLine, entry: TextLine)] = []
        for line in lines where !line.monospaced && !isList(line.text) {
            let size = max(line.fontSize, 4)
            let above = lines.filter { other in
                other != line && !other.monospaced && other.hasSize(line.fontSize)
                    && other.overlapsHorizontally(line) && !other.sharesRow(with: line)
                    && frame(other).midY > frame(line).midY
            }.min { frame($0).minY < frame($1).minY }
            guard let entry = above, entry.wraps != false else { continue }
            let gap = frame(entry).minY - frame(line).maxY
            guard gap >= -body * 0.4, gap < body * 0.9,
                  frame(line).minX - frame(entry).minX > body * 1.5,
                  frame(line).maxX <= frame(entry).maxX - body,
                  line.text.count(where: \.isLetter) >= 2,
                  frame(entry).width >= size * 12, readsAsSentence(entry),
                  let ending = entry.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?:;".contains(ending) else { continue }
            candidates.append((line, entry))
        }
        var edges: [Int: [(wrap: TextLine, entry: TextLine)]] = [:]
        for candidate in candidates {
            edges[Int((frame(candidate.wrap).minX / max(body, 4) * 2).rounded()), default: []].append(candidate)
        }
        var result: [CGRect: CGRect] = [:]
        for hung in edges.values where hung.count >= 3 {
            for candidate in hung { result[candidate.wrap.rect] = candidate.entry.rect }
        }
        return result
    }

    /// The list a page hangs under an outdented marker column, as the lines that open its
    /// entries and the edge it sets their text on — or nil where the page sets no such list
    /// (#282).
    ///
    /// A reference list is one entry per citation: the number outdented into the margin, the
    /// entry's own text on the marker's row, and every line the page wraps beneath it standing on
    /// that text's edge. Nothing in the page's geometry alone says so. The ordinary column test
    /// allows two lines of one column one and a half bodies, and these entries hang further —
    /// 1.35 bodies in the Replay Clocks paper, 2.37 in the Census paper — so each wrap opened a
    /// paragraph of its own. `hangingEntries` (#160) reads a hung wrap from the entry above it,
    /// but asks that the wrap stop a body short of the entry's right edge, which a *justified*
    /// reference list never does: both lines reach the margin. And where the extractor kept the
    /// marker apart, as it does for six of Replay Clocks' twelve entries and eight of the
    /// Census's fourteen, the number stood 12 to 21 points from its own text, past the gutter two
    /// pieces of one row are joined within, and joined the paragraph *above* it instead — so page
    /// 10 read `… Department of Computer Science, 1988. [8]` and opened the next paragraph on
    /// `D. L. Mills. …`.
    ///
    /// What states the list is the marker column itself, which is stronger evidence than any
    /// measure of one wrap: the page sets three or more markers outdented from one edge, each
    /// with its entry beside it on its own row, and hangs at least one unmarked line on that
    /// edge. A page that does that has told the reader where every entry begins, and the lines
    /// between two markers are one entry whatever their measure.
    ///
    /// Only a bracketed number is read here — `[8]`, `[ 12]` — which is what both pages of #282
    /// print. The marker shapes `isList` already reads (`8.`, `a)`) are deliberately left out:
    /// they open the numbered items, headings and worked steps this library reads other ways, and
    /// what they would settle is #171's own reference lists, measured there.
    static func hangingMarkerList(in lines: [TextLine], body: CGFloat)
        -> (openings: Set<CGRect>, edge: CGFloat)? {
        /// The whole of a line, or the token it opens, is `[` a number `]`.
        func marks(_ text: String, whole: Bool) -> Bool {
            text.range(of: whole ? #"^\[\s*[0-9]+\s*\]$"# : #"^\[\s*[0-9]+\s*\]\s"#,
                       options: .regularExpression) != nil
        }
        // The markers the extractor kept apart, with the entry each stands beside. The entry has
        // to be an entry: a line of text, not a cell of a row the page set in two columns.
        var separated: [(marker: TextLine, entry: TextLine)] = []
        for line in lines where !line.monospaced && marks(line.text, whole: true) {
            guard let entry = pieceBeside(line, in: lines),
                  !entry.monospaced, entry.rect.width >= body * 12 else { continue }
            let indent = entry.rect.minX - line.rect.minX
            guard indent >= body * 0.5, indent <= body * 3 else { continue }
            separated.append((line, entry))
        }
        // The edge those entries agree on, and the marker column's own reach from it.
        var edges: [Int: [(marker: TextLine, entry: TextLine)]] = [:]
        for pair in separated {
            edges[Int((pair.entry.rect.minX / max(body, 4) * 4).rounded()), default: []].append(pair)
        }
        guard let hung = edges.values.max(by: { $0.count < $1.count }), hung.count >= 2 else { return nil }
        let edge = hung.map(\.entry.rect.minX).reduce(0, +) / CGFloat(hung.count)
        // Every marker of that column, including the ones the extractor handed back with their
        // entry's first words already attached.
        var openings = Set(hung.map(\.marker.rect))
        for line in lines where !line.monospaced && marks(line.text, whole: false) {
            let indent = edge - line.rect.minX
            if indent >= body * 0.5, indent <= body * 3 { openings.insert(line.rect) }
        }
        guard openings.count >= 3 else { return nil }
        // And the page hangs something on that edge: a line standing there that opens no entry of
        // its own is a wrap, which is the whole reason this rule exists. A column of one-line
        // cells beside a column of numbers states no hang and is left to the table readers.
        let hangs = lines.contains { line in
            abs(line.rect.minX - edge) <= body * 0.25 && !openings.contains(line.rect)
                && !hung.contains { $0.entry.rect == line.rect }
        }
        return hangs ? (openings, edge) : nil
    }

    /// Where on a page the extractor left the same seam on row after row: the x positions at
    /// which three or more printed rows were split, within a quarter of a body of one another.
    ///
    /// PDFKit ends a line wherever the page leaves a gap, and a page that leaves one in the same
    /// place on row after row has set a column there. The pieces beside such a seam are cells,
    /// and the start of the row they stand in says nothing about the row beneath it: Project Blue
    /// Book's statistical appendix hands back eight-column tables whose rows all break at the
    /// same places, and reading each row as one line ran thirty of them together. A page that
    /// breaks one row at a place no other row breaks at has set a space, not a column — the 9/11
    /// report's page 259, the replay-clocks paper and USCIS M-618-A each split a row where
    /// nothing else on the page splits (#272).
    ///
    /// Three rows are what it takes to say so. Two rows that happen to break near one place are
    /// two printed lines — USCIS M-618-A's page 47 breaks two of its sentences within a fifth of
    /// a point of x 319.7 and a third 4.5 points away, and all three are prose.
    static func columnSeams(in lines: [TextLine], body: CGFloat, rightToLeft: Bool) -> [CGFloat] {
        var seams: [CGFloat] = []
        for line in lines {
            let opens = lines.contains { other in
                other != line && TextLine.sameRow(other.uprightRect, line.uprightRect) && {
                    let gap = rightToLeft
                        ? other.uprightRect.minX - line.uprightRect.maxX
                        : line.uprightRect.minX - other.uprightRect.maxX
                    return gap >= 0 && gap < body * 0.75
                }()
            }
            if opens { seams.append(rightToLeft ? line.uprightRect.maxX : line.uprightRect.minX) }
        }
        return seams.filter { seam in seams.count { abs($0 - seam) <= body * 0.25 } >= 3 }
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
            bold = readsWhollyBold(line)
        }
    }

    /// Whether every run of the line that holds a mark is bold: the weight PDFKit reports for a
    /// line, where it reports one.
    static func readsWhollyBold(_ line: TextLine) -> Bool {
        line.content.elements.allSatisfy { element in
            guard case let .text(value, style) = element else { return true }
            return style.contains(.bold) || value.allSatisfy(\.isWhitespace)
        }
    }

    /// A bold sub-heading the book sets at or near its body size, whose paragraph opens directly
    /// beneath it or past an intervening picture and its caption (#218; adapted from the
    /// coordination branch's `sectionLabels` and its `opens(beneath:)`/`pastFigure(_:)`, themselves
    /// built up across #43, #63, #73, #76, #90, #97, #100, #102, #159 and #186). Main has no heading
    /// tiers and no tinted-box detection (`page.tints`, #100's `boxTitles`), so only the bold,
    /// body-adjacent path is ported. *Agricultural Research*'s "Fighting Filth Flies" supplies
    /// the single-line source case (#218); its pages 6, 7 and 17 also qualify compact stacked
    /// labels under the same evidence (#214). Italic labels, hanging-entry titles and tinted
    /// boxes remain outside this rule's qualified source coverage.
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
                              recordingSubheadings: Bool = false, joiningStackedLabels: Bool = true) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        let stacked = joiningStackedLabels ? StackedSectionLabels.groups(in: lines, body: body) : []
        if !stacked.isEmpty {
            let claimed = Set(stacked.flatMap(\.indices))
            let merged = lines.enumerated().filter { !claimed.contains($0.offset) }.map(\.element)
                + stacked.map(\.line)
            let labels = sectionLabels(in: merged, body: body, headingThreshold: headingThreshold,
                                       page: page, styles: styles, recordingSubheadings: recordingSubheadings,
                                       joiningStackedLabels: false)
            return labels.flatMap { label in
                stacked.first(where: { $0.line == label }).map { $0.indices.map { lines[$0] } } ?? [label]
            }
        }
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
    /// language, the document's body size and recurring sub-heading styles (#186, #218), the
    /// heading sizes the book's own tags rank (#294), and the pages whose numbered-note heading
    /// extraction recognized.
    struct DocumentContext: Sendable {
        var hyphens = HyphenContext()
        var language = "en"
        var documentBody: CGFloat?
        var labelStyles: Set<LabelStyle> = []
        var headingRank = HeadingRank()
        var numberedNotePages: Set<Int> = []
    }

    /// One type size, to the half point: the grain at which two lines of a page are set in the
    /// same display type. `LabelStyle` already reads a page's typography at this grain, and
    /// `HeadingRank` ranks the book's at it.
    static func sizeKey(_ size: CGFloat) -> Int { Int((size * 2).rounded()) }

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
    /// Size alone, without a tagged heading at that size, is not enough: it would promote Our
    /// Flag page 3's imprint ("JOINT COMMITTEE ON PRINTING", "WASHINGTON : 2003") and the Fed
    /// cover's "PUBLIC EDUCATION & OUTREACH", whose sizes no tag on their own pages calls a
    /// heading and which head nothing. The FAA handbook — whose 171 headings the rule above
    /// protects — cannot reach this rule at all, because no FAA page's tags name a heading
    /// (#67, #91).
    ///
    /// Where the page's own tags state nothing about a size, the book's do (`rank`, #294): IRS
    /// Publication 596's cover tags `目录` a paragraph in fifteen-point type beside a seventeen-point
    /// `H1`, and the book's other pages tag seventeen and eighteen points `H1` and fourteen `H2`,
    /// so a fifteen-point line is a heading by the book's own ranking and takes the level of the
    /// largest tagged size not above it. The rank speaks only at or above its floor — *Our
    /// Flag*'s imprint stays under that book's — and only to a line that heads something: a
    /// display line whose nearest line beneath, in its own column, is set larger is a label
    /// standing over a title (`standsOverLargerDisplay`), and its paragraph role is believed.
    /// The same cover prints `596 号刊物` in the same fifteen points over its thirty-one-point
    /// title, and the Fed cover its fourteen-point series name over a forty-point one; the book
    /// ranks the size, the page says what the line stands over, and both are read.
    static func contradictedHeadingGroups(_ elements: [Element], roles: [LineRole?],
                                          rank: HeadingRank = HeadingRank()) -> [Int: Int] {
        var tagged: [Int: Int] = [:]
        for element in elements {
            guard let line = element.line, let tag = line.structure, tag.headingLevel > 0 else { continue }
            let key = sizeKey(line.fontSize)
            tagged[key] = min(tagged[key] ?? tag.headingLevel, tag.headingLevel)
        }
        guard !tagged.isEmpty else { return [:] }
        let lines = elements.compactMap(\.line)
        var promoted: [Int: Int] = [:]
        var lengths: [Int: Int] = [:]
        var refused: Set<Int> = []
        for (index, element) in elements.enumerated() {
            guard let line = element.line, let tag = line.structure, tag.headingLevel == 0 else { continue }
            guard roles[index] == .heading,
                  let level = tagged[sizeKey(line.fontSize)] ?? rankedLevel(of: line, among: lines, rank: rank) else {
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

    /// The level the book's rank gives a line whose size the page's own tags never call a
    /// heading, unless the line stands over a larger display line (#294).
    private static func rankedLevel(of line: TextLine, among lines: [TextLine], rank: HeadingRank) -> Int? {
        guard let level = rank.level(of: line), !standsOverLargerDisplay(line, among: lines) else { return nil }
        return level
    }

    /// Whether the nearest line beneath this one in its own column is set larger than it: a
    /// label standing over a title, which heads nothing because what stands beneath it outranks
    /// it. IRS Publication 596's cover prints `596 号刊物` in fifteen-point type over its
    /// thirty-one-point title, and *The Fed Explained*'s prints `PUBLIC EDUCATION & OUTREACH` in
    /// fourteen over its forty-point one: a publication's number and a series name, each set in
    /// a heading's size and tagged a paragraph. `目录` and `Advisory Councils` on the same two
    /// books stand over their own ten-point text (#294).
    ///
    /// The line beneath is the one whose top is highest among those whose middle lies below this
    /// line's bottom and that share some of its horizontal extent; a line the page set at a
    /// quarter turn is measured in its own frame, as `stacksUnderHeading` measures it (#263).
    static func standsOverLargerDisplay(_ line: TextLine, among lines: [TextLine]) -> Bool {
        func frame(_ other: TextLine) -> CGRect { other.turn == line.turn ? other.uprightRect : other.rect }
        let own = frame(line)
        let beneath = lines.filter { other in
            other != line && other.overlapsHorizontally(line) && frame(other).midY < own.minY
        }.max { frame($0).maxY < frame($1).maxY }
        guard let beneath else { return false }
        return sizeKey(beneath.fontSize) > sizeKey(line.fontSize)
    }

    /// A table's own numbered title, sharing its left edge above its explanatory lines. The
    /// semantic grid supplies the relationship; a body-sized "Table N." elsewhere does not.
    static func tableTitles(in lines: [TextLine], tables: [PageTable], body: CGFloat) -> [TextLine] {
        tables.compactMap { table in
            lines.filter { line in
                line.text.range(of: #"^Table\s+\d+[.:]"#, options: .regularExpression) != nil
                    && abs(line.rect.minX - table.rect.minX) <= body
                    && line.rect.minY >= table.rect.maxY
                    && line.rect.minY - table.rect.maxY <= body * 10
                    && line.rect.width <= table.rect.width + body
            }.min { $0.rect.minY < $1.rect.minY }
        }
    }

    /// A semantic table owns its numbered title and aligned introduction above the cell grid.
    /// Decorative paint can overlap this text without turning it into figure lettering.
    static func tableIntroductions(in lines: [TextLine], tables: [PageTable], body: CGFloat) -> Set<CGRect> {
        var result: Set<CGRect> = []
        for table in tables {
            guard let title = tableTitles(in: lines, tables: [table], body: body).first else { continue }
            result.insert(title.rect)
            for line in lines where line.rect.maxY <= title.rect.minY + 1
                && line.rect.minY >= table.rect.maxY
                && abs(line.rect.minX - title.rect.minX) <= body * 0.5
                && line.rect.maxX <= table.rect.maxX + body
                && line.fontSize <= title.fontSize * 1.1 {
                result.insert(line.rect)
            }
        }
        return result
    }

    /// Repeated label/value pairs state a break even when both lines use the same type (#215).
    /// At least three short labels must stand over wider values at one gap and one left edge;
    /// a larger gap above each label marks the pair's start. Ordinary prose fills its measure
    /// instead, and a single short line is not evidence for changing any paragraph.
    static func labelValueStarts(in lines: [TextLine]) -> Set<CGRect> {
        guard lines.count <= 2_000 else { return [] }
        let candidates = lines.filter { !$0.monospaced && $0.turn == .upright && $0.fontSize >= 4 }
        var pairs: [(label: TextLine, value: TextLine, gap: CGFloat)] = []
        for label in candidates where label.text.split(whereSeparator: \.isWhitespace).count <= 6
            && label.text.last.map({ !".!?;,:".contains($0) }) == true {
            let size = label.fontSize
            let edge = candidates.filter { abs($0.rect.minX - label.rect.minX) <= size * 0.2
                && $0.hasSize(size) }
            guard let value = edge.filter({ $0.rect.maxY < label.rect.maxY }).max(by: { $0.rect.maxY < $1.rect.maxY }),
                  label.rect.width <= value.rect.width * 0.8 else { continue }
            let gap = label.rect.minY - value.rect.maxY
            guard gap >= size * 0.2, gap <= size * 0.6 else { continue }
            if let above = edge.filter({ $0.rect.minY > label.rect.minY }).min(by: { $0.rect.minY < $1.rect.minY }),
               above.rect.minY - label.rect.maxY < gap + size * 0.5 { continue }
            pairs.append((label, value, gap))
        }
        return Set(pairs.filter { pair in
            pairs.count { other in
                abs(other.label.rect.minX - pair.label.rect.minX) <= pair.label.fontSize * 0.2
                    && other.label.hasSize(pair.label.fontSize)
                    && abs(other.gap - pair.gap) <= pair.label.fontSize * 0.1
            } >= 3
        }.map { $0.value.rect })
    }

    /// One page's logical blocks: its typography is read once, every line outside a tagged or
    /// numbered-note group is classified by `role(of:)`, and `BlockAssembler` builds the blocks.
    static func blocks(page: PageContent, images: [(CGRect, String)], context: DocumentContext,
                       warnings: inout [ConversionWarning]) -> [ReflowBlock] {
        // A crop takes every line it intersects, except a wrapped paragraph the page prints over
        // one of its own pictures, which is the book's prose and no cut can free (#239).
        let displayTypography = PageTypography(page: page)
        let displayed = page.hasSyntheticTextStyle ? [] : DisplayQuotation.groups(in: page.lines,
            body: displayTypography.body, threshold: displayTypography.headingThreshold)
        let nativeCaptions = page.hasSyntheticTextStyle ? [] : CaptionParagraphs.groups(lines: page.lines,
            pictures: page.pictures + images.map(\.0), body: displayTypography.body)
        let captionIndices = nativeCaptions.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
        let displayedIndices = displayed.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
        let overPicture = displayedIndices.union(captionIndices).union(PageDiagnosis.proseOverPictures(lines: page.lines, pictures: page.pictures + (page.nativeTextPanels ?? []),
                                                          crops: images.map(\.0), bounds: page.bounds,
                                                          language: context.language,
                                                          nativeTypography: !page.recognized && !page.hasSyntheticTextStyle))
        // A crop must not take one half of a word whose other half falls outside it. Replay Clocks
        // page 8 breaks a figure caption `…𝛼 = 40 mes-` / `sages/second.` and the crop's edge fell
        // 0.49 pt above the second line, so the first half went into the picture and the second
        // reflowed alone between two figures. Releasing the half the crop took lets the two rejoin
        // as the caption they are (#59).
        // A crop also does not take a printed row that begins outside it and reaches in: the
        // page prints that row, the picture merely lies across its end (#207).
        let columnHeaders = TableRegionDetector.columnHeaders(in: page, body: max(4, bodySize(page.lines)))
        let tableIntroductions = tableIntroductions(in: page.lines, tables: page.tables,
                                                    body: max(4, bodySize(page.lines)))
        let taken = Set(page.lines.indices.filter { index in
            !tableIntroductions.contains(page.lines[index].rect) && !overPicture.contains(index) && page.sidebarValueRows?.contains(page.lines[index].rect) != true
                && !PageBackdrop.reflows(page.lines[index], on: page)
                && !OutlinedInitial.reflows(page.lines[index], on: page) && images.contains {
                takes($0.0, page.lines[index])
                    && !reachesInto($0.0, page.lines[index], among: page.lines, pictures: page.pictures,
                                    bounds: page.bounds, columnHeaders: columnHeaders)
            }
        })
        let released = Set(taken.filter { index in
            guard index + 1 < page.lines.count, !taken.contains(index + 1) else { return false }
            return continuesBrokenWord(from: page.lines[index], to: page.lines[index + 1])
        })
        // A table read as cells claims the lines it covers: they are emitted once, inside the
        // table, and reflowing them again beside it would print the page's numbers twice (#210).
        let tableRects = page.tables.map { $0.rect.insetBy(dx: -1, dy: -1) }
        let reflowable = page.lines.enumerated().filter { index, line in
            (!taken.contains(index) || released.contains(index))
                && !tableRects.contains { $0.contains(line.rect) }
        }.map(\.element)
        // An inline fraction's denominator joins the line its numerator ends (#53).
        var lines = joinedInlineFractions(reflowable, rules: page.graphics.filter(isThinRule),
                                          body: max(4, bodySize(page.lines)))
        let typography = PageTypography(pageLines: page.lines, reflowableLines: lines, documentBody: context.documentBody,
                                        nativeSizeEvidence: !page.recognized && !page.hasSyntheticTextStyle)
        // A bold sub-heading set at or near body size, whose paragraph opens beneath it directly or
        // past an intervening picture and caption (#218).
        var labels = sectionLabels(in: lines, body: typography.body, headingThreshold: typography.headingThreshold,
                                   page: page, styles: context.labelStyles)
            + tableTitles(in: lines, tables: page.tables, body: typography.body)
        (lines, labels) = StackedSectionLabels.coalescing(lines, labels: labels, body: typography.body)
        // A recognized line in an English book is a heading only if it reads as words: a table
        // cell or a reading of handwriting set large is not a title, and every heading is a
        // navigation entry (#7).
        let judgesTitleWords = page.recognized && EnglishText.isDeclared(context.language)
        var exhausted = false
        // The page's own writing decides which way it is read, never the declared language: the
        // corpus converts the Arabic guide at library defaults, which declare English for it
        // (#41).
        let rightToLeft = ArabicText.readsRightToLeft(lines)
        let summaries = page.recognized || page.hasSyntheticTextStyle ? [] : DisplaySummary.groups(in: lines,
            body: typography.body, threshold: typography.headingThreshold)
        let summarized = summaries.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
        let quotations = page.hasSyntheticTextStyle ? [] : DisplayQuotation.groups(in: lines,
            body: typography.body, threshold: typography.headingThreshold)
        let quoted = quotations.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
        // Prose printed over a photograph has its own reading footprint. A transparent
        // flame or faded background may extend into several body columns, but its caption and
        // image form one unit after those columns, not a barrier across their reading order.
        let gallery = GalleryCaptions.groups(lines: lines, images: page.pictures, body: typography.body).compactMap { card -> GalleryCaptions.Group? in
            let picture = page.pictures[card.image]
            guard let image = images.indices.first(where: { images[$0].0.contains(picture) }),
                  !page.pictures.indices.contains(where: { $0 != card.image && images[image].0.contains(page.pictures[$0]) })
            else { return nil }
            let crop = images[image].0
            let rect = CGRect(x: min(crop.minX,card.rect.minX), y: card.rect.minY,
                              width: max(crop.maxX,card.rect.maxX) - min(crop.minX,card.rect.minX),
                              height: max(crop.maxY,card.rect.maxY) - card.rect.minY)
            return GalleryCaptions.Group(image: image, lines: card.lines, rect: rect)
        }
        let photoCaptions = CaptionParagraphs.groups(lines: lines, pictures: page.pictures + images.map(\.0), body: typography.body)
        var captioned = Set(gallery.flatMap(\.lines))
        let pictureElements = images.enumerated().map { imageIndex, image -> Element in
            if let card = gallery.first(where: { $0.image == imageIndex }) {
                return Element(rect: card.rect, image: image.1, pictureCaption: card.lines.map { lines[$0] })
            }
            let caption = photoCaptions.filter { group in
                group.indices.isDisjoint(with: captioned) && group.lines.contains { image.0.contains($0.rect) }
            }.flatMap { $0.indices }.sorted { lines[$0].rect.minY > lines[$1].rect.minY }
            captioned.formUnion(caption)
            let bodyOver = page.lines.indices.filter {
                overPicture.contains($0) && page.lines[$0].fontSize >= typography.body * 0.9
                    && page.lines[$0].fontSize <= typography.body * 1.1
                    && image.0.intersects(page.lines[$0].rect)
            }
            var reading = image.0
            if bodyOver.count >= 6, let low = bodyOver.map({ page.lines[$0].rect.minY }).min(),
               low - image.0.minY >= typography.body * 3 {
                reading.size.height = low - image.0.minY - typography.body * 0.2
            }
            return Element(rect: reading, image: image.1,
                           pictureCaption: caption.sorted { lines[$0].rect.minY > lines[$1].rect.minY }.map { lines[$0] },
                           proseBackdrop: !page.recognized && !page.hasSyntheticTextStyle && bodyOver.count >= 6)
        }
        let standaloneCaptions = photoCaptions
            .filter { $0.indices.isDisjoint(with: captioned) }
        let standalone = standaloneCaptions.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
        let claimed = summarized.union(quoted).union(captioned).union(standalone)
        let displayProse = page.recognized || page.hasSyntheticTextStyle ? [] : WrappedDisplayProse.groups(in: lines,
            threshold: typography.headingThreshold).filter { group in
                group.indices.isDisjoint(with: claimed)
                    && !page.tables.contains { $0.rect.intersects(group.rect) }
            }
        let displayedProse = displayProse.reduce(into: Set<Int>()) { $0.formUnion($1.indices) }
        let spatial = ordered(lines.enumerated().filter { !quoted.contains($0.offset) && !captioned.contains($0.offset)
            && !standalone.contains($0.offset) && !summarized.contains($0.offset) && !displayedProse.contains($0.offset) }.map {
            Element(rect: $0.element.readingRect ?? $0.element.rect, line: $0.element)
        } + summaries.map { Element(rect: $0.rect, aside: $0.lines) }
            + quotations.map { Element(rect: $0.rect, quotation: $0.lines) }
            + displayProse.map { Element(rect: $0.rect, nativePanel: $0.lines) }
            + pictureElements + standaloneCaptions.map { Element(rect: $0.rect, caption: $0.lines) }
            + page.tables.map { Element(rect: $0.rect, table: $0) },
            bodySize: typography.body, rightToLeft: rightToLeft, exhausted: &exhausted)
        if exhausted {
            warnings.append(.init(code: .complexLayout, page: page.number,
                message: "Whitespace cuts reached their depth limit before separating this page's content; "
                    + "what remained keeps the order it was extracted in, which may not be its reading order."))
        }
        let elements = NativeTextPanels.ordered(structuredOrder(spatial, page: page.number, warnings: &warnings),
            panels: page.recognized || page.hasSyntheticTextStyle ? [] : page.nativeTextPanels ?? [], body: typography.body, rightToLeft: rightToLeft)
        let noteGroups = NumberedNoteDetector.groups(in: elements, page: page,
                                                     headingEvidence: context.numberedNotePages.contains(page.number))
        // A link whose rectangle covers a figure links the figure (#247).
        var imageLinks: [String: LinkTarget] = [:]
        for (rect, path) in images where !page.links.isEmpty {
            if let target = linkCovering(rect, links: page.links) { imageLinks[path] = target }
        }
        // The list the page hangs under an outdented marker column, if it sets one (#282), and
        // the wrapped second line of each entry the page hangs, both read from the lines that
        // still reflow, as the table rows below are (#160).
        let markerList = hangingMarkerList(in: lines, body: typography.body)
        var assembler = BlockAssembler(page: page.number, body: typography.body, leading: typography.leading,
                                       additionalLeading: typography.additionalLeading,
                                       hyphens: context.hyphens, imageLinks: imageLinks,
                                       imageDescriptions: tableAssets(images, tables: page.recognizedTables,
                                                                      page: page.number),
                                       hangingEntries: hangingEntries(in: lines, body: typography.body),
                                       columnSeams: columnSeams(in: lines, body: typography.body,
                                                                rightToLeft: rightToLeft),
                                       ordinaryHeights: ordinaryLineHeights(in: lines),
                                       markerEntries: markerList?.openings ?? [],
                                       markerEntryEdge: markerList?.edge,
                                       labelValueStarts: page.recognized || page.hasSyntheticTextStyle
                                        ? [] : labelValueStarts(in: lines),
                                       rightToLeft: rightToLeft,
                                       recognized: page.recognized || page.hasSyntheticTextStyle,
                                       notesPage: context.numberedNotePages.contains(page.number))
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
        let rows = TableRegionDetector.rowBlocks(in: lines, body: typography.body, rightToLeft: rightToLeft)
        let roles = elements.map { element in
            element.line.map { line -> LineRole in
                let role = role(of: line, on: page, in: lines, typography: typography,
                                labels: labels, judgesTitleWords: judgesTitleWords, rightToLeft: rightToLeft)
                // A heading standing in the block, and monospaced text that keeps its own
                // breaks already, are left as they read.
                guard role != .heading, role != .code,
                      let block = rows.first(where: { $0.insetBy(dx: -1, dy: -1).contains(line.rect) })
                else { return role }
                // A line set in from the block's own left edge is a cell that wrapped, not the
                // next row. It is the printed row that is judged, not the piece the extractor
                // handed over: a row the extractor split at a direction boundary opens at the
                // block's edge however far in the piece that carries its title begins, which is
                // 291 points on the Arabic guide's contents (#41). In left-to-right writing the
                // first piece of a row is its leftmost, so this is the edge it always was.
                let rowStart = lines.filter {
                    block.insetBy(dx: -1, dy: -1).contains($0.rect) && $0.sharesRow(with: line)
                }.map(\.rect.minX).min() ?? line.rect.minX
                return .tableRow(continuation: rowStart > block.minX + typography.body * 0.6)
            }
        }
        let contradicted = contradictedHeadingGroups(elements, roles: roles, rank: context.headingRank)
        var continuations = ColumnContinuation.pairs(elements, roles: roles, body: typography.body)
            .merging(page.recognized || page.hasSyntheticTextStyle ? [:] : InterruptedColumnContinuation.pairs(elements, roles: roles, body: typography.body)) { existing, _ in existing }
        for index in elements.indices where index > 0 && roles[index] == .prose && roles[index - 1] == .prose {
            if let previous = elements[index].panelContinuationFrom, elements[index - 1].line?.rect == previous {
                continuations[index] = index - 1
            }
        }
        let suspendedAt = Set(continuations.values)
        var paragraphHandles: [Int: Int] = [:]
        for (index, element) in elements.enumerated() {
            if let start = continuations[index], let handle = paragraphHandles[start], let line = element.line,
               assembler.resumeProse(handle, with: line) {
                // The sentence continues in its original paragraph; its figure remains after it.
            } else if let panel = element.nativePanel {
                // A panel states its own type size and leading. Reusing the surrounding
                // paragraph's metrics would split its smaller words at every printed row.
                let content = PageContent(number: page.number, bounds: element.rect, lines: panel, graphics: [])
                assembler.appendTextPanel(blocks(page: content, images: [], context: context, warnings: &warnings))
            } else if let group = noteGroups[index], let line = element.line {
                assembler.appendNote(group: group, line)
            } else if let path = element.image {
                assembler.appendImage(path)
                if let caption = element.pictureCaption { assembler.appendCaption(caption) }
            } else if let caption = element.caption {
                assembler.appendCaption(caption)
            } else if let quote = element.quotation {
                assembler.appendQuotation(quote)
            } else if let summary = element.aside {
                assembler.appendAside(summary)
            } else if let table = element.table {
                assembler.appendTable(table)
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
            if suspendedAt.contains(index), let handle = assembler.suspendProse() {
                paragraphHandles[index] = handle
            }
        }
        var result = assembler.finish()
        warnings += assembler.warnings
        // Where a crop took prose the page printed before the first line it reflows, the page's
        // text does not begin at that block, and a cross-page join must not treat it as the
        // sentence the page before left open (#267).
        if let opening = result.firstIndex(where: \.hasReflowedText),
           cropTookThePageOpening(elements, taken: taken.subtracting(released), page: page,
                                  body: typography.body, rightToLeft: rightToLeft) {
            result[opening].followsCroppedText = true
        }
        return result
    }

    /// Whether a crop took what the page printed before the first line it reflows, so the page's
    /// own text does not begin at that line.
    ///
    /// Two shapes, both Wallace's. **Down the page:** page 430 prints `b are the other two sides
    /// (legs), then we can use the following formula, a² + b² = c²`, a display takes the whole
    /// row, and `to find a missing side.` is what is left to reflow. **Along a row:** page 344
    /// prints `values into x =` at the measure and sets the quadratic formula beside it, so the
    /// crop took the opening of the very row the page's first reflowed line stands in.
    ///
    /// What the crop took has to be the page's own flow, not a picture's writing. Above the
    /// line, that is `readsAsSentence` — the test the crop rules (#255) and a block reached past
    /// a picture (#203) already use — together with the measure: the 9/11 report runs its boxed
    /// list of *Operational Opportunities* over the head of page 374 and that prose is indented
    /// onto a measure of its own, while `…all involved were` / `responsible for making it work.`
    /// is the join the page asks for. Along the row no such test is needed, because a printed row
    /// the page began inside a crop is that row wherever its pieces read.
    static func cropTookThePageOpening(_ elements: [Element], taken: Set<Int>, page: PageContent,
                                       body: CGFloat, rightToLeft: Bool) -> Bool {
        guard !taken.isEmpty, let first = elements.first(where: { $0.line != nil })?.line else { return false }
        func earlierAlongTheRow(_ line: TextLine) -> Bool {
            rightToLeft ? line.rect.minX > first.rect.minX : line.rect.minX < first.rect.minX
        }
        func atTheSameMeasure(_ line: TextLine) -> Bool {
            rightToLeft ? line.rect.maxX >= first.rect.maxX - body * 0.25
                        : line.rect.minX <= first.rect.minX + body * 0.25
        }
        return taken.contains { index in
            let line = page.lines[index]
            guard !line.sharesRow(with: first) else { return earlierAlongTheRow(line) }
            return line.rect.minY > first.rect.minY && readsAsSentence(line) && atTheSameMeasure(line)
        }
    }

    /// Convenience for tests that supply the document context piecemeal.
    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], numberedNotePage: Bool = false,
                       language: String = "en", documentBody: CGFloat? = nil,
                       labelStyles: Set<LabelStyle> = [], headingRank: HeadingRank = HeadingRank()) -> [ReflowBlock] {
        let context = DocumentContext(hyphens: HyphenContext(vocabulary: vocabulary), language: language,
                                      documentBody: documentBody, labelStyles: labelStyles, headingRank: headingRank,
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

    /// A picture's block. Its description names the source page rather than inventing a
    /// description of the picture, except where the conversion has *measured* what the picture
    /// holds and the generic description would say nothing a reader can use: a table recognition
    /// located and did not transcribe is named as one, so that the reader is told the cells are
    /// in the picture and nowhere else rather than being handed `Preserved region from page 150`
    /// (#31).
    static func imageBlock(assetID: String, page: Int, reference: Bool = false,
                           link: LinkTarget? = nil, describing: String? = nil) -> ReflowBlock {
        let caption = describing
            ?? (reference ? "Original page \(page)" : "Preserved region from page \(page)")
        return ReflowBlock(content: .image(.init(assetID: assetID, alternativeText: caption,
                                                 caption: caption, link: link)), page: page)
    }

    /// The description of a crop that preserves a table the page's recognition located (#31).
    ///
    /// The library writes no table markup, so no located table's cells reach the reader as text:
    /// the picture is the table, and `Preserved region from page 150` says nothing a reader can
    /// act on. The description names it as a table and says where its cells are. It never states
    /// the table's own shape, because the grid the reading returned is the reading's and not the
    /// page's — on the CIA report's page 150 the page rules four tables of 25 columns and the
    /// reading returns two, of 26 and 25.
    static func tableDescription(page: Int) -> String {
        "Table from page \(page), preserved as an image. Its cells are not transcribed; "
            + "read them in this picture."
    }

    /// Which of a page's crops preserve a table its recognition located, by asset path (#31). A
    /// crop owns a table when it holds most of the table's area: the crop is grown from the
    /// table's own rectangle, so it contains it, while a neighbouring figure's crop on the same
    /// page does not.
    static func tableAssets(_ images: [(CGRect, String)],
                            tables: [TableCellEvidence.Reading], page: Int) -> [String: String] {
        var result: [String: String] = [:]
        for table in tables {
            let area = table.rect.width * table.rect.height
            guard area > 0 else { continue }
            let owner = images.first { crop in
                let overlap = crop.0.intersection(table.rect)
                return !overlap.isNull && overlap.width * overlap.height >= area * 0.5
            }
            if let owner { result[owner.1] = tableDescription(page: page) }
        }
        return result
    }

    /// The target of a link whose rectangle covers most of a crop, which is a link to the figure
    /// rather than to any text (#247). Half the crop's area is the bound: a link over a caption
    /// line inside a figure is a link to text and is marked there.
    static func linkCovering(_ rect: CGRect, links: [PageLink]) -> LinkTarget? {
        guard rect.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        let area = rect.width * rect.height
        return links.first { link in
            let overlap = link.rect.intersection(rect)
            return !overlap.isNull && overlap.width * overlap.height >= area * 0.5
        }?.target
    }

    /// Preserve the source boundary inside a continuing paragraph, without a format-specific marker.
    static func appendPage(_ pageBlocks: [ReflowBlock], page: PageContent, previousPage: PageContent?,
                           to blocks: inout [ReflowBlock], vocabulary: Set<String>,
                           warnings: inout [ConversionWarning]) {
        appendPage(pageBlocks, page: page, previousPage: previousPage, to: &blocks,
                   hyphens: HyphenContext(vocabulary: vocabulary), warnings: &warnings)
    }

    /// Whether a block ends where the page broke a word. `lineEndSubstitute` is a book-wide
    /// reading the streaming bound below does not carry, so only the two characters every book
    /// draws a break with are asked there; the join itself reads the book's own substitute.
    /// A word is what is broken, so a letter or a digit has to stand in front of the break:
    /// Project Blue Book's inherited OCR ends whole blocks on the runs of dashes it reads its
    /// ruled pages as, and none of those is a word carrying on (#280).
    static func endsBroken(_ text: String, substitute: Character? = nil) -> Bool {
        let broken = text.hasSuffix("-") || text.hasSuffix("\u{00ad}")
            || substitute.map { text.last == $0 } == true
        return broken && text.dropLast().last.map { $0.isLetter || $0.isNumber } == true
    }

    /// The text of a block a cross-page join may carry on.
    ///
    /// A paragraph carries on as a paragraph does. A preformatted item carries on only where the
    /// page broke a word over the block boundary, which is the one thing such a block can still be
    /// missing: the 9/11 report's note 22 ends page 490 on `…For the 1998–2001 num-` and page 491
    /// opens `bers, see DOJ Inspector General report,…`. `BlockAssembler.carryBrokenItems` gives
    /// an item the rest of its word everywhere else; across a page only this reaches it (#280).
    /// Nothing else joins to an item: a paragraph the next page opens is that page's, not the
    /// item's, unless the item is holding half a word.
    static func carriedOn(_ content: ReflowBlock.Content, substitute: Character?) -> InlineText? {
        switch content {
        case let .paragraph(text): return text
        case let .preformatted(text): return endsBroken(text.text, substitute: substitute) ? text : nil
        default: return nil
        }
    }

    /// How many blocks at the tail a later page can still amend, which is what reconstruction must
    /// hold back (#203, [decision 0008](../../doc/decisions/0008-streamed-blocks-to-the-writer.md)).
    ///
    /// Ordinarily that is the trailing block alone, which is the paragraph a continued paragraph
    /// joins. Where images stand at the tail, the join steps over them to the paragraph beneath,
    /// so that paragraph and every image the join would move are still open.
    ///
    /// The count cannot grow without bound: a page that opens no paragraph puts its own marker at
    /// the tail, and a marker is not a paragraph, so the walk stops there and the tail is one
    /// block again.
    static func amendableTail(of blocks: [ReflowBlock]) -> Int {
        var anchor = blocks.count - 1
        while anchor >= 0, blocks[anchor].isImage { anchor -= 1 }
        guard anchor >= 0, anchor < blocks.count - 1,
              carriedOn(blocks[anchor].content, substitute: nil) != nil else { return 1 }
        return blocks.count - anchor
    }

    static func appendPage(_ pageBlocks: [ReflowBlock], page: PageContent, previousPage: PageContent?,
                           to blocks: inout [ReflowBlock], hyphens: HyphenContext,
                           warnings: inout [ConversionWarning]) {
        var remaining = pageBlocks
        // A picture between two halves of a paragraph interrupts it; it does not end it. The Fed
        // sets Box 3.5 at the foot of page 47, so `…(See box 3.5 for more details…) The vast
        // major-` was the page's second-to-last block and `ity of the Federal Reserve's assets…`
        // opened page 48 as a paragraph of its own, with the word broken between them. The join
        // steps over the images on either side of the boundary, and each keeps the side of that
        // boundary its own page is on, because the marker the join sets stands inside the
        // paragraph: page 47's box is placed before the paragraph, where it also reads before the
        // sentence that refers to it, and page 48's rule after it. Placing page 47's box after the
        // paragraph would carry it past the page-48 marker (#203).
        var anchor = blocks.count - 1
        while anchor >= 0, blocks[anchor].isImage { anchor -= 1 }
        var opening = 0
        while opening < remaining.count, remaining[opening].isImage { opening += 1 }
        if anchor >= 0, opening < remaining.count, let previousPage,
           let left = carriedOn(blocks[anchor].content, substitute: hyphens.lineEndSubstitute),
           case let .paragraph(right) = remaining[opening].content,
           // Reaching past a picture asks more of the paragraph than standing beside the boundary
           // did. A block the join steps over pictures to reach is being called a paragraph the
           // page interrupted, so it must read as the page's prose; a folio, a figure number or a
           // stray mark is not one. The 9/11 report prints `145` under the column on page 163 and
           // a crop after it, and that folio would otherwise take page 164's opening words. The
           // block directly before a boundary is still reached whatever it holds: #45's wider
           // defect, a join anchored on a folio that is simply the last block, is untouched here.
           (anchor == blocks.count - 1 && opening == 0) || readsAsSentence(blocks[anchor].text),
           // The block a page opens with is the sentence's other half only where it is where the
           // page's text begins. Wallace's page 430 prints `b are the other two sides (legs),
           // then we can use the following formula, a² + b² = c²` and a display crop takes all of
           // it, so `to find a missing side.` is the first line the page reflows; joining that to
           // `…the hypotenuse of the triangle, and a and` reads two fragments the crop had
           // already broken as one paragraph. Those two halves were never consecutive (#267).
           !remaining[opening].followsCroppedText,
           // Two validated paragraph identities that differ are two paragraphs, and never join.
           // One identity and no identity is not that: a page whose tags were not applied says
           // nothing about where its last paragraph ends, so the geometric rule decides, as it
           // did when neither page carried a tag (#67).
           blocks[anchor].structureGroup == remaining[opening].structureGroup
               || blocks[anchor].structureGroup == nil || remaining[opening].structureGroup == nil,
           remaining[opening].text.first?.isLowercase == true,
           blocks[anchor].text.last.map({ !".!?:".contains($0) }) == true,
           previousPage.lines.last.map({ $0.rect.minY < previousPage.bounds.minY + previousPage.bounds.height * 0.2 }) == true,
           page.lines.first.map({ $0.rect.maxY > page.bounds.minY + page.bounds.height * 0.8 }) == true {
            let stepped = Array(blocks[(anchor + 1)...])
            blocks.removeLast(stepped.count)
            let carried = join(left, right, hyphens: hyphens,
                               page: page.number, sourceBoundary: page.number, warnings: &warnings)
            // The block keeps its own kind: an item that was holding half a word is still an item.
            if case .preformatted = blocks[anchor].content {
                blocks[anchor].content = .preformatted(carried)
            } else {
                blocks[anchor].content = .paragraph(carried)
            }
            blocks.insert(contentsOf: stepped, at: anchor)
            blocks += remaining.prefix(opening)
            remaining.removeFirst(opening + 1)
        } else {
            blocks.append(ReflowBlock(content: .sourcePage(page.number), page: page.number))
        }
        blocks += remaining
    }
}
