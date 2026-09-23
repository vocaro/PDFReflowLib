import Foundation

/// Separates a born-digital page's flat ground, text boxes and connectors from its figures.
/// Every admission is based on individual paints before clustering; a page-sized photograph,
/// frame, complex silhouette or invisible transcription never qualifies as a flat backdrop.
enum PageBackdrop {
    static func eligible(_ graphics: GraphicsReader.Result, bounds: CGRect) -> Bool {
        guard !graphics.unsupported, !graphics.hasInvisibleText else { return false }
        let large = graphics.paints.filter { PageDiagnosis.coversPage($0.rect, bounds: bounds) }
        return !large.isEmpty && large.allSatisfy { $0.filled && $0.rectangular && !$0.image }
    }

    /// A conventional seven-corner arrow: all edges are axis-aligned except the two
    /// meeting at its tip. A rectangle, triangle, glyph outline and curved illustration do
    /// not satisfy this shape, so a detached vector drawing is still a figure.
    static func isArrowPolygon(_ vertices: [CGPoint]) -> Bool {
        guard vertices.count == 7 else { return false }
        let diagonal = vertices.indices.filter { index in
            let next = vertices[(index + 1) % vertices.count]
            return abs(vertices[index].x - next.x) > 0.01 && abs(vertices[index].y - next.y) > 0.01
        }
        return diagonal.count == 2 && ((diagonal[0] + 1) % 7 == diagonal[1]
            || (diagonal[1] + 1) % 7 == diagonal[0])
    }

    /// Barely touching bounds do not join a large backdrop diagram to a corner emblem.
    /// Neither figure loses any painted area when these marginal overlaps stay separate.
    static func joins(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= min(a.width * a.height, b.width * b.height) * 0.1
    }

    static func clustered(_ rectangles: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rectangles {
            var combined = rect
            var previous = -1
            while previous != result.count {
                previous = result.count
                result.removeAll { existing in
                    guard joins(existing, combined) else { return false }
                    combined = combined.union(existing)
                    return true
                }
            }
            result.append(combined)
        }
        return result
    }

    /// Panel ownership never frees the lettering actually inside a raster picture.
    static func reflows(_ line: TextLine, on page: PageContent) -> Bool {
        guard let panels = page.backdropTextPanels, !page.pictures.contains(where: { LayoutReconstructor.takes($0, line) }) else {
            return false
        }
        return panels.contains { $0.contains(line.rect) }
    }

    static func compose(_ original: PageContent, graphics: GraphicsReader.Result) -> PageContent? {
        guard eligible(graphics, bounds: original.bounds) else { return nil }
        let paints = graphics.paints
        func holdsText(_ rect: CGRect) -> Bool {
            original.lines.contains { line in
                let overlap = line.rect.intersection(rect)
                return !overlap.isNull && overlap.width * overlap.height >= line.rect.width * line.rect.height * 0.5
            }
        }
        let panels = paints.filter { !$0.image && ($0.rectangular || $0.roundedRectangle == true)
            && !PageDiagnosis.coversPage($0.rect, bounds: original.bounds) && holdsText($0.rect) }
        // A lone straight stroke may be a chart axis. Only a shaft with an attached small
        // arrowhead is a connector; the matching head is then removed along with its shaft.
        let heads = paints.filter { !$0.image && (3...4).contains($0.vertices.count)
            && !$0.rectangular && $0.rect.width <= 24 && $0.rect.height <= 24 }
        func meets(_ shaft: GraphicsReader.Paint, _ head: GraphicsReader.Paint) -> Bool {
            shaft.vertices.count == 2 && shaft.vertices.contains {
                head.rect.insetBy(dx: -3, dy: -3).contains($0)
            }
        }
        let shafts = paints.filter { shaft in !shaft.image && shaft.vertices.count == 2
            && heads.contains { head in meets(shaft, head) } }
        let art = paints.filter { paint in
            if paint.image { return true }
            if PageDiagnosis.coversPage(paint.rect, bounds: original.bounds) { return false }
            if panels.contains(paint), paint.roundedRectangle != true { return false }
            if shafts.contains(paint) || isArrowPolygon(paint.vertices) { return false }
            if heads.contains(paint), shafts.contains(where: { meets($0, paint) }) { return false }
            return true
        }
        var page = original
        page.graphics = clustered(art.map(\.rect))
        page.pictures = graphics.images
        page.backdropTextPanels = panels.map(\.rect)
        // A source text box may be shorter than its wrapped title. Admit the immediate
        // aligned continuation at the same size, not the nearby figure's smaller labels.
        let inside = original.lines.filter { reflows($0, on: page) }
        let continuations = original.lines.filter { line in
            inside.contains { first in
                let gap = first.rect.minY - line.rect.maxY
                let overlap = min(first.rect.maxX, line.rect.maxX) - max(first.rect.minX, line.rect.minX)
                return abs(first.fontSize - line.fontSize) < 0.5 && gap >= -1
                    && gap <= first.fontSize * 0.6
                    && overlap >= max(first.rect.width, line.rect.width) * 0.8
                    && (abs(first.rect.minX - line.rect.minX) <= first.fontSize * 0.3
                        || abs(first.rect.midX - line.rect.midX) <= first.fontSize * 0.3)
            }
        }
        page.backdropTextPanels?.append(contentsOf: continuations.map(\.rect))
        // Whole-label expansion can enlarge a legitimate local diagram; it does not turn
        // its native text into an inherited scan layer. Judge the actual painted seeds.
        guard !page.graphics.contains(where: { PageDiagnosis.coversPage($0, bounds: original.bounds) }) else { return nil }
        return page
    }
}
