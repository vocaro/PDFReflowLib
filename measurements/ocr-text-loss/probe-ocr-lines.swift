import Foundation
import PDFKit
import Vision

// Silent OCR text loss (#116). Each page is rasterized exactly as the converter does (library
// defaults, 180 DPI) and recognized once with the converter's request. Prints one JSON object per
// page: the top candidate and normalized bounding box of every `document.text.lines` observation,
// the table boxes, and Vision's own word, paragraph and transcript volume. Run under a never-used
// executable name to draw a fresh compile of Vision's models (#94); see `run-compile.sh`.
// Build with the library's sources (no library change):
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/OCRReader.swift Sources/PDFReflowLib/OCRTextCoverage.swift \
//     Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
//     Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
//     measurements/ocr-text-loss/probe-ocr-lines.swift -o <unique name>
// Usage: <probe> <pdf> <page>...
@main struct ProbeOCRLines {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: probe-ocr-lines <pdf> <page>...")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for argument in args.dropFirst(2) {
            guard let number = Int(argument), let page = document.page(at: number - 1) else { continue }
            let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox),
                                                 options: ConversionOptions())
            let request = OCRReader.recognitionRequest(language: "en")
            let start = Date()
            let observations = try await request.perform(on: image, orientation: nil)
            let seconds = Date().timeIntervalSince(start)
            var record = Record(page: number, seconds: seconds, width: image.width, height: image.height)
            if let doc = observations.first?.document {
                record.lines = doc.text.lines.compactMap { line in
                    guard let text = line.topCandidates(1).first?.string else { return nil }
                    let box = line.boundingRegion.boundingBox.cgRect
                    return Line(text: text, box: [box.minX, box.minY, box.width, box.height])
                }
                record.tables = doc.tables.map {
                    let box = $0.boundingRegion.boundingBox.cgRect
                    return [box.minX, box.minY, box.width, box.height]
                }
                record.words = doc.text.words?.count ?? -1
                record.paragraphs = doc.paragraphs.count
                record.transcriptCharacters = doc.text.transcript.count
            }
            print(String(decoding: try encoder.encode(record), as: UTF8.self))
        }
    }
}

struct Line: Codable { var text: String; var box: [CGFloat] }
struct Record: Codable {
    var page: Int; var seconds: Double; var width: Int; var height: Int
    var lines: [Line] = []; var tables: [[CGFloat]] = []
    var words = 0; var paragraphs = 0; var transcriptCharacters = 0
}
