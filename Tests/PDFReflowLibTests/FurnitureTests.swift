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
    // Chapter 12 alone supplied three occurrences of one head text (#10). The seven heads
    // also share one folio offset from the physical page, which #62 accepts as its own
    // evidence, so the neighboring two-page chapter 11 and 13 runs go with them.
    #expect(warnings.map(\.page) == Array(579...585))
    for (before, after) in zip(original, pages) {
        #expect(after.lines.map(\.text) == before.lines.filter { $0.rect.midY < 550 }.map(\.text))
    }
}

/// #62: an isolated note page's running head carries text no other page repeats
/// (`554 NOTES TO CHAPTERS 9-10` spans two chapters), so no three-page text run reaches it.
/// Its leading folio is 18 less than the physical page, as its neighbors' folios are.
@Test func isolatedNotePageHeadGoesWithItsNeighborsFolioOffset() throws {
    var pages = try ([126, 127] + Array(571...573)).map { try SourceLayoutFixture.load("911-\($0)").content() }
    let original = pages
    let heads = original[2...].map { $0.lines.max { $0.rect.midY < $1.rect.midY }!.text }
    // No two of the three share a head text, so the three-occurrence text rule removes none.
    #expect(heads == ["NOTES TO CHAPTER 9 553", "554 NOTES TO CHAPTERS 9-10", "NOTES TO CHAPTER 10 555"])
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == [571, 572, 573])
    for (before, after) in zip(original, pages) {
        // Chapter opening 126 carries the same offset in its foot (folio 108) and 127 carries
        // nothing; both keep every source line, head band and foot alike.
        let expected = before.number >= 571 ? before.lines.filter { $0.rect.midY < 550 } : before.lines
        #expect(after.lines.map(\.text) == expected.map(\.text))
        #expect(!after.lines.contains { $0.text.contains("NOTES TO CHAPTER") })
    }
    #expect(pages[0].lines.contains { $0.text == "108" })
}

/// #10: the Thomas concurrence runs four pages, so each alternating head occurs twice and the
/// three-occurrence rule left every one of them. All four pages' folios are 43 less than the
/// physical page, and page 48 opens the next opinion at a different offset without joining them.
@Test func fourPageConcurrenceHeadsGoWithTheirOpinionsFolioOffset() throws {
    var pages = try (44...48).map { try SourceLayoutFixture.load("loper-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == Array(44...48))
    let removed = zip(original, pages).map { before, after in
        before.lines.filter { line in !after.lines.contains { $0.text == line.text && $0.rect == line.rect } }
            .map(\.text)
    }
    #expect(removed == [
        ["1", "Cite as: 603 U. S. ____ (2024)", "THOMAS, J., concurring"],
        ["2 LOPER BRIGHT ENTERPRISES v. RAIMONDO", "THOMAS, J., concurring"],
        ["3", "Cite as: 603 U. S. ____ (2024)", "THOMAS, J., concurring"],
        ["4 LOPER BRIGHT ENTERPRISES v. RAIMONDO", "THOMAS, J., concurring"],
        // Page 48 restarts the numbering for the next concurrence. Its offset has one page of
        // evidence, so its folio stays and its opinion row, occurring once, stays with it.
        // Only the `Cite as:` head, which three of these pages repeat, is removed.
        ["Cite as: 603 U. S. ____ (2024)"],
    ])
    // The case name and the opinion's own body are untouched on the pages that open an opinion.
    for kept in ["1", "GORSUCH, J., concurring", "SUPREME COURT OF THE UNITED STATES"] {
        #expect(pages[4].lines.contains { $0.text == kept })
    }
    for (before, after) in zip(original, pages) {
        #expect(after.lines.filter { $0.rect.midY < 640 }.map(\.text)
            == before.lines.filter { $0.rect.midY < 640 }.map(\.text))
    }
}

