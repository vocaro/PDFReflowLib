import Foundation
import CryptoKit

// usage: pipeprobe <pdf> <ocr: never|automatic>
// Runs the whole reconstruction pipeline (no EPUB writing, reference images off, JPEG regions at a
// low DPI to save time) and prints one line per source page with a hash of that page's blocks, then
// hashes of warnings, note links and assets. Differences between processes are nondeterminism.
@main struct PipeProbe {
    static func h(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined() }
    static func main() async throws {
        let args = CommandLine.arguments
        var options = ConversionOptions()
        options.ocr = args.count > 2 && args[2] == "automatic" ? .automatic : .never
        options.referenceImages = .never
        options.regionImageEncoding = .jpeg(quality: 0.3)
        options.fullPageImageEncoding = .jpeg(quality: 0.3)
        options.rasterDPI = 72
        options.maximumOutputBytes = 64 * 1024 * 1024 * 1024
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pipeprobe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let result = try await PDFReflowLibPipeline.reconstruct(from: URL(fileURLWithPath: args[1]), options: options,
                                                                workspace: workspace, progress: { _ in })
        var pages: [Int: [String]] = [:]
        for block in result.document.blocks {
            pages[block.page, default: []].append("\(block)")
        }
        for page in pages.keys.sorted() {
            print("page \(page)\t\(h(pages[page]!.joined(separator: "\n")))")
        }
        print("blocks\t\(result.document.blocks.count)\t\(h(result.document.blocks.map { "\($0)" }.joined(separator: "\n")))")
        print("warnings\t\(result.warnings.count)\t\(h(result.warnings.map { "\($0)" }.joined(separator: "\n")))")
        print("notes\t\(h("\(result.noteLinks)"))")
        print("assets\t\(result.document.assets.count)")
        print("chapters\t\(h("\(result.document.chapterStartPages.sorted())"))")
    }
}
