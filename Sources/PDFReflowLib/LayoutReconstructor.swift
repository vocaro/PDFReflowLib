import Foundation
import CoreGraphics

enum LayoutReconstructor {
    static func vocabulary(in pages: [PageContent]) -> Set<String> {
        Set(pages.flatMap(\.lines).flatMap { line in
            line.text.lowercased().split { !$0.isLetter && $0 != "-" }.map(String.init)
        })
    }

    static func stripFurniture(_ pages: inout [PageContent]) -> [ConversionWarning] {
        guard pages.count >= 3 else { return [] }
        func key(_ line: TextLine, bounds: CGRect) -> String? {
            let edge: String
            if line.rect.midY > bounds.minY + bounds.height * 0.93 { edge = "top" }
            else if line.rect.midY < bounds.minY + bounds.height * 0.07 { edge = "bottom" }
            else { return nil }
            // Short edge text only; a repeated paragraph is not furniture.
            guard line.text.count < 100 else { return nil }
            return edge + ":" + line.text.lowercased().replacingOccurrences(
                of: "[0-9]+", with: "#", options: .regularExpression)
        }
        var occurrences: [String: Int] = [:]
        for page in pages {
            for candidate in Set(page.lines.compactMap { key($0, bounds: page.bounds) }) {
                occurrences[candidate, default: 0] += 1
            }
        }
        var warnings: [ConversionWarning] = []
        for i in pages.indices {
            let bounds = pages[i].bounds
            let kept = pages[i].lines.filter { line in
                guard let candidate = key(line, bounds: bounds) else { return true }
                return occurrences[candidate, default: 0] < max(3, (pages.count + 1) / 2)
            }
            if !kept.isEmpty && kept.count != pages[i].lines.count {
                warnings.append(.init(code: .furnitureRemoved, page: pages[i].number,
                    message: "Repeated header or footer omitted from the reflowed text."))
                pages[i].lines = kept
            }
        }
        return warnings
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
        var regions = clusters(page.graphics + formulas + TableRegionDetector.regions(in: page), distance: 3)
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
        for line in lines { weights[Int(line.fontSize.rounded()), default: 0] += line.text.count }
        return CGFloat(weights.max { $0.value < $1.value }?.key ?? 12)
    }

    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning]) -> [ReflowBlock] {
        let body = max(4, bodySize(page.lines))
        let lines = page.lines.filter { line in !images.contains { $0.0.intersects(line.rect) } }
        let elements = ordered(lines.map { Element(rect: $0.rect, line: $0) }
            + images.map { Element(rect: $0.0, image: $0.1) }, bodySize: body)
        var result: [ReflowBlock] = []
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
        for element in elements {
            if let path = element.image {
                flush()
                codeOrigin = nil
                result.append(imageBlock(assetID: path, page: page.number))
                continue
            }
            guard let line = element.line else { continue }
            if !line.monospaced { codeOrigin = nil }
            if line.fontSize >= body * 1.25 && line.text.count < 200 {
                flush()
                result.append(ReflowBlock(content: .heading(id: "heading-\(page.number)-\(result.count)", text: line.content),
                    page: page.number))
            } else if line.monospaced {
                flush()
                if let origin = codeOrigin, let last = result.last, case let .preformatted(previousText) = last.content {
                    let indent = min(80, max(0, Int(((line.rect.minX - origin) / (line.fontSize * 0.6)).rounded())))
                    let text = "\n" + String(repeating: " ", count: indent) + line.text
                    result[result.count - 1].content = .preformatted(previousText + text)
                } else {
                    codeOrigin = line.rect.minX
                    result.append(ReflowBlock(content: .preformatted(line.text), page: page.number))
                }
            } else if isList(line.text) {
                flush()
                // Preserve significant source breaks; do not rewrite list markers or code.
                result.append(ReflowBlock(content: .preformatted(line.text), page: page.number))
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
        flush()
        return result
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

    private static func isList(_ text: String) -> Bool {
        text.range(of: "^(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s", options: .regularExpression) != nil
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
