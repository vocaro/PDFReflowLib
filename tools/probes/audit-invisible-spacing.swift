import Foundation
import PDFKit

/// Run beside the library sources listed by tools/pdfreflow_tools/swift_sources.py.
/// Records every native line on which invisible word-box evidence restores a space.
/// This audits extraction only: it does not run recognition or reconstruction.
@main struct InvisibleSpacingAudit {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
            fatalError("usage: audit-invisible-spacing source.pdf changes.json")
        }
        var changes: [[String: Any]] = []
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef,
                      GraphicsReader.read(reference).hasOnlyInvisibleText else { return }
                let evidence = NativeSpacingReader.readInvisible(reference)
                guard !evidence.isEmpty,
                      let selections = page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() else { return }
                let bounds = selections.map { $0.bounds(for: page) }
                let owned = selections.indices.filter {
                    (selections[$0].string ?? "").contains { !$0.isWhitespace && $0 != "\u{FFFC}" }
                }.map { bounds[$0] }
                for (lineIndex, selection) in selections.enumerated() {
                    guard let before = selection.string else { continue }
                    let after = NativeSpacingReader.restoringInvisibleSpaces(before, evidence: evidence,
                        bounds: bounds[lineIndex], allBounds: owned)
                    if before != after { changes.append(["page": index + 1, "before": before, "after": after]) }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: changes, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
