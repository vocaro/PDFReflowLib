import Foundation
import ZIPFoundation

enum EPUBWriter {
    // A serialized body target, not a limit on an indivisible paragraph, heading or figure.
    private static let bodyTargetBytes = 60_000

    static func write(_ book: ReflowDocument, maximumOutputBytes: Int64, directory: URL,
                      packageIdentifier: String? = nil, modificationDate: Date? = nil,
                      progress: @Sendable (Double) async -> Void) async throws -> URL {
        try book.validate()
        let title = book.metadata.title
        // Logical asset identifiers never become paths. The EPUB writer owns archive naming;
        // resource bytes stream directly from neutral staging files into ZIP entries.
        let imagePaths = book.assets.enumerated().map { "images/image-\($0.offset + 1).\($0.element.format.fileExtension)" }
        let imagePathByID = Dictionary(uniqueKeysWithValues: zip(book.assets.map(\.id), imagePaths))
        let publication = directory.appendingPathComponent("EPUB")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("META-INF"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: publication, withIntermediateDirectories: true)
        let language = xml(book.metadata.language)
        func document(_ body: String, name: String) -> String {
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(language)" lang="\(language)">
            <head><title>\(xml(name))</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>\(body)</body></html>
            """
        }
        var toc: [String] = [], pages: [String] = []
        var consumed: Int64 = 0
        func writeText(_ string: String, _ url: URL) throws {
            try Task.checkCancellation()
            consumed += Int64(string.utf8.count)
            guard consumed <= maximumOutputBytes else { throw ConversionError.resourceLimit("EPUB text size") }
            try string.write(to: url, atomically: true, encoding: .utf8)
        }
        var chapters: [String] = []
        var body = ""
        var bodyBytes = 0
        var pendingPage: (number: Int, markup: String)?
        // Headings at the end of the body, with any standalone page markers between them, and the
        // navigation entries they added. A size split carries them into the next document so a
        // heading never ends one spine document while its content begins the next.
        var trailingHeadings: (bodyBytes: Int, toc: Int, pages: Int)?
        // Note links are written as same-document fragments and qualified with their target's
        // file once every document is packed. Packing reserves the longest possible file name
        // for each link, so a patched body still meets the target.
        let linkReservation = "chapter-\(book.blocks.count).xhtml".utf8.count
        var reservedBytes = 0
        var anchors: [String: String] = [:]
        var linkedDocuments: Set<String> = []
        var referenced: Set<NoteKey> = []
        for block in book.blocks {
            switch block.content {
            case let .paragraph(text), let .preformatted(text):
                for case let .noteReference(_, _, key) in text.elements { referenced.insert(key) }
            default: continue
            }
        }
        var referencesEmitted: Set<NoteKey> = []
        // Only a short heading run is kept with its content; a long run of headings packs normally.
        func keepsTrailingHeadings() -> Bool {
            guard let trailing = trailingHeadings else { return false }
            return bodyBytes - trailing.bodyBytes <= bodyTargetBytes / 10
        }
        func nextChapterName() -> String { "chapter-\(chapters.count + 1).xhtml" }
        func finishChapter(carryingTrailingHeadings: Bool = false) throws {
            guard !body.isEmpty else { return }
            let name = nextChapterName()
            var carried = ""
            var carriedEntries: (toc: [String], pages: [String]) = ([], [])
            if carryingTrailingHeadings, keepsTrailingHeadings(), let trailing = trailingHeadings, trailing.bodyBytes > 0 {
                let utf8 = Array(body.utf8)
                carried = String(decoding: utf8[trailing.bodyBytes...], as: UTF8.self)
                body = String(decoding: utf8[..<trailing.bodyBytes], as: UTF8.self)
                carriedEntries = (Array(toc[trailing.toc...]), Array(pages[trailing.pages...]))
                toc.removeSubrange(trailing.toc...)
                pages.removeSubrange(trailing.pages...)
            }
            try writeText(document(body, name: title), publication.appendingPathComponent(name))
            chapters.append(name)
            body = carried; bodyBytes = carried.utf8.count; reservedBytes = 0
            trailingHeadings = carried.isEmpty ? nil : (0, toc.count, pages.count)
            let next = nextChapterName()
            toc += carriedEntries.toc.map { $0.replacingOccurrences(of: "href=\"\(name)#", with: "href=\"\(next)#") }
            pages += carriedEntries.pages.map { $0.replacingOccurrences(of: "href=\"\(name)#", with: "href=\"\(next)#") }
        }
        /// `links` counts note hrefs in the markup that may gain a file name; `ids` are the
        /// note and reference anchors it defines.
        func append(_ markup: String, sourcePages: [Int], heading: (id: String, text: String)? = nil,
                    standaloneMarker: Bool = false, links: Int = 0, ids: [String] = []) throws {
            try Task.checkCancellation()
            let size = markup.utf8.count
            guard Int64(size) <= maximumOutputBytes - consumed else {
                throw ConversionError.resourceLimit("EPUB text size")
            }
            // A body holding only headings stays open for the content they introduce.
            if bodyBytes > 0, bodyBytes + reservedBytes + size + links * linkReservation > bodyTargetBytes,
               !(keepsTrailingHeadings() && trailingHeadings?.bodyBytes == 0) {
                try finishChapter(carryingTrailingHeadings: true)
            }
            if heading != nil, trailingHeadings == nil {
                trailingHeadings = (bodyBytes, toc.count, pages.count)
            } else if heading == nil, !standaloneMarker {
                trailingHeadings = nil
            }
            let name = nextChapterName()
            if links > 0 || !ids.isEmpty { linkedDocuments.insert(name) }
            for id in ids { anchors[id] = name }
            reservedBytes += links * linkReservation
            for number in sourcePages {
                pages.append("<li><a href=\"\(name)#page-\(number)\">\(number)</a></li>")
            }
            if let heading {
                toc.append("<li><a href=\"\(name)#\(xml(heading.id))\">\(xml(heading.text))</a></li>")
            }
            body += markup; bodyBytes += size
            // Never split an atomic block merely to satisfy the target. Oversized blocks
            // are isolated, retain their styles and anchors, and still obey the total budget.
            // A heading waits for its following content before the document is closed.
            if bodyBytes + reservedBytes >= bodyTargetBytes, !keepsTrailingHeadings() { try finishChapter() }
        }
        await progress(0)
        for (i, block) in book.blocks.enumerated() {
            try Task.checkCancellation()
            let completedChapters = chapters.count
            if case let .sourcePage(number) = block.content {
                // Consecutive boundaries describe empty source pages. Only the last boundary
                // needs to travel with the following content; earlier ones can be packed normally.
                if let pendingPage {
                    try append(pendingPage.markup, sourcePages: [pendingPage.number], standaloneMarker: true)
                }
                if book.chapterStartPages.contains(number) { trailingHeadings = nil; try finishChapter() }
                pendingPage = (number, EPUBTextEncoder.sourcePage(number))
            } else {
                var ids: [String] = []
                var links = 0
                // The first reference to a note carries the id its backlink targets.
                let payload = try EPUBTextEncoder.payload(block, imagePaths: imagePathByID) { key in
                    links += 1
                    guard referencesEmitted.insert(key).inserted else { return nil }
                    ids.append(EPUBTextEncoder.referenceID(key))
                    return ids.last
                }
                // A note some marker links to: its own id and a return link around its number.
                let linked = block.note.flatMap { key -> (id: String, payload: String)? in
                    guard referenced.contains(key) else { return nil }
                    let text: InlineText
                    switch block.content {
                    case let .paragraph(value), let .footnote(value): text = value
                    default: return nil
                    }
                    links += 1
                    ids.append(EPUBTextEncoder.noteID(key))
                    return (EPUBTextEncoder.noteID(key),
                            EPUBTextEncoder.note(text, number: key.number, backlink: EPUBTextEncoder.referenceID(key)))
                }
                let markup: String
                var heading: (id: String, text: String)?
                switch block.content {
                case .paragraph:
                    if let linked {
                        markup = "<p id=\"\(xml(linked.id))\" epub:type=\"endnote\">\(linked.payload)</p>\n"
                    } else { markup = "<p>\(payload)</p>\n" }
                case let .heading(id, _, level):
                    markup = "<h\(level) id=\"\(xml(id))\">\(payload)</h\(level)>\n"
                    heading = (id, block.text)
                case .preformatted: markup = "<pre>\(payload)</pre>\n"
                // A visible block with DPUB-ARIA note semantics. An `aside` with
                // epub:type="footnote" is hidden from the flow by some reading systems
                // unless a noteref links to it; an unlinked note keeps this visible form.
                case .footnote:
                    if let linked {
                        markup = "<div class=\"footnote\" role=\"doc-footnote\" id=\"\(xml(linked.id))\"><p>\(linked.payload)</p></div>\n"
                    } else { markup = "<div class=\"footnote\" role=\"doc-footnote\"><p>\(payload)</p></div>\n" }
                case .image, .table: markup = payload + "\n"
                case .sourcePage: preconditionFailure("Source boundaries are handled above")
                }
                try append((pendingPage?.markup ?? "") + markup,
                           sourcePages: pendingPage.map { [$0.number] + block.sourcePages } ?? block.sourcePages,
                           heading: heading, links: links, ids: ids)
                pendingPage = nil
            }
            // Report input-block work without requiring a second serialization pass to count
            // chapters. Bound callback frequency for documents with many tiny blocks.
            if chapters.count != completedChapters || (i + 1).isMultiple(of: 128) || i + 1 == book.blocks.count {
                await progress(0.45 * Double(i + 1) / Double(book.blocks.count))
            }
        }
        if let pendingPage { try append(pendingPage.markup, sourcePages: [pendingPage.number], standaloneMarker: true) }
        try finishChapter()
        // Qualify note and return links whose target lies in another spine document. Only
        // the writer emits `href="#note…"`; escaped text cannot.
        for name in chapters where linkedDocuments.contains(name) {
            try Task.checkCancellation()
            let url = publication.appendingPathComponent(name)
            let text = try String(contentsOf: url, encoding: .utf8)
            var patched = ""
            var cursor = text.startIndex
            while let range = text.range(of: "href=\"#(?:note|noteref)-[^\"]+\"", options: .regularExpression,
                                         range: cursor..<text.endIndex) {
                patched += text[cursor..<range.lowerBound]
                let id = String(text[range].dropFirst("href=\"#".count).dropLast())
                if let file = anchors[id], file != name { patched += "href=\"\(file)#\(id)\"" }
                else { patched += text[range] }
                cursor = range.upperBound
            }
            patched += text[cursor...]
            guard patched != text else { continue }
            consumed -= Int64(text.utf8.count)
            try writeText(patched, url)
        }
        if toc.isEmpty { toc = ["<li><a href=\"\(chapters[0])\">\(xml(title))</a></li>"] }
        let nav = """
        <nav epub:type="toc" id="toc"><h1>Contents</h1><ol>\(toc.joined())</ol></nav>
        <nav epub:type="page-list" hidden="hidden"><h2>Source pages</h2><ol>\(pages.joined())</ol></nav>
        """
        try writeText(document(nav, name: "Contents"), publication.appendingPathComponent("nav.xhtml"))
        try writeText("""
        body { margin: 1em; line-height: 1.5; overflow-wrap: break-word; }
        p { margin: 0 0 0.8em; } h1, h2 { break-after: avoid; }
        img { max-width: 100%; height: auto; } figure { margin: 1em 0; }
        figcaption { font-size: 0.85em; } pre { white-space: pre-wrap; overflow-wrap: anywhere; }
        div.footnote { font-size: 0.85em; }
        table { border-collapse: collapse; margin: 0 0 1em; }
        th, td { border: 1px solid #999; padding: 0.3em; text-align: left; vertical-align: top; }
        caption { text-align: left; } caption p { margin: 0 0 0.4em; }
        """, publication.appendingPathComponent("style.css"))
        // Caller-supplied values make the archive byte-reproducible; defaults vary per run.
        let identifier = xml(packageIdentifier ?? "urn:uuid:" + UUID().uuidString)
        let modificationDate = modificationDate ?? Date()
        let modified = ISO8601DateFormatter().string(from: modificationDate)
        let author = book.metadata.author.map { "<dc:creator>\(xml($0))</dc:creator>" } ?? ""
        let manifest = chapters.enumerated().map {
            "<item id=\"c\($0.offset)\" href=\"\($0.element)\" media-type=\"application/xhtml+xml\"/>"
        }.joined() + imagePaths.enumerated().map {
            "<item id=\"img\($0.offset)\" href=\"\($0.element)\" media-type=\"\(book.assets[$0.offset].format.mediaType)\"/>"
        }.joined()
        let spine = chapters.indices.map { "<itemref idref=\"c\($0)\"/>" }.joined()
        try writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" prefix="rendition: http://www.idpf.org/vocab/rendition/#">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">\(identifier)</dc:identifier><dc:title>\(xml(title))</dc:title><dc:language>\(language)</dc:language>\(author)<meta property="dcterms:modified">\(modified)</meta><meta property="rendition:layout">reflowable</meta></metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="style.css" media-type="text/css"/>\(manifest)</manifest><spine>\(spine)</spine></package>
        """, publication.appendingPathComponent("package.opf"))
        try writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """, directory.appendingPathComponent("META-INF/container.xml"))
        try writeText("application/epub+zip", directory.appendingPathComponent("mimetype"))
        let paths = ["mimetype", "META-INF/container.xml", "EPUB/package.opf", "EPUB/nav.xhtml", "EPUB/style.css"]
            + chapters.map { "EPUB/" + $0 }
        let entries = paths.map { (path: $0, url: directory.appendingPathComponent($0)) }
            + zip(imagePaths, book.assets).map { (path: "EPUB/" + $0.0, url: $0.1.fileURL) }
        await progress(0.5)
        try Task.checkCancellation()
        let archiveURL = directory.appendingPathComponent("publication.epub")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        var bytes: Int64 = 0
        for (i, entry) in entries.enumerated() {
            let path = entry.path
            try Task.checkCancellation()
            let url = entry.url
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            bytes += Int64(size)
            guard bytes <= maximumOutputBytes else { throw ConversionError.resourceLimit("EPUB total size") }
            // First entry is the uncompressed, exact ASCII EPUB mimetype, as required by OCF.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(size),
                modificationDate: modificationDate,
                compressionMethod: path == "mimetype" ? .none : .deflate) { position, count in
                try autoreleasepool {
                    try Task.checkCancellation()
                    try handle.seek(toOffset: UInt64(position))
                    return try handle.read(upToCount: count) ?? Data()
                }
            }
            await progress(0.5 + 0.5 * Double(i + 1) / Double(entries.count))
        }
        return archiveURL
    }
}
