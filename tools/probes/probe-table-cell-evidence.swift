import Foundation
import CryptoKit
import PDFKit
import Vision

// #31. Measures, for each page named, the tables Vision's document recognition locates on a
// checksum-pinned corpus source and how much of each one it transcribes, through the library's
// own rasterizer and `OCRReader.cellEvidence`. It records the reading, never converter output.
// Run from the repository root:
//
//   probe-table-cell-evidence <corpus-case-id> <page> [<page> …] [--fixture <output.json>]
//
// With `--fixture` it also writes the grids as a test fixture: each located table's rectangle in
// the page's own points, its rows and columns, and every cell's transcription, which is what
// `TableCellEvidence` reads. Vision's reading of a given page is not stable across compiled model
// sets (#173), so the tests replay a capture rather than calling Vision.
@main struct ProbeTableCellEvidence {
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var fixture: String?
        if let index = arguments.firstIndex(of: "--fixture"), index + 1 < arguments.count {
            fixture = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }
        guard arguments.count >= 2 else {
            fatalError("usage: probe-table-cell-evidence <corpus-case-id> <page> [<page> …] [--fixture <output.json>]")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        guard let item = (manifest["documents"] as! [[String: Any]]).first(where: {
            $0["id"] as? String == arguments[0]
        }), let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + file)
        let digest = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        let options = ConversionOptions()
        var captured: [[String: Any]] = []
        for argument in arguments.dropFirst() {
            guard let number = Int(argument), let page = document.page(at: number - 1) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.useLanguageCorrection = false
            let language = Locale.Language(identifier: options.language)
            if request.supportedRecognitionLanguages.contains(language) {
                request.textRecognitionOptions.recognitionLanguages = [language]
            }
            let observations = try await request.perform(on: image, orientation: nil)
            guard let read = observations.first?.document else {
                print("page \(number): no document observation")
                continue
            }
            print("page \(number): \(read.text.lines.count) lines, \(read.tables.count) tables")
            var tables: [[String: Any]] = []
            for (index, table) in read.tables.enumerated() {
                let reading = OCRReader.cellEvidence(of: table)
                let rect = CGRect(x: bounds.minX + reading.rect.minX * bounds.width,
                                  y: bounds.minY + reading.rect.minY * bounds.height,
                                  width: reading.rect.width * bounds.width,
                                  height: reading.rect.height * bounds.height)
                print(String(format: "  table %d: %d x %d = %d cells, %d transcribed (%.0f%%), "
                             + "cells were read: %@, rect (%.1f, %.1f, %.1f, %.1f)",
                             index, reading.rows, reading.columns, reading.cells, reading.transcribedCells,
                             reading.transcribedFraction * 100, reading.cellsWereRead ? "yes" : "no",
                             rect.minX, rect.minY, rect.width, rect.height))
                let columns = table.columns.count
                let cells: [[String]] = table.rows.map { row in
                    var line = [String](repeating: "", count: columns)
                    for cell in row {
                        let column = cell.columnRange.lowerBound
                        guard column >= 0, column < columns else { continue }
                        line[column] = cell.content.text.transcript
                    }
                    return line
                }
                tables.append(["rect": [rect.minX, rect.minY, rect.width, rect.height],
                               "columns": columns, "cells": cells])
            }
            captured.append(["page": number, "bounds": [bounds.minX, bounds.minY, bounds.width, bounds.height],
                             "tables": tables])
        }
        guard let fixture else { return }
        let payload: [String: Any] = [
            "caseID": item["id"]!, "sourceSHA256": digest, "sourceTitle": item["title"]!,
            "rightsBasis": item["rightsBasis"] ?? "See corpus manifest and third-party notices.",
            "extraction": "Vision RecognizeDocumentsRequest tables, default ConversionOptions",
            "pages": captured,
        ]
        try JSONSerialization.data(withJSONObject: payload,
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: fixture))
    }
}
