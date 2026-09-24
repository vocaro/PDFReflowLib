import Foundation
import Testing
@testable import PDFReflowLib

@Test(arguments: [848, 849, 860])
func warrenNotesReadDownEachColumnWithoutRewritingMarkers(_ number: Int) throws {
    let page = try SourceLayoutFixture.load("warren-\(number)").content()
    let input = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    let plan = try #require(ScannedEndnotes.plan(input, page: page, headingEvidence: false))
    #expect(plan.elements.count == input.count)
    #expect(plan.elements.compactMap { $0.line?.text }.sorted() == page.lines.map(\.text).sorted())
    let openings = plan.groups.keys.filter { plan.groups[$0] == $0 }.sorted()
        .compactMap { plan.elements[$0].line?.text }
    if number == 848 {
        #expect(openings[0].hasPrefix("I. 3 H"))
        #expect(openings[1].hasPrefix("a. 3 H"))
        #expect(openings[2] == "8. CE 479.")
        let sixtySeven = try #require(openings.firstIndex { $0.hasPrefix("67.") })
        let twelve = try #require(openings.firstIndex { $0.hasPrefix("12.") })
        #expect(twelve < sixtySeven)
        let sixtyNine = try #require(plan.elements.firstIndex { $0.line?.text.hasPrefix("69.") == true })
        let wrap = try #require(plan.elements.firstIndex { $0.line?.text == "226 (Miller)." })
        #expect(plan.groups[wrap] == sixtyNine)
    }
}

@Test func unheadedNumberedColumnsDoNotBecomeAnEndnoteApparatus() throws {
    var page = try SourceLayoutFixture.load("warren-848").content()
    page.lines.removeAll { $0.text.contains("NOTES TO PAGES") }
    let input = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    #expect(ScannedEndnotes.plan(input, page: page, headingEvidence: false) == nil)
    #expect(ScannedEndnotes.plan(input, page: page, headingEvidence: true) != nil)
}

@Test func warrenNoteContinuationsBecomeWholeParagraphs() throws {
    var page = try SourceLayoutFixture.load("warren-848").content()
    page.hasSyntheticTextStyle = true
    // A page-backed scan is retained separately as its reference, not a crop in its text.
    page.graphics = []; page.pictures = []
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let texts = blocks.map(\.text)
    #expect(texts.contains { $0.hasPrefix("69. 7 H") && $0.hasSuffix("226 (Miller).") })
    #expect(!texts.contains("226 (Miller)."))
}

@Test func endnoteLinksRequireSequenceScopeAndPrintedPageEvidence() throws {
    let page = try SourceLayoutFixture.load("warren-848").content()
    var linker = NoteLinker()
    linker.collect(page)
    #expect(linker.target(number: 5, printedPage: 63) != nil)
    #expect(linker.target(number: 5, printedPage: 82) == nil)
    // The source's 1, 2 and 3 are read I., a. and 8.; none is silently corrected.
    #expect(linker.target(number: 1, printedPage: 63) == nil)
    #expect(linker.target(number: 2, printedPage: 63) == nil)
    #expect(linker.target(number: 3, printedPage: 63) == nil)
    let text = InlineText(elements: [.text("A reported observation.", []), .text("5", .superscript)])
    let block = ReflowBlock(content: .paragraph(text), page: 100)
    #expect(linker.applying(to: block, pageLabels: [:]) == block)
    let linked = linker.applying(to: block, pageLabels: [100: "63"])
    #expect(linked.text == block.text)
    #expect(try EPUBTextEncoder.piece(for: linked, imagePaths: [:]).markup.contains("epub:type=\"noteref\""))
    linker.collect(page) // Duplicate scopes have no unique target.
    #expect(linker.target(number: 5, printedPage: 63) == nil)
}

@Test func endnoteWriterResolvesActualSpineAndRemovesMissingTargets() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let text = InlineText(elements: [.text("Observation", []),
        .link(.note("note-2-10-20"), InlineText("5", style: .superscript)),
        .link(.note("note-missing"), InlineText("6", style: .superscript))])
    let book = ReflowDocument(metadata: .init(title: "Notes", language: "en"), blocks: [
        .init(content: .sourcePage(1), page: 1),
        .init(content: .paragraph(text), page: 1),
        .init(content: .paragraph(InlineText(String(repeating: "Text ", count: 12_000))), page: 1),
        .init(content: .sourcePage(2), page: 2),
        .init(content: .paragraph(InlineText("5. Source citation.")), endnoteID: "note-2-10-20", page: 2),
    ], assets: [])
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: dir, progress: { _ in })
    let folder = dir.appendingPathComponent("EPUB")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("chapter-") }
    let chapters = try Dictionary(uniqueKeysWithValues: names.map {
        ($0, try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8))
    })
    let target = try #require(chapters.first { $0.value.contains("id=\"note-2-10-20\"") })
    let reference = try #require(chapters.first { $0.value.contains("Observation") })
    #expect(target.key != reference.key)
    #expect(reference.value.contains("href=\"\(target.key)#note-2-10-20\""))
    #expect(reference.value.contains("<sup>6</sup>"))
    #expect(chapters.values.allSatisfy { !$0.contains("pdfreflow:note:") })
    #expect(target.value.contains("epub:type=\"endnote\" role=\"note\""))
}

