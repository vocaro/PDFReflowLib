import Foundation
import ZIPFoundation

enum EPUBWriter {
    private struct Chapter { var name: String; var blocks: [ReflowBlock] }

    static func write(_ book: ReflowDocument, maximumOutputBytes: Int64, directory: URL,
                      progress: @Sendable (Double) async -> Void) async throws -> URL {
        try book.validate()
        let title = book.metadata.title
        // Logical asset identifiers never become paths. The EPUB writer owns archive naming;
        // resource bytes stream directly from neutral staging files into ZIP entries.
        let imagePaths = book.assets.enumerated().map { "images/image-\($0.offset + 1).\($0.element.format.fileExtension)" }
        let imagePathByID = Dictionary(uniqueKeysWithValues: zip(book.assets.map(\.id), imagePaths))
        var chapters: [Chapter] = []
        var current: [ReflowBlock] = []
        var count = 0
        for block in book.blocks {
            try Task.checkCancellation()
            if count > 60_000, !current.isEmpty {
                chapters.append(Chapter(name: "chapter-\(chapters.count + 1).xhtml", blocks: current))
                current = []; count = 0
            }
            current.append(block); count += try EPUBTextEncoder.payload(block, imagePaths: imagePathByID).utf8.count
        }
        if !current.isEmpty { chapters.append(Chapter(name: "chapter-\(chapters.count + 1).xhtml", blocks: current)) }
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
            consumed += Int64(string.utf8.count)
            guard consumed <= maximumOutputBytes else { throw ConversionError.resourceLimit("EPUB text size") }
            try string.write(to: url, atomically: true, encoding: .utf8)
        }
        for (i, chapter) in chapters.enumerated() {
            try Task.checkCancellation()
            var body = ""
            for block in chapter.blocks {
                for number in block.sourcePages {
                    pages.append("<li><a href=\"\(chapter.name)#page-\(number)\">\(number)</a></li>")
                }
                let payload = try EPUBTextEncoder.payload(block, imagePaths: imagePathByID)
                switch block.content {
                case .paragraph: body += "<p>\(payload)</p>\n"
                case let .heading(id, _):
                    body += "<h2 id=\"\(xml(id))\">\(payload)</h2>\n"
                    toc.append("<li><a href=\"\(chapter.name)#\(xml(id))\">\(xml(block.text))</a></li>")
                case .preformatted: body += "<pre>\(payload)</pre>\n"
                case .image: body += payload + "\n"
                case .sourcePage: body += payload
                }
            }
            try writeText(document(body, name: title), publication.appendingPathComponent(chapter.name))
            await progress(Double(i + 1) / Double(chapters.count + imagePaths.count + 5) * 0.5)
        }
        if toc.isEmpty { toc = ["<li><a href=\"\(chapters[0].name)\">\(xml(title))</a></li>"] }
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
        """, publication.appendingPathComponent("style.css"))
        let identifier = "urn:uuid:" + UUID().uuidString
        let modified = ISO8601DateFormatter().string(from: Date())
        let author = book.metadata.author.map { "<dc:creator>\(xml($0))</dc:creator>" } ?? ""
        let manifest = chapters.enumerated().map {
            "<item id=\"c\($0.offset)\" href=\"\($0.element.name)\" media-type=\"application/xhtml+xml\"/>"
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
            + chapters.map { "EPUB/" + $0.name }
        let entries = paths.map { (path: $0, url: directory.appendingPathComponent($0)) }
            + zip(imagePaths, book.assets).map { (path: "EPUB/" + $0.0, url: $0.1.fileURL) }
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
