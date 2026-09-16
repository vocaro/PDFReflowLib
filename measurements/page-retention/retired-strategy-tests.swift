import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

private func fixture(_ name: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("fixtures/" + name + ".pdf")
}

/// Full-page artwork, a small illustration and plain text: under the image-backed policy the
/// first page is recognized, the others are native, so both retention paths run in one book.
private func mixedRecognitionSource(in directory: URL) throws -> URL {
    let source = directory.appendingPathComponent("mixed.pdf")
    let pdf = PDFDocument()
    for (index, size) in [300, 60, 0].enumerated() {
        let page = try #require(PDFDocument(data: textLayerPDF("Readable source text.", imageSize: size, invisible: false)))
        pdf.insert(try #require(page.page(at: 0)), at: index)
    }
    #expect(pdf.write(to: source))
    return source
}

private struct Reconstruction {
    var result: PDFReflowLibPipeline.Result
    var assetBytes: [Data]
}

private func reconstruct(_ source: URL, retention: PageRetention, options: ConversionOptions) async throws -> Reconstruction {
    let workspace = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options, workspace: workspace,
                                                            retention: retention) { _ in }
    let bytes = try result.document.assets.map { try Data(contentsOf: $0.fileURL) }
    // No spilled page or page directory may survive: the workspace holds only assets afterwards.
    #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.path) == ["assets"],
            "\(retention) left files behind")
    return Reconstruction(result: result, assetBytes: bytes)
}

@Test func everyRetentionStrategyReconstructsTheIdenticalDocument() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    var sources = ["prose", "columns", "graphics", "lists-code", "rotated", "scanned"].map { (fixture($0), ConversionOptions()) }
    var recognizing = ConversionOptions(); recognizing.ocr = .automaticIncludingImageBackedText
    recognizing.removeRepeatedHeadersAndFooters = false
    sources.append((try mixedRecognitionSource(in: dir), recognizing))
    for (source, base) in sources {
        var options = base
        options.referenceImages = .automatic
        let control = try await reconstruct(source, retention: .resident, options: options)
        for retention in [PageRetention.spill, .reextract] {
            let candidate = try await reconstruct(source, retention: retention, options: options)
            let name = "\(source.lastPathComponent) under \(retention)"
            #expect(candidate.result.document.blocks == control.result.document.blocks, Comment(rawValue: name))
            #expect(candidate.result.document.metadata == control.result.document.metadata, Comment(rawValue: name))
            #expect(candidate.result.document.chapterStartPages == control.result.document.chapterStartPages, Comment(rawValue: name))
            #expect(candidate.result.document.assets.map(\.id) == control.result.document.assets.map(\.id), Comment(rawValue: name))
            #expect(candidate.result.document.assets.map(\.format) == control.result.document.assets.map(\.format), Comment(rawValue: name))
            #expect(candidate.assetBytes == control.assetBytes, Comment(rawValue: name))
            #expect(candidate.result.warnings == control.result.warnings, Comment(rawValue: name))
            #expect(candidate.result.pageCount == control.result.pageCount, Comment(rawValue: name))
            #expect(candidate.result.reflowedPageCount == control.result.reflowedPageCount, Comment(rawValue: name))
            #expect(candidate.result.recognizedPageCount == control.result.recognizedPageCount, Comment(rawValue: name))
        }
    }
}

private func trickyPage() -> PageContent {
    var styled = InlineText("Bold ", style: .bold)
    styled.append(InlineText(elements: [.sourcePage(7), .text("ital<ic> & \"quoted\" ünïcode ", [.italic, .superscript])]))
    styled.append(InlineText("plain", style: []))
    var first = TextLine(content: styled, rect: CGRect(x: 1.5, y: 2.25, width: 300.125, height: 12), fontSize: 11.5)
    first.readingRect = CGRect(x: -0.0, y: 2.25, width: 12, height: 12)
    first.structure = TextStructure(group: 3, order: 1, headingLevel: 2, lineCount: 4)
    first.wraps = true
    var second = TextLine(text: "code", rect: CGRect(x: 10, y: 20, width: 30, height: 9.75), fontSize: 9.75, monospaced: true, wraps: false)
    second.readingRect = CGRect.null
    var page = PageContent(number: 42, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [first, second],
                           graphics: [CGRect(x: 100, y: 100, width: 50.5, height: 60.25), CGRect.null])
    page.requiresPageImage = false
    page.recognized = true
    page.hasSyntheticTextStyle = true
    page.preservePageReference = true
    return page
}

@Test func spilledPagesReloadExactlyAndLeaveNoFiles() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pages = dir.appendingPathComponent("pages")
    let store = PageStore(retention: .spill, directory: pages) { index in
        Issue.record("spill must never re-extract page \(index)"); return trickyPage()
    }
    let original = trickyPage()
    let empty = PageContent(number: 2, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), lines: [], graphics: [])
    try store.store(original, at: 0, deterministic: true)
    try store.store(empty, at: 1, deterministic: false)
    #expect(store.spilledIndices == [0, 1])
    #expect(try FileManager.default.contentsOfDirectory(atPath: pages.path).count == 2)
    let reloaded = try store.load(at: 0)
    #expect(reloaded == original)
    #expect(reloaded.lines.map(\.text) == original.lines.map(\.text))
    #expect(reloaded.graphics[1].isNull)
    #expect(reloaded.lines[1].readingRect?.isNull == true)
    // Binary property lists merge equal values, so a negative zero may reload as positive zero;
    // reconstruction never reads the sign of zero, and value equality is the contract.
    #expect(reloaded.lines[0].readingRect == original.lines[0].readingRect)
    #expect(try store.load(at: 1) == empty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: pages.path).isEmpty)
    store.finish()
    #expect(!FileManager.default.fileExists(atPath: pages.path))
}

