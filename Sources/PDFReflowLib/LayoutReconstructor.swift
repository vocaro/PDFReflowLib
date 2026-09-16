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

    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], numberedNotePage: Bool = false) -> [ReflowBlock] {
        let body = max(4, bodySize(page.lines))
        let lines = page.lines.filter { line in !images.contains { $0.0.intersects(line.rect) } }
        // Preserve existing modest-size headings, but reject candidates within 10% of the
        // supported reflowable body size. This only narrows the original page-size heuristic.
        let headingThreshold = max(body * 1.25, headingBodySize(lines, pageBody: body) * 1.1)
        let spatial = ordered(lines.map { Element(rect: $0.readingRect ?? $0.rect, line: $0) }
            + images.map { Element(rect: $0.0, image: $0.1) }, bodySize: body)
        let elements = structuredOrder(spatial, page: page.number, warnings: &warnings)
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
        for (index, element) in elements.enumerated() {
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
        return result
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
        var remaining = pageBlocks
        if let last = blocks.last, let first = remaining.first, let previousPage,
           case let .paragraph(left) = last.content, case let .paragraph(right) = first.content,
           last.structureGroup == first.structureGroup,
           first.text.first?.isLowercase == true, last.text.last.map({ !".!?:".contains($0) }) == true,
           previousPage.lines.last.map({ $0.rect.minY < previousPage.bounds.minY + previousPage.bounds.height * 0.2 }) == true,
           page.lines.first.map({ $0.rect.maxY > page.bounds.minY + page.bounds.height * 0.8 }) == true {
            blocks[blocks.count - 1].content = .paragraph(join(left, right, vocabulary: vocabulary,
                page: page.number, sourceBoundary: page.number, warnings: &warnings))
            remaining.removeFirst()
        } else {
            blocks.append(ReflowBlock(content: .sourcePage(page.number), page: page.number))
        }
        blocks += remaining
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
