import CoreGraphics
import Foundation
import PDFKit

/// A short bar the page paints directly over or under one glyph is that glyph's overline or
/// underline, not a fraction bar and not a figure (#302).
///
/// DASC's page 9 writes a time window's two ends as `(a̱_k, ā_k)`. TeX draws `\overline{a}` and
/// `\underline{a}` as filled rules exactly the glyph's advance wide, so the text layer carries a
/// bare `a` for both, and a bar that short is no thin rule: each seeded a crop of its own, a
/// sliver of the page set between the paragraph's lines, while the line read `(a_k,a_k)`.
///
/// A fraction bar stands against each of its terms exactly as an accent does against its glyph:
/// the denominator hangs under it as an overlined glyph does, and the numerator stands on it as an
/// underlined glyph does. What tells them apart is the bar's other side. A fraction has a term
/// there; an accent has nothing within a numerator's or a denominator's reach. A radical's
/// vinculum over one glyph is an overline too, and is told apart by the radical sign that meets
/// its left end, hanging from the bar's own height.
///
/// Where the glyphs stand is read from the content stream by `GlyphPlacementReader` — each glyph's
/// advance, baseline and size, from the fonts' own widths — and a page it cannot place whole reads
/// no accents. Which character a glyph is comes from PDFKit, which decodes every font the page uses:
/// the text PDFKit selects under the bar's middle within the line, and the line's text up to it,
/// which must be the line's own. A line then carries the mark after that character, and the bar
/// seeds no crop. Anything the evidence does not settle leaves the bar as it was.
enum PaintedAccents {
    /// `ā`: the reading a macron gives an overlined letter.
    static let overline: Unicode.Scalar = "\u{0304}"
    /// `a̱`: the macron's counterpart below the letter.
    static let underline: Unicode.Scalar = "\u{0331}"

    typealias Glyph = GlyphPlacementReader.Glyph

    struct Accent: Equatable {
        /// The bar as `GraphicsReader` reports it, padded two points on every side.
        var bar: CGRect
        var glyph: Glyph
        var scalar: Unicode.Scalar
    }

    /// Whether a painted region could be an accent's bar: at most a point and a half of ink
    /// high, once `GraphicsReader`'s two-point padding is removed, and one to forty points long.
    static func isCandidate(_ region: CGRect) -> Bool {
        region.height <= 5.5 && region.width - 4 >= 1 && region.width - 4 <= 40
    }

    /// The bars among `regions` that are accents, each with the glyph it marks.
    static func accents(_ regions: [CGRect], glyphs: [Glyph]) -> [Accent] {
        regions.filter(isCandidate).compactMap { accent($0, glyphs: glyphs) }
    }

    static func accent(_ bar: CGRect, glyphs: [Glyph]) -> Accent? {
        let left = bar.minX + 2, right = bar.maxX - 2, y = bar.midY, width = right - left
        guard width >= 1 else { return nil }
        // The glyph the bar spans: TeX makes the bar exactly the glyph's advance. Over it, clear
        // of its x-height or its capitals; or under it, below its baseline.
        let placed = glyphs.indices.compactMap { index -> (index: Int, over: Bool)? in
            let glyph = glyphs[index]
            let tolerance = max(0.5, glyph.size * 0.15)
            guard glyph.inked, abs(glyph.minX - left) <= tolerance, abs(glyph.maxX - right) <= tolerance
            else { return nil }
            let rise = (y - glyph.baseline) / glyph.size
            if (0.3...1.1).contains(rise) { return (index, true) }
            if (-0.45 ... -0.02).contains(rise) { return (index, false) }
            return nil
        }
        guard placed.count == 1, let (index, over) = placed.first else { return nil }
        let glyph = glyphs[index], size = glyph.size
        func inks(_ other: Int) -> Bool { other != index && glyphs[other].inked }
        // Anything drawn reaching over the bar's middle.
        let across = glyphs.indices.filter { other in
            inks(other) && min(glyphs[other].maxX, right) - max(glyphs[other].minX, left) > width * 0.2
        }
        if over {
            // A numerator stands on a fraction bar, its baseline within half an em above it.
            guard !across.contains(where: { glyphs[$0].baseline > y && glyphs[$0].baseline - y <= size * 0.5 })
            else { return nil }
            // A radical sign meets its vinculum's left end, hanging from the bar's height.
            guard !glyphs.indices.contains(where: { other in
                inks(other) && abs(glyphs[other].maxX - left) <= size * 0.3
                    && abs(glyphs[other].baseline - y) <= size * 0.3
            }) else { return nil }
        } else {
            // A denominator hangs under a fraction bar, its baseline within an em below it.
            guard !across.contains(where: { glyphs[$0].baseline < y && y - glyphs[$0].baseline <= size * 1.0 })
            else { return nil }
        }
        return Accent(bar: bar, glyph: glyph, scalar: over ? overline : underline)
    }

