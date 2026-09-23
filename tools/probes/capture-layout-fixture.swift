import Foundation
import CryptoKit
import CoreText
import PDFKit
#if os(macOS)
import AppKit
private typealias CaptureFont = NSFont
#else
import UIKit
private typealias CaptureFont = UIFont
#endif

// Run from the repository root. Captures extraction evidence, never reconstructed output.
@main struct CaptureLayoutFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 4, let pageNumber = Int(CommandLine.arguments[2]), pageNumber > 0 else {
            fatalError("usage: capture-layout-fixture <corpus-case-id> <physical-page> <output.json>")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let cases = manifest["documents"] as! [[String: Any]]
        guard let item = cases.first(where: { $0["id"] as? String == CommandLine.arguments[1] }),
              let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + file)
        let data = try Data(contentsOf: source)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source), let page = document.page(at: pageNumber - 1),
              let reference = page.pageRef else { throw CocoaError(.fileReadCorruptFile) }
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        let lines = try NativeTextReader.lines(on: page, limit: 100_000)
        let graphics = GraphicsReader.read(reference)
        var attributedLines: [[String: Any]] = []
        for selection in page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [] {
            guard let attributed = selection.attributedString else { continue }
            var runs: [[String: Any]] = []
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                let font = attrs[.font] as? CaptureFont
                let baseline = attrs[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
                    ?? attrs[.baselineOffset] as? NSNumber
                runs.append(["text": (attributed.string as NSString).substring(with: range),
                    "fontName": font?.fontName ?? "", "fontSize": font?.pointSize ?? 0,
                    "baselineOffset": baseline?.doubleValue ?? 0])
            }
            attributedLines.append(["text": attributed.string, "rect": rect(selection.bounds(for: page)), "runs": runs])
        }
        let payload: [String: Any] = [
            "schemaVersion": 3,
            "caseID": item["id"]!, "sourceSHA256": digest, "page": pageNumber,
            "sourceURL": item["downloadURL"] ?? item["url"] ?? "", "sourceTitle": item["title"]!,
            "rightsBasis": item["rightsBasis"] ?? "See corpus manifest and third-party notices.",
            "bounds": rect(page.bounds(for: .cropBox)), "graphics": graphics.regions.map(rect),
            // The placed raster image XObjects among the regions, which crop ownership reads
            // (#176, #239, #207). Captures before schema version 2 carry none.
            "pictures": graphics.images.map(rect),
            "paintOperations": try JSONSerialization.jsonObject(with: JSONEncoder().encode(graphics.paints)),
            "lines": lines.map { ["text": $0.text, "rect": rect($0.rect), "fontSize": $0.fontSize,
                "monospaced": $0.monospaced] as [String: Any] }, "attributedLines": attributedLines,
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    }
}
