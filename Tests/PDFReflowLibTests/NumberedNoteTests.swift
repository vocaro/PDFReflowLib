import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func noteBlocks(_ page: PageContent, images: [(CGRect, String)] = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
}

private func notePage() -> PageContent {
    func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 400) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 10), fontSize: 10)
    }
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
        line("NOTES TO CHAPTER 1", 40, 754, 180),
        line("38. First source citation.", 60, 700, 200),
        line("39.Second citation begins with sufficient text to wrap", 60, 688),
        line("and continues on the following line.", 40, 676),
        line("40. Third source citation.", 60, 664, 200),
    ], graphics: [])
}

@Test func sourceNumberedNotesKeepTheirNumberAndAllContinuationLines() throws {
    let page = try SourceLayoutFixture.load("911-472").content()
    let blocks = noteBlocks(page)
    for number in 38...54 {
        let start = try #require(page.lines.firstIndex { $0.text.hasPrefix("\(number).") })
        let end = page.lines[(start + 1)...].firstIndex { $0.text.hasPrefix("\(number + 1).") } ?? page.lines.endIndex
        let note = try #require(blocks.first { $0.text.hasPrefix("\(number).") })
        guard case .paragraph = note.content else {
            Issue.record("Note \(number) must reflow as a paragraph"); continue
        }
        // Compare every source line, allowing only the established line-wrap hyphen repair.
        var warnings: [ConversionWarning] = []
        let expected = page.lines[(start + 1)..<end].reduce(page.lines[start].text) {
            LayoutReconstructor.join($0, $1.text, vocabulary: [], page: page.number, warnings: &warnings)
        }
        #expect(note.text == expected)
    }
}
@Test func numberedNoteRecognitionRequiresHeadingSequenceAndContinuationGeometry() {
    let original = notePage()
    #expect(noteBlocks(original).contains { $0.text == "39.Second citation begins with sufficient text to wrap and continues on the following line." })
    var controls: [PageContent] = []
    var page = original; page.lines.removeFirst(); controls.append(page)
    page = original; page.recognized = true; controls.append(page)
    page = original; page.hasSyntheticTextStyle = true; controls.append(page)
    page = original; page.lines[0].rect.origin.y = 600; controls.append(page)
    page = original; page.lines.removeLast(); controls.append(page)
    page = original; page.lines[4] = TextLine(text: "42. Nonsequential citation.", rect: page.lines[4].rect, fontSize: 10); controls.append(page)
    page = original; page.lines[3].rect.origin.x = 80; controls.append(page)
    page = original; page.lines[3].fontSize = 20; controls.append(page)
    page = original; page.lines[3].rect.origin.y -= 20; controls.append(page)
    page = original; page.lines[2].wraps = false; controls.append(page)
    page = original; page.lines[3].monospaced = true; controls.append(page)
    page = original; page.lines[3].structure = .init(group: 7, order: 0, headingLevel: 0, lineCount: 1); controls.append(page)
    for control in controls {
        #expect(noteBlocks(control).contains { block in
            if case .preformatted = block.content { return block.text.hasPrefix("38.") }
            return false
        })
    }
}

/// A page where one chapter's notes end and the next chapter's begin is headed for both
/// chapters, and is a notes page like any other (#292).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func aPageHeadedForTwoChaptersNotesIsANotesPage() {
    func headed(_ text: String) -> PageContent {
        var page = notePage()
        page.lines[0] = TextLine(text: text, rect: page.lines[0].rect, fontSize: 10)
        return page
    }
    for text in ["NOTES TO CHAPTERS 9-10", "554 NOTES TO CHAPTERS 9-10", "NOTES TO CHAPTERS 10–11 560"] {
        #expect(NumberedNoteDetector.hasHeading(on: headed(text)), Comment(rawValue: text))
    }
    for text in ["NOTES TO CHAPTERS 9", "NOTES TO CHAPTERS 9-", "NOTES TO CHAPTERS 0-1", "NOTES TO CHAPTER 9-10",
                 "NOTES TO CHAPTERS 9-10-11", "NOTES TO CHAPTERS 9-10 AND MORE"] {
        #expect(!NumberedNoteDetector.hasHeading(on: headed(text)), Comment(rawValue: text))
    }
}

