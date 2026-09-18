import AppKit
import CoreText
import Foundation

// usage: swiftc -O ligature-render.swift -o <scratch>/ligature-render && <scratch>/ligature-render <out.png>
// Draws `Diﬀerent signs` (U+FB00, as the EPUB carries it) above `Different signs` (spelled out) in
// each family, the way a reader lays out a run: CoreText's font fallback supplies any character the
// family lacks. Prints, per family and form, the widest run of blank columns inside `Di?erent`
// (pixels at 48 pt), so a fallback glyph's side bearings show as a gap wider than any letter joint.
let families = ["Charter", "Times New Roman", "Avenir Next", ".AppleSystemUIFont", "Iowan Old Style", "Georgia", "Palatino"]
let size: CGFloat = 48, rowHeight: CGFloat = 70, width = 900
let forms = ["Di\u{FB00}erent", "Different"]
let height = Int(rowHeight) * families.count * forms.count + 20
let space = CGColorSpaceCreateDeviceGray()
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { exit(1) }
context.setFillColor(gray: 1, alpha: 1)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
var y = CGFloat(height) - rowHeight
for family in families {
    for form in forms {
        let font = CTFontCreateWithName(family as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: form, attributes: [.font: font]))
        // Measure in a scratch bitmap so each row is analysed alone.
        let w = 600, h = Int(rowHeight)
        guard let row = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: space,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { exit(1) }
        row.setFillColor(gray: 1, alpha: 1); row.fill(CGRect(x: 0, y: 0, width: w, height: h))
        row.textPosition = CGPoint(x: 10, y: 18); CTLineDraw(line, row)
        let pixels = row.data!.assumingMemoryBound(to: UInt8.self)
        var inked = [Bool](repeating: false, count: w)
        for x in 0..<w { for yy in 0..<h where pixels[yy * w + x] < 128 { inked[x] = true; break } }
        let first = inked.firstIndex(of: true) ?? 0, last = inked.lastIndex(of: true) ?? 0
        var widest = 0, run = 0
        for x in first...last { if inked[x] { run = 0 } else { run += 1; widest = max(widest, run) } }
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let fonts = runs.map { run -> String in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let used = attributes[kCTFontAttributeName] as! CTFont
            return CTFontCopyPostScriptName(used) as String
        }
        print("\(family)\t\(form == forms[0] ? "U+FB00" : "letters")\twidestInnerGapPx=\(widest)\truns=\(fonts.joined(separator: ","))")
        context.textPosition = CGPoint(x: 10, y: y + 18)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "\(form)   \(family)", attributes: [.font: CTFontCreateWithName(family as CFString, size * 0.6, nil)])), context)
        y -= rowHeight
    }
}
if CommandLine.arguments.count > 1, let image = context.makeImage() {
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
