import Foundation
import PDFKit

// For every page: count lines whose raw selection string contains an attachment placeholder,
// and how many of those carry any non-plain style in the library's styled extraction.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = try PDFPageSource(url: url)
var attachmentLines = 0, styledAttachmentLines = 0, pagesWithAttachments = 0, lineTotal = 0
var examples: [String] = []
for i in 0..<source.pageCount {
    try autoreleasepool {
        let page = try source.page(at: i)
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
        let raw = selection.selectionsByLine().compactMap(\.string)
        lineTotal += raw.count
        let withAttachment = raw.filter { $0.contains("\u{FFFC}") }
        guard !withAttachment.isEmpty else { return }
        pagesWithAttachments += 1
        attachmentLines += withAttachment.count
        let styled = try NativeTextReader.lines(on: page, limit: 100_000_000, includeStyle: true)
        for line in styled {
            let hasStyle = line.content.elements.contains { if case let .text(_, style) = $0 { return !style.isEmpty }; return false }
            // A styled extraction line came from a raw line with an attachment if its text appears in one.
            if hasStyle, withAttachment.contains(where: { $0.replacingOccurrences(of: "\u{FFFC}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(String(line.text.prefix(12))) }) {
                styledAttachmentLines += 1
                if examples.count < 5 { examples.append("p\(i + 1): \(line.text.prefix(60))") }
            }
        }
    }
}
print("\(url.lastPathComponent): pages \(source.pageCount), lines \(lineTotal), pages with attachments \(pagesWithAttachments), attachment lines \(attachmentLines), styled attachment lines \(styledAttachmentLines)")
for e in examples { print("   ", e) }