@Test func numberedNotesRefuseImagesAndPreserveOtherDocumentLayouts() throws {
    let page = notePage()
    let elements = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    var interrupted = elements
    interrupted.insert(.init(rect: CGRect(x: 40, y: 680, width: 400, height: 2), image: "barrier"), at: 3)
    #expect(NumberedNoteDetector.groups(in: interrupted, page: page).isEmpty)
    interrupted = elements
    interrupted.insert(.init(rect: CGRect(x: 40, y: 720, width: 400, height: 2), image: "barrier"), at: 1)
    #expect(NumberedNoteDetector.groups(in: interrupted, page: page).isEmpty)
    // Source page 473 has a second indented paragraph inside note 66. Refuse the
    // unsupported page instead of merging that paragraph or inventing a new note.
    let multiParagraph = try SourceLayoutFixture.load("911-473").content()
    #expect(NumberedNoteDetector.hasHeading(on: multiParagraph))
    #expect(NumberedNoteDetector.groups(in: multiParagraph.lines.map {
        .init(rect: $0.rect, line: $0)
    }, page: multiParagraph).isEmpty)
    for name in ["algebra-26", "faa-211", "911-451", "warren-910", "flag-27", "fed-45"] {
        let control = try SourceLayoutFixture.load(name).content()
        #expect(!NumberedNoteDetector.hasHeading(on: control))
        #expect(NumberedNoteDetector.groups(in: control.lines.map {
            .init(rect: $0.rect, line: $0)
        }, page: control).isEmpty)
    }
}

@Test func numberedNoteJoiningPreservesStylesAndDedentedCitationYears() throws {
    var page = notePage()
    let old = page.lines[3]
    page.lines[3] = TextLine(content: InlineText(elements: [.text("2002.Continued H", .italic),
        .text("2", .subscript), .text("O", []), .text("4", .superscript), .text(" citation.", .bold)]),
        rect: old.rect, fontSize: old.fontSize)
    let note = try #require(noteBlocks(page).first { $0.text.hasPrefix("39.") })
    #expect(try EPUBTextEncoder.payload(note, imagePaths: [:]).contains(
        "wrap <em>2002.Continued H</em><sub>2</sub>O<sup>4</sup><strong> citation.</strong>"))
    #expect(!note.text.contains("40."))
}

@Test func repeatedChapterNoteNumbersRemainSeparateAndKeepPageAnchors() {
    let first = notePage()
    var second = notePage(); second.number = 2
    second.lines[0] = TextLine(text: "NOTES TO CHAPTER 2", rect: second.lines[0].rect, fontSize: 10)
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(noteBlocks(first), page: first, previousPage: nil,
        to: &blocks, vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(noteBlocks(second), page: second, previousPage: first,
        to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks.flatMap(\.sourcePages) == [1, 2])
    #expect(blocks.filter { $0.text.hasPrefix("39.") }.map(\.page) == [1, 2])
}

@Test func sourceNumberInsideDedentedNoteTextDoesNotStealOwnership() throws {
    let page = try SourceLayoutFixture.load("911-532").content()
    let blocks = noteBlocks(page)
    let ninth = try #require(blocks.first { $0.text.hasPrefix("9.") })
    let fifth = try #require(blocks.first { $0.text.hasPrefix("5.") })
    #expect(ninth.text.contains("5.This speculation was based"))
    #expect(!fifth.text.contains("This speculation"))
    #expect(blocks.filter { $0.text.hasPrefix("5.") }.count == 1)
    #expect(!ninth.text.contains("10."))
    let starts = page.lines.indices.filter {
        abs(page.lines[$0].rect.minX - 51.66) < 0.1
            && page.lines[$0].text.range(of: "^[0-9]+\\.", options: .regularExpression) != nil
    }
    #expect(starts.count == 11)
    for (offset, start) in starts.enumerated() {
        let end = offset + 1 < starts.count ? starts[offset + 1] : page.lines.endIndex
        var warnings: [ConversionWarning] = []
        let expected = page.lines[(start + 1)..<end].reduce(page.lines[start].text) {
            LayoutReconstructor.join($0, $1.text, vocabulary: [], page: page.number, warnings: &warnings)
        }
        #expect(blocks.contains { $0.text == expected })
    }
}

@Test func sourceCrossPageAndMultiParagraphNotesKeepTextAndBoundaries() throws {
    var first = try SourceLayoutFixture.load("911-472").content()
    var second = try SourceLayoutFixture.load("911-473").content()
    // The public pipeline retains heading evidence before furniture removal.
    first.lines.removeFirst()
    second.lines.removeFirst()
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    for (page, previous) in [(first, Optional<PageContent>.none), (second, first)] {
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [],
            warnings: &warnings, numberedNotePage: true)
        LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: previous,
            to: &blocks, vocabulary: [], warnings: &warnings)
    }
    func normalized(_ value: String) -> String {
        value.filter { !$0.isWhitespace && $0 != "-" && $0 != "\u{00ad}" }
    }
    #expect(normalized(blocks.map(\.text).joined()) == normalized((first.lines + second.lines).map(\.text).joined()))
    #expect(blocks.flatMap(\.sourcePages) == [472, 473])
    let extra = try #require(blocks.first { $0.text.hasPrefix("The FAA knew or strongly suspected") })
    #expect(!extra.text.contains("66.") && !extra.text.contains("67."))
    // Text survives the source 54/55 page transition; this does not claim that
    // numeric-leading continuations have acquired a cross-page note identity.
    #expect(blocks.first { $0.text.hasPrefix("54.") }?.text.contains("55.") == false)
}

