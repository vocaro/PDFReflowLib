import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func footnoteBlocks(_ page: PageContent, images: [(CGRect, String)] = [],
                            continuesNote: Bool = false) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: LayoutReconstructor.vocabulary(in: [page]),
        warnings: &warnings, continuesNote: continuesNote)
}

/// A source page with its native styles and, as the pipeline strips them before layout,
/// without the running-head rows in the outer fifth of the page.
private func slipOpinionPage(_ name: String) throws -> PageContent {
    var page = try SourceLayoutFixture.load(name).styledContent()
    page.lines.removeAll { $0.rect.midY > page.bounds.minY + page.bounds.height * 0.8 }
    return page
}

private func normalized(_ value: String) -> String {
    value.filter { !$0.isWhitespace && $0 != "-" && $0 != "\u{00ad}" }
}

private func marked(_ marker: String, _ text: String) -> InlineText {
    InlineText(elements: [.text(marker + " ", .superscript), .text(text, [])])
}

private func footnotePage(separator: String = "——————", noteSize: Double = 9, marker: Bool = true,
                          bodyLines: Int = 4) -> PageContent {
    var lines: [TextLine] = []
    for i in 0..<bodyLines {
        lines.append(TextLine(text: "Body prose line \(i + 1) fills the measure of the column here.",
            rect: CGRect(x: 100, y: 700 - Double(i) * 13, width: 300, height: 13), fontSize: 11))
    }
    lines.append(TextLine(text: separator, rect: CGRect(x: 100, y: 640, width: 54, height: 11), fontSize: 9))
    lines.append(TextLine(content: marker ? marked("1", "First note wraps onto") : InlineText("First note wraps onto"),
        rect: CGRect(x: 109, y: 629, width: 291, height: 11), fontSize: marker ? 6 : noteSize))
    lines.append(TextLine(text: "a second line.", rect: CGRect(x: 100, y: 618, width: 80, height: 11), fontSize: noteSize))
    lines.append(TextLine(content: marked("2", "Second note."), rect: CGRect(x: 109, y: 607, width: 200, height: 11), fontSize: 6))
    if noteSize != 9 { for i in lines.indices where lines[i].fontSize == 6 { lines[i].fontSize = noteSize } }
    return PageContent(number: 5, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func sourceGorsuchFootnoteSeparatesFromBodyWithoutTheSeparator() throws {
    let page = try slipOpinionPage("loper-60")
    let blocks = footnoteBlocks(page)
    let notes = blocks.filter(\.isFootnote)
    #expect(notes.count == 1)
    let note = try #require(notes.first)
    #expect(note.text.hasPrefix("2 See also A. Scalia, Judicial Deference to Administrative Interpretations of Law"))
    #expect(note.text.hasSuffix("as a kind of legal fiction”)."))
    guard case let .footnote(text) = note.content else { return }
    #expect(text.elements.first == .text("2", .superscript))
    #expect(blocks.last?.isFootnote == true)
    #expect(!blocks.contains { $0.text.contains("——") })
    let body = try #require(blocks.first { $0.text.contains("that controls.") })
    #expect(body.text.hasSuffix("But it is Congress’s view of “good government,” not ours, that controls."))
    #expect(body.text.contains("make[s] for good government.” Ibid.2 But in our democracy unelected judges"))
    #expect(!body.isFootnote)
    // Every source character except the separator survives, in source order.
    let source = page.lines.filter { !FootnoteDetector.isSeparator($0) }.map(\.text).joined()
    #expect(normalized(blocks.map(\.text).joined()) == normalized(source))
}

@Test func sourceKaganFootnoteContinuesAcrossThePageBeforeTheNextNote() throws {
    let first = try slipOpinionPage("loper-97"), second = try slipOpinionPage("loper-98")
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(footnoteBlocks(first), page: first, previousPage: nil,
        to: &blocks, vocabulary: [], warnings: &warnings)
    let start = try #require(blocks.last)
    #expect(start.isFootnote && start.text.hasPrefix("2 The majority tries to buttress its argument"))
    #expect(start.text.hasSuffix("that questions of law are for courts"))
    #expect(blocks.first { $0.text.contains("spect it”).2") }?.text.hasSuffix("spect it”).2") == true)
    let secondBlocks = footnoteBlocks(second, continuesNote: blocks.last?.isFootnote == true)
    #expect(secondBlocks.filter(\.isFootnote).count == 2)
    #expect(secondBlocks.first?.text.hasPrefix("Section 706’s references to standards of review") == true)
    LayoutReconstructor.appendPage(secondBlocks, page: second, previousPage: first,
        to: &blocks, vocabulary: [], warnings: &warnings)
    LayoutReconstructor.joinContinuedFootnote(&blocks, page: 98, vocabulary: [], warnings: &warnings)
    let notes = blocks.filter(\.isFootnote)
    #expect(notes.count == 2)
    let continued = notes[0]
    #expect(continued.page == 97 && continued.sourcePages == [98])
    #expect(continued.text.contains("questions of law are for courts rather than agencies to decide in the last analysis.”"))
    #expect(continued.text.hasSuffix("independent review of agency action using a deferential standard."))
    #expect(notes[1].text.hasPrefix("3 In a footnote responding to the last two paragraphs"))
    #expect(notes[1].text.hasSuffix("the majority repairs only to history."))
    // The page boundary moved inside the note; the page's body follows the completed note.
    #expect(blocks.flatMap(\.sourcePages) == [97, 98])
    let noteIndex = try #require(blocks.firstIndex { $0.isFootnote })
    let bodyIndex = try #require(blocks.firstIndex { $0.text.hasPrefix("Section 706’s references") })
    let lastIndex = try #require(blocks.lastIndex { $0.isFootnote })
    #expect(noteIndex < bodyIndex && bodyIndex < lastIndex)
    #expect(blocks[bodyIndex].text.hasSuffix("nor forbids Chevron-style deference. Vermeule 207.3"))
    #expect(!blocks[bodyIndex].text.contains("rather than agencies"))
    #expect(!blocks.contains { $0.text.contains("——") })
}

/// Page 100 holds only the end of page 99's footnote 4; page 99 holds the end of page 98's
/// footnote 3 and then footnote 4. Without a preceding note, neither page has footnotes.
@Test(arguments: [("loper-100", "(Dickinson); ante, at", 1, nil),
                  ("loper-99", "But as I will explain below, the majority also gets wrong", 2, "4 I concede one exception")])
func sourceContinuationNeedsAPrecedingNote(name: String, opening: String, count: Int, next: String?) throws {
    let page = try slipOpinionPage(name)
    let plain = footnoteBlocks(page)
    #expect(!plain.contains { $0.isFootnote })
    #expect(normalized(plain.map(\.text).joined()) == normalized(page.lines.map(\.text).joined()))
    let continued = footnoteBlocks(page, continuesNote: true).filter(\.isFootnote)
    #expect(continued.count == count)
    #expect(continued.first?.text.hasPrefix(opening) == true)
    guard case let .footnote(text)? = continued.first?.content else { return }
    #expect(FootnoteDetector.marker(of: text) == nil)
    if let next {
        #expect(continued.last?.text.hasPrefix(next) == true)
        #expect(continued.first?.text.hasSuffix("See infra, at 19–23.") == true)
    }
}

@Test func sourceDetachedBodyMarkerRejoinsItsLineAsASuperscript() throws {
    let page = try slipOpinionPage("loper-13")
    let blocks = footnoteBlocks(page)
    let body = try #require(blocks.first { $0.text.hasPrefix("Petitioners Relentless Inc., Huntress Inc.") })
    guard case let .paragraph(text) = body.content else { Issue.record("Body must stay a paragraph"); return }
    #expect(text.elements.contains(.text("1", .superscript)))
    #expect(body.text.contains("the F/V Relentless and the F/V Persistence.1 These vessels use small-mesh"))
    #expect(body.text.hasSuffix("(about 10 to 14 days, as"))
    #expect(!blocks.contains { $0.text == "1" })
    let note = try #require(blocks.last)
    #expect(note.isFootnote)
    #expect(note.text.hasPrefix("1 For any landlubbers, “F/V” is simply the designation for a fishing ves"))
    #expect(blocks.filter(\.isFootnote).count == 1)
}

/// The body paragraph that ends page 13 above its footnote continues on page 14 (#45): the
/// note is stepped over and follows the joined paragraph, after its marker `Persistence.1`.
@Test func sourceBodyParagraphContinuesAcrossThePageBottomFootnote() throws {
    let first = try slipOpinionPage("loper-13"), second = try slipOpinionPage("loper-14")
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(footnoteBlocks(first), page: first, previousPage: nil,
        to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks.last?.isFootnote == true)
    let secondBlocks = footnoteBlocks(second, continuesNote: true)
    #expect(!secondBlocks.contains { $0.isFootnote })
    LayoutReconstructor.appendPage(secondBlocks, page: second, previousPage: first,
        to: &blocks, vocabulary: [], warnings: &warnings)
    LayoutReconstructor.joinContinuedFootnote(&blocks, page: 14, vocabulary: [], warnings: &warnings)
    let joined = try #require(blocks.first { $0.text.contains("(about 10 to 14 days, as opposed to the more typical 2 to 4).") })
    guard case .paragraph = joined.content else { Issue.record("Body must stay a paragraph"); return }
    #expect(joined.sourcePages == [14] && joined.page == 13)
    #expect(joined.text.hasPrefix("Petitioners Relentless Inc., Huntress Inc."))
    #expect(blocks.flatMap(\.sourcePages) == [13, 14])
    let noteIndex = try #require(blocks.firstIndex { $0.isFootnote })
    let joinedIndex = try #require(blocks.firstIndex { $0 == joined })
    #expect(noteIndex == joinedIndex + 1)
    #expect(blocks.filter { $0.isFootnote }.count == 1)
    #expect(blocks[noteIndex].text.hasPrefix("1 For any landlubbers") && blocks[noteIndex].page == 13)
    // Page 14's remaining paragraphs follow the note.
    #expect(blocks[(noteIndex + 1)...].allSatisfy { $0.page == 14 && !$0.isFootnote })
}

/// A page that is one continuing paragraph leaves the previous page's footnote as the last
/// block; the next page's paragraph still finds the joined paragraph past it, and the
/// footnote ends up after the whole chain, behind its marker.
@Test func bodyParagraphChainsAcrossPagesPastAMovedFootnote() {
    func page(_ number: Int, opening: String, note: Bool) -> PageContent {
        var lines: [TextLine] = []
        let words = ["\(opening) prose that fills the whole measure of the column on page \(number) and",
                     "keeps going with more ordinary words across the whole measure of the column and",
                     "still more ordinary words to fill the measure of the column once again and",
                     "the final line also fills the measure of this justified column without an end"]
        for (i, text) in words.enumerated() {
            lines.append(TextLine(text: text + (i == 1 && number == 1 ? "" : ""),
                rect: CGRect(x: 100, y: 700 - Double(i) * 13, width: 300, height: 13), fontSize: 11))
        }
        if number == 1 { lines[1] = TextLine(content: InlineText(elements: [.text("keeps going with more ordinary words across the whole measure", []), .text("1", .superscript), .text(" of the column and", [])]), rect: lines[1].rect, fontSize: 11) }
        if note {
            lines.append(TextLine(text: "——————", rect: CGRect(x: 100, y: 640, width: 54, height: 11), fontSize: 9))
            lines.append(TextLine(content: marked("1", "A note on page \(number)."), rect: CGRect(x: 109, y: 629, width: 200, height: 11), fontSize: 6))
        }
        return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    }
    let pages = [page(1, opening: "Opening", note: true), page(2, opening: "continuing", note: false), page(3, opening: "ending", note: false)]
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    var previous: PageContent?
    for current in pages {
        let pageBlocks = footnoteBlocks(current, continuesNote: previous != nil && blocks.last?.isFootnote == true)
        LayoutReconstructor.appendPage(pageBlocks, page: current, previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
        if previous != nil { LayoutReconstructor.joinContinuedFootnote(&blocks, page: current.number, vocabulary: [], warnings: &warnings) }
        previous = current
    }
    #expect(blocks.count == 3)
    #expect(blocks[0].content == .sourcePage(1))
    #expect(blocks[1].sourcePages == [2, 3] && blocks[1].page == 1)
    #expect(blocks[1].text.hasPrefix("Opening prose") && blocks[1].text.contains("without an end continuing prose")
        && blocks[1].text.contains("without an end ending prose"))
    #expect(blocks[2].isFootnote && blocks[2].text == "1 A note on page 1." && blocks[2].page == 1)
    #expect(blocks.flatMap(\.sourcePages) == [1, 2, 3])
}

/// A marker-less note after a body join finds its start ahead of the joined paragraph; the
/// page boundary already sits in that paragraph, so the note carries none.
@Test func continuedFootnoteJoinsAfterABodyJoinWithoutASecondBoundary() {
    let start = ReflowBlock(content: .footnote(InlineText(elements: [.text("1", .superscript), .text(" Note begins", [])])), page: 1)
    let body = ReflowBlock(content: .paragraph(InlineText(elements: [.text("body continues", []), .sourcePage(2), .text(" here.", [])])), page: 1)
    let rest = ReflowBlock(content: .footnote(InlineText("and ends.")), page: 2)
    let next = ReflowBlock(content: .footnote(InlineText(elements: [.text("2", .superscript), .text(" Second.", [])])), page: 2)
    var warnings: [ConversionWarning] = []
    var blocks = [ReflowBlock(content: .sourcePage(1), page: 1), start, body, rest, next]
    LayoutReconstructor.joinContinuedFootnote(&blocks, page: 2, vocabulary: [], warnings: &warnings)
    #expect(blocks.map(\.text) == ["", "1 Note begins and ends.", "body continues here.", "2 Second."])
    #expect(blocks.flatMap(\.sourcePages) == [1, 2])
    // With the standalone boundary present, it moves inside the note instead.
    blocks = [ReflowBlock(content: .sourcePage(1), page: 1), start, ReflowBlock(content: .sourcePage(2), page: 2),
              ReflowBlock(content: .paragraph(InlineText("Body.")), page: 2), rest, next]
    LayoutReconstructor.joinContinuedFootnote(&blocks, page: 2, vocabulary: [], warnings: &warnings)
    #expect(blocks.map(\.text) == ["", "1 Note begins and ends.", "Body.", "2 Second."])
    #expect(blocks[1].sourcePages == [2] && blocks.flatMap(\.sourcePages) == [1, 2])
    // A marked first note, or a start two pages back, is not a continuation.
    for controls in [[ReflowBlock(content: .sourcePage(1), page: 1), start, ReflowBlock(content: .sourcePage(2), page: 2), next],
                     [ReflowBlock(content: .sourcePage(1), page: 1), start, ReflowBlock(content: .sourcePage(2), page: 2),
                      ReflowBlock(content: .sourcePage(3), page: 3), ReflowBlock(content: .footnote(InlineText("stray.")), page: 3)]] {
        var unchanged = controls
        LayoutReconstructor.joinContinuedFootnote(&unchanged, page: controls.last!.page, vocabulary: [], warnings: &warnings)
        #expect(unchanged == controls)
    }
}

@Test(arguments: ["loper-61", "loper-101"])
func sourceSingleFootnotePagesKeepBodyAndOneNote(name: String) throws {
    let page = try slipOpinionPage(name)
    let blocks = footnoteBlocks(page)
    let notes = blocks.filter(\.isFootnote)
    #expect(notes.count == 1)
    #expect(blocks.last?.isFootnote == true)
    guard case let .footnote(text)? = notes.first?.content else { return }
    #expect(FootnoteDetector.marker(of: text) != nil)
    #expect(!blocks.contains { $0.text.contains("——") })
    let source = page.lines.filter { !FootnoteDetector.isSeparator($0) }.map(\.text).joined()
    #expect(normalized(blocks.map(\.text).joined()) == normalized(source))
}

@Test(arguments: ["loper-96", "loper-2", "loper-7", "911-20", "911-472", "911-532", "algebra-26",
                  "faa-211", "fed-45", "flag-27", "warren-910", "nbs-7", "usgs-1"])
func pagesWithoutASeparatorAndNoteTypographyHaveNoFootnotes(name: String) throws {
    let page = try SourceLayoutFixture.load(name).styledContent()
    let elements = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    #expect(FootnoteDetector.layout(in: elements, page: page, continuesNote: false) == nil)
    #expect(FootnoteDetector.layout(in: elements, page: page, continuesNote: true) == nil)
    #expect(!footnoteBlocks(page).contains { $0.isFootnote })
}

@Test func syntheticFootnotesRequireSeparatorSizeDropAndSequentialMarkers() {
    let notes = footnoteBlocks(footnotePage()).filter(\.isFootnote)
    #expect(notes.map(\.text) == ["1 First note wraps onto a second line.", "2 Second note."])
    let continued = footnoteBlocks(footnotePage(marker: false), continuesNote: true).filter(\.isFootnote)
    #expect(continued.map(\.text) == ["First note wraps onto a second line.", "2 Second note."])
    var controls: [PageContent] = [
        footnotePage(noteSize: 11),
        footnotePage(noteSize: 10.5),
        footnotePage(marker: false),
        footnotePage(separator: "* * *"),
        footnotePage(separator: "——"),
        footnotePage(bodyLines: 2),
    ]
    var page = footnotePage(); page.lines[7] = TextLine(content: marked("3", "Second note."), rect: page.lines[7].rect, fontSize: 6); controls.append(page)
    page = footnotePage(); page.lines[7] = TextLine(content: InlineText(elements: [.text("a ", .superscript), .text("Second note.", [])]), rect: page.lines[7].rect, fontSize: 6)
    page.lines[5] = TextLine(content: InlineText(elements: [.text("x ", .superscript), .text("First note wraps onto", [])]), rect: page.lines[5].rect, fontSize: 6); controls.append(page)
    page = footnotePage(); page.lines[6].fontSize = 11; controls.append(page)
    page = footnotePage(); page.lines[6].monospaced = true; controls.append(page)
    page = footnotePage(); page.lines[6].structure = .init(group: 3, order: 0, headingLevel: 0, lineCount: 1); controls.append(page)
    page = footnotePage(); page.lines[6].rect.origin.y -= 20; controls.append(page)
    page = footnotePage(); page.lines[6].rect.origin.x = 60; controls.append(page)
    page = footnotePage(); page.lines[7].rect.origin.x = 160; controls.append(page)
    page = footnotePage(); page.recognized = true; controls.append(page)
    page = footnotePage(); page.hasSyntheticTextStyle = true; controls.append(page)
    page = footnotePage(); page.lines.append(TextLine(text: "Later body prose at full size returns.", rect: CGRect(x: 100, y: 590, width: 300, height: 13), fontSize: 11)); controls.append(page)
    page = footnotePage(); page.lines.insert(TextLine(text: "——————", rect: CGRect(x: 100, y: 596, width: 54, height: 11), fontSize: 9), at: 7); controls.append(page)
    for (index, control) in controls.enumerated() {
        let blocks = footnoteBlocks(control)
        #expect(!blocks.contains { $0.isFootnote }, "control \(index)")
        // Displaced lines reorder; every character must still be present.
        #expect(normalized(blocks.map(\.text).joined()).sorted() == normalized(control.lines.map(\.text).joined()).sorted(),
            "control \(index): \(blocks.map(\.text))")
    }
    // An image below the notes is not part of a note block either.
    let image = footnoteBlocks(footnotePage(), images: [(CGRect(x: 100, y: 560, width: 200, height: 30), "figure")])
    #expect(!image.contains { $0.isFootnote })
    #expect(image.contains { if case .image = $0.content { true } else { false } })
}

@Test func syntheticDetachedMarkerNeedsSmallDigitsAtTheLineEnd() {
    func page(marker: String = "1", size: Double = 7, x: Double = 455.9, y: Double = 247.1) -> PageContent {
        PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
            TextLine(text: "Petitioners own two vessels that operate in the Atlantic herring", rect: CGRect(x: 156.2, y: 256.5, width: 299.5, height: 13.2), fontSize: 11),
            TextLine(text: "fishery: the F/V Relentless and the F/V Persistence.", rect: CGRect(x: 156.2, y: 243.3, width: 299.5, height: 13.2), fontSize: 11),
            TextLine(text: marker, rect: CGRect(x: x, y: y, width: 3.9, height: 8.4), fontSize: size),
            TextLine(text: "These vessels use small-mesh bottom-trawl gear and can", rect: CGRect(x: 156.2, y: 230.1, width: 299.6, height: 13.2), fontSize: 11),
        ], graphics: [])
    }
    let joined = footnoteBlocks(page())
    #expect(joined.count == 1)
    guard case let .paragraph(text)? = joined.first?.content else { Issue.record("Paragraph expected"); return }
    #expect(text.elements.contains(.text("1", .superscript)))
    #expect(joined[0].text == "Petitioners own two vessels that operate in the Atlantic herring fishery: the F/V Relentless and the F/V Persistence.1 These vessels use small-mesh bottom-trawl gear and can")
    for control in [page(marker: "a"), page(marker: "1234"), page(size: 11), page(x: 470), page(x: 440), page(y: 225)] {
        let blocks = footnoteBlocks(control)
        #expect(blocks.contains { $0.text == control.lines[2].text })
        #expect(!blocks.contains { block in
            if case let .paragraph(text) = block.content { return text.elements.contains { if case .text(_, let style) = $0 { style.contains(.superscript) } else { false } } }
            return false
        })
    }
}

