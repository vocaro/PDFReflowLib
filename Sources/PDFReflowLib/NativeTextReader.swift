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
        return try operation()
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
        var result: [TextLine] = []
        for line in selections {
            try Task.checkCancellation()
            guard let raw = line.string else { continue }
            // U+FFFC names an attachment, not a word. Retain a boundary between adjacent
            // words; the graphics reader preserves the object's visible content separately.
            let semantic = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
            guard !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let bounds = line.bounds(for: page)
            guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { continue }
            // Object-only selections were discarded before requesting attributed text,
            // which can make PDFKit decode large image attachments.
            let attributed = includeStyle ? line.attributedString : nil
            let repaired = attributed.map {
                $0.string == raw ? NativeSpacingReader.apply(spacing, to: $0, bounds: bounds, allBounds: boundsByLine) : $0
            }
            let corrected = repaired?.string != attributed?.string
                ? repaired?.string.replacingOccurrences(of: "\u{FFFC}", with: " ") : nil
            result.append(textLine(semantic: corrected ?? semantic,
                                   bounds: bounds, attributed: repaired))
        }
        return result
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
        } else if !mono, styled != nil, let attributed, let titleSize = displayNumeralTitleSize(in: attributed) {
            // The line's typography is the title's; the numeral is its ornament (#55).
            result.fontSize = titleSize
        }
        return result
    }

    /// A chapter opener's display numeral fused by PDFKit with the title beside it (The Fed
    /// Explained's 70-point `1` before the 24-point `Overview of the Federal`): a run of one to
    /// three digits at least twice the size of the title run that follows on the line. The
    /// title's size is the line's size for heading evidence; the numeral's own size would rank
    /// the line above its second line and above every other title (#55).
    static func displayNumeralTitleSize(in attributed: NSAttributedString) -> CGFloat? {
        guard attributed.length > 0 else { return nil }
        var initialRange = NSRange()
        let initial = attributed.attributes(at: 0, effectiveRange: &initialRange)
        let numeral = (attributed.string as NSString).substring(with: initialRange)
            .trimmingCharacters(in: .whitespaces)
        guard (1...3).contains(numeral.count), numeral.allSatisfy(\.isNumber),
              initialRange.length < attributed.length, let cap = initial[.font] as? PlatformFont else { return nil }
        let rest = NSRange(location: initialRange.length, length: attributed.length - initialRange.length)
        let title = (attributed.string as NSString).substring(with: rest)
        guard title.filter(\.isLetter).count >= 2, !title.contains("\n"), !title.contains("\r"),
              let font = attributed.attributes(at: rest.location, effectiveRange: nil)[.font] as? PlatformFont else { return nil }
        let size = font.pointSize
        guard size.isFinite, size > 0, cap.pointSize.isFinite, cap.pointSize <= 100_000,
              cap.pointSize >= size * 2 else { return nil }
        var consistent = true
        attributed.enumerateAttributes(in: rest) { attributes, _, _ in
            guard let font = attributes[.font] as? PlatformFont, font.pointSize.isFinite,
                  abs(font.pointSize - size) <= size * 0.1 else { consistent = false; return }
        }
        return consistent ? size : nil
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

    private struct StyledRun {
        var text: String
        var style: TextStyle
        var offset: Double
        var size: Double
        var hasFont: Bool
        var first: Bool
    }

    static func inlineText(from attributed: NSAttributedString) -> InlineText {
        let hasDropCap = dropCapBodySize(in: attributed) != nil
        var styled: [StyledRun] = []
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
            styled.append(StyledRun(text: run, style: style, offset: offset, size: Double(font?.pointSize ?? 12),
                                    hasFont: font != nil, first: range.location == 0))
        }
        var runs: [InlineText.Element] = []
        for (index, run) in styled.enumerated() {
            var style = run.style
            let measured = run.hasFont && run.size.isFinite && run.size > 0 && run.offset.isFinite
            let previous = index > 0 ? styled[index - 1] : nil
            let next = index + 1 < styled.count ? styled[index + 1] : nil
            // A run at least twice the size of every run beside it is display type (a chapter
            // opener's numeral, a drop cap), never a script of the smaller text (#55).
            let neighbours = [previous, next].compactMap { $0 }.filter(\.hasFont).map(\.size)
            let display = measured && !neighbours.isEmpty && neighbours.allSatisfy { run.size >= $0 * 2 }
            if let previous, measured, previous.hasFont, previous.size.isFinite, previous.size > 0, previous.offset.isFinite,
               let last = previous.text.last, let first = run.text.first,
               !last.isWhitespace, !first.isWhitespace, last != "-", last != "\u{00ad}" {
                // PDFKit can concatenate separate visual lines without a space while retaining
                // their full-line baseline offsets. Require matching font sizes and a jump beyond
                // the inline-script range; opposite superscripts/subscripts alone are not evidence.
                let lines = abs(run.size - previous.size) <= max(0.5, max(run.size, previous.size) * 0.1)
                    && abs(run.offset - previous.offset) > max(run.size, previous.size) * 0.75
                    && (abs(run.offset) > run.size * 0.75 || abs(previous.offset) > previous.size * 0.75)
                // A display numeral set on its own baseline before a title (`1` then `Overview`)
                // is a separate word; a raised or lowered script marker beside its base is not.
                let numeral = previous.text.allSatisfy(\.isNumber) && previous.size >= run.size * 2
                    && abs(previous.offset - run.offset) > run.size * 0.75 && first.isLetter
                if lines || numeral { runs.append(.text(" ", [])) }
            }
            let tolerance = max(0.5, run.size * 0.12)
            // Some PDFKit selections combine several OCR lines, represented as baseline
            // shifts of a full line height. Those are layout offsets, not inline scripts.
            if !(hasDropCap && run.first), !display, run.offset.isFinite, abs(run.offset) <= run.size * 0.75 {
                if run.offset > tolerance { style.insert(.superscript) }
                else if run.offset < -tolerance { style.insert(.subscript) }
            }
            runs.append(.text(run.text, style))
        }
        return InlineText(elements: runs).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
