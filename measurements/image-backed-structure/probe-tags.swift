import Foundation

// usage: probe <pdf> page... : dump every block on the listed pages with its tag provenance
let args = CommandLine.arguments
let pages = Set(args.dropFirst(2).compactMap { Int($0) })
let workspace = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("probe-\(UUID().uuidString)")
let semaphore = DispatchSemaphore(value: 0)
Task {
    defer { semaphore.signal() }
    do {
        let result = try await PDFReflowLibPipeline.reconstruct(from: URL(fileURLWithPath: args[1]),
            options: ConversionOptions(), workspace: workspace, progress: { _ in })
        for block in result.document.blocks where pages.contains(block.page) {
            let kind: String
            switch block.content {
            case let .heading(_, _, level): kind = "h\(level)"
            case .paragraph: kind = "p"
            case .preformatted: kind = "pre"
            case .footnote: kind = "note"
            case .image: kind = "img"
            case .table: kind = "table"
            case .sourcePage: kind = "page"
            }
            let tagged = block.taggedLevel.map { $0 == 0 ? "P" : "H\($0)" } ?? "-"
            print("\(block.page)\t\(kind)\ttag=\(tagged)\tgroup=\(block.structureGroup.map(String.init) ?? "-")\t\(block.text.prefix(90))")
        }
    } catch { print("error \(error)") }
    try? FileManager.default.removeItem(at: workspace)
}
semaphore.wait()
