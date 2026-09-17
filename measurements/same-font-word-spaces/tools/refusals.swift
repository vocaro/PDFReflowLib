import Foundation
import PDFKit
import AppKit
// usage: refusals <pdf> <first-page> <last-page>
// For every PDFKit line whose shows carry a same-font word space or note boundary that the line
// lacks, prints why NativeSpacingReader.apply leaves it: page, reason, native text, source text.
// Reasons: `owner` (a show's origin lies in no or several line rectangles), `spelling` (the shows
// do not spell the line apart from its spaces), `repaired`.
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let first = Int(CommandLine.arguments[2])!, last = min(Int(CommandLine.arguments[3])!, doc.pageCount)
func escaped(_ value: String) -> String { value.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") }
for n in first...last {
    autoreleasepool {
        guard let page = doc.page(at: n - 1), let ref = page.pageRef,
              let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
        let evidence = NativeSpacingReader.read(ref)
        let lines = selection.selectionsByLine()
        let bounds = lines.map { $0.bounds(for: page) }
        for (index, line) in lines.enumerated() {
            guard let attributed = line.attributedString, !attributed.string.isEmpty else { continue }
            let matches = evidence.filter { bounds[index].insetBy(dx: -0.75, dy: -0.75).contains($0.origin) }
            let sorted = matches.sorted { $0.origin.x < $1.origin.x }
            var noted = false
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                if let end = a.end, NativeSpacingReader.noteReference(a, before: b, end: end) { noted = true }
            }
            guard noted || matches.contains(where: { !$0.wordSpaces.isEmpty }) else { continue }
            let owned = matches.allSatisfy { m in bounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(m.origin) }.count == 1 }
            let source = sorted.map { $0.unicode ?? "<nil>" }.joined(separator: "¦")
            let repaired = NativeSpacingReader.apply(evidence, to: attributed, bounds: bounds[index], allBounds: bounds)
            let reason = repaired.string != attributed.string ? "repaired"
                : !owned ? "owner" : NativeSpacingReader.missingSpaces(in: attributed.string, shows: matches) == nil ? "spelling" : "unchanged"
            print("\(n)\t\(reason)\t\(escaped(attributed.string))\t\(escaped(source))")
        }
    }
}
