import PDFKit
import Vision

enum OCRReader {
    struct Result { var lines: [TextLine]; var tables: [CGRect] }

    /// The recognition request (#94). The revision and every text option are written out; the
    /// values are the macOS/iOS 27 SDK defaults, so a later SDK default cannot change output
    /// without a visible edit here.
    ///
    /// Compute devices stay automatic. Transcription is still not a function of the image and these
    /// settings alone: Vision compiles its document models into a cache keyed by process name
    /// (`~/Library/Caches/<process name>/com.apple.e5rt.e5bundlecache` on macOS), separate compiles
    /// of the same model can read the same raster differently, and later processes of that name
    /// reuse the cached programs. Pinning the request's only compute stage to the CPU does not
    /// remove the dependence; see `measurements/ocr-location/record.md`.
    static func recognitionRequest(language identifier: String) -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest(.revision1)
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.minimumTextHeightFraction = 0.03125
        request.textRecognitionOptions.maximumCandidateCount = 3
        request.textRecognitionOptions.customWords = []
        let language = Locale.Language(identifier: identifier)
        if request.supportedRecognitionLanguages.contains(language) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        return request
    }

    static func read(page: PDFPage, options: ConversionOptions) async throws -> Result {
        let bounds = page.bounds(for: .cropBox)
        let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
        let request = recognitionRequest(language: options.language)
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
