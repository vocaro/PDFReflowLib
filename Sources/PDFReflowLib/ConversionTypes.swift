import Foundation

/// Policy and resource bounds for one independent conversion. No network or model downloads.
public struct ConversionOptions: Sendable {
    public enum OCRPolicy: Sendable {
        /// Recognize pages with absent or visibly damaged native text.
        case automatic
        case never
        case always
    }

    public var title: String?
    public var author: String?
    /// BCP 47 language tag for EPUB metadata and OCR (when the recognizer supports it).
    public var language = "en"
    public var ocr: OCRPolicy = .automatic
    /// Remove short recurring text at page edges when at least three pages provide evidence.
    public var removeRepeatedHeadersAndFooters = true
    public var maximumInputBytes: Int64 = 256 * 1_024 * 1_024
    public var maximumPages = 2_000
    public var maximumCharacters = 20_000_000
    public var maximumOutputBytes: Int64 = 512 * 1_024 * 1_024
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
        case ocrUsed, ocrFailed, uncertainHyphen, furnitureRemoved
        case imageRegion, pageImageFallback, unsupportedGraphics, emptyPage
        case complexLayout, annotationsNotConverted
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