@Test func numberedNotesPreserveExistingUnambiguousCrossPageContinuation() throws {
    var first = notePage()
    first.lines[4] = TextLine(text: "40. Third source citation continues", rect: CGRect(x: 60, y: 60, width: 400, height: 10), fontSize: 10)
    // Keep close line spacing while moving the complete note run to the page bottom.
    for i in 1...3 { first.lines[i].rect.origin.y -= 604 }
    var second = notePage(); second.number = 2
    for i in 1...4 {
        let line = second.lines[i]
        second.lines[i] = TextLine(text: line.text.replacingOccurrences(of: "38.", with: "41.")
            .replacingOccurrences(of: "39.", with: "42.").replacingOccurrences(of: "40.", with: "43."),
            rect: line.rect, fontSize: line.fontSize)
    }
    second.lines.insert(TextLine(text: "on the following page.", rect: CGRect(x: 40, y: 724, width: 180, height: 10), fontSize: 10), at: 1)
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    first.lines.removeFirst(); second.lines.removeFirst()
    for (page, previous) in [(first, Optional<PageContent>.none), (second, first)] {
        LayoutReconstructor.appendPage(LayoutReconstructor.blocks(page: page, images: [],
            vocabulary: [], warnings: &warnings, numberedNotePage: true), page: page,
            previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
    }
    let continued = try #require(blocks.first { $0.text.hasPrefix("40.") })
    #expect(continued.text == "40. Third source citation continues on the following page.")
    #expect(continued.sourcePages == [2])
    #expect(blocks.flatMap(\.sourcePages) == [1, 2])
    #expect(!continued.text.contains("41."))
}

@Test func publicConversionKeepsNumberedNotesWithEitherFurnitureOption() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("notes.pdf")
    let stream = "BT /F1 10 Tf 1 0 0 1 40 754 Tm (NOTES TO CHAPTER 1) Tj "
        + "1 0 0 1 60 700 Tm (38. First source citation.) Tj "
        + "1 0 0 1 60 688 Tm (39.Second citation begins with sufficient text to wrap) Tj "
        + "1 0 0 1 40 676 Tm (and continues on the following line.) Tj "
        + "1 0 0 1 60 664 Tm (40. Third source citation.) Tj ET"
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 6 0 R >> >> /Contents 7 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 6 0 R >> >> /Contents 7 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 6 0 R >> >> /Contents 7 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", testPDFStream(stream),
    ]).write(to: source)
    for remove in [true, false] {
        var options = ConversionOptions(); options.removeRepeatedHeadersAndFooters = remove
        let output = dir.appendingPathComponent("notes-\(remove).epub")
        let report = try await PDFConverter().convert(from: source, to: output, options: options)
        let archive = try Archive(url: output, accessMode: .read)
        let html = try archive.chapter()
        #expect(html.components(separatedBy: "<p>39.Second citation begins with sufficient text to wrap and continues on the following line.</p>").count - 1 == 3)
        #expect(html.contains("NOTES TO CHAPTER 1") == !remove)
        #expect(report.pageCount == 3)
        for number in 1...3 { #expect(html.contains("id=\"page-\(number)\"")) }
    }
}
