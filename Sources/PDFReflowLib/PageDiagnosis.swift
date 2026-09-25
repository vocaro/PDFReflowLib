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
    /// The sparse layer leaves rows of drawn writing unaccounted for (#176, #192).
    var drawnText: Bool
    /// The English words of an image-backed layer that is sparse, nil otherwise
    /// (`TextLayerPlausibility.sparseEnglishWords`): whatever its finding, recognition of the page
    /// that reads as noise shows handwriting the layer does not transcribe (#216).
    var sparseLayerWords: Int? = nil

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
    static let minimumProseWords = 18
    static let minimumProseMeasure: CGFloat = 0.75

    /// The indices of `lines` that a figure crop takes only because the page prints them over one
    /// of its own pictures or proved rectangular text panels (#239, #191).
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
    /// - **The crop contains a picture or proved text panel.** A run must intersect the crop of a placed
    ///   raster image or a rectangle independently shown to hold native wrapped prose. The complete
    ///   run stays together when only its opening rows overlap. Patterned panel artwork remains
    ///   in its required source crop; a vector figure alone supplies no text-panel evidence.
    /// - **The run is a wrapped paragraph of the book's prose.** Three or more rows on one left
    ///   edge, at one size and one leading, each but the last filling three quarters of the run's
    ///   widest line, at least `minimumProseWords` words, and at least half of them English
    ///   words. A caption or a column of body text satisfies all of it by construction. A
    ///   figure's lettering does not: `faa-phak-8083-25c` page 475's sign legend runs two lines an
    ///   entry, an axis or a key sets each item on its own short line at its own width, and the
    ///   scanned tables of `cia-blue-book-14-1955` read far below half English. Only books
    ///   declared English are judged, as #93's reading of the same pages is.
    ///
    /// The picture is still cropped and shown; what changes is only that its prose also reflows.
    static func proseOverPictures(lines: [TextLine], pictures: [CGRect], crops: [CGRect],
                                  bounds: CGRect, language: String, nativeTypography: Bool = false) -> Set<Int> {
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
            let owners = crops.filter { crop in
                let overlap = crop.intersection(picture)
                return !overlap.isNull && overlap.width * overlap.height >= picture.width * picture.height * 0.9
            }
            let inside = taken.filter { index in
                owners.contains { $0.insetBy(dx: -2, dy: -2).contains(lines[index].rect) }
            }
            guard !inside.isEmpty else { continue }
            let eligible = Set(inside)
            for run in paragraphRuns(Array(lines.indices), in: lines) where readsAsProse(run, in: lines) {
                // One row of the paragraph reflows once. A page that paints a row twice, one copy
                // over the other, so that it reads over the picture beneath it — the USDA
                // magazine's knockout captions — sets one line, and the second copy stays where
                // it was, inside the crop. Only an exact repetition is dropped; two different
                // texts at one rectangle are both the page's.
                guard run.contains(where: { $0.contains(where: eligible.contains) }) else { continue }
                for row in run {
                    freed.formUnion(distinctRow(row, in: lines))
                }
                // A native paragraph's immediately preceding, aligned larger headings
                // belong to that paragraph even when the same decorative picture backs them.
                // Keep this separate from OCR or synthetic sizes, which cannot prove a heading.
                if nativeTypography, let firstRow = run.first, let first = firstRow.first {
                    var next = lines[first]
                    for _ in 0..<2 {
                        let candidates = inside.filter { index in
                            let line = lines[index], gap = line.rect.minY - next.rect.maxY
                            return line.fontSize >= next.fontSize * 1.15
                                && line.fontSize <= next.fontSize * 2
                                && abs(line.rect.minX - next.rect.minX) <= next.fontSize * 0.25
                                && gap >= -1 && gap <= next.fontSize * 1.6
                                && line.text.split(whereSeparator: \.isWhitespace).count >= 2
                                && line.text.count <= 120 && !line.monospaced
                        }
                        guard let heading = candidates.min(by: { lines[$0].rect.minY < lines[$1].rect.minY }) else { break }
                        freed.insert(heading); next = lines[heading]
                    }
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
            } else if let row = rows.firstIndex(where: {
                // PDFKit may start a second selection at a raised reference number and
                // report that number's size for the normal prose following it. Adjacent
                // pieces with the same row bounds still form one measured prose row.
                let overlap = min($0.rect.maxY, line.rect.maxY) - max($0.rect.minY, line.rect.minY)
                let gap = max($0.rect.minX, line.rect.minX) - min($0.rect.maxX, line.rect.maxX)
                return min($0.size, line.fontSize) <= max($0.size, line.fontSize) * 0.75
                    && overlap >= max($0.rect.height, line.rect.height) * 0.8
                    && gap >= -0.5 && gap <= max($0.size, line.fontSize) * 0.5
            }) {
                rows[row].rect = rows[row].rect.union(line.rect)
                rows[row].size = max(rows[row].size, line.fontSize)
                rows[row].indices.append(index)
            } else {
                rows.append((line.rect, line.fontSize, [index]))
            }
        }
        // Several prose columns can lie over one picture. Keep each run open on its own
        // measure rather than letting the other column's next baseline break it.
        var runs: [[(rect: CGRect, size: CGFloat, indices: [Int])]] = []
        for row in rows {
            let next = runs.indices.last { index in
                let run = runs[index], last = run.last!
                let size = max(last.size, row.size)
                let leading = last.rect.minY - row.rect.minY
                let established = run.count >= 2 ? run[0].rect.minY - run[1].rect.minY : leading
                let openingIndent = run.count == 1 && last.rect.minX >= row.rect.minX
                    && last.rect.minX - row.rect.minX <= size * 1.2
                let ended = run.count >= 3 && last.rect.width < (run.map(\.rect.width).max() ?? 0) * minimumProseMeasure
                    && lines[last.indices[0]].text.last.map { ".!?”.".contains($0) } == true
                return !ended && abs(last.size - row.size) <= size * 0.1
                    && (abs(last.rect.minX - row.rect.minX) <= size * 0.25 || openingIndent)
                    && leading >= size * 0.8 && leading <= size * 2.2
                    && abs(leading - established) <= max(1, established * 0.25)
            }
            if let next { runs[next].append(row) }
            else { runs.append([row]) }
        }
        return runs.filter { $0.count >= minimumProseLines }.map { $0.map(\.indices) }
    }

    /// Duplicate knockout paint is one text run; equal words at adjacent positions are not.
    private static func distinctRow(_ row: [Int], in lines: [TextLine]) -> [Int] {
        var result: [Int] = []
        for index in row.sorted(by: { lines[$0].rect.minX < lines[$1].rect.minX }) {
            let line = lines[index]
            if !result.contains(where: {
                let other = lines[$0]
                return other.text == line.text && abs(other.rect.minX - line.rect.minX) <= 0.5
                    && abs(other.rect.minY - line.rect.minY) <= 0.5
                    && abs(other.rect.width - line.rect.width) <= 0.5
            }) { result.append(index) }
        }
        return result
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
        let rows = run.map { distinctRow($0, in: lines).map { lines[$0] } }
        let bounds = rows.map { $0.reduce(CGRect.null) { $0.union($1.rect) } }
        let measure = bounds.map(\.width).max() ?? 0
        guard measure > 0, bounds.dropLast().allSatisfy({ $0.width >= measure * minimumProseMeasure }),
              rows.joined().allSatisfy({ !$0.monospaced }) else { return false }
        let text = rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: " ")
        guard text.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).count >= minimumProseWords,
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
        let judgesLayer = imageBackedText && !content.requiresPageImage && !damagedEncoding
        let implausibleLayer = judgesLayer
            ? try TextLayerPlausibility.judge(lines: content.lines, language: options.language) { try measureInk([]) }
            : nil
        let sparseLayerWords = judgesLayer
            ? TextLayerPlausibility.sparseEnglishWords(lines: content.lines, language: options.language) : nil
        let noText = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A sparse layer may omit writing drawn as outlines, whatever its language (#192).
        // A layer already diagnosed as damaged belongs to the existing replacement/comparison
        // policy, not to the supplemental drawn-writing path. Pictures remain excluded.
        let drawsTextCandidate = !noText && !damagedEncoding && implausibleLayer == nil
            && !content.requiresPageImage && options.ocr.isAutomatic
        let drawnText = try drawsTextCandidate
            && TextLayerPlausibility.judgeImageOnly(lines: content.lines, language: options.language) {
                try measureInk(extracted.placedImages)
            }
        return PageEvidence(requiresPageImage: content.requiresPageImage, hasText: !noText,
                            characters: raw.count, replacementCharacters: replacements,
                            imageBackedText: imageBackedText, damagedEncoding: damagedEncoding,
                            implausibleLayer: implausibleLayer, drawnText: drawnText, sparseLayerWords: sparseLayerWords)
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
