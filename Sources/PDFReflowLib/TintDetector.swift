import CoreGraphics
import Foundation

/// Separates page decoration painted as rectangles (sidebar boxes, tint bands behind prose,
/// table cell shading and the rules between them) from the graphics that must stay images (#54).
///
/// `GraphicsReader` records every painted footprint but cannot tell a figure background from a
/// tint because it does not see the text. Here the page's lines decide: a cluster of rectangles
/// that holds at least three wide prose lines untouched by any other ink is a tinted text block.
/// Its rectangles that carry text no longer seed crops, and the thin rules inside it that touch
/// no other graphic are separators rather than figures. Images, shadings, paths, rectangles
/// painted inside `/Figure` marks and rectangles holding no text keep seeding crops, so a chart
/// inside a sidebar keeps its own image while the prose around it reflows. A cluster without
/// that prose evidence (a figure background with tick labels, a flowchart node, a bar chart)
/// is left exactly as before.
enum TintDetector {
    struct Result: Equatable {
        /// Crop seeds, clustered as `GraphicsReader.Result.regions` would have been.
        var graphics: [CGRect]
        /// The tinted rectangles themselves, unclustered: bands and frames behind reflowed text.
        var tints: [CGRect]
        /// Thin rules dropped inside tinted blocks: row and column separators.
        var separators: [CGRect] = []
    }

