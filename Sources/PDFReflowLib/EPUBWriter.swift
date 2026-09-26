import Foundation
import ZIPFoundation

/// Serializes a logical document as an EPUB 3 archive: spine documents packed by `SpinePacker`,
/// navigation, stylesheet, package metadata, container and the OCF ZIP layout. It has no PDF or
/// OCR dependency, and `EPUBTextEncoder` is the only place that knows XHTML markup.
///
/// The document arrives as a stream of `ReflowPart`s, so a producer never has to hold it whole:
/// each block is serialized once as it arrives and completed spine documents are written as they
/// close, leaving only the open body, the navigation entries and the asset registry in memory.
/// Navigation, package metadata and the archive are built in `finish`.
actor EPUBWriter {
    // A serialized body target, not a limit on an indivisible paragraph, heading or figure.
    private static let bodyTargetBytes = 60_000

    private let maximumOutputBytes: Int64
    private let directory: URL
    private let publication: URL
    private let packageIdentifier: String?
    private let modificationDate: Date?

    private var title = ""
    private var language = ""
    private var author: String?
    private var summary: String?
    private var keywords: [String] = []
    private var created: Date?
    private var pageLabels: [Int: String] = [:]
    private var outline: [OutlineEntry] = []
    private var packer = SpinePacker(bodyTargetBytes: EPUBWriter.bodyTargetBytes, chapterStartPages: [])
    private var validation = ReflowDocument.Validation()
    /// Assets in arrival order: the archive names them by that order and packages their bytes.
    private var assets: [ReflowDocument.Asset] = []
    private var imagePaths: [String] = []
    private var imagePathByID: [String: String] = [:]
    /// Spine documents holding an internal link whose page is not yet placed (#247).
    private var documentsWithPageLinks: [String] = []
    private var documentsWithNoteLinks: [String] = []
    private var noteFiles: [String: String] = [:]
    /// EPUB's manifest must identify every spine document containing MathML (#206).
    private var mathDocuments: Set<String> = []
    private var consumed: Int64 = 0
    private var started = false
    /// The right-to-left and the Latin letters of the book's text blocks (#41). A book most of
    /// whose text is written that way states `page-progression-direction="rtl"`, so a reader turns
    /// its pages and lays out its spreads the way the source does. Letters, not blocks: the Hebrew
    /// Shakespeare sets its Hebrew verse a short block to a line beside English prose and notes,
    /// so its blocks stand near half and half, and joining its split note numbers into their
    /// paragraphs moved them from 49.5% to 50.3% right to left (#314), where its letters are 27.5%
    /// Hebrew, in a book bound left to right.
    private var rightToLeftLetters = 0
    private var latinLetters = 0
    /// The list being packed (#292). A list is packed as one unit, like a table: its items are
    /// gathered until a block that is not an item, a chapter start or the end of the document
    /// arrives, so a spine document never ends inside a list. A list may hold nothing but items,
    /// so a page boundary that arrives while one is open is held here too, and written inside
    /// the item it precedes, or inside the item before it when the page is empty, rather than
    /// handed to the packer, which would set it between two items.
    private var openList: OpenList?
    private var heldPage: Int?
    private var chapterStartPages: Set<Int> = []
    private struct OpenList {
        var kind: ReflowBlock.ListItem.Kind
        var start: Int?
        var entries: [EPUBTextEncoder.ListEntry]
    }

    init(maximumOutputBytes: Int64, directory: URL, packageIdentifier: String? = nil, modificationDate: Date? = nil) {
        self.maximumOutputBytes = maximumOutputBytes
        self.directory = directory
        self.publication = directory.appendingPathComponent("EPUB")
        self.packageIdentifier = packageIdentifier
        self.modificationDate = modificationDate
    }

    /// Writes a whole document by streaming its parts, for callers that already hold one.
    static func write(_ book: ReflowDocument, maximumOutputBytes: Int64, directory: URL,
                      packageIdentifier: String? = nil, modificationDate: Date? = nil,
                      progress: @Sendable (Double) async -> Void) async throws -> URL {
        let writer = EPUBWriter(maximumOutputBytes: maximumOutputBytes, directory: directory,
                                packageIdentifier: packageIdentifier, modificationDate: modificationDate)
        for part in book.parts { try await writer.receive(part) }
        return try await writer.finish(progress: progress)
    }

    /// Accepts the next part of the document. Blocks are validated and serialized here, so a
    /// rejected model or an exhausted byte budget stops the producer where the fault is.
    func receive(_ part: ReflowPart) throws {
        try validation.accept(part)
        switch part {
        case let .start(metadata, chapterStartPages):
            precondition(!started, "a document starts once")
            started = true
            title = metadata.title
            language = xml(metadata.language)
            author = metadata.author
            summary = metadata.summary
            keywords = metadata.keywords
            created = metadata.created
            pageLabels = metadata.pageLabels
            outline = metadata.outline
            packer = SpinePacker(bodyTargetBytes: Self.bodyTargetBytes, chapterStartPages: chapterStartPages,
                                 pageLabels: metadata.pageLabels)
            self.chapterStartPages = chapterStartPages
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("META-INF"),
                                                    withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: publication, withIntermediateDirectories: true)
        case let .asset(asset):
            // Logical asset identifiers never become paths. The EPUB writer owns archive naming;
            // resource bytes stream directly from neutral staging files into ZIP entries.
            let path = "images/image-\(assets.count + 1).\(asset.format.fileExtension)"
            assets.append(asset)
            imagePaths.append(path)
            imagePathByID[asset.id] = path
        case let .block(block):
            precondition(started, "blocks follow the document's start")
            switch block.content {
            case let .sourcePage(number):
                // Inside a list the boundary is held with the list, unless it opens a chapter,
                // which closes the list first: a validated chapter start always begins a new
                // spine document, and the list is written whole into the one before it.
                if openList != nil, !chapterStartPages.contains(number) {
                    if let held = heldPage { openList!.entries[openList!.entries.count - 1].pagesAfter.append(held) }
                    heldPage = number
                } else {
                    try flushList()
                    try add(sourcePage: number)
                }
            case let .listItem(item):
                ArabicText.countLetters(block.text, rightToLeft: &rightToLeftLetters, latin: &latinLetters)
                if var open = openList,
                   (item.level > 0 || (!item.opensList && open.kind == item.kind)) {
                    open.entries.append(.init(block: block, item: item, pagesBefore: heldPage.map { [$0] } ?? []))
                    openList = open
                    heldPage = nil
                } else {
                    try flushList()
                    openList = OpenList(kind: item.kind, start: item.ordinal, entries: [.init(block: block, item: item)])
                }
            default:
                try flushList()
                // A marker inside a continued paragraph shows the number its page prints, exactly
                // as a standalone one does: it is the same marker, and a reader jumping to it is
                // looking for the same printed page (#248, surfaced by #203's cross-page joins).
                if case .image = block.content {} else {
                    ArabicText.countLetters(block.text, rightToLeft: &rightToLeftLetters, latin: &latinLetters)
                }
                try write(try packer.add(EPUBTextEncoder.piece(for: block, imagePaths: imagePathByID,
                                                              labels: pageLabels),
                                         budgetRemaining: maximumOutputBytes - consumed))
            }
        }
    }

    private func add(sourcePage number: Int) throws {
        try write(try packer.add(sourcePage: number,
                                 markup: EPUBTextEncoder.sourcePage(number, labels: pageLabels),
                                 budgetRemaining: maximumOutputBytes - consumed))
    }

    /// Writes the open list, if any, as one piece, and hands the packer a boundary that arrived
    /// inside it and precedes no item, so that it travels with whatever follows the list.
    private func flushList() throws {
        if let open = openList {
            openList = nil
            try write(try packer.add(EPUBTextEncoder.list(open.kind, start: open.start, entries: open.entries,
                                                          imagePaths: imagePathByID, labels: pageLabels),
                                     budgetRemaining: maximumOutputBytes - consumed))
        }
        if let held = heldPage {
            heldPage = nil
            try add(sourcePage: held)
        }
    }

    /// Finishes navigation, package metadata and the archive, and returns the archive's URL.
    /// The reported fraction covers the archive entries; serializing the blocks is the
    /// producer's own work and is reported there.
    func finish(progress: @Sendable (Double) async -> Void) async throws -> URL {
        try validation.finish()
        try flushList()
        try write(try packer.finish(budgetRemaining: maximumOutputBytes - consumed))
        let chapters = packer.documentNames
        // An outline entry names a page, and which spine document holds a page is only known
        // once every document has closed — which is now. `packer.pages` is that map (#249).
        var pageFiles: [Int: String] = [:]
        for entry in packer.pages where entry.fragment.hasPrefix("page-") {
            pageFiles[Int(entry.fragment.dropFirst(5)) ?? 0] = entry.file
        }
        try resolvePageLinks(pageFiles: pageFiles)
        try resolveNoteLinks()
        // The author's own contents is the navigation where the document states a usable one;
        // the detected headings are the navigation everywhere else. Headings keep their ids
        // either way, so nothing in the text stops being addressable.
        var toc = Self.markup(outline, pageFiles: pageFiles)
        if toc.isEmpty { toc = packer.toc.map(\.markup) }
        if toc.isEmpty { toc = ["<li><a href=\"\(chapters[0])\">\(xml(title))</a></li>"] }
        let nav = """
        <nav epub:type="toc" id="toc"><h1>Contents</h1><ol>\(toc.joined())</ol></nav>
        <nav epub:type="page-list" hidden="hidden"><h2>Source pages</h2><ol>\(packer.pages.map(\.markup).joined())</ol></nav>
        """
        try writeText(document(nav, name: "Contents"), publication.appendingPathComponent("nav.xhtml"))
        try writeText("""
        body { margin: 1em; line-height: 1.5; overflow-wrap: break-word; }
        p { margin: 0 0 0.8em; } h1, h2 { break-after: avoid; }
        img { max-width: 100%; height: auto; } figure { margin: 1em 0; }
        figcaption { font-size: 0.85em; } pre { white-space: pre-wrap; overflow-wrap: anywhere; }
        .source-diagram { display: inline-block; position: relative; max-width: 100%; line-height: 0; }
        .source-diagram img { display: block; }
        .diagram-label { position: absolute; display: block; overflow: hidden; white-space: nowrap;
          color: transparent; -webkit-text-fill-color: transparent; user-select: text;
          font-size: 1rem; line-height: 1; }
        .diagram-label::selection { background: rgba(65, 115, 210, 0.35); }
        table { border-collapse: collapse; margin: 1em 0; }
        th, td { text-align: left; vertical-align: top; padding: 0.15em 0.6em 0.15em 0; }
        thead th { border-bottom: 1px solid currentColor; }
        """, publication.appendingPathComponent("style.css"))
        // Caller-supplied values make the archive byte-reproducible; defaults vary per run.
        let identifier = xml(packageIdentifier ?? "urn:uuid:" + UUID().uuidString)
        let modificationDate = self.modificationDate ?? Date()
        let modified = ISO8601DateFormatter().string(from: modificationDate)
        let author = self.author.map { "<dc:creator>\(xml($0))</dc:creator>" } ?? ""
        let summary = self.summary.map { "<dc:description>\(xml($0))</dc:description>" } ?? ""
        let subjects = keywords.map { "<dc:subject>\(xml($0))</dc:subject>" }.joined()
        // The source's creation date, which is when the file was made and not when the work was
        // published: the corpus's scans state 2010, 2013 and 2026 for works of 1977, 1964 and
        // 1955. `dc:date` means publication in EPUB 3, so this is `dcterms:created`, which claims
        // only what the document claims.
        let created = self.created.map {
            "<meta property=\"dcterms:created\">\(ISO8601DateFormatter().string(from: $0))</meta>"
        } ?? ""
        let manifest = chapters.enumerated().map {
            "<item id=\"c\($0.offset)\" href=\"\($0.element)\" media-type=\"application/xhtml+xml\""
                + (mathDocuments.contains($0.element) ? " properties=\"mathml\"/>" : "/>")
        }.joined() + imagePaths.enumerated().map {
            "<item id=\"img\($0.offset)\" href=\"\($0.element)\" media-type=\"\(assets[$0.offset].format.mediaType)\"/>"
        }.joined()
        let spine = chapters.indices.map { "<itemref idref=\"c\($0)\"/>" }.joined()
        let direction = rightToLeftLetters > 0 && rightToLeftLetters >= latinLetters
            ? " page-progression-direction=\"rtl\"" : ""
        try writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" prefix="rendition: http://www.idpf.org/vocab/rendition/#">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">\(identifier)</dc:identifier><dc:title>\(xml(title))</dc:title><dc:language>\(language)</dc:language>\(author)\(summary)\(subjects)\(created)<meta property="dcterms:modified">\(modified)</meta><meta property="rendition:layout">reflowable</meta></metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="style.css" media-type="text/css"/>\(manifest)</manifest><spine\(direction)>\(spine)</spine></package>
        """, publication.appendingPathComponent("package.opf"))
        try writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """, directory.appendingPathComponent("META-INF/container.xml"))
        try writeText("application/epub+zip", directory.appendingPathComponent("mimetype"))
        let paths = ["mimetype", "META-INF/container.xml", "EPUB/package.opf", "EPUB/nav.xhtml", "EPUB/style.css"]
            + chapters.map { "EPUB/" + $0 }
        let entries = paths.map { (path: $0, url: directory.appendingPathComponent($0)) }
            + zip(imagePaths, assets).map { (path: "EPUB/" + $0.0, url: $0.1.fileURL) }
        await progress(0)
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
            await progress(ProgressBudget.writer(archivedEntries: i + 1, of: entries.count))
        }
        return archiveURL
    }

    /// Outline entries as EPUB navigation list items, nested as the author nested them. An entry
    /// whose page did not resolve groups its children in a `span`, and one with neither a
    /// resolved page nor children is left out, because a list item must name something.
    private static func markup(_ entries: [OutlineEntry], pageFiles: [Int: String]) -> [String] {
        var items: [String] = []
        for entry in entries {
            let nested = markup(entry.children, pageFiles: pageFiles)
            let list = nested.isEmpty ? "" : "<ol>\(nested.joined())</ol>"
            if let page = entry.page, let file = pageFiles[page] {
                items.append("<li><a href=\"\(file)#page-\(page)\">\(xml(entry.title))</a>\(list)</li>")
            } else if !list.isEmpty {
                items.append("<li><span>\(xml(entry.title))</span>\(list)</li>")
            }
        }
        return items
    }

    private func document(_ body: String, name: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(language)" lang="\(language)">
        <head><title>\(xml(name))</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>\(body)</body></html>
        """
    }

    private func writeText(_ string: String, _ url: URL) throws {
        try Task.checkCancellation()
        consumed += Int64(string.utf8.count)
        guard consumed <= maximumOutputBytes else { throw ConversionError.resourceLimit("EPUB text size") }
        try string.write(to: url, atomically: true, encoding: .utf8)
    }

    private func write(_ documents: [SpinePacker.Document]) throws {
        for spineDocument in documents {
            if spineDocument.body.contains(EPUBTextEncoder.pageLinkToken) {
                documentsWithPageLinks.append(spineDocument.name)
            }
            if spineDocument.body.contains("pdfreflow:note:") { documentsWithNoteLinks.append(spineDocument.name) }
            let notes = try NSRegularExpression(
                pattern: #"<aside epub:type="(?:endnote" role="note|footnote" role="doc-footnote)" id="([^"]+)""#)
            let body = spineDocument.body as NSString
            for match in notes.matches(in: spineDocument.body, range: NSRange(location: 0, length: body.length)) {
                noteFiles[body.substring(with: match.range(at: 1))] = spineDocument.name
            }
            if spineDocument.body.contains("<math ") { mathDocuments.insert(spineDocument.name) }
            try writeText(document(spineDocument.body, name: title), publication.appendingPathComponent(spineDocument.name))
        }
    }

    /// Resolve against emitted entries, not extraction candidates: a later image fallback
    /// can remove an entry. In that case keep the reference's text without a dangling link.
    private func resolveNoteLinks() throws {
        let links = try NSRegularExpression(
            pattern: #"<a epub:type="noteref" role="doc-noteref" href="pdfreflow:note:([^":]+):-*">(.*?)</a>"#,
            options: [.dotMatchesLineSeparators])
        for name in documentsWithNoteLinks {
            try Task.checkCancellation()
            let url = publication.appendingPathComponent(name)
            let text = try String(contentsOf: url, encoding: .utf8)
            let original = text as NSString
            let result = NSMutableString(string: text)
            for match in links.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
                let id = original.substring(with: match.range(at: 1))
                let content = original.substring(with: match.range(at: 2))
                let replacement = noteFiles[id].map {
                    "<a epub:type=\"noteref\" role=\"doc-noteref\" href=\"\($0)#\(id)\">\(content)</a>"
                } ?? content
                result.replaceCharacters(in: match.range, with: replacement)
            }
            let resolved = result as String
            consumed += Int64(resolved.utf8.count) - Int64(text.utf8.count)
            guard consumed <= maximumOutputBytes else { throw ConversionError.resourceLimit("EPUB text size") }
            try resolved.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Rewrites the page tokens an internal link carries into the file that holds its page (#247).
    ///
    /// A link on page 12 can name page 400, whose spine document does not exist when the link is
    /// serialized; `SpinePacker.pages` knows which document holds which page only once the last
    /// one has closed. Only the documents that actually hold a token are read back, so a book
    /// without internal links is written exactly as it was before. A page the map does not name —
    /// which no conversion has produced, since every page emits a marker — resolves to the
    /// document the link is in, so a published book never carries an href that resolves to
    /// nothing.
    private func resolvePageLinks(pageFiles: [Int: String]) throws {
        for name in documentsWithPageLinks {
            try Task.checkCancellation()
            let url = publication.appendingPathComponent(name)
            let text = try String(contentsOf: url, encoding: .utf8)
            var resolved = ""
            var rest = Substring(text)
            while let token = rest.range(of: EPUBTextEncoder.pageLinkToken) {
                resolved += rest[..<token.lowerBound]
                let digits = rest[token.upperBound...].prefix(while: \.isNumber)
                let page = Int(digits) ?? 0
                // The token is padded to a fixed width so that resolving it can only shorten the
                // body the packer already measured; the padding goes with it.
                let padding = rest[token.upperBound...].dropFirst(digits.count).prefix(while: { $0 == "-" })
                resolved += pageFiles[page].map { "\($0)#page-\(page)" } ?? name
                rest = rest[token.upperBound...].dropFirst(digits.count + padding.count)
            }
            resolved += rest
            guard resolved != text else { continue }
            consumed += Int64(resolved.utf8.count) - Int64(text.utf8.count)
            guard consumed <= maximumOutputBytes else { throw ConversionError.resourceLimit("EPUB text size") }
            try resolved.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