    /// `line` with `mark` set after the character PDFKit reads under the bar, given PDFKit's
    /// text of the line from its start through that character. That text must be the line's
    /// own, glyph for glyph once spaces are set aside, and must end in the one letter or digit
    /// PDFKit reads under the bar; otherwise nil.
    static func marking(_ line: TextLine, through prefix: String, under character: String,
                        with mark: Unicode.Scalar) -> TextLine? {
        let under = character.unicodeScalars.filter(isBase)
        guard under.count == 1, let base = under.first,
              base.properties.isAlphabetic || base.properties.numericType != nil else { return nil }
        let drawn = prefix.unicodeScalars.filter(isBase)
        let own = line.text.unicodeScalars.filter(isBase)
        guard drawn.last == base, drawn.count <= own.count,
              zip(drawn, own).allSatisfy({ $0 == $1 }) else { return nil }
        guard let content = inserting(mark, afterBase: drawn.count, in: line.content) else { return nil }
        var marked = TextLine(content: content, rect: line.rect, fontSize: line.fontSize,
                              monospaced: line.monospaced, wraps: line.wraps, turn: line.turn)
        marked.readingRect = line.readingRect
        marked.structure = line.structure
        return marked
    }

    /// A scalar that stands for a glyph of its own: neither a space nor a mark set on the glyph
    /// before it, such as an accent an earlier bar on the same line put there.
    static func isBase(_ scalar: Unicode.Scalar) -> Bool {
        !scalar.properties.isWhitespace && scalar.properties.generalCategory != .nonspacingMark
    }

    /// `text` with `mark` set straight after its `count`-th base scalar (`isBase`).
    static func inserting(_ mark: Unicode.Scalar, afterBase count: Int, in text: InlineText) -> InlineText? {
        var remaining = count
        var result = text
        func insert(into elements: inout [InlineText.Element]) -> Bool {
            for index in elements.indices {
                switch elements[index] {
                case let .text(value, style):
                    var scalars = Array(value.unicodeScalars)
                    for position in scalars.indices where isBase(scalars[position]) {
                        remaining -= 1
                        if remaining == 0 {
                            scalars.insert(mark, at: position + 1)
                            elements[index] = .text(String(String.UnicodeScalarView(scalars)), style)
                            return true
                        }
                    }
                case let .link(target, inner):
                    var nested = inner.elements
                    if insert(into: &nested) {
                        var linked = inner
                        linked.elements = nested
                        elements[index] = .link(target, linked)
                        return true
                    }
                case .sourcePage:
                    continue
                }
            }
            return false
        }
        guard count > 0 else { return nil }
        return insert(into: &result.elements) ? result : nil
    }

    /// Reads a page's accents and marks its lines. `regions` are `GraphicsReader`'s painted
    /// regions and `glyphs` what `GlyphPlacementReader` placed, nil where it could not place them.
    static func read(_ lines: [TextLine], regions: [CGRect], glyphs: [Glyph]?,
                     page: PDFPage) throws -> (lines: [TextLine], bars: [CGRect]) {
        guard let glyphs else { return (lines, []) }
        let found = accents(regions, glyphs: glyphs)
        guard !found.isEmpty else { return (lines, []) }
        var result = lines
        var bars: [CGRect] = []
        try NativeTextReader.withExtractionLock {
            for accent in found {
                // The one upright line the glyph stands in.
                let holding = result.indices.filter { index in
                    result[index].turn == .upright && !result[index].monospaced
                        && result[index].rect.contains(accent.glyph.center)
                }
                guard holding.count == 1, let index = holding.first else { continue }
                let rect = result[index].rect
                let middle = (accent.glyph.minX + accent.glyph.maxX) / 2
                let quarter = (accent.glyph.maxX - accent.glyph.minX) / 4
                guard let under = page.selection(for: CGRect(x: middle - quarter, y: rect.minY,
                                                             width: quarter * 2, height: rect.height))?.string,
                      // PDFKit selects a character a rectangle holds more than half of.
                      let prefix = page.selection(for: CGRect(x: rect.minX, y: rect.minY,
                                                              width: middle + quarter - rect.minX,
                                                              height: rect.height))?.string,
                      let marked = marking(result[index], through: prefix, under: under, with: accent.scalar)
                else { continue }
                result[index] = marked
                bars.append(accent.bar)
            }
        }
        return (result, bars)
    }
}
