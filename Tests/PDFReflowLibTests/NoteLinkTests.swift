import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func chapterNote(_ number: Int, chapter: Int, _ text: String, page: Int) -> ReflowBlock {
    ReflowBlock(content: .paragraph(InlineText("\(number). \(text)")),
                note: NoteKey(number: number, scope: .chapter(chapter)), page: page)
}

private func body(_ elements: [InlineText.Element], page: Int) -> ReflowBlock {
    ReflowBlock(content: .paragraph(InlineText(elements: elements)), page: page)
}

private func sup(_ digits: String, _ extra: TextStyle = []) -> InlineText.Element {
    .text(digits, extra.union(.superscript))
}

private func key(_ number: Int, chapter: Int) -> NoteKey { NoteKey(number: number, scope: .chapter(chapter)) }
private func key(_ number: Int, page: Int) -> NoteKey { NoteKey(number: number, scope: .page(page)) }

private func elements(_ block: ReflowBlock) -> [InlineText.Element] {
    if case let .paragraph(text) = block.content { return text.elements }
    return []
}

private func writtenFiles(_ book: ReflowDocument, directory: URL) async throws -> [String: String] {
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 100_000_000, directory: directory, progress: { _ in })
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("EPUB").path)
        .filter { $0.hasPrefix("chapter-") }
    return Dictionary(uniqueKeysWithValues: try names.map {
        ($0, try String(contentsOf: directory.appendingPathComponent("EPUB/" + $0), encoding: .utf8))
    })
}

private func bodyBytes(_ chapter: String) -> Int {
    chapter.components(separatedBy: "<body>")[1].components(separatedBy: "</body>")[0].utf8.count
}

@Test func markersLinkToTheirChapterNotesAndNeverAcrossChapters() {
    var blocks = [
        ReflowBlock(content: .sourcePage(1), page: 1),
        body([.text("First chapter", []), sup("4"), .text(" cites", []), sup("9"), .text(" twice.", [])], page: 1),
        ReflowBlock(content: .sourcePage(2), page: 2),
        body([.text("Second chapter", []), sup("4"), .text(" and", []), sup("5")], page: 2),
        ReflowBlock(content: .sourcePage(3), page: 3),
        body([.text("Front matter", []), sup("4")], page: 3),
        ReflowBlock(content: .sourcePage(4), page: 4),
        chapterNote(4, chapter: 1, "Chapter one, note four.", page: 4),
        chapterNote(4, chapter: 2, "Chapter two, note four.", page: 5),
        chapterNote(5, chapter: 2, "Chapter two, note five.", page: 5),
    ]
    let saved = blocks
    let summary = NoteLinker.link(&blocks) { [1: 1, 2: 2][$0] }
    #expect(summary == .init(markers: 5, linked: 3, unscoped: 1, missing: 1, ambiguous: 0, ambiguousNotes: 0))
    #expect(elements(blocks[1]) == [.text("First chapter", []), .noteReference("4", [], key(4, chapter: 1)),
                                    .text(" cites", []), sup("9"), .text(" twice.", [])])
    #expect(elements(blocks[3]) == [.text("Second chapter", []), .noteReference("4", [], key(4, chapter: 2)),
                                    .text(" and", []), .noteReference("5", [], key(5, chapter: 2))])
    // No chapter for page 3, so its marker stays plain; text is unchanged everywhere.
    #expect(blocks[5] == saved[5])
    #expect(blocks.map(\.text) == saved.map(\.text))
    #expect(blocks[7...] == saved[7...])
}

@Test func repeatedReferencesShareOneNoteAndAmbiguousNumbersStayPlain() {
    var blocks = [
        body([.text("Once", []), sup("4"), .text(" and again", []), sup("4"), .text(" but", []), sup("7")], page: 1),
        chapterNote(4, chapter: 1, "Only note four.", page: 9),
        chapterNote(7, chapter: 1, "First claim on seven.", page: 9),
        chapterNote(7, chapter: 1, "Second claim on seven.", page: 10),
    ]
    let summary = NoteLinker.link(&blocks) { _ in 1 }
    #expect(summary == .init(markers: 3, linked: 2, unscoped: 0, missing: 0, ambiguous: 1, ambiguousNotes: 1))
    #expect(elements(blocks[0]) == [.text("Once", []), .noteReference("4", [], key(4, chapter: 1)),
                                    .text(" and again", []), .noteReference("4", [], key(4, chapter: 1)),
                                    .text(" but", []), sup("7")])
}