@Test func footnoteBlocksSerializeAsVisibleNoteDivisions() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = ReflowDocument(metadata: .init(title: "Notes", language: "en"), blocks: [
        ReflowBlock(content: .sourcePage(1), page: 1),
        ReflowBlock(content: .paragraph(InlineText("Body & prose.")), page: 1),
        ReflowBlock(content: .footnote(InlineText(elements: [.text("1", .superscript), .text(" Note <text>.", []),
            .sourcePage(2), .text(" continued.", .italic)])), page: 1),
    ], assets: [])
    let output = try await EPUBWriter.write(book, maximumOutputBytes: .max, directory: dir) { _ in }
    let archive = try Archive(url: output, accessMode: .read)
    func entry(_ path: String) throws -> String {
        var data = Data()
        let item = try #require(archive[path])
        _ = try archive.extract(item) { data += $0 }
        return String(decoding: data, as: UTF8.self)
    }
    let html = try entry("EPUB/chapter-1.xhtml")
    let css = try entry("EPUB/style.css")
    let nav = try entry("EPUB/nav.xhtml")
    #expect(html.contains("<p>Body &amp; prose.</p>\n<div class=\"footnote\" role=\"doc-footnote\"><p><sup>1</sup> Note &lt;text&gt;."
        + "<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-2\" aria-label=\"2\"/><em> continued.</em></p></div>"))
    #expect(!html.contains("<aside"))
    #expect(css.contains("div.footnote { font-size: 0.85em; }"))
    #expect(nav.contains("#page-2\">2</a>"))
}