@Test func mirroredBoundaryFoliosRequireMatchingOffsetsAndMeaningfulInternalDigits() {
    var pages = (1...3).map { n in
        furniturePage(n, header: n.isMultiple(of: 2) ? "\(n + 18) NOTES TO CHAPTER 12" : "NOTES TO CHAPTER 12 \(n + 18)")
    }
    #expect(LayoutReconstructor.stripFurniture(&pages).count == 3)
    let controls = [
        // A folio that does not keep one offset from the physical page is not a folio.
        ["NOTES TO CHAPTER 12 19", "21 NOTES TO CHAPTER 12", "NOTES TO CHAPTER 12 21"],
        // Internal sequential digits are not boundary folios.
        ["SECTION 1 SUMMARY", "SECTION 2 SUMMARY", "SECTION 3 SUMMARY"],
        // A numbered figure label counts up with its pages; its number names the figure.
        ["Figure 19 Air routes", "Figure 20 Air routes", "Figure 21 Air routes"],
        // Two agreeing pages are not a run, however exactly they agree.
        ["NOTES TO CHAPTER 12 19", "20 NOTES TO CHAPTER 12", "OTHER MATERIAL"],
    ]
    for headers in controls {
        var pages = headers.enumerated().map { furniturePage($0.offset + 1, header: $0.element) }
        #expect(LayoutReconstructor.stripFurniture(&pages).isEmpty)
        #expect(pages.map { $0.lines[0].text } == headers)
    }
    // #62: the chapter a notes head names changes from page to page while the head stays
    // furniture. One folio offset across three pages is the evidence the text cannot give.
    var chapters = ["NOTES TO CHAPTER 11 19", "20 NOTES TO CHAPTER 12", "NOTES TO CHAPTER 13 21"]
        .enumerated().map { furniturePage($0.offset + 1, header: $0.element) }
    #expect(LayoutReconstructor.stripFurniture(&chapters).map(\.page) == [1, 2, 3])
    #expect(chapters.allSatisfy { $0.lines.count == 1 })
    // Roman front matter keeps its own numbering; `xiv COMMISSION STAFF` is a running head.
    var roman = ["PREFACE xiv", "xv PREFACE", "PREFACE xvi"]
        .enumerated().map { furniturePage($0.offset + 14, header: $0.element) }
    #expect(LayoutReconstructor.stripFurniture(&roman).map(\.page) == [14, 15, 16])
}

/// The folio reading behind the offset evidence, in isolation: only a canonical numeral is a
/// page number, so an ordinary word at a head's edge supplies none.
@Test func folioReadingAcceptsOnlyCanonicalPageNumbers() {
    #expect(FurnitureDetector.folioValue("554").map(\.value) == 554)
    #expect(FurnitureDetector.folioValue("5-3").map(\.kind) == "chapter-5")
    #expect(FurnitureDetector.folioValue("5-3").map(\.value) == 3)
    #expect(FurnitureDetector.folioValue("xiv") .map(\.value) == 14)
    #expect(FurnitureDetector.folioValue("xiv")?.kind == "roman")
    // Arabic and Roman numbers of equal value stay apart, so one cannot extend the other's run.
    #expect(FurnitureDetector.folioValue("14")?.kind == "arabic")
    // Words that read as numerals only under a non-canonical spelling, and initials.
    for word in ["did", "mill", "civil", "dill", "lid", "c", "i", "x", "", "iiii", "vv", "note"] {
        #expect(FurnitureDetector.folioValue(word) == nil, "\(word) is not a folio")
    }
    // `mix` spells 1009 canonically; the front-matter bound keeps it out.
    #expect(FurnitureDetector.folioValue("mix") == nil)
    #expect(FurnitureDetector.folioValue("cd").map(\.value) == 400)
}

/// A lone page number is not a running head, however well its offset matches the document's:
/// a chapter opening carries nothing else in its margin. One sharing its row with head text
/// that is removed goes with that row, so a `folio + title` row does not lose half of itself.
@Test func loneFoliosStayWhileFoliosBesideRemovedHeadTextGo() {
    func page(_ number: Int, margin: [(String, Double)], folio: String?) -> PageContent {
        var lines = margin.map {
            TextLine(text: $0.0, rect: CGRect(x: $0.1, y: 752, width: 60, height: 10), fontSize: 10)
        }
        lines.append(TextLine(text: "Body paragraph \(number) stays available.",
                              rect: CGRect(x: 40, y: 700, width: 400, height: 12), fontSize: 12))
        if let folio {
            lines.append(TextLine(text: folio, rect: CGRect(x: 300, y: 20, width: 20, height: 10), fontSize: 10))
        }
        return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 600, height: 800),
                           lines: lines, graphics: [])
    }
    // Head text on every page establishes the offset; the chapter openings carry only a folio
    // in the foot, too far apart to repeat. Neither the head's evidence nor their own reaches
    // them, and the head rows are never beside them.
    var pages = (10...60).map { number in
        page(number, margin: [("\(number + 18) QUARTERLY REVIEW", 100)],
             folio: [20, 40, 60].contains(number) ? "\(number + 18)" : nil)
    }
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == Array(10...60))
    for number in [20, 40, 60] {
        #expect(pages[number - 10].lines.map(\.text)
            == ["Body paragraph \(number) stays available.", "\(number + 18)"])
    }
    // The same folio beside removed head text on one row leaves with the row.
    var beside = (10...14).map {
        page($0, margin: [("\($0 + 18)", 300), ("QUARTERLY REVIEW", 100)], folio: nil)
    }
    #expect(LayoutReconstructor.stripFurniture(&beside).map(\.page) == Array(10...14))
    #expect(beside.allSatisfy { $0.lines.map(\.text) == ["Body paragraph \($0.number) stays available."] })
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

