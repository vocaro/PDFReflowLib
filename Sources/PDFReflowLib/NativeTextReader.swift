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
                      shows: [NativeSpacingReader.Evidence]? = nil) throws -> [TextLine] {
        try withExtractionLock {
            try extractLines(on: page, limit: limit, includeStyle: includeStyle, rules: rules,
                             links: links, preserveInvisibleWordGaps: preserveInvisibleWordGaps, shows: shows)
        }
    }

    private static func extractLines(on page: PDFPage, limit: Int, includeStyle: Bool,
                                     rules: [CGRect], links: [PageLink] = [], preserveInvisibleWordGaps: Bool = false,
                                     shows: [NativeSpacingReader.Evidence]? = nil) throws -> [TextLine] {
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
        let rightToLeft = ArabicText.readsRightToLeft(pending.map(\.semantic))
        return pending.map { item in
            guard rightToLeft else { return textLine(semantic: item.semantic, bounds: item.bounds, attributed: item.attributed) }
            let ordered = item.attributed.map { ArabicText.logicalOrder($0, onRightToLeftPage: true) }
            // The styled text is what the line carries; the plain text follows it where the order
            // moved, and is reordered on its own where the line has no styled content.
            let semantic = ordered?.string != item.attributed?.string
                ? ordered!.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
                : ArabicText.logicalOrder(item.semantic, onRightToLeftPage: true)
            return textLine(semantic: semantic, bounds: item.bounds, attributed: ordered)
        }
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

    static func inlineText(from attributed: NSAttributedString) -> InlineText {
        let hasDropCap = dropCapBodySize(in: attributed) != nil
        var runs: [(text: String, style: TextStyle, link: LinkTarget?)] = []
        var previous: (offset: Double, size: Double, text: String)?
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
            // PDFKit can concatenate separate visual lines without a space while retaining
            // their full-line baseline offsets. Require matching font sizes and a jump beyond
            // the inline-script range; opposite superscripts/subscripts alone are not evidence.
            if let previous, font != nil, size.isFinite, size > 0, offset.isFinite,
               abs(size - previous.size) <= max(0.5, max(size, previous.size) * 0.1),
               abs(offset - previous.offset) > max(size, previous.size) * 0.75,
               (abs(offset) > size * 0.75 || abs(previous.offset) > previous.size * 0.75),
               let last = previous.text.last, let first = run.first,
               !last.isWhitespace, !first.isWhitespace, last != "-", last != "\u{00ad}" {
                runs.append((" ", [], nil))
            }
            previous = font != nil && size.isFinite && size > 0 && offset.isFinite
                ? (offset, size, run) : nil
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
            if !(hasDropCap && range.location == 0),
               attributes[GlyphIdentityReader.isolatedAttribute] == nil,
               hasGlyph,
               !ArabicText.isRightToLeftRun(run),
               offset.isFinite, abs(offset) <= (font?.pointSize ?? 12) * 0.75 {
                if offset > tolerance { style.insert(.superscript) }
                else if offset < -tolerance { style.insert(.subscript) }
            }
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
        return InlineText(elements: elements).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
