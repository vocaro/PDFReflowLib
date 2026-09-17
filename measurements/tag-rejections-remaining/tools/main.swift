import Foundation
import PDFKit

// usage: census <pdf> : one TSV row per tagged page (stdout); SAMPLE rows for rejected anchors (stderr).
// Columns: page, tags (MCIDs), groups, imageBacked, invisibleText, validates, reader result, page-level
// reason, rejected groups, group reasons, ignored space-only shows by would-be placement, tagged lines, lines.
// The gates mirror PDFReflowLibPipeline.extractPage: page image (unsupported graphics or rotation) and
// synthetic style (only invisible text over a page-sized graphic) are not attempted.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let doc = PDFDocument(url: url)!
let index = try StructureTreeReader.read(url)
FileHandle.standardError.write("treePresent \(index.present) treeRejected \(index.rejected) taggedPages \(index.pages.count)\n".data(using: .utf8)!)
print("page\ttags\tgroups\timageBacked\tinvisibleText\tvalidates\tapplies\tpageReason\trejectedGroups\tgroupReasons\tblank\ttaggedLines\tlines")
for n in 1...doc.pageCount {
    autoreleasepool {
        let tags = index.pages[n] ?? [:]
        guard !tags.isEmpty, let page = doc.page(at: n - 1), let ref = page.pageRef else { return }
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(ref)
        let requires = g.unsupported || page.rotation % 360 != 0
        let synthetic = g.hasOnlyInvisibleText && g.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 }
        var lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: !requires && !synthetic)) ?? []
        let imageBacked = !lines.isEmpty && g.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 }
        let groups = Set(tags.values.map(\.group))
        let v = StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref)
        CensusReader.pageReason = nil; CensusReader.groupReasons = [:]; CensusReader.anchorBytes = []
        CensusReader.samples = []; CensusReader.blankPoints = []; CensusReader.blankUnknown = 0; CensusReader.blankStats = [:]
        var applies = "-", rejected = 0, reasons = ""
        if requires || synthetic {
            applies = requires ? "notAttempted(pageImage)" : "notAttempted(syntheticStyle)"
        } else if v {
            let ok = CensusReader.apply(tags, page: ref, lines: &lines)
            applies = ok ? "all" : "partial"
            rejected = CensusReader.groupReasons.count
            let counts = CensusReader.groupReasons.values.reduce(into: [String: Int]()) { acc, set in for r in set { acc[r, default: 0] += 1 } }
            reasons = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            for sample in CensusReader.samples { FileHandle.standardError.write("SAMPLE\t\(n)\t\(sample)\n".data(using: .utf8)!) }
        }
        let blank = CensusReader.blankStats.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let tagged = lines.filter { $0.structure != nil }.count
        print("\(n)\t\(tags.count)\t\(groups.count)\t\(imageBacked)\t\(g.hasInvisibleText)\t\(v)\t\(applies)\t\(CensusReader.pageReason ?? "-")\t\(rejected)\t\(reasons.isEmpty ? "-" : reasons)\t\(blank.isEmpty ? "-" : blank)\t\(tagged)\t\(lines.count)")
    }
}
