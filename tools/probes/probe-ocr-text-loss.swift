import CryptoKit
import Foundation
import PDFKit
import Vision

// Measures, page by page, how much of a corpus page's own writing a recognition of it leaves
// unread, and what the band retry recovers (#116). It drives the shipped code — `OCRReader`'s
// request, `OCRReader.recognize`, `OCRReader.completeReading` and `OCRTextCoverage` — so what it
// reports is the conversion's behaviour, not a reimplementation of it. Vision's compiled models
// decide what any one page reads (#173), so a run is evidence about this machine's models; the
// library's own tests use canned readings instead. Run from the repository root; one JSON object
// per page on stdout.
//
//   probe-ocr-text-loss <corpus-case-id> [first-page] [last-page]
//
// With PROBE_TEXT=<dir>, each flagged page's two readings are written there as text, so the
// recovered words can be read against the page's raster and its inherited layer.
@main struct ProbeOCRTextLoss {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard (2...4).contains(arguments.count) else {
            fatalError("usage: probe-ocr-text-loss <corpus-case-id> [first-page] [last-page]")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        guard let item = (manifest["documents"] as! [[String: Any]]).first(where: {
            $0["id"] as? String == arguments[1]
        }), let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + file)
        let digest = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }

        let first = arguments.count > 2 ? Int(arguments[2])! : 1
        let last = arguments.count > 3 ? Int(arguments[3])! : document.pageCount
        let options = ConversionOptions()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for number in first...min(last, document.pageCount) {
            guard let page = document.page(at: number - 1) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
            // The request the conversion makes, so a band the probe recognizes is a band the
            // conversion would have recognized.
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.useLanguageCorrection = false
            let language = Locale.Language(identifier: options.language)
            if request.supportedRecognitionLanguages.contains(language) {
                request.textRecognitionOptions.recognitionLanguages = [language]
            }
            let pixelsPerPoint = Double(image.width) / bounds.width

            let startFirst = Date()
            let reading = try await OCRReader.recognize(image, request: request)
            let firstSeconds = Date().timeIntervalSince(startFirst)

            let startMeasure = Date()
            let before = OCRTextCoverage.measure(image: image, lines: reading.lines.map(\.box),
                                                 excluded: reading.tables, pixelsPerPoint: pixelsPerPoint)
            let measureSeconds = Date().timeIntervalSince(startMeasure)

            let startComplete = Date()
            let completed = try await OCRReader.completeReading(reading, image: image, request: request,
                                                                pixelsPerPoint: pixelsPerPoint)
            let completeSeconds = Date().timeIntervalSince(startComplete)
            // The reading the conversion ends up with, measured again in full, so the record shows
            // what remains uncovered and not only whether that still counts as loss.
            let after = OCRTextCoverage.measure(image: image, lines: completed.recognition.lines.map(\.box),
                                                excluded: completed.recognition.tables,
                                                pixelsPerPoint: pixelsPerPoint)

            let record = PageRecord(
                page: number, width: image.width, height: image.height,
                firstLines: reading.lines.count, firstWords: ProbeOCRTextLoss.words(reading),
                firstTables: reading.tables.count,
                textRows: before.textRows, uncoveredRows: before.uncoveredRows,
                textInk: before.textInk, uncoveredInk: before.uncoveredInk,
                uncoveredFraction: before.uncoveredFraction, indicatesLoss: before.indicatesLoss,
                retried: completed.retried,
                finalLines: completed.recognition.lines.count,
                finalWords: ProbeOCRTextLoss.words(completed.recognition),
                finalTextRows: after.textRows, finalUncoveredRows: after.uncoveredRows,
                finalUncoveredShare: after.uncoveredFraction,
                finalUncoveredFraction: completed.uncoveredTextFraction,
                firstSeconds: firstSeconds, measureSeconds: measureSeconds, completeSeconds: completeSeconds)
            print(String(decoding: try encoder.encode(record), as: UTF8.self))
            fflush(stdout)
            if let directory = ProcessInfo.processInfo.environment["PROBE_TEXT"], before.indicatesLoss {
                let base = URL(fileURLWithPath: directory)
                try reading.lines.map(\.text).joined(separator: "\n")
                    .write(to: base.appendingPathComponent("p\(number)-first.txt"), atomically: true, encoding: .utf8)
                try completed.recognition.lines.map(\.text).joined(separator: "\n")
                    .write(to: base.appendingPathComponent("p\(number)-final.txt"), atomically: true, encoding: .utf8)
            }
        }
    }

    static func words(_ recognition: OCRReader.Recognition) -> Int {
        recognition.lines.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)
    }
}

struct PageRecord: Codable {
    var page: Int, width: Int, height: Int
    var firstLines: Int, firstWords: Int, firstTables: Int
    var textRows: Int, uncoveredRows: Int, textInk: Int, uncoveredInk: Int
    var uncoveredFraction: Double, indicatesLoss: Bool
    var retried: Bool, finalLines: Int, finalWords: Int
    var finalTextRows: Int, finalUncoveredRows: Int, finalUncoveredShare: Double
    /// Set only when what remains still counts as loss, exactly as `OCRReader` reports it.
    var finalUncoveredFraction: Double?
    var firstSeconds: Double, measureSeconds: Double, completeSeconds: Double
}
