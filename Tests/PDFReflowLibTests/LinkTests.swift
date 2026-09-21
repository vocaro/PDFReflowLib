import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-links-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// A PDF of `pages` pages, each drawing `lines` lines, with `annotations` on the first page.
/// `%PAGE n%` inside an annotation is replaced by that page's object reference.
private func annotatedPDF(pages: Int, lines: Int, annotations: [String]) -> Data {
    func pageObject(_ page: Int) -> Int { 4 + (page - 1) * 2 }
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [\((1...pages).map { "\(pageObject($0)) 0 R" }.joined(separator: " ")) ] /Count \(pages) >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    let resolved = annotations.map { annotation in
        (1...pages).reduce(annotation) { $0.replacingOccurrences(of: "%PAGE \($1)%", with: "\(pageObject($1)) 0 R") }
    }
    for page in 1...pages {
        let annots = page == 1 && !resolved.isEmpty
            ? " /Annots [\(resolved.indices.map { "\(4 + pages * 2 + $0) 0 R" }.joined(separator: " "))]" : ""
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 700] "
            + "/Resources << /Font << /F1 3 0 R >> >> /Contents \(pageObject(page) + 1) 0 R\(annots) >>")
        let text = (0..<lines).map {
            "BT /F1 10 Tf 20 \(660 - $0 * 12) Td (Page \(page) line \($0 + 1) of a book with a great deal to say "
                + "about everything, at length, for long enough to fill the writer's body target.) Tj ET"
        }.joined(separator: " ")
        objects.append(testPDFStream(text))
    }
    return testPDF(objects: objects + resolved)
}

/// A link annotation over the first line of the first page.
private func linkAnnotation(_ action: String, y: Double = 652, height: Double = 14) -> String {
    "<< /Type /Annot /Subtype /Link /Rect [20 \(y) 380 \(y + height)] /Border [0 0 0] \(action) >>"
}