@Test func mathExponentsAndExistingLinksAreNotNoteReferences() throws {
    var linker = NoteLinker()
    linker.collect(try SourceLayoutFixture.load("warren-848").content())
    for text in [
        InlineText(elements: [.text("x", []), .text("5", .superscript)]),
        InlineText(elements: [.text("value = term", []), .text("5", .superscript)]),
        InlineText(elements: [.text("observation", []), .text("5", .superscript), .text("th", [])]),
        InlineText(elements: [.link(.external("https://example.org"), InlineText("observation5"))]),
    ] {
        let block = ReflowBlock(content: .paragraph(text), page: 100)
        #expect(linker.applying(to: block, pageLabels: [100: "63"]) == block)
    }
}

@Test func endnoteIdentifiersAreUniqueAndCannotBecomeMarkup() {
    let note = ReflowBlock(content: .paragraph(InlineText("5. Citation")), endnoteID: "note-1", page: 1)
    #expect(throws: ReflowDocument.ValidationError.invalidEndnote) {
        try ReflowDocument(metadata: .init(title: "Notes", language: "en"), blocks: [note, note], assets: []).validate()
    }
    var invalid = note
    invalid.endnoteID = "note-\" onclick=\"bad"
    #expect(throws: ReflowDocument.ValidationError.invalidEndnote) {
        try ReflowDocument(metadata: .init(title: "Notes", language: "en"), blocks: [invalid], assets: []).validate()
    }
}

@Test func warrenLastNotePageStillHasEntryBoundaries() throws {
    let fixture = try SourceLayoutFixture.load("warren-905")
    var page = fixture.content()
    page.hasSyntheticTextStyle = true
    page.pictures = []; page.graphics = []
    let input = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    #expect(ScannedEndnotes.plan(input, page: page, headingEvidence: false) != nil)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.count { $0.endnoteID != nil } >= 80)
    let source = try PDFPageSource(url: URL(fileURLWithPath: "corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf"))
    let actual = try PageReader.read(pageIndex: 904, from: source, limit: 100_000,
                                     options: ConversionOptions(), structure: nil).content
    #expect(ScannedEndnotes.hasHeading(actual))
    let direct = ScannedEndnotes.plan(actual.lines.map { .init(rect: $0.rect, line: $0) },
                                     page: actual, headingEvidence: false)
    #expect(direct != nil)
    let output = LayoutReconstructor.blocks(page: actual, images: [], vocabulary: [], warnings: &warnings)
    #expect(output.count { $0.endnoteID != nil } >= 80)
}

@Test func warrenMergedNoteRowStaysUnlinkedWhenCharacterPositionsCannotDivideIt() throws {
    let source = try PDFPageSource(url: URL(fileURLWithPath: "corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf"))
    let page = try PageReader.read(pageIndex: 880, from: source, limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    #expect(page.lines.contains { $0.text.contains("CE 1027, 283.") })
    let plan = ScannedEndnotes.plan(page.lines.map { .init(rect: $0.rect, line: $0) },
                                    page: page, headingEvidence: false)
    let accepted = try #require(plan)
    let ambiguous = try #require(accepted.elements.firstIndex { $0.line?.text.contains("CE 1027, 283.") == true })
    #expect(accepted.groups[ambiguous] == nil)
}

@Test func warrenEndnoteSourceRunKeepsEveryLineInItsPlan() throws {
    let source = try PDFPageSource(url: URL(fileURLWithPath: "corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf"))
    for number in 845...906 {
        let page = try PageReader.read(pageIndex: number - 1, from: source, limit: 100_000,
                                       options: ConversionOptions(), structure: nil).content
        let plan = try #require(ScannedEndnotes.plan(page.lines.map { .init(rect: $0.rect, line: $0) },
                                                    page: page, headingEvidence: false),
                                Comment(rawValue: "Source page \(number)"))
        #expect(plan.elements.compactMap { $0.line?.text }.sorted() == page.lines.map(\.text).sorted(),
                Comment(rawValue: "Source page \(number)"))
    }
}
