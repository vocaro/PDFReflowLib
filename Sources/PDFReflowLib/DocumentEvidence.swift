import CoreGraphics
import Foundation

/// The document-wide evidence extraction keeps while pages are spilled to the workspace: the
/// hyphen-repair vocabulary, margin-furniture candidates, note-heading pages, chapter matches,
/// the document's body size, recurring sub-heading styles, the heading sizes its tags rank, and
/// the running character budget.
/// `collect` folds one extracted page in; `resolved` decides what reconstruction needs.
struct DocumentEvidence {
    struct Resolved {
        /// What every page's reconstruction shares: the hyphen context, the size most of the
        /// document's native text is set in (#186), the bold sub-heading styles the book repeats
        /// often enough to trust (#218), the heading sizes its tags rank (#294), and the
        /// numbered-note pages.
        var context: LayoutReconstructor.DocumentContext
        var furniturePlan: FurnitureDetector.Plan?
        /// Source-backed outline headings established across pages (#211).
        var formOutline: [Int: [FormOutlineEvidence.Candidate]]
        var formOutlineBaseLevel: Int
        var formOutlineOuterTier: Int
    }

    let chapterCandidates: [ChapterBoundaryReader.Candidate]
    let language: String
    private(set) var chapterStartPages: Set<Int> = []
    private(set) var hyphens: HyphenContext
    private var furniture = FurnitureDetector.Ledger()
    /// The words each page's margin lines hold, kept aside until the furniture plan says which
    /// of those lines the reader will see. A running head set at the body size in ordinary
    /// capitalization is a page's furniture but an ordinary-looking word to the vocabulary, so
    /// the vocabulary is the text stream the reader gets, not the one extraction read (#184).
    private var marginWords: [Int: [Int: [String]]] = [:]
    private(set) var numberedNotePages: Set<Int> = []
    private var scannedNotePages: Set<Int> = []
    private(set) var noteLinker = NoteLinker()
    /// Evidence that this book's font draws its line-end hyphen as another character (#233).
    private var lineEndSubstitutes: [Character: LineEndSubstituteTally] = [:]
    /// Characters per type size over the native pages: the document's body (#186).
    private var bodyWeights: [Int: Int] = [:]
    /// The pages each recurring bold sub-heading style appears on (#218).
    private var labelStylePages: [LayoutReconstructor.LabelStyle: Int] = [:]
    /// The display sizes the book's own tags call headings, page by page (#294).
    private var headingTally = HeadingRank.Tally()
    private var formOutlineCandidates: [FormOutlineEvidence.Candidate] = []
    private var slideTextPages = 0
    private var slidePages = 0
    private var slideCount = 0
    private var slideBounds: CGRect?
    private var uniformLandscape = true
    private(set) var recognizedPages = 0
    private(set) var characters = 0

    init(chapterCandidates: [ChapterBoundaryReader.Candidate], language: String) {
        self.chapterCandidates = chapterCandidates
        self.language = language
        // An English document's word breaks may consult the system lexicon where its own words
        // are silent (#186).
        hyphens = HyphenContext(usesEnglishLexicon: EnglishText.isDeclared(language))
    }

