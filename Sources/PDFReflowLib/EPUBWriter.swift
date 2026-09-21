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
    private var packer = SpinePacker(bodyTargetBytes: EPUBWriter.bodyTargetBytes, chapterStartPages: [])
    private var validation = ReflowDocument.Validation()
    /// Assets in arrival order: the archive names them by that order and packages their bytes.
    private var assets: [ReflowDocument.Asset] = []
    private var imagePaths: [String] = []
    private var imagePathByID: [String: String] = [:]
    private var consumed: Int64 = 0
    private var started = false

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
            packer = SpinePacker(bodyTargetBytes: Self.bodyTargetBytes, chapterStartPages: chapterStartPages)
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
            if case let .sourcePage(number) = block.content {
                try write(try packer.add(sourcePage: number, markup: EPUBTextEncoder.sourcePage(number),
                                         budgetRemaining: maximumOutputBytes - consumed))
            } else {
                try write(try packer.add(EPUBTextEncoder.piece(for: block, imagePaths: imagePathByID),
                                         budgetRemaining: maximumOutputBytes - consumed))
            }
        }
    }

    /// Finishes navigation, package metadata and the archive, and returns the archive's URL.
    /// The reported fraction covers the archive entries; serializing the blocks is the
    /// producer's own work and is reported there.
    func finish(progress: @Sendable (Double) async -> Void) async throws -> URL {
        try validation.finish()
        try write(try packer.finish(budgetRemaining: maximumOutputBytes - consumed))
        let chapters = packer.documentNames
        var toc = packer.toc.map(\.markup)
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
            "<item id=\"c\($0.offset)\" href=\"\($0.element)\" media-type=\"application/xhtml+xml\"/>"
        }.joined() + imagePaths.enumerated().map {
            "<item id=\"img\($0.offset)\" href=\"\($0.element)\" media-type=\"\(assets[$0.offset].format.mediaType)\"/>"
        }.joined()
        let spine = chapters.indices.map { "<itemref idref=\"c\($0)\"/>" }.joined()
        try writeText("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" prefix="rendition: http://www.idpf.org/vocab/rendition/#">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">\(identifier)</dc:identifier><dc:title>\(xml(title))</dc:title><dc:language>\(language)</dc:language>\(author)\(summary)\(subjects)\(created)<meta property="dcterms:modified">\(modified)</meta><meta property="rendition:layout">reflowable</meta></metadata>
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
            try writeText(document(spineDocument.body, name: title), publication.appendingPathComponent(spineDocument.name))
        }
    }
}
