import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func furniturePage(_ number: Int, header: String, y: Double = 752,
                           font: Double = 10, bodyY: Double = 700) -> PageContent {
    PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
        TextLine(text: header, rect: CGRect(x: 40, y: y, width: 250, height: 10), fontSize: font),
        TextLine(text: "Body paragraph \(number) stays available.",
                 rect: CGRect(x: 40, y: bodyY, width: 400, height: 12), fontSize: 12),
    ], graphics: [])
}

@Test func reportHeadersDisappearWhileSourceBodyAndChapterOpeningsSurvive() throws {
    let numbers = Array(19...26) + Array(65...71) + Array(471...476)
    var pages = try numbers.map { try SourceLayoutFixture.load("911-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    for (before, after) in zip(original, pages) {
        // Source-reviewed chapter titles lie well below the running-header band.
        if [19, 65].contains(before.number) {
            #expect(after.lines.map(\.text) == before.lines.map(\.text))
        } else {
            let header = try #require(before.lines.max { $0.rect.midY < $1.rect.midY })
            #expect(!after.lines.contains { $0.text == header.text })
            #expect(after.lines.map(\.text) == before.lines.filter { $0.rect.midY < 550 }.map(\.text))
            #expect(warnings.contains { $0.page == before.number && $0.code == .furnitureRemoved })
        }
    }
}

@Test func chapterLocalAndAlternatingFurnitureDoesNotNeedHalfTheBook() {
    var pages = (1...40).map { furniturePage($0, header: "Unique title \($0 * 17)") }
    for i in 10..<18 { pages[i] = furniturePage(i + 1, header: i.isMultiple(of: 2) ? "Left chapter" : "Right chapter") }
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page).compactMap { $0 } == Array(11...18))
    #expect(pages[10..<18].allSatisfy { $0.lines.count == 1 })
    #expect(pages[..<10].allSatisfy { $0.lines.count == 2 })
}

