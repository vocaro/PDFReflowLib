import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func chapterPDF(secondTitle: String = "Chapter 2 Beta", firstDestination: String = "/Dest [3 0 R /Fit]",
                        secondDestination: String = "/Dest [4 0 R /Fit]", catalog: String = "", nested: Bool = false,
                        visibleTitles: Bool = false, firstTitle: String = "Chapter 1 Alpha",
                        firstPageTitle: String = "Chapter 1 Alpha", secondPageTitle: String = "Chapter 2 Beta") -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R \(catalog) >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 10 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 10 0 R >> >> /Contents 6 0 R >>",
        testPDFStream(visibleTitles ? "BT /F1 24 Tf 40 700 Td (\(firstPageTitle)) Tj ET" : ""),
        testPDFStream(visibleTitles ? "BT /F1 24 Tf 40 700 Td (\(secondPageTitle)) Tj ET" : ""),
        "<< /Type /Outlines /First 8 0 R /Last \(nested ? 8 : 9) 0 R /Count 2 >>",
        "<< /Title (\(firstTitle)) /Parent 7 0 R \(nested ? "/First 9 0 R /Last 9 0 R /Count 1" : "/Next 9 0 R") \(firstDestination) >>",
        "<< /Title (\(secondTitle)) /Parent \(nested ? 8 : 7) 0 R \(nested ? "" : "/Prev 8 0 R") \(secondDestination) >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ])
}

@Test func publicConversionAppliesOnlySourceVerifiedChapterBoundaries() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for valid in [true, false] {
        let source = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book-\(valid).epub")
        try chapterPDF(secondTitle: valid ? "Chapter 2 Beta" : "Chapter 2 Different", visibleTitles: true).write(to: source)
        let report = try await PDFConverter().convert(from: source, to: output)
        #expect(report.pageCount == 2)
        let archive = try Archive(url: output, accessMode: .read)
        #expect(archive.filter { $0.path.hasPrefix("EPUB/chapter-") }.count == (valid ? 2 : 1))
        let text = try archive.chapter(valid ? 2 : 1)
        #expect(text.contains("Chapter 2 Beta"))
        #expect(text.contains("id=\"page-2\""))
    }
}

@Test func chapterOutlineAcceptsLocalDirectNamedAndGoToDestinations() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for data in [chapterPDF(), chapterPDF(secondDestination: "/A << /S /GoTo /D [4 0 R /Fit] >>"),
                 chapterPDF(secondDestination: "/Dest /second", catalog: "/Dests << /second [4 0 R /Fit] >>")] {
        let url = dir.appendingPathComponent("source.pdf")
        try data.write(to: url)
        #expect(try ChapterBoundaryReader.read(url) == [.init(number: 1, title: "Alpha", page: 1),
                                                      .init(number: 2, title: "Beta", page: 2)])
    }
}

@Test func chapterOutlineRejectsAmbiguousUnsafeAndNestedDestinations() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for data in [chapterPDF(secondTitle: "Chapter 3 Beta"), chapterPDF(secondTitle: "Chapter 1 Beta"),
                 chapterPDF(secondTitle: "Section 2 Beta"), chapterPDF(secondDestination: ""),
                 chapterPDF(secondDestination: "/Dest [3 0 R /Fit]"),
                 chapterPDF(firstDestination: "/Dest [4 0 R /Fit]", secondDestination: "/Dest [3 0 R /Fit]"),
                 chapterPDF(secondDestination: "/A << /S /GoToR /F (elsewhere.pdf) /D [0 /Fit] >>"),
                 chapterPDF(secondDestination: "/A << /S /URI /URI (https://example.com/) >>"),
                 chapterPDF(nested: true)] {
        let url = dir.appendingPathComponent("source.pdf")
        try data.write(to: url)
        #expect(try ChapterBoundaryReader.read(url).isEmpty)
    }
}

@Test func sourceChapterOpeningsRequireNumberAndWholeAdjacentTitle() throws {
    let cases = [(33, 1, "Overview: Understanding Risks, Impacts, and Responses"), (80, 2, "Climate Trends"),
                 (139, 3, "Earth Systems Processes"), (1619, 32, "Mitigation")]
    for (page, number, title) in cases {
        let fixture = try SourceLayoutFixture.load("noaa-\(page)")
        let candidate = ChapterBoundaryReader.Candidate(number: number, title: title, page: page)
        let content = fixture.content()
        #expect(ChapterBoundaryReader.matches(candidate, page: content))
        #expect(!ChapterBoundaryReader.matches(.init(number: number + 1, title: title, page: page), page: content))
        #expect(!ChapterBoundaryReader.matches(.init(number: number, title: title + " extra", page: page), page: content))
        #expect(!ChapterBoundaryReader.matches(.init(number: number, title: title, page: page + 1), page: content))
        for synthetic in [false, true] {
            var changed = content
            changed.hasSyntheticTextStyle = synthetic
            changed.recognized = !synthetic
            #expect(!ChapterBoundaryReader.matches(candidate, page: changed))
        }
        var body = content
        for index in body.lines.indices { body.lines[index].rect.origin.y = 100 }
        #expect(!ChapterBoundaryReader.matches(candidate, page: body))
    }
}

