import CoreGraphics
import Foundation

extension MathRecognizer {
    /// A large fraction bar with two small fractions on either side of it. The inner bars
    /// independently prove their fractions; the large bar proves the resulting quotient.
    static func nestedFraction(in crop: CGRect, glyphs: [Glyph], bars: [CGRect],
                               body: CGFloat) -> Row? {
        guard bars.count == 5,
              let outer = bars.max(by: { $0.width < $1.width }) else { return nil }
        let inner = bars.filter { $0 != outer }
        guard inner.count == 4,
              inner.allSatisfy({ $0.minX >= outer.minX - 1 && $0.maxX <= outer.maxX + 1
                  && outer.width >= $0.width * 1.6 }),
              glyphs.allSatisfy({ $0.minX >= outer.minX - 1 && $0.maxX <= outer.maxX + 1 })
        else { return nil }
        let upperBars = inner.filter { $0.midY > outer.midY }
        let lowerBars = inner.filter { $0.midY < outer.midY }
        let upperGlyphs = glyphs.filter { $0.baseline > outer.midY }
        let lowerGlyphs = glyphs.filter { $0.baseline < outer.midY }
        guard upperBars.count == 2, lowerBars.count == 2,
              !upperGlyphs.isEmpty, !lowerGlyphs.isEmpty,
              upperBars.allSatisfy({ $0.minY > outer.maxY }),
              lowerBars.allSatisfy({ $0.maxY < outer.minY }) else { return nil }

        func side(_ glyphs: [Glyph], _ bars: [CGRect]) -> MathExpression.Node? {
            let bounds = (glyphs.map(\.box) + bars).reduce(CGRect.null) { $0.union($1) }
                .insetBy(dx: -1, dy: -1)
            let line = TextLine(text: glyphs.map(\.text).joined(), rect: bounds, fontSize: body)
            guard let parsed = rows(in: bounds, page: .init(glyphs: glyphs), graphics: bars,
                                    lines: [line], body: body), parsed.count == 1,
                  parsed[0].label == nil else { return nil }
            return parsed[0].node
        }
        guard let numerator = side(upperGlyphs, upperBars),
              let denominator = side(lowerGlyphs, lowerBars) else { return nil }
        let bounds = (glyphs.map(\.box) + bars).reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -2, dy: -2).intersection(crop)
        return Row(label: nil, node: .fraction(numerator, denominator, display: true), rect: bounds)
    }
}
