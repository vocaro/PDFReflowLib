import CoreGraphics
import Foundation

/// List bullets a page draws as shapes instead of setting them as characters (#167).
///
/// A browser prints an HTML list's `disc`, `circle` and `square` markers as small vector paths,
/// not as text: the TechPort print draws a filled square before every top-level item and an open
/// circle before every nested one. Each became a crop of its own, a 17-pixel image standing before
/// a paragraph holding the item's text, and the items were paragraphs rather than a list.
///
/// A drawn bullet is a graphic region that is small (its ink between a sixth and four fifths of
/// the type size beside it), about square, made of paths alone (no image), crossed by no text,
/// and standing just before a line on that line's row: its middle within the line's middle three
/// fifths and its right edge at most two and a half type sizes left of the line. The row's first
/// text is that line. At least two such shapes of one size must stand on the page, since a list has
/// items; an icon beside one link is no list. Each becomes a `•` opening its line, and the line
/// starts where the shape does, so reconstruction reads it exactly as a list line set in type and
/// the list pass (`ListBuilder`) decides the list, its runs and its nesting as it does for those.
enum DrawnBulletReader {
    /// `GraphicsReader`'s padding around every painted region.
    private static let padding: CGFloat = 2

    static func apply(_ content: inout PageContent, paints: [GraphicsReader.Paint]) {
        guard !content.lines.isEmpty, !content.graphics.isEmpty else { return }
        var found: [(graphic: CGRect, ink: CGRect, line: Int)] = []
        for graphic in content.graphics where graphic.isFinite {
            let ink = graphic.insetBy(dx: min(padding, graphic.width * 0.49), dy: min(padding, graphic.height * 0.49))
            guard ink.width > 0, ink.height > 0, max(ink.width, ink.height) <= min(ink.width, ink.height) * 1.5,
                  !content.lines.contains(where: { $0.rect.intersects(ink) }),
                  !paints.contains(where: { $0.image && $0.rect.intersects(ink) }) else { continue }
            // The line the shape opens: the nearest one to its right whose row it stands in.
            let row = content.lines.indices.filter { index in
                let line = content.lines[index].rect
                return ink.midY >= line.minY + line.height * 0.2 && ink.midY <= line.maxY - line.height * 0.2
            }
            guard let index = row.filter({ content.lines[$0].rect.minX >= ink.maxX })
                    .min(by: { content.lines[$0].rect.minX < content.lines[$1].rect.minX }) else { continue }
            let line = content.lines[index]
            let size = line.fontSize
            guard size > 0, ink.width >= size / 6, ink.height >= size / 6, max(ink.width, ink.height) <= size * 0.8,
                  line.rect.minX - ink.maxX <= size * 2.5, !line.text.isEmpty,
                  !ListBuilder.bullets.contains(line.text.first!) else { continue }
            found.append((graphic, ink, index))
        }
        // A list has items: two shapes of one size on the page.
        let listed = found.filter { item in
            found.filter { abs($0.ink.width - item.ink.width) <= 0.5 && abs($0.ink.height - item.ink.height) <= 0.5 }.count >= 2
        }
        // One shape per line: a line with two candidates keeps both as art.
        let counts = Dictionary(grouping: listed, by: \.line).mapValues(\.count)
        let bullets = listed.filter { counts[$0.line] == 1 }
        guard !bullets.isEmpty else { return }
        for bullet in bullets {
            var line = content.lines[bullet.line]
            line.markerTextEdge = line.rect.minX
            line.replaceContent(InlineText(elements: [.text("• ", [])] + line.content.elements))
            line.rect = line.rect.union(CGRect(x: bullet.ink.minX, y: line.rect.minY, width: 0, height: line.rect.height))
            if let reading = line.readingRect { line.readingRect = reading.union(line.rect) }
            content.lines[bullet.line] = line
        }
        let removed = Set(bullets.map(\.graphic))
        content.graphics.removeAll { removed.contains($0) }
        for graphic in removed { content.graphicKinds[graphic] = nil }
    }
}