@Test func markerPageFollowsInlineBoundariesAndPageNotesOutrankChapterNotes() {
    let footnote = ReflowBlock(content: .footnote(InlineText(elements: [.text("1", .superscript), .text(" Page note.", [])])),
                               note: key(1, page: 2), page: 2)
    var blocks = [
        body([.text("Before", []), sup("1"), .text(" the break", []), .sourcePage(2), .text(" after", []), sup("1"),
              .text(" styled", []), sup("2", .italic), .text(" spaced", []), sup(" 3 "),
              .text(" not markers", []), sup("a"), sup("1234"), sup("0"), .text("plain 4", [])], page: 1),
        footnote,
        chapterNote(1, chapter: 1, "Chapter note one.", page: 9),
        chapterNote(2, chapter: 1, "Chapter note two.", page: 9),
        chapterNote(3, chapter: 1, "Chapter note three.", page: 9),
        // Notes cite no notes: a marker inside a note or a footnote is left alone.
        ReflowBlock(content: .paragraph(InlineText(elements: [.text("5. See", []), sup("1")])), note: key(5, chapter: 1), page: 9),
        ReflowBlock(content: .footnote(InlineText(elements: [.text("2", .superscript), .text(" cites", []), sup("1")])),
                    note: key(2, page: 3), page: 3),
    ]
    let saved = blocks
    let summary = NoteLinker.link(&blocks) { $0 < 9 ? 1 : nil }
    #expect(summary.markers == 4 && summary.linked == 4)
    #expect(elements(blocks[0]) == [.text("Before", []), .noteReference("1", [], key(1, chapter: 1)), .text(" the break", []),
                                    .sourcePage(2), .text(" after", []), .noteReference("1", [], key(1, page: 2)),
                                    .text(" styled", []), .noteReference("2", .italic, key(2, chapter: 1)),
                                    .text(" spaced", []), .text(" ", []), .noteReference("3", [], key(3, chapter: 1)),
                                    .text(" ", []), .text(" not markers", []), sup("a"), sup("1234"), sup("0"),
                                    .text("plain 4", [])])
    #expect(blocks[0].text == saved[0].text)
    #expect(blocks[1...] == saved[1...])
}

