import CoreGraphics
import Foundation

/// Text and paint evidence before bounding rectangles join unrelated artwork across prose.
enum TextBackdrop {
    static func paragraphs(_ lines: [TextLine]) -> [TextLine] {
        guard lines.count <= 2_000 else { return [] }
        var runs: [[TextLine]] = []
        for line in lines.filter({ !$0.monospaced }).sorted(by: { $0.rect.minY > $1.rect.minY }) {
            if let index = runs.lastIndex(where: { run in
                let last = run.last!, size = max(last.fontSize, line.fontSize)
                return abs(last.fontSize - line.fontSize) <= size * 0.1
                    && last.rect.minY > line.rect.minY
                    && last.rect.minY - line.rect.maxY <= size * 0.9
                    && min(last.rect.maxX, line.rect.maxX) > max(last.rect.minX, line.rect.minX)
                    && abs(run.map(\.rect.minX).min()! - line.rect.minX) <= size * 3
            }) { runs[index].append(line) }
            else { runs.append([line]) }
        }
        return runs.filter { run in
            run.count >= 3 && run.filter { line in
                line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
            }.count >= 2
        }.flatMap { $0 }
    }

    static func bridgesText(_ a: CGRect, _ b: CGRect, lines: [TextLine]) -> Bool {
        let hull = a.union(b)
        return lines.contains { line in
            let rect = line.text.isEmpty ? line.rect : line.rect.insetBy(dx: 1, dy: 1)
            return !rect.isEmpty && hull.intersects(rect) && !a.intersects(rect) && !b.intersects(rect)
        }
    }

