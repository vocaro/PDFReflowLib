import Foundation
import ImageIO
import PDFKit
import Vision

// Development-only raster sweep probe, compiled with the production PageRasterizer and value
// types by tools/raster_sweep.py. For every target it renders the page's crop box and one
// reviewed source region at the requested DPI, encodes the same CGImage as PNG and as JPEG at
// each requested quality, and optionally recognizes text in each encoded region file with
// Vision so lossy encoding and resolution both reach the recognizer. There is no extraction,
// reconstruction, EPUB packaging or alternate raster implementation.
@main struct RasterSweepProbe {
    struct Target: Decodable {
        var id: String
        var source: String
        var page: Int
        /// x0, y0, x1, y1 in PDF points from the top-left of the crop box.
        var region: [Double]
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 7, let dpi = Double(arguments[2]), let pixels = Int(arguments[3]),
              ["ocr", "no-ocr"].contains(arguments[5]) else {
            throw ConversionError.invalidOptions(
                "usage: probe targets.json DPI MAXIMUM_PIXELS QUALITY[,QUALITY...] ocr|no-ocr new-output-directory")
        }
        let qualities = try arguments[4].split(separator: ",").map { part -> Double in
            guard let quality = Double(part), quality.isFinite, (0...1).contains(quality) else {
                throw ConversionError.invalidOptions("JPEG quality must be in 0...1")
            }
            return quality
        }
        let recognize = arguments[5] == "ocr"
        let targets = try JSONDecoder().decode([Target].self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        var options = ConversionOptions()
        options.rasterDPI = dpi
        options.maximumRasterPixels = pixels
        guard (72...600).contains(dpi), (1...48_000_000).contains(pixels) else {
            throw ConversionError.invalidOptions("unsupported raster settings")
        }
        let output = URL(fileURLWithPath: arguments[6], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        var records: [[String: Any]] = []
        for target in targets {
            let region = try autoreleasepool { () throws -> [(kind: String, rect: CGRect, page: PDFPage)] in
                guard let document = PDFDocument(url: URL(fileURLWithPath: target.source)),
                      let page = document.page(at: target.page - 1), target.region.count == 4 else {
                    throw ConversionError.unreadablePDF
                }
                let bounds = page.bounds(for: .cropBox)
                let r = target.region
                guard r.allSatisfy(\.isFinite), r[0] >= 0, r[1] >= 0, r[2] > r[0], r[3] > r[1],
                      r[2] <= bounds.width, r[3] <= bounds.height else {
                    throw ConversionError.invalidOptions("invalid review region for \(target.id)")
                }
                let crop = CGRect(x: bounds.minX + r[0], y: bounds.maxY - r[3], width: r[2] - r[0], height: r[3] - r[1])
                return [("page", bounds, page), ("region", crop, page)]
            }
            for (kind, rect, page) in region {
                var files: [(quality: Double?, url: URL, record: [String: Any])] = []
                try autoreleasepool {
                    let began = Date()
                    let image = try PageRasterizer.image(page: page, rect: rect, options: options,
                                                         applyRotation: kind == "page")
                    let renderingSeconds = Date().timeIntervalSince(began)
                    let encodings: [(String, Double?, ConversionOptions.ImageEncoding)] =
                        [("png", nil, .png)] + qualities.map { ("jpeg\(Int(($0 * 100).rounded()))", $0, .jpeg(quality: $0)) }
                    for (format, quality, encoding) in encodings {
                        let base = output.appendingPathComponent("\(target.id)-\(kind)-\(format)")
                        let beganEncoding = Date()
                        let encoded = try PageRasterizer.encode(image, at: base, encoding: encoding)
                        let record: [String: Any] = [
                            "target": target.id, "page": target.page, "kind": kind, "encoding": format,
                            "jpegQuality": quality as Any, "requestedDPI": dpi, "maximumRasterPixels": pixels,
                            "rect": [rect.minX, rect.minY, rect.width, rect.height],
                            "width": image.width, "height": image.height,
                            "effectiveDPIX": Double(image.width) * 72 / rect.width,
                            "effectiveDPIY": Double(image.height) * 72 / rect.height,
                            "renderingSeconds": renderingSeconds,
                            "encodingSeconds": Date().timeIntervalSince(beganEncoding),
                            "file": encoded.url.lastPathComponent,
                            "bytes": try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize!,
                        ]
                        files.append((quality, encoded.url, record))
                    }
                }
                for var file in files {
                    if recognize && kind == "region" {
                        file.record["ocr"] = await recognizeText(in: file.url)
                    }
                    records.append(file.record)
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// Recognizes the encoded file exactly as a reader or the converter would decode it.
    static func recognizeText(in url: URL) async -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return ["status": "failed", "description": "undecodable image"]
        }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        let language = Locale.Language(identifier: "en")
        if request.supportedRecognitionLanguages.contains(language) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        let began = Date()
        do {
            let observations = try await request.perform(on: image, orientation: nil)
            return ["status": "succeeded", "seconds": Date().timeIntervalSince(began),
                    "lines": observations.first?.document.text.lines.map(\.transcript) ?? []]
        } catch {
            let error = error as NSError
            return ["status": "failed", "domain": error.domain, "code": error.code,
                    "description": error.localizedDescription]
        }
    }
}
