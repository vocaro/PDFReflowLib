import Foundation
import PDFKit
import Testing
import ZIPFoundation
import CryptoKit
@testable import PDFReflowLib

private func fixture(_ name: String) -> URL {
    fixtureURL(name + ".pdf")
}

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func entry(_ path: String, in url: URL) throws -> Data {
    try Archive(url: url, accessMode: .read).entryData(path)
}

private func chapter(_ url: URL) throws -> String {
    String(decoding: try entry("EPUB/chapter-1.xhtml", in: url), as: UTF8.self)
}

@Test func proseReflowsAndHealsOnlySupportedHyphens() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    let report = try await PDFConverter().convert(from: fixture("prose"), to: output)
    let html = try chapter(output)
    #expect(html.contains("ordinary hard-wrapped lines that belong together"))
    #expect(html.contains("reliable conversion without"))
    #expect(html.contains("remains well-known"))
    #expect(!html.contains("PDF REFLOW TEST BOOK"))
    #expect(report.pageCount == 3)
    #expect(report.reflowedPageCount == 3)
    #expect(report.imageCount == 0)
    #expect(html.contains("page-2"))
    #expect(html.contains("without <span"))
    #expect(html.contains("/>losing the original sentence"))
}

@Test func columnOrderIsNotInterleaved() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    _ = try await PDFConverter().convert(from: fixture("columns"), to: output)
    let text = try chapter(output)
    let leftEnd = try #require(text.range(of: "LEFT LAST"))
    let rightStart = try #require(text.range(of: "RIGHT FIRST"))
    #expect(leftEnd.lowerBound < rightStart.lowerBound)
    #expect(text.contains("Two Columns, One Reading Order"))
}

@Test func rasterVectorAndTableRegionsSurvive() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    let report = try await PDFConverter().convert(from: fixture("graphics"), to: output)
    let html = try chapter(output)
    #expect(report.imageCount == 3)
    #expect(report.reflowedPageCount == 1)
    #expect(html.contains("Text before the illustrated region"))
    #expect(html.contains("Text after the table"))
    #expect(!html.contains("<p>12"))
    #expect(!html.contains("<p>E = mc"))
    #expect(html.contains("A displayed formula keeps its superscript placement."))
    for i in 1...report.imageCount {
        let png = try entry("EPUB/images/image-\(i).png", in: output)
        #expect(png.starts(with: [137, 80, 78, 71]))
    }
}

@Test func sourceMarkupIsEscapedAndCodeBreaksRemain() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    var options = ConversionOptions()
    options.title = "Unsafe <title> & text"
    _ = try await PDFConverter().convert(from: fixture("lists-code"), to: output, options: options)
    let html = try chapter(output)
    #expect(html.contains("&lt;script&gt;"))
    #expect(!html.contains("<script>"))
    #expect(html.contains("<pre>if value &lt; 3:\n    print(value)\nreturn value</pre>"))
    #expect(html.contains("1. Keep the first item."))
    #expect(html.contains("2. Keep the second item."))
    #expect(html.contains("<strong>bold</strong>"))
    #expect(html.contains("<em>italic</em>"))
}

@Test func packageHasEPUB3NavigationAndUncompressedMimetype() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    _ = try await PDFConverter().convert(from: fixture("prose"), to: output)
    let bytes = try Data(contentsOf: output)
    #expect(Array(bytes[8..<10]) == [0, 0]) // First ZIP local entry's compression method.
    #expect(String(decoding: bytes[30..<38], as: UTF8.self) == "mimetype")
    #expect(try entry("mimetype", in: output) == Data("application/epub+zip".utf8))
    let opf = String(decoding: try entry("EPUB/package.opf", in: output), as: UTF8.self)
    #expect(opf.contains("version=\"3.0\""))
    #expect(opf.contains("rendition:layout\">reflowable"))
    let nav = String(decoding: try entry("EPUB/nav.xhtml", in: output), as: UTF8.self)
    #expect(nav.contains("epub:type=\"toc\""))
    #expect(nav.contains("epub:type=\"page-list\""))
    #expect(nav.contains("#page-3"))
}

