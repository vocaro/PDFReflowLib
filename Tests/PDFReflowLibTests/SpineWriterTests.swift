import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func spineBook(_ blocks: [ReflowBlock]) -> ReflowDocument {
    ReflowDocument(metadata: .init(title: "Spine test <&>", language: "en"), blocks: blocks, assets: [])
}

private func paragraph(_ text: String) -> ReflowBlock {
    .init(content: .paragraph(InlineText(text)), page: 1)
}

private func writtenChapters(_ book: ReflowDocument, directory: URL) async throws -> [String] {
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: directory, progress: { _ in })
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("EPUB").path)
        .filter { $0.hasPrefix("chapter-") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return try names.map { try String(contentsOf: directory.appendingPathComponent("EPUB/" + $0), encoding: .utf8) }
}

private func body(_ chapter: String) -> String {
    String(chapter.components(separatedBy: "<body>")[1].components(separatedBy: "</body>")[0])
}

@Test func spinePackingAccountsForMarkupBeforeCrossingTarget() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = spineBook([paragraph(String(repeating: "a", count: 29_992)),
                          paragraph(String(repeating: "b", count: 29_992)), paragraph("last")])
    let chapters = try await writtenChapters(book, directory: dir)
    try #require(chapters.count == 2)
    #expect(body(chapters[0]).utf8.count == 60_000)
    #expect(body(chapters[1]) == "<p>last</p>\n")
}

@Test func manyTinyParagraphsStillRespectSerializedSizeTarget() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let chapters = try await writtenChapters(spineBook(Array(repeating: paragraph("x"), count: 8_000)), directory: dir)
    try #require(chapters.count == 2)
    #expect(chapters.allSatisfy { body($0).utf8.count <= 60_000 })
    #expect(chapters.map(body).joined().components(separatedBy: "<p>x</p>").count - 1 == 8_000)
}

@Test func oversizedAtomicBlockGetsItsOwnDocumentWithoutTextLoss() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let value = String(repeating: "é & 👨‍👩‍👧‍👦 ", count: 3_000)
    let book = spineBook([paragraph("before"), paragraph(value), paragraph("after")])
    let chapters = try await writtenChapters(book, directory: dir)
    #expect(chapters.count == 3)
    #expect(chapters.map(body) == ["<p>before</p>\n", "<p>\(xml(value))</p>\n", "<p>after</p>\n"])
}

@Test func pageAndHeadingNavigationFollowContentAcrossSpineSplits() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let marker = ReflowBlock(content: .sourcePage(2), page: 2)
    let heading = ReflowBlock(content: .heading(id: "section-two", text: InlineText("Later section")), page: 2)
    let styled = InlineText(elements: [.text("conver", .bold), .sourcePage(3), .text("sion", [.italic, .superscript])])
    let book = spineBook([.init(content: .sourcePage(1), page: 1), paragraph(String(repeating: "x", count: 59_830)),
                          marker, heading, .init(content: .paragraph(styled), page: 2)])
    let saved = book
    let chapters = try await writtenChapters(book, directory: dir)
    try #require(chapters.count == 2)
    #expect(!chapters[0].contains("id=\"page-2\""))
    #expect(chapters[1].contains("id=\"page-2\""))
    #expect(chapters[1].contains("id=\"section-two\""))
    #expect(chapters[1].contains(EPUBTextEncoder.inline(styled)))
    let nav = try String(contentsOf: dir.appendingPathComponent("EPUB/nav.xhtml"), encoding: .utf8)
    for id in ["page-2", "page-3", "section-two"] {
        #expect(nav.contains("chapter-2.xhtml#\(id)"))
    }
    #expect(book == saved)
}

@Test func trailingEmptyPageMarkersSurviveExactlyOnce() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = spineBook([paragraph("body")] + (1...3).map { .init(content: .sourcePage($0), page: $0) })
    let chapters = try await writtenChapters(book, directory: dir)
    for number in 1...3 {
        #expect(chapters.joined().components(separatedBy: "id=\"page-\(number)\"").count - 1 == 1)
    }
}