@Test func shortSourceNotesRunCombinesLeadingAndTrailingFolios() throws {
    var pages = try (579...585).map { try SourceLayoutFixture.load("911-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == [581, 582, 583])
    for (before, after) in zip(original, pages) {
        // Only chapter 12 supplies three occurrences. Neighboring two-page runs
        // retain their text; shortening the minimum would overstate the evidence.
        let expected = (581...583).contains(before.number)
            ? before.lines.filter { $0.rect.midY < 550 } : before.lines
        #expect(after.lines.map(\.text) == expected.map(\.text))
    }
}

@Test func mirroredBoundaryFoliosRequireMatchingOffsetsAndMeaningfulInternalDigits() {
    var pages = (1...3).map { n in
        furniturePage(n, header: n.isMultiple(of: 2) ? "\(n + 18) NOTES TO CHAPTER 12" : "NOTES TO CHAPTER 12 \(n + 18)")
    }
    #expect(LayoutReconstructor.stripFurniture(&pages).count == 3)
    let controls = [
        ["NOTES TO CHAPTER 12 19", "21 NOTES TO CHAPTER 12", "NOTES TO CHAPTER 12 21"],
        ["NOTES TO CHAPTER 11 19", "20 NOTES TO CHAPTER 12", "NOTES TO CHAPTER 13 21"],
        ["SECTION 1 SUMMARY", "SECTION 2 SUMMARY", "SECTION 3 SUMMARY"],
    ]
    for headers in controls {
        var pages = headers.enumerated().map { furniturePage($0.offset + 1, header: $0.element) }
        #expect(LayoutReconstructor.stripFurniture(&pages).isEmpty)
        #expect(pages.map { $0.lines[0].text } == headers)
    }
}

@Test(arguments: [33, 50, 51])
func reportMapLabelsRemainInsidePreservedGraphics(number: Int) throws {
    let page = try SourceLayoutFixture.load("911-\(number)").content()
    let names = number == 33 ? ["BOST", "ORK", "INDIANAPOLIS", "Indianapolis Center"]
        : number == 50 ? ["Boston", "New York City"] : ["Dulles", "Pentagon", "Newark", "Shanksville, PA"]
    let labels = page.lines.filter { names.contains($0.text) && $0.rect.midY > 350 && $0.rect.midY < 500 }
    #expect(labels.count == (number == 33 ? 5 : 4))
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(regions.count == (number == 33 ? 2 : 1))
    for label in labels {
        #expect(regions.contains { $0.contains(label.rect) })
    }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    // Geographic names in timeline prose can legitimately reappear. Only the
    // detached map-label blocks and their heading promotion are forbidden here.
    #expect(!blocks.contains { names.contains($0.text) })
    #expect(blocks.filter { if case .image = $0.content { true } else { false } }.count == regions.count)
}

@Test func furnitureRequiresStablePositionStyleAndNearbyDistinctPages() {
    let controls: [[PageContent]] = [
        (1...6).map { furniturePage($0 * 10, header: "Scattered heading") },
        (1...6).map { furniturePage($0, header: "Repeated body", y: 650, bodyY: 620) },
        (1...6).map { furniturePage($0, header: "Adjacent prose", bodyY: 738) },
        (1...6).map { furniturePage($0, header: "Drifting heading", y: 723 + Double($0) * 9) },
        (1...3).map { furniturePage($0, header: "Changing typography", font: Double($0) * 10) },
        (1...2).map { furniturePage($0, header: "Only two pages") },
        (1...5).map { _ in furniturePage(1, header: "Duplicate page number") },
    ]
    for original in controls {
        var pages = original
        #expect(LayoutReconstructor.stripFurniture(&pages).isEmpty)
        #expect(zip(pages, original).allSatisfy { $0.lines.map(\.text) == $1.lines.map(\.text) })
    }
}

@Test func furnitureRemovalPreservesOnlyContentAndMatchingBodyTitles() {
    var pages = (1...6).map { furniturePage($0, header: "Recurring title") }
    pages[2].lines.append(TextLine(text: "Recurring title", rect: CGRect(x: 40, y: 600, width: 300, height: 24), fontSize: 24))
    _ = LayoutReconstructor.stripFurniture(&pages)
    #expect(pages[2].lines.contains { $0.text == "Recurring title" && $0.fontSize == 24 })
    var lone = (1...6).map { n -> PageContent in
        var page = furniturePage(n, header: "Only content"); page.lines.removeLast(); return page
    }
    #expect(LayoutReconstructor.stripFurniture(&lone).isEmpty)
    #expect(lone.allSatisfy { $0.lines.count == 1 })
}

@Test func numericFootersAndOffsetPageBoundsAreSupported() {
    var pages = (1...6).map { n -> PageContent in
        var page = furniturePage(n, header: "Body heading \(n * 17)")
        page.lines.append(TextLine(text: "\(n + 100)", rect: CGRect(x: 40, y: 24, width: 20, height: 10), fontSize: 10))
        page.bounds.origin.y = 200
        for i in page.lines.indices { page.lines[i].rect.origin.y += 200 }
        return page
    }
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.count == 6)
    #expect(pages.allSatisfy { $0.lines.count == 2 })
}

@Test func clientCanRetainHeadersThroughThePublicConversionOption() async throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = fixtureURL("prose.pdf")
    let output = directory.appendingPathComponent("headers.epub")
    var options = ConversionOptions()
    options.removeRepeatedHeadersAndFooters = false
    let report = try await PDFConverter().convert(from: source, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    let html = try archive.chapter()
    #expect(html.components(separatedBy: "PDF REFLOW TEST BOOK").count - 1 == 3)
    #expect(!report.warnings.contains { $0.code == .furnitureRemoved })
    #expect(report.pageCount == 3 && report.reflowedPageCount == 3)
}

@Test func chapterPageFoliosSurviveNearbyFigureTextWithoutEnteringProse() {
    var pages = (1...8).map { n -> PageContent in
        var page = furniturePage(n, header: "Unique title \(n * 17)")
        page.lines.append(TextLine(text: "4-\(n)", rect: CGRect(x: 540, y: 24, width: 30, height: 10), fontSize: n.isMultiple(of: 2) ? 12.31 : 10))
        // Fallback pages estimate font size from geometry instead of attributed text.
        // Caption fragments near the footer do not make the numeric folio body text.
        page.lines.append(TextLine(text: "Caption \(n)", rect: CGRect(x: 40, y: 37, width: 200, height: 10), fontSize: 10))
        return page
    }
    #expect(LayoutReconstructor.stripFurniture(&pages).count == 8)
    #expect(pages.allSatisfy { page in
        !page.lines.contains { $0.text == "4-\(page.number)" }
            && page.lines.contains { $0.text == "Caption \(page.number)" }
    })
}

@Test func faaShiftedFoliosDoNotReappearOnDifferentPageSizes() throws {
    var pages = try [363, 364, 365, 437, 438, 439].map { try SourceLayoutFixture.load("faa-\($0)").content() }
    let original = pages
    let folios = ["14-29", "14-30", "14-31", "17-15", "17-16", "17-17"]
    _ = LayoutReconstructor.stripFurniture(&pages)
    for (index, page) in pages.enumerated() {
        #expect(page.lines.map(\.text) == original[index].lines.filter { $0.text != folios[index] }.map(\.text))
    }
}

