import Foundation
import PDFKit
import AppKit
// usage: survey-lines <pdf> [first-page last-page]
// stdout TSV, one row per native line: page, line index, the product NativeTextReader text (with
// the pipeline's styled gate, so NativeSpacingReader repairs are included), the raw PDFKit
// selection string with U+00A6 inserted at every attributed-run boundary where the font name, the
// point size or the baseline offset changes, and the runs' fonts (name/size/baseline, `;`-joined).
// The marked column is empty when the gate disables styled extraction.
func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
}
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let first = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[2])! : 1
let last = CommandLine.arguments.count > 3 ? min(Int(CommandLine.arguments[3])!, doc.pageCount) : doc.pageCount
var out = FileHandle.standardOutput
for n in first...last {
    autoreleasepool {
        guard let page = doc.page(at: n - 1), let ref = page.pageRef else { return }
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(ref)
        let requires = g.unsupported || page.rotation % 360 != 0
        let synthetic = g.hasOnlyInvisibleText && g.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 }
        let styled = !requires && !synthetic
        let lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: styled)) ?? []
        var marked: [(String, String)] = []
        if let selection = page.selection(for: bounds) {
            for line in selection.selectionsByLine() {
                guard let raw = line.string else { continue }
                let semantic = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
                guard !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let lb = line.bounds(for: page)
                guard lb.isFinite, !lb.isNull, lb.width > 0, lb.height > 0 else { continue }
                guard styled, let attributed = line.attributedString, attributed.string == raw else { marked.append(("", "")); continue }
                var text = "", fonts: [String] = [], previous: String?
                attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                    let font = attrs[.font] as? NSFont
                    let traits = font?.fontDescriptor.symbolicTraits ?? []
                    let key = "\(font?.fontName ?? "?")\(traits.contains(.bold) ? "+b" : "")\(traits.contains(.italic) ? "+i" : "")/\(String(format: "%.1f", font?.pointSize ?? 0))/\((attrs[.baselineOffset] as? NSNumber)?.doubleValue ?? 0)"
                    if let previous, previous != key { text += "\u{00A6}" }
                    if previous != key { fonts.append(key) }
                    previous = key
                    text += (attributed.string as NSString).substring(with: range)
                }
                marked.append((text, fonts.joined(separator: ";")))
            }
        }
        var buffer = ""
        for (index, line) in lines.enumerated() {
            let m = marked.count == lines.count ? marked[index] : ("#misaligned", "")
            buffer += "\(n)\t\(index)\t\(escaped(line.text))\t\(escaped(m.0))\t\(m.1)\n"
        }
        out.write(buffer.data(using: .utf8)!)
    }
}
