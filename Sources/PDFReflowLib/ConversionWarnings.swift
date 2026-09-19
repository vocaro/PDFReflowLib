import Foundation

/// A warning the extraction and reconstruction passes can raise about one page, before it is
/// given its page number and prose. Every `ConversionWarning` the pipeline emits is made from one
/// of these by `ConversionWarnings.warning`, so each code's message lives in one place and the
/// policy-dependent "read the source PDF instead" tail is written once.
enum PageWarning: Equatable, Sendable {
    /// Why recognition of a page produced no text.
    enum RecognitionFailure: Equatable, Sendable {
        /// A page whose only writing is drawn kept the crops it was extracted with.
        case unreadDrawnText
        /// A misread layer was kept because recognition failed.
        case layerRetained
        /// The page became a page image.
        case pageImage
    }

    /// Why a region or page is carried as an image.
    enum ImageRole: Equatable, Sendable {
        /// Cropped figures, tables and equations.
        case regionCrops
        /// A source-page reference accompanying reflowed text.
        case pageReference
    }

    /// Tagged text could not be matched unambiguously to native lines on this page.
    case structureFallback
    case unsupportedGraphics
    case annotationsNotConverted
    /// `recognized` says whether recognition of the page image replaces the unreadable text.
    case damagedTextEncoding(recognized: Bool)
    case unverifiedTextLayer
    case implausibleTextLayer(TextLayerPlausibility.Finding, TextLayerPlausibility.Outcome)
    case implausibleRecognition(TextLayerPlausibility.Finding)
    /// `recognizedText` is false when recognition succeeded but found no text.
    case ocrUsed(recognizedText: Bool)
    case ocrFailed(RecognitionFailure)
    case pageImageFallback
    case imageRegion(ImageRole)
    case referenceImageOmitted
}

enum ConversionWarnings {
    /// The document-wide structure-tree warning, attached to page 1.
    static func structureTreeFallback() -> ConversionWarning {
        ConversionWarning(code: .structureFallback, page: 1,
            message: "Some PDF structure tags are invalid or outside supported paragraph/heading roles; spatial reconstruction remains in use for that content.")
    }

    static func warning(_ kind: PageWarning, page: Int, options: ConversionOptions) -> ConversionWarning {
        let referencesDisabled = options.referenceImages == .never
        let (code, message): (ConversionWarning.Code, String) = switch kind {
        case .structureFallback:
            (.structureFallback, "Some tagged text could not be matched unambiguously to native lines; spatial reconstruction is retained for those groups.")
        case .unsupportedGraphics:
            (.unsupportedGraphics, "Unsupported or excessive drawing operations require the original page image.")
        case .annotationsNotConverted:
            (.annotationsNotConverted, referencesDisabled
                ? "Visible annotations and link/form interactions are not reconstructed; supplementary references are disabled."
                : "A page image preserves visible annotations. Link and form interactions are not reconstructed.")
        case .damagedTextEncoding(let recognized):
            (.damagedTextEncoding, "Native text has no usable Unicode mapping (custom font encoding without ToUnicode) "
                + "and does not read as the declared language. "
                + (recognized ? "Recognition of the page image replaces it."
                    : "The unreadable native text is retained; "
                    + (referencesDisabled
                        ? "supplementary references are disabled, so read the source PDF instead."
                        : "read the accompanying source-page image instead.")))
        case .unverifiedTextLayer:
            (.unverifiedTextLayer, "Text overlapping a page-sized graphic has not been verified against the source. "
                + "Transcription, tables, numbers and reading order may be inaccurate. "
                + (referencesDisabled
                    ? "Check the source PDF before relying on the reflowed text; supplementary references are disabled."
                    : "Check the accompanying source-page image before relying on the reflowed text."))
        case .implausibleTextLayer(let finding, let outcome):
            (.implausibleTextLayer, TextLayerPlausibility.message(finding, outcome: outcome, referencesDisabled: referencesDisabled))
        case .implausibleRecognition(let finding):
            (.implausibleRecognition, TextLayerPlausibility.recognitionMessage(finding))
        case .ocrUsed(let recognizedText):
            (.ocrUsed, "Text is OCR transcription. " + (referencesDisabled && recognizedText
                ? "Supplementary references are disabled; compare unrecognized visual content with the source PDF."
                : "The original page image preserves unrecognized visual content."))
        case .ocrFailed(.unreadDrawnText):
            (.ocrFailed, "This page reflows no text of its own and its artwork holds writing, but recognition "
                + "of the page failed or found no text; the artwork is preserved as images and its "
                + "writing does not reflow.")
        case .ocrFailed(.layerRetained):
            (.ocrFailed, "OCR failed; the existing text layer is retained.")
        case .ocrFailed(.pageImage):
            (.ocrFailed, "OCR failed; the source page is preserved as an image.")
        case .pageImageFallback:
            (.pageImageFallback, "This page is preserved as an image and does not reflow.")
        case .imageRegion(.regionCrops):
            (.imageRegion, "Graphical regions retain source appearance as images; their internal text does not reflow.")
        case .imageRegion(.pageReference):
            (.imageRegion, "A source-page reference image accompanies reflowed text to preserve all visual content.")
        case .referenceImageOmitted:
            (.referenceImageOmitted, "Client policy omits a supplementary source-page image recommended for this page. "
                + "Compare the source PDF for visual content and transcription accuracy.")
        }
        return ConversionWarning(code: code, page: page, message: message)
    }
}