@Test func linkedNotesSerializeWithReferenceIdsAndBacklinksAcrossSpineFiles() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let filler = ReflowBlock(content: .paragraph(InlineText(String(repeating: "x", count: 59_300))), page: 1)
    let book = ReflowDocument(metadata: .init(title: "Notes", language: "en"), blocks: [
        ReflowBlock(content: .sourcePage(1), page: 1),
        body([.text("Body", []), .noteReference("4", [], key(4, chapter: 1)), .text(" foot", []),
              .noteReference("2", [], key(2, page: 1)), .text(" again", []), .noteReference("4", .italic, key(4, chapter: 1)),
              .text(" plain", []), sup("9")], page: 1),
        ReflowBlock(content: .footnote(InlineText(elements: [.text("2", .superscript), .text(" Foot & note.", [])])),
                    note: key(2, page: 1), page: 1),
        filler,
        ReflowBlock(content: .sourcePage(2), page: 2),
        chapterNote(4, chapter: 1, "Note <four>.", page: 2),
        chapterNote(5, chapter: 1, "Unreferenced.", page: 2),
        ReflowBlock(content: .paragraph(InlineText(elements: [.text("Odd", .bold), .text(" opening", [])])),
                    note: key(6, chapter: 1), page: 2),
        body([.text("Late", []), .noteReference("6", [], key(6, chapter: 1))], page: 2),
    ], assets: [])
    let files = try await writtenFiles(book, directory: dir)
    // The filler pushes the endnotes into a later spine document than their references.
    let (referenceFile, first) = try #require(files.first { $0.value.contains("id=\"noteref-c1-4\"") })
    let (noteFile, second) = try #require(files.first { $0.value.contains("id=\"note-c1-4\"") })
    #expect(referenceFile == "chapter-1.xhtml" && referenceFile != noteFile)
    // The first reference carries the id; a repeated reference links without one, keeping its style.
    #expect(first.contains("Body<sup><a epub:type=\"noteref\" role=\"doc-noteref\" id=\"noteref-c1-4\" href=\"\(noteFile)#note-c1-4\">4</a></sup> foot"))
    #expect(first.contains(" again<sup><a epub:type=\"noteref\" role=\"doc-noteref\" href=\"\(noteFile)#note-c1-4\"><em>4</em></a></sup> plain<sup>9</sup></p>"))
    // A same-file link keeps the bare fragment; the note's marker becomes the return link.
    #expect(first.contains(" foot<sup><a epub:type=\"noteref\" role=\"doc-noteref\" id=\"noteref-p1-2\" href=\"#note-p1-2\">2</a></sup>"))
    #expect(first.contains("<div class=\"footnote\" role=\"doc-footnote\" id=\"note-p1-2\"><p><sup><a href=\"#noteref-p1-2\" role=\"doc-backlink\" epub:type=\"backlink\">2</a></sup> Foot &amp; note.</p></div>"))
    #expect(second.contains("<p id=\"note-c1-4\" epub:type=\"endnote\"><a href=\"chapter-1.xhtml#noteref-c1-4\" role=\"doc-backlink\" epub:type=\"backlink\">4.</a> Note &lt;four&gt;.</p>"))
    // An unreferenced note and an unlinked marker are written exactly as before.
    #expect(second.contains("<p>5. Unreferenced.</p>"))
    #expect(!second.contains("note-c1-5"))
    // A note that does not open with its number gets the return link appended.
    #expect(second.contains("<p id=\"note-c1-6\" epub:type=\"endnote\"><strong>Odd</strong> opening <a href=\"#noteref-c1-6\" role=\"doc-backlink\" epub:type=\"backlink\">\u{21A9}</a></p>"))
    #expect(second.contains("id=\"noteref-c1-6\" href=\"#note-c1-6\">6</a>"))
    #expect(files.values.allSatisfy { bodyBytes($0) <= 60_000 })
    #expect(!first.contains("epub:type=\"endnote\"") && !second.contains("role=\"doc-footnote\""))
}

@Test func manyCrossFileLinksStillMeetTheSpineBodyTarget() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    var blocks: [ReflowBlock] = [ReflowBlock(content: .sourcePage(1), page: 1)]
    for number in 1...700 {
        blocks.append(body([.text("Paragraph \(number) cites note", []), .noteReference("\(number)", [], key(number, chapter: 1)),
                            .text(" of chapter one.", [])], page: 1))
    }
    blocks.append(ReflowBlock(content: .sourcePage(2), page: 2))
    for number in 1...700 { blocks.append(chapterNote(number, chapter: 1, "Note \(number) text.", page: 2)) }
    let files = try await writtenFiles(ReflowDocument(metadata: .init(title: "Many", language: "en"), blocks: blocks, assets: []), directory: dir)
    #expect(files.count >= 3)
    #expect(files.values.allSatisfy { bodyBytes($0) <= 60_000 })
    let all = files.values.joined()
    #expect(all.components(separatedBy: "role=\"doc-noteref\"").count - 1 == 700)
    #expect(all.components(separatedBy: "role=\"doc-backlink\"").count - 1 == 700)
    for number in [1, 350, 700] {
        let reference = try #require(files.first { $0.value.contains("id=\"noteref-c1-\(number)\"") })
        let note = try #require(files.first { $0.value.contains("id=\"note-c1-\(number)\"") })
        #expect(reference.value.contains("href=\"\(note.key)#note-c1-\(number)\""))
        #expect(note.value.contains("href=\"\(reference.key)#noteref-c1-\(number)\""))
    }
}

