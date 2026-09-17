import CoreGraphics
import Foundation
import PDFKit

let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let page = doc.page(at: 4)!
let ref = page.pageRef!
let bounds = page.bounds(for: .cropBox)
for scale in [2, 3, 4] {
    for quality in [CGInterpolationQuality.default, .none, .low, .high] {
        let w = Int(bounds.width) * scale, h = Int(bounds.height) * scale
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.interpolationQuality = quality
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.drawPDFPage(ref)
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
        // Right axis of Figure 4: x 465-470 pt, top-left y 490-640 pt. Top frame: y 482-490, x 320-460.
        func darkRows(x0: Int, x1: Int, y0: Int, y1: Int, threshold: UInt8) -> (Int, Int) {
            var rows = 0, cols = Set<Int>()
            for y in (y0 * scale)..<(y1 * scale) {
                var any = false
                for x in (x0 * scale)..<(x1 * scale) where px[y * w + x] < threshold { any = true; cols.insert(x) }
                if any { rows += 1 }
            }
            return (rows, (y1 - y0) * scale)
        }
        let axis = darkRows(x0: 462, x1: 472, y0: 500, y1: 640, threshold: 160)
        var colsTop = 0
        for y in (465 * scale)..<(500 * scale) {
            var n = 0
            for x in (330 * scale)..<(450 * scale) where px[y * w + x] < 160 { n += 1 }
            colsTop = max(colsTop, n)
        }
        print("scale \(scale) q \(quality.rawValue): right-axis rows dark \(axis.0)/\(axis.1), best row dark cols y465-500 \(colsTop)/\(120 * scale)")
    }
}
