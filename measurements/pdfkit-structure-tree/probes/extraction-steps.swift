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
let path = CommandLine.arguments[1]
let pages = Int(CommandLine.arguments[2]) ?? 12
let url = URL(fileURLWithPath: path)
var options = ConversionOptions()
print(String(format: "start                     %7.1f MiB", footprint()))
let structure = try StructureTreeReader.read(url)
print(String(format: "structure index           %7.1f MiB (pages: %d)", footprint(), structure.pages.count))
let source = try PDFPageSource(url: url)
print(String(format: "PDFPageSource open        %7.1f MiB", footprint()))
for i in 0..<min(pages, source.pageCount) {
    try autoreleasepool {
        let page = try source.page(at: i)
        let a = footprint()
        guard let reference = page.pageRef else { return }
        let bounds = page.bounds(for: .cropBox)
        let graphics = GraphicsReader.read(reference)
        let b = footprint()
        let requiresPageImage = graphics.unsupported || page.rotation % 360 != 0
        let lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: !requiresPageImage)
        let c = footprint()
        var content = PageContent(number: i + 1, bounds: bounds, lines: lines, graphics: graphics.regions)
        var tagged = false
        if let tags = structure.pages[i + 1], !tags.isEmpty {
            tagged = StructureTreeReader.validates(tags, owners: structure.owners[i + 1] ?? [:], page: reference)
                && MarkedTextReader.apply(tags, page: reference, lines: &content.lines)
        }
        let d = footprint()
        let annotations = page.annotations.count
        let e = footprint()
        print(String(format: "page %3d  open %7.1f  graphics %7.1f (+%6.1f, %d regions)  text %7.1f (+%6.1f, %d lines)  tags %7.1f (+%5.1f, %@)  annots %7.1f (%d)",
                     i + 1, a, b, b - a, graphics.regions.count, c, c - b, lines.count, d, d - c, tagged ? "applied" : "none", e, annotations))
    }
}
source.releaseCachedPages()
print(String(format: "after release             %7.1f MiB", footprint()))
