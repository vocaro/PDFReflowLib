import Foundation
import PDFKit

// usage: probe2 <pdf> : per page, list-line tag groups before/after joiningMarkerPieces
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let doc = PDFDocument(url: url)!
let index = try StructureTreeReader.read(url)
func isList(_ t: String) -> Bool { t.range(of: "^(?:(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s|[0-9]+\\)−)", options: .regularExpression) != nil }
func caption(_ t: String) -> Bool { t.range(of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil }
/// unsafe groups: all, and those that are single list items (first line by order is the only list line, P, no caption)
func classify(_ lines: [TextLine]) -> (unsafe: Set<Int>, single: Set<Int>) {
    let groups = Dictionary(grouping: lines.filter { $0.structure != nil }, by: { $0.structure!.group })
    var unsafe = Set<Int>(), single = Set<Int>()
    for (g, ls) in groups {
        let list = ls.filter { isList($0.text) }
        guard !list.isEmpty || ls.contains(where: { caption($0.text) }) else { continue }
        unsafe.insert(g)
        let sorted = ls.sorted { ($0.structure!.order, -$0.rect.minY) < ($1.structure!.order, -$1.rect.minY) }
        if list.count == 1, sorted.first == list.first, ls.first!.structure!.headingLevel == 0,
           !ls.contains(where: { caption($0.text) }) { single.insert(g) }
    }
    return (unsafe, single)
}
var totals = [String: Int]()
print("page\tunsafeBefore\tunsafeAfterJoin\tjoinCreated\tjoinCreatedSingle\tpreexistingSingle\tpageUnsafeNowSafeIfJoinExempt\tpageUnsafeNowSafeIfSingleExempt")
for n in 1...doc.pageCount {
    autoreleasepool {
        let tags = index.pages[n] ?? [:]
        guard !tags.isEmpty, let page = doc.page(at: n - 1), let ref = page.pageRef else { return }
        var lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true)) ?? []
        guard StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref) else { return }
        _ = MarkedTextReader.apply(tags, page: ref, lines: &lines)
        guard lines.contains(where: { $0.structure != nil }) else { return }
        let before = classify(lines)
        let after = classify(LayoutReconstructor.joiningMarkerPieces(lines))
        let created = after.unsafe.subtracting(before.unsafe)
        let createdSingle = created.intersection(after.single)
        let preSingle = after.single.subtracting(created)
        let joinExempt = !after.unsafe.isEmpty && after.unsafe.subtracting(createdSingle).isEmpty
        let singleExempt = !after.unsafe.isEmpty && after.unsafe.subtracting(after.single).isEmpty
        if before.unsafe.isEmpty && after.unsafe.isEmpty { return }
        print("\(n)\t\(before.unsafe.count)\t\(after.unsafe.count)\t\(created.count)\t\(createdSingle.count)\t\(preSingle.count)\t\(joinExempt)\t\(singleExempt)")
        totals["pagesUnsafeBefore", default: 0] += before.unsafe.isEmpty ? 0 : 1
        totals["pagesUnsafeAfter", default: 0] += after.unsafe.isEmpty ? 0 : 1
        totals["pagesSafeIfJoinExempt", default: 0] += joinExempt ? 1 : 0
        totals["pagesSafeIfSingleExempt", default: 0] += singleExempt ? 1 : 0
        totals["createdNotSingle", default: 0] += created.count - createdSingle.count
    }
}
FileHandle.standardError.write("\(totals.sorted { $0.key < $1.key })\n".data(using: .utf8)!)
