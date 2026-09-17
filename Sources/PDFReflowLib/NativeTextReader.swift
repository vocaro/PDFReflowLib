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

    static func lines(on page: PDFPage, limit: Int, includeStyle: Bool = true,
                      columnJoints: [ColumnJoint] = []) throws -> [TextLine] {
        try withExtractionLock {
            let lines = try extractLines(on: page, limit: limit, includeStyle: includeStyle)
            return try columnJoints.isEmpty ? lines : splitAtColumnJoints(lines, joints: columnJoints, on: page, includeStyle: includeStyle)
        }
    }

    /// The joints a line crosses inside a ruled grid: its middle lies within the joint's rows
    /// and it reaches more than one em past the joint on both sides.
    static func crossedJoints(_ line: TextLine, _ joints: [ColumnJoint]) -> [CGFloat] {
        let em = max(4, line.fontSize)
        return joints.filter { joint in
            line.rect.midY > joint.minY && line.rect.midY < joint.maxY
                && line.rect.minX < joint.x - em && line.rect.maxX > joint.x + em
        }.map(\.x)
    }

    /// PDFKit returns a ruled table's cells on one baseline as one line ("Tool Definition In
    /// practice", Fed page 46). A line crossing a column joint of the rule grid is split there
    /// when the joint falls in whitespace between the glyphs on either side and those glyphs
    /// stand at least one em apart, measured with PDFKit's own rectangle selections; prose
    /// crossing the joint (a caption, a title) has only word spaces and stays whole. The pieces
    /// must spell the line exactly, apart from the whitespace at the cut, or the line is kept
    /// (#65).
    private static func splitAtColumnJoints(_ lines: [TextLine], joints: [ColumnJoint],
                                            on page: PDFPage, includeStyle: Bool) throws -> [TextLine] {
        func squeezed(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func selection(_ rect: CGRect, from minX: CGFloat, to maxX: CGFloat) -> PDFSelection? {
            guard maxX > minX else { return nil }
            return page.selection(for: CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height))
        }
        func visible(_ selection: PDFSelection?) -> String {
            squeezed(selection?.string?.replacingOccurrences(of: "\u{FFFC}", with: " ") ?? "")
        }
        func piece(_ rect: CGRect, from minX: CGFloat, to maxX: CGFloat) -> TextLine? {
            // A space glyph stretches across the gap; shrink both edges of the selection until
            // it holds the piece's own characters only.
            let target = visible(selection(rect, from: minX, to: maxX))
            guard !target.isEmpty else { return nil }
            var low = minX, high = maxX
            for _ in 0..<14 {
                let middle = (low + high) / 2
                if visible(selection(rect, from: minX, to: middle)) == target { high = middle } else { low = middle }
            }
            var left = minX
            low = minX
            var top = high
            for _ in 0..<14 {
                let middle = (low + top) / 2
                if visible(selection(rect, from: middle, to: high)) == target { left = middle; low = middle } else { top = middle }
            }
            guard let chosen = selection(rect, from: left, to: high), visible(chosen) == target,
                  let raw = chosen.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            let bounds = chosen.bounds(for: page)
            guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
            let attributed = includeStyle ? chosen.attributedString : nil
            return textLine(semantic: raw.replacingOccurrences(of: "\u{FFFC}", with: " "), bounds: bounds, attributed: attributed)
        }
        var result: [TextLine] = []
        for line in lines {
            try Task.checkCancellation()
            let crossed = crossedJoints(line, joints)
            guard !crossed.isEmpty, !line.monospaced else { result.append(line); continue }
            let rect = line.rect
            let em = max(4, line.fontSize)
            // A cut is real when the joint falls between words and the glyphs on either side of
            // it stand at least one em apart.
            let cuts = crossed.filter { x in
                guard let left = piece(rect, from: rect.minX, to: x), let right = piece(rect, from: x, to: rect.maxX) else { return false }
                return squeezed(left.text + " " + right.text) == squeezed(line.text)
                    && right.rect.minX - left.rect.maxX >= em
                    && left.rect.maxX <= x + 1 && right.rect.minX >= x - 1
            }
            let edges = [rect.minX] + cuts + [rect.maxX]
            var pieces: [TextLine] = []
            for (start, end) in zip(edges, edges.dropFirst()) {
                guard let next = piece(rect, from: start, to: end) else { pieces = []; break }
                pieces.append(next)
            }
            guard pieces.count >= 2, squeezed(pieces.map(\.text).joined(separator: " ")) == squeezed(line.text) else {
                result.append(line); continue
            }
            result += pieces
        }
        return result
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
