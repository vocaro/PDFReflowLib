import Foundation
import PDFKit
import Synchronization
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// The pipeline's recognition path end to end: canned recognizers, selective OCR policies,
// image-backed and invisible text layers, attachment placeholders and cancellation.

/// The pipeline takes its recognizer as a parameter, so its recognition branches run on the
/// bundled fixtures with canned readings instead of Vision.
private func fixture(_ name: String) -> URL {
    fixtureURL("\(name).pdf")
}

private func workspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-recognition-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct RecognizerFailure: Error {}

private func reading(_ text: String) -> OCRReader.Result {
    OCRReader.Result(lines: [TextLine(text: text, rect: CGRect(x: 40, y: 40, width: 300, height: 12), fontSize: 12)], tables: [])
}

@Test func cannedRecognitionReplacesPagesWithoutText() async throws {
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let calls = Mutex(0)
    let result = try await PDFReflowLibPipeline.reconstruct(from: fixture("scanned"), options: .init(), workspace: directory,
        recognize: { _, _ in
            calls.withLock { $0 += 1 }
            return reading("Canned recognition of the scanned page")
        }) { _ in }
    #expect(calls.withLock { $0 } == result.pageCount)
    #expect(result.recognizedPageCount == result.pageCount)
    #expect(result.book.blocks.contains { $0.text.contains("Canned recognition of the scanned page") })
    #expect(result.warnings.contains { $0.code == .ocrUsed })
    #expect(!result.warnings.contains { $0.code == .ocrFailed || $0.code == .pageImageFallback })
}

@Test func failedRecognitionPreservesThePageAsAnImage() async throws {
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = try await PDFReflowLibPipeline.reconstruct(from: fixture("scanned"), options: .init(), workspace: directory,
        recognize: { _, _ in throw RecognizerFailure() }) { _ in }
    #expect(result.recognizedPageCount == 0)
    #expect(result.reflowedPageCount == 0)
    #expect(result.warnings.contains { $0.code == .ocrFailed && $0.message.contains("preserved as an image") })
    #expect(result.warnings.contains { $0.code == .pageImageFallback })
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
}

@Test func cancellationInsideRecognitionPropagates() async throws {
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: CancellationError.self) {
        try await PDFReflowLibPipeline.reconstruct(from: fixture("scanned"), options: .init(), workspace: directory,
            recognize: { _, _ in throw CancellationError() }) { _ in }
    }
}

