import CryptoKit
import Foundation
import PDFKit
import Vision

// Investigation-only, single-request capture. No reflow output or inferred heading labels.
// Compile with PageRasterizer.swift, ConversionTypes.swift, DocumentModel.swift and ReflowDocument.swift.
@main struct ProbeVisionTitles {
    static func main() async throws {
        guard CommandLine.arguments.count == 4,
              let pageNumber = Int(CommandLine.arguments[2]), pageNumber > 0 else {
            fatalError("usage: probe-vision-titles <corpus-case-id> <physical-page> <output.json>")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        guard let item = (manifest["documents"] as! [[String: Any]]).first(where: {
            $0["id"] as? String == CommandLine.arguments[1]
        }), let filename = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + filename)
        let digest = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let pdf = PDFDocument(url: source), let page = pdf.page(at: pageNumber - 1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let bounds = page.bounds(for: .cropBox)
        let raster = try PageRasterizer.image(page: page, rect: bounds, options: ConversionOptions())
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        let language = Locale.Language(identifier: "en")
        if request.supportedRecognitionLanguages.contains(language) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        let observations = try await request.perform(on: raster, orientation: nil)
        guard let observation = observations.first else { fatalError("No document observation") }
        let root = observation.document
        let rootLines = root.text.lines
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        func line(_ value: RecognizedTextObservation) -> [String: Any] {
            ["text": value.transcript, "uuid": value.uuid.uuidString,
             "isTitle": value.isTitle, "confidence": value.confidence,
             "wraps": value.shouldWrapToNextLine as Any? ?? NSNull(),
             "rect": rect(value.boundingRegion.boundingBox.cgRect),
             "points": [value.topLeft, value.topRight, value.bottomRight, value.bottomLeft].map { [$0.x, $0.y] }]
        }
        func matches(_ value: RecognizedTextObservation) -> [String: Any] {
            var result = line(value)
            result["equalRootIndices"] = rootLines.indices.filter { rootLines[$0] == value }
            result["uuidRootIndices"] = rootLines.indices.filter { rootLines[$0].uuid == value.uuid }
            result["textAndRegionRootIndices"] = rootLines.indices.filter {
                rootLines[$0].transcript == value.transcript && rootLines[$0].boundingRegion == value.boundingRegion
            }
            return result
        }
        var containers: [[String: Any]] = []
        func capture(_ container: DocumentObservation.Container, path: String) {
            var result: [String: Any] = ["path": path,
                "rect": rect(container.boundingRegion.boundingBox.cgRect),
                "lineCount": container.text.lines.count, "title": NSNull()]
            if let title = container.title {
                result["title"] = ["text": title.transcript,
                    "rect": rect(title.boundingRegion.boundingBox.cgRect),
                    "lines": title.lines.map(matches)]
            }
            containers.append(result)
            for (tableIndex, table) in container.tables.enumerated() {
                for (rowIndex, row) in table.rows.enumerated() {
                    for (cellIndex, cell) in row.enumerated() {
                        capture(cell.content, path: "\(path).table[\(tableIndex)].row[\(rowIndex)].cell[\(cellIndex)]")
                    }
                }
            }
            for (listIndex, list) in container.lists.enumerated() {
                for (itemIndex, item) in list.items.enumerated() {
                    capture(item.content, path: "\(path).list[\(listIndex)].item[\(itemIndex)]")
                }
            }
        }
        capture(root, path: "document")
        let payload: [String: Any] = ["schemaVersion": 1, "caseID": item["id"]!,
            "sourceSHA256": digest, "sourceTitle": item["title"]!, "page": pageNumber,
            "bounds": rect(bounds), "rasterPixels": [raster.width, raster.height],
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "extraction": "One RecognizeDocumentsRequest; default ConversionOptions raster; English; language correction off",
            "observationCount": observations.count, "lines": rootLines.map(line),
            "containers": containers]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    }
}
