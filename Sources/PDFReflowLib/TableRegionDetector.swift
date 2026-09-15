import Foundation

/// Conservative preservation for numeric lookup tables separated by dot leaders. This is not
/// a semantic table parser: column associations remain in the source rendering.
enum TableRegionDetector {
    static func regions(in page: PageContent) -> [CGRect] {
        let rowPattern = #"^\s*[+−-]?\d[\d,]*(?:\.\d+)?\s*(?:\.\s*){3,}[+−-]?\d[\d\s.,/%×xX+−–:-]*$"#
        let rows = page.lines.filter {
            !$0.monospaced && $0.text.range(of: rowPattern, options: .regularExpression) != nil
        }.sorted { $0.rect.midY > $1.rect.midY }
        var groups: [[TextLine]] = []
        for row in rows {
            if let index = groups.indices.first(where: { index in
                let last = groups[index].last!
                let size = max(row.fontSize, last.fontSize)
                let gap = last.rect.minY - row.rect.maxY
                return abs(last.rect.minX - row.rect.minX) <= max(2, size * 0.6)
                    && abs(last.rect.maxX - row.rect.maxX) <= size * 2
                    && gap >= -size * 0.4 && gap <= size * 1.5
            }) {
                groups[index].append(row)
            } else { groups.append([row]) }
        }
        return groups.compactMap { rows in
            guard rows.count >= 3, let first = rows.first else { return nil }
            let rowBounds = union(rows.map(\.rect))
            // Require a nearby, similarly aligned textual header. A contents entry or a
            // prose ellipsis must not become a table merely because it contains dots.
            let headers = page.lines.filter { line in
                let gap = line.rect.minY - first.rect.maxY
                let words = line.text.split { !$0.isLetter }
                return words.count >= 2 && !line.monospaced
                    && gap >= 0 && gap <= first.fontSize * 3
                    && abs(line.rect.minX - rowBounds.minX) <= max(2, first.fontSize)
                    && line.rect.width >= rowBounds.width * 0.65
                    && line.rect.width <= rowBounds.width * 1.3
            }
            guard let header = headers.min(by: { $0.rect.minY < $1.rect.minY }) else { return nil }
            // An intervening paragraph breaks a row sequence even when its numbers align.
            guard !page.lines.contains(where: { line in
                rowBounds.intersects(line.rect) && !rows.contains(where: { $0.rect == line.rect && $0.text == line.text })
            }) else { return nil }
            return rowBounds.union(header.rect).insetBy(dx: -2, dy: -2).intersection(page.bounds)
        }
    }
}
