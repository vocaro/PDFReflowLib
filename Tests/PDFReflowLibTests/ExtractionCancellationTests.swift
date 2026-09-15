import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

private func waitForSignal(_ signal: DispatchSemaphore, seconds: Double) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: signal.wait(timeout: .now() + seconds))
        }
    }
}

/// Hold the real extraction gate on a dedicated thread, with a fail-safe deadline.
/// The test's async task never holds a thread-owned lock across suspension.
private final class ExtractionHold: Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)

    init() {
        DispatchQueue.global().async { [self] in
            defer { finished.signal() }
            do {
                try NativeTextReader.withExtractionLock {
                    entered.signal()
                    #expect(release.wait(timeout: .now() + 10) == .success)
                }
            } catch { Issue.record("Unexpected holder error: \(error)") }
        }
    }

    func waitUntilEntered() async throws {
        let status = await waitForSignal(entered, seconds: 5)
        try #require(status == .success)
    }

    func stop() async {
        release.signal()
        let status = await waitForSignal(finished, seconds: 5)
        #expect(status == .success)
    }
}

@Suite(.serialized)
struct ExtractionCancellationTests {
    @Test func cancelledConversionCleansStagingWhileGateRemainsHeld() async throws {
        let directory = try testPDFDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("cancelled.epub")
        let source = Bundle.module.resourceURL!.appendingPathComponent("fixtures/prose.pdf")
        let hold = ExtractionHold()
        defer { hold.release.signal() }
        try await hold.waitUntilEntered()
        let opened = AsyncStream<Void>.makeStream()
        let cancelled = DispatchSemaphore(value: 0)
        let task = Task {
            defer { opened.continuation.finish() }
            do {
                _ = try await PDFConverter().convert(from: source, to: output) { event in
                    #expect(event.stage == .opening)
                    opened.continuation.yield()
                }
                Issue.record("Cancelled conversion unexpectedly succeeded")
            } catch is CancellationError { cancelled.signal() }
        }
        for await _ in opened.stream { break }
        // Wait for the conversion to create its workspace before testing queued cancellation.
        for _ in 0..<200 {
            if try !FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        task.cancel()
        let status = await waitForSignal(cancelled, seconds: 1)
        #expect(status == .success, "Conversion cancellation must not wait for another page")
        if status == .success {
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
        await hold.stop()
        try await task.value
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func cancelledNativeReaderReturnsWhileAnotherExtractionStillHoldsGate() async throws {
        let hold = ExtractionHold()
        defer { hold.release.signal() }
        try await hold.waitUntilEntered()
        let started = AsyncStream<Void>.makeStream()
        let cancelled = DispatchSemaphore(value: 0)
        let task = Task.detached {
            defer { started.continuation.finish() }
            let url = Bundle.module.resourceURL!.appendingPathComponent("fixtures/lists-code.pdf")
            let document = try #require(PDFDocument(url: url))
            let page = try #require(document.page(at: 0))
            started.continuation.yield()
            do {
                _ = try NativeTextReader.lines(on: page, limit: 100_000)
                Issue.record("Cancelled extraction unexpectedly succeeded")
            } catch is CancellationError { cancelled.signal() }
        }
        for await _ in started.stream { break }
        // Give the synchronous reader time to enter the contended wait before cancelling.
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let status = await waitForSignal(cancelled, seconds: 1)
        #expect(status == .success, "Cancellation must finish before the holder releases the gate")
        let survivorFinished = DispatchSemaphore(value: 0)
        let survivor = Task.detached {
            try NativeTextReader.withExtractionLock { survivorFinished.signal() }
        }
        #expect(await waitForSignal(survivorFinished, seconds: 0.1) == .timedOut,
                "A cancelled waiter must not release another extraction's lock")
        await hold.stop()
        try await task.value
        _ = try await survivor.value
        #expect(await waitForSignal(survivorFinished, seconds: 1) == .success)

        // A cancelled waiter must neither unlock the holder nor poison later extraction.
        let document = try #require(PDFDocument(url: Bundle.module.resourceURL!
            .appendingPathComponent("fixtures/lists-code.pdf")))
        let lines = try NativeTextReader.lines(on: #require(document.page(at: 0)), limit: 100_000)
        #expect(lines.contains { $0.text.contains("Keep the first item.") })
        #expect(lines.contains { $0.content.elements.contains { element in
            if case let .text(text, style) = element { return text.contains("bold") && style.contains(.bold) }
            return false
        } })
    }

    @Test func throwingOperationReleasesExtractionGate() throws {
        enum ProbeError: Error { case expected }
        #expect(throws: ProbeError.self) {
            try NativeTextReader.withExtractionLock { throw ProbeError.expected }
        }
        #expect(try NativeTextReader.withExtractionLock { 42 } == 42)
    }

    @Test func alreadyCancelledTaskNeverEntersExtraction() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try NativeTextReader.withExtractionLock { Issue.record("Cancelled task entered PDFKit gate") }
            }
        }
        await task.value
    }
}
