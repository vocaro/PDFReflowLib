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
    /// Evidence that this book's font draws its line-end hyphen as another character (#233).
    private var lineEndSubstitutes: [Character: LineEndSubstituteTally] = [:]
    /// Characters per type size over the native pages: the document's body (#186).
    private var bodyWeights: [Int: Int] = [:]
    /// The pages each recurring bold sub-heading style appears on (#218).
    private var labelStylePages: [LayoutReconstructor.LabelStyle: Int] = [:]
    /// The display sizes the book's own tags call headings, page by page (#294).
    private var headingTally = HeadingRank.Tally()
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
            // A bold sub-heading style counts once per page it appears on; `labelStyles(from:)`
            // keeps only the styles the book repeats (#218).
            for style in LayoutReconstructor.labelEvidence(on: content) {
                labelStylePages[style, default: 0] += 1
            }
            // The sizes this page's tags call a heading, ranked once the book is read (#294).
            headingTally.record(content, pageIndex: i)
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
        let context = LayoutReconstructor.DocumentContext(
            hyphens: hyphens, language: language,
            documentBody: LayoutReconstructor.bodySize(weights: bodyWeights),
            labelStyles: LayoutReconstructor.labelStyles(from: labelStylePages),
            headingRank: HeadingRank(headingTally),
            numberedNotePages: numberedNotePages)
        return Resolved(context: context, furniturePlan: plan)
    }
}
