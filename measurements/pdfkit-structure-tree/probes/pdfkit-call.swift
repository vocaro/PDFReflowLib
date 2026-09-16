import Foundation
import PDFKit

func footprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let index = (Int(CommandLine.arguments[2]) ?? 2) - 1
let mode = CommandLine.arguments[3]
var line = ""
autoreleasepool {
    var document: PDFDocument? = PDFDocument(url: url)
    let page = document!.page(at: index)!
    let before = footprint()
    var detail = ""
    switch mode {
    case "count": detail = "\(page.numberOfCharacters) chars"; 
    case "string": detail = "\(page.string?.count ?? -1) chars"
    case "attributed": detail = "\(page.attributedString?.length ?? -1) attributed"
    case "selection": detail = "\(page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine().count ?? -1) lines"
    case "smallselection": detail = "\(page.selection(for: CGRect(x: 0, y: 0, width: 20, height: 20)) == nil ? "nil" : "sel")"
    case "charbounds": detail = "\(page.characterBounds(at: 0))"
    case "thumbnail": detail = "\(page.thumbnail(of: CGSize(width: 200, height: 260), for: .cropBox).size)"
    case "cgpage": detail = "\(page.pageRef.map { $0.getBoxRect(.cropBox) } ?? .zero)"
    default: break
    }
    let after = footprint()
    document = nil
    line = String(format: "%-15@ before %6.1f  after %7.1f (+%6.1f)  %@", mode, before, after, after - before, detail)
}
let drained = footprint()
malloc_zone_pressure_relief(nil, 0)
print(line + String(format: "  | released+drained %7.1f MiB | after pressure relief %7.1f MiB", drained, footprint()))
if CommandLine.arguments.count > 4 { fputs("pid \(getpid())\n", stderr); sleep(12) }
