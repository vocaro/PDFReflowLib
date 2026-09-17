import Foundation
import PDFKit

// Review aid for #93: recognizes selected pages with the converter's own `OCRReader` (including
// its #116 banded retry) and prints the transcription, so a flagged page's inherited layer can be
// read beside what would replace it. The executable's name selects its Vision model cache (#94):
// transcriptions from this probe are review evidence, not converter output.
// Build: as survey-pages.swift, with this file in place of it.
// Usage: probe-ocr <pdf> <page> [page ...] > ocr.jsonl
@main struct ProbeOCR {
    struct Record: Encodable { var page: Int, text: String, retried: Bool, uncovered: Double?, seconds: Double }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: probe-ocr <pdf> <page> [page ...]")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for number in args.dropFirst(2).compactMap({ Int($0) }) {
            guard let page = document.page(at: number - 1) else { continue }
            let start = Date()
            let result = try await OCRReader.read(page: page, options: ConversionOptions())
            let record = Record(page: number, text: result.lines.map(\.text).joined(separator: "\n"),
                                retried: result.retriedInBands, uncovered: result.uncoveredTextFraction,
                                seconds: Date().timeIntervalSince(start))
            FileHandle.standardOutput.write(try encoder.encode(record) + Data("\n".utf8))
        }
    }
}
