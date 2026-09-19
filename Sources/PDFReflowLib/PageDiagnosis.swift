import CoreGraphics
import Foundation

/// What the judgments about one extracted page found. `RecognitionPolicy.plan` turns this and
/// the OCR policy into a decision; nothing here depends on whether recognition will run.
struct PageEvidence: Equatable, Sendable {
    var requiresPageImage: Bool
    /// The extracted text holds something other than whitespace.
    var hasText: Bool
    /// Characters of extracted text, and how many of them are U+FFFD/U+FFFC replacements.
    var characters: Int
    var replacementCharacters: Int
    /// Existing text lies over a graphic covering more than `pageSizedGraphicFraction` of the
    /// page: the conservative signal shared by the review warning and recognition candidacy.
    var imageBackedText: Bool
    /// A font without a usable Unicode mapping is present and the words fail the declared
    /// language's statistics (#38).
    var damagedEncoding: Bool
    /// The image-backed layer failed the plausibility test (#93, #7); nil when it passed or was
    /// not judged.
    var implausibleLayer: TextLayerPlausibility.Finding?
    /// The page reflows no word of its own and its artwork carries rows of writing (#176).
    var drawnText: Bool

    /// The page has no text worth keeping under an automatic policy: nothing, mostly
    /// replacement characters, only drawn writing, or an unreadable encoding.
    var lacksReadableText: Bool {
        !hasText || replacementCharacters > max(2, characters / 50) || drawnText || damagedEncoding
    }
}

enum PageDiagnosis {
    /// A graphic larger than this share of the page is page-sized: it backs the page's text.
    static let pageSizedGraphicFraction: CGFloat = 0.75

    static func coversPage(_ rect: CGRect, bounds: CGRect) -> Bool {
        rect.width * rect.height > bounds.width * bounds.height * pageSizedGraphicFraction
    }

    /// Judges an extracted page. `measureInk` renders the page and measures the text-shaped ink
    /// outside its lines, ignoring the given rectangles; it is called at most twice, and only
    /// when a judgment needs it.
    static func assess(_ extracted: ExtractedPage, options: ConversionOptions,
                       measureInk: (_ excluding: [CGRect]) throws -> OCRTextCoverage.Measurement?) rethrows -> PageEvidence {
        let content = extracted.content
        let raw = content.lines.map(\.text).joined()
        let replacements = raw.unicodeScalars.filter { $0.value == 0xFFFD || $0.value == 0xFFFC }.count
        // Index-style glyph names without ToUnicode make PDFKit report indexes as characters.
        // Flag only when the extracted words also fail the declared language's statistics (#38).
        let damagedEncoding = extracted.hasUnmappedFont
            && TextEncodingCheck.isImplausible(content.lines.map(\.text).joined(separator: "\n"), language: options.language)
        let imageBackedText = !content.lines.isEmpty && content.graphics.contains {
            coversPage($0, bounds: content.bounds)
        }
        // Inherited text over the image that does not read as English, misreads its words in
        // place, or leaves most of the page's text-shaped ink uncovered, is not a plausible
        // transcription of it (#93). Judged under every policy, so the page is reported whether
        // or not its text is replaced. Excluded when the layer itself is a damaged encoding
        // (#38): that is a different diagnosis of the same page, not a second one.
        let implausibleLayer = imageBackedText && !content.requiresPageImage && !damagedEncoding
            ? try TextLayerPlausibility.judge(lines: content.lines, language: options.language) { try measureInk([]) }
            : nil
        let noText = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A page that reflows no word of its own, but draws writing over its ground, has no
        // text layer to judge: its sentence is artwork (#176). `judgeImageOnly` gates on
        // `reflowsNoWords`, which only a page with no letters at all passes, so it never fires
        // on #93's or #38's territory; candidacy does not exclude `imageBackedText`, since a
        // born-digital page with a full-bleed background paint reads as image-backed on that
        // signal exactly like a scan does. Only automatic policies ask: `.always` recognizes
        // the page anyway and `.never` keeps it.
        let drawsTextCandidate = !noText && !damagedEncoding && !content.requiresPageImage && options.ocr.isAutomatic
        let drawnText = try drawsTextCandidate
            && TextLayerPlausibility.judgeImageOnly(lines: content.lines, language: options.language) {
                try measureInk(extracted.placedImages)
            }
        return PageEvidence(requiresPageImage: content.requiresPageImage, hasText: !noText,
                            characters: raw.count, replacementCharacters: replacements,
                            imageBackedText: imageBackedText, damagedEncoding: damagedEncoding,
                            implausibleLayer: implausibleLayer, drawnText: drawnText)
    }

    /// Prepares a page whose extracted text stands, at least until recognition is compared with
    /// it: unreadable or unverified text keeps a source reference and loses its tags, an
    /// unverified layer's page-sized scan is a reference rather than a figure, and an empty page
    /// is an image.
    static func prepareExtracted(_ content: inout PageContent, evidence: PageEvidence) {
        if evidence.damagedEncoding {
            content.preservePageReference = true
            for index in content.lines.indices { content.lines[index].structure = nil }
        }
        if !content.requiresPageImage, evidence.imageBackedText {
            // A scan with an existing OCR layer must still reflow. Keep its visual page as a
            // reference rather than treating the full-page scan as one figure covering all text.
            content.preservePageReference = true
            for index in content.lines.indices { content.lines[index].structure = nil }
            content.graphics = []
        }
        if content.lines.isEmpty && !content.requiresPageImage {
            content.requiresPageImage = true
        }
    }
}

/// Renders a page for its ink tests at most once, however many judgments ask.
final class PageInkMeasurer {
    private let render: () throws -> CGImage
    private let bounds: CGRect
    private let lines: [TextLine]
    private var image: CGImage?
    private(set) var renders = 0

    init(bounds: CGRect, lines: [TextLine], render: @escaping () throws -> CGImage) {
        self.render = render
        self.bounds = bounds
        self.lines = lines
    }

    func measure(excluding: [CGRect]) throws -> OCRTextCoverage.Measurement? {
        if image == nil {
            image = try render()
            renders += 1
        }
        return TextLayerPlausibility.measureInk(image: image!, bounds: bounds, lines: lines, excluding: excluding)
    }
}
