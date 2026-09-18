import Foundation

/// Policy and resource bounds for one independent conversion. No network or model downloads.
public struct ConversionOptions: Sendable {
    public enum OCRPolicy: Sendable {
        /// Recognize pages with absent or visibly damaged native text, and image-backed pages whose
        /// existing text fails the English plausibility test (`implausibleTextLayer`).
        case automatic
        /// Automatic recognition plus retry of existing text over a graphic covering more
        /// than 75% of the page. This conservative signal also matches valid illustrated
        /// pages; fresh OCR replaces their native text and does not guarantee better accuracy.
        case automaticIncludingImageBackedText
        /// Automatic recognition, except that existing text over a page-sized graphic is always
        /// kept, even when it fails the plausibility test (still reported as `implausibleTextLayer`).
        case automaticKeepingImageBackedText
        case never
        case always
    }

    public enum ReferenceImagePolicy: Sendable {
        /// Include references for OCR, unverified text layers and annotations (the default).
        case automatic
        /// Include a reference for every reconstructed page.
        case always
        /// Omit supplementary references; required fallback pages and figure crops remain.
        case never
    }

    public enum ImageEncoding: Sendable, Equatable {
        case png
        /// ImageIO quality in 0...1. Lossy even at quality 1; no resizing is implied.
        case jpeg(quality: Double)
        /// Encode both and keep the smaller file (PNG on ties). Uses extra encoding work.
        case smallest(jpegQuality: Double)
        /// The default (#193): classify each image and permit lossy only where it is safe, then
        /// behave as `.smallest(jpegQuality:)` there and as `.png` everywhere else. Lossy is
        /// permitted for photographs, continuous-tone art, tonal text scans, full-page mixed
        /// references and anything effectively neutral (under 2% of pixels coloured against the
        /// image's own ground); refused for coloured line art and charts, mixed region crops, and
        /// coloured bilevel or born-digital text pages. A permitted image may still end up PNG.
        case automatic(jpegQuality: Double)

        /// The default JPEG quality for `.automatic`. Below 1.00 ImageIO subsamples chroma, which
        /// is the damage that shows; 0.95 and 0.90 subsample identically.
        public static let automaticJPEGQuality = 0.90

        var isAutomatic: Bool {
            if case .automatic = self { return true }
            return false
        }

        var isValid: Bool {
            switch self {
            case .png: true
            case .jpeg(let quality), .smallest(let quality), .automatic(let quality):
                quality.isFinite && (0...1).contains(quality)
            }
        }
    }

    public var referenceImages: ReferenceImagePolicy = .automatic
    /// Encoding for supplementary references and required full-page fallbacks.
    public var fullPageImageEncoding: ImageEncoding = .automatic(jpegQuality: ImageEncoding.automaticJPEGQuality)
    /// Encoding for figures, tables, equations and other preserved regions.
    public var regionImageEncoding: ImageEncoding = .automatic(jpegQuality: ImageEncoding.automaticJPEGQuality)
    public var title: String?
    public var author: String?
    /// BCP 47 language tag for EPUB metadata and OCR. OCR uses the recognition language Vision
    /// lists for it (`fr` → `fr-FR`); an unlisted language keeps Vision's default, reported once.
    public var language = "en"
    /// Written verbatim as the package `dc:identifier`. Nil writes a random `urn:uuid:` per run.
    /// Must be non-blank XML text; a client pinning output bytes supplies a stable value.
    public var packageIdentifier: String?
    /// Written as `dcterms:modified` and as every ZIP entry date. Nil uses the conversion time.
    /// Must fall in 1980–2099, the ZIP date range; ZIP stores it in two-second UTC resolution.
    /// With both values set, the writer adds no per-run variation. Rendering, OCR and image
    /// encoding can still differ across OS builds and device capabilities.
    public var modificationDate: Date?
    public var ocr: OCRPolicy = .automatic
    /// Remove short recurring text at page edges when at least three pages provide evidence.
    public var removeRepeatedHeadersAndFooters = true
    public var maximumInputBytes: Int64 = 256 * 1_024 * 1_024
    public var maximumPages = 2_000
    public var maximumCharacters = 20_000_000
    /// Budget for image assets and total entry bytes before ZIP compression, not RAM or ZIP size.
    /// Set Int64.max to effectively disable this budget while retaining other resource bounds.
    public var maximumOutputBytes: Int64 = 512 * 1_024 * 1_024
    /// Optional cap on the final EPUB file, including ZIP overhead. Nil imposes no separate cap.
    /// Enforced before publication; exceeding it cleans staging and emits no completion event.
    public var maximumEPUBBytes: Int64?
    public var maximumRasterPixels = 12_000_000
    public var rasterDPI: Double = 180

    public init() {}
}

public struct ConversionProgress: Sendable, Equatable {
    public enum Stage: String, Sendable, Codable {
        case opening, extracting, recognizing, reconstructing, writing, completed
    }
    public let stage: Stage
    /// Monotonic work estimate, not an elapsed-time estimate. Reaches 1 only after publication.
    public let fractionCompleted: Double
    /// One-based source page when applicable.
    public let page: Int?
    public let totalPages: Int
}

public struct ConversionWarning: Sendable, Codable, Equatable {
    public enum Code: String, Sendable, Codable {
        /// Structure tags cannot safely describe some content; spatial reconstruction remains in use.
        case structureFallback
        case ocrUsed, ocrFailed, uncertainHyphen, furnitureRemoved
        case imageRegion, pageImageFallback, unsupportedGraphics, emptyPage
        case complexLayout, annotationsNotConverted
        /// A supplementary reference recommended by analysis was omitted by client policy.
        case referenceImageOmitted
        /// Existing text over a page-sized graphic has not been checked against its image.
        /// This is a conservative review signal, not a measured OCR confidence score.
        case unverifiedTextLayer
        /// Born-digital text whose fonts have a custom encoding without a usable Unicode
        /// mapping and whose extracted words do not read as the declared language. Automatic
        /// OCR policies recognize the page image instead; `.never` keeps the unreadable text.
        /// A source-page reference is recommended either way.
        case damagedTextEncoding
        /// Existing text over a page-sized graphic that fails the English plausibility test: too
        /// few English words, or too little text for the page's text-shaped ink. `.automatic`,
        /// `.automaticIncludingImageBackedText` and `.always` replace it with OCR of the page image;
        /// `.automaticKeepingImageBackedText` and `.never` keep it. Reported either way, so the
        /// page can be reviewed; the message states what failed and whether OCR replaced the text,
        /// left only the page image (recognition failed or found nothing) or the policy kept it.
        case implausibleTextLayer
    }
    public let code: Code
    public let page: Int
    public let message: String
}

public struct ConversionReport: Sendable, Codable {
    public let outputURL: URL
    public let pageCount: Int
    public let reflowedPageCount: Int
    public let recognizedPageCount: Int
    public let imageCount: Int
    public let warnings: [ConversionWarning]
}

public enum ConversionError: Error, Sendable, LocalizedError {
    case invalidOptions(String)
    case unreadablePDF
    case encryptedPDF
    case outputExists
    case resourceLimit(String)
    case renderingFailed(page: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidOptions(let reason): "Invalid conversion options: \(reason)"
        case .unreadablePDF: "The input is not a readable PDF."
        case .encryptedPDF: "Unlock the PDF before converting it."
        case .outputExists: "The output already exists. Choose a new destination."
        case .resourceLimit(let reason): "Conversion resource limit: \(reason)"
        case .renderingFailed(let page): "Could not preserve the appearance of page \(page)."
        }
    }
}
