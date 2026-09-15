import PDFKit
import Vision

enum OCRReader {
    struct Result { var lines: [TextLine]; var tables: [CGRect] }

    static func read(page: PDFPage, options: ConversionOptions) async throws -> Result {
        let bounds = page.bounds(for: .cropBox)
        let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        let language = Locale.Language(identifier: options.language)
        if request.supportedRecognitionLanguages.contains(language) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        let observations = try await request.perform(on: image, orientation: nil)
        try Task.checkCancellation()
        guard let document = observations.first?.document else { return Result(lines: [], tables: []) }
        func pageRect(_ normalized: CGRect) -> CGRect {
            CGRect(x: bounds.minX + normalized.minX * bounds.width,
                   y: bounds.minY + normalized.minY * bounds.height,
                   width: normalized.width * bounds.width, height: normalized.height * bounds.height)
        }
        let lines: [TextLine] = document.text.lines.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Preserve uncertain transcription rather than dropping low-confidence words silently.
            let normalized = observation.boundingRegion.boundingBox.cgRect
            let rect = pageRect(normalized)
            return TextLine(text: candidate.string, rect: rect, fontSize: rect.height,
                            wraps: observation.shouldWrapToNextLine)
        }
        return Result(lines: lines, tables: document.tables.map {
            pageRect($0.boundingRegion.boundingBox.cgRect).insetBy(dx: -3, dy: -3).intersection(bounds)
        })
    }
}
