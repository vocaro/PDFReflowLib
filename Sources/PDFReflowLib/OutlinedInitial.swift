import Foundation
import PDFKit
import Vision

/// An outlined initial beside three native, wrapped body rows. Recognition is restricted to
/// that opening paragraph; it may add one letter and cannot replace any native word.
enum OutlinedInitial {
    struct Candidate {
        var rect: CGRect
        var indices: [Int]
    }
    static func candidates(lines: [TextLine], paints: [GraphicsReader.Paint]) -> [Candidate] {
        let body = LayoutReconstructor.bodySize(lines)
        guard body >= 4, lines.count <= 2_000 else { return [] }
        return paints.compactMap { paint in
            let rect = paint.rect
            guard !paint.image, !paint.rectangular, paint.shaded != true, paint.vertices.isEmpty,
                  rect.height >= body * 2.5, rect.height <= body * 4.5,
                  rect.width >= body, rect.width <= body * 4.5 else { return nil }
            let rows = lines.indices.filter { index in
                let line = lines[index]
                return line.turn == .upright && abs(line.fontSize - body) <= body * 0.1 && !line.monospaced
                    && line.rect.midY >= rect.minY - body * 0.5 && line.rect.midY <= rect.maxY + body * 0.5
                    && line.rect.minX >= rect.minX + body * 0.5 && line.rect.minX <= rect.maxX + body
                    && line.rect.width >= body * 8
            }.sorted { lines[$0].rect.minY > lines[$1].rect.minY }
            guard rows.count == 3, let first = rows.first,
                  lines[first].text.first?.isLowercase == true,
                  abs(lines[first].rect.maxY - rect.maxY) <= body,
                  lines.contains(where: { line in
                      abs(line.fontSize - body) <= body * 0.1
                          && abs(line.rect.minX - rect.minX) <= body * 0.5
                          && line.rect.maxY <= rect.minY + body * 0.5
                          && line.rect.maxY >= rect.minY - body * 1.5
                  }) else { return nil }
            return Candidate(rect: rect, indices: rows)
        }
    }

    static func prefix(_ letter: String, to text: String, isWord: (String) -> Bool?) -> String? {
        guard letter.count == 1, letter.first?.isUppercase == true, letter.first?.isLetter == true,
              let first = text.split(whereSeparator: { !$0.isLetter }).first else { return nil }
        if isWord((letter + first).lowercased()) == true, isWord(first.lowercased()) == false {
            return letter
        }
        if (letter == "A" || letter == "I"), isWord(first.lowercased()) == true { return letter + " " }
        return nil
    }

    static func recover(on page: PDFPage, content: inout PageContent, paints: [GraphicsReader.Paint],
                        options: ConversionOptions) throws -> Bool {
        guard EnglishText.isDeclared(options.language), !content.hasSyntheticTextStyle,
              options.ocr != .always else { return false }
        let candidates = candidates(lines: content.lines, paints: paints)
        guard candidates.count == 1, let candidate = candidates.first else { return false }
        content.outlinedInitialRows = candidate.indices.map { content.lines[$0].rect }
        guard options.ocr != .never else { return false }
        let region = union(candidate.indices.map { content.lines[$0].rect } + [candidate.rect])
            .insetBy(dx: -4, dy: -4).intersection(content.bounds)
        var raster = options
        raster.rasterDPI = max(options.rasterDPI, 300)
        try Task.checkCancellation()
        let image = try PageRasterizer.image(page: page, rect: region, options: raster)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { return false }
        let readings = (request.results ?? []).compactMap { observation -> String? in
            guard let reading = observation.topCandidates(1).first, reading.confidence >= 0.9 else { return nil }
            let box = observation.boundingBox
            let center = CGPoint(x: region.minX + box.midX * region.width,
                                 y: region.minY + box.midY * region.height)
            guard candidate.rect.contains(center) else { return nil }
            let letter = OCRReader.repairedScript(reading.string, language: options.language)
            return letter.count == 1 ? letter : nil
        }
        guard readings.count == 1, let letter = readings.first, let index = candidate.indices.first,
              let prefix = prefix(letter, to: content.lines[index].text, isWord: EnglishText.lexiconContains)
        else { return false }
        let line = prepending(prefix, to: content.lines[index])
        content.lines[index] = line
        content.outlinedInitialRows?.append(line.rect)
        content.graphics.removeAll { $0 == candidate.rect }
        content.recognized = true
        content.preservePageReference = true
        return true
    }

    static func prepending(_ prefix: String, to original: TextLine) -> TextLine {
        var text = InlineText(prefix); text.append(original.content)
        var line = TextLine(content: text, rect: original.rect, fontSize: original.fontSize,
                            monospaced: original.monospaced, wraps: original.wraps, turn: original.turn)
        line.readingRect = original.readingRect
        line.structure = original.structure
        return line
    }

    static func reflows(_ line: TextLine, on page: PageContent) -> Bool {
        page.outlinedInitialRows?.contains(line.rect) == true
    }
}
