import Foundation
import PDFKit
import CryptoKit
import Vision

// usage: ocrprobe <pdf> <page>...
// Replays OCRReader.read's decision steps on each page and prints, per page, one tab-separated line:
// page, raster hash, first recognition (lines, text hash, table count), first coverage (textRows,
// uncoveredRows, textInk, uncoveredInk, fraction, indicatesLoss), and when retried the band
// recognitions' text hash and both line-only coverages and whether the retry is kept.
@main struct OCRProbe {
    static func h(_ d: Data) -> String { SHA256.hash(data: d).prefix(4).map { String(format: "%02x", $0) }.joined() }
    static func h(_ s: String) -> String { h(Data(s.utf8)) }
    static func describe(_ r: OCRReader.Recognition) -> String {
        h(r.lines.map { "\($0.text)|\($0.box)" }.joined(separator: "\n") + "T\(r.tables)")
    }
    static func cov(_ m: OCRTextCoverage.Measurement) -> String {
        "rows=\(m.textRows) unc=\(m.uncoveredRows) ink=\(m.textInk) uink=\(m.uncoveredInk) f=\(String(format: "%.5f", m.uncoveredFraction)) loss=\(m.indicatesLoss)"
    }
    static func main() async throws {
        let args = CommandLine.arguments
        let source = try PDFPageSource(url: URL(fileURLWithPath: args[1]))
        let options = ConversionOptions()
        for number in args[2...].compactMap({ Int($0) }) {
            let page = try source.page(at: number - 1)
            let bounds = page.bounds(for: .cropBox)
            let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
            let raster = image.dataProvider!.data! as Data
            let request = OCRReader.recognitionRequest(language: options.language)
            let first = try await OCRReader.recognize(image, request: request)
            let ppp = Double(image.width) / bounds.width
            let coverage = OCRTextCoverage.measure(image: image, lines: first.lines.map(\.box), excluded: first.tables, pixelsPerPoint: ppp)
            var out = "\(number)\traster=\(h(raster))\tfirst=\(first.lines.count)/\(describe(first))/t\(first.tables.count)\t\(cov(coverage))"
            if coverage.indicatesLoss {
                var bands: [(recognition: OCRReader.Recognition, bottom: Double, height: Double)] = []
                for band in OCRReader.retryBands {
                    let top = Int((1 - band.upperBound) * Double(image.height))
                    let bottom = Int((1 - band.lowerBound) * Double(image.height))
                    let tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top))!
                    bands.append((try await OCRReader.recognize(tile, request: request),
                                  1 - Double(bottom) / Double(image.height), Double(bottom - top) / Double(image.height)))
                }
                let merged = OCRReader.mergeBands(bands)
                let a = OCRTextCoverage.measure(image: image, lines: first.lines.map(\.box), pixelsPerPoint: ppp)
                let b = OCRTextCoverage.measure(image: image, lines: merged.lines.map(\.box), pixelsPerPoint: ppp)
                out += "\tbands=\(describe(bands[0].recognition))+\(describe(bands[1].recognition))\tfirstLines[\(cov(a))]\tmerged[\(cov(b))]\tkept=\(b.uncoveredInk < a.uncoveredInk)"
            }
            print(out)
            fflush(stdout)
        }
    }
}