/// The handoff itself: a document the writer consumed part by part, as the converter now feeds
/// it, must package to the same bytes as the same document collected whole and written after.
@Test func streamedReconstructionPackagesTheSameArchiveAsACollectedDocument() async throws {
    var options = ConversionOptions()
    options.packageIdentifier = "urn:uuid:identity"
    options.modificationDate = Date(timeIntervalSince1970: 1_767_225_600)
    options.referenceImages = .always
    func archive(streamed: Bool) async throws -> Data {
        let workspace = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: workspace) }
        let source = fixtureURL("graphics.pdf")
        let url: URL
        if streamed {
            let writer = EPUBWriter(maximumOutputBytes: options.maximumOutputBytes, directory: workspace,
                packageIdentifier: options.packageIdentifier, modificationDate: options.modificationDate)
            _ = try await PDFReflowLibPipeline.reconstruct(from: source, options: options, workspace: workspace,
                emit: { try await writer.receive($0) }, progress: { _ in })
            url = try await writer.finish(progress: { _ in })
        } else {
            let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
                workspace: workspace, progress: { _ in })
            url = try await EPUBWriter.write(result.book, maximumOutputBytes: options.maximumOutputBytes,
                directory: workspace, packageIdentifier: options.packageIdentifier,
                modificationDate: options.modificationDate, progress: { _ in })
        }
        return try Data(contentsOf: url)
    }
    let streamed = try await archive(streamed: true)
    #expect(streamed.count > 0)
    #expect(streamed == (try await archive(streamed: false)))
}

private actor SpineProgress {
    var values: [Double] = []
    func add(_ value: Double) { values.append(value) }
}

@Test func spineWritingReportsOrderedProgressAndCanCancelBeforeArchive() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = spineBook((1...20).map { paragraph(String(repeating: "body \($0) ", count: 4_000)) })
    let log = SpineProgress()
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: dir, progress: { await log.add($0) })
    let values = await log.values
    // The writer's own fraction is the archive; the blocks were serialized as they arrived, and
    // the producer reports that work.
    #expect(values.first == 0)
    #expect(values.last == 1)
    #expect(values == values.sorted())
    #expect(values.allSatisfy { (0...1).contains($0) })
    let canceled = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: canceled) }
    let task = Task {
        try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: canceled) { fraction in
            if fraction == 0 { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: canceled.appendingPathComponent("publication.epub").path))
}

@Test func streamedBlocksStopAtCancellationBeforeAnythingIsPackaged() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = spineBook((1...20).map { paragraph(String(repeating: "body \($0) ", count: 4_000)) })
    let task = Task {
        let writer = EPUBWriter(maximumOutputBytes: 10_000_000, directory: dir)
        try await writer.receive(.start(book.metadata, chapterStartPages: []))
        for (index, block) in book.blocks.enumerated() {
            if index == 5 { withUnsafeCurrentTask { $0?.cancel() } }
            try await writer.receive(.block(block))
        }
        return try await writer.finish(progress: { _ in })
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("publication.epub").path))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("EPUB/nav.xhtml").path))
}

@Test func headingLevelsSurviveSerializationAndInvalidLevelsAreRejected() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = spineBook((1...6).map { .init(content: .heading(id: "h\($0)", text: InlineText("Title & \($0)", style: .italic), level: $0), page: 1) })
    let chapters = try await writtenChapters(book, directory: dir)
    for level in 1...6 {
        #expect(chapters.joined().contains("<h\(level) id=\"h\(level)\"><em>Title &amp; \(level)</em></h\(level)>"))
    }
    for level in [0, 7, Int.max] {
        let invalid = spineBook([.init(content: .heading(id: "bad", text: InlineText("bad"), level: level), page: 1)])
        #expect(throws: ReflowDocument.ValidationError.invalidHeadingLevel(level)) { try invalid.validate() }
    }
}

