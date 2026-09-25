import Foundation
import PDFKit

/// Renders page regions into the workspace's asset directory and keeps the asset registry and
/// the uncompressed image-byte budget for one conversion.
final class PageAssetWriter {
    private(set) var assets: [ReflowDocument.Asset] = []
    private var imageBytes: Int64 = 0
    private let workspace: URL
    private let options: ConversionOptions
    /// The placed images of the page being written, read once for the run of crops it supplies
    /// (#251). Streams belong to that page and are dropped with it.
    private var placements: (page: CGPDFPage, images: [EmbeddedImageReader.Placement])?

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
        // A crop that is exactly one placed JPEG is written as that JPEG. The original stream is
        // what the page draws, at the resolution the source holds rather than the one the
        // renderer would pick, and it is usually smaller than a re-encode of a 180 DPI redraw
        // (#251). A full page is never one image in this sense: it carries the page's text.
        if !fullPage, let extracted = try extractedJPEG(for: rect, on: page, id: assetID) {
            return extracted
        }
        let encoded = try autoreleasepool {
            // `.automatic` is decided here, where the image's role and its page are known, from the
            // raster's own buffer: reading a finished `CGImage`'s pixels would copy them (#193).
            let requested = fullPage ? options.fullPageImageEncoding : options.regionImageEncoding
            var measured: ImageContentClassifier.Features?
            // An image whose only colour is its ground's tint is written as its lightness alone
            // (#216), taken from the same buffer while it is still the context's.
            var monochrome: CGImage?
            let image = try PageRasterizer.image(page: page, rect: rect, options: options, applyRotation: rotate,
                inspect: requested.isAutomatic ? { bytes, width, height, bytesPerRow in
                    let features = ImageContentClassifier.features(bytes, width: width, height: height,
                                                                    bytesPerRow: bytesPerRow)
                    measured = features
                    if ImageContentClassifier.isMonochrome(features) {
                        monochrome = PageRasterizer.grayscale(bytes, width: width, height: height,
                                                              bytesPerRow: bytesPerRow)
                    }
                } : nil)
            // Only a supplementary reference sits beside its page's reflowed text; a required
            // fallback (the rotated page) is the page's only copy and is judged like a crop.
            let encoding = ImageContentClassifier.resolve(requested, role: fullPage && !rotate ? .page : .region,
                pageDrawnFromImage: drawnFromImage,
                features: measured ?? ImageContentClassifier.features(of: image))
            return try PageRasterizer.encode(monochrome ?? image, at: workspace.appendingPathComponent("assets/" + assetID),
                encoding: encoding)
        }
        imageBytes += Int64(try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard imageBytes <= options.maximumOutputBytes else { throw ConversionError.resourceLimit("image output bytes") }
        assets.append(.init(id: assetID, fileURL: encoded.url, format: encoded.format))
        return assetID
    }

    /// Writes the crop's own embedded JPEG and registers it, or returns nil for the render.
    ///
    /// The content classifier is bypassed rather than consulted: an extracted original has
    /// already made the choice it would make. A client that named `.png` for regions asked for
    /// PNG and gets the render, and a rotated page is drawn rather than extracted, because the
    /// stream's pixels are not in the order the page shows them.
    private func extractedJPEG(for rect: CGRect, on page: PDFPage, id assetID: String) throws -> String? {
        guard options.regionImageEncoding != .png, page.rotation % 360 == 0,
              let reference = page.pageRef else { return nil }
        if placements?.page !== reference {
            placements = (reference, EmbeddedImageReader.placements(reference))
        }
        guard let images = placements?.images, !images.isEmpty else { return nil }
        // The budget sees the real size before the asset is committed: a scan extracted
        // losslessly can be larger than its render, and then the render is what fits.
        let remaining = options.maximumOutputBytes - imageBytes
        guard remaining > 0,
              let data = EmbeddedImageReader.extractableJPEG(for: rect, among: images,
                                                             maximumBytes: Int(min(remaining, Int64(Int.max)))) else {
            return nil
        }
        let url = workspace.appendingPathComponent("assets/" + assetID + ".jpg")
        try data.write(to: url)
        imageBytes += Int64(data.count)
        assets.append(.init(id: assetID, fileURL: url, format: .jpeg))
        return assetID
    }
}