private func convert(_ data: Data, in directory: URL, name: String = "book") async throws -> (Archive, ConversionReport) {
    let source = directory.appendingPathComponent(name + ".pdf")
    try data.write(to: source)
    let output = directory.appendingPathComponent(name + ".epub")
    let report = try await PDFConverter().convert(from: source, to: output)
    return (try Archive(url: output, accessMode: .read), report)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func onlyLinkSchemesAReaderCanFollowAreCarried() {
    #expect(PageReader.externalTarget(URL(string: "https://www.w3.org/TR/epub-33/")!)
        == .external("https://www.w3.org/TR/epub-33/"))
    #expect(PageReader.externalTarget(URL(string: "http://example.org/a?b=1#c")!)
        == .external("http://example.org/a?b=1#c"))
    #expect(PageReader.externalTarget(URL(string: "mailto:reader@example.org")!)
        == .external("mailto:reader@example.org"))
    // Neither of these may ever reach an output document.
    #expect(PageReader.externalTarget(URL(string: "javascript:alert('no')")!) == nil)
    #expect(PageReader.externalTarget(URL(string: "file:///etc/passwd")!) == nil)
    #expect(PageReader.externalTarget(URL(string: "ftp://example.org/x")!) == nil)
    let long = URL(string: "https://example.org/" + String(repeating: "a", count: 3_000))!
    #expect(PageReader.externalTarget(long) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func theBundledLinksConvertAndTheOnesThatMustNotAreDropped() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("links.epub")
    let report = try await PDFConverter().convert(from: fixtureURL("links.pdf"), to: output)
    let html = try Archive(url: output, accessMode: .read).chapter()
    #expect(html.contains("<a href=\"https://www.w3.org/TR/epub-33/\">published</a>"))
    #expect(html.contains("<a href=\"mailto:reader@example.org\">reader@example.org</a>"))
    // One link over two printed lines is one anchor, not two.
    #expect(html.contains("<a href=\"chapter-1.xhtml#page-2\">This sentence about the second page "
        + "runs across two lines and the link covers both of them.</a>"))
    // A link whose rectangle covers the figure links the figure.
    #expect(html.contains("<a href=\"chapter-1.xhtml#page-2\"><img src=\"images/image-1.png\""))
    #expect(!html.contains("javascript"))
    let annotations = try #require(report.warnings.first { $0.code == .annotationsNotConverted })
    #expect(annotations.message.contains("4 links converted to anchors"))
    #expect(annotations.message.contains("1 annotation is not reconstructed"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func anInternalLinkResolvesToTheSpineDocumentThatEndsUpHoldingThePage() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // The link is serialized on page 1, long before the document holding page 12 is opened.
    let (archive, _) = try await convert(annotatedPDF(pages: 24, lines: 54, annotations: [
        linkAnnotation("/A << /S /GoTo /D [%PAGE 24% /XYZ null null null] >>"),
    ]), in: dir)
    let html = try archive.chapter()
    let file = try #require(html.firstMatch(of: /<a href="(chapter-\d+)\.xhtml#page-24">/)?.1)
    #expect(file != "chapter-1")
    #expect(archive["EPUB/\(file).xhtml"] != nil)
    #expect(try archive.entryText("EPUB/\(file).xhtml").contains("id=\"page-24\""))
    // No token survives into a published book.
    for number in 1...24 where archive["EPUB/chapter-\(number).xhtml"] != nil {
        #expect(!(try archive.chapter(number)).contains(EPUBTextEncoder.pageLinkToken))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247"))
func resolvingALinkCanOnlyShortenTheBodyThePackerMeasured() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // The packer measures a body when the block is serialized and the writer resolves the token
    // afterwards, so a token that grew would push a finished document past the target it had
    // already been measured against.
    #expect(EPUBTextEncoder.href(.page(400)).count == EPUBTextEncoder.pageLinkTokenWidth)
    #expect(EPUBTextEncoder.href(.page(1)).hasPrefix(EPUBTextEncoder.pageLinkToken + "1-"))
    #expect("chapter-999999.xhtml#page-999999".count < EPUBTextEncoder.pageLinkTokenWidth)

    // A book whose every page links to its last, long enough to fill several spine documents.
    let links = (1...24).map { _ in linkAnnotation("/A << /S /GoTo /D [%PAGE 24% /XYZ null null null] >>") }
    let (archive, _) = try await convert(annotatedPDF(pages: 24, lines: 54, annotations: links), in: dir)
    var documents = 0
    for number in 1...24 {
        guard archive["EPUB/chapter-\(number).xhtml"] != nil else { break }
        documents += 1
        let body = try archive.chapter(number).split(separator: "<body>")[1].split(separator: "</body>")[0]
        #expect(body.utf8.count <= 60_000, "spine document \(number) is \(body.utf8.count) bytes")
        #expect(!body.contains(EPUBTextEncoder.pageLinkToken))
    }
    #expect(documents > 1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func aPageWhoseAnnotationsAllConvertNeedsNoPictureOfItself() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let (converted, report) = try await convert(annotatedPDF(pages: 2, lines: 6, annotations: [
        linkAnnotation("/A << /S /URI /URI (https://example.org/) >>"),
    ]), in: dir, name: "converted")
    #expect(!report.warnings.contains { $0.code == .annotationsNotConverted })
    #expect(report.imageCount == 0)
    #expect(try converted.chapter().contains("<a href=\"https://example.org/\">"))

    // A destination outside this document is not a link this converter reproduces, so the page
    // still needs its own picture and still says so.
    let (_, dropped) = try await convert(annotatedPDF(pages: 2, lines: 6, annotations: [
        linkAnnotation("/A << /S /GoToR /F (other.pdf) /D [0 /XYZ null null null] >>"),
    ]), in: dir, name: "dropped")
    let warning = try #require(dropped.warnings.first { $0.code == .annotationsNotConverted })
    #expect(warning.message.contains("1 annotation is not reconstructed"))
    #expect(!warning.message.contains("converted to anchors"))
    #expect(dropped.imageCount == 1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func editingTextReachesInsideALinkRatherThanSkippingIt() {
    let target = LinkTarget.external("https://example.org/")
    // A word a page breaks can end inside a link, and both repairs edit the link's own text:
    // the hyphen a font drew as another character is put back, then the join removes it.
    var text = InlineText(elements: [.text("see ", []), .link(target, InlineText("conver\u{2010}"))])
    #expect(text.text == "see conver\u{2010}")
    #expect(text.links.map(\.text) == ["conver\u{2010}"])
    text.replaceLastCharacter(with: "-")
    #expect(text.text == "see conver-")
    text.removeLastCharacter()
    #expect(text.text == "see conver")
    #expect(text.links.map(\.text) == ["conver"])
    // Trimming reaches into a link at either end, and drops one that trims away entirely.
    let padded = InlineText(elements: [.link(target, InlineText("  ")), .text(" middle ", []),
                                       .link(target, InlineText(" edge  "))])
    let trimmed = padded.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(trimmed.text == "middle edge")
    // A page boundary inside a link is still the page the text is on.
    let across = InlineText(elements: [.link(target, InlineText(elements: [.text("a", []), .sourcePage(4)]))])
    #expect(across.sourcePages == [4])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func oneLinkBrokenAcrossLinesBecomesOneAnchor() {
    let target = LinkTarget.page(7)
    var text = InlineText(elements: [
        .link(target, InlineText("a sentence that")), .text(" ", []),
        .link(target, InlineText("runs on")), .text(" and then ", []),
        .link(.external("https://example.org/"), InlineText("another")),
    ])
    text.mergeAdjacentLinks()
    #expect(text.elements.count == 3)
    #expect(text.links.map(\.text) == ["a sentence that runs on", "another"])
    // Text between two links of the same target is not part of either.
    var separated = InlineText(elements: [.link(target, InlineText("one")), .text(" word ", []),
                                          .link(target, InlineText("two"))])
    separated.mergeAdjacentLinks()
    #expect(separated.elements.count == 3)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/247")) func aLinkSurvivesTheSpillToDiskBetweenThePipelinesTwoPasses() throws {
    let directory = try scratch(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = PageStore(directory: directory)
    var page = PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 400, height: 700),
                           lines: [], graphics: [])
    page.links = [PageLink(rect: CGRect(x: 1, y: 2, width: 3, height: 4), target: .page(9))]
    page.lines = [TextLine(content: InlineText(elements: [
        .text("see ", []), .link(.external("https://example.org/"), InlineText("the notes", style: .italic)),
    ]), rect: CGRect(x: 0, y: 0, width: 100, height: 12), fontSize: 12)]
    try store.store(page, at: 0)
    let loaded = try store.load(at: 0)
    #expect(loaded == page)
    #expect(loaded.lines[0].content.links.map(\.target) == [.external("https://example.org/")])
    store.finish()
}
