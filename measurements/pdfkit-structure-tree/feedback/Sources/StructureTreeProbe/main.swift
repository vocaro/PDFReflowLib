// Standalone PDFKit reproducer: the first text-layout call on a page carrying /StructParents
// in a tagged document allocates ~489 MB. Only Foundation and PDFKit are used.
//
// usage: StructureTreeProbe <pdf> <one-based page> <call>
//   call: count | string | attributed | selection | smallselection | charbounds | thumbnail
// Run each call in a fresh process; the cost is paid once per process.
import Foundation
import PDFKit

func footprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let pageNumber = Int(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: StructureTreeProbe <pdf> <page> <call>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: arguments[1])
let call = arguments[3]
var summary = ""
autoreleasepool {
    guard var document = PDFDocument(url: url), let page = document.page(at: pageNumber - 1) else {
        FileHandle.standardError.write(Data("cannot open page \(pageNumber) of \(url.path)\n".utf8))
        exit(1)
    }
    let before = footprintBytes()
    var detail = ""
    switch call {
    case "count": detail = "\(page.numberOfCharacters) characters"
    case "string": detail = "\(page.string?.count ?? -1) characters"
    case "attributed": detail = "\(page.attributedString?.length ?? -1) attributed characters"
    case "selection": detail = "\(page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine().count ?? -1) lines"
    case "smallselection": detail = page.selection(for: CGRect(x: 0, y: 0, width: 20, height: 20)) == nil ? "no selection" : "selection"
    case "charbounds": detail = "\(page.characterBounds(at: 0))"
    case "thumbnail": detail = "\(page.thumbnail(of: CGSize(width: 200, height: 260), for: .cropBox).size)"
    default:
        FileHandle.standardError.write(Data("unknown call \(call)\n".utf8))
        exit(2)
    }
    let after = footprintBytes()
    document = PDFDocument()  // release the original document before the pool drains
    summary = String(format: "%-14@ page %d  before %6.1f MiB  after %7.1f MiB  delta %+7.1f MiB  (%@)",
                     call, pageNumber, Double(before) / 1_048_576, Double(after) / 1_048_576,
                     Double(after) / 1_048_576 - Double(before) / 1_048_576, detail)
}
malloc_zone_pressure_relief(nil, 0)
print(summary + String(format: "  released %7.1f MiB", Double(footprintBytes()) / 1_048_576))
