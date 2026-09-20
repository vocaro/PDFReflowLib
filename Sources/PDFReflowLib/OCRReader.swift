import PDFKit
import Vision

enum OCRReader {
    struct Result: Equatable {
        var lines: [TextLine]
        var tables: [CGRect]
        /// The page was recognized a second time in overlapping bands, because the first reading
        /// left the page's writing uncovered, and the bands read more of it (#116).
        var retriedInBands = false
        /// The share of the page's text-shaped ink still outside every recognized line, when that
        /// is enough to say the reading is incomplete; nil when the reading covers the page's
        /// writing. Set from the reading the caller is given, retried or not.
        var uncoveredTextFraction: Double?
    }

    /// One recognition, in Vision's normalized lower-left coordinates of the image it read.
    struct Recognition: Equatable {
        struct Line: Equatable { var text: String; var box: CGRect; var wraps: Bool? }
        var lines: [Line] = []
        var tables: [CGRect] = []

        /// The words the reading came back with, which a band retry may not reduce (#240).
        var words: Int {
            lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        }
    }

    /// The retry's bands, as normalized page height measured from the bottom: each covers 60% of
    /// the page and they share the middle 20%, so a line one band's edge cuts is whole in the
    /// other (#116).
    static let retryBands: [ClosedRange<Double>] = [0.4...1.0, 0.0...0.6]
    /// Where the bands hand over: a line belongs to the band holding its center.
    static let retryBandSplit = 0.5

    /// Cyrillic capitals and lowercase drawn the same as a Latin letter.
    private static let latinLookAlikes: [Character: Character] = [
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C",
        "Т": "T", "У": "Y", "Х": "X", "І": "I", "Ј": "J", "Ѕ": "S", "а": "a", "е": "e", "о": "o",
        "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s",
    ]

