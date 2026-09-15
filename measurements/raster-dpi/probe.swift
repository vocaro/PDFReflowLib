import Foundation
import PDFKit

// Development-only: compiled alongside the actual production rasterizer and value types.
// No PDF extraction, OCR, reconstruction, EPUB packaging or alternate raster implementation.
@main struct RasterDPIProbe {
    struct Target: Decodable {
        var id: String
        var source: String
        var page: Int
        // Normalized source crop-box coordinates, top-left origin.
        var region: [Double]
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5, let dpi = Double(arguments[2]),
              let pixels = Int(arguments[3]) else {
            throw ConversionError.invalidOptions("usage: probe targets.json DPI MAXIMUM_PIXELS new-output-directory")
        }
        let targets = try JSONDecoder().decode([Target].self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        var options = ConversionOptions()
        options.rasterDPI = dpi
        options.maximumRasterPixels = pixels
        guard [120.0, 180.0, 240.0].contains(dpi), [1_000_000, 12_000_000].contains(pixels) else {
            throw ConversionError.invalidOptions("unsupported experiment settings")
        }
        let output = URL(fileURLWithPath: arguments[4], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        var records: [[String: Any]] = []
        for target in targets {
            try autoreleasepool {
                guard let document = PDFDocument(url: URL(fileURLWithPath: target.source)),
                      let page = document.page(at: target.page - 1), page.rotation == 0,
                      target.region.count == 4 else { throw ConversionError.unreadablePDF }
                let bounds = page.bounds(for: .cropBox)
                let r = target.region
                guard r.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
                      r[2] > 0, r[3] > 0, r[0] + r[2] <= 1, r[1] + r[3] <= 1 else {
                    throw ConversionError.invalidOptions("invalid review crop")
                }
                let crop = CGRect(x: bounds.minX + r[0] * bounds.width,
                    y: bounds.maxY - (r[1] + r[3]) * bounds.height,
                    width: r[2] * bounds.width, height: r[3] * bounds.height)
                for (kind, rect) in [("page", bounds), ("region", crop)] {
                    try autoreleasepool {
                        let began = Date()
                        let image = try PageRasterizer.image(page: page, rect: rect, options: options,
                            applyRotation: kind == "page")
                        let renderingSeconds = Date().timeIntervalSince(began)
                        for (format, encoding) in [("png", ConversionOptions.ImageEncoding.png),
                            ("jpeg90", .jpeg(quality: 0.90))] {
                            let base = output.appendingPathComponent("\(target.id)-\(kind)-\(format)")
                            let beganEncoding = Date()
                            let encoded = try PageRasterizer.encode(image, at: base, encoding: encoding)
                            records.append([
                                "target": target.id, "page": target.page, "kind": kind,
                                "encoding": format, "requestedDPI": dpi, "maximumRasterPixels": pixels,
                                "rect": [rect.minX, rect.minY, rect.width, rect.height],
                                "width": image.width, "height": image.height,
                                "effectiveDPIX": Double(image.width) * 72 / rect.width,
                                "effectiveDPIY": Double(image.height) * 72 / rect.height,
                                "renderingSeconds": renderingSeconds,
                                "encodingSeconds": Date().timeIntervalSince(beganEncoding),
                                "file": encoded.url.lastPathComponent,
                                "bytes": try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                            ])
                        }
                    }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
