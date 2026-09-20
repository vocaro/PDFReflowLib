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
    ///
    /// `drawnFromImage` is the page's own evidence for `.automatic` (#193): a page whose type, if
    /// any, arrives inside an image, which makes a full-page raster of it a scan rather than
    /// born-digital text. It is ignored by every encoding that names its format.
    func save(page: PDFPage, rect: CGRect, fullPage: Bool = false, rotate: Bool = false,
              drawnFromImage: Bool = false) throws -> String {
        try Task.checkCancellation()
        let assetID = "image-\(assets.count + 1)"
        let encoded = try autoreleasepool {
            // `.automatic` is decided here, where the image's role and its page are known, from the
            // raster's own buffer: reading a finished `CGImage`'s pixels would copy them (#193).
            let requested = fullPage ? options.fullPageImageEncoding : options.regionImageEncoding
            var measured: ImageContentClassifier.Features?
            let image = try PageRasterizer.image(page: page, rect: rect, options: options, applyRotation: rotate,
                inspect: requested.isAutomatic ? { measured = ImageContentClassifier.features($0,
                    width: $1, height: $2, bytesPerRow: $3) } : nil)
            // Only a supplementary reference sits beside its page's reflowed text; a required
            // fallback (the rotated page) is the page's only copy and is judged like a crop.
            let encoding = ImageContentClassifier.resolve(requested, role: fullPage && !rotate ? .page : .region,
                pageDrawnFromImage: drawnFromImage,
                features: measured ?? ImageContentClassifier.features(of: image))
            return try PageRasterizer.encode(image, at: workspace.appendingPathComponent("assets/" + assetID),
                encoding: encoding)
        }
        imageBytes += Int64(try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard imageBytes <= options.maximumOutputBytes else { throw ConversionError.resourceLimit("image output bytes") }
        assets.append(.init(id: assetID, fileURL: encoded.url, format: encoded.format))
        return assetID
    }
}