    /// Rewrites a reading's Cyrillic look-alikes as the Latin the page draws (#168).
    ///
    /// Vision returns Cyrillic from a page this library has told it is English:
    /// `RecognizeDocumentsRequest` with `recognitionLanguages = [en-US]` reads the CDC graphic
    /// novel's hand-lettered `MAYBE` as `МАУВЕ`, and neither restricting the language nor enabling
    /// language correction changes it (`measurements/apple-feedback-vision-script`).
    ///
    /// Only a token whose every Cyrillic character is a Latin look-alike is rewritten, and only
    /// when nothing of another script survives the rewrite. `МАУВЕ` becomes `MAYBE`; `НИН?!` and
    /// `ОКДУ` keep every character they were read with, because their `И` and `Д` stand where the
    /// page draws `U` and `A` and no substitution can know that. A guess there would replace a
    /// reading the page can be checked against with one it cannot.
    ///
    /// A document that is not declared English is never touched, so a page of actual Russian
    /// keeps its script. Real Cyrillic prose reaches this rule as words holding the letters with
    /// no Latin look-alike, and keeps them.
    static func repairedScript(_ text: String, language: String) -> String {
        guard EnglishText.isDeclared(language),
              text.contains(where: { latinLookAlikes.keys.contains($0) || isCyrillic($0) }) else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false).map { token -> Substring in
            guard token.contains(where: isCyrillic) else { return token }
            let mapped = String(token.map { latinLookAlikes[$0] ?? $0 })
            return mapped.contains(where: isCyrillic) ? token : Substring(mapped)
        }.joined(separator: " ")
    }

    private static func isCyrillic(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    static func read(page: PDFPage, options: ConversionOptions) async throws -> Result {
        let bounds = page.bounds(for: .cropBox)
        let image = try PageRasterizer.image(page: page, rect: bounds, options: options)
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        let language = Locale.Language(identifier: options.language)
        if request.supportedRecognitionLanguages.contains(language) {
            request.textRecognitionOptions.recognitionLanguages = [language]
        }
        let first = try await recognize(image, request: request)
        try Task.checkCancellation()
        let complete = try await completeReading(first, image: image, request: request,
                                                 pixelsPerPoint: Double(image.width) / bounds.width)
        let recognition = complete.recognition

        func pageRect(_ normalized: CGRect) -> CGRect {
            CGRect(x: bounds.minX + normalized.minX * bounds.width,
                   y: bounds.minY + normalized.minY * bounds.height,
                   width: normalized.width * bounds.width, height: normalized.height * bounds.height)
        }
        let lines: [TextLine] = recognition.lines.map { line in
            let rect = pageRect(line.box)
            return TextLine(text: repairedScript(line.text, language: options.language),
                            rect: rect, fontSize: rect.height, wraps: line.wraps)
        }
        return Result(lines: lines,
                      tables: recognition.tables.map { pageRect($0).insetBy(dx: -3, dy: -3).intersection(bounds) },
                      retriedInBands: complete.retried, uncoveredTextFraction: complete.uncoveredTextFraction)
    }

    /// What the reading of a page came to once its coverage of the page's writing was checked.
    struct CompletedReading {
        var recognition: Recognition
        var retried: Bool
        /// The uncovered share of the page's text ink, when it still indicates loss.
        var uncoveredTextFraction: Double?
    }

    /// Checks a reading against the page's own writing and, when it has left text out, recognizes
    /// the page again in bands and keeps whichever reading covers more (#116).
    ///
    /// Vision reports success while leaving whole paragraphs or table columns out of the page it
    /// read, and the result carries no sign of it. The page's text-shaped ink is the only evidence
    /// the conversion has: rows of it outside every recognized line are writing the reading does
    /// not account for. Vision's own table regions are set aside, because a recognized table
    /// becomes a cropped image whose cells were never going to reflow.
    ///
    /// The page's luminance copy is built once, here, and released when this returns, so a page
    /// that reads cleanly carries none of it into the rest of the conversion.
    static func completeReading(_ first: Recognition, image: CGImage, request: RecognizeDocumentsRequest,
                                pixelsPerPoint: Double) async throws -> CompletedReading {
        guard let raster = OCRTextCoverage.GrayRaster(image) else {
            return CompletedReading(recognition: first, retried: false)
        }
        func coverage(_ recognition: Recognition, excludingTables: Bool = true) -> OCRTextCoverage.Measurement {
            OCRTextCoverage.measure(raster, lines: recognition.lines.map {
                                        OCRTextCoverage.Line(box: $0.box,
                                                             advances: OCRTextCoverage.advances(of: $0.text))
                                    },
                                    excluded: excludingTables ? recognition.tables : [],
                                    pixelsPerPoint: pixelsPerPoint)
        }
        var recognition = first
        var measurement = coverage(first)
        var retried = false
        if measurement.indicatesLoss, let banded = try await readInBands(image, request: request),
           // The comparison ignores both readings' tables: a retry that merely found a larger
           // table region would move ink out of the measurement, and text into an image, without
           // reading a word more.
           bandsAreKept(uncoveredInk: coverage(banded, excludingTables: false).uncoveredInk,
                        words: banded.words,
                        overUncoveredInk: coverage(first, excludingTables: false).uncoveredInk,
                        words: first.words) {
            recognition = banded
            measurement = coverage(banded)
            retried = true
        }
        return CompletedReading(recognition: recognition, retried: retried,
                                uncoveredTextFraction: measurement.indicatesLoss ? measurement.uncoveredFraction : nil)
    }

    /// Whether the banded reading replaces the first one: it is kept for covering more of the
    /// page's writing, and only when it does not cost the page words (#240). Covering more ink
    /// with fewer words is a reading spread wider and read thinner, which is not what the retry
    /// is for; the page is no better off, and a reader would be worse off.
    static func bandsAreKept(uncoveredInk banded: Int, words bandedWords: Int,
                             overUncoveredInk first: Int, words firstWords: Int) -> Bool {
        banded < first && bandedWords >= firstWords
    }

    /// One recognition of an image, in that image's normalized coordinates.
    static func recognize(_ image: CGImage, request: RecognizeDocumentsRequest) async throws -> Recognition {
        let observations = try await request.perform(on: image, orientation: nil)
        guard let document = observations.first?.document else { return Recognition() }
        return Recognition(lines: document.text.lines.compactMap { observation in
            // Preserve uncertain transcription rather than dropping low-confidence words silently.
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Recognition.Line(text: candidate.string, box: observation.boundingRegion.boundingBox.cgRect,
                                    wraps: observation.shouldWrapToNextLine)
        }, tables: document.tables.map { $0.boundingRegion.boundingBox.cgRect })
    }

    /// Recognizes the page again in `retryBands`, merged back into page coordinates; nil when a
    /// band could not be cropped. A band is a smaller image with fewer lines in it, which is what
    /// the dropped-paragraph failure responds to; there is exactly one such retry per page.
    private static func readInBands(_ image: CGImage,
                                    request: RecognizeDocumentsRequest) async throws -> Recognition? {
        var bands: [(recognition: Recognition, bottom: Double, height: Double)] = []
        for band in retryBands {
            let top = Int((1 - band.upperBound) * Double(image.height))
            let bottom = Int((1 - band.lowerBound) * Double(image.height))
            guard bottom > top,
                  let tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top))
            else { return nil }
            bands.append((try await recognize(tile, request: request),
                          1 - Double(bottom) / Double(image.height),
                          Double(bottom - top) / Double(image.height)))
            try Task.checkCancellation()
        }
        return mergeBands(bands)
    }

    /// Maps each band's recognition back into page-normalized coordinates, given the band's bottom
    /// edge and height as fractions of the page. A line is kept from the band on the same side of
    /// `retryBandSplit` as its center, so the strip the bands share is not transcribed twice; a
    /// table crossing the split is kept from both bands and the parts joined.
    static func mergeBands(_ bands: [(recognition: Recognition, bottom: Double, height: Double)]) -> Recognition {
        var merged = Recognition()
        var tables: [CGRect] = []
        for (recognition, bottom, height) in bands {
            func place(_ box: CGRect) -> CGRect {
                CGRect(x: box.minX, y: bottom + box.minY * height, width: box.width, height: box.height * height)
            }
            let ownsUpper = bottom + height / 2 >= retryBandSplit
            func owns(_ box: CGRect) -> Bool { ownsUpper ? box.midY >= retryBandSplit : box.midY < retryBandSplit }
            merged.lines += recognition.lines
                .map { Recognition.Line(text: $0.text, box: place($0.box), wraps: $0.wraps) }
                .filter { owns($0.box) }
            tables += recognition.tables.map(place)
                .filter { owns($0) || ($0.minY < retryBandSplit && $0.maxY > retryBandSplit) }
        }
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
