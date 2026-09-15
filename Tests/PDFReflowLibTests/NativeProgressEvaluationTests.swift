import Foundation
import Testing
@testable import PDFReflowLib

// SDK behavior probes for doc/progress-composition.md. These deliberately do not
// replace the converter's awaited event stream with an observed progress tree.
@Suite struct NativeProgressEvaluationTests {
    @Test func weightedChildrenCanRepresentTheExistingStageEstimates() {
        let overall = ProgressManager(totalCount: 100)
        let extraction = overall.subprogress(assigningCount: 55).start(totalCount: 4)
        let reconstruction = overall.subprogress(assigningCount: 25).start(totalCount: 4)
        let writing = overall.subprogress(assigningCount: 17).start(totalCount: 100)
        let reporter = overall.reporter

        #expect(reporter.fractionCompleted == 0)
        overall.complete(count: 2)
        for page in 1...4 {
            extraction.complete(count: 1)
            #expect(abs(reporter.fractionCompleted - (0.02 + 0.55 * Double(page) / 4)) < 1e-12)
        }
        for page in 1...4 {
            reconstruction.complete(count: 1)
            #expect(abs(reporter.fractionCompleted - (0.57 + 0.25 * Double(page) / 4)) < 1e-12)
        }
        writing.complete(count: 100)
        #expect(abs(reporter.fractionCompleted - 0.99) < 1e-12)
        #expect(!reporter.isFinished)
        overall.complete(count: 1) // Reserved for successful publication.
        #expect(reporter.fractionCompleted == 1)
        #expect(reporter.isFinished)
        withExtendedLifetime((extraction, reconstruction, writing)) {}
    }

    @Test func releasingAnUnfinishedChildCreditsItsEntireAllocation() {
        let overall = ProgressManager(totalCount: 100)
        var child: ProgressManager? = overall.subprogress(assigningCount: 100).start(totalCount: 10)
        child!.complete(count: 2)
        #expect(abs(overall.fractionCompleted - 0.2) < 1e-12)
        child = nil // Also happens when a throwing/cancelled operation unwinds.
        #expect(overall.fractionCompleted == 1)
        #expect(overall.isFinished)
    }

    @Test func retainingAChildReporterPreservesItsIncompleteStateUntilRelease() {
        let overall = ProgressManager(totalCount: 100)
        var child: ProgressManager? = overall.subprogress(assigningCount: 100).start(totalCount: 10)
        var reporter: ProgressReporter? = child!.reporter
        weak var retainedManager = child
        child!.complete(count: 2)
        child = nil
        #expect(retainedManager != nil)
        #expect(abs(reporter!.fractionCompleted - 0.2) < 1e-12)
        #expect(abs(overall.fractionCompleted - 0.2) < 1e-12)
        reporter = nil
        #expect(retainedManager == nil)
        #expect(overall.fractionCompleted == 1)
    }

    @Test func changingTotalDoesNotGuaranteeMonotonicProgress() {
        let manager = ProgressManager(totalCount: 10)
        manager.complete(count: 5)
        let before = manager.fractionCompleted
        manager.setCounts { _, total in total = 20 }
        #expect(before == 0.5)
        #expect(manager.fractionCompleted == 0.25)
        #expect(manager.fractionCompleted < before)
    }
}

private actor AwaitedProgressAudit {
    private var active = 0
    private(set) var overlaps = false
    private(set) var entered: [ConversionProgress] = []
    private(set) var returned: [ConversionProgress] = []

    func receive(_ event: ConversionProgress, destination: URL) async {
        active += 1
        overlaps = overlaps || active != 1
        entered.append(event)
        // Suspension lets an incorrectly detached/reentrant delivery enter again.
        try? await Task.sleep(for: .milliseconds(2))
        if event.stage == .completed {
            #expect(event.fractionCompleted == 1)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        } else {
            #expect(event.fractionCompleted < 1)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
        returned.append(event)
        active -= 1
    }
}

@Suite struct OrderedProgressContractTests {
    private var source: URL {
        Bundle.module.resourceURL!.appendingPathComponent("fixtures/prose.pdf")
    }

    @Test func slowCallbacksAreAwaitedThroughPublicationAndReturn() async throws {
        let directory = try testPDFDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("book.epub")
        let audit = AwaitedProgressAudit()
        _ = try await PDFConverter().convert(from: source, to: destination) { event in
            await audit.receive(event, destination: destination)
        }
        let events = await audit.entered
        #expect(await audit.returned == events)
        #expect(await !audit.overlaps)
        #expect(events.first?.stage == .opening)
        #expect(events.last?.stage == .completed)
        #expect(events.filter { $0.stage == .completed }.count == 1)
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.fractionCompleted <= $1.fractionCompleted })
        #expect(events.filter { $0.stage == .extracting }.compactMap(\.page) == [1, 2, 3])
        #expect(events.filter { $0.stage == .reconstructing }.compactMap(\.page) == [1, 2, 3])
        #expect(events.dropFirst().allSatisfy { $0.totalPages == 3 })
    }

    @Test(arguments: [false, true])
    func unsuccessfulConversionNeverReportsCompletion(cancel: Bool) async throws {
        let directory = try testPDFDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("book.epub")
        let audit = AwaitedProgressAudit()
        var options = ConversionOptions()
        // A final-file budget failure happens after writing reaches its endpoint.
        if !cancel { options.maximumEPUBBytes = 1 }
        let conversionOptions = options
        let task = Task {
            try await PDFConverter().convert(from: source, to: destination, options: conversionOptions) { event in
                await audit.receive(event, destination: destination)
                if cancel && event.stage == .writing { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation or the final-file budget failure")
        } catch is CancellationError {
            #expect(cancel)
        } catch ConversionError.resourceLimit(let name) {
            #expect(!cancel)
            #expect(name == "final EPUB file bytes")
        }
        let events = await audit.entered
        #expect(await audit.returned == events)
        #expect(await !audit.overlaps)
        #expect(events.contains { $0.stage == .writing })
        #expect(events.allSatisfy { $0.stage != .completed && $0.fractionCompleted < 1 })
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.fractionCompleted <= $1.fractionCompleted })
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
