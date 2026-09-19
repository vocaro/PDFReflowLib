import CoreGraphics
import Foundation

/// The document-wide evidence extraction keeps while pages are spilled to the workspace: the
/// hyphen-repair vocabulary, margin-furniture candidates, note-heading pages, chapter matches,
/// the document's body size and recurring sub-heading styles, and the running character budget.
/// `collect` folds one extracted page in; `resolved` decides what reconstruction needs.
struct DocumentEvidence {
    struct Resolved {
        /// What every page's reconstruction shares: the hyphen context, the size most of the
        /// document's native text is set in (#186), the bold sub-heading styles the book repeats
        /// often enough to trust (#218), and the numbered-note pages.
        var context: LayoutReconstructor.DocumentContext
        var furniturePlan: FurnitureDetector.Plan?
    }

    let chapterCandidates: [ChapterBoundaryReader.Candidate]
    let language: String
    private(set) var chapterStartPages: Set<Int> = []
    private(set) var hyphens: HyphenContext
    private var furniture = FurnitureDetector.Ledger()
    private(set) var numberedNotePages: Set<Int> = []
    /// Characters per type size over the native pages: the document's body (#186).
    private var bodyWeights: [Int: Int] = [:]
    /// The pages each recurring bold sub-heading style appears on (#218).
    private var labelStylePages: [LayoutReconstructor.LabelStyle: Int] = [:]
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
        // Retain heading evidence before removing furniture, after all extraction/OCR work.
        if suppliesVocabulary {
            LayoutReconstructor.addVocabulary(of: content, to: &hyphens.vocabulary)
        }
        if !content.recognized, !content.hasSyntheticTextStyle, !content.requiresPageImage {
            LayoutReconstructor.addBodyWeights(of: content.lines, to: &bodyWeights)
            // A bold sub-heading style counts once per page it appears on; `labelStyles(from:)`
            // keeps only the styles the book repeats (#218).
            for style in LayoutReconstructor.labelEvidence(on: content) {
                labelStylePages[style, default: 0] += 1
            }
        }
        if NumberedNoteDetector.hasHeading(on: content) { numberedNotePages.insert(content.number) }
        if options.removeRepeatedHeadersAndFooters { FurnitureDetector.collect(content, pageIndex: i, into: &furniture) }
        if content.recognized { recognizedPages += 1 }
    }

    /// Decides the document-wide values reconstruction needs and releases the furniture ledger.
    mutating func resolved(options: ConversionOptions) -> Resolved {
        let plan = options.removeRepeatedHeadersAndFooters ? FurnitureDetector.resolve(furniture) : nil
        furniture = FurnitureDetector.Ledger()
        let context = LayoutReconstructor.DocumentContext(
            hyphens: hyphens, language: language,
            documentBody: LayoutReconstructor.bodySize(weights: bodyWeights),
            labelStyles: LayoutReconstructor.labelStyles(from: labelStylePages),
            numberedNotePages: numberedNotePages)
        return Resolved(context: context, furniturePlan: plan)
    }
}
