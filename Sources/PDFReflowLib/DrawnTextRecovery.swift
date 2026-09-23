import Foundation

/// Recognition supplements a sparse, otherwise readable layer (#192). The pictures that the
/// candidacy test excluded remain pictures after recognition: incidental lettering inside a
/// wordmark must not re-enter as a title. Native text retains its exact spelling and styles.
enum DrawnTextRecovery {
    static func reading(_ recognized: OCRReader.Result, on page: PageContent) -> OCRReader.Result {
        var result = recognized
        result.lines = []
        result.wordBoxes = [] // consumed below; the repaired lines no longer have these ranges
        var mergedNative = Set<Int>()
        for (index, line) in recognized.lines.enumerated() {
            if page.pictures.contains(where: { contains(line.rect, in: $0) }) { continue }
            if page.lines.contains(where: { contains(line.rect, in: $0.rect.insetBy(dx: -3, dy: -3)) }) { continue }
            let native = page.lines.enumerated().filter {
                contains($0.element.rect, in: line.rect.insetBy(dx: -3, dy: -3))
            }
            guard !native.isEmpty else { result.lines.append(line); continue }
            let words = index < recognized.wordBoxes.count ? recognized.wordBoxes[index] : []
            var replacements: [(Range<Int>, InlineText)] = []
            for (nativeIndex, original) in native {
                let owned = words.filter { contains($0.box, in: original.rect.insetBy(dx: -3, dy: -3)) }
                // Without word positions a same-row merged OCR line cannot be reconciled
                // safely. Keep the extracted page and its artwork with the existing unread-
                // drawn-text warning rather than duplicate the native word or guess its spelling.
                guard let first = owned.first, let last = owned.last else {
                    result.lines = []; return result
                }
                replacements.append((first.range.lowerBound..<last.range.upperBound, original.content))
                mergedNative.insert(nativeIndex)
            }
            replacements.sort { $0.0.lowerBound < $1.0.lowerBound }
            var content = InlineText(), cursor = 0
            for (range, original) in replacements {
                guard range.lowerBound >= cursor, range.upperBound <= line.text.count else {
                    result.lines = []; return result
                }
                let start = line.text.index(line.text.startIndex, offsetBy: cursor)
                let end = line.text.index(line.text.startIndex, offsetBy: range.lowerBound)
                content.append(InlineText(String(line.text[start..<end])))
                content.append(original)
                cursor = range.upperBound
            }
            content.append(InlineText(String(line.text.dropFirst(cursor))))
            result.lines.append(TextLine(content: content, rect: line.rect, fontSize: line.fontSize,
                                         wraps: line.wraps, turn: line.turn))
        }
        // A failed/empty recognition must still take the existing keep-crops failure path.
        guard !result.lines.isEmpty else { return result }
        result.lines += page.lines.enumerated().filter { !mergedNative.contains($0.offset) }.map(\.element)
        result.lines.sort { $0.rect.midY > $1.rect.midY }
        return result
    }

    static func preserveArtwork(in content: inout PageContent, extracted: PageContent) {
        let writing = content.lines.filter { line in
            !extracted.lines.contains { $0.rect == line.rect && $0.text == line.text }
        }.map(\.rect)
        // Nearby rows share a crop. Bounds include every recognized row and generous padding,
        // rather than relying on the outline reader's clipped seed (Earthdata slide 5).
        let regions = extracted.graphics.filter {
            !PageDiagnosis.coversPage($0, bounds: content.bounds)
        }
        let writtenRegions = regions.filter { rect in writing.contains { $0.intersects(rect) } }
        content.recognizedArtwork = clusters(writing + writtenRegions, distance: 24).map {
            $0.insetBy(dx: -6, dy: -6).intersection(content.bounds)
        }
        let figures = regions.filter { rect in !writing.contains { $0.intersects(rect) } }
        content.graphics = clusters(content.graphics + figures + extracted.pictures, distance: 3)
    }

    private static func contains(_ line: CGRect, in picture: CGRect) -> Bool {
        let overlap = line.intersection(picture)
        return !overlap.isNull && overlap.width * overlap.height >= line.width * line.height * 0.9
    }
}