@Test func theRecognizerRunsOnlyWhenThePolicyAsks() async throws {
    for (policy, name, expectedCalls) in [(ConversionOptions.OCRPolicy.never, "scanned", 0), (.automatic, "prose", 0)] {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = ConversionOptions()
        options.ocr = policy
        let calls = Mutex(0)
        let result = try await PDFReflowLibPipeline.reconstruct(from: fixture(name), options: options, workspace: directory,
            recognize: { _, _ in
                calls.withLock { $0 += 1 }
                return reading("Never used")
            }) { _ in }
        #expect(calls.withLock { $0 } == expectedCalls, "\(policy) on \(name)")
        #expect(result.recognizedPageCount == 0)
    }
    // `.always` recognizes every page, including ones with native text.
    let directory = try workspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    var always = ConversionOptions()
    always.ocr = .always
    let calls = Mutex(0)
    let result = try await PDFReflowLibPipeline.reconstruct(from: fixture("prose"), options: always, workspace: directory,
        recognize: { _, _ in
            calls.withLock { $0 += 1 }
            return reading("Recognized instead of extracted")
        }) { _ in }
    #expect(calls.withLock { $0 } == result.pageCount)
    #expect(result.recognizedPageCount == result.pageCount)
    #expect(result.book.blocks.filter(\.hasReflowedText).allSatisfy { $0.text.contains("Recognized instead of extracted") })
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
        let log = ProgressLog()
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
        let html = try archive.chapter()
        #expect(html.components(separatedBy: "Readable source text.").count - 1 == 3)
        if policy == .automaticIncludingImageBackedText {
            #expect(html.components(separatedBy: "<strong>Readable source text.</strong>").count - 1 == 2)
            #expect(report.warnings.contains { $0.code == .ocrUsed && $0.page == 1 })
            #expect(html.contains("Source page 1") || html.contains("Original page 1"))
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
    // Recognition of the blank page succeeds and reads nothing, which is not a transcription:
    // the page is preserved as an image and is not counted as recognized (#222).
    #expect(result.recognizedPageCount == 0)
    #expect(result.reflowedPageCount == 0)
    #expect(result.book.blocks.allSatisfy { $0.text.isEmpty })
    #expect(result.book.assets.count == 1)
    #expect(result.warnings.contains { $0.code == .pageImageFallback })
    #expect(result.warnings.contains { $0.code == .ocrFailed && $0.message.contains("found no text") })
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
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
    #expect(result.book.assets.count == 1)
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

func textLayerPDF(_ text: String, imageSize: Int = 300, invisible: Bool = true) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /XObject << /Im 5 0 R >> /Font << /F1 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("q \(imageSize) 0 0 \(imageSize) 0 0 cm /Im Do Q BT /F1 12 Tf \(invisible ? 3 : 0) Tr 20 240 Td (\(text)) Tj ET"),
        testPDFStream("FFFFFF>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding /ToUnicode 7 0 R >>",
        testPDFStream("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        /CMapName /AttachmentTest def /CMapType 2 def
        1 begincodespacerange <00> <FF> endcodespacerange
        1 beginbfchar <7E> <FFFC> endbfchar
        endcmap CMapName currentdict /CMap defineresource pop end end
        """),
    ])
}

@Test func attachmentPlaceholdersAreNotSemanticTextAndStylesSurvive() throws {
    for (raw, expected) in [("~~", ""), ("Before~after", "Before after"), ("~Before after~", "Before after")] {
        let document = try #require(PDFDocument(data: textLayerPDF(raw)))
        let page = try #require(document.page(at: 0))
        #expect(pdfKitGated { page.string }?.contains("\u{FFFC}") == true) // Prove the extraction defect is exercised.
        for styled in [true, false] {
            let lines = try NativeTextReader.lines(on: page, limit: 1000, includeStyle: styled)
            #expect(lines.map(\.text).joined() == expected)
            if !expected.isEmpty && styled {
                #expect(lines.flatMap { $0.content.elements }.contains {
                    if case let .text(value, style) = $0 { return value.contains("Before") && style.contains(.bold) }
                    return false
                })
            }
        }
    }
}

@Test func textlessAttachmentScansUseOCRPolicyWithoutClaimingReflow() async throws {
    for policy in [ConversionOptions.OCRPolicy.automatic, .automaticIncludingImageBackedText, .never] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("source.pdf")
        try textLayerPDF("~~").write(to: pdf)
        var options = ConversionOptions(); options.ocr = policy
        let result = try await PDFReflowLibPipeline.reconstruct(from: pdf, options: options,
            workspace: dir.appendingPathComponent("work"), progress: { _ in })
        #expect(result.reflowedPageCount == 0)
        #expect(result.book.blocks.allSatisfy { $0.text.isEmpty })
        #expect(result.book.assets.count == 1)
        #expect(result.warnings.contains { $0.code == .pageImageFallback && $0.page == 1 })
        #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
        // Recognition reads nothing from the scan whichever policy asked for it, so no page is
        // counted as recognized and none claims a transcription (#222); only the attempt differs.
        #expect(result.recognizedPageCount == 0)
        #expect(!result.warnings.contains { $0.code == .ocrUsed })
        #expect(result.warnings.contains { $0.code == .ocrFailed && $0.message.contains("found no text") } == (policy != .never))
    }
}

@Test func inheritedTextGetsReviewWarningAndSourceImageWithoutDiscardingProse() async throws {
    for imageSize in [60, 300] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
        try textLayerPDF("Existing~transcription.", imageSize: imageSize).write(to: pdf)
        let report = try await PDFConverter().convert(from: pdf, to: epub)
        #expect(report.reflowedPageCount == 1)
        #expect(report.recognizedPageCount == 0)
        #expect(report.imageCount == 1)
        let warnings = report.warnings.filter { $0.code == .unverifiedTextLayer }
        #expect(warnings.count == (imageSize == 300 ? 1 : 0))
        if let warning = warnings.first {
            #expect(warning.page == 1)
            #expect(warning.message.contains("Check the accompanying source-page image"))
            let decoded = try JSONDecoder().decode(ConversionWarning.self, from: JSONEncoder().encode(warning))
            #expect(decoded == warning)
        }
        let archive = try Archive(url: epub, accessMode: .read)
        let html = try archive.chapter()
        #expect(html.contains("Existing transcription."))
        #expect(!html.contains("\u{FFFC}"))
        #expect(html.contains("<img "))
    }
}

private func imageBackedTextPDF(invisible: Bool) -> Data {
    let mode = invisible ? 3 : 0
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> /XObject << /Im 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("""
        q 400 0 0 500 0 0 cm /Im Do Q
        BT /F1 12 Tf \(mode) Tr 40 420 Td (Ordinary prose should reflow across) Tj 0 -14 Td (the source line break without becoming code.) Tj ET
        BT /F1 18 Tf \(mode) Tr 40 380 Td (Noisy size is not a heading.) Tj ET
        """),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
        "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length 7 >>\nstream\nFFFFFF>\nendstream",
    ])
}

@Test func invisibleCourierLayerDoesNotInventCodeOrHeadings() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let input = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book.epub")
    try imageBackedTextPDF(invisible: true).write(to: input)
    var options = ConversionOptions(); options.ocr = .never
    let report = try await PDFConverter().convert(from: input, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    let html = try archive.chapter()
    #expect(!html.contains("<pre>"))
    #expect(!html.contains("<h2"))
    #expect(html.contains("Ordinary prose should reflow across the source line break"))
    #expect(report.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(report.imageCount >= 1 && report.recognizedPageCount == 0)
}

@Test func visibleCourierAndRealHeadingsKeepTheirSemantics() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let input = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book.epub")
    try imageBackedTextPDF(invisible: false).write(to: input)
    var options = ConversionOptions(); options.ocr = .never
    _ = try await PDFConverter().convert(from: input, to: output, options: options)
    let archive = try Archive(url: output, accessMode: .read)
    let html = try archive.chapter()
    #expect(html.contains("<pre>"))
    #expect(html.contains("<h2"))
}

@Test(arguments: ["warren-50", "warren-910"])

func warrenSyntheticFontsCannotDeclareCodeOrHeadings(name: String) throws {
    var page = try SourceLayoutFixture.load(name).content()
    // Source stream inspection confirms exclusively mode-3 text over full-page scan images.
    page.hasSyntheticTextStyle = true
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: ["communist", "evidence"], warnings: &warnings)
    #expect(!blocks.contains { if case .heading = $0.content { return true }; return false })
    let preformatted = blocks.compactMap { block -> String? in
        if case let .preformatted(text) = block.content { return text.text }; return nil
    }
    // Source points 10/11 retain the existing list representation, not arbitrary prose lines.
    if name == "warren-50" {
        #expect(preformatted.count == 2)
        #expect(preformatted.allSatisfy { $0.hasPrefix("10.") || $0.hasPrefix("11.") })
    } else { #expect(preformatted.isEmpty) }
    let text = blocks.map(\.text).joined(separator: " ")
    if name == "warren-50" {
        #expect(text.contains("Communist Party"))
        #expect(text.contains("bis known contacts witb")) // Do not invent spelling corrections.
    } else { #expect(text.contains("De Mohrenschildt, Jeanne")) }
}

@Test func invisibleTextClassificationRespectsSavedStateAndForms() throws {
    func inspect(_ body: String, form: String? = nil) throws -> GraphicsReader.Result {
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >> /Contents 4 0 R >>",
            testPDFStream(body), "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
        ]
        if let form {
            objects.append("<< /Type /XObject /Subtype /Form /BBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> >> /Length \(form.utf8.count) >>\nstream\n\(form)\nendstream")
        }
        let document = try #require(PDFDocument(data: testPDF(objects: objects)))
        let page = try #require(document.page(at: 0)?.pageRef)
        return GraphicsReader.read(page)
    }
    let hidden = "BT /F1 12 Tf 3 Tr 40 400 Td (Hidden) Tj ET"
    let visible = "BT /F1 12 Tf 0 Tr 40 380 Td (Visible) Tj ET"
    #expect(try inspect(hidden).hasOnlyInvisibleText)
    #expect(try !inspect(hidden + visible).hasOnlyInvisibleText)
    #expect(try !inspect("q " + hidden + " Q BT /F1 12 Tf (Visible) Tj ET").hasOnlyInvisibleText)
    #expect(try inspect(hidden + " q 0 Tr Q BT (Hidden too) Tj ET").hasOnlyInvisibleText)
    #expect(try inspect("/Fm Do", form: hidden).hasOnlyInvisibleText)
    #expect(try !inspect("/Fm Do " + visible, form: hidden).hasOnlyInvisibleText)
    #expect(try !inspect(hidden + " /Fm Do", form: visible).hasOnlyInvisibleText)
    #expect(try !inspect("BT 9 Tr (Invalid) Tj ET").hasOnlyInvisibleText)
    #expect(try !inspect("BT 7 Tr (Clipping text) Tj ET").hasOnlyInvisibleText)
}
