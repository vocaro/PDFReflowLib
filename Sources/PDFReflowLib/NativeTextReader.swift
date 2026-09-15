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
    static func lines(on page: PDFPage, limit: Int, includeStyle: Bool = true) throws -> [TextLine] {
        guard page.numberOfCharacters <= limit else {
            throw ConversionError.resourceLimit("too many characters")
        }
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        var result: [TextLine] = []
        for line in selection.selectionsByLine() {
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
            result.append(TextLine(content: styled ?? InlineText(text), rect: bounds,
                fontSize: size, monospaced: mono))
        }
        return result
    }

    static func inlineText(from attributed: NSAttributedString) -> InlineText {
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
            if offset.isFinite, abs(offset) <= (font?.pointSize ?? 12) * 0.75 {
                if offset > tolerance { style.insert(.superscript) }
                else if offset < -tolerance { style.insert(.subscript) }
            }
            runs.append(.text(run, style))
        }
        return InlineText(elements: runs).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
