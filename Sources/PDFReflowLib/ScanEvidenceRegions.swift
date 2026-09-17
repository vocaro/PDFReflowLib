import CoreGraphics
import Foundation

/// Whole figures and display equations on a scanned page whose inherited OCR layer marks what it
/// could not transcribe with inline images (#37). Adobe Paper Capture places such boxes over a
/// figure's strips or part of an equation; they are evidence that visual content exists there,
/// never crop bounds. Each box grows over the scan's ink until it holds the whole figure (ending
/// above its `FIGURE N.` caption) or the whole display row with its equation number, and never
/// reaches a line of prose or a caption.
enum ScanEvidenceRegions {
    /// Dark cells of the rendered page, one per point, with a summed-area table for extents.
    struct InkMap {
        let origin: CGPoint
        let columns: Int
        let rows: Int
        /// `(columns + 1) × (rows + 1)` prefix counts; row 0 is the bottom of the page.
        private let sums: [Int32]

        /// `dark(column, row)` with row 0 at the bottom of the page.
        init(origin: CGPoint, columns: Int, rows: Int, dark: (Int, Int) -> Bool) {
            self.origin = origin
            self.columns = columns
            self.rows = rows
            var sums = [Int32](repeating: 0, count: (columns + 1) * (rows + 1))
            for row in 0..<rows {
                var running: Int32 = 0
                for column in 0..<columns {
                    if dark(column, row) { running += 1 }
                    sums[(row + 1) * (columns + 1) + column + 1] = sums[row * (columns + 1) + column + 1] + running
                }
            }
            self.sums = sums
        }

        private func count(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int) -> Int32 {
            let w = columns + 1
            return sums[r1 * w + c1] - sums[r0 * w + c1] - sums[r1 * w + c0] + sums[r0 * w + c0]
        }

        /// The bounding box of the dark cells inside `rect`, or nil when it holds none.
        func bounds(in rect: CGRect) -> CGRect? {
            guard rect.isFinite, !rect.isNull else { return nil }
            let c0 = max(0, Int((rect.minX - origin.x).rounded(.up)))
            let c1 = min(columns, Int((rect.maxX - origin.x).rounded(.down)))
            let r0 = max(0, Int((rect.minY - origin.y).rounded(.up)))
            let r1 = min(rows, Int((rect.maxY - origin.y).rounded(.down)))
            guard c0 < c1, r0 < r1, count(c0, r0, c1, r1) > 0 else { return nil }
            var bottom = r0, top = r1, left = c0, right = c1
            while count(c0, bottom, c1, bottom + 1) == 0 { bottom += 1 }
            while count(c0, top - 1, c1, top) == 0 { top -= 1 }
            while count(left, r0, left + 1, r1) == 0 { left += 1 }
            while count(right - 1, r0, right, r1) == 0 { right -= 1 }
            return CGRect(x: origin.x + CGFloat(left), y: origin.y + CGFloat(bottom),
                          width: CGFloat(right - left), height: CGFloat(top - bottom))
        }
    }

    /// Renders the page in gray at four pixels per point: at two, Core Graphics' downsampling
    /// all but erases a scan's one-pixel rules (NBS figure 4's right axis). A one-point cell is
    /// dark when at least two of its sixteen pixels are, so an isolated speck does not bridge a
    /// gap. Nil for a page too large to render within the budget.
    static func inkMap(_ page: CGPDFPage, bounds: CGRect) -> InkMap? {
        let scale = 4
        let columns = Int(bounds.width.rounded(.down)), rows = Int(bounds.height.rounded(.down))
        guard bounds.isFinite, columns > 0, rows > 0, columns * rows <= 1_000_000 else { return nil }
        let width = columns * scale, height = rows * scale
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        // Bitmap row 0 is the top of the page.
        return InkMap(origin: bounds.origin, columns: columns, rows: rows) { column, row in
            var dark = 0
            for y in (height - scale * (row + 1))..<(height - scale * row) {
                for x in (column * scale)..<((column + 1) * scale) where pixels[y * width + x] < 160 {
                    dark += 1
                    if dark >= 2 { return true }
                }
            }
            return false
        }
    }

