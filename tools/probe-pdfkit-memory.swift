// Standalone diagnostic: no PDFReflowLib, EPUB, images, or extracted strings are retained.
// Build and run instructions live in doc/memory-testing.md. Run each mode in a fresh process.
import Darwin
import Foundation
import PDFKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3, ["plain", "line", "page"].contains(arguments[1]),
      let passes = Int(arguments[2]), (1...10).contains(passes) else {
    fputs("Usage: probe-pdfkit-memory input.pdf plain|line|page passes(1...10)\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: arguments[0])
let mode = arguments[1]
let pages = autoreleasepool { PDFDocument(url: url)?.pageCount ?? 0 }
guard pages > 0 else { exit(2) }
var characters = 0
for pass in 1...passes {
    for index in 0..<pages {
        autoreleasepool {
            guard let document = PDFDocument(url: url), let page = document.page(at: index) else { exit(1) }
            if mode == "page" {
                characters += page.attributedString?.length ?? 0
            } else if let selection = page.selection(for: page.bounds(for: .cropBox)) {
                for line in selection.selectionsByLine() {
                    characters += mode == "line" ? (line.attributedString?.length ?? 0) : (line.string?.count ?? 0)
                }
            }
        }
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let capacity = Int(count)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    var record: [String: Any] = ["mode": mode, "pass": pass, "pages": pages,
        "peakRSSBytes": usage.ru_maxrss, "charactersVisited": characters]
    if status == KERN_SUCCESS { record["physicalFootprintAfterPassBytes"] = info.phys_footprint }
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
