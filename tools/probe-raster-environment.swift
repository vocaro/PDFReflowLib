import CryptoKit
import Foundation
import Metal
import PDFKit
import Vision

// Diagnostic only. Compile with PageRasterizer.swift, ConversionTypes.swift,
// DocumentModel.swift and ReflowDocument.swift. The PDF path is explicit so the
// probe and converter use the same verified source even outside corpus/cache.
// The context label is supplied by the caller; it is not sandbox detection.
@main struct ProbeRasterEnvironment {
    static func main() async throws {
        guard CommandLine.arguments.count == 6,
              let number = Int(CommandLine.arguments[2]), number > 0 else {
            fatalError("usage: probe-raster-environment <pdf> <physical-page> <context-label> <run-id> <output.json>")
        }
        func hash(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceHash = hash(try Data(contentsOf: source))
        guard let document = PDFDocument(url: source), let page = document.page(at: number - 1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[5])
        let image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox),
            options: ConversionOptions())
        // Hash actual packed rows, excluding CGContext's alignment padding.
        let data = image.dataProvider!.data! as Data
        var packed = Data()
        let rowBytes = image.width * image.bitsPerPixel / 8
        for row in 0..<image.height {
            packed.append(data.subdata(in: row * image.bytesPerRow ..< row * image.bytesPerRow + rowBytes))
        }
        try PageRasterizer.write(image, to: output.deletingPathExtension().appendingPathExtension("png"))
        var payload: [String: Any] = [
            "schemaVersion": 1, "runID": CommandLine.arguments[4],
            "sourceSHA256": sourceHash, "page": number,
            "executionContext": CommandLine.arguments[3],
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "probeSHA256": hash(try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))),
            "rasterDPI": ConversionOptions().rasterDPI,
            "width": image.width, "height": image.height, "bitsPerPixel": image.bitsPerPixel,
            "packedPixelSHA256": hash(packed),
            "colorSpaceName": image.colorSpace?.name as String? ?? "unnamed",
            "colorSpaceICC_SHA256": image.colorSpace?.copyICCData().map { hash($0 as Data) } ?? "unavailable",
            "metalDevice": MTLCreateSystemDefaultDevice()?.name ?? "unavailable",
        ]
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        let language = Locale.Language(identifier: "en")
        if request.supportedRecognitionLanguages.contains(language) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        do {
            let observations = try await request.perform(on: image, orientation: nil)
            payload["ocr"] = ["status": "succeeded", "lines": observations.first?.document.text.lines.map(\.transcript) ?? []]
        } catch {
            let error = error as NSError
            payload["ocr"] = ["status": "failed", "domain": error.domain, "code": error.code,
                "description": error.localizedDescription, "details": String(describing: error.userInfo)]
        }
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: output)
    }
}
