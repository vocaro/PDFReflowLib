import Foundation
import PDFKit
import CoreText
#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

enum NativeTextReader {
    // PDFKit attributed extraction can raise an NSFont exception when separate documents
    // are read concurrently (#21). Serialize this synchronous page step across converter
    // instances; never hold the lock across async progress, OCR, graphics or EPUB writing.
    // Host code using PDFKit independently does not participate in this library-local lock.
    private static let extractionLock = NSLock()

    static func withExtractionLock<T>(_ operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        // Keep the uncontended path immediate. A queued conversion checks cancellation
        // between timed waits instead of waiting for another document's page to finish.
        // This does not interrupt a PDFKit call already executing inside the gate.
        if !extractionLock.try() {
            while !extractionLock.lock(before: Date(timeIntervalSinceNow: 0.05)) {
                try Task.checkCancellation()
            }
        }
        defer { extractionLock.unlock() }
        try Task.checkCancellation()
        // Drain what the operation autoreleased before unlocking. PDFKit returns its selections
        // and attributed strings, with the fonts they carry, autoreleased; drained by the
        // caller's pool while another thread holds the gate, they abort that thread's
        // `attributedString` with the same NSFont exception (#21: 2 of 80 eight-worker processes
        // aborted with the drain removed, 0 of 70 with it present; see
        // measurements/pdfkit-gate-drain/record.md).
        return try autoreleasepool { try operation() }
    }

    /// `rules` are the page's painted thin rules, which supply the underline evidence the text
    /// layer does not carry (#235). `shows` are the page's own text-showing operations, where the
    /// caller has already read them: `TableReader` needs the same reading to divide a printed row
    /// into cells, and one walk of the content stream serves both (#210).
    static func lines(on page: PDFPage, limit: Int, includeStyle: Bool = true,
                      rules: [CGRect] = [], links: [PageLink] = [], preserveInvisibleWordGaps: Bool = false,
                      shows: [NativeSpacingReader.Evidence]? = nil, language: String = "en") throws -> [TextLine] {
        try withExtractionLock {
            try extractLines(on: page, limit: limit, includeStyle: includeStyle, rules: rules,
                             links: links, preserveInvisibleWordGaps: preserveInvisibleWordGaps, shows: shows,
                             language: language)
        }
    }

