import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private actor SelectiveOCRProgress {
    var events: [ConversionProgress] = []
    func append(_ event: ConversionProgress) { events.append(event) }
}

@Test func selectiveOCRRetriesOnlyPageSizedImageTextAndKeepsNativeStyles() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("mixed.pdf")
    let pdf = PDFDocument()
    // Full-page artwork, small illustration, and plain text, all visibly readable.
    for (index, size) in [300, 60, 0].enumerated() {
        let pagePDF = try #require(PDFDocument(data: textLayerPDF("Readable source text.", imageSize: size, invisible: false)))
        pdf.insert(try #require(pagePDF.page(at: 0)), at: index)
    }
    #expect(pdf.write(to: source))
    for (name, policy, count) in [
        ("automatic", ConversionOptions.OCRPolicy.automatic, 0),
        ("never", .never, 0),
        ("selective", .automaticIncludingImageBackedText, 1),
        ("always", .always, 3),
    ] {
        var options = ConversionOptions(); options.ocr = policy
        options.removeRepeatedHeadersAndFooters = false
        let log = SelectiveOCRProgress()
        let output = dir.appendingPathComponent(name + ".epub")
        let report = try await PDFConverter().convert(from: source, to: output, options: options) {
            await log.append($0)
        }
        #expect(report.recognizedPageCount == count)
        #expect(report.reflowedPageCount == 3)
        let events = await log.events
        let recognizedPages = events.filter { $0.stage == .recognizing }.compactMap(\.page)
        #expect(recognizedPages == (count == 3 ? [1, 2, 3] : count == 1 ? [1] : []))
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.fractionCompleted <= $1.fractionCompleted })
        #expect(events.last?.stage == .completed && events.last?.fractionCompleted == 1)
        #expect(report.warnings.filter { $0.code == .unverifiedTextLayer }.count == (count == 0 ? 1 : 0))
        let archive = try Archive(url: output, accessMode: .read)
        var bytes = Data()
        _ = try archive.extract(try #require(archive["EPUB/chapter-1.xhtml"])) { bytes += $0 }
        let html = String(decoding: bytes, as: UTF8.self)
        #expect(html.components(separatedBy: "Readable source text.").count - 1 == 3)
        if policy == .automaticIncludingImageBackedText {
            #expect(html.components(separatedBy: "<strong>Readable source text.</strong>").count - 1 == 2)
            #expect(report.warnings.contains { $0.code == .ocrUsed && $0.page == 1 })
            #expect(html.contains("title=\"Source page 1\""))
        }
    }
}

@Test func selectiveOCRDiscardsUnseenInheritedTextAndPreservesBlankSource() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("blank.pdf")
    try textLayerPDF("Invented inherited text.").write(to: source)
    var options = ConversionOptions(); options.ocr = .automaticIncludingImageBackedText
    options.referenceImages = .never
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.recognizedPageCount == 1)
    #expect(result.reflowedPageCount == 0)
    #expect(result.document.blocks.allSatisfy { $0.text.isEmpty })
    #expect(result.document.assets.count == 1)
    #expect(result.warnings.contains { $0.code == .pageImageFallback })
    #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
}

@Test func selectiveOCRRetainsRequiredRotatedFallback() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = try #require(PDFDocument(data: textLayerPDF("Existing text.")))
    try #require(pdf.page(at: 0)).rotation = 90
    let source = dir.appendingPathComponent("rotated.pdf")
    #expect(pdf.write(to: source))
    var options = ConversionOptions(); options.ocr = .automaticIncludingImageBackedText
    options.referenceImages = .never
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.recognizedPageCount == 0 && result.reflowedPageCount == 0)
    #expect(result.document.assets.count == 1)
    #expect(result.warnings.contains { $0.code == .pageImageFallback })
}

@Test func selectiveOCRCancellationCleansStagingBeforePublication() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book.epub")
    try textLayerPDF("Readable source text.", invisible: false).write(to: source)
    var options = ConversionOptions(); options.ocr = .automaticIncludingImageBackedText
    let task = Task {
        try await PDFConverter().convert(from: source, to: output, options: options) { event in
            if event.stage == .recognizing { withUnsafeCurrentTask { $0?.cancel() } }
            #expect(event.stage != .completed)
        }
    }
    do {
        _ = try await task.value
        Issue.record("Expected cancellation on selective OCR entry")
    } catch is CancellationError { }
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["source.pdf"])
}
