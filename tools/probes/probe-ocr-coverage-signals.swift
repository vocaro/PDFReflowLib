import CryptoKit
import Foundation
import PDFKit
import Vision

// Measures, page by page, every signal #240 weighs against the coverage rule of #116: the shipped
// measurement, the geometry of the reading's line boxes against the page's own rows of writing,
// and what the band retry would recover whether or not the shipped rule asks for it. It drives
// the shipped code — `OCRReader.recognize`, `OCRReader.mergeBands` and `OCRTextCoverage` — so what
// it reports is the conversion's behavior. Vision's compiled models decide what any one page
// reads (#173), so a run is evidence about this machine's models.
// Run from the repository root; one JSON object per page on stdout.
//
//   probe-ocr-coverage-signals <corpus-case-id> [first-page] [last-page]
//
// PROBE_RETRY=always attempts the band retry on every page rather than only where the reading
// leaves at least `OCRTextCoverage.minimumUncoveredRows` rows of writing unread.
@main struct ProbeOCRCoverageSignals {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard (2...4).contains(arguments.count) else {
            fatalError("usage: probe-ocr-coverage-signals <corpus-case-id> [first-page] [last-page]")
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
        let alwaysRetry = ProcessInfo.processInfo.environment["PROBE_RETRY"] == "always"
        let options = ConversionOptions()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for number in first...min(last, document.pageCount) {
            guard let page = document.page(at: number - 1) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.useLanguageCorrection = false
            let language = Locale.Language(identifier: options.language)
            if request.supportedRecognitionLanguages.contains(language) {
                request.textRecognitionOptions.recognitionLanguages = [language]
            }
            let pixelsPerPoint = Double(image.width) / bounds.width
            guard let raster = OCRTextCoverage.GrayRaster(image) else { continue }

            let startFirst = Date()
            let reading = try await OCRReader.recognize(image, request: request)
            let firstSeconds = Date().timeIntervalSince(startFirst)

            let startMeasure = Date()
            let before = OCRTextCoverage.measure(raster, boxes: reading.lines.map(\.box),
                                                 excluded: reading.tables, pixelsPerPoint: pixelsPerPoint)
            let measureSeconds = Date().timeIntervalSince(startMeasure)

            // Every row of writing the page draws, whatever the reading covers: measured against no
            // lines at all, every counted row is uncovered, so its boxes are all of the page's rows.
            let allRows = OCRTextCoverage.measure(raster, boxes: [], excluded: reading.tables,
                                                  pixelsPerPoint: pixelsPerPoint, collectBoxes: true)
            let rowHeights = allRows.uncoveredRowBoxes.map { Double($0.height) }.sorted()
            let rowHeight = percentile(rowHeights, 0.5)
            let lineHeights = reading.lines.map { $0.box.height * Double(image.height) }.sorted()

            func variantMeasure(_ recognition: OCRReader.Recognition, clip: Double) -> OCRTextCoverage.Measurement {
                OCRTextCoverage.measure(raster, boxes: clipped(recognition, to: clip, rowHeight: rowHeight,
                                                               imageHeight: Double(image.height)),
                                        excluded: recognition.tables, pixelsPerPoint: pixelsPerPoint)
            }
            // What the reading wrote, rather than where it looked: a line box cut back to the
            // width its own transcription can fill, at `k` row heights per character.
            func written(_ recognition: OCRReader.Recognition, perCharacter k: Double) -> [CGRect] {
                guard rowHeight > 0 else { return recognition.lines.map(\.box) }
                return recognition.lines.map { line in
                    let characters = advanceUnits(line.text)
                    let fill = characters * k * rowHeight / Double(image.width)
                    guard fill < line.box.width else { return line.box }
                    return CGRect(x: line.box.minX, y: line.box.minY, width: fill, height: line.box.height)
                }
            }
            // The same clip counting every character as one Latin advance, for comparison.
            func plainMeasure(_ recognition: OCRReader.Recognition, _ k: Double) -> OCRTextCoverage.Measurement {
                guard rowHeight > 0 else {
                    return OCRTextCoverage.measure(raster, boxes: recognition.lines.map(\.box),
                                                   excluded: recognition.tables, pixelsPerPoint: pixelsPerPoint)
                }
                let lines = recognition.lines.map { line -> CGRect in
                    let fill = Double(line.text.filter { !$0.isWhitespace }.count) * k * rowHeight / Double(image.width)
                    guard fill < line.box.width else { return line.box }
                    return CGRect(x: line.box.minX, y: line.box.minY, width: fill, height: line.box.height)
                }
                return OCRTextCoverage.measure(raster, boxes: lines, excluded: recognition.tables,
                                               pixelsPerPoint: pixelsPerPoint)
            }
            func writtenMeasure(_ recognition: OCRReader.Recognition, _ k: Double) -> OCRTextCoverage.Measurement {
                OCRTextCoverage.measure(raster, boxes: written(recognition, perCharacter: k),
                                        excluded: recognition.tables, pixelsPerPoint: pixelsPerPoint)
            }
            let plain04 = plainMeasure(reading, 0.4)
            let written04 = writtenMeasure(reading, 0.4)
            let written05 = writtenMeasure(reading, 0.5)
            let written06 = writtenMeasure(reading, 0.6)
            let written07 = writtenMeasure(reading, 0.7)
            if let directory = ProcessInfo.processInfo.environment["PROBE_TEXT"] {
                // Per-line geometry and transcription, so the per-character width can be
                // calibrated from readings the page's own layer says are complete.
                let geometry = reading.lines.map { line in
                    LineGeometry(characters: line.text.filter { !$0.isWhitespace }.count,
                                 widthPixels: line.box.width * Double(image.width),
                                 heightPixels: line.box.height * Double(image.height),
                                 minXPixels: line.box.minX * Double(image.width),
                                 minYPixels: (1 - line.box.maxY) * Double(image.height))
                }
                try encoder.encode(geometry).write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("p\(number)-lines.json"))
            }
            let clip15 = variantMeasure(reading, clip: 1.5)
            let clip25 = variantMeasure(reading, clip: 2.5)
            let dropped = OCRTextCoverage.measure(
                raster,
                boxes: reading.lines.map(\.box).filter { rowHeight <= 0
                    || $0.height * Double(image.height) <= 2.5 * rowHeight },
                excluded: reading.tables, pixelsPerPoint: pixelsPerPoint)

