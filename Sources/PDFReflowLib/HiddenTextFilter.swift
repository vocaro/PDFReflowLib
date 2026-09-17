import CoreGraphics
import Foundation

/// PDFKit extracts every shown glyph, including text the rendering never shows: a running head
/// painted beneath an opaque chapter-opener photograph (#74) or a leftover caption entirely
/// outside the artwork's clipping path (#85). Selections carry no paint order or clip, so the
/// content-stream placements from `GraphicsReader` decide, conservatively: a line is hidden only
/// when some show demonstrably starts inside it and every show that could put a glyph on it is
/// hidden for the line's whole bounds, by lying outside the clip in force or beneath a later
/// opaque cover.
enum HiddenTextFilter {
    /// Indices of `lines` whose text cannot be visible. Empty when the page's placements cannot
    /// be trusted: unsupported drawing, unplaceable text, or any invisible (mode 3) text, whose
    /// scan-and-OCR pages the unverified-text-layer path owns.
    static func hiddenLines(_ lines: [TextLine], graphics: GraphicsReader.Result) -> [Int] {
        guard !graphics.unsupported, !graphics.hasInvisibleText, !graphics.textPlacementUnsupported,
              !graphics.textShows.isEmpty, lines.count <= 10_000 else { return [] }
        let hidden = hiddenLines(lines, graphics: graphics, covers: graphics.covers)
        guard !graphics.covers.isEmpty, !hidden.isEmpty else { return hidden }
        // Text laid beneath the image that shows it is a searchable page's transcription layer
        // (the CDC comic draws all its lettering under each page's artwork), not leftovers:
        // when covers would hide half the page's lines, only the clip can hide text there.
        let clipped = hiddenLines(lines, graphics: graphics, covers: [])
        return (hidden.count - clipped.count) * 2 >= lines.count ? clipped : hidden
    }

    private static func hiddenLines(_ lines: [TextLine], graphics: GraphicsReader.Result,
                                    covers: [GraphicsReader.Cover]) -> [Int] {
        let shows = graphics.textShows.sorted { $0.baseline < $1.baseline }
        let baselines = shows.map(\.baseline)
        var hidden: [Int] = []
        for (index, line) in lines.enumerated() {
            let rect = line.rect
            guard rect.isFinite, !rect.isNull else { continue }
            let origins = rect.insetBy(dx: -0.75, dy: -0.75)
            // PDFKit's line bounds contain its glyphs' baselines; the margin admits more shows,
            // and every show admitted must be hidden, so a wider band only keeps more text.
            let margin = max(1, rect.height * 0.25)
            let band = shows[lowerBound(baselines, rect.minY - margin)...].prefix { $0.baseline <= rect.maxY + margin }
                .filter { $0.left <= rect.maxX + 1 }
            let anchors = band.filter { $0.origin.map(origins.contains) == true }
            guard !anchors.isEmpty, anchors.allSatisfy({ isHidden($0, in: rect, covers: covers) }) else { continue }
            let visible = band.contains { show in
                guard !isHidden(show, in: rect, covers: covers) else { return false }
                // A run that visibly starts in another native line, on a baseline apart from
                // every hidden show that starts in this one, belongs to that line: PDFKit
                // separated it from this line's glyphs (a clipped caption overprinting the
                // visible caption it replaced, #85).
                if let start = show.chainStart, !origins.contains(start),
                   lines.indices.contains(where: { $0 != index && lines[$0].rect.insetBy(dx: -0.75, dy: -0.75).contains(start) }),
                   anchors.allSatisfy({ abs($0.baseline - show.baseline) > 0.5 }) {
                    return false
                }
                return true
            }
            guard !visible else { continue }
            // Rotated and vertical text keeps every line its glyphs could reach.
            let reach = rect.insetBy(dx: -margin, dy: -margin)
            if graphics.slantedShows.contains(where: { crosses($0, reach) && !isHidden(clip: $0.clip, sequence: $0.sequence, in: rect, covers: covers) }) {
                continue
            }
            hidden.append(index)
        }
        return hidden
    }

    static func isHidden(_ show: GraphicsReader.TextShow, in rect: CGRect, covers: [GraphicsReader.Cover]) -> Bool {
        isHidden(clip: show.clip, sequence: show.sequence, in: rect, covers: covers)
    }

    private static func isHidden(clip: CGRect, sequence: Int, in rect: CGRect, covers: [GraphicsReader.Cover]) -> Bool {
        let bounds = rect.insetBy(dx: -1, dy: -1)
        if clip.isNull || bounds.maxX < clip.minX || bounds.minX > clip.maxX
            || bounds.maxY < clip.minY || bounds.minY > clip.maxY { return true }
        return covers.contains { $0.sequence > sequence && $0.rect.contains(bounds) }
    }

    /// Whether the thick ray (or line) of a slanted show can meet `rect`. Separating only along
    /// the ray's own axes over-reports contact, which keeps text.
    private static func crosses(_ show: GraphicsReader.SlantedShow, _ rect: CGRect) -> Bool {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let u = show.direction
        let along = corners.map { ($0.x - show.origin.x) * u.dx + ($0.y - show.origin.y) * u.dy }
        let across = corners.map { -($0.x - show.origin.x) * u.dy + ($0.y - show.origin.y) * u.dx }
        if show.bounded && along.max()! < -show.halfWidth { return false }
        return across.min()! <= show.halfWidth && across.max()! >= -show.halfWidth
    }

    /// Removes hidden lines and keeps tagged groups' line counts true to what remains.
    static func removeHidden(_ lines: inout [TextLine], graphics: GraphicsReader.Result) -> Int {
        let hidden = hiddenLines(lines, graphics: graphics)
        guard !hidden.isEmpty else { return 0 }
        let removed = Set(hidden)
        let groups = Set(hidden.compactMap { lines[$0].structure?.group })
        lines = lines.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        if !groups.isEmpty {
            let counts = Dictionary(grouping: lines.compactMap(\.structure), by: \.group).mapValues(\.count)
            for index in lines.indices {
                if let group = lines[index].structure?.group, groups.contains(group) {
                    lines[index].structure?.lineCount = counts[group] ?? 0
                }
            }
        }
        return hidden.count
    }

    private static func lowerBound(_ values: [CGFloat], _ value: CGFloat) -> Int {
        var low = 0, high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
