import PDFKit
import Vision

enum OCRReader {
    struct Result {
        var lines: [TextLine]
        var tables: [CGRect]
        /// The page was recognized again in two overlapping bands, which covered more text (#116).
        var retriedInBands = false
        /// Set when the final recognition still leaves text-shaped ink uncovered: its share.
        var uncoveredTextFraction: Double?
    }

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
        if let language = recognitionLanguage(for: identifier, supported: request.supportedRecognitionLanguages) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        return request
    }

    /// Empty when the book language maps to a recognition language; otherwise a sentence for the
    /// `ocrUsed` message naming the recognizer default that was used instead.
    static func languageFallbackNote(for identifier: String) -> String {
        guard recognitionLanguage(for: identifier) == nil else { return "" }
        let fallback = RecognizeDocumentsRequest(.revision1).textRecognitionOptions.recognitionLanguages
            .map { [$0.languageCode?.identifier, $0.region?.identifier ?? $0.script?.identifier]
                .compactMap { $0 }.joined(separator: "-") }
            .joined(separator: ", ")
        return " Vision does not recognize the book language \(identifier); OCR used its default "
            + "language (\(fallback)) with automatic language detection."
    }

    /// Sentences for the `ocrUsed` message about the text-coverage check (#116); empty when the
    /// first recognition covered the page's text-shaped ink.
    static func coverageNote(retriedInBands: Bool, uncoveredTextFraction: Double?, referencesDisabled: Bool) -> String {
        var note = ""
        if retriedInBands {
            note += " The first recognition left text-shaped ink outside every recognized line, so the page was "
                + "recognized again in two overlapping bands."
        }
        if let fraction = uncoveredTextFraction {
            let percent = max(1, Int((fraction * 100).rounded()))
            note += " About \(percent)% of the page's text-shaped ink is still outside every recognized line, so "
                + "some text may be missing; "
                + (referencesDisabled ? "compare the source PDF." : "compare the original page image.")
        }
        return note
    }

    /// The supported recognition language for a book language tag, or nil when Vision lists none
    /// for that language (#106). Vision lists region- or script-qualified languages (`en-US`,
    /// `fr-FR`, `zh-Hant`), while books usually declare a bare code (`en`, `fr`). In order:
    /// the language whose likely-subtag expansion equals the tag's (`en` → `en-US`, `zh-TW` →
    /// `zh-Hant`), then the first with the same language code and script (`fr-CA` → `fr-FR`),
    /// then the first with the same language code.
    static func recognitionLanguage(for identifier: String,
                                    supported: [Locale.Language]? = nil) -> Locale.Language? {
        let supported = supported ?? RecognizeDocumentsRequest(.revision1).supportedRecognitionLanguages
        let requested = Locale.Language(identifier: identifier)
        guard let code = requested.languageCode else { return nil }
        if let exact = supported.first(where: { $0.maximalIdentifier == requested.maximalIdentifier }) {
            return exact
        }
        let sameCode = supported.filter { $0.languageCode == code }
        return sameCode.first { $0.script == requested.script } ?? sameCode.first
    }

    /// The direction a recognized line reads, from its quadrilateral's top edge in normalized
    /// coordinates, when that edge runs more than 45° from left to right; nil otherwise. A caption
    /// set sideways (CDC page 17) has an axis-aligned rectangle taller than wide, and only this
    /// edge says whether its lines run down the page, stacking leftward, or up it, stacking
    /// rightward (#122).
    static func readingDirection(from start: (x: Double, y: Double), to end: (x: Double, y: Double),
                                 in bounds: CGRect) -> CGVector? {
        let dx = (end.x - start.x) * bounds.width, dy = (end.y - start.y) * bounds.height
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, abs(dy) > abs(dx) || dx < 0 else { return nil }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    static func read(page: PDFPage, options: ConversionOptions) async throws -> Result {
        let bounds = page.bounds(for: .cropBox)
        let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
        let request = recognitionRequest(language: options.language)
        var recognition = try await recognize(image, request: request)
        try Task.checkCancellation()
        // Vision can return success while leaving whole paragraphs or table columns out (#116).
        // Text-shaped ink outside every recognized line triggers one retry in two overlapping
        // bands, which is kept only when it leaves less of that ink uncovered.
        let pixelsPerPoint = Double(image.width) / bounds.width
        var coverage = OCRTextCoverage.measure(image: image, lines: recognition.lines.map(\.box),
                                               excluded: recognition.tables, pixelsPerPoint: pixelsPerPoint)
        var retried = false
        if coverage.indicatesLoss {
            var bands: [(recognition: Recognition, bottom: Double, height: Double)] = []
            for band in retryBands {
                let top = Int((1 - band.upperBound) * Double(image.height))
                let bottom = Int((1 - band.lowerBound) * Double(image.height))
                guard bottom > top, let tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width,
                                                                          height: bottom - top)) else { continue }
                bands.append((try await recognize(tile, request: request),
                              1 - Double(bottom) / Double(image.height), Double(bottom - top) / Double(image.height)))
                try Task.checkCancellation()
            }
            if bands.count == retryBands.count {
                let merged = mergeBands(bands)
                // Compare line coverage alone: a retry must not win by finding a larger table
                // region, which only moves ink out of the measurement (and text into an image).
                let first = OCRTextCoverage.measure(image: image, lines: recognition.lines.map(\.box),
                                                    pixelsPerPoint: pixelsPerPoint)
                let second = OCRTextCoverage.measure(image: image, lines: merged.lines.map(\.box),
                                                     pixelsPerPoint: pixelsPerPoint)
                if second.uncoveredInk < first.uncoveredInk {
                    recognition = Recognition(lines: merged.lines,
                                              tables: retainedTables(first: recognition.tables, retry: merged.tables))
                    coverage = OCRTextCoverage.measure(image: image, lines: recognition.lines.map(\.box),
                                                       excluded: recognition.tables, pixelsPerPoint: pixelsPerPoint)
                    retried = true
                }
            }
        }
        func pageRect(_ normalized: CGRect) -> CGRect {
            CGRect(x: bounds.minX + normalized.minX * bounds.width,
                   y: bounds.minY + normalized.minY * bounds.height,
                   width: normalized.width * bounds.width, height: normalized.height * bounds.height)
        }
        let lines: [TextLine] = recognition.lines.map { line in
            let rect = pageRect(line.box)
            var result = TextLine(text: line.text, rect: rect, fontSize: rect.height, wraps: line.wraps)
            if let edge = line.topEdge {
                result.readingDirection = readingDirection(from: (0, 0), to: (Double(edge.dx), Double(edge.dy)), in: bounds)
            }
            return result
        }
        return Result(lines: lines, tables: recognition.tables.map {
            pageRect($0).insetBy(dx: -3, dy: -3).intersection(bounds)
        }, retriedInBands: retried, uncoveredTextFraction: coverage.indicatesLoss ? coverage.uncoveredFraction : nil)
    }

    /// One recognition, in Vision's normalized lower-left coordinates of the recognized image.
    struct Recognition: Equatable {
        struct Line: Equatable {
            var text: String; var box: CGRect; var wraps: Bool?
            /// The quadrilateral's top edge, from its top-left to its top-right corner, in the same
            /// normalized coordinates as `box`: the direction the text runs (#122).
            var topEdge: CGVector? = nil
        }
        var lines: [Line] = []
        var tables: [CGRect] = []
    }

    /// The retry's bands, in normalized page height from the bottom: each covers 60% of the page
    /// and they share the middle 20%, so a line cut by one band's edge is whole in the other.
    static let retryBands: [ClosedRange<Double>] = [0.4...1.0, 0.0...0.6]
    /// Where the bands hand over: a line belongs to the band holding its center.
    static let retryBandSplit = 0.5

    /// The table regions a kept retry reports (#129): only those that overlap a table region of the
    /// first recognition. Table regions become images whose text does not reflow, and the two
    /// recognitions of one raster rarely agree on them: on the Blue Book's retried table pages the
    /// retry's 72 regions overlapped the first recognition's in 14 places. A region only one
    /// recognition reports would hide text the retry recovered (whole pages of it on Blue Book 148
    /// and 175), so the retry can remove table images but never add them.
    static func retainedTables(first: [CGRect], retry: [CGRect]) -> [CGRect] {
        retry.filter { table in first.contains { $0.intersects(table) } }
    }

    static func recognize(_ image: CGImage, request: RecognizeDocumentsRequest) async throws -> Recognition {
        let observations = try await request.perform(on: image, orientation: nil)
        guard let document = observations.first?.document else { return Recognition() }
        return Recognition(lines: document.text.lines.compactMap { observation in
            // Preserve uncertain transcription rather than dropping low-confidence words silently.
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return .init(text: candidate.string, box: observation.boundingRegion.boundingBox.cgRect,
                         wraps: observation.shouldWrapToNextLine,
                         topEdge: CGVector(dx: observation.topRight.x - observation.topLeft.x,
                                           dy: observation.topRight.y - observation.topLeft.y))
        }, tables: document.tables.map { $0.boundingRegion.boundingBox.cgRect })
    }

    /// Maps each band's recognition back to page-normalized coordinates, given the band's bottom
    /// edge and height as fractions of the page (top band first). A line or table is kept from the
    /// band on the same side of the split as its center, so the shared strip is not transcribed
    /// twice; a table crossing the split keeps both parts, joined.
    static func mergeBands(_ bands: [(recognition: Recognition, bottom: Double, height: Double)]) -> Recognition {
        var merged = Recognition()
        var tables: [CGRect] = []
        for (recognition, bottom, height) in bands {
            func place(_ box: CGRect) -> CGRect {
                CGRect(x: box.minX, y: bottom + box.minY * height, width: box.width, height: box.height * height)
            }
            let ownsUpper = bottom + height / 2 >= retryBandSplit
            func owns(_ box: CGRect) -> Bool { ownsUpper ? box.midY >= retryBandSplit : box.midY < retryBandSplit }
            merged.lines += recognition.lines.map { line in
                .init(text: line.text, box: place(line.box), wraps: line.wraps,
                      topEdge: line.topEdge.map { CGVector(dx: $0.dx, dy: $0.dy * height) })
            }
                .filter { owns($0.box) }
            tables += recognition.tables.map(place).filter { owns($0) || ($0.minY < retryBandSplit && $0.maxY > retryBandSplit) }
        }
        // Join overlapping table parts (one table seen in both bands) into one region.
        for table in tables {
            if let index = merged.tables.firstIndex(where: { $0.intersects(table) }) {
                merged.tables[index] = merged.tables[index].union(table)
            } else {
                merged.tables.append(table)
            }
        }
        return merged
    }
}
