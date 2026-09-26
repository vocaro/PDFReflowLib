import CoreGraphics
import CoreText
import Foundation
#if os(macOS)
import AppKit
private typealias ReferenceFont = NSFont
#else
import UIKit
private typealias ReferenceFont = UIFont
#endif

/// A PDFKit line measured from the baseline of smaller text beside it, measured from its own
/// baseline instead (#308).
///
/// PDFKit gathers a printed row into one line, states every run's baseline offset from one
/// reference, and can then hand the row over as several pieces, each carrying the whole row's
/// vertical extent. Wallace page 210 prints `1)` and beside it an inline fraction whose numerator
/// stands 6.24 points higher: PDFKit takes the numerator's baseline as the row's reference, and
/// hands the number over alone, `1) ` at 11.96 points and −6.24, with a rectangle exactly as tall
/// as the numerator's piece beside it. Read alone, the number is a lowered script. But a script is
/// set smaller than the text it is set against, and the only text on this reference is the 7.97-
/// point numerator: the number stands on its own baseline, which is the row's.
///
/// A line is measured from its own baseline when all of these hold:
/// - **It stands whole off its reference.** Every glyph run is within max(0.5, 10%) of the line's
///   largest size and within max(0.5, 12% of that size) of one offset, which lies beyond that
///   tolerance and within 75% of the size, where `NativeTextReader.inlineText` would read a
///   script. Nothing in the line shows where its baseline is, so the evidence is beside it.
/// - **A piece of the same PDFKit line stands beside it.** Another line has the same vertical
///   extent, within 0.05 points, and starts within one em of the line's size after its end or
///   ends within one em before its start.
/// - **The text on the reference is smaller.** Those pieces set glyphs on PDFKit's reference
///   (within max(0.5, 12%) of their own size of it), and every such run is at most 90% of the
///   line's size, which is as large as a script may be against it.
/// - **Nothing beside it is larger, or on another baseline at its size.** No glyph run in those
///   pieces is larger than the line's size (beyond max(0.5, 10%)), and every run over 90% of it
///   stands on the line's own offset: page 21's `21)` beside `6·` on its baseline and the
///   numerator over it.
///
/// A script PDFKit splits from its row (#303) is measured from the larger text it is set
/// against, and a note number or a chemical formula's subscript is smaller than the words beside
/// it, so none of them is moved. A line holding right-to-left letters or an attachment takes no
/// part.
enum BorrowedLineReference {
    typealias Item = (semantic: String, bounds: CGRect, attributed: NSAttributedString?)

    private static let baselineKey = NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)

    private struct Run {
        let size: Double
        let offset: Double
    }

    static func rebased(_ items: [Item]) -> [Item] {
        guard items.count > 1 else { return items }
        let runs = items.map(glyphRuns)
        var result = items
        for index in items.indices {
            guard let own = runs[index], let size = own.map(\.size).max(), let offset = own.first?.offset,
                  let attributed = items[index].attributed else { continue }
            let tolerance = max(0.5, size * 0.12)
            guard own.allSatisfy({ abs($0.size - size) <= max(0.5, size * 0.1) && abs($0.offset - offset) <= tolerance }),
                  abs(offset) > tolerance, abs(offset) <= size * 0.75 else { continue }
            let bounds = items[index].bounds
            let pieces = items.indices.filter { other in
                guard other != index else { return false }
                let rect = items[other].bounds
                guard abs(rect.minY - bounds.minY) <= 0.05, abs(rect.maxY - bounds.maxY) <= 0.05 else { return false }
                let after = Double(rect.minX) >= Double(bounds.maxX) - 0.5 && Double(rect.minX) <= Double(bounds.maxX) + size
                let before = Double(rect.maxX) <= Double(bounds.minX) + 0.5 && Double(rect.maxX) >= Double(bounds.minX) - size
                return after || before
            }
            // A piece PDFKit hands over without readable runs could hold anything.
            guard !pieces.isEmpty, pieces.allSatisfy({ runs[$0] != nil }) else { continue }
            let beside = pieces.flatMap { runs[$0] ?? [] }
            let onReference = beside.filter { abs($0.offset) <= max(0.5, $0.size * 0.12) }
            guard !onReference.isEmpty, onReference.allSatisfy({ $0.size <= size * 0.9 }),
                  beside.allSatisfy({ $0.size <= size + max(0.5, size * 0.1) }),
                  beside.allSatisfy({ $0.size <= size * 0.9 || abs($0.offset - offset) <= tolerance })
            else { continue }
            result[index].attributed = shifted(attributed, by: -offset)
        }
        return result
    }

    /// The line's glyph runs, or nil where a run carries no measurable font or the line holds
    /// right-to-left letters, whose shaping moves letters off the baseline (#41), or an attachment.
    private static func glyphRuns(_ item: Item) -> [Run]? {
        guard let attributed = item.attributed, attributed.length > 0,
              !attributed.string.contains("\u{FFFC}"),
              !attributed.string.unicodeScalars.contains(where: ArabicText.isRightToLeftLetter) else { return nil }
        let string = attributed.string as NSString
        var runs: [Run] = []
        var usable = true
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, stop in
            guard string.substring(with: range).contains(where: { !$0.isWhitespace }) else { return }
            let offset = ((attributes[baselineKey] ?? attributes[.baselineOffset]) as? NSNumber)?.doubleValue ?? 0
            guard let font = attributes[.font] as? ReferenceFont, case let size = Double(font.pointSize),
                  size.isFinite, size > 0, size <= 1_000, offset.isFinite, abs(offset) <= 1_000
            else { usable = false; stop.pointee = true; return }
            runs.append(Run(size: size, offset: offset))
        }
        return usable && !runs.isEmpty ? runs : nil
    }

    /// The line with every run's offset moved by `delta`.
    private static func shifted(_ attributed: NSAttributedString, by delta: Double) -> NSAttributedString {
        let moved = NSMutableAttributedString(attributedString: attributed)
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let offset = ((attributes[baselineKey] ?? attributes[.baselineOffset]) as? NSNumber)?.doubleValue ?? 0
            moved.addAttribute(baselineKey, value: NSNumber(value: offset + delta), range: range)
            if attributes[.baselineOffset] != nil {
                moved.addAttribute(.baselineOffset, value: NSNumber(value: offset + delta), range: range)
            }
        }
        return moved
    }
}
