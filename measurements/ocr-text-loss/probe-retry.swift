import Foundation
import PDFKit
import Vision

// Does a second recognition recover silently dropped text (#116)? For each page, recognizes with
// the converter's request under several variants and measures every result with the library's
// `OCRTextCoverage` against that variant's own raster:
//   base      the converter's raster (180 DPI)
//   dpi240    the page rasterized at 240 DPI
//   dpi150    the page rasterized at 150 DPI
//   tiles     the 180 DPI raster cut into top and bottom bands (60% of the height each, 20% shared),
//             each recognized as its own image; lines are kept by the band that owns their center
//   roi       the same bands via `regionOfInterest` on the uncropped raster, boxes read as full-image
//   roi-relative  the same, boxes read as relative to the region of interest (what Vision returns)
// Build (unique executable name; this compiles Vision's models, see #94):
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/OCRReader.swift \
//     Sources/PDFReflowLib/OCRTextCoverage.swift Sources/PDFReflowLib/PageRasterizer.swift \
//     Sources/PDFReflowLib/ConversionTypes.swift Sources/PDFReflowLib/DocumentModel.swift \
//     Sources/PDFReflowLib/ReflowDocument.swift measurements/ocr-text-loss/probe-retry.swift -o <name>
// Usage: <probe> <pdf> <page>...
@main struct ProbeRetry {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: probe-retry <pdf> <page>...")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for argument in args.dropFirst(2) {
            guard let number = Int(argument), let page = document.page(at: number - 1) else { continue }
            let bounds = page.bounds(for: .cropBox)
            var results: [Variant] = []
            for (name, dpi) in [("base", 180.0), ("dpi240", 240), ("dpi150", 150)] {
                var options = ConversionOptions()
                options.rasterDPI = dpi
                let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
                let start = Date()
                let found = try await recognize(image, roi: nil)
                let boxes = found.map(\.box)
                results.append(Variant(name: name, seconds: Date().timeIntervalSince(start), lines: boxes.count,
                    coverage: Coverage(measure(image, boxes, bounds)), texts: name == "base" ? found.map(\.text) : nil))
            }
            let image = try PageRasterizer.image(page: page, rect: bounds, options: ConversionOptions())
            // Bands in Vision's lower-left normalized space: bottom [0, 0.6], top [0.4, 1].
            let bands = [(low: 0.4, high: 1.0, keepLow: 0.5, keepHigh: 1.01),
                         (low: 0.0, high: 0.6, keepLow: -0.01, keepHigh: 0.5)]
            for mode in ["tiles", "roi", "roi-relative"] {
                let start = Date()
                var merged: [(box: CGRect, text: String)] = []
                for band in bands {
                    var boxes: [(box: CGRect, text: String)]
                    if mode == "roi-relative" {
                        // The same request, reading boxes as relative to the region of interest.
                        let span = band.high - band.low
                        boxes = try await recognize(image, roi: CGRect(x: 0, y: band.low, width: 1, height: span)).map {
                            (CGRect(x: $0.box.minX, y: band.low + $0.box.minY * span, width: $0.box.width, height: $0.box.height * span), $0.text)
                        }
                    } else if mode == "tiles" {
                        let top = Int((1 - band.high) * Double(image.height))
                        let bottom = Int((1 - band.low) * Double(image.height))
                        guard let tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top)) else { continue }
                        let span = Double(bottom - top) / Double(image.height)
                        boxes = try await recognize(tile, roi: nil).map {
                            (CGRect(x: $0.box.minX, y: band.low + $0.box.minY * span, width: $0.box.width, height: $0.box.height * span), $0.text)
                        }
                    } else {
                        boxes = try await recognize(image, roi: CGRect(x: 0, y: band.low, width: 1, height: band.high - band.low))
                    }
                    merged += boxes.filter { $0.box.midY >= band.keepLow && $0.box.midY < band.keepHigh }
                }
                results.append(Variant(name: mode, seconds: Date().timeIntervalSince(start), lines: merged.count,
                    coverage: Coverage(measure(image, merged.map(\.box), bounds)), texts: mode == "tiles" ? merged.map(\.text) : nil))
            }
            print(String(decoding: try encoder.encode(Record(page: number, variants: results)), as: UTF8.self))
        }
    }

    static func measure(_ image: CGImage, _ boxes: [CGRect], _ bounds: CGRect) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.measure(image: image, lines: boxes, pixelsPerPoint: Double(image.width) / bounds.width)
    }

    /// Line boxes and top candidates, normalized to the recognized image or region of interest.
    static func recognize(_ image: CGImage, roi: CGRect?) async throws -> [(box: CGRect, text: String)] {
        var request = OCRReader.recognitionRequest(language: "en")
        if let roi {
            request.regionOfInterest = NormalizedRect(x: roi.minX, y: roi.minY, width: roi.width, height: roi.height)
        }
        let observations = try await request.perform(on: image, orientation: nil)
        return observations.first?.document.text.lines.map {
            ($0.boundingRegion.boundingBox.cgRect, $0.topCandidates(1).first?.string ?? "")
        } ?? []
    }
}

struct Coverage: Codable {
    var rows: Int, uncoveredRows: Int, fraction: Double, loss: Bool
    init(_ m: OCRTextCoverage.Measurement) {
        rows = m.textRows; uncoveredRows = m.uncoveredRows; fraction = m.uncoveredFraction; loss = m.indicatesLoss
    }
}
struct Variant: Codable { var name: String; var seconds: Double; var lines: Int; var coverage: Coverage; var texts: [String]? }
struct Record: Codable { var page: Int; var variants: [Variant] }
