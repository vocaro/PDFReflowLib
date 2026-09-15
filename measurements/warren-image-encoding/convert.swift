import Foundation
import PDFReflowLib
@main struct Experiment {
    static func main() async throws {
        let args = CommandLine.arguments
        var options = ConversionOptions()
        // Experiment only: collect the complete lossless baseline, without changing library defaults.
        options.maximumOutputBytes = 2 * 1024 * 1024 * 1024
        let report = try await PDFConverter().convert(from: URL(fileURLWithPath: args[1]),
            to: URL(fileURLWithPath: args[2]), options: options) { event in
            FileHandle.standardError.write(Data("\(event.fractionCompleted) \(event.stage.rawValue) \(event.page ?? 0)/\(event.totalPages)\n".utf8))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
    }
}
