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
            if panels.contains(paint) { return false }
            if shafts.contains(paint) || isArrowPolygon(paint.vertices) { return false }
            if heads.contains(paint), shafts.contains(where: { meets($0, paint) }) { return false }
            return true
        }
        var page = original
        page.graphics = clusters(art.map(\.rect), distance: 4)
        page.pictures = graphics.images
        page.backdropTextPanels = panels.map(\.rect)
        let crops = LayoutReconstructor.graphicsWithLabels(page)
        let total = original.lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let taken = original.lines.filter { line in !reflows(line, on: page) && crops.contains { LayoutReconstructor.takes($0, line) } }
            .reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        guard !crops.contains(where: { PageDiagnosis.coversPage($0, bounds: original.bounds) }),
              taken * 2 <= total else { return nil }
        return page
    }
}
