import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let pages = args[2].split(separator: ",").compactMap { Int($0) }
let out = args.count > 3 ? args[3] : nil
let doc = PDFDocument(url: url)!
for p in pages {
    let page = doc.page(at: p - 1)!
    let ref = page.pageRef!
    let bounds = page.bounds(for: .cropBox)
    let g = GraphicsReader.read(ref)
    print("page \(p) unsupported=\(g.unsupported) invisible=\(g.hasInvisibleText) onlyInvisible=\(g.hasOnlyInvisibleText) regions=\(g.regions.count) paints=\(g.paints.count) inline=\(g.inlineImages.count)")
    for pt in g.paints where !g.inlineImages.contains(pt.rect) {
        let r = pt.rect
        print(String(format: "  paint frame=%d x %.1f-%.1f top %.1f-%.1f", pt.frame ? 1 : 0, r.minX, r.maxX, bounds.maxY - r.maxY, bounds.maxY - r.minY))
    }
    for r in g.inlineImages {
        print(String(format: "  EI x %.1f-%.1f top %.1f-%.1f", r.minX, r.maxX, bounds.maxY - r.maxY, bounds.maxY - r.minY))
    }
    if let out {
        let scale: CGFloat = 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.drawPDFPage(ref)
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/cg-\(p).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
