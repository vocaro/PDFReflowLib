import Foundation
import CryptoKit
import PDFKit
import AppKit

// Survey-only instrumentation for #180 item 3. Run from the repository root; writes one TSV row
// per PDFKit line:
//
//   page  line  minX  maxX  minY  maxY  size  trailingSpace  text
//
// `trailingSpace` is whether the selection's own string ends in whitespace before extraction trims
// it. Row pairs are read from the rectangles in Python.
@main struct SurveyRowSpaces {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { fatalError("usage: survey-row-spaces <corpus-case-id>") }
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let cases = manifest["documents"] as! [[String: Any]]
        guard let item = cases.first(where: { $0["id"] as? String == arguments[1] }),
              let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + file)
        let data = try Data(contentsOf: source)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        let out = FileHandle.standardOutput
        func emit(_ line: String) { out.write(Data((line + "\n").utf8)) }
        emit("page\tline\tminX\tmaxX\tminY\tmaxY\tsize\ttrailing\ttext")
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index),
                      let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
                for (order, piece) in selection.selectionsByLine().enumerated() {
                    guard let raw = piece.string else { continue }
                    let semantic = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
                    guard !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let bounds = piece.bounds(for: page)
                    guard !bounds.isNull, bounds.width > 0, bounds.height > 0, bounds.minX.isFinite, bounds.maxX.isFinite else { continue }
                    let size = (piece.attributedString?.length ?? 0) > 0
                        ? (piece.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
                        : nil
                    let trailing = semantic.last?.isWhitespace == true
                    let text = semantic.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\t", with: " ")
                    emit("\(index + 1)\t\(order)\t\(bounds.minX)\t\(bounds.maxX)\t\(bounds.minY)\t\(bounds.maxY)\t"
                        + "\(size ?? bounds.height)\t\(trailing)\t\(String(text.prefix(110)))")
                }
            }
        }
    }
}
