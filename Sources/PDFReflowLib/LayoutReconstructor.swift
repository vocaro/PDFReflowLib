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
        let body = max(4, bodySize(page.lines))
        var regions = clusters(page.graphics + formulas + TableRegionDetector.regions(in: page)
            + FractionRegionDetector.regions(in: page, body: body), distance: 3)
        var previous: [CGRect] = []
        while regions != previous {
            previous = regions
            for i in regions.indices {
                var prior = CGRect.null
                while prior != regions[i] {
                    prior = regions[i]
                    for line in page.lines where regions[i].intersects(line.rect) {
                        regions[i] = regions[i].union(line.rect.insetBy(dx: -2, dy: -2))
                    }
                }
                regions[i] = regions[i].intersection(page.bounds)
            }
            // A merged bounding rectangle can newly intersect a label that neither component
            // touched. Expand again before rasterizing, or its text is removed from prose while
            // the image clips part of it (for example, a raised exponent beside a fraction).
            regions = clusters(regions, distance: 3)
        }
        return regions
    }

    struct Element {
        var rect: CGRect
        var line: TextLine?
        var image: String?
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
        weights.max { $0.value < $1.value }.map { CGFloat($0.key) }
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
    /// so they touch or overlap), sharing the left edge, the centre or the right edge (#186).
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
        func neighbour(of line: TextLine, above: Bool) -> TextLine? {
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
            guard let above = neighbour(of: line, above: true),
                  above.rect.minY - line.rect.maxY < size * 0.9,
                  abs(line.rect.minX - above.rect.minX - step) <= size * 0.5,
                  let below = neighbour(of: line, above: false),
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

    /// One page's logical blocks: its typography is read once, every line outside a tagged or
    /// numbered-note group is classified by `role(of:)`, and `BlockAssembler` builds the blocks.
    static func blocks(page: PageContent, images: [(CGRect, String)], context: DocumentContext,
                       warnings: inout [ConversionWarning]) -> [ReflowBlock] {
        let lines = page.lines.filter { line in !images.contains { $0.0.intersects(line.rect) } }
        let typography = PageTypography(pageLines: page.lines, reflowableLines: lines, documentBody: context.documentBody)
        // A bold sub-heading set at or near body size, whose paragraph opens beneath it directly or
        // past an intervening picture and caption (#218).
        let labels = sectionLabels(in: lines, body: typography.body, headingThreshold: typography.headingThreshold,
                                   page: page, styles: context.labelStyles)
        // A recognized line in an English book is a heading only if it reads as words: a table
        // cell or a reading of handwriting set large is not a title, and every heading is a
        // navigation entry (#7).
        let judgesTitleWords = page.recognized && EnglishText.isDeclared(context.language)
        let spatial = ordered(lines.map { Element(rect: $0.readingRect ?? $0.rect, line: $0) }
            + images.map { Element(rect: $0.0, image: $0.1) }, bodySize: typography.body)
        let elements = structuredOrder(spatial, page: page.number, warnings: &warnings)
        let noteGroups = NumberedNoteDetector.groups(in: elements, page: page,
                                                     headingEvidence: context.numberedNotePages.contains(page.number))
        var assembler = BlockAssembler(page: page.number, body: typography.body, hyphens: context.hyphens)
        for (index, element) in elements.enumerated() {
            if let group = noteGroups[index], let line = element.line {
                assembler.appendNote(group: group, line)
            } else if let path = element.image {
                assembler.appendImage(path)
            } else if let line = element.line {
                if let tag = line.structure {
                    assembler.appendTagged(tag, line)
                } else {
                    assembler.append(line, as: role(of: line, on: page, in: lines, typography: typography,
                                                    labels: labels, judgesTitleWords: judgesTitleWords))
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
           last.structureGroup == first.structureGroup,
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
