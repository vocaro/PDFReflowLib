import Foundation
import PDFKit
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
                var runs: [InlineText.Element] = []
                attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                    let name = (value as? PlatformFont)?.fontName.lowercased() ?? ""
                    let run = (attributed.string as NSString).substring(with: range)
                        .replacingOccurrences(of: "\u{FFFC}", with: " ")
                    var style: TextStyle = []
                    if name.contains("italic") || name.contains("oblique") { style.insert(.italic) }
                    if name.contains("bold") { style.insert(.bold) }
                    runs.append(.text(run, style))
                }
                styled = InlineText(elements: runs).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Keep each selection's own text with its geometry. PDFKit's characterBounds offsets
            // need not agree with string offsets at synthesized newlines on current OS builds.
            result.append(TextLine(content: styled ?? InlineText(text), rect: bounds,
                fontSize: size, monospaced: mono))
        }
        return result
    }
}