/// Page 469 opens chapter 1's notes: note 1 has a second indented paragraph, which stays a
/// paragraph of its own without a key; page 20's raised 4 after `7:45.` links to note 4.
@Test func sourcePageTwentyMarkerLinksToChapterOneNoteFourOnPageFourSixtyNine() throws {
    var notesPage = try SourceLayoutFixture.load("911-469").content()
    #expect(NumberedNoteDetector.chapter(on: notesPage) == 1)
    notesPage.lines.removeFirst()
    var warnings: [ConversionWarning] = []
    let noteBlocks = LayoutReconstructor.blocks(page: notesPage, images: [], vocabulary: [], warnings: &warnings, noteChapter: 1)
    let keyed = noteBlocks.compactMap(\.note)
    #expect(keyed == (1...9).map { key($0, chapter: 1) })
    let extra = try #require(noteBlocks.first { $0.text.hasPrefix("Like the other two airports") })
    #expect(extra.note == nil && !extra.text.contains("2. CAPPS"))
    let first = try #require(noteBlocks.first { $0.note == key(1, chapter: 1) })
    #expect(first.text.hasSuffix("Portland International Jetport site visit (Aug. 18, 2003)."))
    let fixture = try SourceLayoutFixture.load("911-20")
    let line = try #require(fixture.attributedLines.first { $0.text.contains("7:45.") })
    var blocks = [ReflowBlock(content: .sourcePage(20), page: 20),
                  ReflowBlock(content: .paragraph(NativeTextReader.inlineText(from: line.attributedString())), page: 20),
                  ReflowBlock(content: .sourcePage(469), page: 469)] + noteBlocks
    let summary = NoteLinker.link(&blocks) { $0 == 20 ? 1 : nil }
    #expect(summary.linked == 1 && summary.markers == 1)
    #expect(elements(blocks[1]).contains(.noteReference("4", [], key(4, chapter: 1))))
    #expect(blocks[1].text.contains("scheduled to depart at 7:45.4"))
    #expect(EPUBTextEncoder.inline(InlineText(elements: elements(blocks[1]))).contains(
        "7:45.<sup><a epub:type=\"noteref\" role=\"doc-noteref\" href=\"#note-c1-4\">4</a></sup>"))
    let note = try #require(blocks.first { $0.note == key(4, chapter: 1) })
    guard case let .paragraph(text) = note.content else { Issue.record("note must be a paragraph"); return }
    #expect(EPUBTextEncoder.note(text, number: 4, backlink: "noteref-c1-4").hasPrefix(
        "<a href=\"#noteref-c1-4\" role=\"doc-backlink\" epub:type=\"backlink\">4.</a> Flight 11 pushed back from Gate 32"))
}

/// Page 484 ends chapter 1's notes with 241, then opens chapter 2's notes under its own
/// heading: notes 1–22 there belong to chapter 2, so chapter 1's note 4 stays unique.
@Test func sourceChapterOpeningHeadingBetweenNotesSwitchesTheScope() throws {
    var page = try SourceLayoutFixture.load("911-484").content()
    #expect(NumberedNoteDetector.chapter(on: page) == 1)
    page.lines.removeFirst()
    let elements = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    let layout = try #require(NumberedNoteDetector.layout(in: elements, page: page, chapter: 1))
    let notes = layout.notes.values.sorted { ($0.chapter, $0.number) < ($1.chapter, $1.number) }
    #expect(notes == [.init(number: 241, chapter: 1)] + (1...22).map { .init(number: $0, chapter: 2) })
    let heading = try #require(page.lines.firstIndex { $0.text.hasPrefix("2 The Foundation") })
    #expect(layout.paragraphs[heading] == nil)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, noteChapter: 1)
    #expect(blocks.compactMap(\.note) == [key(241, chapter: 1)] + (1...22).map { key($0, chapter: 2) })
    #expect(blocks.contains { $0.text == "2 The Foundation of the New Terrorism" && $0.note == nil })
    // Without a heading of the next chapter's number, the sequence break refuses the page.
    var renumbered = page
    renumbered.lines[heading] = TextLine(text: "4 The Foundation of the New Terrorism", rect: page.lines[heading].rect,
                                         fontSize: page.lines[heading].fontSize)
    #expect(NumberedNoteDetector.layout(in: renumbered.lines.map { .init(rect: $0.rect, line: $0) }, page: renumbered, chapter: 1) == nil)
    var smaller = page
    smaller.lines[heading].fontSize = 7
    #expect(NumberedNoteDetector.layout(in: smaller.lines.map { .init(rect: $0.rect, line: $0) }, page: smaller, chapter: 1) == nil)
}