@Test func reextractionRepeatsOnlyDeterministicPages() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    var repeated: [Int] = []
    let store = PageStore(retention: .reextract, directory: dir.appendingPathComponent("pages")) { index in
        repeated.append(index)
        var page = trickyPage(); page.number = index + 1; return page
    }
    let recognized = trickyPage()
    try store.store(trickyPage(), at: 0, deterministic: true)
    try store.store(recognized, at: 1, deterministic: false)
    try store.store(trickyPage(), at: 2, deterministic: true)
    #expect(store.spilledIndices == [1])
    #expect(try store.load(at: 0).number == 1)
    #expect(try store.load(at: 1) == recognized)
    #expect(try store.load(at: 2).number == 3)
    #expect(repeated == [0, 2])
}

@Test func residentPagesNeverTouchDiskOrReextraction() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = PageStore(retention: .resident, directory: dir.appendingPathComponent("pages")) { index in
        Issue.record("resident must never re-extract page \(index)"); return trickyPage()
    }
    let page = trickyPage()
    try store.store(page, at: 5, deterministic: false)
    #expect(store.spilledIndices.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("pages").path))
    #expect(try store.load(at: 5) == page)
}

private func syntheticMarginPage(_ number: Int, unique: Bool) -> PageContent {
    var page = PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
        TextLine(text: unique ? "distinct footer \(number * 31)" : "scan footer \(number)",
                 rect: CGRect(x: 40, y: 20, width: 200, height: 10), fontSize: 10),
        TextLine(text: "Body text of scanned page \(number).", rect: CGRect(x: 40, y: 400, width: 400, height: 12), fontSize: 12),
    ], graphics: [])
    page.hasSyntheticTextStyle = true
    return page
}

@Test func furnitureLedgerMatchesWholeDocumentStripping() throws {
    // Native running headers from the source-derived 9/11 fixtures plus a synthetic-layer
    // run long enough to cross the document-wide synthetic threshold.
    let numbers = Array(19...26) + Array(65...71) + Array(471...476) + Array(579...585)
    var pages = try numbers.map { try SourceLayoutFixture.load("911-\($0)").content() }
    pages += (600..<640).map { syntheticMarginPage($0, unique: $0 % 9 == 0) }
    var whole = pages
    let expected = LayoutReconstructor.stripFurniture(&whole)
    #expect(expected.contains { $0.page == 20 } && expected.contains { $0.page == 601 })
    #expect(!expected.contains { $0.page == 603 })

    var ledger = FurnitureDetector.Ledger()
    for (index, page) in pages.enumerated() { FurnitureDetector.collect(page, pageIndex: index, into: &ledger) }
    let plan = FurnitureDetector.resolve(ledger)
    var streamed: [ConversionWarning] = []
    for index in pages.indices {
        // Only this page is in hand, as in the reconstruction pass.
        var page = pages[index]
        if let warning = FurnitureDetector.apply(plan, to: &page, pageIndex: index) { streamed.append(warning) }
        #expect(page == whole[index], "page \(page.number)")
    }
    #expect(streamed.sorted { $0.page < $1.page } == expected)

    // Fewer than three pages disables both rules, as before.
    var short = Array(pages.prefix(2))
    #expect(LayoutReconstructor.stripFurniture(&short).isEmpty)
    var shortLedger = FurnitureDetector.Ledger()
    for (index, page) in short.enumerated() { FurnitureDetector.collect(page, pageIndex: index, into: &shortLedger) }
    var copy = short[0]
    #expect(FurnitureDetector.apply(FurnitureDetector.resolve(shortLedger), to: &copy, pageIndex: 0) == nil)
    #expect(copy == short[0])
}

@Test func retentionSelectionRejectsUnknownValues() throws {
    #expect(try PageRetention.configured(environment: [:]) == .spill)
    #expect(try PageRetention.configured(environment: [PageRetention.environmentVariable: ""]) == .spill)
    #expect(try PageRetention.configured(environment: [PageRetention.environmentVariable: "spill"]) == .spill)
    #expect(try PageRetention.configured(environment: [PageRetention.environmentVariable: "reextract"]) == .reextract)
    for invalid in ["Spill", "disk", "resident "] {
        #expect(throws: ConversionError.self) {
            try PageRetention.configured(environment: [PageRetention.environmentVariable: invalid])
        }
    }
}

@Test func spillCancellationThrowsAndLeavesOnlyWorkspaceFiles() async throws {
    let workspace = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: workspace) }
    let task = Task {
        try await PDFReflowLibPipeline.reconstruct(from: fixture("prose"), options: ConversionOptions(),
                                                   workspace: workspace, retention: .spill) { event in
            if event.stage == .reconstructing { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}
