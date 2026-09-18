import Foundation
import PDFKit

// Survey for #7: recognizes every page of one PDF (or a range) with the converter's own `OCRReader`,
// including its #116 banded retry, and records each recognized line's text and box, so the
// plausibility of what recognition would put in a page's place can be scored offline
// (`score-text.swift`). The executable's name selects its Vision model cache (#94): these
// transcriptions are measurement evidence, not converter output.
// Build: ../text-layer-plausibility/build-tool.sh survey-ocr.swift <scratch>/survey-ocr
// Usage: survey-ocr <pdf> [first last] > ocr.jsonl
@main struct SurveyOCR {
    struct Record: Encodable {
        var page: Int, text: String, rects: [[Double]], retried: Bool, uncovered: Double?, tables: Int, seconds: Double
    }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: survey-ocr <pdf> [first last]")
        }
        let first = args.count >= 4 ? Int(args[2])! : 1
        let last = args.count >= 4 ? Int(args[3])! : document.pageCount
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for number in first...min(last, document.pageCount) {
            guard let page = document.page(at: number - 1) else { continue }
            let start = Date()
            let result = try await OCRReader.read(page: page, options: ConversionOptions())
            let record = Record(page: number, text: result.lines.map(\.text).joined(separator: "\n"),
                                rects: result.lines.map { [$0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height] },
                                retried: result.retriedInBands, uncovered: result.uncoveredTextFraction,
                                tables: result.tables.count, seconds: Date().timeIntervalSince(start))
            FileHandle.standardOutput.write(try encoder.encode(record) + Data("\n".utf8))
        }
    }
}
