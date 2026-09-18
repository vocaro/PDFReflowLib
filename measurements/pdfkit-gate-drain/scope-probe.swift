// Discriminating probe for #21: which work on other threads lets a serialized (locked)
// attributed extraction abort? Apple SDKs only.
//   xcrun swiftc -O -swift-version 5 scope-probe.swift -o scope-probe
//   ./scope-probe untagged.pdf <mode> <iterations>      (fixture from check_pdfkit_concurrency.py)
// Every locked extraction opens its own document. Modes:
//   alone         one thread, extraction only (no other threads)
//   extract       8 threads, lock around extraction only (the library's gate before the drain)
//   extractdrain  8 threads, lock around extraction plus an autorelease drain inside the lock;
//                 page and document released after unlocking
//   drainrelease  as extractdrain, with page and document also released inside the lock
//   all           8 threads, lock around the whole iteration (open, extract, drain, release)
// The rest run one locked extracting thread beside 7 threads doing, without the lock:
//   lifecycle     document opens and releases, no text
//   render        CGContext.drawPDFPage of the page
//   plain         PDFPage.string and plain selection strings
//   nsfont        NSFont(name:size:) and withSize(_:)
//   ctfont        CTFontCreateWithName, CTLineCreateWithAttributedString, CTLineDraw
//   annot         PDFKit-synthesized free-text and text-widget annotations drawn to a bitmap
// and, with the other threads' work under the lock: nsfontlocked (font made under the lock,
// released after it), ctfontlocked, annotlocked.
import Foundation
import PDFKit
import AppKit
import CoreText

let lock = NSLock()
let expected = ["Small heading", "First paragraph line", "second paragraph line."]

@inline(never) func extractText(_ page: PDFPage) -> Bool {
    guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return false }
    let lines = selection.selectionsByLine()
    var fonts = 0
    for line in lines {
        guard let attributed = line.attributedString else { return false }
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if value is NSFont { fonts += 1 }
        }
    }
    return lines.count == 3 && fonts >= 3
}

func open(_ url: URL) -> PDFPage? { PDFDocument(url: url)?.page(at: 0) }

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]), mode = args[2], iterations = Int(args[3])!
let threads = mode == "alone" ? 1 : 8
let group = DispatchGroup()
let stop = NSLock(); var stopped = false
var failures = 0
for index in 0..<threads {
    group.enter()
    Thread.detachNewThread {
        defer { group.leave() }
        let extractor = index == 0 || ["extract", "extractdrain", "drainrelease", "all"].contains(mode)
        for _ in 0..<iterations {
            if !extractor {
                stop.lock(); let done = stopped; stop.unlock()
                if done { return }
            }
            autoreleasepool {
                switch (mode, extractor) {
                case ("all", _):
                    lock.lock(); defer { lock.unlock() }
                    autoreleasepool { if let page = open(url), !extractText(page) { failures += 1 } }
                case ("extractdrain", _):
                    // Autoreleased extraction results drain inside the lock; the page and its
                    // document are released after unlocking.
                    guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return }
                    lock.lock()
                    autoreleasepool { if !extractText(page) { failures += 1 } }
                    lock.unlock()
                    withExtendedLifetime((document, page)) {}
                case ("drainrelease", _):
                    // As above, but the page and document are released inside the lock too.
                    var document = PDFDocument(url: url), page = document?.page(at: 0)
                    lock.lock()
                    autoreleasepool { if let page, !extractText(page) { failures += 1 } }
                    autoreleasepool { page = nil; document = nil }
                    lock.unlock()
                    withExtendedLifetime((document, page)) {}
                case (_, true):
                    guard let page = open(url) else { return }
                    lock.lock(); defer { lock.unlock() }
                    if mode.hasSuffix("locked") {
                        autoreleasepool { if !extractText(page) { failures += 1 } }
                    } else if !extractText(page) { failures += 1 }
                case ("lifecycle", false):
                    if let page = open(url) { _ = page.bounds(for: .cropBox) }
                case ("render", false):
                    guard let page = open(url), let cg = page.pageRef else { return }
                    let context = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.scaleBy(x: 0.5, y: 0.5)
                    context.drawPDFPage(cg)
                case ("nsfont", false):
                    // Unrelated font objects created and released without the lock.
                    let size = CGFloat(Int.random(in: 6...40))
                    if let font = NSFont(name: "Helvetica", size: size) { _ = font.withSize(size * 1.5) }
                case ("ctfont", false):
                    // Test-style CoreText drawing: a CTFont line drawn into a bitmap, no lock.
                    let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(Int.random(in: 6...40)), nil)
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Probe text",
                        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                    let context = CGContext(data: nil, width: 200, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    CTLineDraw(line, context)
                case ("nsfontlocked", false):
                    // Fixture-style: a font made under the lock, carried in an attributed string
                    // and released after unlocking.
                    lock.lock()
                    let size = CGFloat(Int.random(in: 6...40))
                    let held = NSAttributedString(string: "Fixture", attributes: [.font: NSFont(name: "Helvetica", size: size)!])
                    lock.unlock()
                    withExtendedLifetime(held) {}
                case ("ctfontlocked", false):
                    // Synthetic-PDF-style CoreText drawing entirely under the lock.
                    lock.lock(); defer { lock.unlock() }
                    autoreleasepool {
                        let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(Int.random(in: 6...40)), nil)
                        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Probe text",
                            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                        let context = CGContext(data: nil, width: 200, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        CTLineDraw(line, context)
                    }
                case ("annot", false), ("annotlocked", false):
                    // A PDFKit-synthesized free-text annotation drawn into a bitmap, as the rasterizer
                    // draws a page's annotations.
                    guard let page = open(url) else { return }
                    let annotation = PDFAnnotation(bounds: CGRect(x: 40, y: 40, width: 200, height: 40), forType: .freeText, withProperties: nil)
                    annotation.contents = "Annotation text"
                    let field = PDFAnnotation(bounds: CGRect(x: 40, y: 100, width: 200, height: 30), forType: .widget, withProperties: nil)
                    field.widgetFieldType = .text
                    field.widgetStringValue = "Field value"
                    page.addAnnotation(annotation)
                    page.addAnnotation(field)
                    let context = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    if mode == "annotlocked" { lock.lock() }
                    for a in page.annotations { a.draw(with: .cropBox, in: context) }
                    if mode == "annotlocked" { lock.unlock() }
                case ("plain", false):
                    // Plain-text PDFKit extraction without the lock.
                    if let page = open(url) { _ = page.string; _ = page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine().map(\.string) }
                default: break
                }
            }
        }
        if extractor { stop.lock(); stopped = true; stop.unlock() }
    }
}
group.wait()
print("done \(mode) failures=\(failures)")