@Test func progressIsMonotonicAndEndsAfterPublication() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    let log = ProgressLog()
    _ = try await PDFConverter().convert(from: fixture("prose"), to: output) { event in
        await log.append(event)
        if event.stage == .completed { #expect(FileManager.default.fileExists(atPath: output.path)) }
    }
    let events = await log.events
    #expect(events.first?.fractionCompleted == 0)
    #expect(events.last?.fractionCompleted == 1)
    #expect(zip(events, events.dropFirst()).allSatisfy { $0.fractionCompleted <= $1.fractionCompleted })
}

/// MS-DOS (time, date) fields of every central-directory record and its local header, read
/// from raw bytes so the check does not depend on ZIPFoundation's decoding or the local time zone.
private func zipEntryDateFields(_ data: Data) throws -> [(time: UInt16, date: UInt16)] {
    let bytes = [UInt8](data)
    func u16(_ at: Int) -> UInt16 { UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int {
        let low = Int(u16(at)), high = Int(u16(at + 2))
        return low | high << 16
    }
    let end = bytes.count - 22 // End-of-central-directory record; the writer adds no comment.
    try #require(u32(end) == 0x06054b50)
    var record = u32(end + 16), fields: [(time: UInt16, date: UInt16)] = []
    for _ in 0..<Int(u16(end + 10)) {
        try #require(u32(record) == 0x02014b50)
        let local = u32(record + 42)
        try #require(u32(local) == 0x04034b50)
        fields.append((u16(record + 12), u16(record + 14)))
        fields.append((u16(local + 10), u16(local + 12)))
        record += 46 + Int(u16(record + 28)) + Int(u16(record + 30)) + Int(u16(record + 32))
    }
    return fields
}

@Test func suppliedIdentifierAndDateMakeTheEPUBByteReproducible() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    var options = ConversionOptions(); options.referenceImages = .always
    options.packageIdentifier = "urn:isbn:9780000000002 & <pinned>"
    // A non-UTC offset: output must be the same instant in UTC whatever the host's time zone.
    options.modificationDate = ISO8601DateFormatter().date(from: "2026-01-02T12:04:05+09:00")
    var archives: [Data] = []
    for run in 1...2 {
        let output = dir.appendingPathComponent("book-\(run).epub")
        _ = try await PDFConverter().convert(from: fixture("graphics"), to: output, options: options)
        archives.append(try Data(contentsOf: output))
    }
    #expect(SHA256.hash(data: archives[0]) == SHA256.hash(data: archives[1]))
    let opf = String(decoding: try entry("EPUB/package.opf", in: dir.appendingPathComponent("book-1.epub")), as: UTF8.self)
    #expect(opf.contains("<dc:identifier id=\"book-id\">urn:isbn:9780000000002 &amp; &lt;pinned&gt;</dc:identifier>"))
    #expect(opf.contains("<meta property=\"dcterms:modified\">2026-01-02T03:04:05Z</meta>"))
    // Pinned header values, not "now": 03:04:04 UTC (two-second resolution) on 2026-01-02.
    // Two runs need not straddle a clock tick, because a wall-clock date could never match these.
    let dosTime: UInt16 = 0x1882 // hour << 11 | minute << 5 | second / 2
    let dosDate: UInt16 = 0x5C22 // (year - 1980) << 9 | month << 5 | day
    let fields = try zipEntryDateFields(archives[0])
    let entryCount = Array(try Archive(data: archives[0], accessMode: .read)).count
    #expect(entryCount > 5 && fields.count == 2 * entryCount)
    #expect(fields.allSatisfy { $0.time == dosTime && $0.date == dosDate })
}

@Test func defaultPackagesReceiveDistinctIdentifiers() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    var identifiers: Set<String> = []
    for run in 1...2 {
        let output = dir.appendingPathComponent("book-\(run).epub")
        _ = try await PDFConverter().convert(from: fixture("prose"), to: output)
        let opf = String(decoding: try entry("EPUB/package.opf", in: output), as: UTF8.self)
        let identifier = try #require(opf.firstMatch(of: /<dc:identifier id="book-id">(urn:uuid:[0-9A-F-]{36})</)?.1)
        identifiers.insert(String(identifier))
    }
    #expect(identifiers.count == 2)
}

