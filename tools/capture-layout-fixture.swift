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
        // `--keep-overprints` writes PDFKit's lines as they come, before extraction drops a line
        // that only overprints another (#165), so a fixture can carry the duplicates a source
        // draws twice in one place.
        let keepOverprints = CommandLine.arguments.contains("--keep-overprints")
        let arguments = CommandLine.arguments.filter { $0 != "--keep-overprints" }
        guard arguments.count == 4, let pageNumber = Int(arguments[2]), pageNumber > 0 else {
            fatalError("usage: capture-layout-fixture <corpus-case-id> <physical-page> <output.json> [--keep-overprints]")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let cases = manifest["documents"] as! [[String: Any]]
        guard let item = cases.first(where: { $0["id"] as? String == arguments[1] }),
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
        // `graphics` are the clustered regions every fixture carries; `paints` are the
        // unclustered footprints with their frame flag, from which tests compose graphics.
        let graphics = GraphicsReader.read(reference)
        // Lines as the pipeline extracts them: cells merged across a ruled grid's column joints
        // (#65) or a borderless table's column gap (#121) are split.
        var lines = try NativeTextReader.lines(on: page, limit: 100_000,
            columnJoints: GraphicsReader.columnJoints(graphics.paints.map(\.rect)),
            borderlessTableInk: graphics.paints.map(\.rect), removingOverprints: !keepOverprints)
        // The tags the pipeline applies where the page's structure validates: every group that
        // matches its lines, even when another does not (`structure` per line; absent in fixtures
        // captured before #89/#90).
        var tagged = false
        if let index = try? StructureTreeReader.read(source), let tags = index.pages[pageNumber], !tags.isEmpty,
           StructureTreeReader.validates(tags, owners: index.owners[pageNumber] ?? [:], page: reference) {
            _ = MarkedTextReader.apply(tags, page: reference, lines: &lines)
            tagged = true
        }
        var attributedLines: [[String: Any]] = []
        // Runs drawn in a bold font resource PDFKit does not name bold carry `bold` (#125), and runs
        // drawn in an italic text font resource carry `italic` (#133); runs drawn in a maths
        // italic font resource carry `mathItalic` (#142). Fixtures captured before each carry no
        // such field.
        let selections = page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? []
        let weights = FontWeightReader.read(reference)
        // Symbol fonts' private-use characters are decoded as the pipeline decodes them (#155).
        let privateUse = PrivateUseDecoder.characters(on: reference)
        let selectionBounds = selections.map { $0.bounds(for: page) }
        for (selection, lineBounds) in zip(selections, selectionBounds) {
            guard let native = selection.attributedString else { continue }
            let attributed = PrivateUseDecoder.decode(
                FontWeightReader.apply(weights, to: native, bounds: lineBounds, allBounds: selectionBounds), privateUse)
            var runs: [[String: Any]] = []
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                let font = attrs[.font] as? CaptureFont
                let baseline = attrs[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
                    ?? attrs[.baselineOffset] as? NSNumber
                var run: [String: Any] = ["text": (attributed.string as NSString).substring(with: range),
                    "fontName": font?.fontName ?? "", "fontSize": font?.pointSize ?? 0,
                    "baselineOffset": baseline?.doubleValue ?? 0]
                if attrs[FontWeightReader.boldAttribute] != nil { run["bold"] = true }
                if attrs[FontWeightReader.italicAttribute] != nil { run["italic"] = true }
                if attrs[FontWeightReader.mathItalicAttribute] != nil { run["mathItalic"] = true }
                runs.append(run)
            }
            // A selection over figure text can report infinite bounds (FAA page 474), which JSON cannot hold.
            var entry: [String: Any] = ["text": attributed.string, "runs": runs]
            let bounds = selection.bounds(for: page)
            if bounds.isFinite { entry["rect"] = rect(bounds) }
            attributedLines.append(entry)
        }
        let payload: [String: Any] = [
            "caseID": item["id"]!, "sourceSHA256": digest, "page": pageNumber,
            "sourceURL": item["downloadURL"] ?? item["url"] ?? "", "sourceTitle": item["title"]!,
            "rightsBasis": item["rightsBasis"] ?? "See corpus manifest and third-party notices.",
            "bounds": rect(page.bounds(for: .cropBox)), "graphics": graphics.regions.map(rect),
            "paints": graphics.paints.map { ["rect": rect($0.rect), "frame": $0.frame, "image": $0.image, "filled": $0.filled,
                                             "grouped": $0.grouped] as [String: Any] },
            "lines": lines.map { line -> [String: Any] in
                var entry: [String: Any] = ["text": line.text, "rect": rect(line.rect), "fontSize": line.fontSize,
                                            "monospaced": line.monospaced]
                if tagged, let tag = line.structure {
                    entry["structure"] = ["group": tag.group, "order": tag.order, "headingLevel": tag.headingLevel,
                                          "lineCount": tag.lineCount, "opensWithSplitMarker": tag.opensWithSplitMarker]
                }
                return entry
            }, "attributedLines": attributedLines,
        ]
        // JSON holds no infinity or NaN; name the element rather than abort inside the writer (#99).
        func nonFinite(_ value: Any, _ path: String) -> String? {
            switch value {
            case let number as Double: number.isFinite ? nil : "\(path) = \(number)"
            case let number as CGFloat: number.isFinite ? nil : "\(path) = \(number)"
            case let array as [Any]: array.indices.lazy.compactMap { nonFinite(array[$0], "\(path)[\($0)]") }.first
            case let object as [String: Any]: object.keys.sorted().lazy.compactMap { nonFinite(object[$0]!, "\(path).\($0)") }.first
            default: nil
            }
        }
        if let problem = nonFinite(payload, "fixture") {
            fatalError("Non-finite geometry cannot be captured: \(problem)")
        }
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: arguments[3]))
    }
}