@Test func numberedNoteStartsIgnoreDedentedNumbersAndRefuseListsInsideNotes() throws {
    func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 400) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 10), fontSize: 10)
    }
    var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
        line("NOTES TO CHAPTER 3", 40, 754, 180),
        line("2003.“Written statements continue the previous page's note here", 40, 712),
        line("38. First source citation with enough letters.", 60, 700, 300),
        line("39.Second citation begins with sufficient text to wrap", 60, 688),
        line("p. 11; and continues on the following line.", 40, 676),
        line("A second paragraph of the same note sits at the indent.", 60, 664),
        line("40. Ibid.", 60, 652, 60),
        line("41. Third source citation.", 60, 640, 200),
    ], graphics: [])
    var warnings: [ConversionWarning] = []
    var blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, noteChapter: 3)
    #expect(blocks.compactMap(\.note) == [38, 39, 40, 41].map { key($0, chapter: 3) })
    #expect(blocks.first { $0.text.hasPrefix("2003.") }?.note == nil)
    #expect(blocks.first { $0.note == key(39, chapter: 3) }?.text == "39.Second citation begins with sufficient text to wrap p. 11; and continues on the following line.")
    #expect(blocks.first { $0.text.hasPrefix("A second paragraph") }?.note == nil)
    #expect(blocks.first { $0.note == key(40, chapter: 3) }?.text == "40. Ibid.")
    // A lettered list item at the indent, or a bare number, is not a note's paragraph.
    for control in ["a. First lettered item of a list", "7"] {
        page.lines[5] = line(control, 60, 664)
        blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, noteChapter: 3)
        #expect(blocks.compactMap(\.note).isEmpty, "control \(control)")
    }
}

@Test func sourceSlipOpinionMarkersLinkToTheirPageFootnotes() throws {
    for (name, number, before) in [("loper-60", 2, "Ibid."), ("loper-13", 1, "Persistence.")] {
        var page = try SourceLayoutFixture.load(name).styledContent()
        page.lines.removeAll { $0.rect.midY > page.bounds.minY + page.bounds.height * 0.8 }
        var warnings: [ConversionWarning] = []
        var blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                                warnings: &warnings)
        let note = try #require(blocks.first { $0.isFootnote })
        #expect(note.note == key(number, page: page.number))
        let summary = NoteLinker.link(&blocks) { _ in nil }
        #expect(summary.linked == 1)
        let cited = try #require(blocks.first { elements($0).contains(.noteReference("\(number)", [], key(number, page: page.number))) })
        #expect(cited.text.contains(before + "\(number)"))
    }
}