    /// Folds one finished page in. `suppliesVocabulary` is false for retained unreadable text,
    /// which supplies no hyphen-repair vocabulary (#38).
    mutating func collect(_ content: PageContent, pageIndex i: Int, suppliesVocabulary: Bool,
                          options: ConversionOptions) throws {
        characters += content.lines.reduce(0) { $0 + $1.text.count }
        guard characters <= options.maximumCharacters else { throw ConversionError.resourceLimit("document text") }
        slideCount += 1
        if let slideBounds, slideBounds != content.bounds { uniformLandscape = false }
        slideBounds = content.bounds
        if content.bounds.width <= content.bounds.height { uniformLandscape = false }
        if !content.lines.isEmpty {
            slideTextPages += 1
            if !SlideDeck.title(in: content).isEmpty { slidePages += 1 }
        }
        if let chapter = chapterCandidates.first(where: { $0.page == content.number }),
           ChapterBoundaryReader.matches(chapter, page: content) {
            chapterStartPages.insert(content.number)
        }
        if options.removeRepeatedHeadersAndFooters { FurnitureDetector.collect(content, pageIndex: i, into: &furniture) }
        // Retain heading evidence before removing furniture, after all extraction/OCR work.
        if suppliesVocabulary {
            let margins = furniture.marginLines[i] ?? []
            LayoutReconstructor.addVocabulary(of: content, skippingLines: margins, to: &hyphens.vocabulary)
            LayoutReconstructor.tallyLineEndSubstitutes(of: content, skippingLines: margins,
                                                        into: &lineEndSubstitutes)
            for lineIndex in margins.sorted() {
                marginWords[i, default: [:]][lineIndex] = LayoutReconstructor.words(of: content.lines[lineIndex])
            }
        }
        if !content.recognized, !content.hasSyntheticTextStyle, !content.requiresPageImage {
            LayoutReconstructor.addBodyWeights(of: content.lines, to: &bodyWeights)
            if formOutlineCandidates.count < 10_000 {
                formOutlineCandidates += FormOutlineEvidence.candidates(on: content)
            }
            // A bold sub-heading style counts once per page it appears on; `labelStyles(from:)`
            // keeps only the styles the book repeats (#218).
            for style in LayoutReconstructor.labelEvidence(on: content) {
                labelStylePages[style, default: 0] += 1
            }
            // The sizes this page's tags call a heading, ranked once the book is read (#294).
            headingTally.record(content, pageIndex: i)
        }
        if ScannedEndnotes.hasHeading(content) {
            scannedNotePages.insert(content.number)
            noteLinker.collect(content)
        }
        if NumberedNoteDetector.hasHeading(on: content) { numberedNotePages.insert(content.number) }
        if content.recognized { recognizedPages += 1 }
    }

    /// Decides the document-wide values reconstruction needs and releases the furniture ledger.
    mutating func resolved(options: ConversionOptions) -> Resolved {
        let plan = options.removeRepeatedHeadersAndFooters ? FurnitureDetector.resolve(furniture) : nil
        furniture = FurnitureDetector.Ledger()
        // A margin line the plan leaves on the page is text the reader keeps, so it supplies
        // vocabulary after all; one the plan takes never reaches the reader and supplies none.
        for (pageIndex, lines) in marginWords {
            let removed = plan?.removals(onPageAt: pageIndex) ?? []
            for (lineIndex, words) in lines where !removed.contains(lineIndex) {
                hyphens.vocabulary.formUnion(words)
            }
        }
        marginWords = [:]
        hyphens.lineEndSubstitute = LayoutReconstructor.lineEndSubstitute(from: lineEndSubstitutes)
        lineEndSubstitutes = [:]
        let documentBody = LayoutReconstructor.bodySize(weights: bodyWeights)
        let context = LayoutReconstructor.DocumentContext(
            hyphens: hyphens, language: language,
            documentBody: documentBody,
            labelStyles: LayoutReconstructor.labelStyles(from: labelStylePages),
            headingRank: HeadingRank(headingTally),
            numberedNotePages: numberedNotePages,
            scannedNotePages: scannedNotePages,
            slideDeck: slideCount >= 3 && uniformLandscape && slideTextPages > 0
                && slidePages * 3 >= slideTextPages * 2)
        let establishedOutline = FormOutlineEvidence.established(formOutlineCandidates)
        let outline = Dictionary(grouping: establishedOutline, by: \.page)
        formOutlineCandidates = []
        // A form's large title lines sit above its outline. Source Pro Se 1 has two distinct
        // display sizes above its 11-point body, so its Roman, capital and numeric tiers rank
        // at h4, h5 and h6. An outline with no display title starts at h2.
        let displays = Set(bodyWeights.keys.filter { CGFloat($0) > (documentBody ?? 12) * 1.1 })
        return Resolved(context: context, furniturePlan: plan, formOutline: outline,
                        formOutlineBaseLevel: min(4, 2 + displays.count),
                        formOutlineOuterTier: establishedOutline.compactMap(\.tier).min() ?? 0)
    }
}
