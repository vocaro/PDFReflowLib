import CoreGraphics
import Foundation
import PDFKit

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let pages = args[2].split(separator: ",").compactMap { Int($0) }
let doc = PDFDocument(url: url)!
func fmt(_ r: CGRect, _ b: CGRect) -> String {
    String(format: "%.1f\t%.1f\t%.1f\t%.1f", r.minX - b.minX, b.maxY - r.maxY, r.maxX - b.minX, b.maxY - r.minY)
}
for p in pages {
    let page = doc.page(at: p - 1)!
    let ref = page.pageRef!
    let bounds = page.bounds(for: .cropBox)
    let g = GraphicsReader.read(ref)
    let lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: false)
    for r in g.inlineImages { print("\(p)\tE\t" + fmt(r, bounds)) }
    let body = LayoutReconstructor.bodySize(lines)
    for l in lines where LayoutReconstructor.isProseRow(l, in: lines, body: body) { print("\(p)\tP\t" + fmt(l.rect, bounds)) }
    for l in lines where !LayoutReconstructor.isProseRow(l, in: lines, body: body) { print("\(p)\tN\t" + fmt(l.rect, bounds)) }
    guard let ink = ScanEvidenceRegions.inkMap(ref, bounds: bounds) else { print("\(p)\tno ink"); continue }
    guard let grown = ScanEvidenceRegions.regions(evidence: g.inlineImages, lines: lines, bounds: bounds, ink: ink) else {
        print("\(p)\tFALLBACK"); continue
    }
    for r in grown { print("\(p)\tG\t" + fmt(r, bounds)) }
    let content = PageContent(number: p, bounds: bounds, lines: lines, graphics: grown)
    for r in LayoutReconstructor.graphicsWithLabels(content) { print("\(p)\tC\t" + fmt(r, bounds)) }
}
