import Foundation

/// Marks intact native tategaki columns for reading in their own frame (#44).
/// PDFKit sometimes returns one complete top-to-bottom Japanese column as a narrow, tall
/// selection but gives it no writing direction. This only labels those already intact lines;
/// a page PDFKit splits into single glyphs needs a different reconstruction or image fallback.
enum VerticalJapaneseColumns {
    static func hasProvenTurnedColumns(_ lines: [TextLine]) -> Bool {
        let columns = lines.filter { line in
            line.turn == .clockwise && japaneseCount(line.text) >= 16
                && line.rect.width >= 5 && line.rect.width <= 40
                && line.rect.height >= max(100, line.rect.width * 6)
        }
        return columns.count >= 4 && columns.reduce(0) { $0 + japaneseCount($1.text) } >= 180
    }

    /// A proved native vertical page whose other content intersects its writing band has no
    /// safe page-wide turn: the horizontal item may be an inset, caption or table cell between
    /// columns. Preserve that page as an image instead of silently reversing the columns.
    static func needsImageFallback(_ lines: [TextLine], regions: [CGRect], language: String) -> Bool {
        guard Locale.Language(identifier: language).languageCode?.identifier == "ja" else { return false }
        let vertical = lines.filter { $0.turn == .clockwise }
        guard hasProvenTurnedColumns(vertical) else { return false }
        let lower = vertical.map(\.rect.minY).min()!, upper = vertical.map(\.rect.maxY).max()!
        func inside(_ rect: CGRect) -> Bool { rect.maxY > lower - 1 && rect.minY < upper + 1 }
        return lines.contains { $0.turn != .clockwise && inside($0.rect) }
            || regions.contains(where: inside)
    }

    static func oriented(_ lines: [TextLine], language: String, pageWidth: CGFloat) -> [TextLine] {
        guard Locale.Language(identifier: language).languageCode?.identifier == "ja",
              lines.count >= 4, pageWidth > 0 else { return lines }

        let counts = lines.map { japaneseCount($0.text) }
        let totalJapanese = counts.reduce(0, +)
        let core = lines.indices.filter { index in
            let line = lines[index], rect = line.rect
            return line.turn == .upright && counts[index] >= 16
                && rect.width >= 5 && rect.width <= 40
                && rect.height >= max(100, rect.width * 6)
                && counts[index] * 5 >= line.text.unicodeScalars.count * 3
        }
        guard core.count >= 4, core.reduce(0, { $0 + counts[$1] }) >= 180,
              core.reduce(0, { $0 + counts[$1] }) * 4 >= totalJapanese * 3 else { return lines }

        // Four substantial, separate columns must overlap one printed body band. A vertical
        // title, margin note or table head by itself cannot establish the page's writing mode.
        let cohort = core.filter { anchor in
            core.filter { other in
                let first = lines[anchor].rect, second = lines[other].rect
                let overlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
                return overlap >= min(first.height, second.height) * 0.6
                    && (anchor == other || abs(first.midX - second.midX) >= min(first.width, second.width) * 0.65)
            }.count >= 4
        }
        guard !cohort.isEmpty else { return lines }
        let bodyMinX = core.map { lines[$0].rect.minX }.min()!
        let bodyMaxX = core.map { lines[$0].rect.maxX }.max()!
        return lines.indices.map { index in
            var line = lines[index]
            let rect = line.rect
            // Short author/title continuations may stand beside the proven body columns.
            // They still have to be narrow, Japanese, and truly vertical; horizontal heads and
            // isolated margin labels outside the body band keep their original orientation.
            if line.turn == .upright, counts[index] >= 3,
               counts[index] * 5 >= line.text.unicodeScalars.count * 3,
               rect.width >= 5, rect.width <= 40,
               rect.height >= max(30, rect.width * 3),
               rect.midX >= bodyMinX - 20,
               rect.midX <= bodyMaxX + min(100, pageWidth * 0.16) {
                line.turn = .clockwise
            }
            return line
        }
    }

    private static func japaneseCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            let value = scalar.value
            return count + ((0x3040...0x30FF).contains(value) || (0x3400...0x9FFF).contains(value) ? 1 : 0)
        }
    }
}