    private static func extractLines(on page: PDFPage, limit: Int, includeStyle: Bool,
                                     rules: [CGRect], links: [PageLink] = [], preserveInvisibleWordGaps: Bool = false,
                                     shows: [NativeSpacingReader.Evidence]? = nil,
                                     language: String) throws -> [TextLine] {
        guard page.numberOfCharacters <= limit else {
            throw ConversionError.resourceLimit("too many characters")
        }
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let selections = selection.selectionsByLine()
        let boundsByLine = selections.map { $0.bounds(for: page) }
        let spacing = includeStyle ? (shows ?? page.pageRef.map(NativeSpacingReader.read) ?? []) : []
        let invisibleSpacing = preserveInvisibleWordGaps ? page.pageRef.map(NativeSpacingReader.readInvisible) ?? [] : []
        let glyphs = includeStyle ? page.pageRef.map(GlyphIdentityReader.read) ?? [] : []
        // PDFKit's text of every line, beside its rectangle: read once so both the styled-line
        // filter below and `attributedTexts`'s alignment check reuse it instead of asking PDFKit
        // for each line's plain text twice.
        let textsByLine = selections.map(\.string)
        // TeX's sized delimiters, which no map states and PDFKit reads as nothing, and the lines
        // the shows around them place them in (#305); without the shows none can be placed.
        let delimiters = includeStyle && !spacing.isEmpty ? page.pageRef.map(ExtensionDelimiterReader.read) ?? [] : []
        let delimiterPlacements = ExtensionDelimiterReader.placements(delimiters, shows: spacing, lines: boundsByLine,
                                                                      texts: textsByLine.map { $0 ?? "" })
        let discretionaryShows = includeStyle ? page.pageRef.map(DiscretionaryHyphenReader.read) ?? [] : []
        let discretionary = includeStyle ? DiscretionaryHyphenReader.lines(
            shows: discretionaryShows,
            texts: textsByLine.map { $0 ?? "" }, bounds: boundsByLine) : [:]
        let explicitSoftHyphens = includeStyle ? DiscretionaryHyphenReader.explicitSoftHyphenLines(
            shows: discretionaryShows, texts: textsByLine.map { $0 ?? "" }, bounds: boundsByLine) : []
        // A scan also contributes a page-sized attachment selection. It owns no words, and
        // must not make every word-box anchor look shared by two text lines (#295).
        let invisibleBounds = preserveInvisibleWordGaps ? selections.indices.compactMap { index -> CGRect? in
            guard let text = textsByLine[index], text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }) else { return nil }
            return boundsByLine[index]
        } : []
        // Every line the loop below reads with style: one with visible text over a real rectangle.
        let styledLines = includeStyle ? selections.indices.filter { index in
            guard let raw = textsByLine[index], !raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let bounds = boundsByLine[index]
            return bounds.isFinite && !bounds.isNull && bounds.width > 0 && bounds.height > 0
        } : []
        let attributedByLine = attributedTexts(of: styledLines, in: selections, texts: textsByLine, on: page)
        // A rule the page draws down its margin, which an inherited recognition read as a column of
        // letters and PDFKit hands back inside the lines beside it (#264). A page that draws no
        // such rule pays one pass over its lines and nothing else.
        let crop = page.bounds(for: .cropBox)
        let suspectsRule = MarginRuleMarks.suspected(texts: textsByLine, rects: boundsByLine, bounds: crop)
        // A row of two columns PDFKit handed back as one line spanning the gutter (#270). It is
        // read from the same character boxes as the margin rule, so a page that shows neither
        // shape asks PDFKit for nothing.
        let suspectsGutter = ColumnGutterCut.suspected(texts: textsByLine, rects: boundsByLine)
        let boxesByLine = suspectsRule || suspectsGutter ? characterBoxes(of: textsByLine, on: page) : []
        let marginRule = suspectsRule
            ? MarginRuleMarks.read(texts: textsByLine.map { $0 ?? "" }, boxes: boxesByLine,
                                   rects: boundsByLine, bounds: crop)
            : [:]
        // A line the margin rule also reached keeps that reading: its box is already being
        // re-measured, and no page states both shapes for one line.
        let gutterCuts = suspectsGutter
            ? ColumnGutterCut.read(texts: textsByLine.map { $0 ?? "" }, boxes: boxesByLine,
                                   rects: boundsByLine).filter { marginRule[$0.key] == nil }
            : [:]
        // Each line as it was read, held until the page's own writing is known: a page written
        // right to left hands back the separators inside its numbers, and any line with no
        // right-to-left letter of its own, in the order it painted them (#41).
        var pending: [(semantic: String, bounds: CGRect, attributed: NSAttributedString?)] = []
        // Glyphs a show drew past the end of the line its origin fell in, waiting for the next
        // line of the same printed row (#237). A row TeX sets as one show and PDFKit reports as
        // several lines is read here, in PDFKit's own reading order, because only this loop sees
        // every line's text: `GlyphIdentityReader` is handed one line at a time. A line this loop
        // does not read at all cannot continue a row, so held glyphs are dropped rather than
        // reaching across it.
        var carry: GlyphIdentityReader.IndexGlyphCarry?
        for (index, line) in selections.enumerated() {
            try Task.checkCancellation()
            guard let raw = line.string else { carry = nil; continue }
            // U+FFFC names an attachment, not a word. Retain a boundary between adjacent
            // words; the graphics reader preserves the object's visible content separately.
            let transcription = invisibleSpacing.isEmpty ? raw : NativeSpacingReader.restoringInvisibleSpaces(
                raw, evidence: invisibleSpacing, bounds: boundsByLine[index], allBounds: invisibleBounds)
            let semantic = transcription.replacingOccurrences(of: "\u{FFFC}", with: " ")
            guard !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { carry = nil; continue }
            let bounds = line.bounds(for: page)
            guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { carry = nil; continue }
            // Object-only selections were discarded before requesting attributed text,
            // which can make PDFKit decode large image attachments.
            var attributed = includeStyle ? attributedByLine[index] ?? line.attributedString : nil
            if includeStyle, !rules.isEmpty, let text = attributed {
                attributed = markUnderlines(text, box: bounds, rules: rules, on: page)
            }
            if includeStyle, !links.isEmpty, let text = attributed {
                attributed = markLinks(text, box: bounds, links: links, on: page)
            }
            let spacingFixed = attributed.map {
                $0.string == raw ? NativeSpacingReader.apply(spacing, to: $0, bounds: bounds, allBounds: boundsByLine) : $0
            }
            // Glyphs a font's own map misreports are redrawn last: spacing evidence compares
            // PDFKit's characters with the shows' own maps, which must still agree (#217).
            var repaired: NSAttributedString?
            if let spacingFixed {
                repaired = GlyphIdentityReader.apply(glyphs, to: spacingFixed, bounds: bounds,
                                                     allBounds: boundsByLine, carry: &carry)
            }
            if let placed = delimiterPlacements[index], let current = repaired {
                repaired = ExtensionDelimiterReader.apply(placed, shows: spacing, delimiters: delimiters, to: current,
                                                          bounds: bounds)
            }
            // Preserve the literal source glyph; the exact continuation and compound guards
            // decide whether this font evidence applies when two lines are actually joined.
            if let word = discretionary[index] {
                repaired = repaired.map { DiscretionaryHyphenReader.apply(to: $0, word: word) }
            }
            if explicitSoftHyphens.contains(index) {
                repaired = repaired.map(DiscretionaryHyphenReader.restoreSoftHyphen)
            }
            // Chinese sets no space between the characters of a word, so a space the text layer
            // carries between two ideographs was never in the writing (#42).
            repaired = repaired.map(CJKText.joinIdeographs)
            let corrected = repaired?.string != attributed?.string
                ? repaired?.string.replacingOccurrences(of: "\u{FFFC}", with: " ") : nil
            guard let rule = marginRule[index] else {
                // A row of two columns PDFKit merged into one line is cut at the edge the rows
                // above and below it state, and each piece keeps its own half of the styled text
                // (#270). They are appended left then right, which is the order PDFKit reports the
                // pieces of a row it did divide.
                if let cut = gutterCuts[index],
                   let pieces = ColumnGutterCut.split(cut, from: repaired, text: corrected ?? semantic) {
                    pending.append((pieces.left.text, cut.left, pieces.left.styled))
                    pending.append((pieces.right.text, cut.right, pieces.right.styled))
                    continue
                }
                pending.append((corrected ?? semantic, bounds, repaired))
                continue
            }
            // The rule is page furniture, so it is kept out of the line: the marks go, and the
            // line is measured by the characters that remain. A line the rule drew and nothing
            // else carries no text at all (#264).
            guard !rule.rect.isNull else { carry = nil; continue }
            let (cutText, cutStyled) = MarginRuleMarks.cut(rule, from: repaired, text: corrected ?? semantic)
            pending.append((cutText, rule.rect, cutStyled))
        }
        // A slide build can paint the same text box twice. Remove the second impression before
        // detached-show splitting, where coincident bounds make show ownership ambiguous (#165).
        if pending.count > 1 {
            let impressions = pending.map { textLine(semantic: $0.semantic, bounds: $0.bounds, attributed: $0.attributed) }
            let retained = Set(withoutOverprints(impressions))
            if retained.count != pending.count {
                pending = pending.enumerated().compactMap { retained.contains($0.offset) ? $0.element : nil }
            }
        }
        // Opposite-side labels can share a PDFKit selection although the page leaves most of
        // its width blank between them (#172). Slice the already repaired attributed text, so
        // links and styles survive without issuing another attributed-text request.
        if !spacing.isEmpty, pending.count <= 10_000, spacing.count * pending.count <= 2_000_000 {
            let allBounds = pending.map(\.bounds)
            pending = try pending.flatMap { item in
                try Task.checkCancellation()
                let line = textLine(semantic: item.semantic, bounds: item.bounds, attributed: item.attributed)
                guard !line.monospaced,
                      let pieces = DetachedTextReader.pieces(text: item.semantic, rect: item.bounds,
                          size: line.fontSize, shows: spacing, allBounds: allBounds,
                          pageWidth: page.bounds(for: .cropBox).width,
                          measure: { rect, start, end in detachedPiece(rect, from: start, to: end, on: page) })
                else { return [item] }
                return pieces.map { piece in
                    let styled = item.attributed.flatMap { original -> NSAttributedString? in
                        // Attachment normalization replaces one UTF-16 unit with one space;
                        // ranges still align, as in textLine's existing style check.
                        guard original.string.replacingOccurrences(of: "\u{FFFC}", with: " ") == item.semantic
                        else { return nil }
                        return original.attributedSubstring(from: piece.range)
                    }
                    return (semantic: piece.text, bounds: piece.rect, attributed: styled)
                }
            }
        }
        let rightToLeft = ArabicText.readsRightToLeft(pending.map(\.semantic))
        let lines = pending.map { item in
            guard rightToLeft else { return textLine(semantic: item.semantic, bounds: item.bounds, attributed: item.attributed) }
            let ordered = item.attributed.map { ArabicText.logicalOrder($0, onRightToLeftPage: true) }
            // The styled text is what the line carries; the plain text follows it where the order
            // moved, and is reordered on its own where the line has no styled content.
            let semantic = ordered?.string != item.attributed?.string
                ? ordered!.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
                : ArabicText.logicalOrder(item.semantic, onRightToLeftPage: true)
            return textLine(semantic: semantic, bounds: item.bounds, attributed: ordered)
        }
        return VerticalJapaneseColumns.oriented(lines, language: language,
                                                pageWidth: page.bounds(for: .cropBox).width)
    }

    /// Indices of text impressions with distinct ink; offset shadows remain distinct (#165).
    static func withoutOverprints(_ lines: [TextLine]) -> [Int] {
        var byText: [String: [Int]] = [:]
        var kept: [Int] = []
        for (index, line) in lines.enumerated() {
            let duplicate = (byText[line.text] ?? []).contains { candidate in
                let other = lines[candidate]
                return abs(other.fontSize - line.fontSize) <= 0.01
                    && abs(other.rect.minX - line.rect.minX) <= 0.05
                    && abs(other.rect.minY - line.rect.minY) <= 0.05
                    && abs(other.rect.width - line.rect.width) <= 0.05
                    && abs(other.rect.height - line.rect.height) <= 0.05
            }
            if !duplicate {
                kept.append(index)
                byText[line.text, default: []].append(index)
            }
        }
        return kept
    }

    /// Separate independently painted labels on a slide when PDFKit joins their row. The
    /// ordinary detached-label rule keeps its wider threshold for books; PageReader calls this
    /// only after the page's top-band title establishes that it reads as a slide (#175).
    static func separateSlideLabels(_ lines: [TextLine], on page: PDFPage) throws -> [TextLine] {
        try withExtractionLock {
            guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return lines }
            let selections = selection.selectionsByLine()
            let texts = selections.map(\.string)
            let boxes = characterBoxes(of: texts, on: page)
            return lines.flatMap { line -> [TextLine] in
                guard line.turn == .upright, line.structure == nil, line.content.elements.count == 1,
                      case let .text(value, style) = line.content.elements[0], value == line.text,
                      let space = line.text.firstIndex(of: " "),
                      line.text.filter(\.isWhitespace).count == 1,
                      let left = String(line.text[..<space]).first,
                      let right = String(line.text[line.text.index(after: space)...]).first,
                      left.isUppercase, right.isUppercase,
                      let index = selections.indices.first(where: {
                          texts[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) == line.text
                              && selections[$0].bounds(for: page).intersects(line.rect)
                      }),
                      boxes[index].count == (line.text as NSString).length
                else { return [line] }
                let split = (line.text as NSString).range(of: " ").location
                guard split > 0, split + 1 < boxes[index].count else { return [line] }
                let leftBoxes = boxes[index][..<split], rightBoxes = boxes[index][(split + 1)...]
                guard leftBoxes.allSatisfy(\.isFinite), rightBoxes.allSatisfy(\.isFinite),
                      let first = leftBoxes.first, let second = rightBoxes.first else { return [line] }
                let leftRect = leftBoxes.dropFirst().reduce(first) { $0.union($1) }
                let rightRect = rightBoxes.dropFirst().reduce(second) { $0.union($1) }
                let gap = rightRect.minX - leftRect.maxX
                let least = max(line.fontSize * 4, page.bounds(for: .cropBox).width * 0.1)
                let gapRect = CGRect(x: leftRect.maxX, y: line.rect.minY,
                                     width: max(0, gap), height: line.rect.height)
                guard gap >= least, gap >= min(leftRect.width, rightRect.width),
                      !lines.contains(where: { $0 != line && $0.sharesRow(with: line)
                          && gapRect.intersects($0.rect) }) else { return [line] }
                let before = String(line.text[..<space])
                let after = String(line.text[line.text.index(after: space)...])
                return [TextLine(content: InlineText(before, style: style), rect: leftRect,
                                 fontSize: line.fontSize, monospaced: line.monospaced, wraps: line.wraps),
                        TextLine(content: InlineText(after, style: style), rect: rightRect,
                                 fontSize: line.fontSize, monospaced: line.monospaced, wraps: line.wraps)]
            }
        }
    }

    /// PDFKit can close a line across a form's empty rule: `State of (name).` is printed with a
    /// writing space before its period. Split only where the rule interior selects no letters or
    /// numbers, and require the pieces to spell the original line (#197, #211).
    static func splitAtBlanks(_ lines: [TextLine], blanks: [FormBlank], on page: PDFPage) throws -> [TextLine] {
        guard !blanks.isEmpty else { return lines }
        return try withExtractionLock {
            var result: [TextLine] = []
            for line in lines {
                try Task.checkCancellation()
                let em = max(4, line.fontSize)
                let crossed = blanks.filter { $0.sharesRow(with: line.rect) }
                    .map { $0.rule.insetBy(dx: 2, dy: 0) }
                    .filter { $0.width > em * 3 && line.rect.minX < $0.minX && line.rect.maxX > $0.maxX }
                    .sorted { $0.minX < $1.minX }
                guard !crossed.isEmpty, !line.monospaced, line.turn == .upright,
                      crossed.allSatisfy({ rule in
                          let interior = CGRect(x: rule.minX + em, y: line.rect.minY,
                                                width: rule.width - em * 2, height: line.rect.height)
                          return !(page.selection(for: interior)?.string ?? "").contains { $0.isLetter || $0.isNumber }
                      }) else { result.append(line); continue }
                let edges = [line.rect.minX] + crossed.map(\.midX) + [line.rect.maxX]
                var pieces: [TextLine] = []
                for (start, end) in zip(edges, edges.dropFirst()) {
                    guard let (reading, bounds) = detachedPiece(line.rect, from: start, to: end, on: page),
                          !reading.isEmpty else { pieces = []; break }
                    let selected = page.selection(for: CGRect(x: start, y: line.rect.minY,
                                                              width: end - start, height: line.rect.height))
                    let styled = selected?.attributedString
                    pieces.append(textLine(semantic: reading, bounds: bounds, attributed: styled))
                }
                func compact(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
                guard pieces.count == crossed.count + 1,
                      compact(pieces.map(\.text).joined()) == compact(line.text) else {
                    result.append(line); continue
                }
                for index in pieces.indices {
                    var rect = pieces[index].rect
                    if index > 0 {
                        let left = max(rect.minX, crossed[index - 1].maxX)
                        rect = CGRect(x: left, y: rect.minY, width: rect.maxX - left, height: rect.height)
                    }
                    if index < crossed.count { rect.size.width = min(rect.maxX, crossed[index].minX) - rect.minX }
                    guard rect.width > 0 else { pieces = []; break }
                    pieces[index].rect = rect
                }
                result += pieces.isEmpty ? [line] : pieces
            }
            return result
        }
    }

    private static func detachedPiece(_ rect: CGRect, from minX: CGFloat, to maxX: CGFloat,
                                on page: PDFPage) -> (String, CGRect)? {
        func selection(_ left: CGFloat, _ right: CGFloat) -> PDFSelection? {
            guard right > left else { return nil }
            return page.selection(for: CGRect(x: left, y: rect.minY, width: right - left, height: rect.height))
        }
        func visible(_ selection: PDFSelection?) -> String {
            (selection?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let target = visible(selection(minX, maxX))
        guard !target.isEmpty else { return nil }
        // Trim the synthesized space spanning the page, without trusting character offsets.
        var low = minX, high = maxX
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if visible(selection(minX, middle)) == target { high = middle } else { low = middle }
        }
        var left = minX
        low = minX
        var top = high
        for _ in 0..<14 {
            let middle = (low + top) / 2
            if visible(selection(middle, high)) == target { left = middle; low = middle } else { top = middle }
        }
        guard let chosen = selection(left, high), visible(chosen) == target else { return nil }
        let bounds = chosen.bounds(for: page)
        guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        return (target, bounds)
    }

    /// PDFKit's own rectangle for every character of every line, in the order `selectionsByLine`
    /// reports them (#264).
    ///
    /// `characterBounds(at:)` is indexed over the page's characters *without* the separators the
    /// reading synthesizes between rows, which is the offset the lines' own strings reach when
    /// they are laid end to end — the same relation `lineRanges` reads in the other direction.
    /// A page whose lines run past the characters it declares supplies no boxes at all rather
    /// than boxes read at the wrong offset.
    ///
    /// `private`: every PDFKit call here must stay inside the extraction gate (#21), which only
    /// this function's caller, `extractLines`, is verified to run inside.
    private static func characterBoxes(of texts: [String?], on page: PDFPage) -> [[CGRect]] {
        let lengths = texts.map { ($0 as NSString?)?.length ?? 0 }
        guard lengths.reduce(0, +) <= page.numberOfCharacters else { return texts.map { _ in [] } }
        var boxes: [[CGRect]] = []
        boxes.reserveCapacity(texts.count)
        var cursor = 0
        for length in lengths {
            boxes.append((cursor..<(cursor + length)).map { page.characterBounds(at: $0) })
            cursor += length
        }
        return boxes
    }

    /// The attributed text of the lines at `indices`, read with one PDFKit request for the page.
    /// PDFKit leaks every attributed string it returns (FB24783799, #4): the string, its runs and
    /// a font and attribute dictionary per run. A request per line leaves that whole graph behind
    /// for every line; one request for their union leaves the page's characters once. Each line's
    /// slice of the union carries the attributes its own request returns. A page whose union text
    /// does not align with its lines (`lineRanges`) returns nothing, and its lines are requested
    /// one by one as before; so does a page with a single styled line. `private`: every PDFKit call
    /// here must stay inside the extraction gate (#21), which only this function's caller,
    /// `extractLines`, is verified to run inside; the alignment logic it hands off to
    /// (`sliceUnion`) makes none and is tested directly.
    private static func attributedTexts(of indices: [Int], in selections: [PDFSelection], texts: [String?],
                                        on page: PDFPage) -> [Int: NSAttributedString] {
        guard indices.count > 1, let document = page.document else { return [:] }
        let union = PDFSelection(document: document)
        union.add(indices.map { selections[$0] })
        guard let plain = union.string, let whole = union.attributedString else { return [:] }
        return sliceUnion(of: indices, texts: texts, plainUnion: plain, attributedUnion: whole)
    }

    /// The pure alignment-and-slice step of `attributedTexts`, with the union's plain and
    /// attributed text already in hand: no PDFKit call of its own, so it needs no gate.
    /// The plain text is checked before slicing the attributed text, since a page whose lines
    /// don't align at all should not pay for slicing the one PDFKit call that leaks.
    static func sliceUnion(of indices: [Int], texts: [String?], plainUnion: String,
                           attributedUnion: NSAttributedString) -> [Int: NSAttributedString] {
        let lines = indices.map { texts[$0] ?? "" }
        guard lineRanges(of: lines, in: plainUnion) != nil,
              let ranges = lineRanges(of: lines, in: attributedUnion.string) else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(indices, ranges.map(attributedUnion.attributedSubstring)))
    }

    /// Where each line's text lies in the text of their union: in order, each directly after the
    /// previous one or after a single newline, and nothing after the last. PDFKit separates lines
    /// of different rows with a newline and runs pieces of one row together. Nil when the union's
    /// text is anything else, such as lines out of reading order or a line holding a newline.
    static func lineRanges(of lines: [String], in union: String) -> [NSRange]? {
        let text = union as NSString
        var ranges: [NSRange] = []
        var cursor = 0
        for line in lines {
            let length = (line as NSString).length
            func holds(at location: Int) -> Bool {
                location + length <= text.length
                    && (text.substring(with: NSRange(location: location, length: length)) as NSString).isEqual(to: line)
            }
            if !holds(at: cursor), cursor < text.length, text.character(at: cursor) == 0x0A { cursor += 1 }
            guard length > 0, holds(at: cursor) else { return nil }
            ranges.append(NSRange(location: cursor, length: length))
            cursor += length
        }
        return cursor == text.length ? ranges : nil
    }

    /// Marks the runs a page paints a rule under, so emphasis the font does not carry survives
    /// reflow (#235).
    ///
    /// The 9/11 report underlines single words by painting a filled path, not by setting an
    /// underlined font, so nothing in the text layer records it. PDFKit's own hit-testing supplies
    /// the range: the selection over the rule's horizontal extent within the line's box is the
    /// underlined text, and the selection from the line's left edge to the rule's start is what
    /// precedes it, whose length is the offset. Position is what resolves a word the line holds
    /// twice — page 161 underlines `gain` on a line that also reads `gains`.
    ///
    /// `GraphicsReader` pads a region by two points on each side, which is removed before asking,
    /// or the selection takes the character beyond the rule's ink. A rule reaching most of the
    /// line's measure is its decoration or a table's rule rather than emphasis of a word, and a
    /// run of no letters is not a word, so neither is marked. A computed range whose text is not
    /// the text PDFKit selected is dropped rather than guessed at.
    private static func markUnderlines(_ attributed: NSAttributedString, box: CGRect, rules: [CGRect],
                                       on page: PDFPage) -> NSAttributedString {
        let underlining = rules.map { $0.insetBy(dx: 2, dy: 0) }.filter { rule in
            rule.width > 0 && rule.width <= box.width * 0.9
                // Inside the line's own box, in its lower half: a rule above the box belongs to
                // the line above it — Wallace's radical vincula sit a point or two over the line
                // beneath them and would otherwise read as its underline.
                && rule.midY >= box.minY && rule.midY <= box.minY + box.height * 0.5
                // A rule under the start of a line is that line's own decoration — an underlined
                // section label, a heading's rule — and the words it carries are not emphasized
                // against the rest of the line. Emphasis of a word sits inside the measure.
                && rule.minX > box.minX + 1 && rule.maxX <= box.maxX + 3
        }
        // Emphasis is a thing running prose does. A line of mathematics is full of rules that are
        // its terms' — vincula, fraction bars — and none of them emphasizes anything, so a line
        // that does not read as a sentence is left alone.
        let words = attributed.string.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }
        guard !underlining.isEmpty, attributed.length > 0, words.count >= 4 else { return attributed }
        let marked = NSMutableAttributedString(attributedString: attributed)
        for rule in underlining {
            let over = CGRect(x: rule.minX, y: box.minY, width: rule.width, height: box.height)
            let before = CGRect(x: box.minX, y: box.minY, width: max(0, rule.minX - box.minX),
                                height: box.height)
            // Emphasis marks words. A rule over a single letter or a digit is a mathematical
            // term's — a radical's vinculum, a fraction's bar — and Wallace's `y`, `2` and `− y`
            // are what marking those produces.
            guard let text = page.selection(for: over)?.string, text.utf16.count <= 60,
                  text.filter(\.isLetter).count >= 2 else { continue }
            let offset = page.selection(for: before)?.string?.utf16.count ?? 0
            let range = NSRange(location: offset, length: text.utf16.count)
            guard range.location >= 0, range.upperBound <= marked.length,
                  (marked.string as NSString).substring(with: range) == text else { continue }
            marked.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        return marked
    }

    /// The target of the link covering a run, set by `markLinks` and read by `inlineText`.
    private static let linkAttribute = NSAttributedString.Key("PDFReflowLinkTarget")

    /// Carries a link target through an attributed string, which stores objects.
    private final class LinkBox: NSObject {
        let target: LinkTarget
        init(_ target: LinkTarget) { self.target = target }
    }

    /// Marks the runs a link annotation covers, so a link survives reflow as a link (#247).
    ///
    /// This is #235's geometry, which the underline rule established: the selection over the
    /// annotation's horizontal extent within the line's box is the linked text, and the selection
    /// from the line's left edge to the annotation's start gives the offset. Position is what
    /// distinguishes one occurrence of a word from another on the same line.
    ///
    /// None of the underline rule's guards against decoration apply here. A link is not
    /// typography a reader might mistake for something else: the page states outright that this
    /// rectangle points somewhere, so a link over a whole line, over one letter, or over a line
    /// that reads as no sentence is still that link. The only requirements are that the
    /// annotation and the line meet over most of the line's height — a link on the line above
    /// must not claim this one — and that the text PDFKit selects is the text at the computed
    /// offset, which is what keeps a mismatch from marking the wrong words.
    private static func markLinks(_ attributed: NSAttributedString, box: CGRect, links: [PageLink],
                                  on page: PDFPage) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let covering = links.filter { link in
            let overlap = link.rect.intersection(box)
            return !overlap.isNull && overlap.width >= 1 && overlap.height >= box.height * 0.5
        }
        guard !covering.isEmpty else { return attributed }
        let marked = NSMutableAttributedString(attributedString: attributed)
        for link in covering {
            let overlap = link.rect.intersection(box)
            let over = CGRect(x: overlap.minX, y: box.minY, width: overlap.width, height: box.height)
            let before = CGRect(x: box.minX, y: box.minY, width: max(0, overlap.minX - box.minX),
                                height: box.height)
            guard let text = page.selection(for: over)?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let offset = page.selection(for: before)?.string?.utf16.count ?? 0
            let range = NSRange(location: offset, length: text.utf16.count)
            guard range.location >= 0, range.length > 0, range.upperBound <= marked.length,
                  (marked.string as NSString).substring(with: range) == text else { continue }
            marked.addAttribute(linkAttribute, value: LinkBox(link.target), range: range)
        }
        return marked
    }

    /// The size a line's own text is set in, where a list marker opens it at a size of its own.
    ///
    /// A marker is drawn at whatever size the page likes: the Fed's page 58 sets a 10-point bullet
    /// over 8-point text on 14 lines, and IRS Publication 596 sets one large enough that seven of
    /// its bulleted sentences were read as headings. The line's size comes from its first
    /// character, so the marker states it for the whole line, in either direction — a marker
    /// larger than its item overstates the line and a smaller one understates it (#183, #254).
    ///
    /// Only a line opening with a marker glyph and a space is concerned, and only the run holding
    /// that marker is skipped. A contents line's dot leaders, a drop cap and an opening quotation
    /// mark are not markers and are left exactly as they were: weighting every character instead
    /// cost the Fed its seven chapter entries and Our Flag its Pledge of Allegiance display lines,
    /// which is the survey this rule replaced.
    private static func sizeAfterListMarker(_ attributed: NSAttributedString) -> CGFloat? {
        let string = attributed.string as NSString
        guard string.length >= 2, let opening = string.substring(to: 1).first,
              !opening.isLetter, !opening.isNumber, !opening.isWhitespace,
              string.substring(with: NSRange(location: 1, length: 1)).first?.isWhitespace == true
        else { return nil }
        var markerRange = NSRange()
        guard let marker = attributed.attribute(.font, at: 0, effectiveRange: &markerRange) as? PlatformFont,
              markerRange.upperBound < attributed.length else { return nil }
        let size = (attributed.attribute(.font, at: markerRange.upperBound, effectiveRange: nil)
            as? PlatformFont)?.pointSize
        // Correcting the smaller marker too is what promoted IRS Publication 596's starred
        // footnotes into headings while this rule read one direction only. What stops that is not
        // a bound on the size but the reading of the line: a bulleted line is an item of a list,
        // whatever size its text is set in, and `LayoutReconstructor.role` no longer calls one a
        // heading (#254).
        guard let size, size.isFinite, size > 0, marker.pointSize != size else { return nil }
        return size
    }

    static func textLine(semantic: String, bounds: CGRect, attributed: NSAttributedString?) -> TextLine {
        let font = (attributed?.length ?? 0) > 0
            ? attributed?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont : nil
        let name = font?.fontName.lowercased() ?? ""
        let mono = name.contains("courier") || name.contains("mono")
        // A list marker is drawn at its own size and must not state the line's (#183).
        let proposedSize = attributed.flatMap(sizeAfterListMarker) ?? font?.pointSize ?? bounds.height
        let size = proposedSize.isFinite && proposedSize > 0 && proposedSize <= 100_000
            ? proposedSize : min(100_000, bounds.height)
        let text = semantic.trimmingCharacters(in: mono ? .newlines : .whitespacesAndNewlines)
        var styled: InlineText?
        if let attributed, attributed.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) == text {
            styled = inlineText(from: attributed)
        }
        // Keep each selection's own text with its geometry. PDFKit's characterBounds offsets
        // need not agree with string offsets at synthesized newlines on current OS builds.
        var result = TextLine(content: styled ?? InlineText(text), rect: bounds,
            fontSize: size, monospaced: mono)
        if !mono, styled != nil, let attributed, let bodySize = dropCapBodySize(in: attributed),
           bounds.height >= bodySize * 2, bounds.width >= bodySize * 8 {
            result.fontSize = bodySize
            result.readingRect = CGRect(x: bounds.minX, y: bounds.maxY - bodySize,
                width: bounds.width, height: bodySize)
        }
        return result
    }

    /// A lowered, oversized single initial followed by a substantial normal-baseline body run.
    /// This is typography evidence, not a claim that the PDF has logical structure tags.
    private static func dropCapBodySize(in attributed: NSAttributedString) -> CGFloat? {
        guard attributed.length > 0 else { return nil }
        var initialRange = NSRange()
        let initial = attributed.attributes(at: 0, effectiveRange: &initialRange)
        let first = (attributed.string as NSString).substring(with: initialRange)
            .trimmingCharacters(in: .whitespaces)
        guard first.count == 1, first.first?.isUppercase == true,
              initialRange.length < attributed.length,
              let cap = initial[.font] as? PlatformFont,
              !cap.fontName.lowercased().contains("courier"),
              !cap.fontName.lowercased().contains("mono") else { return nil }
        let rest = NSRange(location: initialRange.length, length: attributed.length - initialRange.length)
        let bodyText = (attributed.string as NSString).substring(with: rest)
        guard bodyText.first?.isLowercase == true, bodyText.filter(\.isLetter).count >= 20,
              !bodyText.contains("\n"), !bodyText.contains("\r") else { return nil }
        let body = attributed.attributes(at: rest.location, effectiveRange: nil)
        guard let font = body[.font] as? PlatformFont else { return nil }
        let size = font.pointSize
        let offset = baselineOffset(initial)
        guard size.isFinite, size > 0, cap.pointSize.isFinite, cap.pointSize <= 100_000,
              cap.pointSize >= size * 2, cap.pointSize <= size * 8,
              offset.isFinite, offset <= -size, offset >= -cap.pointSize else { return nil }
        var consistent = true
        attributed.enumerateAttributes(in: rest) { attributes, _, _ in
            guard let font = attributes[.font] as? PlatformFont,
                  font.pointSize.isFinite, abs(font.pointSize - size) <= size * 0.1,
                  baselineOffset(attributes).isFinite,
                  abs(baselineOffset(attributes)) < size * 0.12 else {
                consistent = false; return
            }
        }
        return consistent ? size : nil
    }

    private static func baselineOffset(_ attributes: [NSAttributedString.Key: Any]) -> Double {
        (attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
            ?? attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
    }

    /// Whether a run may take a script style at all; `inlineText` gives the reasons for each exception.
    private static func mayTakeScript(_ attributes: [NSAttributedString.Key: Any], run: String, first: Bool,
                                      hasDropCap: Bool, offset: Double) -> Bool {
        !(hasDropCap && first)
            && attributes[GlyphIdentityReader.isolatedAttribute] == nil
            && run.contains(where: { !$0.isWhitespace })
            && !ArabicText.isRightToLeftRun(run)
            && offset.isFinite
    }

    /// A first-level script run: its style, its baseline offset and its size.
    struct ScriptAnchor {
        let script: TextStyle
        let offset: Double
        let size: Double
    }

    /// The script level a glyph run is drawn at, from its baseline offset, and from the
    /// first-level script it follows when there is one (#302).
    ///
    /// On its own a run is a script where its offset lies beyond positioning noise and within
    /// three quarters of its own size; beyond that is a layout shift of a whole line, not a script.
    /// A run that follows a first-level script with no baseline glyph between can be read against
    /// that script instead, in two ways the source draws:
    ///
    /// - **A second level.** A run set smaller again than the script it follows, drawn off the
    ///   line's baseline and raised or lowered from that script by more than noise and at most
    ///   three quarters of the script's size, is the script's own superscript or subscript:
    ///   `STA` with `n` raised and `i` raised from `n`, or `x` with `i` lowered and `j` lowered
    ///   from `i`. Smaller again but on the script's own baseline, it is more of that script. Its
    ///   own size says nothing about how far it may sit from the line's baseline, because that
    ///   distance is the two levels' shifts together.
    /// - **The same level set further out.** A run the script's size, further from the baseline on
    ///   the script's side, within three quarters of the line's own size, is a script at the same
    ///   level: Wallace page 178 raises the exponent of `(a²)³` over a tall parenthesis the text
    ///   layer does not carry, so it stands higher than the `²` it follows. On the script's own
    ///   baseline it is more of that script, however far that is from the line's (#304): DASC's
    ///   `STA^{r_f(k)}` resumes `(k)` at `r`'s height after the second-level `f`.
    ///
    /// `stacked` admits a superscript its own size would reject, where `scriptBaseline` found the
    /// stack TeX raises it over (#304).
    static func scriptStyle(offset: Double, size: Double, tolerance: Double,
                            after anchor: ScriptAnchor?, lineSize: Double, stacked: Bool = false) -> TextStyle {
        var own: TextStyle = []
        if abs(offset) <= size * 0.75 || stacked {
            if offset > tolerance { own = .superscript } else if offset < -tolerance { own = .subscript }
        }
        guard let anchor else { return own }
        let shift = offset - anchor.offset
        if size <= anchor.size * 0.9 {
            guard abs(offset) > tolerance else { return own }
            if abs(shift) <= tolerance { return anchor.script }
            guard abs(shift) <= anchor.size * 0.75 else { return own }
            return anchor.script.union(shift > 0 ? .nestedSuperscript : .nestedSubscript)
        }
        let sameSize = abs(size - anchor.size) <= max(0.5, anchor.size * 0.1)
        if own.isEmpty, sameSize, abs(offset) > tolerance, abs(shift) <= tolerance { return anchor.script }
        let further = anchor.script.contains(.superscript) ? shift > tolerance : shift < -tolerance
        if own.isEmpty, further, sameSize, abs(shift) <= anchor.size * 0.75, abs(offset) <= lineSize * 0.75 {
            return anchor.script
        }
        return own
    }

    /// A run as `scriptBaseline` reads it (#304).
    struct ScriptRun {
        let location: Int
        let text: String
        /// Its font's size; nil where PDFKit names no font.
        let size: Double?
        let offset: Double
        /// Whether it may take a script style at all: `inlineText` never gives one to a drop
        /// cap, an isolated glyph, a run of right-to-left letters or a run holding no glyph.
        let eligible: Bool
    }

    /// The offset a line's scripts are measured from, and the runs admitted as superscripts raised
    /// over a stack of their own (#304).
    ///
    /// PDFKit states every run's baseline offset from one reference per line, and the reference
    /// need not be the baseline the line's text stands on: Wallace page 178 reads `a²` as `a` at
    /// −4.32 and its exponent at 0.00, and DASC page 5 reads `STA` at −2.71 and its superscript at
    /// +2.71. Where every body-size run of the line (over 90% of its largest glyph size) stands on
    /// one baseline, and a script set against that text shows it — a run at most 90% of a body
    /// run's size, following it with no space between, off it by more than its tolerance and
    /// within the script limit — the line's scripts are measured from that baseline instead. The
    /// body run must end in a glyph a script is set against. An opening bracket, a dash, a relation
    /// or an operator begins or joins operands, and a smaller run after one is a numerator or a new
    /// operand: the Replay Clocks paper sets the numerator of `⌊mpt.f / I⌋` after `(`. Body text on
    /// two baselines, such as a big operator PDFKit measures from its top (the Census report's
    /// sums) or two rows it ran together, leaves the reference where PDFKit put it.
    ///
    /// TeX raises a superscript further when it carries a script of its own, past three quarters
    /// of its own size, the limit that otherwise tells a script from a fraction's numerator: DASC
    /// raises `n` in `STA^{n^i_h}_h` 5.42 points at 6.97, and in `A^{n^i_f,j}_f` 6.39. Such a run
    /// is admitted when it is raised from a body run ending in a letter or digit, at most three
    /// quarters of that run's size, and the run after it is its own second level: smaller again,
    /// following it with no space between, and raised or lowered from it by more than its
    /// tolerance and at most three quarters of its size. A numerator starts a new operand after
    /// `=`, a bracket or a problem number (Wallace page 51's `10) E = mv²/2`, page 187's `13)` over
    /// `u²v`), and the numerators Wallace sets after a letter or digit (a mixed number's `1`) carry
    /// no second level of their own.
    static func scriptBaseline(of runs: [ScriptRun], lineSize: Double) -> (reference: Double, stacked: Set<Int>) {
        func tolerance(_ size: Double) -> Double { max(0.5, size * 0.12) }
        func size(_ run: ScriptRun) -> Double? { run.eligible ? run.size : nil }
        func touching(_ left: ScriptRun, _ right: ScriptRun) -> Bool {
            left.text.last?.isWhitespace == false && right.text.first?.isWhitespace == false
        }
        let body = runs.filter { (size($0) ?? 0) > lineSize * 0.9 }
        guard let reference = body.first?.offset,
              body.allSatisfy({ abs($0.offset - reference) <= tolerance($0.size ?? 0) }) else { return (0, []) }
        var shown = false
        var stacked: Set<Int> = []
        for index in runs.indices.dropLast() {
            let base = runs[index], script = runs[index + 1]
            guard let baseSize = size(base), baseSize > lineSize * 0.9, let scriptSize = size(script),
                  scriptSize <= baseSize * 0.9, touching(base, script),
                  let last = base.text.unicodeScalars.last, carriesScripts(last) else { continue }
            let shift = script.offset - reference
            guard abs(shift) > tolerance(scriptSize) else { continue }
            if abs(shift) <= scriptSize * 0.75 { shown = true; continue }
            guard shift > 0, shift <= baseSize * 0.75,
                  last.properties.isAlphabetic || last.properties.numericType != nil,
                  index + 2 < runs.count, case let inner = runs[index + 2], let innerSize = size(inner),
                  innerSize <= scriptSize * 0.9, touching(script, inner),
                  case let step = abs(inner.offset - script.offset),
                  step > tolerance(innerSize), step <= scriptSize * 0.75 else { continue }
            shown = true
            stacked.insert(script.location)
        }
        return shown ? (reference, stacked) : (0, [])
    }

    /// Whether a script can be set against this glyph: not an opening bracket, a dash, a relation
    /// or an operator, which begin or join operands rather than carry scripts (#304).
    static func carriesScripts(_ glyph: Unicode.Scalar) -> Bool {
        guard !glyph.properties.isWhitespace else { return false }
        switch glyph.properties.generalCategory {
        case .openPunctuation, .dashPunctuation, .mathSymbol: return false
        default: return glyph != "·" && glyph != "/"
        }
    }

    static func inlineText(from attributed: NSAttributedString) -> InlineText {
        let hasDropCap = dropCapBodySize(in: attributed) != nil
        var runs: [(text: String, style: TextStyle, link: LinkTarget?)] = []
        var previous: (offset: Double, size: Double, text: String, nested: Bool)?
        // The first-level script the runs since the last one on the baseline belong to, which a
        // second level is measured from (#302).
        var anchor: ScriptAnchor?
        // A tall delimiter restored just before this run, and its baseline offset (#305).
        var delimiter: (reach: ExtensionDelimiterReader.Reach, offset: Double)?
        var lineSize = 0.0
        // Every run as the script measurement reads it (#304).
        var scriptRuns: [ScriptRun] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let raw = (attributed.string as NSString).substring(with: range)
            let text = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
            let pointSize = (attributes[.font] as? PlatformFont).map { Double($0.pointSize) }
            let offset = baselineOffset(attributes)
            scriptRuns.append(ScriptRun(
                location: range.location, text: text,
                size: pointSize.flatMap { $0.isFinite && $0 > 0 && $0 <= 100_000 ? $0 : nil }, offset: offset,
                eligible: mayTakeScript(attributes, run: text, first: range.location == 0, hasDropCap: hasDropCap,
                                        offset: offset)))
            guard let size = pointSize, size.isFinite, size <= 100_000, raw.contains(where: { !$0.isWhitespace })
            else { return }
            lineSize = max(lineSize, size)
        }
        let baseline = scriptBaseline(of: scriptRuns, lineSize: lineSize)
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let font = attributes[.font] as? PlatformFont
            let name = font?.fontName.lowercased() ?? ""
            let run = (attributed.string as NSString).substring(with: range)
                .replacingOccurrences(of: "\u{FFFC}", with: " ")
            // A run holding no glyph at all draws nothing a reader could see emphasized, so it
            // takes no emphasis from its font: `<strong> </strong>` and `<em> </em>` claim italic
            // or bold over a space (#278). The run itself is kept, exactly as #273 keeps it — the
            // page set that space and the words on either side need it. An underline is judged
            // differently: a rule the page painted under a space is ink the page really put
            // there (#235), so it is not a font's claim to drop.
            let hasGlyph = run.contains(where: { !$0.isWhitespace })
            var style: TextStyle = []
            if hasGlyph, name.contains("italic") || name.contains("oblique") { style.insert(.italic) }
            if hasGlyph, name.contains("bold") { style.insert(.bold) }
            // Set by `markUnderlines` from the page's own painted rules, not by the font (#235).
            if attributes[.underlineStyle] != nil { style.insert(.underline) }
            // PDFKit supplies Core Text baseline offsets even when font size/name do not
            // change. Preserve that evidence instead of guessing from character offsets.
            let offset = (attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
                ?? attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
            let size = Double(font?.pointSize ?? 12)
            let tolerance = max(0.5, (font?.pointSize ?? 12) * 0.12)
            // Some PDFKit selections combine several OCR lines, represented as baseline
            // shifts of a full line height. Those are layout offsets, not inline scripts.
            // A glyph GlyphIdentityReader redrew from a font's own table and found standing
            // alone between word spaces (a dingbat bullet substituted with a mismatched font,
            // #217) is never an inline superscript or subscript, however its metrics place it.
            // Neither is a run of right-to-left letters, whose shaping shifts single letters off
            // the baseline inside a word the page never raised (#41).
            // And a run holding no glyph at all takes no script style, however its metrics place
            // it: a raised space is a space, and `<sup> </sup>` claims an inline script over
            // nothing a reader can see raised (#273). The run itself is kept — the page set that
            // space and the words on either side of it need it — it simply keeps the body's
            // baseline, which is the only thing about it a reader could have observed.
            if mayTakeScript(attributes, run: run, first: range.location == 0, hasDropCap: hasDropCap, offset: offset) {
                // Measured from the baseline the line's text stands on, where PDFKit's reference
                // is not that baseline (#304).
                let measured = offset - baseline.reference
                var script = scriptStyle(offset: measured, size: size, tolerance: tolerance, after: anchor,
                                         lineSize: lineSize, stacked: baseline.stacked.contains(range.location))
                if script.isEmpty, let delimiter {
                    script = ExtensionDelimiterReader.script(after: delimiter.reach, at: delimiter.offset,
                                                             offset: offset, size: size, tolerance: tolerance)
                }
                style.formUnion(script)
                // A second-level run leaves the anchor where it is, so the outer script can resume
                // after it. Only a first-level script anchors, and only one set smaller than the
                // line's own text: a body-sized run the reference baseline happens to place off
                // zero is not a script a smaller glyph could be raised from.
                if !script.contains(.nestedSuperscript), !script.contains(.nestedSubscript) {
                    anchor = !script.isEmpty && size <= lineSize * 0.9
                        ? ScriptAnchor(script: script, offset: measured, size: size) : nil
                }
            } else if hasGlyph {
                anchor = nil
            }
            if hasGlyph {
                delimiter = (attributes[ExtensionDelimiterReader.reachAttribute] as? ExtensionDelimiterReader.Reach)
                    .map { ($0, offset) }
            }
            let nested = style.contains(.nestedSuperscript) || style.contains(.nestedSubscript)
            // PDFKit can concatenate separate visual lines without a space while retaining
            // their full-line baseline offsets. Require matching font sizes and a jump beyond
            // the inline-script range; opposite superscripts/subscripts alone are not evidence.
            // Nor is a step between two glyphs of one second script level, which rises and falls
            // around the script they belong to by more than their own small size (#302).
            if let previous, font != nil, size.isFinite, size > 0, offset.isFinite,
               !(nested && previous.nested),
               abs(size - previous.size) <= max(0.5, max(size, previous.size) * 0.1),
               abs(offset - previous.offset) > max(size, previous.size) * 0.75,
               (abs(offset) > size * 0.75 || abs(previous.offset) > previous.size * 0.75),
               let last = previous.text.last, let first = run.first,
               !last.isWhitespace, !first.isWhitespace, last != "-", last != "\u{00ad}" {
                runs.append((" ", [], nil))
            }
            previous = font != nil && size.isFinite && size > 0 && offset.isFinite
                ? (offset, size, run, nested) : nil
            runs.append((run, style, (attributes[linkAttribute] as? LinkBox)?.target))
        }
        // `enumerateAttributes` splits at every attribute change, including ones no style reads, so
        // one underlined word can arrive as several runs of one style. Adjacent runs that read the
        // same are one run, which keeps `<u>more</u>` from being written `<u>mor</u><u>e</u>`.
        var merged: [(text: String, style: TextStyle, link: LinkTarget?)] = []
        for run in runs {
            if let previous = merged.last, previous.style == run.style, previous.link == run.link {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        // Consecutive runs one link covers are one anchor over its styled runs, not one anchor
        // each: a linked phrase whose middle word is italic stays one link (#247).
        var elements: [InlineText.Element] = []
        for run in merged {
            guard let target = run.link else { elements.append(.text(run.text, run.style)); continue }
            if case let .link(previous, inner)? = elements.last, previous == target {
                var inner = inner
                inner.elements.append(.text(run.text, run.style))
                elements[elements.count - 1] = .link(target, inner)
            } else {
                elements.append(.link(target, InlineText(elements: [.text(run.text, run.style)])))
            }
        }
        var result = InlineText(elements: elements).trimmingCharacters(in: .whitespacesAndNewlines)
        let original = attributed.string as NSString
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("-"), let range = attributed.string.range(of: trimmed, options: .backwards) {
            let end = NSRange(range, in: attributed.string).upperBound - 1
            result.sourceDiscretionaryWord = attributed.attribute(DiscretionaryHyphenReader.attribute,
                at: end, effectiveRange: nil) as? String
        }
        return result
    }
}
