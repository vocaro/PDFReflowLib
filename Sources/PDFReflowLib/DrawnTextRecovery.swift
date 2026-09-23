import Foundation

/// Recognition supplements a sparse, otherwise readable layer (#192). The pictures that the
/// candidacy test excluded remain pictures after recognition: incidental lettering inside a
/// wordmark must not re-enter as a title. Native text retains its exact spelling and styles.
enum DrawnTextRecovery {
    static func reading(_ recognized: OCRReader.Result, on page: PageContent) -> OCRReader.Result {
        var result = recognized
        result.lines.removeAll { line in
            page.pictures.contains { contains(line.rect, in: $0) }
                || page.lines.contains { contains(line.rect, in: $0.rect.insetBy(dx: -3, dy: -3)) }
        }
        // A failed/empty recognition must still take the existing keep-crops failure path.
        guard !result.lines.isEmpty else { return result }
        result.lines += page.lines
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