@Test func chapterTitleControlsCoverWrappingWhitespaceAndBodyMentions() {
    let candidate = ChapterBoundaryReader.Candidate(number: 1, title: "A real title", page: 1)
    func page(_ text: [String]) -> PageContent {
        PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: text.enumerated().map {
            TextLine(text: $0.element, rect: CGRect(x: 40, y: 740 - $0.offset * 25, width: 300, height: 20), fontSize: 18)
        }, graphics: [])
    }
    for lines in [["CHAPTER 1", "A real", "title"], ["Chapter 1 A real title"], ["Chapter   1", "A real title"]] {
        #expect(ChapterBoundaryReader.matches(candidate, page: page(lines)))
    }
    for lines in [["Chapter 11", "A real title"], ["Chapter 1", "A real title appears in this sentence."],
                  ["Chapter 1", "Unrelated intervening text", "A real title"], ["A real title"],
                  ["Read Chapter 1 A real title for details"]] {
        #expect(!ChapterBoundaryReader.matches(candidate, page: page(lines)))
    }
}

@Test func logicalChapterBoundariesMustHaveStandalonePageMarkers() {
    let inline = InlineText(elements: [.text("continued", []), .sourcePage(2), .text("word", [])])
    let book = ReflowDocument(metadata: .init(title: "test", language: "en"),
        blocks: [.init(content: .paragraph(inline), page: 1)], assets: [], chapterStartPages: [2])
    #expect(throws: ReflowDocument.ValidationError.invalidChapterBoundary(2)) { try book.validate() }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/15"))
func romanChaptersInsidePartsKeepCrossChapterLinksAndNavigation() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 11 0 R >> >> /Contents 5 0 R /Annots [12 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 11 0 R >> >> /Contents 6 0 R /Annots [13 0 R] >>",
        testPDFStream("BT /F1 24 Tf 40 700 Td (Chapter I: Alpha) Tj ET"),
        testPDFStream("BT /F1 24 Tf 40 700 Td (Chapter II: Beta) Tj ET"),
        "<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 3 >>",
        "<< /Title (Part One) /Parent 7 0 R /First 9 0 R /Last 10 0 R /Count 2 >>",
        "<< /Title (Chapter I: Alpha) /Parent 8 0 R /Next 10 0 R /Dest [3 0 R /Fit] >>",
        "<< /Title (Chapter II: Beta) /Parent 8 0 R /Prev 9 0 R /Dest [4 0 R /Fit] >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Annot /Subtype /Link /Rect [35 680 480 740] /A << /S /GoTo /D [4 0 R /Fit] >> >>",
        "<< /Type /Annot /Subtype /Link /Rect [35 680 480 740] /A << /S /GoTo /D [3 0 R /Fit] >> >>",
    ])
    let source = dir.appendingPathComponent("roman.pdf"), output = dir.appendingPathComponent("roman.epub")
    try data.write(to: source)
    let candidates = try ChapterBoundaryReader.read(source)
    #expect(candidates.map(\.number) == [1, 2])
    #expect(candidates.map(\.marker) == ["chapter i", "chapter ii"])
    _ = try await PDFConverter().convert(from: source, to: output)
    let archive = try Archive(url: output, accessMode: .read)
    #expect(archive.filter { $0.path.hasPrefix("EPUB/chapter-") }.count == 2)
    let one = try archive.chapter(1), two = try archive.chapter(2)
    #expect(one.contains("href=\"chapter-2.xhtml#page-2\""))
    #expect(two.contains("href=\"chapter-1.xhtml#page-1\""))
    #expect(one.contains("Chapter I: Alpha") && two.contains("Chapter II: Beta"))
    let navigation = try archive.entryText("EPUB/nav.xhtml")
    #expect(navigation.contains("Part One"))
    #expect(navigation.contains("Chapter I: Alpha") && navigation.contains("Chapter II: Beta"))
    #expect(!one.contains("id=\"page-2\""))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/15"))
func chapterNumeralAndPunctuationRequireExactSourceEvidence() throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.pdf")
    for (first, second) in [("Chapter 1: Alpha", "Chapter 2. Beta"), ("Chapter I Alpha", "Chapter II Beta")] {
        try chapterPDF(secondTitle: second, firstTitle: first).write(to: source)
        #expect(try ChapterBoundaryReader.read(source).map(\.number) == [1, 2])
    }
    for second in ["Chapter IIX Beta", "Chapter III Beta", "Chapter I Beta", "Chapter 0 Beta"] {
        try chapterPDF(secondTitle: second, firstTitle: "Chapter I Alpha").write(to: source)
        #expect(try ChapterBoundaryReader.read(source).isEmpty)
    }
    let candidate = ChapterBoundaryReader.Candidate(number: 2, title: "Beta", page: 2, marker: "chapter ii")
    func page(_ title: String) -> PageContent {
        PageContent(number: 2, bounds: CGRect(x: 0, y: 0, width: 600, height: 800),
            lines: [TextLine(text: title, rect: CGRect(x: 40, y: 700, width: 300, height: 24), fontSize: 24)], graphics: [])
    }
    #expect(ChapterBoundaryReader.matches(candidate, page: page("Chapter II: Beta")))
    #expect(ChapterBoundaryReader.matches(candidate, page: page("Chapter II — Beta")))
    #expect(!ChapterBoundaryReader.matches(candidate, page: page("Chapter III: Beta")))
    #expect(!ChapterBoundaryReader.matches(candidate, page: page("Chapter II: Beta is discussed here.")))
    #expect(!ChapterBoundaryReader.matches(candidate, page: page("Chapter 2: Beta")))
}
