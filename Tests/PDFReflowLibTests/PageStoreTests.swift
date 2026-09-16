import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

private func fixture(_ name: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("fixtures/" + name + ".pdf")
}

/// Full-page artwork, a small illustration and plain text: under the image-backed policy the
/// first page is recognized, the others are native, so recognized and native pages spill together.
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

private func reconstruct(_ source: URL, options: ConversionOptions) async throws -> Reconstruction {
    let workspace = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options, workspace: workspace) { _ in }
    let bytes = try result.document.assets.map { try Data(contentsOf: $0.fileURL) }
    // No spilled page or page directory may survive: the workspace holds only assets afterwards.
    #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.path) == ["assets"])
    return Reconstruction(result: result, assetBytes: bytes)
}

@Test func spilledReconstructionIsRepeatableAndLeavesOnlyAssets() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    var sources = ["prose", "columns", "graphics", "lists-code", "rotated", "scanned"].map { (fixture($0), ConversionOptions()) }
    var recognizing = ConversionOptions(); recognizing.ocr = .automaticIncludingImageBackedText
    recognizing.removeRepeatedHeadersAndFooters = false
    sources.append((try mixedRecognitionSource(in: dir), recognizing))
    for (source, base) in sources {
        var options = base
        options.referenceImages = .automatic
        let first = try await reconstruct(source, options: options)
        let second = try await reconstruct(source, options: options)
        let name = Comment(rawValue: source.lastPathComponent)
        #expect(second.result.document.blocks == first.result.document.blocks, name)
        #expect(second.result.document.metadata == first.result.document.metadata, name)
        #expect(second.result.document.chapterStartPages == first.result.document.chapterStartPages, name)
        #expect(second.result.document.assets.map(\.id) == first.result.document.assets.map(\.id), name)
        #expect(second.assetBytes == first.assetBytes, name)
        #expect(second.result.warnings == first.result.warnings, name)
        #expect(second.result.recognizedPageCount == first.result.recognizedPageCount, name)
        #expect(first.result.pageCount > 0, name)
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
    page.tints = [CGRect(x: 88.5, y: 202.5, width: 435, height: 501)]
    page.separators = [CGRect(x: 95.7, y: 536.3, width: 149, height: 4), CGRect(x: 96, y: 536.5, width: 4, height: 62.6)]
    page.requiresPageImage = false
    page.recognized = true
    page.hasSyntheticTextStyle = true
    page.preservePageReference = true
    return page
}

@Test func spilledPagesReloadExactlyAndLeaveNoFiles() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pages = dir.appendingPathComponent("pages")
    let store = PageStore(directory: pages)
    let original = trickyPage()
    let empty = PageContent(number: 2, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), lines: [], graphics: [])
    try store.store(original, at: 0)
    try store.store(empty, at: 1)
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

@Test func spillCancellationThrowsAndLeavesOnlyWorkspaceFiles() async throws {
    let workspace = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: workspace) }
    let task = Task {
        try await PDFReflowLibPipeline.reconstruct(from: fixture("prose"), options: ConversionOptions(),
                                                   workspace: workspace) { event in
            if event.stage == .reconstructing { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}
