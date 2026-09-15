import Foundation
import PDFKit
import Darwin
let path = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
var count = 0
for pass in 1...3 {
    for index in 0..<522 {
        autoreleasepool {
            let document = PDFDocument(url: URL(fileURLWithPath: path))!
            let page = document.page(at: index)!
            if mode == "page" {
                count += page.attributedString?.length ?? 0
            } else if let selection = page.selection(for: page.bounds(for: .cropBox)) {
                for line in selection.selectionsByLine() {
                    count += mode == "line" ? (line.attributedString?.length ?? 0) : (line.string?.count ?? 0)
                }
            }
        }
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print("pass \(pass) peakRSSBytes \(usage.ru_maxrss) count \(count)")
    fflush(stdout)
}
