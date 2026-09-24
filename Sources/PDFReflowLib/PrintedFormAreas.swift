import CoreGraphics
import Foundation

/// Printed writing spaces whose rules are text glyphs or a drawn empty box, rather than widgets.
enum PrintedFormAreas {
    static func normalizedWritingLines(_ lines: [TextLine]) -> [TextLine] {
        func rule(_ line: TextLine) -> Bool {
            !line.monospaced && line.turn == .upright && line.text.count >= 16
                && line.text.allSatisfy { $0 == "_" }
        }
        let candidates = lines.indices.filter { rule(lines[$0]) }
        guard candidates.count >= 2 else { return lines }
        let stacked = Set(candidates.filter { index in
            candidates.contains { other in
                other != index && abs(lines[other].rect.minX - lines[index].rect.minX) <= 3
                    && abs(lines[other].rect.width - lines[index].rect.width) <= 4
                    && abs(lines[other].rect.midY - lines[index].rect.midY) <= lines[index].fontSize * 1.5
            }
        })
        return lines.indices.map { index in
            guard stacked.contains(index) else { return lines[index] }
            let source = lines[index]
            var result = TextLine(text: FormBlank.text, rect: source.rect, fontSize: source.fontSize,
                                  monospaced: false, wraps: false, turn: source.turn)
            result.structure = source.structure
            return result
        }
    }

    struct EmptyBox {
        var region: CGRect
        var labels: [TextLine]
        var rows: [TextLine]
    }

    /// Two labeled, empty cells inside one thin drawn grid, on a page independently identified
    /// as a printed form by a stack of writing rules. Requiring both cell edges avoids admitting
    /// a table or a ruled illustration as an answer box (#211).
    static func emptyBox(regions: [CGRect], paints: [CGRect], lines: [TextLine],
                         bounds: CGRect) -> EmptyBox? {
        let normalized = normalizedWritingLines(lines)
        guard zip(lines, normalized).filter({ original, revised in original.text != revised.text }).count >= 2
        else { return nil }
        let body = max(4, lines.map(\.fontSize).sorted()[lines.count / 2])
        for region in regions where region.width >= bounds.width * 0.55
            && region.width <= bounds.width * 0.9 && region.height >= body * 2.5
            && region.height <= body * 5 {
            let marks = paints.filter { region.insetBy(dx: -1, dy: -1).contains($0) }
            let horizontal = marks.filter { $0.width >= region.width * 0.35 && $0.height <= 6 }
            let vertical = marks.filter { $0.height >= region.height * 0.7 && $0.width <= 6 }
            guard horizontal.count >= 4, vertical.count >= 3 else { continue }
            let top = horizontal.filter { abs($0.midY - region.maxY) <= 4 }
            let bottom = horizontal.filter { abs($0.midY - region.minY) <= 4 }
            guard top.count >= 2, bottom.count >= 2 else { continue }
            let labels = lines.filter { line in
                line.turn == .upright && line.text.hasSuffix(":") && region.contains(line.rect)
                    && line.rect.midY >= region.midY && line.rect.width < region.width * 0.45
            }.sorted { $0.rect.midX < $1.rect.midX }
            guard labels.count == 2, labels[0].rect.midX < region.midX,
                  labels[1].rect.midX > region.midX else { continue }
            let interior = CGRect(x: region.minX + 5, y: region.minY + 5,
                                  width: region.width - 10, height: labels[0].rect.minY - region.minY - 7)
            guard interior.height >= body * 0.6,
                  !lines.contains(where: { $0.rect.intersects(interior) }),
                  !marks.contains(where: { $0.intersects(interior)
                      && abs($0.midX - region.midX) > 4 }) else { continue }
            let columns = [region.minX, region.midX, region.maxX]
            guard vertical.contains(where: { abs($0.midX - columns[0]) <= 4 }),
                  vertical.contains(where: { abs($0.midX - columns[1]) <= 4 }),
                  vertical.contains(where: { abs($0.midX - columns[2]) <= 4 }) else { continue }
            let rows = (0..<2).map { index in
                var content = labels[index].content
                content.append(InlineText(" " + FormBlank.text))
                var row = TextLine(content: content, rect: labels[index].rect,
                                   fontSize: labels[index].fontSize, wraps: false)
                row.structure = labels[index].structure
                return row
            }
            return EmptyBox(region: region, labels: labels, rows: rows)
        }
        return nil
    }
}
