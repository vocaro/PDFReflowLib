import CoreGraphics

/// Reads a repeated pair of outline-only boxes at the ends of ruled form labels (#211).
/// A square in a diagram is not enough: each box needs its own printed label and a horizontal
/// rule joining that label to the box, and the four strokes must be the whole graphics region.
enum DrawnCheckboxReader {
    struct Reading {
        var boxes: [CGRect]
        var regions: [CGRect]
    }

    static func read(lines: [TextLine], paints: [GraphicsReader.Paint], regions: [CGRect]) -> [Reading] {
        struct Row {
            var box: CGRect
            var boxPaint: Int
            var rulePaint: Int
        }
        let rows: [Row] = paints.enumerated().compactMap { index, paint in
            guard paint.strokeOnly == true, paint.rectangular, paint.vertices.count == 4 else { return nil }
            let box = paint.vertices.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            guard (6...20).contains(box.width), (6...20).contains(box.height),
                  box.width / box.height >= 0.5, box.width / box.height <= 2,
                  !lines.contains(where: { $0.rect.intersects(box) }) else { return nil }
            for line in lines where line.rect.maxX < box.minX && abs(line.rect.midY - box.midY) <= 3 {
                guard line.text.split(whereSeparator: \.isWhitespace).count >= 2 else { continue }
                if let rule = paints.indices.first(where: { other in
                    let mark = paints[other]
                    guard mark.strokeOnly == true, !mark.rectangular, mark.vertices.count == 2 else { return false }
                    let start = mark.vertices[0], end = mark.vertices[1]
                    let left = min(start.x, end.x), right = max(start.x, end.x)
                    return abs(start.y - end.y) <= 1 && right - left >= 20
                        && abs(left - line.rect.maxX) <= max(4, line.fontSize * 0.5)
                        && box.minX - right >= 0 && box.minX - right <= line.fontSize
                        && abs(start.y - box.midY) <= box.height * 0.5
                }) {
                    return Row(box: box, boxPaint: index, rulePaint: rule)
                }
            }
            return nil
        }
        var readings: [Reading] = []
        for group in Dictionary(grouping: rows, by: { Int(($0.box.minX / 2).rounded()) }).values {
            guard group.count >= 2,
                  group.max(by: { $0.box.width < $1.box.width })!.box.width
                    - group.min(by: { $0.box.width < $1.box.width })!.box.width <= 2 else { continue }
            let marks = Set(group.flatMap { [$0.boxPaint, $0.rulePaint] })
            let outlineRegions = regions.filter { region in
                let contained = Set(paints.indices.filter { region.contains(paints[$0].rect) })
                return !contained.isEmpty && contained.isSubset(of: marks)
            }
            guard !outlineRegions.isEmpty,
                  marks.allSatisfy({ mark in outlineRegions.contains { $0.contains(paints[mark].rect) } }),
                  group.allSatisfy({ row in outlineRegions.contains {
                      $0.contains(paints[row.boxPaint].rect) && $0.contains(paints[row.rulePaint].rect)
                  } }) else { continue }
            readings.append(Reading(boxes: group.map(\.box), regions: outlineRegions))
        }
        return readings
    }
}
