import CoreGraphics
import Foundation

/// Where each glyph of a page stands: its advance along the baseline, its baseline and its size,
/// placed from the fonts' own widths, the text state's spacing and scale, and the text and current
/// transformation matrices (#302).
///
/// This reads geometry, not characters, so it needs nothing of a font but its `Widths`: a TeX
/// font with a built-in encoding and no `ToUnicode` map, which `NativeSpacingReader` cannot read
/// (every page of DASC), is placed exactly. Which character a glyph is stays PDFKit's to say.
/// A page is read whole or not at all: a composite or Type3 font, a font without widths, text
/// drawn turned, or a Form XObject whose text this walk does not follow leaves glyphs it cannot
/// place, and a reader that relies on seeing every glyph near a mark must see them all.
enum GlyphPlacementReader {
    /// One glyph the content stream draws, in page space. A space (code 32) draws nothing.
    struct Glyph: Equatable {
        var minX: CGFloat
        var maxX: CGFloat
        var baseline: CGFloat
        var size: CGFloat
        var inked = true
        var center: CGPoint { CGPoint(x: (minX + maxX) / 2, y: baseline + size * 0.25) }
    }

    /// Every glyph the page's own content stream draws, or nil where one cannot be placed.
    static func read(_ page: CGPDFPage) -> [Glyph]? {
        let visitor = Visitor()
        var options = ContentStreamWalk.Options()
        options.operators = ["Tc", "Tw", "Tz", "Ts", "Do"]
        options.selectsFonts = true
        options.moveAndShow = .invalidate
        guard ContentStreamWalk.scan(page, options: options, visitor: visitor) else { return nil }
        return visitor.glyphs
    }

    /// Places each glyph a simple font draws by its width, the text state's spacing and scale,
    /// and the text and current transformation matrices.
    private final class Visitor: ContentStreamVisitor {
        struct Metrics { var widths: [UInt8: CGFloat]; var missing: CGFloat }
        var font: Metrics?
        var size: CGFloat = 0
        var characterSpacing: CGFloat = 0, wordSpacing: CGFloat = 0, scale: CGFloat = 1, rise: CGFloat = 0
        var saved: [(Metrics?, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = []
        /// The text matrix, which a show advances, as against the walk's line matrix.
        var text = CGAffineTransform.identity
        var continuing = false
        var fonts: [Int: Metrics?] = [:]
        var glyphs: [Glyph] = []

        func saveState() { saved.append((font, size, characterSpacing, wordSpacing, scale, rise)) }
        func restoreState() {
            guard let state = saved.popLast() else { return }
            (font, size, characterSpacing, wordSpacing, scale, rise) = state
        }
        func beginText(_ walk: ContentStreamWalk) { text = .identity; continuing = false }

        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            self.size = size
            guard let resource, let dict = CGPDFObjects.dictionary(of: resource) else { font = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = fonts[id] { font = cached; return }
            guard fonts.count < 256 else { walk.invalid = true; return }
            font = Self.metrics(dict)
            fonts[id] = font
        }

        static func metrics(_ dict: CGPDFDictionaryRef) -> Metrics? {
            guard let kind = CGPDFObjects.name(dict, "Subtype"), ["Type1", "MMType1", "TrueType"].contains(kind),
                  let first = CGPDFObjects.integer(dict, "FirstChar"), (0...255).contains(first),
                  let array = CGPDFObjects.array(dict, "Widths"), CGPDFArrayGetCount(array) <= 256 else { return nil }
            var widths: [UInt8: CGFloat] = [:]
            for index in 0..<CGPDFArrayGetCount(array) where first + index <= 255 {
                var width: CGPDFReal = 0
                guard CGPDFArrayGetNumber(array, index, &width), width.isFinite, width >= 0 else { return nil }
                widths[UInt8(first + index)] = width / 1000
            }
            var missing: CGPDFReal = 0
            if let descriptor = CGPDFObjects.dictionary(dict, "FontDescriptor"),
               !CGPDFDictionaryGetNumber(descriptor, "MissingWidth", &missing) { missing = 0 }
            return Metrics(widths: widths, missing: missing.isFinite && missing >= 0 ? missing / 1000 : 0)
        }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            if op == "Do" {
                // A Form's text is not followed, so a page that draws one is not accounted for.
                guard let name = ContentStreamWalk.popName(scanner),
                      let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                      let stream = CGPDFObjects.stream(of: object), let dict = CGPDFStreamGetDictionary(stream),
                      CGPDFObjects.name(dict, "Subtype") == "Image" else { walk.invalid = true; return }
                return
            }
            guard let value = ContentStreamWalk.numbers(scanner, 1)?.first else { walk.invalid = true; return }
            switch op {
            case "Tc": characterSpacing = value
            case "Tw": wordSpacing = value
            case "Tz": scale = value / 100
            default: rise = value
            }
        }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard let font, size > 0 else { walk.invalid = true; return }
            if walk.positioned { text = walk.lineMatrix } else if !continuing { walk.invalid = true; return }
            let transform = text.concatenating(walk.matrix)
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0,
                  transform.tx.isFinite, transform.ty.isFinite else { walk.invalid = true; return }
            var cursor: CGFloat = 0
            for argument in arguments {
                switch argument {
                case .adjustment(let amount):
                    cursor -= amount / 1000 * size * scale
                case .string(let string):
                    guard let bytes = CGPDFStringGetBytePtr(string) else { walk.invalid = true; return }
                    for index in 0..<CGPDFStringGetLength(string) {
                        let code = bytes[index]
                        let advance = (font.widths[code] ?? font.missing) * size
                        let start = CGPoint(x: cursor, y: rise).applying(transform)
                        let end = CGPoint(x: cursor + advance * scale, y: rise).applying(transform)
                        guard glyphs.count < 100_000 else { walk.invalid = true; return }
                        glyphs.append(Glyph(minX: start.x, maxX: end.x, baseline: start.y, size: size * transform.d,
                                            inked: code != 32))
                        cursor += (advance + characterSpacing + (code == 32 ? wordSpacing : 0)) * scale
                    }
                case .other:
                    walk.invalid = true; return
                }
            }
            text = text.translatedBy(x: cursor, y: 0)
            continuing = true
        }
    }
}