@Test func validatedChaptersStartNewSpineDocumentsAndKeepSizeSubdivisions() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let blocks: [ReflowBlock] = [.init(content: .sourcePage(1), page: 1), paragraph("front matter"),
        .init(content: .sourcePage(2), page: 2),
        .init(content: .heading(id: "chapter-one", text: InlineText("Chapter 1")), page: 2),
        paragraph(String(repeating: "x", count: 59_800)), paragraph(String(repeating: "y", count: 30_000)),
        .init(content: .sourcePage(3), page: 3),
        .init(content: .heading(id: "chapter-two", text: InlineText("Chapter 2")), page: 3), paragraph("last")]
    var book = spineBook(blocks)
    book.chapterStartPages = [2, 3]
    let chapters = try await writtenChapters(book, directory: dir)
    try #require(chapters.count == 4)
    #expect(body(chapters[0]).contains("front matter"))
    #expect(body(chapters[1]).hasPrefix(EPUBTextEncoder.sourcePage(2)))
    #expect(body(chapters[2]).hasPrefix("<p>yyy"))
    #expect(body(chapters[3]).hasPrefix(EPUBTextEncoder.sourcePage(3)))
    #expect(chapters.allSatisfy { body($0).utf8.count <= 60_000 })
    let nav = try String(contentsOf: dir.appendingPathComponent("EPUB/nav.xhtml"), encoding: .utf8)
    for id in ["page-2", "chapter-one"] { #expect(nav.contains("chapter-2.xhtml#\(id)")) }
    for id in ["page-3", "chapter-two"] { #expect(nav.contains("chapter-4.xhtml#\(id)")) }
    let control = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: control) }
    let ordinary = try await writtenChapters(spineBook(blocks), directory: control)
    #expect(chapters.map(body).joined() == ordinary.map(body).joined())
}

@Test func chapterStartAfterEmptyPagesAndExactSizeDoesNotEmitEmptyDocuments() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    var book = spineBook([paragraph(String(repeating: "x", count: 59_992)),
        .init(content: .sourcePage(1), page: 1), .init(content: .sourcePage(2), page: 2), paragraph("chapter")])
    book.chapterStartPages = [2]
    let chapters = try await writtenChapters(book, directory: dir)
    #expect(chapters.map(body) == ["<p>\(String(repeating: "x", count: 59_992))</p>\n",
                                  EPUBTextEncoder.sourcePage(1), EPUBTextEncoder.sourcePage(2) + "<p>chapter</p>\n"])
}

private func heading(_ id: String, _ text: String, page: Int = 2) -> ReflowBlock {
    .init(content: .heading(id: id, text: InlineText(text)), page: page)
}

@Test func sizeSplitCarriesTrailingHeadingAndItsNavigationIntoTheNextDocument() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    // The marker and heading fit under the target, but the section body does not.
    let book = spineBook([.init(content: .sourcePage(1), page: 1), paragraph(String(repeating: "x", count: 59_800)),
                          .init(content: .sourcePage(2), page: 2), heading("section", "Section"),
                          heading("subsection", "Subsection"), paragraph(String(repeating: "y", count: 400))])
    let chapters = try await writtenChapters(book, directory: dir)
    try #require(chapters.count == 2)
    #expect(body(chapters[0]) == EPUBTextEncoder.sourcePage(1) + "<p>\(String(repeating: "x", count: 59_800))</p>\n")
    #expect(body(chapters[1]).hasPrefix(EPUBTextEncoder.sourcePage(2) + "<h2 id=\"section\">Section</h2>\n<h2 id=\"subsection\">"))
    #expect(body(chapters[1]).hasSuffix("<p>\(String(repeating: "y", count: 400))</p>\n"))
    let nav = try String(contentsOf: dir.appendingPathComponent("EPUB/nav.xhtml"), encoding: .utf8)
    for id in ["page-2", "section", "subsection"] {
        #expect(nav.contains("chapter-2.xhtml#\(id)"))
        #expect(!nav.contains("chapter-1.xhtml#\(id)"))
    }
    #expect(nav.contains("chapter-1.xhtml#page-1"))
    // Navigation order is unchanged by moving entries between documents.
    let toc = try #require(nav.range(of: "Section")?.lowerBound)
    #expect(nav.range(of: "Subsection")!.lowerBound > toc)
}

