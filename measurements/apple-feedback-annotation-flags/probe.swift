// Standalone PDFKit annotation-flag probe. Apple SDKs only; it writes the PDF it tests, so it
// needs no input file.
//
//   xcrun swiftc -O probe.swift -o annotation-flags-probe && ./annotation-flags-probe
//
// It builds one page carrying four identical square annotations that differ only in their /F
// flag bits, reopens the file, and reports for each what PDFKit says and what PDFKit draws.
import AppKit
import Foundation
import PDFKit

// PDF 32000-1:2008 table 165: annotation flags.
let cases: [(name: String, flags: Int)] = [
    ("none", 0), ("Hidden (bit 2)", 2), ("NoView (bit 6)", 32), ("Print (bit 3)", 4),
]

let page = PDFPage()
page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 200), for: .mediaBox)
for (index, item) in cases.enumerated() {
    let bounds = CGRect(x: 20, y: 20 + CGFloat(index) * 40, width: 160, height: 30)
    let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
    annotation.interiorColor = .black
    annotation.color = .black
    annotation.setValue(item.flags, forAnnotationKey: .flags)
    page.addAnnotation(annotation)
}
let document = PDFDocument()
document.insert(page, at: 0)
let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("annotation-flags.pdf")
guard document.write(to: url) else { fputs("write failed\n", stderr); exit(1) }

guard let reopened = PDFDocument(url: url), let subject = reopened.page(at: 0) else {
    fputs("reopen failed\n", stderr); exit(1)
}
print("Wrote \(url.path)")
print(String(format: "%-16s %-8s %-14s %s", ("flags" as NSString).utf8String!,
             ("/F" as NSString).utf8String!, ("shouldDisplay" as NSString).utf8String!,
             ("dark pixels drawn" as NSString).utf8String!))

/// Dark pixels in the horizontal band a given annotation occupies, in a page rendered the way a
/// renderer renders it: into a bitmap context through `PDFPage.draw(with:to:)`.
func inkedRows(_ rect: CGRect, of page: PDFPage) -> Int {
    let scale = 2
    let width = 200 * scale, height = 200 * scale
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    page.draw(with: .mediaBox, to: context)
    guard let data = context.data else { return -1 }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var dark = 0
    for y in Int(rect.minY) * scale..<Int(rect.maxY) * scale {
        let row = height - 1 - y
        guard row >= 0, row < height else { continue }
        for x in Int(rect.minX) * scale..<Int(rect.maxX) * scale where x >= 0 && x < width {
            if pixels[(row * width + x) * 4] < 128 { dark += 1 }
        }
    }
    return dark
}

for (index, annotation) in subject.annotations.enumerated() {
    let flags = annotation.value(forAnnotationKey: .flags) as? Int ?? -1
    let name = index < cases.count ? cases[index].name : "?"
    let dark = inkedRows(annotation.bounds, of: subject)
    print(String(format: "%-16@ %-8d %-14@ %d", name as NSString, flags,
                 (annotation.shouldDisplay ? "true" : "false") as NSString, dark))
}
