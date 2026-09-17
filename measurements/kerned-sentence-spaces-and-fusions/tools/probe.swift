import Foundation
import PDFKit
// usage: probe <pdf> <page> [filter]  prints NativeSpacingReader evidence for one page
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let page = doc.page(at: Int(CommandLine.arguments[2])! - 1)!
let filter = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
let evidence = NativeSpacingReader.read(page.pageRef!)
print("evidence", evidence.count)
for e in evidence where filter.isEmpty || (e.unicode ?? "").contains(filter) {
    print(String(format: "%.2f %.2f end=%@ size=%.2f spaced=%d", e.origin.x, e.origin.y, e.end.map { String(format: "%.2f", $0) } ?? "nil", e.size, e.spaced ? 1 : 0),
          e.unicode ?? "<nil>", e.wordSpaces.sorted(), e.sentenceSpaces.sorted())
}
