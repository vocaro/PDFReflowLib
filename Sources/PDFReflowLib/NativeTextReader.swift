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

    static func lines(on page: PDFPage, limit: Int, includeStyle: Bool = true) throws -> [TextLine] {
        try withExtractionLock { try extractLines(on: page, limit: limit, includeStyle: includeStyle) }
    }

    private static func extractLines(on page: PDFPage, limit: Int, includeStyle: Bool) throws -> [TextLine] {
        guard page.numberOfCharacters <= limit else {
            throw ConversionError.resourceLimit("too many characters")
        }
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let selections = selection.selectionsByLine()
        let boundsByLine = selections.map { $0.bounds(for: page) }
        let spacing = includeStyle ? page.pageRef.map(NativeSpacingReader.read) ?? [] : []
        let glyphs = includeStyle ? page.pageRef.map(GlyphIdentityReader.read) ?? [] : []
        // PDFKit's text of every line, beside its rectangle: read once so both the styled-line
        // filter below and `attributedTexts`'s alignment check reuse it instead of asking PDFKit
        // for each line's plain text twice.
        let textsByLine = selections.map(\.string)
        // Every line the loop below reads with style: one with visible text over a real rectangle.
        let styledLines = includeStyle ? selections.indices.filter { index in
            guard let raw = textsByLine[index], !raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let bounds = boundsByLine[index]
            return bounds.isFinite && !bounds.isNull && bounds.width > 0 && bounds.height > 0
        } : []
        let attributedByLine = attributedTexts(of: styledLines, in: selections, texts: textsByLine, on: page)
        var result: [TextLine] = []
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
            let semantic = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
            guard !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { carry = nil; continue }
            let bounds = line.bounds(for: page)
            guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { carry = nil; continue }
            // Object-only selections were discarded before requesting attributed text,
            // which can make PDFKit decode large image attachments.
            let attributed = includeStyle ? attributedByLine[index] ?? line.attributedString : nil
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
            result.append(textLine(semantic: corrected ?? semantic,
                                   bounds: bounds, attributed: repaired))
        }
        return result
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

    static func textLine(semantic: String, bounds: CGRect, attributed: NSAttributedString?) -> TextLine {
        let font = (attributed?.length ?? 0) > 0
            ? attributed?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont : nil
        let name = font?.fontName.lowercased() ?? ""
        let mono = name.contains("courier") || name.contains("mono")
        let proposedSize = font?.pointSize ?? bounds.height
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
        var runs: [InlineText.Element] = []
        var previous: (offset: Double, size: Double, text: String)?
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let font = attributes[.font] as? PlatformFont
            let name = font?.fontName.lowercased() ?? ""
            let run = (attributed.string as NSString).substring(with: range)
                .replacingOccurrences(of: "\u{FFFC}", with: " ")
            var style: TextStyle = []
            if name.contains("italic") || name.contains("oblique") { style.insert(.italic) }
            if name.contains("bold") { style.insert(.bold) }
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
                runs.append(.text(" ", []))
            }
            previous = font != nil && size.isFinite && size > 0 && offset.isFinite
                ? (offset, size, run) : nil
            let tolerance = max(0.5, (font?.pointSize ?? 12) * 0.12)
            // Some PDFKit selections combine several OCR lines, represented as baseline
            // shifts of a full line height. Those are layout offsets, not inline scripts.
            // A glyph GlyphIdentityReader redrew from a font's own table and found standing
            // alone between word spaces (a dingbat bullet substituted with a mismatched font,
            // #217) is never an inline superscript or subscript, however its metrics place it.
            if !(hasDropCap && range.location == 0),
               attributes[GlyphIdentityReader.isolatedAttribute] == nil,
               offset.isFinite, abs(offset) <= (font?.pointSize ?? 12) * 0.75 {
                if offset > tolerance { style.insert(.superscript) }
                else if offset < -tolerance { style.insert(.subscript) }
            }
            runs.append(.text(run, style))
        }
        return InlineText(elements: runs).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
