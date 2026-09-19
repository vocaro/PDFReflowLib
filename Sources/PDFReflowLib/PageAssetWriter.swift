import Foundation
import PDFKit

/// Renders page regions into the workspace's asset directory and keeps the asset registry and
/// the uncompressed image-byte budget for one conversion.
final class PageAssetWriter {
    private(set) var assets: [ReflowDocument.Asset] = []
    private var imageBytes: Int64 = 0
    private let workspace: URL
    private let options: ConversionOptions

    init(workspace: URL, options: ConversionOptions) {
        self.workspace = workspace
        self.options = options
    }

    /// Saves one region of `page` and returns its asset identifier. Full-page images use the
    /// full-page encoding; `rotate` applies the page's own rotation.
    func save(page: PDFPage, rect: CGRect, fullPage: Bool = false, rotate: Bool = false) throws -> String {
        try Task.checkCancellation()
        let assetID = "image-\(assets.count + 1)"
        let encoded = try autoreleasepool {
            let image = try PageRasterizer.image(page: page, rect: rect, options: options, applyRotation: rotate)
            return try PageRasterizer.encode(image, at: workspace.appendingPathComponent("assets/" + assetID),
                encoding: fullPage ? options.fullPageImageEncoding : options.regionImageEncoding)
        }
        imageBytes += Int64(try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard imageBytes <= options.maximumOutputBytes else { throw ConversionError.resourceLimit("image output bytes") }
        assets.append(.init(id: assetID, fileURL: encoded.url, format: encoded.format))
        return assetID
    }
}