@Test func invalidReproducibilityOptionsAreRejected() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    var blank = ConversionOptions(); blank.packageIdentifier = " \n"
    var control = ConversionOptions(); control.packageIdentifier = "id\u{0}"
    var early = ConversionOptions(); early.modificationDate = Date(timeIntervalSince1970: 0)
    for options in [blank, control, early] {
        await #expect(throws: ConversionError.self) {
            try await PDFConverter().convert(from: fixture("prose"), to: dir.appendingPathComponent("book.epub"),
                                             options: options)
        }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}

@Test func existingDestinationAndResourceLimitsAreSafe() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    try Data("keep me".utf8).write(to: output)
    await #expect(throws: ConversionError.self) {
        try await PDFConverter().convert(from: fixture("prose"), to: output)
    }
    #expect(try Data(contentsOf: output) == Data("keep me".utf8))
    var options = ConversionOptions(); options.maximumPages = 1
    let other = dir.appendingPathComponent("other.epub")
    await #expect(throws: ConversionError.self) {
        try await PDFConverter().convert(from: fixture("prose"), to: other, options: options)
    }
    #expect(!FileManager.default.fileExists(atPath: other.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["book.epub"])
}

@Test func cancellationCleansStagingAndNeverPublishes() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    let task = Task {
        try await PDFConverter().convert(from: fixture("prose"), to: output) { event in
            if event.stage == .extracting { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}

@Test func rotatedAndOCRDisabledPagesAreExplicitImageFallbacks() async throws {
    for name in ["rotated", "scanned"] {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        var options = ConversionOptions(); options.ocr = .never
        let report = try await PDFConverter().convert(from: fixture(name),
            to: dir.appendingPathComponent("book.epub"), options: options)
        #expect(report.reflowedPageCount == 0)
        #expect(report.imageCount == 1)
        #expect(report.warnings.contains { $0.code == .pageImageFallback })
    }
}

@Test func scannedTextUsesRealVision() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    let report = try await PDFConverter().convert(from: fixture("scanned"), to: output)
    #expect(report.recognizedPageCount == 1)
    #expect(report.reflowedPageCount == 1)
    #expect(report.imageCount == 1)
    #expect(try chapter(output).contains("clear scanned paragraph"))
    #expect(report.warnings.contains { $0.code == .ocrUsed })
}

@Test func fixtureIdentitiesMatchTheirManifest() throws {
    struct Manifest: Decodable {
        struct Item: Decodable { let file: String; let bytes: Int; let sha256: String }
        let fixtures: [Item]
    }
    let directory = Bundle.module.resourceURL!.appendingPathComponent("fixtures")
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    #expect(manifest.fixtures.count == 6)
    for item in manifest.fixtures {
        let data = try Data(contentsOf: directory.appendingPathComponent(item.file))
        #expect(data.count == item.bytes)
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == item.sha256)
    }
}

@Test func failedWritingAndMalformedInputsLeaveNoPartialOutput() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    var options = ConversionOptions(); options.maximumOutputBytes = 32
    await #expect(throws: ConversionError.self) {
        try await PDFConverter().convert(from: fixture("graphics"), to: output, options: options)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    let bad = dir.appendingPathComponent("broken.pdf")
    try Data("not a PDF".utf8).write(to: bad)
    await #expect(throws: ConversionError.self) {
        try await PDFConverter().convert(from: bad, to: output)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["broken.pdf"])
}

@Test func cancellationDuringPackagingDoesNotPublish() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("book.epub")
    let task = Task {
        try await PDFConverter().convert(from: fixture("graphics"), to: output) { event in
            if event.stage == .writing { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}

@Test func chapterSplittingPreservesNavigationTargets() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("EPUB/images"), withIntermediateDirectories: true)
    let blocks = [
        ReflowBlock(content: .paragraph(InlineText(String(repeating: "word ", count: 13_000))), page: 1),
        ReflowBlock(content: .heading(id: "later", text: InlineText("Later chapter")), page: 2),
    ]
    let book = ReflowDocument(metadata: .init(title: "Large book", language: "en"), blocks: blocks, assets: [])
    let output = try await EPUBWriter.write(book, maximumOutputBytes: ConversionOptions().maximumOutputBytes,
        directory: dir, progress: { _ in })
    let nav = String(decoding: try entry("EPUB/nav.xhtml", in: output), as: UTF8.self)
    #expect(nav.contains("chapter-2.xhtml#later"))
    #expect(try entry("EPUB/chapter-2.xhtml", in: output).count > 0)
}

