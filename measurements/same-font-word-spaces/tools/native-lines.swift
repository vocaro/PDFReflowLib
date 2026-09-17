import Foundation
import PDFKit
// usage: native-lines <pdf> <page>...
// JSON {"<page>": [{"text": PDFKit line attributed string, "rect": [x, y, w, h]}]} for every
// selectionsByLine line whose attributed string equals its plain string, the lines
// NativeTextReader hands to NativeSpacingReader.apply.
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
var result: [String: [[String: Any]]] = [:]
for argument in CommandLine.arguments.dropFirst(2) {
    let number = Int(argument)!
    guard let page = doc.page(at: number - 1), let selection = page.selection(for: page.bounds(for: .cropBox)) else { continue }
    var lines: [[String: Any]] = []
    for line in selection.selectionsByLine() {
        guard let raw = line.string, let attributed = line.attributedString, attributed.string == raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let b = line.bounds(for: page)
        lines.append(["text": raw, "rect": [b.minX, b.minY, b.width, b.height].map { ($0 * 10_000).rounded() / 10_000 }])
    }
    result[argument] = lines
}
let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