/// A slip-opinion page: a title row with a folio at 85% of the page height, a section row
/// at 82%, then justified body lines 8 pt beneath it.
private func slipPage(_ number: Int, outer: [String]?, inner: String?, innerY: Double = 643.8,
                      bodyY: Double = 622.6) -> PageContent {
    var lines: [TextLine] = []
    for (i, text) in (outer ?? []).enumerated() {
        lines.append(TextLine(text: text, rect: CGRect(x: 160 + Double(i) * 90, y: 667.4,
            width: Double(text.count) * 5, height: 10.8), fontSize: 9))
    }
    if let inner {
        lines.append(TextLine(text: inner, rect: CGRect(x: 256, y: innerY, width: 100, height: 10.8), fontSize: 9))
    }
    for i in 0..<3 {
        lines.append(TextLine(text: "Body line \(i + 1) of page \(number) in the opinion's justified column.",
            rect: CGRect(x: 156, y: bodyY - Double(i) * 13.2, width: 299, height: 13.2), fontSize: 10.98))
    }
    return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func alternatingHead(_ number: Int) -> [String] {
    number.isMultiple(of: 2) ? ["\(number)", "LOPER BRIGHT ENTERPRISES v. RAIMONDO"] : ["Cite as: 603 U. S. ____ (2024)", "\(number)"]
}

@Test func sourceSlipOpinionTwoRowRunningHeadsDisappearFromAlternatingPages() throws {
    var pages = try (96...101).map { try SourceLayoutFixture.load("loper-\($0)").content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == Array(96...101))
    for (before, after) in zip(original, pages) {
        let band = before.bounds.minY + before.bounds.height * 0.8
        let heads = before.lines.filter { $0.rect.midY > band }.map(\.text)
        #expect(heads.count == 3 && heads.contains("KAGAN, J., dissenting"))
        #expect(after.lines.map(\.text) == before.lines.filter { $0.rect.midY <= band }.map(\.text))
    }
}

@Test func secondHeaderRowGoesOnlyWithARemovedRowAboveIt() {
    var pages = (1...6).map { slipPage($0, outer: alternatingHead($0), inner: "GORSUCH, J., concurring") }
    #expect(LayoutReconstructor.stripFurniture(&pages).map(\.page) == Array(1...6))
    #expect(pages.allSatisfy { page in page.lines.count == 3 && page.lines.allSatisfy { $0.text.hasPrefix("Body line") } })
    // Each control keeps its second row; the title row goes only where it alternates.
    let controls: [(String, Bool, [PageContent])] = [
        // Alone, the section row is 8 pt above the body: too close for a first-row header.
        ("lone second row", false, (1...6).map { slipPage($0, outer: nil, inner: "GORSUCH, J., concurring") }),
        // A repeated second row beneath unrepeated titles is retained with them.
        ("unique titles", false, (1...6).map { slipPage($0, outer: ["Unique title \($0 * 17)"], inner: "GORSUCH, J., concurring") }),
        // A row well below the title row is not part of the running head.
        ("distant row", true, (1...6).map { slipPage($0, outer: alternatingHead($0), inner: "GORSUCH, J., concurring", innerY: 610, bodyY: 580) }),
        // A repeated opening line that its paragraph follows directly is prose.
        ("adjacent prose", true, (1...6).map { slipPage($0, outer: alternatingHead($0), inner: "GORSUCH, J., concurring", bodyY: 632.6) }),
    ]
    for (name, titlesRemoved, original) in controls {
        var pages = original
        #expect(LayoutReconstructor.stripFurniture(&pages).count == (titlesRemoved ? 6 : 0), "\(name)")
        for (before, after) in zip(original, pages) {
            let expected = titlesRemoved ? before.lines.filter { $0.rect.midY < 660 } : before.lines
            #expect(after.lines.map(\.text) == expected.map(\.text), "\(name)")
            #expect(after.lines.contains { $0.text == "GORSUCH, J., concurring" }, "\(name)")
        }
    }
}

@Test func furnitureRequiresStablePositionStyleAndNearbyDistinctPages() {
    let controls: [[PageContent]] = [
        (1...6).map { furniturePage($0 * 10, header: "Scattered heading") },
        // Below the outer fifth of the page, repetition alone is not furniture.
        (1...6).map { furniturePage($0, header: "Repeated body", y: 600, bodyY: 570) },
        (1...6).map { furniturePage($0, header: "Adjacent prose", bodyY: 738) },
        // Inside the band, a repeated first line that its paragraph follows directly stays.
        (1...6).map { furniturePage($0, header: "Repeated opening line", y: 650, bodyY: 640) },
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
    let source = Bundle.module.resourceURL!.appendingPathComponent("fixtures/prose.pdf")
    let output = directory.appendingPathComponent("headers.epub")
    var options = ConversionOptions()
    options.removeRepeatedHeadersAndFooters = false
    let report = try await PDFConverter().convert(from: source, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    let chapter = try #require(archive["EPUB/chapter-1.xhtml"])
    var data = Data()
    _ = try archive.extract(chapter) { data += $0 }
    let html = String(decoding: data, as: UTF8.self)
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
