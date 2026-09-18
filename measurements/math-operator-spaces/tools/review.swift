import AppKit
import Foundation
import PDFKit

// usage: swiftc -O review.swift -o <scratch>/review && <scratch>/review <pdf> <rows.tsv> <out-prefix>
// rows.tsv: page, PDFKit line index, label (the candidate line). For each row, renders the source
// line's PDFKit rectangle at 200 dpi above its label, twelve rows to a sheet
// (<out-prefix>-NN.png), numbered in order, so each inserted space can be read against the ink.
let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let rows = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
    .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
let prefix = CommandLine.arguments[3]
let scale: CGFloat = 200 / 72, width = 1500, stripHeight = 150, perSheet = 12
var lineCache: [Int: [CGRect]] = [:]
func lineRects(_ number: Int) -> [CGRect] {
    if let cached = lineCache[number] { return cached }
    guard let page = document.page(at: number - 1), let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
    let rects = selection.selectionsByLine().compactMap { line -> CGRect? in
        guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let bounds = line.bounds(for: page)
        return !bounds.isNull && !bounds.isInfinite && bounds.width > 0 && bounds.height > 0 ? bounds : nil
    }
    lineCache[number] = rects
    return rects
}
for sheet in stride(from: 0, to: rows.count, by: perSheet) {
    let chunk = rows[sheet..<min(sheet + perSheet, rows.count)]
    let height = stripHeight * chunk.count
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (k, row) in chunk.enumerated() {
        let top = CGFloat(height - k * stripHeight)
        guard row.count >= 3, let number = Int(row[0]), let index = Int(row[1]), let page = document.page(at: number - 1) else { continue }
        let rects = lineRects(number)
        guard index < rects.count else { continue }
        let rect = rects[index].insetBy(dx: -4, dy: -3)
        // Draw the page so that `rect` lands in the strip's upper part, at `scale`.
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: top - 95, width: CGFloat(width), height: 95))
        context.translateBy(x: 10 - rect.minX * scale, y: top - 92 - rect.minY * scale)
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        let label = NSAttributedString(string: "\(sheet + k + 1). p\(number) l\(index): \(row[2])",
                                       attributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.systemBlue])
        context.textPosition = CGPoint(x: 10, y: top - 130)
        CTLineDraw(CTLineCreateWithAttributedString(label), context)
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1)); context.stroke(CGRect(x: 0, y: top - CGFloat(stripHeight), width: CGFloat(width), height: 1))
    }
    if let image = context.makeImage() {
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@-%02d.png", prefix, sheet / perSheet + 1)))
    }
}
