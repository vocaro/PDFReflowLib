import Foundation
import Synchronization
import Testing
@testable import PDFReflowLib

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
    #expect(result.document.blocks.contains { $0.text.contains("Canned recognition of the scanned page") })
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
    #expect(result.document.blocks.filter(\.hasReflowedText).allSatisfy { $0.text.contains("Recognized instead of extracted") })
}
