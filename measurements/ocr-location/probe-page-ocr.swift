import CryptoKit
import Foundation
import PDFKit
import Vision

// OCR pages of one PDF in order with the converter's request, in one process (#94).
// Build with the library's raster sources, as the capability probe is built:
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/PageRasterizer.swift \
//     Sources/PDFReflowLib/ConversionTypes.swift Sources/PDFReflowLib/DocumentModel.swift \
//     Sources/PDFReflowLib/ReflowDocument.swift measurements/ocr-location/probe-page-ocr.swift -o <probe>
// Usage: <probe> <pdf> <page>...   PROBE_DEVICE=CPU|GPU|NeuralEngine pins the request's compute stage.
// Prints the page, seconds, a SHA-256 prefix of the recognized text and Census noise markers.
@main struct ProbePageOCR {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: probe-page-ocr <pdf> <page>...")
        }
        let device = ProcessInfo.processInfo.environment["PROBE_DEVICE"]
        for argument in args.dropFirst(2) {
            guard let number = Int(argument), let page = document.page(at: number - 1) else { continue }
            let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox), options: ConversionOptions())
            var request = OCRRequestShape.make()
            if let device {
                for (stage, devices) in request.supportedComputeStageDevices {
                    if let match = devices.first(where: { "\($0)".contains(device) }) { request.setComputeDevice(match, for: stage) }
                }
            }
            let start = Date()
            let observations = try await request.perform(on: image, orientation: nil)
            let text = observations.first?.document.text.lines.map(\.transcript).joined(separator: "\n") ?? ""
            let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
            let markers = ["rauk", "re-identilicatiou", "|18", "[ 18]", "uoise"].filter { text.contains($0) }
            print("page", number, String(format: "%.2fs", Date().timeIntervalSince(start)), hash, markers)
        }
    }
}

/// The converter's request before #94 made its defaults explicit (same values).
enum OCRRequestShape {
    static func make() -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        return request
    }
}
