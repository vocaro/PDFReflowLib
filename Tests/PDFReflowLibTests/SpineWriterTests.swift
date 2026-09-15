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
    #expect(values.first == 0)
    #expect(values.last == 1)
    #expect(values == values.sorted())
    #expect(values.allSatisfy { (0...1).contains($0) })
    let cancelled = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: cancelled) }
    let task = Task {
        try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: cancelled) { fraction in
            if fraction > 0 && fraction < 0.5 { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: cancelled.appendingPathComponent("publication.epub").path))
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