@Test func lowerMarginOutsideExistingFooterBandKeepsLayoutEvidence() {
    var pages = (1...6).map { n -> PageContent in
        var page = furniturePage(n, header: "Unique title \(n * 17)")
        page.lines.append(TextLine(text: "\(n)", rect: CGRect(x: 300, y: 62, width: 10, height: 10), fontSize: 10))
        return page
    }
    let original = pages
    #expect(LayoutReconstructor.stripFurniture(&pages).isEmpty)
    #expect(zip(pages, original).allSatisfy { $0.lines.map(\.text) == $1.lines.map(\.text) })
}

@Test func stackedMarginRowsGoAsOneBlockOrNotAtAll() throws {
    var pages = try (24...27).map { try SourceLayoutFixture.load("p596-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    // The running foot and the table's "(continued)" marker stand closer together than a line
    // height, so neither row is set apart on its own and the old single-row rule kept both.
    #expect(warnings.map(\.page) == [25, 26, 27])
    for (before, after) in zip(original, pages) {
        let block = before.lines.filter { $0.text == "(继续)" || $0.text.contains("596 号刊物") }
        #expect(block.count == 2)
        // Page 24's block is worded differently: a table footnote printed only there stands
        // with those two rows, so nothing of that page's foot goes.
        let expected = before.number == 24 ? before.lines
            : before.lines.filter { line in !block.contains { $0.rect == line.rect } }
        #expect(after.lines.map(\.text) == expected.map(\.text))
        // The repeated EIC table head is nine rows deep, past the block's line ceiling, and its
        // column titles are content: the head band keeps every page's table intact.
        #expect(after.lines.contains { $0.text.contains("低收入家庭福利优惠") })
        #expect(after.lines.contains { $0.text.contains("已婚联合报税") })
    }
}

@Test func repeatedSlideTitlesAreNotAStackedRunningHead() throws {
    // Three consecutive slides print the same two-line title. The lines stand closer than a line
    // height, so they form one block, but it reaches to 0.82 of the page: a title set that deep
    // is the slide's heading, not a running head, and must survive its own repetition.
    var pages = try (16...18).map { try SourceLayoutFixture.load("earthdata-\($0)").content() }
    let original = pages
    #expect(pages.allSatisfy { page in
        page.lines.filter { $0.rect.midY > page.bounds.height * 0.84 }.count == 2
    })
    #expect(LayoutReconstructor.stripFurniture(&pages).isEmpty)
    #expect(zip(pages, original).allSatisfy { $0.lines.map(\.text) == $1.lines.map(\.text) })
}

@Test(arguments: ["blue-5", "blue-12"])
func syntheticScanMarginsKeepExistingRepeatedArtifactCleanup(name: String) throws {
    let source = try SourceLayoutFixture.load(name).content()
    var pages = (1...6).map { n -> PageContent in
        var page = source; page.number = n; page.hasSyntheticTextStyle = true; return page
    }
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.count == pages.count)
    for page in pages {
        let interior = source.lines.filter { $0.rect.midY >= source.bounds.minY + source.bounds.height * 0.07
            && $0.rect.midY <= source.bounds.minY + source.bounds.height * 0.93 }
        #expect(page.lines.map(\.text) == interior.map(\.text))
    }
    // Mixed-size, sparsely positioned native lines must not enter the scan-only rule.
    var native = (1...6).map { n in furniturePage(n * 10, header: "I") }
    #expect(LayoutReconstructor.stripFurniture(&native).isEmpty)
}