@Test func encryptedInputReportsTheUnlockRequirement() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let document = try #require(PDFDocument(url: fixture("prose")))
    let source = dir.appendingPathComponent("locked.pdf")
    #expect(document.write(to: source, withOptions: [.ownerPasswordOption: "test-owner", .userPasswordOption: "test-reader"]))
    do {
        _ = try await PDFConverter().convert(from: source, to: dir.appendingPathComponent("book.epub"))
        Issue.record("Encrypted input should require an unlocked source")
    } catch ConversionError.encryptedPDF {
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["locked.pdf"])
    }
}

@Test func extremeRasterAspectRatioCannotExceedThePixelBudget() throws {
    let page = try #require(PDFDocument(url: fixture("prose"))?.page(at: 0))
    var options = ConversionOptions(); options.maximumRasterPixels = 1
    #expect(throws: ConversionError.self) {
        try PageRasterizer.image(page: page, rect: CGRect(x: 0, y: 0, width: 0.001, height: 100_000), options: options)
    }
}

private final class WeakDocument {
    weak var value: PDFDocument?
    init(_ value: PDFDocument?) { self.value = value }
}

@Test func parsedPDFDocumentsAreReleasedAcrossPageWindows() throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let document = try #require(PDFDocument(url: fixture("prose")))
    for _ in 0..<9 {
        let page = try #require(document.page(at: 0)?.copy() as? PDFPage)
        document.insert(page, at: document.pageCount)
    }
    let url = dir.appendingPathComponent("many-pages.pdf")
    #expect(document.write(to: url))
    let source = try PDFPageSource(url: url)
    let (first, retainedLines) = try autoreleasepool {
        let page = try source.page(at: 0)
        return (WeakDocument(page.document), try NativeTextReader.lines(on: page, limit: 100_000))
    }
    #expect(first.value != nil)
    let second = try autoreleasepool { WeakDocument(try source.page(at: 8).document) }
    #expect(first.value == nil)
    #expect(retainedLines.contains { $0.text.contains("A Small Book of Conversion") })
    #expect(second.value != nil)
    source.releaseCachedPages()
    #expect(second.value == nil)
    #expect(try source.page(at: 0).string?.contains("A Small Book of Conversion") == true)
}

@Test func independentConcurrentConversionsKeepOutputProgressAndCancellationSeparate() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let names = ["prose", "columns", "lists-code", "graphics"]
    let markers = ["reliable conversion", "LEFT FIRST", "print(value)", "Text after the table"]
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in names.indices {
            group.addTask {
                let output = dir.appendingPathComponent("book-\(index).epub")
                let log = ProgressLog()
                var options = ConversionOptions()
                options.title = "Independent publication \(index)"
                let report = try await PDFConverter().convert(from: fixture(names[index]), to: output, options: options) { event in
                    await log.append(event)
                    await Task.yield()
                    if event.stage == .completed { #expect(FileManager.default.fileExists(atPath: output.path)) }
                }
                let html = try chapter(output)
                #expect(html.contains(markers[index]))
                for other in names.indices where other != index { #expect(!html.contains(markers[other])) }
                let opf = String(decoding: try entry("EPUB/package.opf", in: output), as: UTF8.self)
                #expect(opf.contains("Independent publication \(index)"))
                #expect(report.outputURL == output)
                let events = await log.events
                #expect(events.first?.fractionCompleted == 0)
                #expect(events.last?.stage == .completed && events.last?.fractionCompleted == 1)
                #expect(zip(events, events.dropFirst()).allSatisfy { $0.fractionCompleted <= $1.fractionCompleted })
                if names[index] == "lists-code" {
                    #expect(html.contains("<strong>bold</strong>") && html.contains("<em>italic</em>"))
                }
                if names[index] == "graphics" { #expect(report.imageCount == 3) }
            }
        }
        group.addTask {
            let log = ProgressLog()
            await #expect(throws: CancellationError.self) {
                try await PDFConverter().convert(from: fixture("prose"), to: dir.appendingPathComponent("canceled.epub")) { event in
                    await log.append(event)
                    if event.stage == .extracting { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            #expect(await log.events.allSatisfy { $0.stage != .completed })
        }
        try await group.waitForAll()
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        == names.indices.map { "book-\($0).epub" })
}
