import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

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
            context.concatenate(reference.getDrawingTransform(.cropBox,
                rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0,
                preserveAspectRatio: true))
        } else {
            context.scaleBy(x: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height)
            context.translateBy(x: -rect.minX, y: -rect.minY)
        }
        context.drawPDFPage(reference)
        for annotation in page.annotations where annotation.shouldDisplay {
            annotation.draw(with: .cropBox, in: context)
        }
        guard let image = context.makeImage() else {
            throw ConversionError.resourceLimit("raster creation failed")
        }
        return image
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