@Test func headingThatFillsADocumentWaitsForItsContent() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    // The heading brings the serialized body to exactly the 60,000-byte target.
    let title = String(repeating: "h", count: 172)
    let book = spineBook([paragraph(String(repeating: "x", count: 59_800)), heading("full", title), paragraph("body")])
    #expect("<p>\(String(repeating: "x", count: 59_800))</p>\n<h2 id=\"full\">\(title)</h2>\n".utf8.count == 60_000)
    let chapters = try await writtenChapters(book, directory: dir)
    try #require(chapters.count == 2)
    #expect(body(chapters[0]) == "<p>\(String(repeating: "x", count: 59_800))</p>\n")
    #expect(body(chapters[1]) == "<h2 id=\"full\">\(title)</h2>\n<p>body</p>\n")
}

@Test func headingStaysWithAnOversizedBlockWithoutAnEmptyHeadingDocument() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let large = String(repeating: "z", count: 70_000)
    let book = spineBook([paragraph("intro"), heading("large", "Large section"), paragraph(large), paragraph("after")])
    let chapters = try await writtenChapters(book, directory: dir)
    #expect(chapters.map(body) == ["<p>intro</p>\n", "<h2 id=\"large\">Large section</h2>\n<p>\(large)</p>\n", "<p>after</p>\n"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func aBookTurnsItsPagesTheWayMostOfItsLettersRead() async throws {
    // The Hebrew Shakespeare's shape: its Hebrew verse is a short block to a line beside long
    // English paragraphs, so the right-to-left blocks are the more numerous while most of the
    // letters are English, in a book bound left to right. Joining its split note numbers into
    // their paragraphs took its blocks from 49.5% to 50.3% right to left and turned the spine.
    // The Arabic guide's shape is the other way round: long Arabic paragraphs and short English
    // labels.
    let english = String(repeating: "The translation keeps the sense of the verse beside it. ", count: 6)
    let arabic = String(repeating: "يقدم هذا الدليل معلومات مفيدة للمهاجرين الجدد في الولايات المتحدة. ", count: 6)
    for (blocks, rightToLeft) in [
        ([paragraph("וְהִנְנִי נִשְׁבַּע"), paragraph("כִּי יָדִי רַב לִי"), paragraph("וְלֹא קָטֹנְתִּי"),
          paragraph(english), paragraph(english)], false),
        ([paragraph(arabic), paragraph(arabic), paragraph("USCIS"), paragraph("Form I-551"), paragraph("Green Card")], true),
    ] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await writtenChapters(spineBook(blocks), directory: dir)
        let package = try String(contentsOf: dir.appendingPathComponent("EPUB/package.opf"), encoding: .utf8)
        #expect(package.contains("<spine page-progression-direction=\"rtl\">") == rightToLeft)
    }
}

@Test func longHeadingRunsStillRespectTheSizeTarget() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let headings = (1...2_000).map { heading("h\($0)", "Heading number \($0)") }
    let chapters = try await writtenChapters(spineBook(headings + [paragraph("end")]), directory: dir)
    #expect(chapters.count >= 2)
    #expect(chapters.allSatisfy { body($0).utf8.count <= 60_000 })
    #expect(chapters.map(body).joined().components(separatedBy: "<h2 ").count - 1 == 2_000)
}
