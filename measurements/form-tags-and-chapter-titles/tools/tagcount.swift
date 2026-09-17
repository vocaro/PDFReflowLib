import Foundation
import PDFKit

// Per tagged page: whether every group applies, and how many native lines carry a tag after
// `MarkedTextReader.apply` (the reader keeps valid groups on pages it reports as fallbacks).
// Not the pipeline's page-image or synthetic-style gates; those pages are counted too.
@main struct TagCount {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = PDFDocument(url: url)!
        let index = try StructureTreeReader.read(url)
        var tagged = 0, allApply = 0, someLines = 0, lines = 0, taggedLines = 0
        for n in 1...document.pageCount {
            guard let tags = index.pages[n], !tags.isEmpty, let page = document.page(at: n - 1), let ref = page.pageRef else { continue }
            var native = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)
            tagged += 1
            let ok = StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref)
                && MarkedTextReader.apply(tags, page: ref, lines: &native)
            let count = native.filter { $0.structure != nil }.count
            if ok { allApply += 1 }
            if count > 0 { someLines += 1 }
            lines += native.count; taggedLines += count
        }
        print("taggedPages=\(tagged) allGroupsApply=\(allApply) pagesWithTaggedLines=\(someLines) taggedLines=\(taggedLines)/\(lines)")
    }
}
