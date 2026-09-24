import Foundation
import Testing
@testable import PDFReflowLib

private func styledSlide(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    for index in page.lines.indices {
        guard let source = fixture.attributedLines.first(where: { $0.text == page.lines[index].text }),
              source.text.contains("Analytics Optimized Data Store") || source.text == "AODS1"
        else { continue }
        let line = page.lines[index]
        page.lines[index] = TextLine(content: NativeTextReader.inlineText(from: source.attributedString()),
                                     rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
    }
    return page
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/165"))
func sourceSlideTitlesFollowTheTopBand() throws {
    for (fixture, title) in [
        ("earthdata-sparse-2", ["Earth Observing System Data and", "Information System (EOSDIS)"]),
        ("earthdata-sparse-3", ["Over time, EOSDIS archive volumes", "increase exponentially"]),
        ("earthdata-sparse-6", ["Solution: Data-proximal Analysis"]),
        ("earthdata-10", ["Architectural Concept"]),
        ("earthdata-16", ["Open Pipeline Provides Outputs at Different", "Stages Appropriate for a Diverse User Base"]),
    ] {
        let page = try SourceLayoutFixture.load(fixture).content()
        #expect(SlideDeck.title(in: page).map(\.text) == title)
    }
    let control = try SourceLayoutFixture.load("noaa-body-1691").content()
    #expect(SlideDeck.title(in: control).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/165"))
func slideTenTitleIsSmallerThanItsBody() throws {
    let page = try SourceLayoutFixture.load("earthdata-10").content()
    let title = try #require(page.lines.first { $0.text == "Architectural Concept" })
    let typography = PageTypography(page: page)
    // Main's ordinary size rule cannot identify this source title; its top-band place can.
    #expect(!LayoutReconstructor.isTitleSized(title, in: page.lines, typography: typography,
                                             judgesTitleWords: false))
    #expect(SlideDeck.title(in: page) == [title])
    var warnings: [ConversionWarning] = []
    let ordinary = LayoutReconstructor.blocks(page: page, images: [],
        context: .init(), warnings: &warnings)
    #expect(!ordinary.contains { block in
        if case let .heading(_, text, _) = block.content { return text.text.contains("Architectural Concept") }
        return false
    })
    let deck = LayoutReconstructor.blocks(page: page, images: [],
        context: .init(slideDeck: true), warnings: &warnings)
    #expect(deck.contains { block in
        if case let .heading(_, text, level) = block.content {
            return level == 2 && text.text.contains("Architectural Concept")
        }
        return false
    })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/165"))
func exactSlideOverprintsLoseOnlyTheirSecondImpression() throws {
    let source = try SourceLayoutFixture.load("earthdata-18").content()
    let impressions = source.lines.filter { $0.text == "Cumulus" }
    #expect(impressions.count == 2)
    let label = try #require(impressions.first)
    var shifted = label
    shifted.rect.origin.x += 0.2
    let lines = impressions + [shifted]
    #expect(NativeTextReader.withoutOverprints(lines) == [0, 2])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/165"))
func repeatedSlideNotesStayOnEachSourcePage() throws {
    var pages = try (16...18).map { try styledSlide("earthdata-\($0)") }
    _ = FurnitureDetector.strip(&pages)
    for page in pages {
        #expect(page.lines.contains { $0.text == "1 Analytics Optimized Data Store" })
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/165"))
func documentEvidenceRecognizesADeckFromSourcePages() throws {
    var evidence = DocumentEvidence(chapterCandidates: [], language: "en")
    let options = ConversionOptions()
    for (index, number) in (16...18).enumerated() {
        let page = try SourceLayoutFixture.load("earthdata-\(number)").content()
        try evidence.collect(page, pageIndex: index, suppliesVocabulary: true, options: options)
    }
    #expect(evidence.resolved(options: options).context.slideDeck)
    var book = DocumentEvidence(chapterCandidates: [], language: "en")
    for index in 0..<3 {
        var page = try SourceLayoutFixture.load("noaa-body-1691").content()
        page.number = index + 1
        try book.collect(page, pageIndex: index, suppliesVocabulary: true, options: options)
    }
    #expect(!book.resolved(options: options).context.slideDeck)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/165"))
func diagramLabelsStayBelowTheirSlideTitle() throws {
    let page = try SourceLayoutFixture.load("earthdata-16").content()
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [],
        context: .init(slideDeck: true), warnings: &warnings)
    let headings = blocks.compactMap { block -> String? in
        if case let .heading(_, text, _) = block.content { return text.text }
        return nil
    }
    #expect(headings == ["Open Pipeline Provides Outputs at Different Stages Appropriate for a Diverse User Base"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/175"))
func lowerLeftSlideNotesReadAfterTheirDiagrams() throws {
    for number in [19, 20] {
        let page = try styledSlide("earthdata-\(number)")
        var warnings: [ConversionWarning] = []
        let blocks = LayoutReconstructor.blocks(page: page, images: [],
            context: .init(slideDeck: true), warnings: &warnings)
        let baselineNote = try #require(blocks.firstIndex { $0.text.contains("Analytics Optimized Data Store") })
        let baselineDiagram = try #require(blocks.lastIndex {
            $0.text.contains("Interpretation") || $0.text.contains("Exploration")
        })
        #expect(baselineNote < baselineDiagram)
        let ordered = SlideDeck.notesLast(blocks, on: page)
        let note = try #require(ordered.firstIndex { $0.text.contains("Analytics Optimized Data Store") })
        let diagram = try #require(ordered.lastIndex {
            $0.text.contains("Interpretation") || $0.text.contains("Exploration")
        })
        #expect(note > diagram)
        #expect(ordered.filter { !$0.text.contains("Analytics Optimized Data Store") }.map(\.text)
            == blocks.filter { !$0.text.contains("Analytics Optimized Data Store") }.map(\.text))
    }
}