    static func clustersKeepingText(_ rectangles: [CGRect], lines: [TextLine], distance: CGFloat) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rectangles where rect.isFinite && !rect.isNull {
            var merged = rect, previous = -1
            while previous != result.count {
                previous = result.count
                result.removeAll { existing in
                    guard existing.insetBy(dx: -distance, dy: -distance).intersects(merged),
                          !bridgesText(existing, merged, lines: lines) else { return false }
                    merged = existing.union(merged)
                    return true
                }
            }
            result.append(merged)
        }
        return result
    }

    /// A proved gallery's gutters separate pictures even when padded frame bounds nearly touch.
    static func galleryGutters(_ lines: [TextLine], pictures: [CGRect]) -> [TextLine] {
        let cards = GalleryCaptions.groups(lines: lines, images: pictures, body: LayoutReconstructor.bodySize(lines))
            .sorted { $0.rect.minX < $1.rect.minX }
        return zip(cards, cards.dropFirst()).compactMap { left, right in
            let a = pictures[left.image], b = pictures[right.image]
            guard abs(a.maxY - b.maxY) <= 4, b.minX > a.maxX else { return nil }
            let x = (a.maxX + b.minX) / 2
            return TextLine(text: "", rect: CGRect(x: x - 0.1, y: min(a.minY,b.minY), width: 0.2,
                                                 height: max(a.maxY,b.maxY) - min(a.minY,b.minY)), fontSize: 1)
        }
    }

    /// Split operators can paint adjacent parts of one underline. Rejoin only collinear
    /// fragments before table-header evidence counts rules; never join a rule into artwork.
    static func joinedRules(_ rectangles: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rectangles.sorted(by: { $0.minX < $1.minX }) {
            if let index = result.indices.first(where: {
                abs(result[$0].midY - rect.midY) <= 0.5
                    && rect.minX <= result[$0].maxX + 4 && rect.maxX >= result[$0].minX
            }) { result[index] = result[index].union(rect) }
            else { result.append(rect) }
        }
        return result
    }

    static func compose(_ original: PageContent, graphics: GraphicsReader.Result) -> PageContent {
        guard !graphics.unsupported, !graphics.hasInvisibleText, !graphics.paints.isEmpty else { return original }
        // Aggregate artwork spanning a page already has conservative reference/native-text
        // handling. Splitting that hull must not newly hand its text to local image crops.
        // Only independently proved whole-page backgrounds justify replacing that handling.
        if original.graphics.contains(where: { PageDiagnosis.coversPage($0, bounds: original.bounds) }) {
            let large = graphics.paints.filter { PageDiagnosis.coversPage($0.rect, bounds: original.bounds) }
            guard !large.isEmpty && large.allSatisfy({ !$0.image
                && (($0.rectangular && $0.filled) || $0.backgroundShading == true) }) else { return original }
        }
        let prose = paragraphs(original.lines)
        let gutters = galleryGutters(original.lines, pictures: graphics.paints.filter(\.image).map(\.rect))
        var page = original
        page.pictures = graphics.paints.filter(\.image).map(\.rect)
        page.headerBackdrop = graphics.paints.first { paint in
            paint.rectangular && paint.filled && !paint.image
                && paint.rect.width >= original.bounds.width * 0.8
                && paint.rect.minY >= original.bounds.minY + original.bounds.height * 0.83
                && paint.rect.height >= original.bounds.height * 0.04
                && original.lines.filter { paint.rect.contains($0.rect) }.count >= 2
        }?.rect
        guard !prose.isEmpty else { return page }
        page.nativeTextPanels = graphics.paints.filter { paint in
            !paint.image && paint.rectangular && min(paint.rect.width,paint.rect.height) > 6
                && prose.filter { paint.rect.insetBy(dx: -1,dy: -1).contains($0.rect) }.count >= 3
        }.map(\.rect)
        let fieldPanels = graphics.paints.filter { paint in
            guard paint.filled, paint.rectangular, !paint.image,
                  paint.rect.height >= paint.rect.width * 2.5,
                  paint.rect.width * paint.rect.height >= original.bounds.width * original.bounds.height * 0.1
            else { return false }
            let inside = original.lines.filter { paint.rect.contains($0.rect) }
            let beside = prose.filter { !$0.rect.intersects(paint.rect)
                && $0.rect.midY >= paint.rect.minY && $0.rect.midY <= paint.rect.maxY }
            return inside.count >= 8 && beside.count >= 6
        }.map(\.rect)
        let values = original.lines.filter { line in
            guard fieldPanels.contains(where: { $0.contains(line.rect) }),
                  line.text.split(separator: ":", omittingEmptySubsequences: false).count == 2 else { return false }
            let parts = line.text.split(separator: ":", omittingEmptySubsequences: false)
            return parts[0].split(whereSeparator: \.isWhitespace).count <= 4
                && parts[0].contains(where: \.isLetter)
                && Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil
        }.sorted { $0.rect.minY > $1.rect.minY }
        if values.count >= 3, zip(values, values.dropFirst()).allSatisfy({ first, second in
            abs(first.fontSize - second.fontSize) < 0.1
                && abs(first.rect.minX - second.rect.minX) < first.fontSize * 0.25
                && first.rect.minY - second.rect.minY >= first.fontSize * 0.8
                && first.rect.minY - second.rect.minY <= first.fontSize * 1.5
        }) { page.sidebarValueRows = values.map(\.rect) }
        let paints = graphics.paints.filter { paint in
            if !paint.image, paint.rectangular, (paint.filled || paint.strokeOnly == true), fieldPanels.contains(where: {
                $0.insetBy(dx: -2, dy: -2).contains(paint.rect)
                    && paint.rect.width >= $0.width * 0.95 && paint.rect.height >= $0.height * 0.95
            }) { return false }
            if paint.backgroundShading == true && PageDiagnosis.coversPage(paint.rect, bounds: original.bounds) {
                page.preservePageReference = true
                return false
            }
            // A long divider meeting a small ornament is not a single wide picture.
            // Keep the ornament itself and avoid turning the divider's bounding hull into
            // ownership of the first row in all the columns below it.
            if !paint.image, paint.shaded != true, (paint.filled || paint.strokeOnly == true),
               paint.rect.height <= 6, paint.rect.width >= original.bounds.width * 0.8,
               graphics.images.contains(where: {
                   $0.intersects(paint.rect) && $0.width <= paint.rect.width * 0.15
               }), !original.lines.contains(where: {
                   let core = $0.rect.insetBy(dx: 0, dy: $0.rect.height * 0.25)
                   return core.intersects(paint.rect)
               }) { return false }
            guard !paint.image, paint.rectangular, paint.filled || paint.strokeOnly == true else { return true }
            let inside = prose.filter { paint.rect.insetBy(dx: -1, dy: -1).contains($0.rect) }
            // A flat frame or fill behind a wrapped paragraph is its decoration. The figure's
            // own paths and images still seed crops independently, including diagrams inside
            // a larger sidebar panel. A narrow rule is never a text background.
            return min(paint.rect.width, paint.rect.height) <= 6 || inside.count < 3
        }
        // Classify a leader or underline while it is still a thin rule. Merging it into
        // a photograph first would make that decoration own the table-of-contents row.
        let rules = joinedRules(paints.map(\.rect).filter(LayoutReconstructor.isThinRule))
        let art = paints.map(\.rect).filter { !LayoutReconstructor.isThinRule($0) }
        page.graphics = rules + clustersKeepingText(art, lines: prose + gutters, distance: 4)
        return page
    }
}
