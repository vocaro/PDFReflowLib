import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

private extension PDFAnnotation {
    /// Whether a reader of the source page would see this annotation, and so whether a page image
    /// standing in for that page should draw it (#170).
    ///
    /// PDFKit's `shouldDisplay` is its own display switch and does not reflect the annotation's
    /// `/F` flags, so a Hidden or NoView annotation — a field a producer filled and chose not to
    /// show, a review layer left in the file — is drawn into the image although no reader of the
    /// PDF ever sees it. Bit 2 is Hidden and bit 6 NoView (PDF 32000-1 table 165); NoView means
    /// "do not draw on screen but do print", and a page image is the screen.
    var isDrawnForReading: Bool {
        guard shouldDisplay else { return false }
        guard let flags = value(forAnnotationKey: .flags) as? NSNumber else { return true }
        return flags.intValue & ((1 << 1) | (1 << 5)) == 0
    }
}

enum PageRasterizer {
    static func image(page: PDFPage, rect: CGRect, options: ConversionOptions,
                      applyRotation: Bool = false) throws -> CGImage {
        guard let reference = page.pageRef, rect.isFinite, rect.width > 0, rect.height > 0 else {
            throw ConversionError.resourceLimit("invalid page geometry")
        }
        let turned = applyRotation && abs(page.rotation % 180) == 90
        let size = turned ? CGSize(width: rect.height, height: rect.width) : rect.size
        let scale = min(options.rasterDPI / 72,
                        sqrt(Double(options.maximumRasterPixels) / (size.width * size.height)))
        let width = max(1, Int(floor(size.width * scale)))
        let height = max(1, Int(floor(size.height * scale)))
        guard width <= options.maximumRasterPixels / height else {
            throw ConversionError.resourceLimit("raster aspect ratio exceeds pixel budget")
        }
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.resourceLimit("raster allocation failed")
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if applyRotation {
            // Ask Core Graphics for crop/rotation in page units, then scale to pixels
            // explicitly. getDrawingTransform can leave larger destinations at 1:1 scale.
            context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
            context.concatenate(reference.getDrawingTransform(.cropBox,
                rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        } else {
            context.scaleBy(x: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height)
            context.translateBy(x: -rect.minX, y: -rect.minY)
        }
        context.saveGState()
        context.drawPDFPage(reference)
        context.restoreGState()
        for annotation in page.annotations where annotation.isDrawnForReading {
            // PDFKit annotation drawing applies the page's crop/rotation itself, unlike
            // drawPDFPage. Undo that extra mapping so both use the same source coordinates.
            context.saveGState()
            context.concatenate(page.transform(for: .cropBox).inverted())
            annotation.draw(with: .cropBox, in: context)
            context.restoreGState()
        }
        guard let image = context.makeImage() else {
            throw ConversionError.resourceLimit("raster creation failed")
        }
        return image
    }

    /// Returns the actual format and file. At most one raster and two encoded files are live.
    static func encode(_ image: CGImage, at baseURL: URL,
                       encoding: ConversionOptions.ImageEncoding) throws -> (url: URL, format: ReflowDocument.Asset.Format) {
        guard encoding.isValid else { throw ConversionError.invalidOptions("JPEG quality must be finite and in 0...1") }
        let png = baseURL.appendingPathExtension("png"), jpeg = baseURL.appendingPathExtension("jpg")
        switch encoding {
        case .png:
            try write(image, to: png)
            return (png, .png)
        case .jpeg(let quality):
            try write(image, to: jpeg, jpegQuality: quality)
            return (jpeg, .jpeg)
        case .smallest(let quality):
            try write(image, to: png)
            try Task.checkCancellation()
            try write(image, to: jpeg, jpegQuality: quality)
            let pngBytes = try png.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let jpegBytes = try jpeg.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if jpegBytes < pngBytes {
                try FileManager.default.removeItem(at: png)
                return (jpeg, .jpeg)
            }
            try FileManager.default.removeItem(at: jpeg)
            return (png, .png)
        }
    }

    static func write(_ image: CGImage, to url: URL, jpegQuality: Double? = nil) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            (jpegQuality == nil ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties = jpegQuality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