@Test func documentWideMarginSlotCarriesTheShortestNotesRuns() throws {
    // #10. The report's notes reach chapters whose notes fill two pages, and transition heads
    // name two chapters at once, so no three consecutive pages word their head alike. Every one
    // of them stands in the same margin slot the book keeps for 538 of its 585 pages, which is
    // the evidence the words withhold. Pages 19 and 65 are source-reviewed chapter openings:
    // they vacate the slot, and their titles stand lower and larger.
    let numbers = [19] + Array(20...26) + Array(65...71) + Array(471...476) + Array(579...585)
    var pages = try numbers.map { try SourceLayoutFixture.load("911-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    for short in [579, 580, 584, 585] {
        #expect(warnings.contains { $0.page == short && $0.code == .furnitureRemoved })
    }
    for (before, after) in zip(original, pages) {
        if [19, 65].contains(before.number) {
            #expect(after.lines.map(\.text) == before.lines.map(\.text))
        } else {
            // Exactly the outermost margin row goes; every other line of the page survives.
            #expect(after.lines.map(\.text) == before.lines.filter { $0.rect.midY < 550 }.map(\.text))
        }
    }
}

@Test func marginSlotEvidenceNeedsTheWholeBookNotAnExcerpt() throws {
    // The same seven notes pages on their own establish no slot: three removals out of seven
    // pages are a run, not a place the document keeps. Over-removal is the worse failure, so
    // short runs are admitted only where the book itself has stated the slot.
    var pages = try (579...585).map { try SourceLayoutFixture.load("911-\($0)").content() }
    let original = pages
    #expect(LayoutReconstructor.stripFurniture(&pages).map(\.page) == [581, 582, 583])
    for (before, after) in zip(original, pages) where ![581, 582, 583].contains(before.number) {
        #expect(after.lines.map(\.text) == before.lines.map(\.text))
    }
}

@Test func genuineTopOfPageSectionHeadingsAreNeverMarginSlotCandidates() throws {
    // Positive controls on the keep side. Our Flag sets its section titles at the very top of
    // the page at 22 pt and has no running head at all; the Fed's running head is 8 pt at 0.951
    // of the page while its section titles are 14 pt and larger, lower down. Neither book may
    // lose a line to margin evidence.
    for (prefix, numbers) in [("flag", [7, 9, 27, 30, 31]), ("fed", [13, 32, 45, 46, 54, 75, 77, 103, 109, 123])] {
        var pages = try numbers.map { try SourceLayoutFixture.load("\(prefix)-\($0)").content() }
        let original = pages
        _ = LayoutReconstructor.stripFurniture(&pages)
        for (before, after) in zip(original, pages) {
            let titles = before.lines.filter { $0.fontSize >= 14 && $0.rect.midY > before.bounds.height * 0.85 }
            #expect(titles.allSatisfy { title in after.lines.contains { $0.text == title.text } })
        }
    }
}

@Test func noaaChapterPageRunningFootGoesWhileItsChapterOpeningStays() throws {
    // #184. NOAA sets `23-2 | US Caribbean` at the body size in ordinary capitalization, so
    // nothing on one page separates it from prose, and every page words it differently. The
    // leading `chapter-page` number normalizes against a consistent physical-page offset, the
    // way a bare folio does, leaving the chapter and the words meaningful.
    var pages = try (1050...1056).map { try SourceLayoutFixture.load("noaa-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == Array(1051...1056))
    for (before, after) in zip(original, pages) {
        let furniture = ["Fifth National Climate Assessment", "23-\(before.number - 1049) | US Caribbean"]
        let expected = before.number == 1050 ? before.lines.map(\.text)
            : before.lines.map(\.text).filter { !furniture.contains($0) }
        #expect(after.lines.map(\.text) == expected)
    }
    // The chapter opening keeps both its lines, including the head naming the chapter.
    #expect(pages[0].lines.map(\.text) == ["Fifth National Climate Assessment: Chapter 23", "US Caribbean"])
    // Genuine headings inside the chapter survive with the foot gone.
    for title in ["Chapter 23. US Caribbean", "Table of Contents", "Introduction"] {
        #expect(pages.contains { $0.lines.contains { $0.text == title } })
    }
}

@Test func marginWordsReachTheVocabularyOnlyWhenTheReaderKeepsTheLine() throws {
    // #184's second half: the reference vocabulary is the text stream the reader gets, not the
    // one extraction read. A running head set at the body size is an ordinary-looking word to
    // the vocabulary, and a broken word's carry must not be able to end there.
    func vocabulary(removingFurniture: Bool, header: (Int) -> String) throws -> Set<String> {
        var options = ConversionOptions()
        options.removeRepeatedHeadersAndFooters = removingFurniture
        var evidence = DocumentEvidence(chapterCandidates: [], language: "en")
        for number in 1...6 {
            try evidence.collect(furniturePage(number, header: header(number)), pageIndex: number - 1,
                                 suppliesVocabulary: true, options: options)
        }
        return evidence.resolved(options: options).context.hyphens.vocabulary
    }
    let removed = try vocabulary(removingFurniture: true) { _ in "Marginalia" }
    #expect(!removed.contains("marginalia"))
    #expect(removed.contains("paragraph"))
    // The same words stay when the client keeps its headers, and when the line is not furniture.
    #expect(try vocabulary(removingFurniture: false) { _ in "Marginalia" }.contains("marginalia"))
    #expect(try vocabulary(removingFurniture: true) { "Marginalia \($0 * 17)" }.contains("marginalia"))
}
