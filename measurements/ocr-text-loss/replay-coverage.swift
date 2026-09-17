import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// Replays `OCRTextCoverage` over recorded recognition (#116) without running Vision, so it never
// touches a model cache. For each page in a `probe-ocr-lines` JSONL file it rasterizes the page as
// the converter does, measures the recorded lines, then measures simulated losses: a contiguous
// block of lines removed from the middle of Vision's reading order (a dropped paragraph run) and
// the same share removed at scattered, seeded positions.
// Build:
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/OCRTextCoverage.swift \
//     Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
//     Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
//     measurements/ocr-text-loss/replay-coverage.swift -o <scratch>/replay
// Usage: replay <pdf> <probe jsonl>
// With REPLAY_OVERLAY=<dir>, clean pages with at least the minimum uncovered rows are written there as half-size PNGs with
// recognized line boxes in green and uncovered text rows in red. REPLAY_MIN_GLYPHS overrides the
// minimum glyphs per row.
@main struct ReplayCoverage {
    static let shares = [0.2, 0.35, 0.5, 0.8]

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: replay <pdf> <probe jsonl>")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = try String(contentsOfFile: args[2], encoding: .utf8)
        for line in text.split(separator: "\n") {
            let record = try JSONDecoder().decode(Probe.self, from: Data(line.utf8))
            guard let page = document.page(at: record.page - 1) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let image = try PageRasterizer.image(page: page, rect: bounds, options: ConversionOptions())
            let ppp = Double(image.width) / bounds.width
            let start = Date()
            guard let gray = OCRTextCoverage.GrayRaster(image) else { continue }
            let boxes = record.lines.map { CGRect(x: $0.box[0], y: $0.box[1], width: $0.box[2], height: $0.box[3]) }
            let tables = record.tables.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
            let overlay = ProcessInfo.processInfo.environment["REPLAY_OVERLAY"]
            let glyphs = Int(ProcessInfo.processInfo.environment["REPLAY_MIN_GLYPHS"] ?? "") ?? 5
            let clean = OCRTextCoverage.measure(gray, lines: boxes, excluded: tables, pixelsPerPoint: ppp,
                                                collectBoxes: overlay != nil, minimumGlyphs: glyphs)
            if let overlay, clean.uncoveredRows >= OCRTextCoverage.minimumUncoveredRows {
                try writeOverlay(image, lines: boxes, rows: clean.uncoveredRowBoxes,
                                 to: URL(fileURLWithPath: overlay).appendingPathComponent("p\(record.page).png"))
            }
            var out = Output(page: record.page, lines: boxes.count, seconds: Date().timeIntervalSince(start),
                             clean: Metric(clean))
            var generator = SeededGenerator(seed: UInt64(record.page) &* 116)
            for share in shares {
                let drop = Int((Double(boxes.count) * share).rounded())
                guard drop > 0 else { continue }
                let first = (boxes.count - drop) / 2
                let block = Array(boxes[..<first] + boxes[(first + drop)...])
                let scattered = Array(Array(boxes.indices).shuffled(using: &generator).dropFirst(drop)).sorted().map { boxes[$0] }
                out.simulated.append(Simulated(share: share, kind: "block",
                    metric: Metric(OCRTextCoverage.measure(gray, lines: block, excluded: tables, pixelsPerPoint: ppp, minimumGlyphs: glyphs))))
                out.simulated.append(Simulated(share: share, kind: "scattered",
                    metric: Metric(OCRTextCoverage.measure(gray, lines: scattered, excluded: tables, pixelsPerPoint: ppp, minimumGlyphs: glyphs))))
            }
            print(String(decoding: try encoder.encode(out), as: UTF8.self))
        }
    }
}

func writeOverlay(_ image: CGImage, lines: [CGRect], rows: [CGRect], to url: URL) throws {
    let w = image.width / 2, h = image.height / 2
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    context.setLineWidth(2)
    context.setStrokeColor(red: 0, green: 0.7, blue: 0, alpha: 1)
    for line in lines {
        context.stroke(CGRect(x: line.minX * Double(w), y: line.minY * Double(h), width: line.width * Double(w), height: line.height * Double(h)))
    }
    context.setStrokeColor(red: 1, green: 0, blue: 0, alpha: 1)
    for row in rows {
        context.stroke(CGRect(x: row.minX / 2, y: Double(h) - row.maxY / 2, width: row.width / 2, height: row.height / 2))
    }
    guard let out = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, out, nil)
    CGImageDestinationFinalize(destination)
}

struct ProbeLine: Codable { var text: String; var box: [CGFloat] }
struct Probe: Codable { var page: Int; var lines: [ProbeLine]; var tables: [[CGFloat]] }
struct Metric: Codable {
    var rows: Int, uncoveredRows: Int, ink: Int, uncoveredInk: Int, fraction: Double, loss: Bool
    init(_ m: OCRTextCoverage.Measurement) {
        rows = m.textRows; uncoveredRows = m.uncoveredRows; ink = m.textInk; uncoveredInk = m.uncoveredInk
        fraction = m.uncoveredFraction; loss = m.indicatesLoss
    }
}
struct Simulated: Codable { var share: Double; var kind: String; var metric: Metric }
struct Output: Codable {
    var page: Int; var lines: Int; var seconds: Double; var clean: Metric; var simulated: [Simulated] = []
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