    /// The share of `rect` covered by any of `covers`, sampled on a grid.
    static func coverage(of rect: CGRect, by covers: [CGRect]) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        var hits = 0
        for i in 0..<16 {
            for j in 0..<16 {
                let point = CGPoint(x: rect.minX + rect.width * (CGFloat(i) + 0.5) / 16,
                                    y: rect.minY + rect.height * (CGFloat(j) + 0.5) / 16)
                if covers.contains(where: { $0.contains(point) }) { hits += 1 }
            }
        }
        return CGFloat(hits) / 256
    }

    /// A rule after the reader's two-point padding, horizontal or vertical.
    static func isThin(_ rect: CGRect) -> Bool { min(rect.width, rect.height) <= 6 }

    /// Prose evidence: a line of at least four words spanning at least 40% of the block.
    private static func isProse(_ line: TextLine, in hull: CGRect) -> Bool {
        !line.monospaced && line.rect.width >= hull.width * 0.4
            && line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
    }

    private static func mostlyInside(_ rect: CGRect, _ container: CGRect) -> Bool {
        let overlap = rect.intersection(container)
        return !overlap.isNull && overlap.width * overlap.height >= rect.width * rect.height * 0.5
    }

    /// `clusters`, keeping each cluster's members.
    private static func groups(_ rects: [CGRect], distance: CGFloat) -> [[CGRect]] {
        var result: [(hull: CGRect, members: [CGRect])] = []
        for rect in rects where !rect.isNull && rect.isFinite {
            var merged = (hull: rect, members: [rect])
            var previousCount = -1
            while previousCount != result.count {
                previousCount = result.count
                result.removeAll { existing in
                    if existing.hull.insetBy(dx: -distance, dy: -distance).intersects(merged.hull) {
                        merged.hull = merged.hull.union(existing.hull)
                        merged.members += existing.members
                        return true
                    }
                    return false
                }
            }
            result.append(merged)
        }
        return result.map(\.members)
    }

    /// Collinear thin strokes joined into one edge: InDesign draws a box side as one segment
    /// per table row, so a side is the union of the segments sharing its line.
    private static func edges(_ rules: [CGRect], horizontal: Bool) -> [(rect: CGRect, strokes: [CGRect])] {
        var result: [(rect: CGRect, strokes: [CGRect])] = []
        for rule in rules where horizontal ? rule.width > rule.height : rule.height >= rule.width {
            let position = horizontal ? rule.midY : rule.midX
            if let index = result.firstIndex(where: { abs((horizontal ? $0.rect.midY : $0.rect.midX) - position) <= 1.5
                && (horizontal ? $0.rect.minX <= rule.maxX + 3 && rule.minX <= $0.rect.maxX + 3
                    : $0.rect.minY <= rule.maxY + 3 && rule.minY <= $0.rect.maxY + 3) }) {
                result[index].rect = result[index].rect.union(rule)
                result[index].strokes.append(rule)
            } else { result.append((rule, [rule])) }
        }
        return result.filter { horizontal ? $0.rect.width >= 40 : $0.rect.height >= 40 }
    }

    /// Four thin edges meeting at their corners draw the same box as a stroked `re`.
    static func strokedRectangles(_ rules: [CGRect]) -> [(rect: CGRect, strokes: [CGRect])] {
        let horizontals = edges(rules, horizontal: true)
        let verticals = edges(rules, horizontal: false)
        var result: [(rect: CGRect, strokes: [CGRect])] = []
        for (index, top) in horizontals.enumerated() {
            for bottom in horizontals[(index + 1)...]
            where abs(top.rect.minX - bottom.rect.minX) <= 3 && abs(top.rect.maxX - bottom.rect.maxX) <= 3
                && abs(top.rect.midY - bottom.rect.midY) >= 12 {
                let rect = top.rect.union(bottom.rect)
                let sides = verticals.filter { side in
                    abs(side.rect.minY - rect.minY) <= 3 && abs(side.rect.maxY - rect.maxY) <= 3
                        && (abs(side.rect.midX - rect.minX) <= 3 || abs(side.rect.midX - rect.maxX) <= 3)
                }
                guard sides.contains(where: { abs($0.rect.midX - rect.minX) <= 3 }),
                      sides.contains(where: { abs($0.rect.midX - rect.maxX) <= 3 }) else { continue }
                result.append((rect, top.strokes + bottom.strokes + sides.flatMap(\.strokes)))
            }
        }
        // Only the outermost box is a frame; the rules of a table inside it stay a grid.
        return result.filter { candidate in !result.contains { $0.rect != candidate.rect && $0.rect.contains(candidate.rect) } }
    }

    /// A frame without prose evidence whose rules and bands the table detector reads as a text
    /// table (#65): Fed page 46's Table 3.1, a shaded title band and header band over body rows
    /// separated only by rules. The table must have a header row on its own band and at least two
    /// body rows, no solid ink may lie in the frame, and every line in the frame other than the
    /// table's own lies above it (a title band). Anything else keeps its image, as before.
    private static func ruledTextTable(hull: CGRect, tinted: [CGRect], lines: [TextLine], inside: [TextLine],
                                       rules: [CGRect], solidInk: [CGRect], bounds: CGRect, body: CGFloat) -> Bool {
        guard !solidInk.contains(where: { $0.intersects(hull) }) else { return false }
        let grid = rules.filter { hull.insetBy(dx: -body, dy: -body).contains($0) }
        guard grid.filter({ $0.width > $0.height }).count >= 2 else { return false }
        var trial = PageContent(number: 0, bounds: bounds, lines: lines, graphics: [])
        trial.tints = tinted
        trial.separators = grid
        return ShadedTableDetector.tables(in: trial, lines: lines).contains { table in
            let owned = table.lines
            let bodyRows = table.rows.filter { !$0.header }
            return table.rows.first?.header == true && bodyRows.count >= 2
                && hull.insetBy(dx: -2, dy: -2).contains(table.bounds)
                && inside.allSatisfy { line in
                    owned.contains { $0.rect == line.rect && $0.text == line.text } || line.rect.minY >= table.bounds.maxY - 1
                }
        }
    }

    static func compose(_ paints: [GraphicsReader.Paint], lines: [TextLine], bounds: CGRect) -> Result {
        let finite = paints.filter { !$0.rect.isNull && $0.rect.isFinite }
        let stroked = strokedRectangles(finite.filter { isThin($0.rect) }.map(\.rect))
        let candidates = finite.filter { $0.frame && !isThin($0.rect) }.map(\.rect) + stroked.map(\.rect)
        guard !candidates.isEmpty, !lines.isEmpty else {
            return Result(graphics: clusters(paints.map(\.rect), distance: 4), tints: [])
        }
        let strokes = stroked.flatMap(\.strokes)
        let ink = finite.filter { (!$0.frame || isThin($0.rect)) && !strokes.contains($0.rect) }.map(\.rect)
        let solidInk = ink.filter { !isThin($0) }
        var tints: [CGRect] = []
        var blocks: [(hull: CGRect, prose: [TextLine], ruled: Bool)] = []
        let body = max(4, LayoutReconstructor.bodySize(lines))
        for members in groups(candidates, distance: 4) {
            let hull = union(members)
            let inside = lines.filter { line in
                mostlyInside(line.rect, hull) && !solidInk.contains { $0.intersects(line.rect) }
            }
            let prose = inside.filter { isProse($0, in: hull) }
            let tinted = members.filter { member in
                lines.contains { member.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            }
            // Prose must carry the text that would reflow: a figure whose labels PDFKit merges
            // into short fragments (a ratings grid, columns of bullets) keeps its image.
            if prose.count >= 3, prose.count * 3 >= inside.count {
                guard !tinted.isEmpty else { continue }
                tints += tinted
                blocks.append((union(tinted), prose, false))
            } else if !tinted.isEmpty, ruledTextTable(hull: hull, tinted: tinted, lines: lines, inside: inside,
                                                      rules: ink.filter(isThin), solidInk: solidInk, bounds: bounds, body: body) {
                tints += tinted
                blocks.append((union(tinted), prose, true))
            }
        }
        guard !tints.isEmpty else {
            return Result(graphics: clusters(paints.map(\.rect), distance: 4), tints: [])
        }
        // Rules that only touch each other inside a tinted block separate its rows and columns.
        // A rule connected to solid ink (a chart axis) stays with that graphic. A lone fraction
        // bar keeps its terms; a grid of rules between single-letter cells is not a fraction.
        // A ruled grid whose cells are not shaded stays an image with the frame drawn around it,
        // unless the table reader already accepted its block as a ruled text table (#65).
        var separators: [CGRect] = []
        var carved: [CGRect] = []
        var consumed: [CGRect] = []
        var restored: [CGRect] = []
        for members in groups(ink, distance: 4) {
            let hull = union(members)
            if members.allSatisfy(isThin) {
                // A stroked frame sits a little outside the bands it encloses.
                guard let block = blocks.first(where: { $0.hull.insetBy(dx: -body, dy: -body).contains(hull) }),
                      !(members.count <= 2 && members.contains { LayoutReconstructor.isFractionBar($0, in: lines, body: body) })
                else { continue }
                let interior = block.hull.insetBy(dx: 6, dy: 6)
                let rules = members.filter { $0.width >= $0.height && $0.midY > interior.minY && $0.midY < interior.maxY }
                // The box around the table shades nothing; its bands and cells must.
                let shading = tints.filter { tint in
                    !(tint.width * tint.height >= block.hull.width * block.hull.height * 0.9
                      && tints.contains { $0 != tint && tint.contains($0) })
                }
                if !block.ruled && rules.count >= 2 && coverage(of: union(rules), by: shading) < 0.8 {
                    restored += stroked.filter { $0.rect.intersects(hull) }.flatMap(\.strokes)
                    continue
                }
                separators += members
                continue
            }
            // Solid ink inside a tinted block (a chart in a sidebar) keeps the block's full-width
            // band between the prose above and below it, so tick labels, legends, captions and
            // notes that only the raster carries stay with the graphic while the prose reflows.
            guard let block = blocks.first(where: { mostlyInside(hull, $0.hull) }) else { continue }
            // Border strokes along the block's edges are decoration connected to the figure;
            // the figure's own extent decides which prose lies above and below it.
            let edges = block.hull.insetBy(dx: 6, dy: 6)
            let core = union(members.filter { member in
                !isThin(member) || (member.width > member.height
                    ? member.midY > edges.minY && member.midY < edges.maxY
                    : member.midX > edges.minX && member.midX < edges.maxX)
            })
            guard !core.isNull else { continue }
            let above = block.prose.filter { $0.rect.minY >= core.maxY - 1 }.map(\.rect.minY).min() ?? block.hull.maxY
            let below = block.prose.filter { $0.rect.maxY <= core.minY + 1 }.map(\.rect.maxY).max() ?? block.hull.minY
            carved.append(CGRect(x: block.hull.minX, y: below, width: block.hull.width, height: max(0, above - below)).union(core))
            consumed += members
        }
        // A stroked box that became a tint gives up its strokes unless a ruled grid inside it
        // restored them; a stroked box that is not a tint keeps them as ordinary ink.
        let framed = stroked.filter { tints.contains($0.rect) && !restored.contains($0.strokes[0]) }
        let consumedStrokes = framed.flatMap(\.strokes)
        let kept = paints.map(\.rect).filter { rect in
            !tints.contains(rect) && !separators.contains(rect) && !consumed.contains(rect) && !consumedStrokes.contains(rect)
        }
        let tinted = tints.filter { tint in !stroked.contains { $0.rect == tint && restored.contains($0.strokes[0]) } }
        return Result(graphics: clusters(kept + carved, distance: 4), tints: tinted, separators: separators)
    }
}
