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
    /// A line that opens lowercase after a line-end hyphen opens with the rest of a broken word
    /// (`es-` + `timates.html`, `communi-` + `cations`), which vouches for no join: that one
    /// word is not evidence, though the same letters seen anywhere else are (#101). A compound
    /// there keeps its own unbroken hyphen (`straight-` + `and-level`), so it still counts.
    static func addVocabulary(of page: PageContent, to vocabulary: inout Set<String>) {
        var previous: String?
        for line in page.lines {
            var words = line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" })
            if let previous, previous.hasSuffix("-") || previous.hasSuffix("\u{00ad}"),
               line.text.first?.isLowercase == true, let first = words.first, !first.contains("-") {
                words.removeFirst()
            }
            for word in words { vocabulary.insert(String(word)) }
            addAddressVocabulary(of: line.text, to: &vocabulary)
            previous = line.text
        }
    }

    /// Web addresses seen unbroken, for resolving a line-end hyphen inside an address (#88). The
    /// entries share the word set under prefixes no word can hold: every prefix of an address
    /// that ends at `/ . ? # & = :` or at its end, and every segment between those characters,
    /// lowercased and without scheme or `www.`. An address ending its line may continue on the
    /// next, so its last segment is not evidence.
    static func addAddressVocabulary(of text: String, to vocabulary: inout Set<String>) {
        guard text.contains("/") || text.contains("www.") || text.contains("WWW.") else { return }
        let words = text.split(whereSeparator: \.isWhitespace)
        for (index, word) in words.enumerated() where word.contains("/") || word.lowercased().contains("www.") {
            let run = String(word.reversed().drop { !addressCharacters.contains($0) }.reversed())
            guard let address = trailingAddress(run) else { continue }
            // A line's first word may continue an address broken on the line above (`federalre-` +
            // `serve.gov/…`): without a scheme or `www.`, its first segment is not evidence.
            var fragmentSegment = index == 0
                && address.range(of: "^(?:[A-Za-z][A-Za-z0-9+.-]*://|www\\.)", options: [.regularExpression, .caseInsensitive]) == nil
            var normalized = Substring(normalizedAddress(address))
            while let last = normalized.last, ".,;:)]".contains(last) { normalized.removeLast() }
            if index == words.count - 1 {
                guard let cut = normalized.lastIndex(where: { addressDelimiters.contains($0) }) else { continue }
                normalized = normalized[..<cut]
            }
            guard !normalized.isEmpty else { continue }
            vocabulary.insert(addressPrefixKey + normalized)
            var segmentStart = normalized.startIndex
            for position in normalized.indices where addressDelimiters.contains(normalized[position]) {
                vocabulary.insert(addressPrefixKey + normalized[..<position])
                if segmentStart < position, !fragmentSegment { vocabulary.insert(addressSegmentKey + normalized[segmentStart..<position]) }
                fragmentSegment = false
                segmentStart = normalized.index(after: position)
            }
            if segmentStart < normalized.endIndex, !fragmentSegment { vocabulary.insert(addressSegmentKey + normalized[segmentStart...]) }
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

    /// A thin rule spanning at least half of the page's text that no text sits against: nothing
    /// within one body size above or below it, or only a running head's row of body-sized text
    /// between it and the page edge with all other text beyond it (The Fed Explained's header
    /// rule on every page, #66). It carries nothing a reader needs as an image. A rule set
    /// directly beneath a heading (Our Flag page 27's section rules, 1.6 pt under 22-pt titles)
    /// or beside table text still has text within a body size and is not decoration here.
    static func isDecorationRule(_ rule: CGRect, in lines: [TextLine], bounds: CGRect, body: CGFloat) -> Bool {
        guard isThinRule(rule), !lines.isEmpty, !lines.contains(where: { $0.rect.intersects(rule) }) else { return false }
        let text = union(lines.map(\.rect))
        guard rule.width >= text.width * 0.5 else { return false }
        let near = lines.filter { $0.rect.intersects(rule.insetBy(dx: 0, dy: -body)) }
        guard let first = near.first else { return true }
        let above = first.rect.midY > rule.midY
        guard near.allSatisfy({ ($0.rect.midY > rule.midY) == above && $0.fontSize <= body * 1.2
                                && sameRow($0.rect, first.rect) }) else { return false }
        // The running head sits between the rule and the page edge; everything else lies beyond.
        let beyond = lines.filter { line in !near.contains { $0.rect == line.rect && $0.text == line.text } }
        let margin = bounds.height * 0.12
        return above ? beyond.allSatisfy { $0.rect.maxY <= rule.midY } && first.rect.minY >= bounds.maxY - margin
                     : beyond.allSatisfy { $0.rect.minY >= rule.midY } && first.rect.maxY <= bounds.minY + margin
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

    /// A piece that is nothing but a list marker: a bullet, or a number of up to three digits or
    /// a single letter followed by `.` or `)`. A minus or hyphen alone is a sign or a rule.
    private static func isMarkerPiece(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces)
            .range(of: "^(?:•|[0-9]{1,3}[.)]|[A-Za-z][.)])$", options: .regularExpression) != nil
    }

    /// PDFKit splits a list marker from its item's text at the gap after the marker: `4.` and
    /// `Neither the intelligence community…` on one baseline (9/11 page 365), and `•` apart from
    /// most FAA and NOAA bullets. Neither piece reads as a list line, so the marker became a
    /// paragraph of its own or joined the end of the block above (FAA page 27's `…reasons: •`),
    /// and its item's text opened an unmarked paragraph. A marker piece that opens its row (no piece on that row ends within one of its
    /// font sizes to its left) joins the nearest piece that starts to its right within two font
    /// sizes, at the same size and in the same structure group, which is not itself a marker
    /// piece. Every other line passes through unchanged (#69).
    ///
    /// Both pieces of a tagged join belong to one validated group (the FAA handbook tags each
    /// bullet item, marker and text, as one `P`). The joined line keeps that group, sorts at the
    /// earlier of the two pieces' orders, and every line of the group counts one line fewer, so the
    /// group stays complete. Its lines record that the group opens with a rejoined marker, which
    /// is what lets `structuredOrder` accept a group holding exactly that one list item (#81).
    static func joiningMarkerPieces(_ lines: [TextLine]) -> [TextLine] {
        var result = lines
        // Pieces already joined, and the marker pieces absorbed into the piece beside them.
        var claimed = Set<Int>(), absorbed = Set<Int>()
        // Tagged groups that absorbed a marker piece, with the number of pieces each absorbed.
        var joinedGroups: [Int: Int] = [:]
        for (index, marker) in lines.enumerated() where !claimed.contains(index) && !marker.monospaced
            && isMarkerPiece(marker.text) {
            let size = marker.fontSize
            let row = lines.indices.filter { $0 != index && !claimed.contains($0) && sameRow(lines[$0].rect, marker.rect) }
            guard !row.contains(where: {
                lines[$0].rect.minX < marker.rect.minX && lines[$0].rect.maxX >= marker.rect.minX - size
            }) else { continue }
            let pieces = row.filter { other in
                let line = lines[other]
                let gap = line.rect.minX - marker.rect.maxX
                return gap >= -1 && gap <= size * 2 && abs(line.fontSize - size) <= size * 0.1
                    && !line.monospaced && line.structure?.group == marker.structure?.group
                    && !isMarkerPiece(line.text)
            }
            guard let target = pieces.min(by: { lines[$0].rect.minX < lines[$1].rect.minX }) else { continue }
            let text = lines[target]
            var content = marker.content
            content.append(InlineText(" "))
            content.append(text.content)
            var joined = TextLine(content: content, rect: marker.rect.union(text.rect), fontSize: text.fontSize,
                                  wraps: text.wraps)
            joined.readingRect = text.readingRect.map { $0.union(marker.rect) }
            // The join requires one group on both sides, so both tags are nil or both are set.
            if var tag = text.structure, let markerTag = marker.structure {
                tag.order = min(tag.order, markerTag.order)
                joined.structure = tag
                joinedGroups[tag.group, default: 0] += 1
            }
            result[target] = joined
            claimed.formUnion([index, target])
            absorbed.insert(index)
        }
        var kept = result.indices.filter { !absorbed.contains($0) }.map { result[$0] }
        guard !joinedGroups.isEmpty else { return kept }
        for index in kept.indices {
            guard let group = kept[index].structure?.group, let pieces = joinedGroups[group] else { continue }
            kept[index].structure?.lineCount -= pieces
            kept[index].structure?.opensWithSplitMarker = true
        }
        return kept
    }

    /// PDFKit splits a prose row at an inline radical: `Not all numbers have a nice even square
    /// root. For example, if we found 8` and `√ on` (Wallace page 288), `process is being able to
    /// translate a problem like 180 √ into 36· 5` and `√ . There are sev-` (page 289). Each piece
    /// used to open a paragraph of its own, and a piece whose radical sign raised its rectangle
    /// sorted a line early (#95). The pieces of one row rejoin into one line before anything reads
    /// the lines.
    ///
    /// Radical signs overshoot a row's type by most of a line above and below, so rectangle
    /// overlap alone cannot tell a row from its neighbour (page 288's last two rows overlap by 14
    /// points). Two pieces can belong to one row when they are untagged, not monospaced, at the
    /// body's size, overlap vertically as `sameRow` does, and meet horizontally in one of the ways a
    /// split row does. The right piece can start where the left one ends, within one and a half
    /// font sizes, on an edge no other line starts on (as a column or table cell would); where that
    /// gap is wider than a font size a mathematical sign stands at the join (in the left piece's last
    /// two tokens or the right piece's first two, since PDFKit writes a radicand before its sign:
    /// `81 √ = 9 but 814√`, page 292) or one piece is mathematics alone (`25 √ .`, `36· 5`). A
    /// derivation's annotation beside its step has neither (page 189's `Convert 3.21 × 105 to
    /// standard notation` and `Positive exponent means…`). The radical at the join can make them
    /// overlap in step by up to four font sizes, each extending past the other by more than half a
    /// font size. Or a radicand extracted apart from its sign (`x8` inside `√ = x4, because we`,
    /// page 290) lies within the sign's piece: narrow, without words, and clear of that piece's
    /// left edge. A short line of the next row at the column's edge (`21.`, `example.`, `equal to`,
    /// pages 9, 180 and 120) lies within the tall rectangle of a full line above it and joins
    /// nothing. No preserved image may
    /// stand between the pieces.
    ///
    /// Each piece proposes the candidates it overlaps most vertically, and proposals join strongest
    /// first, only while every piece of the growing row still shares a band at least half a font
    /// size tall: the pieces of one row all hold its baseline, whereas a chain through a tall piece
    /// reaches the next row (page 198's `then combine like terms …` beneath `− 8xy + 21xy− 14y2 and`,
    /// page 212's `12x3 + 32x. …` beneath `− 3x + 8) = 8x4`). A joined row must carry
    /// inline mathematics (a radical, operator or relation sign in one of its pieces: page 288's
    /// `squares" a number. For example, because 52` and `= 25 we say …` split at the raised 2) and
    /// read as prose on its paragraph's measure (`isProseRow`), so table rows, exercise columns and
    /// a two-column page's rows stay apart, and a stray same-size digit beside a line end is left
    /// to the rules that already read it.
    ///
    /// The joined line reads its pieces left to right by centre, keeps their styles, and occupies
    /// one line of its type: from the highest bottom edge among the pieces, as tall as the page's
    /// ordinary lines of that size, so the paragraph rules see the row's leading rather than the
    /// radical signs' overshoot.
    ///
    /// A joined row that opens with a mathematical minus before a number or a variable (page 321's
    /// radicand `− 1`, read ahead of `√ , and it is in the denominator…`) is not a list line, though
    /// `isList` reads `− ` as a bullet; its opening piece must not have been a list line on its own
    /// (#109). Such rows are returned in `mathMinusRows`, and the list rules pass over them. `isList`
    /// itself is unchanged: across the corpus a line opening with U+2212 is Wallace's alone, and the
    /// equation and derivation lines that open with one stay separate blocks.
    static func joiningRowPieces(_ lines: [TextLine], images: [CGRect], body: CGFloat) -> [TextLine] {
        joinedRows(lines, images: images, body: body).lines
    }

    static func joinedRows(_ lines: [TextLine], images: [CGRect], body: CGFloat)
        -> (lines: [TextLine], mathMinusRows: [TextLine]) {
        let sized = lines.indices.filter { index in
            let line = lines[index]
            return line.structure == nil && !line.monospaced && abs(line.fontSize - body) <= body * 0.15
                && !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard sized.count >= 2 else { return (lines, []) }
        func signed(_ text: Substring) -> Bool { text.rangeOfCharacter(from: rowMathSymbols) != nil }
        func word(_ token: Substring) -> Bool { token.filter(\.isLetter).count >= 2 }
        func candidate(_ a: TextLine, _ b: TextLine) -> Bool {
            guard sameRow(a.rect, b.rect), abs(a.fontSize - b.fontSize) <= max(a.fontSize, b.fontSize) * 0.1 else { return false }
            let (left, right) = a.rect.midX <= b.rect.midX ? (a, b) : (b, a)
            let size = max(a.fontSize, b.fontSize)
            let gap = right.rect.minX - left.rect.maxX
            if gap >= 0 {
                guard gap <= size * 1.5 else { return false }
                // A column or table cell starts on an edge other lines share; a split row's piece
                // starts wherever its radical falls.
                let aligned = lines.filter { other in
                    other != left && other != right && !sameRow(other.rect, right.rect)
                        && abs(other.rect.minX - right.rect.minX) <= 2
                }
                guard aligned.count < 2 else { return false }
                if gap > size {
                    let leftTokens = left.text.split(whereSeparator: \.isWhitespace)
                    let rightTokens = right.text.split(whereSeparator: \.isWhitespace)
                    let formulaOnly = [leftTokens, rightTokens].contains { !$0.contains(where: word) && $0.contains(where: signed) }
                    guard formulaOnly || leftTokens.suffix(2).contains(where: signed) || rightTokens.prefix(2).contains(where: signed)
                    else { return false }
                }
            } else if right.rect.minX - left.rect.minX > size * 0.5, right.rect.maxX - left.rect.maxX > size * 0.5 {
                guard -gap <= size * 4 else { return false }
            } else {
                // A radicand PDFKit extracts apart from its sign lies within the span of the piece
                // holding the sign: narrow, without words, clear of that piece's left edge, and
                // only by its own choice (`a` is the piece choosing), since a full line of the next
                // row also spans a short piece.
                guard a.rect.width < b.rect.width, a.rect.width <= size * 4,
                      !a.text.split(whereSeparator: \.isWhitespace).contains(where: word),
                      a.rect.minX >= b.rect.minX + size * 0.5, a.rect.maxX <= b.rect.maxX + 1 else { return false }
            }
            let start = min(left.rect.maxX, right.rect.minX), end = max(left.rect.maxX, right.rect.minX)
            let band = a.rect.union(b.rect)
            return !images.contains { image in
                image.minX < end && image.maxX > start && image.minY < band.maxY && image.maxY > band.minY
            }
        }
        func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat { min(a.maxY, b.maxY) - max(a.minY, b.minY) }
        var parent = Dictionary(uniqueKeysWithValues: sized.map { ($0, $0) })
        // Each row's shared band: the highest bottom and the lowest top among its pieces.
        var band = Dictionary(uniqueKeysWithValues: sized.map { ($0, (bottom: lines[$0].rect.minY, top: lines[$0].rect.maxY)) })
        func root(_ index: Int) -> Int {
            var index = index
            while let next = parent[index], next != index { index = next }
            return index
        }
        var proposals: [(piece: Int, other: Int, overlap: CGFloat)] = []
        for index in sized {
            let piece = lines[index]
            let neighbours = sized.filter { $0 != index && candidate(piece, lines[$0]) }
            guard let best = neighbours.map({ overlap(piece.rect, lines[$0].rect) }).max() else { continue }
            for other in neighbours where overlap(piece.rect, lines[other].rect) >= best - 0.01 {
                proposals.append((index, other, overlap(piece.rect, lines[other].rect)))
            }
        }
        // Strongest first; ties in page order, so the result does not depend on sorting stability.
        proposals.sort { ($0.overlap, -$0.piece, -$0.other) > ($1.overlap, -$1.piece, -$1.other) }
        for proposal in proposals {
            let a = root(proposal.piece), b = root(proposal.other)
            guard a != b, let first = band[a], let second = band[b] else { continue }
            let shared = (bottom: max(first.bottom, second.bottom), top: min(first.top, second.top))
            guard shared.top - shared.bottom >= lines[proposal.piece].fontSize * 0.5 else { continue }
            parent[b] = a
            band[a] = shared
        }
        let clusters = Dictionary(grouping: sized, by: root).values.filter { $0.count >= 2 }
        guard !clusters.isEmpty else { return (lines, []) }
        var replaced: [Int: TextLine] = [:]
        var removed = Set<Int>()
        var mathMinusRows: [TextLine] = []
        for cluster in clusters {
            let pieces = cluster.sorted { lines[$0].rect.midX < lines[$1].rect.midX }
            guard pieces.contains(where: { lines[$0].text.rangeOfCharacter(from: rowMathSymbols) != nil }),
                  isProseRow(pieces: pieces.map { lines[$0] }, in: lines, body: body) else { continue }
            var content = InlineText()
            for index in pieces {
                if !content.elements.isEmpty { content.append(InlineText(" ")) }
                content.append(lines[index].content)
            }
            // The joined row must not turn into a list line that its opening piece was not, unless
            // what reads as a marker is a minus sign before a number or variable: page 321's
            // radicand `− 1`, read ahead of `√ , and it is in the denominator…` (#109).
            var opensWithMathMinus = false
            if let opening = pieces.min(by: { lines[$0].rect.minX < lines[$1].rect.minX }),
               isList(content.text), !isList(lines[opening].text) {
                guard opensWithMinusSign(content.text) else { continue }
                opensWithMathMinus = true
            }
            let first = lines[pieces[0]], last = lines[pieces[pieces.count - 1]]
            let bounds = union(pieces.map { lines[$0].rect })
            let bottom = pieces.map { lines[$0].rect.minY }.max() ?? bounds.minY
            let height = min(bounds.maxY - bottom, ordinaryLineHeight(first.fontSize, in: lines) ?? first.rect.height)
            var joined = TextLine(content: content, rect: CGRect(x: bounds.minX, y: bottom, width: bounds.width, height: height),
                                  fontSize: first.fontSize, wraps: last.wraps)
            if pieces.contains(where: { lines[$0].readingRect != nil }) {
                joined.readingRect = union(pieces.map { lines[$0].readingRect ?? lines[$0].rect })
            }
            // The row keeps the reading position of its earliest piece in page order.
            let anchor = cluster.min()!
            replaced[anchor] = joined
            removed.formUnion(cluster.filter { $0 != anchor })
            if opensWithMathMinus { mathMinusRows.append(joined) }
        }
        return (lines.indices.compactMap { index in
            removed.contains(index) ? nil : replaced[index] ?? lines[index]
        }, mathMinusRows)
    }

    /// A line that opens with a mathematical minus (U+2212) before a number or a single-letter
    /// variable (`− 1`, `− 3x`, `− x +6y`), rather than a bullet before a word (`− Your fair dealing`,
    /// the license list on Wallace page 2).
    static func opensWithMinusSign(_ text: String) -> Bool {
        text.range(of: "^−\\s+(?:[0-9]|[A-Za-z](?![A-Za-z]))", options: .regularExpression) != nil
    }

    /// The page's ordinary line height at a size: the median height of its lines of that size.
    static func ordinaryLineHeight(_ size: CGFloat, in lines: [TextLine]) -> CGFloat? {
        let heights = lines.filter { abs($0.fontSize - size) <= size * 0.1 }.map(\.rect.height).sorted()
        return heights.isEmpty ? nil : heights[heights.count / 2]
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
                // A cut rebuilt from origin and size can fall short of an edge it shares with
                // the kept ink by rounding (FAA page 195: a figure box ending exactly at the
                // crop's top); a hundredth of a point is below any drawn distinction.
                ].filter { $0.width > 0 && $0.height > 0 && $0.insetBy(dx: -0.01, dy: -0.01).contains(kept) }
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
    ///
    /// A title can run nearly the column's width (FAA page 43's `Crew Resource Management (CRM)
    /// and`, 95% of its prose). Its width is then no evidence, but the book's typography is: a
    /// line set in a `LabelStyle` that the book's narrower section labels establish (`styles`)
    /// is a label when it passes every other test and still fits within the column (#73).
    ///
    /// A book's smallest sub-headings can be set at body size or barely above it (FAA's 10-point
    /// Helvetica-Bold `Radius of Turn` and 11-point Times-BoldItalic `Fixed-Pitch Propeller` over
    /// 10-point Times). Size is then no evidence and only the book's repeated typography is: such a
    /// line is a label when it is set entirely in bold in a `LabelStyle` of `styles`, fits the same
    /// narrow width, has clear space above it, and a paragraph opens directly beneath it on its
    /// left edge in ordinary body text (#76). `recordingSubheadings` admits every such line
    /// without a style, for `labelEvidence(on:)` to record.
    ///
    /// The book's lowest titles can be set in its body's italic (FAA's 10-point Times-Italic
    /// `Southerly Turning Errors`, `Drugs`). Where no tag sets them apart, such a line is a label
    /// on the same evidence, with the italic in place of bold: set wholly in italic in a recurring
    /// italic `LabelStyle`, in title case, not a figure or table caption, and over ordinary
    /// body text that is not itself italic, either on its left edge or as the list it heads
    /// (`opensListBeneath`). Italic emphasis inside prose has no clear space above it or no
    /// paragraph opening beneath it (#97).
    static func sectionLabels(in lines: [TextLine], body: CGFloat, headingThreshold: CGFloat,
                              page: PageContent, styles: Set<LabelStyle> = [],
                              recordingSubheadings: Bool = false) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var labels: [TextLine] = []
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            let subheading = line.fontSize < body * 1.15
            // A list item (an answer-key entry, a contents line) keeps its list representation.
            guard !line.monospaced, line.fontSize >= body * (subheading ? 0.95 : 1.15), line.fontSize < headingThreshold,
                  line.text.count >= 2, line.text.count < 200, !isList(line.text),
                  // Past an opening bracket or quote: `(EMAS)` finishes FAA page 370's title.
                  let first = line.text.first(where: { !"([\u{201C}\"'".contains($0) }),
                  first.isUppercase || first.isNumber,
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
               subheading || !(labels.contains(above) && abs(above.fontSize - line.fontSize) <= line.fontSize * 0.05) { continue }
            let letters = line.text.filter(\.isLetter)
            let capitals = letters.allSatisfy(\.isUppercase)
            let prose = column.filter { $0.fontSize < body * 1.1 }.map(\.rect.width).max() ?? 0
            if subheading {
                let style = LabelStyle(line, body: body)
                func nearestBelow(_ title: TextLine) -> TextLine? {
                    lines.filter { other in
                        other != title && other.rect.minX < title.rect.maxX && other.rect.maxX > title.rect.minX
                            && other.rect.maxY <= title.rect.minY + body * 0.4
                    }.max(by: { $0.rect.maxY < $1.rect.maxY })
                }
                // Whether `title`'s paragraph opens directly beneath it (#76, #97).
                func opens(beneath title: TextLine) -> Bool {
                    guard let below = nearestBelow(title), title.rect.minY - below.rect.maxY < body * 0.8,
                          abs(below.fontSize - body) <= body * 0.1, !LabelStyle(below, body: body).bold else { return false }
                    let paragraph = abs(below.rect.minX - line.rect.minX) <= body * 0.5 && below.rect.width > title.rect.width
                    // An italic title opens ordinary body text or a list, never more italic type.
                    return style.bold ? paragraph
                        : !LabelStyle(below, body: body).italic
                            && (paragraph && !isList(below.text) || opensListBeneath(below, title: line, body: body))
                }
                guard style.bold || style.italic && !isCaption(line.text), recordingSubheadings || styles.contains(style),
                      prose > 0, line.rect.width <= prose else { continue }
                if line.rect.width <= prose * 0.9, !style.italic || isTitleCase(line.text), opens(beneath: line) {
                    labels.append(line)
                    continue
                }
                // A sub-heading set over two lines in the book's recurring style: the second line
                // stacks under the first on its left edge at heading leading, the pair reads as
                // one title, and the paragraph opens beneath the second (FAA page 21's `The
                // Professional Air Traffic Controllers` / `Organization (PATCO) Strike`, page 404's
                // `Use of Chart Supplement U.S. (formerly Airport/` / `Facility Directory)`; #102).
                // The first line may run the column's measure, as a wrapping title does. Only a
                // style the book already repeats qualifies; pairs are no evidence of their own.
                guard styles.contains(style), let second = nearestBelow(line), LabelStyle(second, body: body) == style,
                      abs(second.fontSize - line.fontSize) <= line.fontSize * 0.1,
                      abs(second.rect.minX - line.rect.minX) <= body * 0.5, second.rect.width <= prose * 0.9,
                      stacksUnderHeading(second, after: line), !opensHeading(second.text),
                      !isList(second.text), !isContentsEntry(line.text), !isContentsEntry(second.text),
                      let end = second.text.last, !".,;:".contains(end) else { continue }
                let text = line.text + " " + second.text
                guard !style.italic || isTitleCase(text) && !isCaption(text), opens(beneath: second) else { continue }
                labels += [line, second]
                continue
            }
            if capitals || line.rect.width <= prose * 0.9 || prose == 0
                || line.rect.width <= prose && styles.contains(LabelStyle(line, body: body)) { labels.append(line) }
        }
        // Three or more labels ending in folios are a table of contents, not section labels.
        let folio = #"\s(?:\d{1,4}|[ivxlc]+(?:[–-][ivxlc]+)?)$"#
        let entries = labels.filter { $0.text.range(of: folio, options: .regularExpression) != nil }
        return entries.count >= 3 ? labels.filter { !entries.contains($0) } : labels
    }

    /// A section label's typography relative to its page: its size and the body's (to the half
    /// point), whether every word is bold, and whether a line that is not bold is wholly italic.
    /// The FAA handbook sets its section titles in 12-point bold over 10-point prose, and its
    /// lowest titles in 10-point italic (#97). A bold line never carries the italic flag, so
    /// bold and bold-italic labels keep one style between them as before.
    struct LabelStyle: Hashable {
        var size: Int
        var body: Int
        var bold: Bool
        var italic: Bool

        init(_ line: TextLine, body: CGFloat) {
            size = Int((line.fontSize * 2).rounded())
            self.body = Int((body * 2).rounded())
            func wholly(_ trait: TextStyle) -> Bool {
                line.content.elements.allSatisfy { element in
                    guard case let .text(value, style) = element else { return true }
                    return style.contains(trait) || value.allSatisfy(\.isWhitespace)
                }
            }
            bold = wholly(.bold)
            italic = !bold && wholly(.italic)
        }
    }

    /// A title set in title case: at most ten words, every word of four or more letters
    /// capitalised (`Coupled Ailerons and Rudder`, `Southerly Turning Errors`). An italic phrase
    /// in prose or an italic sentence is rarely set so (#90, #97).
    static func isTitleCase(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.count <= 10 && words.allSatisfy { word in
            let letters = word.drop { !$0.isLetter }
            return letters.filter(\.isLetter).count < 4 || letters.first?.isUppercase == true
        }
    }

    /// A list line set directly beneath a title opens the list the title heads: its marker
    /// stands on the title's left edge or up to 2.5 em inside it (FAA page 48 indents its
    /// bullets 9 points under `Airport` and `Airspace`; #97).
    static func opensListBeneath(_ below: TextLine, title: TextLine, body: CGFloat) -> Bool {
        let indent = below.rect.minX - title.rect.minX
        return isList(below.text) && indent >= -body * 0.5 && indent <= body * 2.5
    }

    /// The label styles one page's narrow section labels establish, measured as `blocks` measures
    /// them but before image regions are known: lines inside a painted graphic, running heads and
    /// margin lines are no evidence. `labelStyles(from:)` keeps the styles that recur.
    static func labelEvidence(on page: PageContent) -> Set<LabelStyle> {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        let figures = page.graphics.filter { !isThinRule($0) }
        let lines = page.lines.map { line -> TextLine in
            var copy = line; copy.structure = nil; return copy
        }.filter { line in
            !figures.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) }
                && !inMargin(line, of: page) && !isHeaderLike(line, in: page, bothBands: true)
        }
        let body = max(4, bodySize(page.lines))
        let boxes = clusters(page.tints, distance: 4)
        let outside = lines.filter { line in !boxes.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }
        let reflowBody = headingBodySize(outside, pageBody: body)
        let threshold = max(body * 1.25, reflowBody * 1.1)
        return Set(sectionLabels(in: lines, body: reflowBody, headingThreshold: threshold, page: page,
                                 recordingSubheadings: true)
            .filter { !isContentsEntry($0.text) }.map { LabelStyle($0, body: reflowBody) })
    }

    /// The styles of one page's heading-size lines (at or past the page's heading threshold),
    /// measured as `labelEvidence(on:)` measures labels: lines inside a painted graphic, running
    /// heads and contents entries are no evidence, and neither is a line with fewer than two
    /// letters (a drop cap, a numeral, a folio such as `C-1`). The margin bands stay in: a chapter
    /// label sits high on its opening page. `labelStyles(from:)` keeps the styles that recur: the
    /// FAA handbook opens each chapter with a 16-point `Chapter N` over a 48-point title (#84).
    static func headingEvidence(on page: PageContent) -> Set<LabelStyle> {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        let figures = page.graphics.filter { !isThinRule($0) }
        let lines = page.lines.map { line -> TextLine in
            var copy = line; copy.structure = nil; return copy
        }.filter { line in
            !figures.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) }
                && !isHeaderLike(line, in: page, bothBands: true)
        }
        let body = max(4, bodySize(page.lines))
        let boxes = clusters(page.tints, distance: 4)
        let outside = lines.filter { line in !boxes.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }
        let reflowBody = headingBodySize(outside, pageBody: body)
        let threshold = max(body * 1.25, reflowBody * 1.1)
        return Set(lines.filter { line in
            !line.monospaced && line.fontSize >= threshold && line.text.count < 200
                && line.text.filter(\.isLetter).count >= 2 && line.rect.width >= line.rect.height
                && !isContentsEntry(line.text)
        }.map { LabelStyle($0, body: reflowBody) })
    }

    /// A style is the book's label typography once narrow labels set in it appear on at least
    /// three pages; `pages` counts the pages whose evidence names each style. The same count
    /// selects the book's recurring heading styles from `headingEvidence(on:)`.
    static func labelStyles(from pages: [LabelStyle: Int]) -> Set<LabelStyle> {
        Set(pages.filter { $0.value >= 3 }.keys)
    }

    /// The titles of tinted boxes set in the box's own text size (#100). The Fed's narrow sidebars
    /// open with an 8-point demibold title over 8-point book text (`A fresh look at the monetary
    /// policy framework`), below the page's heading size and label band, and PDFKit names both
    /// fonts `Helvetica`, so no bold run marks the title either. The box's spacing does: the title
    /// is the top line of the box's text column, set off from the text beneath by more than that
    /// text's own leading (15.6-point pitch over 12). A title set over two lines keeps its lines at
    /// no more than that leading (10-point pitch) and sets the space after its second line
    /// (`Finding data on institutions supervised by the` / `Federal Reserve`).
    ///
    /// The box's lines are read top to bottom as they stand, so the line directly beneath the title
    /// and the next one below it are the box's next two lines, whatever their edge: the text
    /// beneath continues on the title's left edge at the title's size (the leading between those
    /// two lines is measured, not assumed). A paragraph that opens on a first-line indent is no
    /// title's text: the 9/11 report's page 348 sidebar indents `The FBI interviewed…` under a
    /// two-line paragraph. The title reads as one: a capital, digit or quotation mark first, no
    /// closing `.`, `,`, `;` or `:` before any raised note marker (`…allowed to depart.30`; a
    /// question stays a title: `What does “systemically important” mean?`), no list marker or
    /// leader, and no line wider than the box's text measure (the title can outrun the ragged line
    /// directly beneath it, page 19). A box whose first paragraph ends a sentence before paragraph
    /// space (the Fed's page 63 `…den’s Riksbank was formed.`) has no title; a box title at heading
    /// size is a heading already. Recognized and synthetic pages have no trustworthy sizes.
    static func boxTitles(in lines: [TextLine], page: PageContent) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var titles: [TextLine] = []
        for hull in clusters(page.tints, distance: 4) {
            let stack = lines.filter { hull.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                .sorted { $0.rect.maxY > $1.rect.maxY }
            guard let first = stack.first else { continue }
            let size = first.fontSize
            // One line to a row: a row PDFKit split (or two columns) is no stack of lines.
            guard stack.count >= 3, !zip(stack, stack.dropFirst()).prefix(3).contains(where: { sameRow($0.rect, $1.rect) })
            else { continue }
            for count in 1...2 where stack.count >= count + 2 {
                let title = Array(stack.prefix(count))
                let below = stack[count]
                let next = stack[count + 1]
                guard (title + [below]).allSatisfy({ abs($0.rect.minX - first.rect.minX) <= size * 0.5
                          && abs($0.fontSize - size) <= size * 0.1 }),
                      abs(next.fontSize - size) <= size * 0.1 else { break }
                let leading = below.rect.minY - next.rect.maxY
                let gap = title[count - 1].rect.minY - below.rect.maxY
                let measure = stack.dropFirst(count).filter { abs($0.rect.minX - first.rect.minX) <= size * 0.5 }
                    .map(\.rect.width).max() ?? 0
                let text = title.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                guard gap >= leading + size * 0.25, gap <= size * 2.5, leading >= -size * 0.4,
                      zip(title, title.dropFirst()).allSatisfy({ $0.rect.minY - $1.rect.maxY <= leading + size * 0.1 }),
                      title.allSatisfy({ $0.rect.width <= measure + size * 0.5 }),
                      text.count < 150, text.filter(\.isLetter).count >= 2,
                      let initial = text.first(where: { !"([\u{201C}\"'".contains($0) }), initial.isUppercase || initial.isNumber,
                      let last = lastCharacterBeforeMarker(title[count - 1]), !".,;:".contains(last),
                      !title.contains(where: { isList($0.text) || isContentsEntry($0.text) || $0.text.contains("....") })
                else { continue }
                titles += title
                break
            }
        }
        return titles
    }

    /// A line's last visible character past closing quotes and brackets and past a raised
    /// reference marker (`…allowed to depart.30`), as `opensSection` reads a sentence's end.
    private static func lastCharacterBeforeMarker(_ line: TextLine) -> Character? {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        for element in line.content.elements.reversed() {
            guard case let .text(value, style) = element else { continue }
            if style.contains(.superscript), value.allSatisfy({ $0.isNumber || $0.isWhitespace }) { continue }
            if let character = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) { return character }
        }
        return nil
    }

    /// A contents entry: a dot leader of four or more dots running to the line's end, with or
    /// without its folio (PDFKit can split the folio into a same-row line). Contents pages set
    /// their chapter entries at heading size, but a leader never ends a heading (#55). The folio
    /// can be numbered within its chapter or lettered part (`Introduction To Flying.......1-1`,
    /// `Glossary.......G-1`; #97).
    static func isContentsEntry(_ text: String) -> Bool {
        text.range(of: #"(?:\.\s*){4,}(?:\d{1,4}|[ivxlcdm]{1,8}|(?:\d{1,3}|[a-z])[-–]\d{1,4})?\s*$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether `line` is the next line of the heading `previous` opens: the same size, set
    /// directly beneath it at ordinary heading leading (the rectangles include PDFKit's
    /// leading, so they touch or overlap), sharing the left edge, the centre or the right edge.
    ///
    /// With `hanging`, the line may instead start under the previous line's text past its
    /// section number: acmart indents `OVERHEAD` under `REPRESENTATION` in `6 REPRESENTATION OF
    /// REPCL AND ITS` (#83), and the 9/11 report `LAW ENFORCEMENT COMMUNITY` under `3.2
    /// ADAPTATION—AND NONADAPTATION—IN THE`. The indent is past the shared edge but no wider than
    /// the number and its space can be set: 0.6 em per character and one em for the space.
    static func stacksUnderHeading(_ line: TextLine, after previous: TextLine, hanging: Bool = false) -> Bool {
        let size = max(previous.fontSize, line.fontSize)
        guard abs(previous.fontSize - line.fontSize) <= size * 0.1, !sameRow(previous.rect, line.rect),
              line.rect.minY < previous.rect.minY, line.rect.maxY >= previous.rect.minY - size,
              previous.rect.minY - line.rect.minY <= size * 2.2 else { return false }
        if abs(previous.rect.minX - line.rect.minX) <= size * 0.6
            || abs(previous.rect.midX - line.rect.midX) <= size * 0.6
            || abs(previous.rect.maxX - line.rect.maxX) <= size * 0.6 { return true }
        guard hanging, let number = previous.text.range(of: #"^\d+(?:\.\d+)*\.?(?=\s+\S)"#, options: .regularExpression)
        else { return false }
        let indent = line.rect.minX - previous.rect.minX
        let characters = CGFloat(previous.text.distance(from: number.lowerBound, to: number.upperBound))
        return indent > size * 0.6 && indent <= size * (0.6 * characters + 1)
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
    /// end a sentence, and the line does not open a numbered heading of its own (#55). A line
    /// hanging under a numbered first line's text continues it too (#83).
    static func continuesHeading(_ heading: String, with line: TextLine, after previous: TextLine) -> Bool {
        stacksUnderHeading(line, after: previous, hanging: heading == previous.text)
            && !endsSentence(heading) && !opensHeading(line.text)
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

    private static let mathSymbols = CharacterSet(charactersIn: "∫∑∏√∂∇≈≠≤≥∞")
    /// Signs of inline mathematics at which PDFKit splits a prose row (`joiningRowPieces`).
    private static let rowMathSymbols = mathSymbols.union(CharacterSet(charactersIn: "=·×÷±−"))

    /// Letters-only words of at least `minimum` letters (surrounding quotes, brackets and
    /// punctuation ignored) and the number of whitespace-separated tokens.
    private static func wordShare(_ text: String, minimum: Int = 3) -> (words: Int, tokens: Int) {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let edges = CharacterSet(charactersIn: "\"'“”‘’()[]{}.,;:!?")
        let words = tokens.filter { token in
            let core = String(token).trimmingCharacters(in: edges)
            return core.count >= minimum && core.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
        }.count
        return (words, tokens.count)
    }

    /// Text that reads as words: at least two words of three or more letters, and words of two
    /// or more letters making up at least 40% of the tokens. Prose dense with inline mathematics
    /// (`is where x = 0 and y = 0. As we move`) stays above that share, single-letter variables
    /// do not count; whether a wordy row is prose is decided by its measure.
    private static func isWordy(_ text: String) -> Bool {
        let share = wordShare(text, minimum: 2)
        return wordShare(text).words >= 2 && share.words * 5 >= share.tokens * 2
    }

    private static let functionWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "for", "from", "if", "in", "is",
        "it", "not", "of", "on", "or", "our", "so", "that", "the", "then", "there", "these", "this",
        "to", "was", "we", "when", "which", "will", "with",
    ]

    /// Words set as a sentence carry function words (`the`, `we`, `is`, `of`). A stacked display
    /// set the full measure reads as terms and names alone (`sin⁻¹(opposite/hypotenuse) = θ …`,
    /// Wallace page 428), however many letters its words have.
    private static func readsAsSentence(_ text: String) -> Bool {
        let edges = CharacterSet(charactersIn: "\"'“”‘’()[]{}.,;:!?")
        return text.split(whereSeparator: \.isWhitespace).contains {
            functionWords.contains(String($0).trimmingCharacters(in: edges).lowercased())
        }
    }

    /// The pieces of a line's visual row that read with it. PDFKit splits a prose row at an
    /// inline radical or superscript (`The square root of 25 is written as` / `25 √ .`); the
    /// pieces sit beside each other with text above or below spanning the gap between them,
    /// whereas a column gutter stays blank.
    private static func rowPieces(_ line: TextLine, in lines: [TextLine], body: CGFloat) -> [TextLine] {
        let candidates = lines.filter { $0 != line && sameRow($0.rect, line.rect) }
        var row = [line]
        var changed = true
        while changed {
            changed = false
            for piece in candidates where !row.contains(piece) {
                let joins = row.contains { member in
                    let start = min(member.rect.maxX, piece.rect.maxX), end = max(member.rect.minX, piece.rect.minX)
                    guard end > start else { return true }
                    guard end - start <= body * 2 else { return false }
                    return lines.contains { other in
                        !row.contains(other) && other != piece && !sameRow(other.rect, line.rect)
                            && other.rect.minX <= start && other.rect.maxX >= end
                            && max(other.rect.minY - line.rect.maxY, line.rect.minY - other.rect.maxY) <= body * 2
                    }
                }
                if joins { row.append(piece); changed = true }
            }
        }
        return row
    }

    /// A line whose visual row is prose: the row reads as a sentence and is set on its
    /// paragraph's measure. Either it is a full line of a justified paragraph (at least three
    /// other prose lines on the page share both of its edges, or two with one adjacent at
    /// ordinary leading), or an adjacent full line shares its left or right edge (a paragraph's
    /// indented first or short last line). An inline equation in such a row (`since the maximum
    /// driven velocity Uo = eEo/mw becomes`, NBS page 7; `We can use the product rule to
    /// simplify an expression such as √36·5`, Wallace page 288) is read as text (#51, #58). A
    /// displayed derivation is set apart from the paragraph's edges and stays a formula; a
    /// repeated annotation (`Change the signs and combine`, set three times down Wallace page
    /// 207 at one indent) shares edges with its repeats but has no adjacent full line.
    static func isProseRow(_ line: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        isProseRow(pieces: rowPieces(line, in: lines, body: body), in: lines, body: body)
    }

    /// `isProseRow` for a row whose pieces are already known; the first piece stands for the row.
    private static func isProseRow(pieces row: [TextLine], in lines: [TextLine], body: CGFloat) -> Bool {
        guard let line = row.first else { return false }
        let text = row.map(\.text).joined(separator: " ")
        // A row whose pieces stand at least twice their type size stacks terms (fractions,
        // radical indices) and has spatial structure to preserve unless it reads as a sentence.
        // A single-level row keeps no structure a line of text cannot carry, so a word equation
        // set in the column's measure (`True Course (180°) ± Variation (+10°) = Magnetic
        // Course`, FAA page 227) reads as the text it is.
        let stacked = row.contains { $0.rect.height >= $0.fontSize * 2 }
        guard isWordy(text), !stacked || readsAsSentence(text) else { return false }
        let bounds = union(row.map(\.rect))
        let prose = lines.filter { other in
            !other.monospaced && wordShare(other.text).words >= 4 && isWordy(other.text)
        }
        func sharesEdges(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 2 && abs(a.maxX - b.maxX) <= 2
        }
        func adjacent(_ a: CGRect, _ b: CGRect) -> Bool {
            max(a.minY - b.maxY, b.minY - a.maxY) <= body * 2
        }
        func fullLine(_ rect: CGRect, excluding: [TextLine]) -> Bool {
            let sharing = prose.filter { !excluding.contains($0) && sharesEdges($0.rect, rect) }
            return sharing.count >= 3 || (sharing.count == 2 && sharing.contains { adjacent($0.rect, rect) })
        }
        if fullLine(bounds, excluding: row) { return true }
        return prose.contains { other in
            !row.contains(other) && fullLine(other.rect, excluding: [other])
                && !sameRow(other.rect, line.rect) && adjacent(other.rect, bounds)
                && min(bounds.maxX, other.rect.maxX) > max(bounds.minX, other.rect.minX)
                && (abs(other.rect.minX - bounds.minX) <= 2 || abs(other.rect.maxX - bounds.maxX) <= 2)
        }
    }

    /// A text line a formula's margin must not reach: prose, or a row of words alone above the
    /// formula, an instruction or label introducing it (`Simplify.` over the page-291 exercises).
    /// A line carrying any term, number or operator (`Find g(3)+ f(3)` closing a page-398
    /// exercise) can belong to the formula beside it, and so can words that share their row with
    /// other pieces (a derivation's `Our Solution`) or conclude it from beneath (`Infinite
    /// solutions Our Solution`, page 149).
    private static func isTextNeighbour(_ line: TextLine, above: Bool, in lines: [TextLine], body: CGFloat) -> Bool {
        let edges = CharacterSet(charactersIn: "\"'“”‘’.,;:!?")
        let tokens = line.text.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: edges) }
        // Words of two or more letters: a single letter is a variable (`y Use two variables, x
        // and y` opens a page-359 derivation row).
        if above, wordShare(line.text).words >= 1,
           tokens.allSatisfy({ $0.count >= 2 && $0.unicodeScalars.allSatisfy(CharacterSet.letters.contains) }),
           !lines.contains(where: { $0 != line && sameRow($0.rect, line.rect) }) {
            return true
        }
        return isProseRow(line, in: lines, body: body)
    }

    /// A word whose equals signs belong to a web address's query string, not an equation: an
    /// address with a query (`…/print.php3?ReportID=145).`, `www.nftc.org/…?Mode=View&…`), or
    /// the wrapped rest of one, two or more `name=value` pairs joined by `&`
    /// (`item_id=1645&content_type_id=7).`). 9/11 notes pages 571 and 581–583 lost the lines
    /// around such addresses to formula crops (#80).
    static func isURLQuery(_ word: Substring) -> Bool {
        if let query = word.firstIndex(of: "?"), let equals = word.firstIndex(of: "="), query < equals,
           word[..<query].contains(where: { $0 == "/" || $0 == "." }) { return true }
        return word.range(of: #"(?:^|[(?&])[A-Za-z_][A-Za-z0-9_.-]*=[^\s&=]*(?:&[A-Za-z_][A-Za-z0-9_.-]*=[^\s&=]*)+[).,;]*$"#,
                          options: .regularExpression) != nil
    }

    /// A title that spells out a mnemonic's letter, set wholly in bold: one capital letter, an
    /// equals sign and a capitalised word of three or more letters, then words of two or more (the FAA's
    /// PAVE checklist titles `A = Aircraft` and `V = EnVironment`, pages 47–48). It carries no
    /// term, number or operator besides the sign, so it is not a displayed equation; as a formula
    /// seed its crop took the title and the italic title beneath it out of the text (#97).
    static func isLetterMnemonic(_ line: TextLine) -> Bool {
        LabelStyle(line, body: line.fontSize).bold
            && line.text.range(of: #"^\p{Lu} = \p{Lu}\p{L}{2,}(?: [\p{L}()]{2,}){0,6}$"#, options: .regularExpression) != nil
    }

    /// Expand crops to whole intersecting text lines so a label cannot be cut in half.
    static func graphicsWithLabels(_ page: PageContent) -> [CGRect] {
        let body = max(4, bodySize(page.lines))
        // Displayed formulas have spatial meaning (superscripts, fractions, aligned terms)
        // that line concatenation cannot reproduce. Preserve recognizable formulas as crops.
        // A prose row with inline mathematics is not a displayed formula, and a formula's
        // margin (raised and lowered terms, radical bars) stops short of neighbouring text.
        // A contents entry is no display either: FAA page 6 lists the PAVE checklist's `A =
        // Aircraft` and `V = EnVironment` in plain type with their leaders, and their crop took
        // the column's last four entries out of the contents (#102).
        let formulas = page.lines.filter { line in
            guard !line.monospaced, line.text.count < 160, !isContentsEntry(line.text) else { return false }
            let symbols = line.text.rangeOfCharacter(from: mathSymbols) != nil
            let words = line.text.split(whereSeparator: \.isWhitespace)
            let equation = words.count <= 12 && words.contains { $0.contains("=") && !isURLQuery($0) }
                && !isLetterMnemonic(line)
            return (symbols || equation) && !isProseRow(line, in: page.lines, body: body)
        }.map { line -> CGRect in
            var seed = line.rect.insetBy(dx: -4, dy: -8)
            for other in page.lines where other != line && seed.intersects(other.rect)
                && !sameRow(other.rect, line.rect)
                && isTextNeighbour(other, above: other.rect.midY > line.rect.midY, in: page.lines, body: body) {
                if other.rect.midY > line.rect.midY {
                    let top = max(line.rect.maxY, min(seed.maxY, other.rect.minY - 0.5))
                    seed.size.height = top - seed.minY
                } else {
                    let bottom = min(line.rect.minY, max(seed.minY, other.rect.maxY + 0.5))
                    seed.size.height = seed.maxY - bottom
                    seed.origin.y = bottom
                }
            }
            return seed
        }
        // A rule underlining one text line is that text's decoration, not a figure. Rows of
        // column-header underlines are table evidence instead (#36).
        let tables = TableRegionDetector.underlinedColumnRegions(in: page)
        let floats = algorithmFloats(in: page)
        func owner(of rect: CGRect) -> TextLine? {
            page.lines.first { line in
                rect.minX >= line.rect.minX - body && rect.maxX <= line.rect.maxX + body
                    && rect.midY >= line.rect.minY - 3 && rect.midY <= line.rect.maxY
            }
        }
        let otherSeeds = formulas + TableRegionDetector.regions(in: page) + FractionRegionDetector.regions(in: page)
            + tables + floats.regions
        let graphics = page.graphics.compactMap { rect -> CGRect? in
            // A radical's bar inside a prose row decorates that row (`is written as √25.`, `if
            // we found √8 on`): the tall rectangle PDFKit gives the radical piece would otherwise
            // read as a fraction's terms around it, and a bar over one or two digits is shorter
            // than a rule (#58). Only a row that carries the radical sign qualifies; any other
            // small mark touching prose keeps its line.
            if rect.height <= 6, rect.width > rect.height, let owner = owner(of: rect),
               rowPieces(owner, in: page.lines, body: body).contains(where: { $0.text.rangeOfCharacter(from: mathSymbols) != nil }),
               isProseRow(owner, in: page.lines, body: body) {
                return nil
            }
            guard isThinRule(rect) else { return rect }
            if tables.contains(where: { $0.contains(rect) }) || floats.decorations.contains(rect) { return nil }
            // A fraction bar keeps the terms it touches, as any intersecting graphic does.
            if isFractionBar(rect, in: page.lines, body: body) {
                return page.lines.filter { rect.intersects($0.rect) }.reduce(rect) { $0.union($1.rect) }
            }
            // A rule inside one line's box belongs to that line: a radical's vinculum or an
            // exercise bar keeps its short mathematical line; an underline beneath prose is
            // decoration. A rule outside every line stays an isolated graphic unless it is a
            // page's decoration rule (#66).
            guard let owner = owner(of: rect) else {
                let isolated = !page.graphics.contains { $0 != rect && $0.insetBy(dx: -4, dy: -4).intersects(rect) }
                    && !otherSeeds.contains { $0.insetBy(dx: -4, dy: -4).intersects(rect) }
                return isolated && isDecorationRule(rect, in: page.lines, bounds: page.bounds, body: body) ? nil : rect
            }
            let mathematical = owner.text.count <= 40 && !owner.monospaced
                && owner.text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil
            return mathematical ? rect.union(owner.rect) : nil
        }
        let seeds = graphics + otherSeeds
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

    // Recursive whitespace cuts: columns first, except that a single-line heading band above
    // them is cut off first (`headingBand`); a spanning heading is separated by a horizontal cut
    // before retrying columns; a gutter hidden by overhanging figures is measured over text last.
    // No page-wide y/x sort of interleaved column text.
    static func ordered(_ elements: [Element], bodySize: CGFloat, depth: Int = 0) -> [Element] {
        guard elements.count > 1, depth < 32 else { return elements }
        /// The widest whitespace band in one direction, measured over `measured`. The cut is
        /// kept only when every element of the region falls wholly on one side of it: ordering
        /// drops an element that straddles its cut, so a subset may not choose a line that the
        /// elements it leaves out would cross.
        func gap(horizontal: Bool, measuring measured: [Element], in part: [Element]? = nil) -> CGFloat? {
            let region = part ?? elements
            guard measured.count > 1 else { return nil }
            let intervals = measured.map { horizontal ? ($0.rect.minX, $0.rect.maxX) : ($0.rect.minY, $0.rect.maxY) }
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
                        let left = region.filter { $0.rect.maxX < middle }
                        let right = region.filter { $0.rect.minX > middle }
                        let proseColumns = [left, right].allSatisfy { column in
                            column.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }.count >= 2
                        }
                        if !proseColumns { end = max(end, interval.1); continue }
                    }
                    best = (width, middle)
                }
                end = max(end, interval.1)
            }
            guard let middle = best?.1, region.allSatisfy({
                horizontal ? ($0.rect.maxX < middle || $0.rect.minX > middle)
                    : ($0.rect.maxY < middle || $0.rect.minY > middle)
            }) else { return nil }
            return middle
        }
        if let x = gap(horizontal: true, measuring: elements) {
            if let y = headingBand(elements, gutter: x, bodySize: bodySize) {
                return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                    + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
            }
            if let y = stackedBlocks(elements, gutter: x, bodySize: bodySize) {
                return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                    + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
            }
            let columns = ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX > x }, bodySize: bodySize, depth: depth + 1)
            // Cells numbered along their rows read in number order, not down each column (#78).
            if let labels = rowMajorLabels(elements, bodySize: bodySize) {
                return inNumberOrder(columns, labels: labels)
            }
            return columns
        }
        if let y = gap(horizontal: false, measuring: elements) {
            // Two prose columns can break a paragraph at the same height, and when a figure across
            // their full measure closes the gutter, that aligned paragraph space is the widest
            // whitespace: FAA page 439's drug table and page 392's time-zone map read left, right,
            // left, right (#86). A band no wider than paragraph spacing gives way to the figure
            // partition (`spanningFigures`); Our Flag's state grids band their rows with 62 pt.
            let width = horizontalBands(elements).first { abs($0.y - y) < 0.01 }?.width ?? .greatestFiniteMagnitude
            if width <= bodySize * 1.5, let parts = spanningFigures(elements, bodySize: bodySize, gutter: {
                gap(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0)
            }) {
                return ordered(parts.head, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.columns, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.foot, bodySize: bodySize, depth: depth + 1)
            }
            // A heading left alone at the foot of the part above heads the part below (#103).
            let y = trailingHeading(elements, cut: y, bodySize: bodySize) ?? y
            return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
        }
        // A preserved figure or table is set to its column's measure, but its rectangle can
        // overhang the prose by a few points and swallow the gutter: the FAA's pages 165, 199
        // and 262 keep 11.6–11.9 pt of whitespace between their text columns — the same measure
        // the page-91 and -511 columns are cut on — while figures at the columns' heads narrow
        // it to 6.5–7.4 pt, under the 0.75-body test, so those pages find no cut at all and
        // fall through to the reading-order sort, which interleaves them line by line (#56).
        // Measured over the text lines alone the gutter is there; it is taken only once neither
        // whitespace cut has found anything, so a page whose rows are banded horizontally — Our
        // Flag's four-to-a-page state grids, whose folio sits in the gutter 3.6 pt from the
        // flags while 62 pt of whitespace separates the rows — is still cut into its rows first.
        // The cut is kept only when every figure falls wholly on one side of it, so a figure
        // heading a column joins that column instead of bridging both.
        if let x = gap(horizontal: true, measuring: elements.filter { $0.line != nil }) {
            return ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX > x }, bodySize: bodySize, depth: depth + 1)
        }
        // A figure set across the full measure above or below two columns, its rectangle within
        // a few points of the columns' first or last lines (#86, `spanningFigures`).
        if let parts = spanningFigures(elements, bodySize: bodySize, gutter: {
            gap(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0)
        }) {
            return ordered(parts.head, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.columns, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.foot, bodySize: bodySize, depth: depth + 1)
        }
        // A heading set in a row with a figure divides the sections above and below it (#103).
        if let parts = headingRow(elements, bodySize: bodySize) {
            return ordered(parts.above, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.row, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.below, bodySize: bodySize, depth: depth + 1)
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

    /// A line set above columns heads all of them, but it need not span the gutter that
    /// separates them. Wallace's answer keys centre `Answers - Chapter 0` and each
    /// `Answers - <topic>` label on the page while column 1 begins far to their left, so the
    /// page's widest whitespace is column 1's gutter and the title is cut away with columns 2
    /// and 3, reading after column 1's whole answer list; the section numbers `0.1` and `8.1`,
    /// set over column 1 alone, were read with that column instead of ahead of every column
    /// they number (#47).
    ///
    /// Given the gutter the whitespace test would otherwise cut, the region's horizontal
    /// whitespace divides it into bands, read here from the top. A band that is a single text
    /// line — a title, a section number, a table's label — heads the columns and is separated
    /// by a horizontal cut first. Returns that cut: the whitespace above the line when anything
    /// precedes it, otherwise the whitespace below it. Any other band is column content and is
    /// passed over. Two or more lines at ordinary leading are a paragraph, which belongs to the
    /// column it sits in even when it stands clear of the other column: the CDC comic's speech
    /// balloons are spaced exactly as labels are, and reading one ahead of the panel beside it
    /// breaks the panel order.
    ///
    /// The columns must still run beside each other beneath the band, or the search ends. A
    /// column that has ended keeps its own continuation: the FAA's glossary page 511 fills its
    /// left column below the last entry of the right one, with only the printed folio beyond
    /// the gutter, and a cut there would read the tail of the left column after the right
    /// column instead of before it. Bands are found at 0.8 body rather than the 1.1 the
    /// whitespace cut demands, because a label sits closer to the column it heads than to the
    /// label above it (Wallace page 438 sets `Answers - Integers` 10.7 pt over 12-point
    /// answers); a row of the columns themselves is never a single line, so the looser measure
    /// cannot cut one.
    static func headingBand(_ elements: [Element], gutter: CGFloat, bodySize: CGFloat) -> CGFloat? {
        let intervals = elements.map { ($0.rect.minY, $0.rect.maxY) }.sorted { $0.0 < $1.0 }
        guard let first = intervals.first else { return nil }
        var end = first.1
        var cuts: [CGFloat] = []
        for interval in intervals.dropFirst() {
            if interval.0 - end > bodySize * 0.8 { cuts.append((end + interval.0) / 2) }
            end = max(end, interval.1)
        }
        let boundaries = Array(cuts.reversed())
        for (index, lower) in boundaries.enumerated() {
            let below = elements.filter { $0.rect.maxY < lower }
            let left = below.filter { $0.rect.maxX < gutter }, right = below.filter { $0.rect.minX > gutter }
            guard !left.isEmpty, !right.isEmpty else { return nil }
            let leftRange = union(left.map(\.rect)), rightRange = union(right.map(\.rect))
            guard min(leftRange.maxY, rightRange.maxY) > max(leftRange.minY, rightRange.minY) else { return nil }
            let upper = index == 0 ? CGFloat.greatestFiniteMagnitude : boundaries[index - 1]
            let band = elements.filter { $0.rect.minY > lower && $0.rect.maxY < upper }
            if band.count == 1, band[0].line != nil { return index == 0 ? lower : upper }
        }
        return nil
    }

    /// A line set in heading type: at least the 1.25 bodies `blocks` demands of a heading, and
    /// not a list line.
    private static func isHeadingType(_ element: Element, bodySize: CGFloat) -> Bool {
        guard let line = element.line, !line.monospaced else { return false }
        return line.fontSize >= bodySize * 1.25 && !isList(line.text)
    }

    /// A horizontal cut can find as much whitespace below a heading as above it. DGA page 4 sets
    /// `Incorporate Healthy Fats` 13.89 pt under the columns before it and 13.91 pt over its own
    /// bullets, so the widest band leaves it at the foot of the part above; there the gutter cut
    /// reads it with the left column, ahead of the right column's last bullet and its sub-items
    /// (#103). Given the cut, when everything beneath the lowest band of more than 1.1 body in the
    /// part above is one or two lines in heading type, returns that band instead: the heading
    /// reads first in the part below, the content it introduces. Nil when the cut stands.
    static func trailingHeading(_ elements: [Element], cut: CGFloat, bodySize: CGFloat) -> CGFloat? {
        let upper = elements.filter { $0.rect.minY > cut }
        // Every element of the part falls on one side of each band `horizontalBands` reports.
        guard let band = horizontalBands(upper).last(where: { $0.width > bodySize * 1.1 }) else { return nil }
        let tail = upper.filter { $0.rect.maxY < band.y }
        guard (1...2).contains(tail.count), tail.allSatisfy({ isHeadingType($0, bodySize: bodySize) }) else { return nil }
        return band.y
    }

    /// Stacked sections whose rows sit closer than the whitespace cut's 1.1 body, each a heading
    /// with a decorative band across the measure over two columns, give no cut at all: the band
    /// hides the gutter and the sort interleaves the columns line by line. DGA page 9 sets
    /// `Older Adults` beside its band 8.4 pt over its columns and 10.5 pt under the section
    /// above; where the tags fall back, its one bullet read across both columns a line at a time
    /// (#103). A heading-type line and the figures in its row, with nothing else reaching into
    /// the row's height, separate what is above them from what is below: the parts are read in
    /// turn, each cut on its own. Returns nil unless there is content on both sides of the row.
    static func headingRow(_ elements: [Element], bodySize: CGFloat)
        -> (above: [Element], row: [Element], below: [Element])? {
        for heading in elements.filter({ isHeadingType($0, bodySize: bodySize) }).sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            let row = elements.filter { $0.rect.minY < heading.rect.maxY && $0.rect.maxY > heading.rect.minY }
            guard row.contains(where: { $0.line == nil && $0.box == nil }) else { continue }
            let extent = union(row.map(\.rect))
            let above = elements.filter { $0.rect.minY >= extent.maxY }
            let below = elements.filter { $0.rect.maxY <= extent.minY }
            guard !above.isEmpty, !below.isEmpty, above.count + row.count + below.count == elements.count else { continue }
            return (above, row, below)
        }
        return nil
    }

    /// Whitespace bands across a region, top to bottom: the midpoint of each band and its height.
    static func horizontalBands(_ elements: [Element]) -> [(y: CGFloat, width: CGFloat)] {
        let intervals = elements.map { ($0.rect.minY, $0.rect.maxY) }.sorted { $0.1 > $1.1 }
        guard var floor = intervals.first?.0 else { return [] }
        var bands: [(y: CGFloat, width: CGFloat)] = []
        for interval in intervals.dropFirst() {
            if interval.1 < floor { bands.append(((floor + interval.1) / 2, floor - interval.1)) }
            floor = min(floor, interval.0)
        }
        return bands
    }

    /// A figure set across both columns' full measure, above or below them, bridges their
    /// gutter, so the text-measured gutter refuses to cut it; when its rectangle comes within
    /// 1.1 body of the columns' first or last lines no horizontal band separates it either, and
    /// the page falls to the reading-order sort, which interleaves the columns line by line.
    /// FAA page 340's runway figure ends 0.7 pt above the columns' headings, and page 401's two
    /// wind-triangle figures begin 8 pt below the left column's last line with a caption under
    /// them (#86). A crop can also come nearer still: page 108's ground-effect figure rises to
    /// within a few points of both columns' last lines, and page 19's airmail map to the lines
    /// beneath it, so no whitespace band isolates the figure without taking column lines too.
    ///
    /// The figures are therefore separated by partition, not by a cut. The gutter is measured
    /// over the text lines other than captions (`Figure N`/`Table N` lines and the lines wrapped
    /// beneath them). The figures that straddle it must all lie above the columns' first line or
    /// below their last (within half a body); a figure between two blocks of columns is not
    /// moved. Every other element, captions set beside the columns included, must fall wholly on
    /// one side of a gutter that separates prose on both sides (two lines at least 12 bodies wide
    /// each): short cells keep their row associations. A caption whose lines all lie beyond the
    /// columns goes with the figures, unless it sits against a figure of the columns' own: page
    /// 194's `Figure 7-38` under its photo stays with the left column, as does page 19's photo
    /// caption, whose first line stands beside the right column's last lines. Returns the figures
    /// and captions read before the columns, the columns, and those read after them; nil when the
    /// region has no such figure. Tinted boxes are not figures.
    static func spanningFigures(_ elements: [Element], bodySize: CGFloat, gutter: ([Element]) -> CGFloat?)
        -> (head: [Element], columns: [Element], foot: [Element])? {
        guard elements.contains(where: { $0.line == nil && $0.box == nil }) else { return nil }
        // Each caption line keys its caption: a `Figure N` line and the lines wrapped beneath it on
        // its left edge at ordinary leading.
        var caption: [Int: Int] = [:]
        for index in elements.indices where elements[index].line.map({ isCaption($0.text) }) ?? false { caption[index] = index }
        var grown = true
        while grown {
            grown = false
            for index in elements.indices where caption[index] == nil {
                guard let line = elements[index].line,
                      let owner = caption.first(where: { member, _ in
                          let above = elements[member].rect
                          return abs(above.minX - line.rect.minX) <= bodySize * 0.5
                              && above.minY - line.rect.maxY > -bodySize * 0.4 && above.minY - line.rect.maxY < bodySize * 0.5
                      })?.value else { continue }
                caption[index] = owner; grown = true
            }
        }
        let captions = Set(caption.keys)
        let text = elements.indices.filter { elements[$0].line != nil && !captions.contains($0) }.map { elements[$0] }
        guard let measured = gutter(text) else { return nil }
        let spanning = elements.indices.filter { index in
            let element = elements[index]
            return element.line == nil && element.box == nil && element.rect.minX < measured && element.rect.maxX > measured
        }
        guard !spanning.isEmpty else { return nil }
        let body = elements.indices.filter { !spanning.contains($0) && !captions.contains($0) }
        guard let top = body.map({ elements[$0].rect.maxY }).max(), let bottom = body.map({ elements[$0].rect.minY }).min()
        else { return nil }
        let tolerance = bodySize * 0.5
        func above(_ index: Int) -> Bool { elements[index].rect.minY >= top - tolerance }
        func below(_ index: Int) -> Bool { elements[index].rect.maxY <= bottom + tolerance }
        guard spanning.allSatisfy({ above($0) || below($0) }) else { return nil }
        // A caption goes with the spanning figures only when all of its lines lie beyond the columns
        // and it does not sit against a figure of the columns' own.
        let own = elements.indices.filter { elements[$0].line == nil && !spanning.contains($0) }.map { elements[$0].rect }
        let beyond = Set(Dictionary(grouping: captions, by: { caption[$0]! }).filter { owner, lines in
            let label = elements[owner].rect
            let captionsOwnFigure = own.contains { figure in
                figure.minX < label.maxX && figure.maxX > label.minX
                    && (abs(figure.minY - label.maxY) <= bodySize * 1.5 || abs(label.minY - figure.maxY) <= bodySize * 1.5)
            }
            return !captionsOwnFigure && (lines.allSatisfy(above) || lines.allSatisfy(below))
        }.values.joined())
        let outer = Set(spanning + beyond)
        let columns = elements.indices.filter { !outer.contains($0) }.map { elements[$0] }
        guard let x = gutter(columns) else { return nil }
        let sides = [columns.filter { $0.rect.maxX < x }, columns.filter { $0.rect.minX > x }]
        guard sides.allSatisfy({ side in side.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }.count >= 2 })
        else { return nil }
        let head = outer.sorted().filter { above($0) }.map { elements[$0] }
        let foot = outer.sorted().filter { !above($0) }.map { elements[$0] }
        return (head, columns, foot)
    }

    /// Stacked blocks of short answer columns that share one gutter. Wallace page 487 sets item
    /// 1's sub-answers a–i in three columns above answers 2–15 in three columns on the same
    /// edges, so the gutter runs through both blocks and cutting it read `a`–`d`, `2`–`6`,
    /// `e`–`h`… (#78). The blocks stand 38 pt apart, while no column's own rows are more than 15 pt
    /// apart.
    ///
    /// Returns the widest horizontal band of at least two bodies, at least twice the widest
    /// whitespace inside either side of the gutter above or below it, that has columns running
    /// beside each other on both sides of it. Prose columns (any line at least 12 bodies wide)
    /// are never stacked blocks: their paragraphs flow from one column's foot to the next
    /// column's head.
    static func stackedBlocks(_ elements: [Element], gutter: CGFloat, bodySize: CGFloat) -> CGFloat? {
        guard !elements.contains(where: { $0.line != nil && $0.rect.width >= bodySize * 12 }) else { return nil }
        /// The part's two sides of the gutter, when both hold content running beside each other.
        func sides(_ part: [Element]) -> [[Element]]? {
            let left = part.filter { $0.rect.maxX < gutter }, right = part.filter { $0.rect.minX > gutter }
            guard !left.isEmpty, !right.isEmpty else { return nil }
            let l = union(left.map(\.rect)), r = union(right.map(\.rect))
            return min(l.maxY, r.maxY) > max(l.minY, r.minY) ? [left, right] : nil
        }
        var best: (y: CGFloat, width: CGFloat)?
        for band in horizontalBands(elements) where band.width >= bodySize * 2 && band.width > (best?.width ?? 0) {
            guard let above = sides(elements.filter { $0.rect.minY > band.y }),
                  let below = sides(elements.filter { $0.rect.maxY < band.y }) else { continue }
            let spacing = (above + below).map { horizontalBands($0).map(\.width).max() ?? 0 }.max() ?? 0
            if band.width >= spacing * 2 { best = band }
        }
        return best?.y
    }

    /// Labelled cells numbered along their rows. Wallace page 448 sets graphs 15–22 three to a
    /// row under their labels `15)`, `16)`, `17)` / `18)`… with no whitespace between the rows
    /// (graph 20 hangs below label 21's top), so only the column gutters cut them, and they read
    /// 15, 18, 21, 16… (#78). The answer lists and exercise sets are numbered down their columns
    /// by design and must keep reading that way, so the geometry does not decide; the numbers do.
    ///
    /// Returns the region's `N)` labels when they form a grid read row-major: at least four
    /// labels in two or more rows of at least two, at least three columns, each row's labels on
    /// the first row's column edges, the numbers consecutive row by row, and nothing in the region
    /// above the first row. Otherwise nil. Wallace sets its exercises two to a row and numbers them
    /// along the rows (`1)` | `2)`), but the book reads them column by column by contract (pages 10,
    /// 26 and 424's triangles), so a two-column grid is never reordered.
    static func rowMajorLabels(_ elements: [Element], bodySize: CGFloat) -> [(rect: CGRect, number: Int)]? {
        let labels = elements.compactMap { element -> (rect: CGRect, number: Int)? in
            guard let text = element.line?.text,
                  let range = text.range(of: #"^[0-9]{1,3}(?=\))"#, options: .regularExpression),
                  let number = Int(text[range]) else { return nil }
            return (element.rect, number)
        }
        guard labels.count >= 4 else { return nil }
        var rows: [[(rect: CGRect, number: Int)]] = []
        for label in labels.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            if let anchor = rows.last?.first, anchor.rect.maxY - label.rect.maxY <= bodySize { rows[rows.count - 1].append(label) }
            else { rows.append([label]) }
        }
        rows = rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
        guard rows.count >= 2, rows.filter({ $0.count >= 2 }).count >= 2,
              let first = rows.first, first.count >= 3, rows.allSatisfy({ $0.count <= first.count }) else { return nil }
        // A grid: the i-th label of every row stands on the i-th label's left edge in the first row.
        guard rows.allSatisfy({ row in row.indices.allSatisfy { abs(row[$0].rect.minX - first[$0].rect.minX) <= bodySize } })
        else { return nil }
        let sequence = rows.flatMap { $0.map(\.number) }
        guard zip(sequence, sequence.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return nil }
        // Every cell hangs beneath its label: nothing in the region stands above the first row.
        let ceiling = first.map(\.rect.maxY).max()!
        guard elements.allSatisfy({ $0.rect.maxY <= ceiling + bodySize * 0.25 }) else { return nil }
        return labels
    }

    /// Column-ordered cells regrouped by their labels' numbers: each label leads the elements that
    /// follow it in its column.
    static func inNumberOrder(_ columns: [Element], labels: [(rect: CGRect, number: Int)]) -> [Element] {
        var head: [Element] = [], cells: [(number: Int, elements: [Element])] = []
        for element in columns {
            if element.line != nil, let label = labels.first(where: { $0.rect == element.rect }) {
                cells.append((label.number, [element]))
            } else if cells.isEmpty {
                head.append(element)
            } else {
                cells[cells.count - 1].elements.append(element)
            }
        }
        return head + cells.sorted { $0.number < $1.number }.flatMap(\.elements)
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
    /// retained before furniture removal; nil for pages without one. `noteLastChapter` is the
    /// second chapter a `NOTES TO CHAPTERS N-M` head names. `continuesNote` states
    /// that the previous page ended in a page-bottom footnote, so a marker-less note under
    /// this page's separator may continue it. `labelStyles` is the book's section-label
    /// typography (`labelStyles(from:)`), and `headingStyles` its recurring heading-size
    /// typography (`headingEvidence(on:)`). `continuingNoteList` is the previous page's open list
    /// inside a numbered note, which this page may resume; `noteLayout` receives this page's
    /// numbered-note layout (nil when the page is not a notes page), so the caller can pass its
    /// open list to the next page.
    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], noteChapter: Int? = nil,
                       noteLastChapter: Int? = nil, continuingNoteList: NumberedNoteDetector.OpenList? = nil,
                       noteLayout reportNoteLayout: ((NumberedNoteDetector.Layout?) -> Void)? = nil,
                       continuesNote: Bool = false,
                       labelStyles: Set<LabelStyle> = [], headingStyles: Set<LabelStyle> = []) -> [ReflowBlock] {
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
        // A marker PDFKit split from its item's text rejoins it before anything reads the lines.
        // So do the pieces of a prose row PDFKit split at an inline radical (#95).
        let (free, mathMinusRows) = joinedRows(joiningMarkerPieces(lines.filter { line in !tableLines.contains(line) }),
                                               images: images.map(\.0), body: body)
        // A list line, except a joined prose row whose apparent marker is a minus sign (#109).
        func listLine(_ line: TextLine) -> Bool { isList(line.text) && !mathMinusRows.contains(line) }
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
                                   headingThreshold: headingThreshold, page: page, styles: labelStyles)
            + boxTitles(in: free.map(untagged), page: page)
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
        // A line runs on into the line beneath it: set directly below at ordinary leading on the
        // same left edge in the same type, neither a heading, a list item nor a leader entry, and
        // filling the page's justified measure, with evidence that no paragraph ends between them.
        // Tags that split one paragraph at such a line describe the source's text frames, not the
        // author's paragraphs (FAA page 211 tags `…in the AFM/` and `POH. These airspeeds
        // include:` as two paragraphs, page 105 `…upon stability.` and `The allowable location of
        // the CG…`; #75).
        func wraps(_ upper: TextLine, onto lower: TextLine) -> Bool {
            let size = max(upper.fontSize, lower.fontSize)
            let gap = upper.rect.minY - lower.rect.maxY
            guard !sameRow(upper.rect, lower.rect), abs(upper.rect.minX - lower.rect.minX) <= size * 0.5,
                  abs(upper.fontSize - lower.fontSize) <= size * 0.15, gap > -size * 0.4, gap < size * 0.4,
                  !isList(lower.text),
                  !upper.text.contains("..."), !lower.text.contains("..."),
                  LabelStyle(upper, body: body).bold == LabelStyle(lower, body: body).bold,
                  !headingTypography(upper), !headingTypography(lower), upper.rect.width >= body * 12,
                  // Both lines are set as prose: a table row spreads a few characters over the
                  // measure (FAA page 416's `Compass Locator  Under 25  15`, 0.9 em a character,
                  // where a loosely justified line of text sets about half that).
                  [upper, lower].allSatisfy({ $0.rect.width <= CGFloat($0.text.count) * size * 0.7 })
            else { return false }
            // The upper line reaches its column's right edge, and that measure is the page's
            // justified measure (three other lines set to it): a title, a ragged list entry or a
            // short report line does not run on.
            let column = free.filter { abs($0.rect.minX - upper.rect.minX) <= body * 0.5 }.map(\.rect.maxX).max() ?? upper.rect.maxX
            let measure = free.filter { $0 != upper && abs($0.rect.width - upper.rect.width) <= body * 0.75 }
            guard upper.rect.maxX >= column - body * 0.75, measure.count >= 3 else { return false }
            // Continuation evidence: the lower line's first letter is lowercase (past an opening
            // bracket: `(bottom) are examples…`), or the upper line breaks at a hyphen or a slash.
            if lower.text.first(where: \.isLetter)?.isLowercase == true
                || upper.text.last.map({ "-/\u{00AD}".contains($0) }) == true { return true }
            // Otherwise the next line continues the paragraph only where the column marks
            // paragraphs with space, so ordinary leading is itself evidence (FAA page 342: `…against
            // you.` / `Runway holding position markings consist…`). A list set at even leading (FAA's
            // acronyms, page 462) has no such space.
            let edge = free.filter { abs($0.rect.minX - upper.rect.minX) <= body * 0.5
                && abs($0.fontSize - upper.fontSize) <= upper.fontSize * 0.1 }
                .sorted { $0.rect.minY > $1.rect.minY }
            let spaced = zip(edge, edge.dropFirst()).filter { above, below in
                let gap = above.rect.minY - below.rect.maxY
                return gap >= upper.fontSize * 0.6 && gap <= upper.fontSize * 2.5
            }
            if spaced.count >= 2 { return true }
            // Or the column is justified and sets space somewhere on its edge: most of its lines end
            // at its right edge, so a line that fills the measure and a line on the same edge at
            // ordinary leading read as one block of text, whatever sentence opens the lower line,
            // in a column that shows its breaks with space (FAA page 96's `…affected portion of the
            // airfoil.` / `Manufacturers have developed…`, whose only space sets off `A Third
            // Dimension`; #89). A ragged list (the acronyms) reaches that edge only with its longest
            // entries, and a column with no space at all leaves the tags as the only evidence.
            let justified = edge.filter { $0.rect.maxX >= column - body * 0.75 }
            let sameEdge = free.filter { abs($0.rect.minX - upper.rect.minX) <= body * 0.5 }.sorted { $0.rect.minY > $1.rect.minY }
            let spacedAtAll = zip(sameEdge, sameEdge.dropFirst()).contains { above, below in
                let gap = above.rect.minY - below.rect.maxY
                return gap >= upper.fontSize * 0.6 && gap <= upper.fontSize * 2.5
            }
            return edge.count >= 6 && justified.count * 2 > edge.count && spacedAtAll
        }
        var elements = structuredOrder(spatial, page: page.number, warnings: &warnings,
                                       headingTypography: headingTypography, wraps: { wraps($0, onto: $1) })
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
        // The book's own typography is evidence too. A group set entirely in a heading or label
        // style the book repeats on three or more pages is a title wherever it stands, even
        // directly above another heading: FAA tags each chapter opener's `Chapter 4` and
        // `Principles of Flight` as paragraphs over the `Introduction` heading (#84). A title
        // page's one-off imprint (Our Flag) and a cover's publication label (the Fed) are set in
        // no recurring style, so they still need the column test.
        let bookStyles = labelStyles.union(headingStyles)
        func inBookHeadingStyle(_ line: TextLine) -> Bool {
            line.text.filter(\.isLetter).count >= 2 && bookStyles.contains(LabelStyle(line, body: reflowBody))
        }
        let introduces = Set(Dictionary(grouping: elements.indices.filter {
            elements[$0].line?.structure?.headingLevel == 0
        }, by: { elements[$0].line!.structure!.group }).compactMap { group, indices -> Int? in
            let lines = indices.sorted().map { elements[$0].line! }
            guard lines.allSatisfy(headingTypography),
                  pullQuoteLines(in: lines, candidates: { _ in true }).count < lines.count else { return nil }
            if lines.allSatisfy(inBookHeadingStyle) { return group }
            guard let last = indices.max(),
                  let left = lines.map({ $0.rect.minX }).min(), let right = lines.map({ $0.rect.maxX }).max(),
                  let next = elements[(last + 1)...].lazy.compactMap(\.line)
                    .first(where: { $0.rect.minX < right && $0.rect.maxX > left }),
                  !headingTypography(next), left <= next.rect.minX + body else { return nil }
            return group
        })
        // A paragraph group can also be a title that the page's own label test cannot see, because
        // that test asks for body text directly beneath a body-size label: FAA page 27 stacks
        // `Pilot and Aeronautical Information` over `Notices to Airmen (NOTAMs)`, page 54 sets
        // `PAVE Checklist: Identify Hazards and Personal` / `Minimums` over two lines, and the
        // chapter openers set `Introduction` right under the chapter title. The tag already makes the
        // line its own element, so the evidence left to find is that the element is a title (#90):
        // - every line is set in bold in a heading or label style the book repeats, and the group
        //   reads as a title (a capital first, no closing punctuation, no list marker or leader); or
        // - it is one line in the body's size set wholly in italic, in title case, over a wider
        //   body-text line on its own left edge or over the list it heads (#97), with space or
        //   another title above it: the FAA's lowest title level (`Likelihood of an Event`,
        //   `Coupled Ailerons and Rudder`, page 48's `Airport` over its bullets). An italic
        //   sentence, quotation or caption fragment ends in punctuation or is not in title case.
        // Such a group is emitted as a heading in tag order, ranked by its size (see `flushTagged`).
        func readsAsTitle(_ lines: [TextLine]) -> Bool {
            let text = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard (1...3).contains(lines.count), text.count < 150, text.filter(\.isLetter).count >= 2,
                  let first = text.first(where: { !"([\u{201C}\"'".contains($0) }), first.isUppercase || first.isNumber,
                  let last = text.last, !".,;:!?".contains(last) else { return false }
            // A contents page's chapter label heads leader entries (`Introduction To Flying.....1-1`,
            // whose chapter-prefixed folio `isContentsEntry` does not read), and a table's header
            // row spreads a few words over its width (`Class  (Watts)  (Miles)`).
            guard !lines.contains(where: { $0.text.contains("....") || $0.rect.width > CGFloat($0.text.count) * $0.fontSize * 0.7 }),
                  let lowest = lines.min(by: { $0.rect.minY < $1.rect.minY }) else { return false }
            let beneath = free.filter { $0.rect.maxY <= lowest.rect.minY + body * 0.4 && $0.rect.minX < lowest.rect.maxX
                && $0.rect.maxX > lowest.rect.minX }.max { $0.rect.maxY < $1.rect.maxY }
            // The entry beneath can wrap before its leader (`Performance Data for Cessna Model 172R` /
            // `and Challenger 605.....A-1`): its whole group counts.
            if let beneath, free.contains(where: { other in
                (other == beneath || other.structure != nil && other.structure?.group == beneath.structure?.group)
                    && other.text.contains("....")
            }) { return false }
            return !lines.contains { isList($0.text) || isContentsEntry($0.text) || isHeaderLike($0, in: page, bothBands: true) }
        }
        func wholly(_ line: TextLine, _ trait: TextStyle) -> Bool {
            line.content.elements.allSatisfy { element in
                guard case let .text(value, style) = element else { return true }
                return style.contains(trait) || value.allSatisfy(\.isWhitespace)
            }
        }
        func setsItalicTitle(_ line: TextLine) -> Bool {
            guard wholly(line, .italic), abs(line.fontSize - reflowBody) <= reflowBody * 0.1, isTitleCase(line.text),
                  !isCaption(line.text) else { return false }
            let column = free.filter { $0.rect.minX < line.rect.maxX && $0.rect.maxX > line.rect.minX && !sameRow($0.rect, line.rect) }
            // Beneath it, body text on its own edge or a list it heads (FAA page 48's `Airport`; #97).
            guard let below = column.filter({ $0.rect.maxY <= line.rect.minY + body * 0.4 }).max(by: { $0.rect.maxY < $1.rect.maxY }),
                  line.rect.minY - below.rect.maxY < body * 0.8, abs(below.fontSize - reflowBody) <= reflowBody * 0.1,
                  !wholly(below, .italic), !wholly(below, .bold),
                  abs(below.rect.minX - line.rect.minX) <= body * 0.5 && below.rect.width > line.rect.width && !isList(below.text)
                    || opensListBeneath(below, title: line, body: body) else { return false }
            guard let above = column.filter({ $0.rect.minY >= line.rect.maxY - body * 0.25 }).min(by: { $0.rect.minY < $1.rect.minY })
            else { return true }
            return above.rect.minY - line.rect.maxY >= body * 0.5 || wholly(above, .bold) || headingTypography(above)
        }
        let taggedTitles = Set(Dictionary(grouping: elements.indices.filter {
            elements[$0].line?.structure?.headingLevel == 0
        }, by: { elements[$0].line!.structure!.group }).compactMap { group, indices -> Int? in
            guard !introduces.contains(group) else { return nil }
            let lines = indices.sorted().map { elements[$0].line! }
            // A section title is set flush left. A title centred over the body text of its column is a
            // table's or display's title (`NONDIRECTIONAL RADIO BEACON (NDB)` on FAA page 416, 16 points
            // in from the column edge and centred on the prose line above it).
            guard readsAsTitle(lines), !free.contains(where: { other in
                !sameRow(other.rect, lines[0].rect) && abs(other.fontSize - reflowBody) <= reflowBody * 0.1
                    && !wholly(other, .bold) && lines[0].rect.minX - other.rect.minX > body
                    && abs(lines[0].rect.midX - other.rect.midX) <= body
            }) else { return nil }
            if lines.allSatisfy({ inBookHeadingStyle($0) && wholly($0, .bold) && $0.fontSize >= reflowBody * 0.95 }) {
                return group
            }
            return lines.count == 1 && setsItalicTitle(untagged(lines[0])) ? group : nil
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
        let noteLayout = NumberedNoteDetector.layout(in: elements, page: page, chapter: noteChapter,
            lastChapter: noteLastChapter, continuing: continuingNoteList)
        reportNoteLayout?(noteLayout)
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
        // The groups the open tagged block holds, and its last line (see `wraps`).
        var taggedGroups: Set<Int> = []
        var taggedLast: TextLine?
        func flushTagged() {
            guard let (tag, text, size) = tagged else { return }
            // A paragraph group that is one rejoined list item (#81) keeps the representation
            // the same item has untagged: a preserved list line, its marker intact.
            // A paragraph group that reads as a title (`taggedTitles`) is a heading with no validated
            // level: `rankHeadingLevels` ranks it by size, as it ranks untagged headings.
            let title = tag.headingLevel == 0 && taggedTitles.contains(tag.group)
            let content: ReflowBlock.Content = title
                ? .heading(id: "heading-\(page.number)-\(result.count)", text: text, level: 2)
                : tag.headingLevel == 0
                ? (tag.opensWithSplitMarker && isList(text.text) ? .preformatted(text) : .paragraph(text))
                : .heading(id: "heading-\(page.number)-\(result.count)", text: text, level: tag.headingLevel)
            var block = ReflowBlock(content: content, structureGroup: tag.group, page: page.number)
            block.taggedLevel = title ? nil : tag.headingLevel
            // A tagged heading keeps its validated level, but its typography still belongs in the
            // document-wide scale: see `rankHeadingLevels`.
            if tag.headingLevel > 0 || title { block.headingSize = size }
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
        // PDFKit can drop the space after a numbered marker (`10.August 2001: …` among spaced
        // items 6 to 9 on 9/11 page 374). Such a line opens a list item only when a capital
        // letter follows the period, at least two spaced numbered items share its left edge and
        // size on this page, and its number is next to one of theirs. Decimals (`3.5 percent`),
        // section numbers (`1.1 INSIDE`) and times (`10.30`) never qualify, and a note run
        // (`5.This`) has already claimed its lines (#69).
        let spacedMarkers: [(line: TextLine, number: Int)] = free.compactMap { line in
            guard !line.monospaced, let end = line.text.range(of: "^[0-9]{1,3}\\.\\s", options: .regularExpression),
                  let number = Int(line.text[end].dropLast(2)) else { return nil }
            return (line, number)
        }
        func isTightMarker(_ line: TextLine) -> Bool {
            guard !line.monospaced, let end = line.text.range(of: "^[0-9]{1,3}\\.\\p{Lu}", options: .regularExpression),
                  let number = Int(line.text[end].dropLast(2)) else { return false }
            let siblings = spacedMarkers.filter {
                abs($0.line.rect.minX - line.rect.minX) <= body * 0.5 && abs($0.line.fontSize - line.fontSize) <= line.fontSize * 0.1
            }
            return siblings.count >= 2 && siblings.contains { $0.number == number - 1 || $0.number == number + 1 }
        }
        // A list item's marker line opens the item; its wrapped lines are set in the hanging
        // indent under the item's text, at ordinary line spacing and no larger than the item.
        // The item closes at the next marker, a paragraph gap, a dedent to the marker's edge,
        // a heading, an image, a table or a box edge, each of which another branch takes
        // first, so this line joins the open item instead of opening a paragraph (#50, #64).
        func continuesListItem(_ line: TextLine, item: (marker: TextLine, last: TextLine, indent: CGFloat?, index: Int)) -> Bool {
            guard !listLine(line), line.fontSize <= item.marker.fontSize + 0.5 else { return false }
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
            // A period inside a web address ends nothing (FAA page 372's `(AIM)—www.faa.` +
            // `gov/air_traffic/…`, #79).
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard let ending = item.last.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?".contains(ending) || addressContinues(item.last.text, line.text) else { return false }
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
            guard endsSentence(prev) else { return false }
            // A section opens flush with the column the paragraph above it fills, so a run-in
            // label indented inside an item or a note is not one.
            return abs(prev.rect.minX - line.rect.minX) <= body * 0.5
        }
        // The sentence's own last character, past closing quotes and brackets and past a
        // raised reference marker: USGS sections end `… copper supply.5` before the next
        // lead-in, and the marker is not the sentence's punctuation.
        func endsSentence(_ prev: TextLine) -> Bool {
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            for element in prev.content.elements.reversed() {
                guard case let .text(value, style) = element else { continue }
                if style.contains(.superscript), value.allSatisfy({ $0.isNumber || $0.isWhitespace }) { continue }
                if let character = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) {
                    return ".!?".contains(character)
                }
            }
            return false
        }
        // A paragraph set off by added space alone opens a paragraph even where that space falls
        // under the ordinary threshold. The USGS Mineral Commodity Summaries leave a blank line
        // between paragraphs at 11.04-point leading, but their line rectangles are 13.76 points
        // tall, so the lines of a paragraph report a gap of -2.72 points and the blank line only
        // 7.9, under `body * 0.9` (COMEX on copper page 2, #71). The evidence is measured against
        // the paragraph's own leading: the gap exceeds the gap its last line was attached at by at
        // least half the body size, the previous line ends a sentence, and this line opens with a
        // capital (past opening quotes and brackets) on the same left edge in the same type. A
        // wrapped line inside a paragraph sits at the paragraph's leading; nothing about the right
        // edge is consulted, so ragged and justified columns are read alike.
        func opensSpacedParagraph(_ line: TextLine, after prev: TextLine, gap: CGFloat, leading: CGFloat?) -> Bool {
            guard let leading, gap >= leading + body * 0.5, !line.monospaced,
                  abs(line.fontSize - prev.fontSize) <= max(line.fontSize, prev.fontSize) * 0.1,
                  abs(prev.rect.minX - line.rect.minX) <= body * 0.5,
                  line.text.first(where: { !"([\u{201C}\u{2018}\"'".contains($0) && !$0.isWhitespace })?.isUppercase == true
            else { return false }
            return endsSentence(prev)
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
                // A paragraph group can open on the line an untagged paragraph wraps onto: FAA page
                // 127 tags `…there is maximum thrust.` with text across a figure, so its group falls
                // back, and `After liftoff, …` opens the next group at ordinary leading. The wrap
                // evidence that joins two tagged groups joins these too (#89); the group's text
                // then continues the open paragraph.
                if tag.headingLevel == 0, !tag.opensWithSplitMarker, !taggedTitles.contains(tag.group), tagged == nil, !line.monospaced,
                   let prev = previous, prev.wraps != false, !paragraph.elements.isEmpty, wraps(prev, onto: line) {
                    tagged = (tag, join(paragraph, line.content, vocabulary: vocabulary, page: page.number,
                        warnings: &warnings), max(prev.fontSize, line.fontSize))
                    taggedGroups = [tag.group]
                    taggedLast = line
                    paragraph = InlineText()
                    previous = nil
                    previousGap = nil
                    codeOrigin = nil
                    continue
                }
                flush()
                codeOrigin = nil
                if let current = tagged, !taggedGroups.contains(tag.group) {
                    // Two paragraph groups split at a wrapped line read as one paragraph.
                    if current.0.headingLevel == 0, !current.0.opensWithSplitMarker, tag.headingLevel == 0,
                       !tag.opensWithSplitMarker, !taggedTitles.contains(current.0.group), !taggedTitles.contains(tag.group),
                       let last = taggedLast, wraps(last, onto: line) {
                        taggedGroups.insert(tag.group)
                    } else { flushTagged() }
                }
                taggedLast = line
                if tagged == nil { taggedGroups = [tag.group] }
                if let current = tagged {
                    tagged = (current.0, join(current.1, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings), max(current.2, line.fontSize))
                } else { tagged = (tag, line.content, line.fontSize) }
                continue
            }
            // The converse: an untagged line a paragraph group's last line wraps onto continues that
            // paragraph (FAA page 360's `…[Figure 14-44]` / `In addition to basic radar service, …`,
            // whose group crosses the figure beside it and falls back). The open group's text becomes
            // the spatial paragraph, and the ordinary rules below attach the line to it.
            if let current = tagged, current.0.headingLevel == 0, !current.0.opensWithSplitMarker,
               !taggedTitles.contains(current.0.group),
               let last = taggedLast, !line.monospaced, wraps(last, onto: line) {
                tagged = nil
                paragraph = current.1
                previous = last
                previousGap = nil
            }
            flushTagged()
            if !line.monospaced { codeOrigin = nil }
            if isHeadingCandidate(line), !quotes.contains(line) {
                // PDFKit splits a heading row at a wide gap (a section number and its title);
                // the pieces form one heading, as do the lines of a title set over several
                // lines (#55). The pieces of one row sit within a few ems of each other; two
                // columns' titles on one row are two headings (FAA page 340, #76).
                if let row = previousHeading, let last = result.indices.last,
                   case let .heading(id, text, level) = result[last].content,
                   sameRow(row.first.rect, line.rect) && abs(row.first.fontSize - line.fontSize) <= line.fontSize * 0.1
                    && line.rect.minX - row.last.rect.maxX <= line.fontSize * 3
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
            } else if listLine(line) || isTightMarker(line), !continuesParagraph(line) {
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
                    // An inline expression makes its line's rectangle taller than the page's
                    // ordinary line of that size, above the type (a radical's bar) or below it
                    // (Wallace's minus and times glyphs drop the rectangle 8.5 points), so that
                    // line overlaps its neighbour by more than tight leading does (#109). The
                    // overlap allowed grows by the extra height of a line set as prose on its
                    // paragraph's measure (`isProseRow`); a derivation's stacked terms and
                    // annotations are not, and a rectangle more than twice the ordinary height is
                    // a display, not an inline expression. The paragraph gap above is still
                    // measured on the rectangles, and such a gap is not the paragraph's leading.
                    let inflation = [prev, line].map { neighbour -> CGFloat in
                        guard let ordinary = ordinaryLineHeight(neighbour.fontSize, in: lines),
                              neighbour.rect.height > ordinary + body * 0.25,
                              neighbour.rect.height <= ordinary * 2,
                              isProseRow(neighbour, in: free, body: body) else { return 0 }
                        return neighbour.rect.height - ordinary
                    }.reduce(0, +)
                    let sameColumn = abs(prev.rect.minX - line.rect.minX) < body * 1.5
                        && verticalGap >= -(body * 0.4 + inflation) && verticalGap < body * 0.9
                    let shortEnding = prev.rect.width < line.rect.width * 0.65
                        && prev.text.last.map { ".!?".contains($0) } == true
                    // A figure caption ends where clearly larger type begins at body size or
                    // above: that line is a section title, not more caption (#63). A caption's
                    // own lines differ by less: FAA opens each with an 8-point bold label and
                    // wraps its 9-point text, and a figure-heavy page can measure a 9-point body.
                    // A line only slightly larger ends it too when it leaves the caption's
                    // alignment, sharing neither its left edge nor its centre: FAA page 159's
                    // 9-point `Figure 5-16.` caption, indented 3.5 points, over 10-point body text
                    // flush with the column (#82). Wrapped caption lines keep the caption's edge.
                    let leavesCaption = line.fontSize >= prev.fontSize * 1.05
                        && abs(line.rect.minX - prev.rect.minX) > body * 0.25
                        && abs(line.rect.midX - prev.rect.midX) > body * 0.25
                    let endsCaption = (line.fontSize >= prev.fontSize * 1.15 || leavesCaption)
                        && line.fontSize >= reflowBody * 0.95 && isCaption(paragraph.text)
                    if prev.wraps == false || !sameColumn || shortEnding || endsCaption
                        || opensSection(line, after: prev, gap: verticalGap, leading: previousGap)
                        || opensSpacedParagraph(line, after: prev, gap: verticalGap, leading: previousGap) {
                        flush()
                    } else { attachedGap = inflation > 0 ? previousGap : verticalGap }
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
    /// `headingTypography` is the page's own heading typography, before tags, and `wraps` whether
    /// one line runs on into the line beneath it (see `blocks`).
    static func structuredOrder(_ spatial: [Element], page: Int,
                                warnings: inout [ConversionWarning], depth: Int = 0,
                                headingTypography: (TextLine) -> Bool = { _ in false },
                                wraps: (TextLine, TextLine) -> Bool = { _, _ in false }) -> [Element] {
        var elements = spatial
        guard depth < 32 else {
            for index in elements.indices { elements[index].line?.structure = nil }
            return elements
        }
        if depth == 0 {
            let groups = Dictionary(grouping: elements.compactMap(\.line).filter { $0.structure != nil },
                by: { $0.structure!.group })
            var unsafe = Set(groups.compactMap { group, lines -> Int? in
                // Caption ownership and lists are outside this phase. A paragraph tag alone
                // must not detach a figure label or collapse significant item breaks. One
                // exception: a paragraph group that opens with a marker PDFKit split from its
                // text, and holds no other list line, is exactly that one item, so it has no
                // item break to collapse (#81). An unsplit bullet inside a group still falls back.
                let listLines = lines.filter { isList($0.text) }
                // The item opens the group: first by tag order, and first in spatial order among
                // lines sharing that order (one marked section can hold several lines).
                let opening = lines.min { $0.structure!.order < $1.structure!.order }
                let singleSplitItem = listLines.count == 1 && lines.first!.structure!.headingLevel == 0
                    && listLines[0].structure!.opensWithSplitMarker && opening == listLines[0]
                let captionOrList = (!listLines.isEmpty && !singleSplitItem) || lines.contains { $0.text.range(
                    of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil }
                let oversizedHeading = lines.first!.structure!.headingLevel > 0
                    && lines.reduce(0, { $0 + $1.text.count + 1 }) >= 200
                return captionOrList || oversizedHeading ? group : nil
            })
            // A source can tag a wrapped line as a paragraph of its own: FAA page 227 tags
            // `Figure 8-34. Utilization of a compass rose aids compensation for` and `deviation
            // errors.` as two groups. A paragraph group whose first line continues the last line of
            // a group that falls back falls back with it, so the spatial caption and list rules read
            // the whole item, as they do where the page has no tags (#75).
            var grown = true
            while grown {
                grown = false
                for (group, lines) in groups where !unsafe.contains(group) && lines.first!.structure!.headingLevel == 0 {
                    if unsafe.contains(where: { groups[$0].map { wraps($0.last!, lines.first!) } ?? false }) {
                        unsafe.insert(group); grown = true
                    }
                }
            }
            // A paragraph tag over a title and the body set beneath it is not one paragraph, and
            // its order is no evidence either: FAA page 203 tags `Introduction`, its paragraph,
            // `Pitot-Static Flight Instruments` and its paragraph as one `P`, ahead of the
            // chapter title (#84). Such a group keeps its spatial reading. A drop cap or numeral
            // (fewer than two letters) is not a title.
            let titled = Set(groups.compactMap { group, lines -> Int? in
                guard lines.first!.structure!.headingLevel == 0, !unsafe.contains(group) else { return nil }
                return lines.indices.contains { index in
                    lines[index].text.filter(\.isLetter).count >= 2 && headingTypography(lines[index])
                        && lines[(index + 1)...].contains { !headingTypography($0) }
                } ? group : nil
            })
            if !titled.isEmpty {
                for index in elements.indices {
                    if let group = elements[index].line?.structure?.group, titled.contains(group) {
                        elements[index].line?.structure = nil
                    }
                }
                warnings.append(.init(code: .structureFallback, page: page,
                    message: "A paragraph tag spanning a heading and the text beneath it requires broader semantic validation; spatial reconstruction is retained."))
            }
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
            // boundary, so page navigation reaches it from the next page. Headings directly above
            // the paragraph move with it: the section they open starts with that paragraph, and
            // a figure the page set beside or below the section must not come between them (FAA
            // page 33's `Selecting a Flight School`, #63).
            var start = anchors.previous
            while start > 0, case .heading = blocks[start - 1].content { start -= 1 }
            let headings = Array(blocks[start..<anchors.previous])
            let trailing = Array(blocks[(anchors.previous + 1)...])
            blocks.replaceSubrange(start..., with: trailing.filter { !$0.isFootnote } + headings + [joined]
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

    /// An Arabic page number (optionally prefixed by its chapter's number or its part's letter,
    /// `5-17` or `C-2`) or a Roman numeral.
    private static func isFolio(_ text: String) -> Bool {
        !text.isEmpty && text.range(of: "^(?:(?:[0-9]+-|[A-Za-z]-)?[0-9]+|m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3}))$",
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
    static func isList(_ text: String) -> Bool {
        text.range(of: "^(?:(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s|[0-9]+\\)−)", options: .regularExpression) != nil
    }

    private enum JoinOperation { case space, concatenate, removeHyphen }

    private static let addressCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&()*+,;=%")

    private static func isASCIIAlphanumeric(_ character: Character?) -> Bool {
        character.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
    }

    /// The web address `text` ends inside: the run of URL characters that ends it, after any
    /// whitespace, dash or quote (`(NACO)—www.faa.` on FAA page 372) and without leading opening
    /// punctuation, when that run has a scheme (`https://`), starts with `www.`, or opens with a
    /// domain and a slash (`ffiec.gov/`).
    static func trailingAddress(_ text: String) -> Substring? {
        let start = text.lastIndex(where: { !addressCharacters.contains($0) }).map { text.index(after: $0) } ?? text.startIndex
        let word = text[start...].drop { "([<:;,".contains($0) }
        guard word.count >= 2, word.contains("."),
              word.range(of: "^(?:[A-Za-z][A-Za-z0-9+.-]*://|www\\.|[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}/)",
                         options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return word
    }

    /// A line broken inside a web address continues it with no space (#79). The break is inside
    /// the address when the address ends in a character that cannot end one after a letter or
    /// digit (`bst_` + `openmarketops.htm`, `?content_` + `item_id=…`), in a dot after a letter or
    /// digit before a lowercase continuation (`https://www.` + `federalreserve.gov`) or a
    /// continuation that is not a bare number (`10.1080/14693062.` + `2022.2061405`, never `2004`),
    /// in a hyphen before a digit or capital (`Spec/02-` + `2004/Article…`), or when the next line
    /// opens with such a character (`www.federalreserve.gov` + `/monetarypolicy/…`). A hyphen
    /// before a lowercase letter is decided by `addressHyphenOperation`: the Fed's typesetter
    /// hyphenates inside addresses (`communi-` + `cations.htm`) as well as breaking at real ones. A period
    /// after a closing parenthesis, or before a capital, ends the sentence.
    private static func addressContinues(_ left: String, _ right: String) -> Bool {
        guard let next = right.first, let address = trailingAddress(left), let last = address.last else { return false }
        // A percent escape encodes a character the address continues past (`Lithium%20` +
        // `Batteries%200621_0.pdf`).
        if address.range(of: "%[0-9A-Fa-f]{0,2}$", options: .regularExpression) != nil {
            return isASCIIAlphanumeric(next) || next == "%"
        }
        let before = address.dropLast().last
        switch last {
        case "_", "=", "&", "?", "#", "%", "~":
            return isASCIIAlphanumeric(before) && isASCIIAlphanumeric(next)
        case ".":
            guard isASCIIAlphanumeric(before), next.isASCII else { return false }
            if next.isLowercase { return true }
            let word = right.prefix { !$0.isWhitespace }.reversed().drop { ".,;:)]".contains($0) }
            return next.isNumber && word.contains { !$0.isNumber }
        case "-":
            return next.isASCII && (next.isNumber || next.isUppercase)
        default:
            return isASCIIAlphanumeric(last) && "/._?#=&%~".contains(next) && isASCIIAlphanumeric(right.dropFirst().first)
        }
    }

    private static let addressDelimiters = Set("/.?#&=:")
    private static let addressPrefixKey = "\u{1}address:"
    private static let addressSegmentKey = "\u{1}segment:"

    /// An address without its scheme or `www.`, lowercased: the form address evidence compares.
    static func normalizedAddress(_ address: Substring) -> String {
        var text = address.lowercased()
        if let scheme = text.range(of: "^[a-z][a-z0-9+.-]*://", options: .regularExpression) { text.removeSubrange(scheme) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return text
    }

    private static func uncertainHyphen(page: Int, warnings: inout [ConversionWarning]) {
        guard !warnings.contains(where: { $0.code == .uncertainHyphen && $0.page == page }) else { return }
        warnings.append(.init(code: .uncertainHyphen, page: page,
            message: "An ambiguous line-ending hyphen is retained. Review source word joins."))
    }

    /// A line-end hyphen inside a web address before a lowercase letter (#88). The Fed's
    /// typesetter hyphenates inside addresses (`federalreserve.gov/monetary-` + `policy/…`) and
    /// also breaks at real hyphens (`publications/page1-` + `econ/…`), and prose compounds say
    /// nothing about either, so the book's own addresses decide. The address through the broken
    /// segment, as seen unbroken elsewhere (`federalreserve.gov/monetarypolicy`), decides first;
    /// then the broken segment seen in any address (`dfa-stress-tests`). One form must be seen
    /// and the other not. Failing both, a break inside a word removes the hyphen: the letters on
    /// either side, with no digit beside them (never `page1-` + `econ`), join into a book word
    /// and are not both book words themselves (`communi-` + `cations.htm`; `cations` is a
    /// line-start fragment of prose hyphenation, `communi` is not a word). Otherwise the hyphen
    /// stays and the page warns.
    private static func addressHyphenOperation(_ address: Substring, _ right: String, vocabulary: Set<String>, page: Int,
                                               warnings: inout [ConversionWarning]) -> JoinOperation {
        let rest = right.prefix { addressCharacters.contains($0) && !addressDelimiters.contains($0) }
        let removed = normalizedAddress(Substring(address.dropLast() + rest))
        let kept = normalizedAddress(Substring(address + rest))
        func segment(_ text: String) -> Substring {
            text.lastIndex(where: { addressDelimiters.contains($0) }).map { text[text.index(after: $0)...] } ?? Substring(text)
        }
        for (removedKey, keptKey) in [(addressPrefixKey + removed, addressPrefixKey + kept),
                                      (addressSegmentKey + segment(removed), addressSegmentKey + segment(kept))] {
            switch (vocabulary.contains(removedKey), vocabulary.contains(keptKey)) {
            case (true, false): return .removeHyphen
            case (false, true): return .concatenate
            default: continue
            }
        }
        let prefix = address.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()
        let suffix = right.prefix(while: { $0.isLetter })
        let whole = !(address.dropLast().dropLast(prefix.count).last?.isNumber ?? false)
            && !(right.dropFirst(suffix.count).first?.isNumber ?? false)
        if whole, !prefix.isEmpty, !suffix.isEmpty, vocabulary.contains((String(prefix) + suffix).lowercased()),
           !vocabulary.contains(String(prefix).lowercased()) || !vocabulary.contains(suffix.lowercased()) {
            return .removeHyphen
        }
        uncertainHyphen(page: page, warnings: &warnings)
        return .concatenate
    }

    private static func joinOperation(_ left: String, _ right: String, vocabulary: Set<String>, page: Int,
                                      warnings: inout [ConversionWarning]) -> JoinOperation {
        if left.hasSuffix("\u{00ad}") { return .removeHyphen }
        // A line broken after a slash inside a compound or an address (`runway/` + `taxiway`,
        // `and/` + `or`, `www.faa.gov/` + `pilots/`, `https://` + `www.`) continues it with no
        // space: a letter, digit or slash sits before the slash and a letter or digit follows
        // the break. A slash the source sets apart (`China /` + `East Asia`) keeps the space, as
        // does one after other punctuation, which in the corpus is only damaged OCR (#70).
        if left.hasSuffix("/"), let before = left.dropLast().last, before.isLetter || before.isNumber || before == "/",
           let next = right.first, next.isLetter || next.isNumber { return .concatenate }
        if addressContinues(left, right) { return .concatenate }
        guard left.hasSuffix("-"), right.first?.isLowercase == true else { return .space }
        if let address = trailingAddress(left) {
            return addressHyphenOperation(address, right, vocabulary: vocabulary, page: page, warnings: &warnings)
        }
        let prefix = left.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()
        let suffix = right.prefix(while: { $0.isLetter })
        let joined = (String(prefix) + suffix).lowercased()
        let compound = (String(prefix) + "-" + suffix).lowercased()
        if vocabulary.contains(joined), !vocabulary.contains(compound) { return .removeHyphen }
        if !vocabulary.contains(compound) { uncertainHyphen(page: page, warnings: &warnings) }
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
