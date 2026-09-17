import Foundation
import PDFKit
import CoreGraphics

// For every page with annotations: pixels (72 DPI) the PDFKit annotation drawing changes against
// the page drawn without annotations, as the pipeline's page image draws them; and per annotation,
// how many of its own pixels it inks when drawn alone on transparency.
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
let path = CommandLine.arguments[1]
let verbose = CommandLine.arguments.count > 2
let doc = PDFDocument(url: URL(fileURLWithPath: path))!
var totals: [String: (count: Int, inking: Int)] = [:]
var pagesChanged = 0, pagesWith = 0
for i in 0..<doc.pageCount {
    let page = doc.page(at: i)!
    let annots = page.annotations
    if annots.isEmpty { continue }
    pagesWith += 1
    let rect = page.bounds(for: .cropBox)
    let w = Int(rect.width.rounded(.up)), h = Int(rect.height.rounded(.up))
    func render(_ withAnnots: Bool) -> [UInt8] {
        let c = context(w, h)
        c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.translateBy(x: -rect.minX, y: -rect.minY)
        c.saveGState(); c.drawPDFPage(page.pageRef!); c.restoreGState()
        if withAnnots {
            for a in annots where a.shouldDisplay {
                c.saveGState(); c.concatenate(page.transform(for: .cropBox).inverted())
                a.draw(with: .cropBox, in: c); c.restoreGState()
            }
        }
        let p = c.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }
    let base = render(false), with = render(true)
    var diff = 0
    for k in stride(from: 0, to: base.count, by: 4) {
        if abs(Int(base[k]) - Int(with[k])) > 8 || abs(Int(base[k+1]) - Int(with[k+1])) > 8 || abs(Int(base[k+2]) - Int(with[k+2])) > 8 { diff += 1 }
    }
    if diff > 0 { pagesChanged += 1 }
    var perPage: [String: (Int, Int)] = [:]
    for a in annots {
        let c = context(w, h)
        c.translateBy(x: -rect.minX, y: -rect.minY)
        if a.shouldDisplay { c.concatenate(page.transform(for: .cropBox).inverted()); a.draw(with: .cropBox, in: c) }
        let p = c.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var ink = 0
        for k in stride(from: 3, to: w * h * 4, by: 4) where p[k] > 8 { ink += 1 }
        let key = (a.type ?? "?") + (a.widgetFieldType.rawValue.isEmpty ? "" : "/" + a.widgetFieldType.rawValue)
        totals[key, default: (0, 0)].count += 1
        if ink > 0 { totals[key, default: (0, 0)].inking += 1 }
        perPage[key, default: (0, 0)].0 += 1
        if ink > 0 { perPage[key, default: (0, 0)].1 += 1 }
        if verbose && (ink > 0 || a.type == "Widget") {
            let under = page.selection(for: a.bounds)?.string?.replacingOccurrences(of: "\n", with: " | ") ?? ""
            print("  p\(i+1) \(key) display=\(a.shouldDisplay) ink=\(ink) widgetValue=\(a.widgetStringValue ?? "") state=\(a.buttonWidgetState.rawValue) under=\(under.prefix(60)) bounds=\(a.bounds)")
        }
    }
    print("p\(i+1): diffPixels=\(diff) " + perPage.map { "\($0.key) \($0.value.1)/\($0.value.0) ink" }.sorted().joined(separator: ", "))
}
print("SUMMARY pagesWithAnnots=\(pagesWith) pagesVisiblyChanged=\(pagesChanged) " + totals.map { "\($0.key): \($0.value.inking)/\($0.value.count) ink" }.sorted().joined(separator: ", "))