/// An outline that numbers its chapters without the word (`1 Alpha`) scopes note references
/// without adding spine boundaries; equal note numbers in two chapters stay distinct.
@Test func publicConversionLinksRepeatedNoteNumbersByNumberedOutlineChapter() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    func chapterPage(_ number: Int, title: String) -> String {
        "BT /F1 24 Tf 1 0 0 1 40 740 Tm (\(number)) Tj 1 0 0 1 40 710 Tm (\(title)) Tj "
            + "/F1 10 Tf 1 0 0 1 40 680 Tm (Chapter \(number) body cites its first note) Tj /F1 6 Tf 3 Ts (1) Tj 0 Ts "
            + "/F1 10 Tf ( and its second) Tj /F1 6 Tf 3 Ts (2) Tj 0 Ts /F1 10 Tf ( here.) Tj ET"
    }
    func notesPage(_ number: Int) -> String {
        "BT /F1 10 Tf 1 0 0 1 40 754 Tm (NOTES TO CHAPTER \(number)) Tj "
            + "1 0 0 1 60 700 Tm (1. First note of chapter \(number) with enough words to wrap) Tj "
            + "1 0 0 1 40 688 Tm (and a dedented continuation line.) Tj "
            + "1 0 0 1 60 676 Tm (2. Second note of chapter \(number).) Tj "
            + "1 0 0 1 60 664 Tm (3. Third note of chapter \(number).) Tj ET"
    }
    let source = dir.appendingPathComponent("chapters.pdf")
    let page = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 7 0 R >> >> /Contents "
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 8 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R] /Count 4 >>",
        page + "12 0 R >>", page + "13 0 R >>", page + "14 0 R >>", page + "15 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Outlines /First 9 0 R /Last 10 0 R /Count 2 >>",
        "<< /Title (1 ALPHA) /Parent 8 0 R /Next 10 0 R /Dest [3 0 R /Fit] >>",
        "<< /Title (2 BE TA) /Parent 8 0 R /Prev 9 0 R /Dest [4 0 R /Fit] >>",
        "<< >>",
        testPDFStream(chapterPage(1, title: "ALPHA")), testPDFStream(chapterPage(2, title: "BETA")),
        testPDFStream(notesPage(1)), testPDFStream(notesPage(2)),
    ]).write(to: source)
    let output = dir.appendingPathComponent("chapters.epub")
    let report = try await PDFConverter().convert(from: source, to: output, options: ConversionOptions())
    #expect(report.pageCount == 4)
    let archive = try Archive(url: output, accessMode: .read)
    #expect(archive.filter { $0.path.hasPrefix("EPUB/chapter-") }.count == 1)
    var data = Data()
    _ = try archive.extract(try #require(archive["EPUB/chapter-1.xhtml"])) { data += $0 }
    let html = String(decoding: data, as: UTF8.self)
    for chapter in 1...2 {
        #expect(html.contains("Chapter \(chapter) body cites its first note<sup><a epub:type=\"noteref\" role=\"doc-noteref\" id=\"noteref-c\(chapter)-1\" href=\"#note-c\(chapter)-1\">1</a></sup> and its second<sup><a epub:type=\"noteref\" role=\"doc-noteref\" id=\"noteref-c\(chapter)-2\" href=\"#note-c\(chapter)-2\">2</a></sup> here."), "\(html)")
        #expect(html.contains("<p id=\"note-c\(chapter)-1\" epub:type=\"endnote\"><a href=\"#noteref-c\(chapter)-1\" role=\"doc-backlink\" epub:type=\"backlink\">1.</a> First note of chapter \(chapter) with enough words to wrap and a dedented continuation line.</p>"))
        #expect(html.contains("<p>3. Third note of chapter \(chapter).</p>"))
    }
    #expect(html.components(separatedBy: "role=\"doc-noteref\"").count - 1 == 4)
    #expect(html.components(separatedBy: "role=\"doc-backlink\"").count - 1 == 4)
    let candidates = try ChapterBoundaryReader.read(source, scheme: .numbered)
    #expect(candidates == [.init(number: 1, title: "ALPHA", page: 1, scheme: .numbered),
                           .init(number: 2, title: "BE TA", page: 2, scheme: .numbered)])
    #expect(try ChapterBoundaryReader.read(source).isEmpty)
}

@Test func numberedChapterMatchesNeedABareNumeralLineAndIgnoreSpacing() {
    func page(_ texts: [String]) -> PageContent {
        PageContent(number: 5, bounds: CGRect(x: 0, y: 0, width: 400, height: 600), lines: texts.enumerated().map {
            TextLine(text: $0.element, rect: CGRect(x: 40, y: 560 - Double($0.offset) * 30, width: 200, height: 20), fontSize: 20)
        }, graphics: [])
    }
    let candidate = ChapterBoundaryReader.Candidate(number: 5, title: "AL QAEDA AIMS ATTHE AMERICAN HOMELAND", page: 5, scheme: .numbered)
    #expect(ChapterBoundaryReader.matches(candidate, page: page(["5", "AL QAEDA AIMS AT THE", "AMERICAN HOMELAND"])))
    #expect(ChapterBoundaryReader.matches(candidate, page: page(["5", "Al Qaeda Aims at the American Homeland"])))
    #expect(!ChapterBoundaryReader.matches(candidate, page: page(["Part 5", "AL QAEDA AIMS AT THE", "AMERICAN HOMELAND"])))
    #expect(!ChapterBoundaryReader.matches(candidate, page: page(["5", "AL QAEDA AIMS AT THE"])))
    #expect(!ChapterBoundaryReader.matches(candidate, page: page(["6", "AL QAEDA AIMS AT THE", "AMERICAN HOMELAND"])))
    let labelled = ChapterBoundaryReader.Candidate(number: 5, title: "AL QAEDA AIMS ATTHE AMERICAN HOMELAND", page: 5)
    #expect(!ChapterBoundaryReader.matches(labelled, page: page(["Chapter 5", "AL QAEDA AIMS AT THE", "AMERICAN HOMELAND"])))
    #expect(ChapterBoundaryReader.matches(labelled, page: page(["Chapter 5", "AL QAEDA AIMS ATTHE", "AMERICAN HOMELAND"])))
}
