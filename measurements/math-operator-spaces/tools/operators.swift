import AppKit
import Foundation
import PDFKit

// usage: operators <pdf> [first last]
// Build with `missing-spaces-survey/tools/build.sh`'s file list plus this file instead of its main.swift
// (see `survey.sh`). For every PDFKit line whose shows the spacing reader owns alone (the ownership
// rule of `NativeSpacingReader.apply`), one TSV row per glyph boundary beside a mathematical operator:
//
//   page, line, kind (in | cross), left, right, gapEm, pdfkitSpace (1 | 0), spells (1 | 0), decision, line text
//
// `in` is a TJ adjustment inside one show (`Evidence.operatorGaps`); `cross` is the gap from one
// show's measured end to the next show's origin on the same baseline. `pdfkitSpace` says whether
// PDFKit's text has whitespace at the boundary; `spells` whether the line's shows spell PDFKit's text
// apart from its own whitespace (the exact-line rule every repair needs); `decision` is
// `NativeSpacingReader.operatorSpace` (1 when the reader would set a space there).
func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
}

struct Boundary { var offset: Int; var kind: String; var left: Unicode.Scalar; var right: Unicode.Scalar; var gap: CGFloat }

let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let first = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[2])! : 1
let last = CommandLine.arguments.count > 3 ? min(Int(CommandLine.arguments[3])!, document.pageCount) : document.pageCount
let out = FileHandle.standardOutput
for number in first...last {
    autoreleasepool {
        guard let page = document.page(at: number - 1), let reference = page.pageRef,
              let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
        let shows = NativeSpacingReader.read(reference)
        guard !shows.isEmpty else { return }
        let lines = selection.selectionsByLine().compactMap { line -> (String, CGRect)? in
            guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let bounds = line.bounds(for: page)
            return bounds.isFinite && !bounds.isNull && bounds.width > 0 && bounds.height > 0 ? (text, bounds) : nil
        }
        let allBounds = lines.map(\.1)
        var buffer = ""
        for (index, (native, bounds)) in lines.enumerated() {
            let owned = shows.filter { bounds.insetBy(dx: -0.75, dy: -0.75).contains($0.origin) }
            guard !owned.isEmpty, owned.allSatisfy({ show in
                allBounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(show.origin) }.count == 1
            }) else { continue }
            var source: [UInt16] = [], found: [Boundary] = [], previous: NativeSpacingReader.Evidence?, readable = true
            for show in owned.sorted(by: { $0.origin.x < $1.origin.x }) {
                guard let unicode = show.unicode, !unicode.isEmpty else { readable = false; break }
                let scalars = unicode.unicodeScalars
                for (offset, gap) in show.operatorGaps where offset > 0 && offset < unicode.utf16.count {
                    let at = String.Index(utf16Offset: offset, in: unicode)
                    if let before = scalars.index(at, offsetBy: -1, limitedBy: scalars.startIndex) {
                        found.append(Boundary(offset: source.count + offset, kind: "in", left: scalars[before], right: scalars[at], gap: gap))
                    }
                }
                if let previous, let end = previous.end, let left = previous.unicode?.unicodeScalars.last, let right = scalars.first,
                   abs(previous.origin.y - show.origin.y) <= max(previous.size, show.size) * 0.1,
                   NativeSpacingReader.mathOperators.contains(left) || NativeSpacingReader.mathOperators.contains(right) {
                    found.append(Boundary(offset: source.count, kind: "cross", left: left, right: right,
                                          gap: (show.origin.x - end) / max(previous.size, show.size)))
                }
                source += unicode.utf16
                previous = show
            }
            guard readable, !found.isEmpty else { continue }
            // Align the shows' text with PDFKit's, skipping PDFKit's whitespace, as `missingSpaces` does.
            let extracted = Array(native.utf16)
            func whitespace(_ value: UInt16) -> Bool { UnicodeScalar(value).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false }
            var i = 0, j = 0, spacedAt: [Int: Bool] = [:], spells = true
            while i < source.count, j < extracted.count {
                if source[i] == extracted[j] { spacedAt[i] = j > 0 && whitespace(extracted[j - 1]); i += 1; j += 1 }
                else if whitespace(extracted[j]) { j += 1 }
                else { spells = false; break }
            }
            while j < extracted.count, whitespace(extracted[j]) { j += 1 }
            while i < source.count, j == extracted.count, whitespace(source[i]) { i += 1 }
            if i != source.count || j != extracted.count { spells = false }
            for boundary in found {
                let spaced = spacedAt[boundary.offset].map { $0 ? "1" : "0" } ?? "?"
                let decision = NativeSpacingReader.operatorSpace(left: boundary.left, right: boundary.right, gap: boundary.gap) ? "1" : "0"
                buffer += "\(number)\t\(index)\t\(boundary.kind)\t\(boundary.left)\t\(boundary.right)\t"
                    + String(format: "%.4f", boundary.gap) + "\t\(spaced)\t\(spells ? 1 : 0)\t\(decision)\t\(escaped(native))\n"
            }
        }
        out.write(buffer.data(using: .utf8)!)
    }
}
