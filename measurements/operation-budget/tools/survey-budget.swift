import Foundation
import CoreGraphics
import PDFKit
import Darwin

// The real reader with its budget lifted, so every page reports the operations it would charge
// and what a full scan of it costs in time and resident memory. Output: one JSON object per
// document on stdout.
private func residentBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

@main struct SurveyBudget {
    static func main() throws {
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            guard let document = PDFDocument(url: url) else { continue }
            var rows: [[String: Any]] = []
            for index in 0..<document.pageCount {
                autoreleasepool {
                    guard let page = document.page(at: index), let reference = page.pageRef else { return }
                    let before = residentBytes()
                    let start = Date()
                    let result = GraphicsReader.read(reference)
                    let seconds = Date().timeIntervalSince(start)
                    let after = residentBytes()
                    rows.append(["page": index + 1, "operations": result.operations, "seconds": seconds,
                                 "unsupported": result.unsupported, "regions": result.regions.count,
                                 "footprintBefore": before, "footprintAfter": after])
                }
            }
            let payload: [String: Any] = ["file": url.lastPathComponent, "pages": rows]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
