import CoreGraphics
import Foundation

/// Recognizes a page that shows nothing, so it contributes only its page boundary rather than an
/// all-white page image (#132; 9/11 pages 2, 4, 8, 10, 12, 162, 342 and 466, Fed pages 2, 23, 49,
/// 65, 87 and 134, whose content streams paint nothing).
///
/// Two kinds of evidence must agree. The page's own drawing must place no mark the reader can
/// see: no extracted text line, no text show, no painted footprint (image, inline image, shading
/// or non-white path), nothing unsupported or unplaceable, and no annotation. Then the rendered
/// crop box, drawn at one pixel per point in device RGB over white, must hold no pixel with any
/// channel below 254 (`minimumChannel`): one level of rounding, and nothing else. At that scale
/// a black hairline a quarter of a point wide darkens its pixels by about 64 levels and a 5% gray
/// tint by about 13, so faint real content is never taken for paper. A scan of an empty sheet is an
/// image and keeps its page. The render is the decisive evidence: marks the reader does not
/// count (white fills are not footprints) still fail it when they show.
enum BlankPageDetector {
    /// The lowest channel value, 0–255, that a blank page's rendered pixels may hold.
    static let minimumChannel: UInt8 = 254

    /// Whether the drawing evidence alone permits a blank page; the render must still confirm it.
    static func drawsNothing(lines: [TextLine], graphics: GraphicsReader.Result, annotations: Int) -> Bool {
        lines.isEmpty && annotations == 0 && !graphics.unsupported && !graphics.textPlacementUnsupported
            && !graphics.hasInvisibleText && graphics.regions.isEmpty && graphics.paints.isEmpty
            && graphics.textShows.isEmpty && graphics.slantedShows.isEmpty && graphics.inlineImages.isEmpty
    }

    /// Whether the page's crop box renders as unmarked white paper.
    static func rendersWhite(_ page: CGPDFPage, bounds: CGRect) -> Bool {
        let width = Int(bounds.width.rounded(.up)), height = Int(bounds.height.rounded(.up))
        guard bounds.isFinite, width > 0, height > 0, width * height <= 16_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        guard let data = context.data else { return false }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            if bytes[offset] < minimumChannel || bytes[offset + 1] < minimumChannel || bytes[offset + 2] < minimumChannel {
                return false
            }
        }
        return true
    }
}