            var bandedRecord: BandedRecord?
            if alwaysRetry || before.uncoveredRows >= OCRTextCoverage.minimumUncoveredRows {
                let startBanded = Date()
                let banded = try await readInBands(image, request: request)
                let bandedSeconds = Date().timeIntervalSince(startBanded)
                if let banded {
                    if let directory = ProcessInfo.processInfo.environment["PROBE_TEXT"] {
                        let base = URL(fileURLWithPath: directory)
                        try reading.lines.map(\.text).joined(separator: "\n")
                            .write(to: base.appendingPathComponent("p\(number)-first.txt"),
                                   atomically: true, encoding: .utf8)
                        try banded.lines.map(\.text).joined(separator: "\n")
                            .write(to: base.appendingPathComponent("p\(number)-banded.txt"),
                                   atomically: true, encoding: .utf8)
                    }
                    let after = OCRTextCoverage.measure(raster, boxes: banded.lines.map(\.box),
                                                        excluded: banded.tables, pixelsPerPoint: pixelsPerPoint)
                    // #116's keep test: tables ignored on both sides, so a larger table cannot win.
                    func inkIgnoringTables(_ recognition: OCRReader.Recognition) -> Int {
                        OCRTextCoverage.measure(raster, boxes: recognition.lines.map(\.box), excluded: [],
                                                pixelsPerPoint: pixelsPerPoint).uncoveredInk
                    }
                    let clipped15 = variantMeasure(banded, clip: 1.5)
                    let bandedWritten = writtenMeasure(banded, 0.5)
                    bandedRecord = BandedRecord(
                        lines: banded.lines.count, words: words(banded), tables: banded.tables.count,
                        coversMore: inkIgnoringTables(banded) < inkIgnoringTables(reading),
                        textRows: after.textRows, uncoveredRows: after.uncoveredRows,
                        uncoveredFraction: after.uncoveredFraction,
                        clip15UncoveredRows: clipped15.uncoveredRows,
                        clip15UncoveredFraction: clipped15.uncoveredFraction,
                        written05UncoveredRows: bandedWritten.uncoveredRows,
                        written05UncoveredFraction: bandedWritten.uncoveredFraction,
                        seconds: bandedSeconds)
                }
            }

