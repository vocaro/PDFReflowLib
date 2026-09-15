// Rejected experiment: copy to Tests/PDFReflowLibTests only when reproducing the candidate.
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

@Test func sourceEndnoteMarkerRetainsNativeSuperscriptEvidence() throws {
    let fixture = try SourceLayoutFixture.load("911-20")
    let source = try #require(fixture.attributedLines.first { $0.text.contains("7:45.") })
    #expect(EPUBTextEncoder.inline(NativeTextReader.inlineText(from: source.attributedString()))
        .contains("7:45.<sup>4</sup>"))
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

@Test func numberedNotesRefuseImagesAndPreserveOtherDocumentLayouts() throws {
    let page = notePage()
    let elements = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    var interrupted = elements
    interrupted.insert(.init(rect: CGRect(x: 40, y: 680, width: 400, height: 2), image: "barrier"), at: 3)
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
    var warnings: [ConversionWarning] = [], blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(noteBlocks(first), page: first, previousPage: nil,
        to: &blocks, vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(noteBlocks(second), page: second, previousPage: first,
        to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks.flatMap(\.sourcePages) == [1, 2])
    #expect(blocks.filter { $0.text.hasPrefix("39.") }.map(\.page) == [1, 2])
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
        var data = Data()
        _ = try archive.extract(try #require(archive["EPUB/chapter-1.xhtml"])) { data += $0 }
        let html = String(decoding: data, as: UTF8.self)
        #expect(html.components(separatedBy: "<p>39.Second citation begins with sufficient text to wrap and continues on the following line.</p>").count - 1 == 3)
        #expect(html.contains("NOTES TO CHAPTER 1") == !remove)
        #expect(report.pageCount == 3)
        for number in 1...3 { #expect(html.contains("id=\"page-\(number)\"")) }
    }
}
