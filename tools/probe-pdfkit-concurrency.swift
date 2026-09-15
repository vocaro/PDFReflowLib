// Standalone Apple-SDK probe. Compile with -D PDFREFLOW_NATIVE and the library's
// extraction/value sources to additionally exercise the actual NativeTextReader.
import Foundation
import PDFKit
import Darwin
#if os(macOS)
import AppKit
#endif

private struct Sample: Sendable {
    var completed = 0
    var failures: [String] = []
}

private final class Workers: @unchecked Sendable {
    // Only counters and value results cross threads. Each iteration owns its PDFKit objects.
    private let condition = NSCondition()
    private var ready = 0
    private var released = false
    private var results: [Sample] = []

    func awaitStart() {
        condition.lock()
        ready += 1
        condition.broadcast()
        while !released { condition.wait() }
        condition.unlock()
    }
    func release(count: Int) {
        condition.lock()
        while ready < count { condition.wait() }
        released = true
        condition.broadcast()
        condition.unlock()
    }
    func finish(_ sample: Sample) {
        condition.lock()
        results.append(sample)
        condition.broadcast()
        condition.unlock()
    }
    func collect(count: Int) -> [Sample] {
        condition.lock()
        defer { condition.unlock() }
        while results.count < count { condition.wait() }
        return results
    }
}

private let expected = ["Small heading", "First paragraph line", "second paragraph line."]
private let sizes: [CGFloat] = [12, 24, 24]

private func extract(_ url: URL, mode: String) throws {
    guard let document = PDFDocument(url: url), document.pageCount == 1,
          let page = document.page(at: 0) else { throw ProbeError.invalid("Cannot open one-page fixture") }
    #if PDFREFLOW_NATIVE
    if mode == "native" {
        let lines = try NativeTextReader.lines(on: page, limit: 1_000)
        guard lines.map(\.text) == expected, lines.count == sizes.count,
              zip(lines, sizes).allSatisfy({ abs($0.fontSize - $1) < 0.01 }) else {
            throw ProbeError.invalid("Native text/font mismatch: \(lines.map(\.text)) / \(lines.map(\.fontSize))")
        }
        return
    }
    #endif
    guard let selection = page.selection(for: page.bounds(for: .cropBox)) else {
        throw ProbeError.invalid("Missing selection")
    }
    let lines = selection.selectionsByLine()
    let strings = lines.map { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    guard strings == expected else { throw ProbeError.invalid("Text mismatch: \(strings)") }
    if mode == "attributed" {
        for (line, size) in zip(lines, sizes) {
            guard let attributed = line.attributedString,
                  attributed.string.trimmingCharacters(in: .whitespacesAndNewlines) == line.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  attributed.length > 0 else { throw ProbeError.invalid("Missing/mismatched attributed text") }
            var valid = true
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                guard let font = value as? NSFont, abs(font.pointSize - size) < 0.01 else { valid = false; return }
            }
            guard valid else { throw ProbeError.invalid("Missing/wrong font") }
        }
    }
}

private enum ProbeError: Error { case invalid(String) }

@main enum Probe {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var modes = ["plain", "attributed"]
        #if PDFREFLOW_NATIVE
        modes.append("native")
        #endif
        guard args.count == 4, modes.contains(args[1]),
              let workers = Int(args[2]), (0...16).contains(workers),
              let iterations = Int(args[3]), (1...10_000).contains(iterations) else {
            FileHandle.standardError.write(Data("Usage: probe fixture.pdf plain|attributed|native workers(0=main,1...16) iterations(1...10000)\n".utf8))
            exit(2)
        }
        let url = URL(fileURLWithPath: args[0]), mode = args[1]
        func emit(_ record: [String: Any]) throws {
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        try emit(["event": "started", "mode": mode, "workers": workers, "iterations": iterations])
        let run: @Sendable () -> Sample = {
            var sample = Sample()
            for iteration in 0..<iterations {
                do {
                    try autoreleasepool { try extract(url, mode: mode) }
                    sample.completed += 1
                } catch {
                    sample.failures.append("Iteration \(iteration): \(error)")
                    break
                }
            }
            return sample
        }
        let samples: [Sample]
        if workers == 0 { samples = [run()] }
        else {
            let state = Workers()
            for _ in 0..<workers {
                Thread.detachNewThread {
                    state.awaitStart()
                    state.finish(run())
                }
            }
            state.release(count: workers)
            samples = state.collect(count: workers)
        }
        let failures = samples.flatMap(\.failures)
        let completed = samples.reduce(0) { $0 + $1.completed }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        try emit(["event": "completed", "mode": mode, "workers": workers, "iterations": iterations,
                  "completed": completed, "failures": failures, "peakRSSBytes": usage.ru_maxrss])
        if !failures.isEmpty || completed != max(1, workers) * iterations { exit(1) }
    }
}