            let record = PageRecord(
                page: number, width: image.width, height: image.height, pixelsPerPoint: pixelsPerPoint,
                firstLines: reading.lines.count, firstWords: words(reading), firstTables: reading.tables.count,
                lineHeightMedian: percentile(lineHeights, 0.5), lineHeightP90: percentile(lineHeights, 0.9),
                linesTallerThanRow: lineHeights.filter { rowHeight > 0 && $0 > 2.5 * rowHeight }.count,
                allRows: allRows.textRows, allRowInk: allRows.textInk, rowHeightMedian: rowHeight,
                textRows: before.textRows, uncoveredRows: before.uncoveredRows,
                textInk: before.textInk, uncoveredInk: before.uncoveredInk,
                uncoveredFraction: before.uncoveredFraction, indicatesLoss: before.indicatesLoss,
                clip15UncoveredRows: clip15.uncoveredRows, clip15TextRows: clip15.textRows,
                clip15UncoveredFraction: clip15.uncoveredFraction,
                clip25UncoveredRows: clip25.uncoveredRows, clip25UncoveredFraction: clip25.uncoveredFraction,
                drop25UncoveredRows: dropped.uncoveredRows, drop25UncoveredFraction: dropped.uncoveredFraction,
                plain04UncoveredRows: plain04.uncoveredRows, plain04UncoveredFraction: plain04.uncoveredFraction,
                written04UncoveredRows: written04.uncoveredRows, written04UncoveredFraction: written04.uncoveredFraction,
                written05UncoveredRows: written05.uncoveredRows, written05UncoveredFraction: written05.uncoveredFraction,
                written06UncoveredRows: written06.uncoveredRows, written06UncoveredFraction: written06.uncoveredFraction,
                written07UncoveredRows: written07.uncoveredRows, written07UncoveredFraction: written07.uncoveredFraction,
                banded: bandedRecord,
                firstSeconds: firstSeconds, measureSeconds: measureSeconds)
            print(String(decoding: try encoder.encode(record), as: UTF8.self))
            fflush(stdout)
        }
    }

    /// The reading's line boxes with any box taller than `clip` rows of the page's own writing cut
    /// back to that height about its own center: one way of not believing a block-shaped region.
    static func clipped(_ recognition: OCRReader.Recognition, to clip: Double, rowHeight: Double,
                        imageHeight: Double) -> [CGRect] {
        guard rowHeight > 0 else { return recognition.lines.map(\.box) }
        let limit = clip * rowHeight / imageHeight
        return recognition.lines.map { line in
            guard line.box.height > limit else { return line.box }
            return CGRect(x: line.box.minX, y: line.box.midY - limit / 2, width: line.box.width, height: limit)
        }
    }

    /// #116's own band retry, repeated here because `OCRReader.readInBands` is private and the
    /// probe attempts it on pages the shipped rule does not flag.
    static func readInBands(_ image: CGImage, request: RecognizeDocumentsRequest) async throws -> OCRReader.Recognition? {
        var bands: [(recognition: OCRReader.Recognition, bottom: Double, height: Double)] = []
        for band in OCRReader.retryBands {
            let top = Int((1 - band.upperBound) * Double(image.height))
            let bottom = Int((1 - band.lowerBound) * Double(image.height))
            guard bottom > top,
                  let tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top))
            else { return nil }
            bands.append((try await OCRReader.recognize(tile, request: request),
                          1 - Double(bottom) / Double(image.height),
                          Double(bottom - top) / Double(image.height)))
        }
        return OCRReader.mergeBands(bands)
    }

    /// A line's width in Latin character advances: a fullwidth or ideographic character is drawn
    /// about twice as wide as a Latin one at the same size, so it counts twice.
    static func advanceUnits(_ text: String) -> Double {
        var total = 0.0
        for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
            total += isWide(scalar) ? 2 : 1
        }
        return total
    }

    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    static func words(_ recognition: OCRReader.Recognition) -> Int {
        recognition.lines.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)
    }

    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * q).rounded())))]
    }
}

struct BandedRecord: Codable {
    var lines: Int, words: Int, tables: Int
    var coversMore: Bool
    var textRows: Int, uncoveredRows: Int, uncoveredFraction: Double
    var clip15UncoveredRows: Int, clip15UncoveredFraction: Double
    var written05UncoveredRows: Int, written05UncoveredFraction: Double
    var seconds: Double
}

struct LineGeometry: Codable {
    var characters: Int
    var widthPixels: Double, heightPixels: Double, minXPixels: Double, minYPixels: Double
}

struct PageRecord: Codable {
    var page: Int, width: Int, height: Int, pixelsPerPoint: Double
    var firstLines: Int, firstWords: Int, firstTables: Int
    var lineHeightMedian: Double, lineHeightP90: Double, linesTallerThanRow: Int
    var allRows: Int, allRowInk: Int, rowHeightMedian: Double
    var textRows: Int, uncoveredRows: Int, textInk: Int, uncoveredInk: Int
    var uncoveredFraction: Double, indicatesLoss: Bool
    var clip15UncoveredRows: Int, clip15TextRows: Int, clip15UncoveredFraction: Double
    var clip25UncoveredRows: Int, clip25UncoveredFraction: Double
    var drop25UncoveredRows: Int, drop25UncoveredFraction: Double
    var plain04UncoveredRows: Int, plain04UncoveredFraction: Double
    var written04UncoveredRows: Int, written04UncoveredFraction: Double
    var written05UncoveredRows: Int, written05UncoveredFraction: Double
    var written06UncoveredRows: Int, written06UncoveredFraction: Double
    var written07UncoveredRows: Int, written07UncoveredFraction: Double
    var banded: BandedRecord?
    var firstSeconds: Double, measureSeconds: Double
}