    /// A caption line opens with its figure number (`FIGURE 1.`, OCR's `FICURE 3.`, `Fig. 2:`).
    static func isCaption(_ text: String) -> Bool {
        text.range(of: #"^\s*fi[gc](?:ure|\.)\s*[0-9]+\s*[.:]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Crops for the evidence boxes, or nil when a figure cannot be grown without reaching prose,
    /// in which case the page keeps its image. Evidence outside the text block's horizontal extent
    /// (a scan border) or over blank paper is dropped.
    static func regions(evidence: [CGRect], lines: [TextLine], bounds: CGRect, ink: InkMap) -> [CGRect]? {
        let body = LayoutReconstructor.bodySize(lines)
        let captionLines = lines.filter { isCaption($0.text) }
        let prose = lines.filter { !captionLines.contains($0) && LayoutReconstructor.isProseRow($0, in: lines, body: body) }
        guard !prose.isEmpty else { return nil }
        let block = union(prose.map(\.rect) + captionLines.map(\.rect))
        // A caption continues on the lines set directly beneath its first at the same size.
        let captions: [CGRect] = captionLines.map { first in
            var caption = first.rect
            var grown = true
            while grown {
                grown = false
                for line in lines where !caption.contains(line.rect) && abs(line.fontSize - first.fontSize) <= 1.5
                    && line.rect.maxY <= caption.minY + line.rect.height * 0.5 && line.rect.maxY >= caption.minY - body
                    && line.rect.minX < caption.maxX && line.rect.maxX > caption.minX {
                    caption = caption.union(line.rect)
                    grown = true
                }
            }
            return caption
        }
        let obstacles = prose.map(\.rect) + captions
        let limit = CGRect(x: block.minX - body, y: bounds.minY + 6, width: block.width + 2 * body,
                           height: bounds.height - 12)
        let boxes = evidence.filter { box in
            box.midX >= block.minX && box.midX <= block.maxX
                && box.width * box.height < bounds.width * bounds.height * 0.75
                && ink.bounds(in: box) != nil
        }

        /// Grows `region` over ink within `margin` (horizontally, the whole column when `rows`),
        /// never reaching an obstacle beside, above or below it, nor `floor` (a caption's top).
        func grow(_ seed: CGRect, margin: CGFloat, rows: Bool, floor: CGFloat, toFloor: Bool = false, others: [CGRect],
                  span: ClosedRange<CGFloat>? = nil) -> CGRect {
            var region = seed
            for _ in 0..<64 {
                let walls = obstacles + others
                var left = max(limit.minX, span?.lowerBound ?? limit.minX)
                var right = min(limit.maxX, span?.upperBound ?? limit.maxX)
                var bottom = max(limit.minY, floor), top = limit.maxY
                for wall in walls where !wall.intersects(region) {
                    let beside = wall.maxY > region.minY && wall.minY < region.maxY
                    let across = wall.maxX > region.minX && wall.minX < region.maxX
                    if beside && wall.maxX <= region.minX { left = max(left, wall.maxX + 1) }
                    if beside && wall.minX >= region.maxX { right = min(right, wall.minX - 1) }
                    if across && wall.minY >= region.maxY { top = min(top, wall.minY - 1) }
                    if across && wall.maxY <= region.minY { bottom = max(bottom, wall.maxY + 1) }
                }
                // A figure ends at its caption: everything between them is its labels and axes.
                let search = CGRect(x: rows ? left : max(left, region.minX - margin),
                                    y: toFloor ? bottom : max(bottom, region.minY - margin), width: 0, height: 0)
                let far = CGPoint(x: rows ? right : min(right, region.maxX + margin), y: min(top, region.maxY + margin))
                guard far.x > search.minX, far.y > search.minY,
                      let found = ink.bounds(in: CGRect(x: search.minX, y: search.minY,
                                                        width: far.x - search.minX, height: far.y - search.minY))
                else { break }
                let next = region.union(found)
                if next == region { break }
                region = next
            }
            return region
        }

        // A figure's evidence lies above its caption, over the caption's measure, with no prose
        // between them; the nearest such caption below claims it.
        var figures: [(caption: CGRect, boxes: [CGRect])] = captions.map { ($0, []) }
        var equations: [CGRect] = []
        for box in boxes {
            let candidates = figures.indices.filter { index in
                let caption = figures[index].caption
                return caption.maxY <= box.minY + 1
                    && min(box.maxX, caption.maxX + 2 * body) > max(box.minX, caption.minX - 2 * body)
                    && !obstacles.contains { wall in
                        wall != caption && wall.minY >= caption.maxY - 1 && wall.maxY <= box.minY + 1
                            && wall.maxX > box.minX && wall.minX < box.maxX
                    }
            }
            if let nearest = candidates.max(by: { figures[$0].caption.maxY < figures[$1].caption.maxY }) {
                figures[nearest].boxes.append(box)
            } else {
                equations.append(box)
            }
        }
        var result: [CGRect] = []
        for figure in figures where !figure.boxes.isEmpty {
            let others = boxes.filter { !figure.boxes.contains($0) }
            // Growth starts from the ink the boxes hold, not their rectangles.
            let seed = union(figure.boxes.compactMap { ink.bounds(in: $0) })
            let region = grow(seed, margin: body * 1.25, rows: false,
                              floor: figure.caption.maxY + 2, toFloor: true, others: others)
            guard !obstacles.contains(where: { $0.insetBy(dx: 0.5, dy: 0.5).intersects(region) }) else { return nil }
            result.append(region)
        }
        let figureRegions = result
        // The formula crops layout would make from the OCR text are display rows too: grown the
        // same way, they keep their equation numbers. Only evidence boxes fall back to their ink.
        let formulas = LayoutReconstructor.graphicsWithLabels(PageContent(number: 0, bounds: bounds, lines: lines, graphics: []))
            .filter { formula in !figureRegions.contains { $0.intersects(formula) } }
        for box in equations + formulas {
            let evidence = equations.contains(box)
            guard !figureRegions.contains(where: { $0.contains(box) }) else { continue }
            // A display row extends across its column: the measure of the prose set near it over
            // the box (both columns for a display spanning the gutter), never past the gutter.
            let near = prose.map(\.rect).filter { line in
                line.maxX > box.minX && line.minX < box.maxX
                    && max(line.minY - box.maxY, box.minY - line.maxY) <= body * 6
            }
            let span = near.isEmpty ? nil
                : (near.map(\.minX).min()! - 2)...(near.map(\.maxX).max()! + 2)
            // A formula crop carries a margin that can reach the gutter; its ink inside the column cannot.
            let column = span.map { CGRect(x: $0.lowerBound, y: box.minY, width: $0.upperBound - $0.lowerBound, height: box.height) }
            guard let seed = ink.bounds(in: column.map { box.intersection($0) } ?? box) else { continue }
            let region = grow(seed, margin: body * 0.6, rows: true, floor: limit.minY, others: figureRegions, span: span)
            // An equation reaching prose keeps only what it certainly is: its own box's ink.
            if obstacles.contains(where: { $0.insetBy(dx: 0.5, dy: 0.5).intersects(region) }) {
                if evidence, let own = ink.bounds(in: box) { result.append(own) }
            } else {
                result.append(region)
            }
        }
        // Antialiased stroke ends lighter than the ink threshold stay inside a two-point margin
        // on every side that keeps clear of prose and captions.
        let padded = result.map { region -> CGRect in
            var region = region
            for side in 0..<4 {
                var trial = region
                switch side {
                case 0: trial.origin.x -= 2; trial.size.width += 2
                case 1: trial.size.width += 2
                case 2: trial.origin.y -= 2; trial.size.height += 2
                default: trial.size.height += 2
                }
                trial = trial.intersection(bounds)
                if !obstacles.contains(where: { $0.insetBy(dx: 0.5, dy: 0.5).intersects(trial) }) { region = trial }
            }
            return region
        }
        return clusters(padded, distance: 1)
    }
}
