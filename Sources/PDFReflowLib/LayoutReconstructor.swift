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
            + FractionRegionDetector.regions(in: page) + tables
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

    /// `continuesNote` states that the previous page ended in a page-bottom footnote, so a
    /// marker-less note under this page's separator may continue it.
    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], numberedNotePage: Bool = false,
                       continuesNote: Bool = false) -> [ReflowBlock] {
        let body = max(4, bodySize(page.lines))
        let lines = page.lines.filter { line in !images.contains { $0.0.intersects(line.rect) } }
        // Preserve existing modest-size headings, but reject candidates within 10% of the
        // supported reflowable body size. This only narrows the original page-size heuristic.
        let headingThreshold = max(body * 1.25, headingBodySize(lines, pageBody: body) * 1.1)
        let spatial = ordered(lines.map { Element(rect: $0.readingRect ?? $0.rect, line: $0) }
            + images.map { Element(rect: $0.0, image: $0.1) }, bodySize: body)
        let elements = structuredOrder(spatial, page: page.number, warnings: &warnings)
        // Page-bottom footnotes end the page's reading order; the body is everything before
        // their separator, which is not emitted.
        let footnotes = FootnoteDetector.layout(in: elements, page: page, continuesNote: continuesNote)
        let bodyElements = elements[..<(footnotes?.separator ?? elements.count)]
        let noteGroups = NumberedNoteDetector.groups(in: elements, page: page, headingEvidence: numberedNotePage)
        var result: [ReflowBlock] = []
        var note: (Int, InlineText)?
        func flushNote() {
            if let (_, text) = note { result.append(ReflowBlock(content: .paragraph(text), page: page.number)) }
            note = nil
        }
        var tagged: (TextStructure, InlineText)?
        func flushTagged() {
            guard let (tag, text) = tagged else { return }
            let content: ReflowBlock.Content = tag.headingLevel == 0 ? .paragraph(text)
                : .heading(id: "heading-\(page.number)-\(result.count)", text: text, level: tag.headingLevel)
            result.append(ReflowBlock(content: content, structureGroup: tag.group, page: page.number))
            tagged = nil
        }
        var paragraph = InlineText()
        var previous: TextLine?
        var codeOrigin: CGFloat?
        func flush() {
            if !paragraph.elements.isEmpty {
                result.append(ReflowBlock(content: .paragraph(paragraph), page: page.number))
            }
            paragraph = InlineText()
            previous = nil
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
        for (index, element) in bodyElements.enumerated() {
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
            guard let line = element.line else { continue }
            if let tag = line.structure {
                flush()
                codeOrigin = nil
                if tagged?.0.group != tag.group { flushTagged() }
                if let current = tagged {
                    tagged = (current.0, join(current.1, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings))
                } else { tagged = (tag, line.content) }
                continue
            }
            flushTagged()
            if !line.monospaced { codeOrigin = nil }
            if !page.hasSyntheticTextStyle && line.fontSize >= headingThreshold && line.text.count < 200 {
                flush()
                result.append(ReflowBlock(content: .heading(id: "heading-\(page.number)-\(result.count)", text: line.content),
                    page: page.number))
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
            } else {
                if let prev = previous, isDetachedMarker(line, after: prev) {
                    paragraph.append(InlineText(line.text, style: .superscript))
                    continue
                }
                if let prev = previous {
                    let verticalGap = prev.rect.minY - line.rect.maxY
                    let sameColumn = abs(prev.rect.minX - line.rect.minX) < body * 1.5
                        && verticalGap >= -body * 0.4 && verticalGap < body * 0.9
                    let shortEnding = prev.rect.width < line.rect.width * 0.65
                        && prev.text.last.map { ".!?".contains($0) } == true
                    if prev.wraps == false || !sameColumn || shortEnding { flush() }
                }
                if paragraph.elements.isEmpty { paragraph = line.content }
                else {
                    paragraph = join(paragraph, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings)
                }
                previous = line
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
            result.append(ReflowBlock(content: .footnote(text), page: page.number))
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
              case let .footnote(rest) = blocks[index].content, FootnoteDetector.marker(of: rest) == nil,
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
        if let previousPage,
           let anchors = continuation(from: blocks, previousPage: previousPage, previousImages: previousImages,
                                      to: remaining, page: page, images: images),
           case let .paragraph(left) = blocks[anchors.previous].content,
           case let .paragraph(right) = remaining[anchors.next].content {
            var joined = blocks[anchors.previous]
            joined.content = .paragraph(join(left, right, vocabulary: vocabulary, page: page.number,
                sourceBoundary: page.number, warnings: &warnings))
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
        guard previous >= 0, case let .paragraph(left) = blocks[previous].content,
              blocks[previous].page == previousPage.number
                || blocks[previous].sourcePages.contains(previousPage.number) else { return nil }
        var next = 0
        while next < pageBlocks.count, isSkippable(pageBlocks[next], page: page) { next += 1 }
        guard next < pageBlocks.count, case let .paragraph(right) = pageBlocks[next].content else { return nil }
        // Two validated identities are the author's evidence; one untagged side keeps the heuristic.
        if let leftGroup = blocks[previous].structureGroup, let rightGroup = pageBlocks[next].structureGroup,
           leftGroup != rightGroup { return nil }
        guard right.text.first?.isLowercase == true, !endsSentence(left),
              let last = lastLine(of: left.text, in: previousPage.lines),
              let first = firstLine(of: right.text, in: page.lines),
              !isHeaderLike(first, in: page), wordCount(first.text) >= 2,
              readsAsProse(last.text), readsAsProse(first.text),
              fillsColumn(last, in: previousPage.lines, body: max(4, bodySize(previousPage.lines))),
              endsColumn(last, in: previousPage, images: previousImages),
              opensColumn(first, in: page, images: images) else { return nil }
        return (previous, next)
    }

    /// Preserved images, page-bottom footnotes, figure captions and bare folios in the margin
    /// do not carry body text.
    private static func isSkippable(_ block: ReflowBlock, page: PageContent) -> Bool {
        switch block.content {
        case .image, .footnote: return true
        case .paragraph: break
        case .heading, .preformatted, .sourcePage: return false
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

    /// A short line in the top band that opens or closes with a page number and is separated from
    /// the text below it is a running header that furniture removal kept (`xiv COMMISSION STAFF`).
    /// A paragraph's short final line at the head of a page carries no folio.
    private static func isHeaderLike(_ line: TextLine, in page: PageContent) -> Bool {
        let words = line.text.split(whereSeparator: \.isWhitespace)
        guard page.bounds.height > 0, (line.rect.midY - page.bounds.minY) / page.bounds.height >= 0.9,
              line.text.count < 100, let first = words.first, let last = words.last,
              isFolio(String(first)) || isFolio(String(last)) else { return false }
        let below = page.lines.filter { $0.rect.midY < line.rect.midY - line.rect.height * 0.4 }
        guard let gap = below.map({ line.rect.minY - $0.rect.maxY }).min() else { return true }
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
