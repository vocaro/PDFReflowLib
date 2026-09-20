// Development-only full-source cancellation probe. Link the existing release library objects.
import Foundation
import CryptoKit
import PDFReflowLib

@main
struct NOAACancellationProbe {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, ["reconstructing", "writing"].contains(arguments[3]) else {
            fatalError("Usage: cancel source.pdf new-output-directory reconstructing|writing")
        }
        let source = URL(fileURLWithPath: arguments[1])
        let directory = URL(fileURLWithPath: arguments[2])
        let requestedStage = arguments[3]
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == 219_876_258,
              hash == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf" else {
            fatalError("Source differs from pinned NOAA report")
        }
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            fatalError("Output directory must be new")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("canceled.epub")
        var options = ConversionOptions()
        options.fullPageImageEncoding = .jpeg(quality: 0.90)
        options.maximumOutputBytes = 4 * 1_024 * 1_024 * 1_024
        options.maximumEPUBBytes = 4 * 1_024 * 1_024 * 1_024
        let started = Date()
        do {
            _ = try await PDFConverter().convert(from: source, to: output, options: options) { event in
                let cancel = event.stage.rawValue == requestedStage
                    && (requestedStage == "writing" || event.page == 900)
                let line = "\(event.fractionCompleted) \(event.stage.rawValue) page \(event.page ?? 0)/\(event.totalPages) cancel=\(cancel)\n"
                FileHandle.standardError.write(Data(line.utf8))
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }
            fatalError("Canceled conversion unexpectedly succeeded")
        } catch is CancellationError {
            let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard remaining.isEmpty else { fatalError("Cancellation left staged/output files: \(remaining)") }
            let result: [String: Any] = ["sourceSHA256": hash, "sourcePages": 1834,
                "cancellationStage": requestedStage, "reconstructionTriggerPage": 900,
                "elapsedSeconds": Date().timeIntervalSince(started),
                "canceled": true, "outputAbsent": true, "stagingRemoved": true]
            let encoded = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(encoded)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
