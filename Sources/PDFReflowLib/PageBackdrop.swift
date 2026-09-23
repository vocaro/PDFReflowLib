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

    static func compose(_ original: PageContent, graphics: GraphicsReader.Result) -> PageContent? {
        guard eligible(graphics, bounds: original.bounds) else { return nil }
        let paints = graphics.paints
        func holdsText(_ rect: CGRect) -> Bool {
            original.lines.contains { line in
                let overlap = line.rect.intersection(rect)
                return !overlap.isNull && overlap.width * overlap.height >= line.rect.width * line.rect.height * 0.5
            }
        }
        let shafts = paints.filter { !$0.image && $0.vertices.count == 2 }
        let art = paints.filter { paint in
            if paint.image { return true }
            if PageDiagnosis.coversPage(paint.rect, bounds: original.bounds) { return false }
            if holdsText(paint.rect) { return false }
            // A shaft is a simple open segment; a small filled triangle touching its endpoint
            // is its arrowhead. Their position relative to text boxes does not change this.
            if paint.vertices.count == 2 || isArrowPolygon(paint.vertices) { return false }
            if (3...4).contains(paint.vertices.count), !paint.rectangular,
               paint.rect.width <= 24, paint.rect.height <= 24,
               shafts.contains(where: { shaft in
                   shaft.vertices.contains { paint.rect.insetBy(dx: -3, dy: -3).contains($0) }
               }) { return false }
            return true
        }
        var page = original
        page.graphics = clusters(art.map(\.rect), distance: 4)
        page.pictures = graphics.images
        let crops = LayoutReconstructor.graphicsWithLabels(page)
        let total = original.lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let taken = original.lines.filter { line in crops.contains { LayoutReconstructor.takes($0, line) } }
            .reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        guard !crops.contains(where: { PageDiagnosis.coversPage($0, bounds: original.bounds) }),
              taken * 2 <= total else { return nil }
        return page
    }
}
