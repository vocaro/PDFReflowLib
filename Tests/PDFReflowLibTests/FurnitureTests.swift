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
