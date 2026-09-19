import Foundation
import CryptoKit
import PDFKit
import Vision

// Captures Vision extraction, never reconstructed output. Run from the repository root.
@main struct CaptureOCRLayoutFixture {
    static func main() async throws {
        guard CommandLine.arguments.count == 4,
              let number = Int(CommandLine.arguments[2]), number > 0 else {
            fatalError("usage: capture-ocr-layout-fixture <corpus-case-id> <physical-page> <output.json>")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        guard let item = (manifest["documents"] as! [[String: Any]]).first(where: {
            $0["id"] as? String == CommandLine.arguments[1]
        }), let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + file)
        let digest = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source), let page = document.page(at: number - 1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let result = try await OCRReader.read(page: page, options: ConversionOptions())
        let raster = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox), options: ConversionOptions())
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "en")]
        let observations = try await request.perform(on: raster, orientation: nil)
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        let payload: [String: Any] = [
            "caseID": item["id"]!, "sourceSHA256": digest, "page": number,
            "sourceTitle": item["title"]!, "extraction": "Vision RecognizeDocumentsRequest, default ConversionOptions",
            "bounds": rect(page.bounds(for: .cropBox)), "graphics": result.tables.map(rect),
            "lines": result.lines.map { ["text": $0.text, "rect": rect($0.rect),
                "fontSize": $0.fontSize, "monospaced": $0.monospaced,
                "wraps": $0.wraps ?? false] as [String: Any] }, "attributedLines": [],
            "quadrilaterals": observations.first?.document.text.lines.map { line in
                ["text": line.transcript, "isTitle": line.isTitle,
                 "points": [line.topLeft, line.topRight, line.bottomRight, line.bottomLeft].map { [$0.x, $0.y] }]
            } ?? [],
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    }
}
