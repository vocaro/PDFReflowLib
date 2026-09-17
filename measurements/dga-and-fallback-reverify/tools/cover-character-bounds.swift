import Foundation
import PDFKit
let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let page = document.page(at: 0)!
let selection = page.selection(for: page.bounds(for: .cropBox))!
for line in selection.selectionsByLine() {
    let n = line.numberOfTextRanges(on: page)
    print(line.string ?? "nil", "ranges", n, (0..<n).map { line.range(at: $0, on: page) }, line.bounds(for: page))
    if line.string?.contains("Fruits") == true {
        let r = line.range(at: 0, on: page)
        for o in 0..<r.length { print("  ", o, page.characterBounds(at: r.location + o)) }
    }
}
