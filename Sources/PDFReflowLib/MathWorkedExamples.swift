import CoreGraphics
import Foundation

extension MathRecognizer {
    /// A worked example with formula rows at the left and prose notes at one aligned right
    /// edge. The whole source crop must reconcile before its glyphs can be divided by row.
    static func workedRows(in crop: CGRect, page: PageGlyphs, graphics: [CGRect],
                           lines: [TextLine], body: CGFloat) -> [Row]? {
        guard crop.width > body * 15, crop.height > body * 5,
              !page.opaque.contains(where: crop.contains) else { return nil }
        let glyphs = page.glyphs.filter { crop.contains($0.center) && !$0.text.allSatisfy(\.isWhitespace) }
        guard explains(glyphs, lines: lines, crop: crop) else { return nil }
        let bars = graphics.filter { $0.intersects(crop) }
        guard bars.count >= 3, bars.allSatisfy({ crop.contains($0) && $0.height <= 5 && $0.width >= 6 })
        else { return nil }
        var grouped: [[CGRect]] = []
        for bar in bars.sorted(by: { $0.midY > $1.midY }) {
            if let last = grouped.last, abs(last[0].midY - bar.midY) <= body * 0.2 {
                grouped[grouped.count - 1].append(bar)
            } else { grouped.append([bar]) }
        }
        guard grouped.count >= 3,
              zip(grouped, grouped.dropFirst()).allSatisfy({ pair in
                  body * 1.2 ... body * 2.2 ~= pair.0[0].midY - pair.1[0].midY
              }) else { return nil }

        // A note begins after a clear gap in each row, at the same printed x. The first
        // note may start with a number, so alignment and the complete text check matter more
        // than the first character's class.
        let candidateStarts: [[CGFloat]] = grouped.map { row in
            let baseline = row[0].midY - body * 0.8
            let onLine = glyphs.filter { abs($0.baseline - baseline) <= body * 0.3 }
                .sorted { $0.minX < $1.minX }
            return zip(onLine, onLine.dropFirst()).compactMap { pair in
                pair.1.minX - pair.0.maxX >= body * 0.55
                    && pair.1.minX > crop.minX + body * 4
                    && pair.1.minX < crop.maxX - body * 4
                    ? pair.1.minX : nil
            }
        }
        guard let first = candidateStarts.first,
              let noteX = first.first(where: { x in
                  candidateStarts.dropFirst().allSatisfy { row in
                      row.contains(where: { abs($0 - x) <= body * 0.25 })
                  }
              }),
              grouped.allSatisfy({ row in row.allSatisfy { $0.maxX < noteX - body * 0.4 } })
        else { return nil }

        struct SourceRow {
            var math: [Glyph] = []
            var note: [Glyph] = []
        }
        var sourceRows = Array(repeating: SourceRow(), count: grouped.count)
        for glyph in glyphs {
            let index = grouped.indices.min { a, b in
                func distance(_ row: Int) -> CGFloat {
                    let axis = grouped[row][0].midY
                    let expected = glyph.text == "√" ? axis : axis - body * 0.8
                    return abs(glyph.baseline - expected)
                }
                return distance(a) < distance(b)
            }!
            let axis = grouped[index][0].midY
            let expected = glyph.text == "√" ? axis : axis - body * 0.8
            guard abs(glyph.baseline - expected) <= body * 0.35 else { return nil }
            if glyph.minX >= noteX - body * 0.1 { sourceRows[index].note.append(glyph) }
            else { sourceRows[index].math.append(glyph) }
        }

        var result: [Row] = []
        for index in grouped.indices {
            let row = sourceRows[index]
            guard !row.math.isEmpty, row.note.count >= 5,
                  let note = sourceNote(row.note, in: lines, crop: crop) else { return nil }
            let bounds = (row.math.map(\.box) + grouped[index]).reduce(CGRect.null) { $0.union($1) }
                .insetBy(dx: -2, dy: -2)
            let mathGlyphs = row.math.sorted { $0.minX < $1.minX }
            let synthetic = TextLine(text: mathGlyphs.map(\.text).joined(), rect: bounds, fontSize: body)
            guard let parsed = rows(in: bounds, page: .init(glyphs: mathGlyphs),
                                    graphics: grouped[index], lines: [synthetic], body: body),
                  parsed.count == 1 else { return nil }
            var expression = parsed[0]
            expression.note = note
            result.append(expression)
        }
        return result
    }

    /// PDFKit may join the printed formula and note into one line. The note's glyphs identify
    /// its exact suffix, including the source's spaces and punctuation.
    private static func sourceNote(_ glyphs: [Glyph], in lines: [TextLine], crop: CGRect) -> String? {
        let ordered = glyphs.sorted { $0.minX < $1.minX }
        guard let first = ordered.first else { return nil }
        func compact(_ value: String) -> String {
            String(value.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace })
        }
        let identity = compact(ordered.map(\.text).joined())
        let matches = lines.filter { $0.rect.intersects(crop) && $0.rect.contains(first.center) }
            .flatMap { line in
                line.text.indices.compactMap { index -> String? in
                    let suffix = String(line.text[index...]).trimmingCharacters(in: .whitespaces)
                    return compact(suffix) == identity ? suffix : nil
                }
            }
        let distinct = Set(matches)
        return distinct.count == 1 ? distinct.first : nil
    }
}
