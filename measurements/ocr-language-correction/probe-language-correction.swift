import Foundation
import PDFKit
import Vision

// Language correction on English OCR pages (#108 item 1). Each page is rasterized once exactly as
// the converter does (library defaults, 180 DPI) and recognized with the converter's request
// (`OCRReader.recognitionRequest(language: "en")`) twice in the same process, differing only in
// `useLanguageCorrection`. Both settings therefore share one set of compiled Vision programs (#94).
// Build with the library's sources (no library change):
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/OCRReader.swift \
//     Sources/PDFReflowLib/OCRTextCoverage.swift Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
//     Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
//     measurements/ocr-language-correction/probe-language-correction.swift -o <unique name>
// Usage: <probe> <pdf> <order: off-on|on-off> <page>...
// Prints one JSON object per page and setting: page, correction, seconds, lines (top candidates).
@main struct ProbeLanguageCorrection {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: probe-language-correction <pdf> <off-on|on-off> <page>...")
        }
        let settings = args[2] == "on-off" ? [true, false] : [false, true]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for argument in args.dropFirst(3) {
            guard let number = Int(argument), let page = document.page(at: number - 1) else { continue }
            let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox),
                                                 options: ConversionOptions())
            for correction in settings {
                var request = OCRReader.recognitionRequest(language: "en")
                request.textRecognitionOptions.useLanguageCorrection = correction
                let start = Date()
                let observations = try await request.perform(on: image, orientation: nil)
                let lines = observations.first?.document.text.lines
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                let record = Record(page: number, correction: correction,
                                    seconds: Date().timeIntervalSince(start), lines: lines)
                print(String(decoding: try encoder.encode(record), as: UTF8.self))
            }
        }
    }
}

struct Record: Codable { var page: Int; var correction: Bool; var seconds: Double; var lines: [String] }