@Test func publicConversionSeparatesAndJoinsPageBottomFootnotes() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("footnotes.pdf")
    let body = (0..<4).map { i in
        "1 0 0 1 100 \(700 - i * 13) Tm (Body prose line \(i + 1) fills the measure of the column here.) Tj "
    }.joined()
    let first = "BT /F1 11 Tf " + body + "/F1 9 Tf 1 0 0 1 100 640 Tm (------) Tj "
        + "1 0 0 1 109 629 Tm /F1 6 Tf 2.5 Ts (1 ) Tj 0 Ts /F1 9 Tf (First note wraps onto) Tj "
        + "1 0 0 1 100 618 Tm (a second line that) Tj ET"
    let second = "BT /F1 11 Tf " + body + "/F1 9 Tf 1 0 0 1 100 640 Tm (------) Tj "
        + "1 0 0 1 100 629 Tm (continues on the next page.) Tj "
        + "1 0 0 1 109 618 Tm /F1 6 Tf 2.5 Ts (2 ) Tj 0 Ts /F1 9 Tf (Second note.) Tj ET"
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", testPDFStream(first), testPDFStream(second),
    ]).write(to: source)
    let output = dir.appendingPathComponent("footnotes.epub")
    let report = try await PDFConverter().convert(from: source, to: output, options: ConversionOptions())
    let archive = try Archive(url: output, accessMode: .read)
    var data = Data()
    _ = try archive.extract(try #require(archive["EPUB/chapter-1.xhtml"])) { data += $0 }
    let html = String(decoding: data, as: UTF8.self)
    #expect(report.pageCount == 2)
    #expect(!html.contains("------"), "\(html)")
    #expect(html.contains("<div class=\"footnote\" role=\"doc-footnote\"><p><sup>1</sup> First note wraps onto a second line that "
        + "<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-2\" aria-label=\"2\"/>continues on the next page.</p></div>"), "\(html)")
    #expect(html.contains("<div class=\"footnote\" role=\"doc-footnote\"><p><sup>2</sup> Second note.</p></div>"))
    #expect(html.components(separatedBy: "id=\"page-2\"").count == 2)
    #expect(html.components(separatedBy: "<p>Body prose line 1 fills the measure of the column here. Body prose line 2").count == 3)
    #expect(html.range(of: "continues on the next page.</p></div>\n<p>Body prose line 1") != nil)
}
