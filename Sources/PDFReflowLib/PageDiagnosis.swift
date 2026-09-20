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

    /// A wrapped paragraph printed over a picture needs this many lines, this many words, and
    /// this share of its widest line on every line but its last (#239).
    static let minimumProseLines = 3
    static let minimumProseWords = 20
    static let minimumProseMeasure: CGFloat = 0.8

    /// The indices of `lines` that a figure crop takes only because the page prints them over one
    /// of its own pictures (#239).
    ///
    /// A crop removes from the reflowed text every line it intersects, and for a picture's own
    /// lettering that is right: a diagram's labels, a chart's axis and a legend's entries are
    /// part of the picture, the crop preserves them where they belong, and pulling them into the
    /// reading order is what `TextLayerPlausibility.carriesDrawnText` and #176 decided against.
    /// It is wrong for prose the page sets *on* a photograph. `LayoutReconstructor.expanded`
    /// trims a crop back off any text it can, but a run inside the artwork cannot be cut away
    /// from it without losing the artwork, so the crop keeps the words and the book loses them:
    /// `usda-ars-agresearch-2012-11` page 4 lost its sixty-word caption exactly this way once the
    /// photograph's clipped footprint stopped covering three quarters of the page (#52, #98), and
    /// it is the mechanism behind #158, #166 and #181.
    ///
    /// Two conditions, both read off the page:
    ///
    /// - **The crop is a picture's own footprint.** Only a run lying wholly inside a placed raster
    ///   image is considered, because that is the crop no cut can free it from. A vector figure's
    ///   region is seeded from what it paints and can still be carved; artwork is not.
    /// - **The run is a wrapped paragraph of the book's prose.** Three or more rows on one left
    ///   edge, at one size and one leading, each but the last filling four fifths of the run's
    ///   widest line, at least `minimumProseWords` words, and at least half of them English
    ///   words. A caption or a column of body text satisfies all of it by construction. A
    ///   figure's lettering does not: `faa-phak-8083-25c` page 475's sign legend runs two lines an
    ///   entry, an axis or a key sets each item on its own short line at its own width, and the
    ///   scanned tables of `cia-blue-book-14-1955` read far below half English. Only books
    ///   declared English are judged, as #93's and #176's readings of the same pages are.
    ///
    /// The picture is still cropped and shown; what changes is only that its prose also reflows.
    static func proseOverPictures(lines: [TextLine], pictures: [CGRect], crops: [CGRect],
                                  bounds: CGRect, language: String) -> Set<Int> {
        guard EnglishText.isDeclared(language), !pictures.isEmpty, !crops.isEmpty else { return [] }
        // The lines a crop takes are read once; a page of many pictures then costs one pass over
        // that much smaller set each.
        let taken = lines.indices.filter { index in crops.contains { $0.intersects(lines[index].rect) } }
        guard !taken.isEmpty else { return [] }
        var freed: Set<Int> = []
        // A page-sized picture is not something the page prints prose *over*: it is the page, a
        // scan whose text is an inherited layer, and `prepareExtracted` has already reflowed it
        // whole. `cia-blue-book-14-1955`'s sighting tables are pages of that kind whose crop is
        // seeded by `TableRegionDetector` after the scan itself was dropped.
        for picture in pictures where !coversPage(picture, bounds: bounds) {
            let inside = taken.filter { picture.insetBy(dx: -1, dy: -1).contains(lines[$0].rect) }
            for run in paragraphRuns(inside, in: lines) where readsAsProse(run, in: lines) {
                // One row of the paragraph reflows once. A page that paints a row twice, one copy
                // over the other, so that it reads over the picture beneath it — the USDA
                // magazine's knockout captions — sets one line, and the second copy stays where
                // it was, inside the crop. Only an exact repetition is dropped; two different
                // texts at one rectangle are both the page's.
                for row in run {
                    freed.formUnion(row.enumerated().filter { $0.offset == 0 || lines[$0.element].text != lines[row[0]].text }
                        .map(\.element))
                }
            }
        }
        return freed
    }

    /// The runs of `taken` that read as one wrapped paragraph, each a list of rows and each row
    /// the indices of the lines standing at that position. A page can paint one line twice — the
    /// USDA magazine sets its caption over the photograph twice, for a knockout — and the pair
    /// is one row of the paragraph, not a break in its leading.
    private static func paragraphRuns(_ taken: [Int], in lines: [TextLine]) -> [[[Int]]] {
        var rows: [(rect: CGRect, size: CGFloat, indices: [Int])] = []
        for index in taken.sorted(by: { lines[$0].rect.maxY > lines[$1].rect.maxY }) {
            let line = lines[index]
            if let row = rows.firstIndex(where: {
                abs($0.rect.minY - line.rect.minY) <= 0.5 && abs($0.rect.minX - line.rect.minX) <= 0.5
                    && abs($0.rect.width - line.rect.width) <= 0.5
            }) {
                rows[row].indices.append(index)
            } else {
                rows.append((line.rect, line.fontSize, [index]))
            }
        }
        var runs: [[[Int]]] = []
        var run: [(rect: CGRect, size: CGFloat, indices: [Int])] = []
        func flush() {
            if run.count >= minimumProseLines { runs.append(run.map(\.indices)) }
            run = []
        }
        for row in rows {
            if let last = run.last {
                let size = max(last.size, row.size)
                let leading = last.rect.minY - row.rect.minY
                let established = run.count >= 2 ? run[0].rect.minY - run[1].rect.minY : leading
                let continues = abs(last.size - row.size) <= size * 0.1
                    && abs(last.rect.minX - row.rect.minX) <= size * 0.25
                    && leading >= size * 0.8 && leading <= size * 2.2
                    && abs(leading - established) <= max(1, established * 0.25)
                if !continues { flush() }
            }
            run.append(row)
        }
        flush()
        return runs
    }

    /// Whether a run's rows read as the book's prose rather than a picture's lettering: every row
    /// but the last fills the measure, the run holds enough words, and its words read as English.
    ///
    /// Both word thresholds are the inherited layer's own (#93): at least
    /// `TextLayerPlausibility.minimumEnglishShare` of the words the lexicon judges are English
    /// words, and a run in which `maximumNumericShare` or more of the tokens carry digits is a
    /// table or a form rather than prose and is not judged at all. The second is what separates a
    /// paragraph from the ruled cells of `cia-blue-book-14-1955`'s scanned sighting tables, whose
    /// rows share a left edge and a leading as a paragraph's do: page 136's four rows read 11 of
    /// 18 judged words as English — a majority, on the strength of stray `I`s and `a`s — but 46%
    /// of their tokens carry digits.
    private static func readsAsProse(_ run: [[Int]], in lines: [TextLine]) -> Bool {
        let rows = run.map { lines[$0[0]] }
        let measure = rows.map(\.rect.width).max() ?? 0
        guard measure > 0, rows.dropLast().allSatisfy({ $0.rect.width >= measure * minimumProseMeasure }),
              rows.allSatisfy({ !$0.monospaced }) else { return false }
        let text = rows.map(\.text).joined(separator: " ")
        guard text.split(whereSeparator: \.isWhitespace).count >= minimumProseWords,
              let counts = EnglishText.wordCounts(text), counts.judged > 0,
              Double(counts.numericTokens) < Double(counts.tokens) * TextLayerPlausibility.maximumNumericShare
        else { return false }
        return Double(counts.english) >= Double(counts.judged) * TextLayerPlausibility.minimumEnglishShare
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
        // Flag only when the extracted words also fail the declared language's statistics (#38),
        // or when the page carries more characters the conversion could not state than an
        // ordinary page's stray replacements. `GlyphIndexDecoder` reads what a document's own
        // words establish and writes U+FFFD where they establish nothing (#143, #226), so a page
        // whose prose it recovered reads as English and keeps its text, while one whose
        // mathematics is drawn in fonts nothing in the document explains still reports the
        // damaged encoding and goes to recognition exactly as it did before the decoder existed.
        let unstated = replacements + extracted.unreadGlyphs > max(2, raw.count / 50)
        let damagedEncoding = extracted.hasUnmappedFont
            && (unstated
                || TextEncodingCheck.isImplausible(content.lines.map(\.text).joined(separator: "\n"),
                                                   language: options.language))
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
