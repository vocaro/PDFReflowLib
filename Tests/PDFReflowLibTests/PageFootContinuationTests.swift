import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// A paragraph a page leaves open above the notes at its foot carries on at the head of the next
// page, and the notes keep their side of the page boundary (#306). Loper Bright page 76 ends its
// body on `…voiced their own thoughtful and extensive`, prints `——————` and footnote 6 beneath
// it, and page 77 opens `criticisms of Chevron.` The pages here are original content streams in
// that shape: an 11-point body, a rule and a note set in 9-point type, and a number raised in
// the body that the note answers.

/// One printed line: where it starts, its baseline, and its text as content-stream operators
/// that follow a `Tm` placing it there.
private struct Row {
    var x: Double
    var y: Double
    var shows: String

    /// A line of the 11-point body.
    static func body(_ text: String, y: Double, x: Double = 80) -> Row {
        Row(x: x, y: y, shows: "/F1 11 Tf (\(text)) Tj")
    }

    /// A line of the 9-point notes, and the rule above them.
    static func note(_ text: String, y: Double, x: Double = 80) -> Row {
        Row(x: x, y: y, shows: "/F1 9 Tf (\(text)) Tj")
    }
}

/// The 11-point body's leading, and the baselines of the first page's twelve body lines.
private let leading = 13.25
private func bodyBaseline(_ index: Int) -> Double { 280 - Double(index) * leading }

/// The first page: one paragraph that raises the note's number in its fifth line and is still
/// open at the foot of the body, the rule, and the note in six lines. `lastLine` is the body's
/// last line, and `rule` whether the page sets the rule as a line of its own.
private func firstPage(lastLine: String = "voiced their own thoughtful and extensive", rule: Bool = true) -> [Row] {
    let body = [
        "for a time it was applied without much comment by anyone. Its",
        "author later came to doubt the whole enterprise, and he said",
        "so plainly in a short opinion of his own, which many judges",
    ]
    var rows = [Row.body("The rule began as a modest instruction to the courts, and", y: bodyBaseline(0), x: 91)]
    rows += body.enumerated().map { Row.body($0.element, y: bodyBaseline($0.offset + 1)) }
    // The reference: a 7-point `6` raised four points after `humility.`, as a slip opinion
    // raises its note numbers.
    rows.append(Row(x: 80, y: bodyBaseline(4), shows: "/F1 11 Tf (read as a quiet tribute to his humility.) Tj"
        + " /F1 7 Tf 4 Ts (6) Tj /F1 11 Tf 0 Ts ( Other judges were not) Tj"))
    let rest = [
        "far behind him. Over the following decade one after another",
        "raised questions about the rule, asked what it demanded of a",
        "court in practice, and wondered whether any statute had ever",
        "called for it at all. The rule was applied less and less often,",
        "and in the end the court stopped relying on it altogether.",
        "Along the way, an unusually large number of appellate judges",
    ]
    rows += rest.enumerated().map { Row.body($0.element, y: bodyBaseline($0.offset + 5)) }
    rows.append(.body(lastLine, y: bodyBaseline(11)))
    // Beneath the body, the rule and the note, at the 9-point leading of 10.8.
    if rule { rows.append(.note("\\227\\227\\227\\227\\227\\227", y: 116.75)) }
    let note = [
        "judges preferred their own accounts of a statute to its text, and",
        "the rule was meant to discipline that habit. Its author later saw",
        "that it had the right diagnosis but the wrong cure, and he said so",
        "in his later writings, which asked judges to return to the enacted",
        "text rather than defer to anyone else in reading it.",
    ]
    rows.append(.note("6 It should be recalled that when the rule was first announced, many", y: 105.25, x: 89))
    rows += note.enumerated().map { Row.note($0.element, y: 94.45 - Double($0.offset) * 10.8) }
    return rows
}

/// The note's own last words, which nothing the next page prints may follow inside the note.
private let noteEnding = "text rather than defer to anyone else in reading it."

/// The second page's body as a slip opinion continues it: the rest of the sentence, then a new
/// paragraph the page indents.
private let continuation = [
    Row.body("criticisms of the rule, and several state courts declined to", y: bodyBaseline(0)),
    Row.body("adopt it.", y: bodyBaseline(1)),
] + newParagraph(from: 2)

private func newParagraph(from line: Int) -> [Row] {
    [Row.body("Even so, some have argued that the rule should be kept", y: bodyBaseline(line), x: 91)]
        + ["because judges cannot manage without it. That objection is",
           "no answer to the statute that governs how courts review",
           "what agencies do."].enumerated().map { Row.body($0.element, y: bodyBaseline(line + 1 + $0.offset)) }
}

/// Two 460 by 300 pages in Times-Roman under WinAnsiEncoding, where `\227` is the em dash.
private func footnotedPDF(_ first: [Row], _ second: [Row]) -> Data {
    func stream(_ rows: [Row]) -> String {
        testPDFStream(rows.map { "BT 1 0 0 1 \($0.x) \($0.y) Tm \($0.shows) ET" }.joined(separator: "\n"))
    }
    let resources = "/Resources << /Font << /F1 3 0 R /F2 8 0 R >> >>"
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 460 300] \(resources) /Contents 5 0 R >>",
        stream(first),
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 460 300] \(resources) /Contents 7 0 R >>",
        stream(second),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold /Encoding /WinAnsiEncoding >>",
    ])
}

/// The converted book's only spine document and its navigation document.
private func convert(_ first: [Row], _ second: [Row]) async throws -> (chapter: String, navigation: String) {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try footnotedPDF(first, second).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.reflowedPageCount == 2 && report.imageCount == 0)
    let archive = try Archive(url: epub, accessMode: .read)
    #expect(archive["EPUB/chapter-2.xhtml"] == nil)
    return (try archive.chapter(), try archive.entryText("EPUB/nav.xhtml"))
}

private let secondMarker = #"<span epub:type="pagebreak" role="doc-pagebreak" id="page-2" aria-label="2"/>"#

/// The body's blocks in order, one string each — the writer puts each block on a line of its
/// own — with the markup stripped and each page marker written as `[page-N]`.
private func blocks(_ chapter: String) -> [String] {
    let body = chapter.components(separatedBy: "<body")[1]
        .replacingOccurrences(of: "^[^>]*>", with: "", options: .regularExpression)
    return body.components(separatedBy: "\n").map { line in
        line.replacingOccurrences(of: #"<span epub:type="pagebreak"[^>]*id="(page-\d+)"[^>]*/>"#,
                                  with: "[$1]", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
    }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// The aside the note is written as, from its opening tag to its close.
private func noteAside(_ chapter: String) throws -> String {
    let start = try #require(chapter.range(of: #"<aside epub:type="footnote" role="doc-footnote" id="note-fn-1-6">"#))
    let end = try #require(chapter.range(of: "</aside>", range: start.upperBound..<chapter.endIndex))
    return String(chapter[start.lowerBound..<end.upperBound])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aParagraphContinuedPastPageFootNotesJoinsItsContinuation() async throws {
    let (chapter, navigation) = try await convert(firstPage(), continuation)
    // The note is still a footnote the raised 6 links to, and it holds only its own text.
    let aside = try noteAside(chapter)
    #expect(aside.contains("6 It should be recalled that when the rule was first announced"))
    #expect(aside.hasSuffix("\(noteEnding)</p></aside>"))
    #expect(!aside.contains("criticisms"))
    #expect(chapter.contains(#"humility.<a epub:type="noteref" role="doc-noteref" href="chapter-1.xhtml#note-fn-1-6"><sup>6</sup></a>"#))
    // One paragraph runs from page 1 on to page 2, and the page-2 marker stands inside it at the
    // boundary, where the join set it: there is no standalone page-2 marker.
    let joined = "voiced their own thoughtful and extensive \(secondMarker)criticisms of the rule, and several state courts"
    #expect(chapter.contains(joined))
    #expect(chapter.components(separatedBy: #"id="page-2""#).count == 2)
    // The rule and the note keep page 1's side of the boundary: after page 1's marker, before
    // the paragraph that carries page 2's. The indented paragraph after it is page 2's own.
    let order = blocks(chapter)
    #expect(order.count == 4, "\(order)")
    #expect(order.first == "[page-1]——————")
    #expect(order.dropFirst().first?.hasPrefix("6 It should be recalled") == true)
    #expect(order.dropFirst(2).first?.hasPrefix("The rule began as a modest instruction") == true)
    #expect(order.dropFirst(2).first?.hasSuffix(
        "extensive [page-2]criticisms of the rule, and several state courts declined to adopt it.") == true)
    #expect(order.last?.hasPrefix("Even so, some have argued") == true)
    // The page-list still sends a reader to both pages, in the one spine document.
    #expect(navigation.contains(#"<a href="chapter-1.xhtml#page-1">1</a>"#))
    #expect(navigation.contains(#"<a href="chapter-1.xhtml#page-2">2</a>"#))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aParagraphThatEndsBeforeTheNotesDoesNotJoinTheNextPage() async throws {
    // The body's sentence ends with a full stop above the rule. Page 2 still opens in lowercase,
    // so the full stop is the only thing that tells the two paragraphs apart.
    let (chapter, _) = try await convert(firstPage(lastLine: "voiced their own thoughtful criticisms of the rule."),
                                         continuation)
    let order = blocks(chapter)
    #expect(order.contains { $0.hasPrefix("[page-2]criticisms of the rule, and several state courts") }, "\(order)")
    #expect(order.contains { $0.hasSuffix("voiced their own thoughtful criticisms of the rule.") })
    #expect(order.contains("——————"))
    // Nor does the continuation run into the note, which was the defect before #299.
    let aside = try noteAside(chapter)
    #expect(aside.hasSuffix("\(noteEnding)</p></aside>"))
    #expect(!aside.contains("criticisms"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aPageThatOpensWithAHeadingOrANewParagraphDoesNotContinueTheOneBeforeTheNotes() async throws {
    // A heading.
    let heading = [Row(x: 80, y: 272, shows: "/F2 16 Tf (The Question of Reliance) Tj")] + newParagraph(from: 2)
    let (headed, _) = try await convert(firstPage(), heading)
    #expect(headed.contains("<strong>The Question of Reliance</strong></h2>"), "\(blocks(headed))")
    #expect(blocks(headed).contains { $0.hasPrefix("[page-2]") })
    #expect(blocks(headed).contains { $0.hasSuffix("voiced their own thoughtful and extensive") })
    #expect(try noteAside(headed).hasSuffix("\(noteEnding)</p></aside>"))

    // A new paragraph the page indents, opening on a capital.
    let (indented, _) = try await convert(firstPage(), newParagraph(from: 0))
    let order = blocks(indented)
    #expect(order.contains { $0.hasPrefix("[page-2]Even so, some have argued") }, "\(order)")
    #expect(order.contains { $0.hasSuffix("voiced their own thoughtful and extensive") })
    let aside = try noteAside(indented)
    #expect(aside.hasSuffix("\(noteEnding)</p></aside>"))
    #expect(!aside.contains("Even so"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aPageWithoutItsRuleStillStepsOverItsNotes() async throws {
    // A page may draw its rule rather than type it, or print none. The note alone is stepped
    // over, and the paragraph still joins.
    let (chapter, _) = try await convert(firstPage(rule: false), continuation)
    #expect(chapter.contains("voiced their own thoughtful and extensive \(secondMarker)criticisms of the rule"))
    #expect(!chapter.contains("——"))
    #expect(try noteAside(chapter).hasSuffix("\(noteEnding)</p></aside>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aTypedRuleIsASeparatorOnAPageWhoseTextIsItsOwn() {
    // A rule typed at the body's leading, between two runs of prose it would otherwise be read
    // into: Loper Bright page 67 ended a paragraph on `…judgment).5 ——————` and page 68 opened
    // its note's continuation as `—————— serve the Constitution`.
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
    func line(_ text: String, y: Double, width: Double = 300) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 40, y: y, width: width, height: 12), fontSize: 12)
    }
    var page = PageContent(number: 1, bounds: bounds, lines: [
        line("the court declined to follow the rule in any", y: 300),
        line("case it had decided before the statute changed", y: 286),
        line("——————", y: 272, width: 54),
        line("and the court never explained why it did so", y: 258),
    ], graphics: [])
    var warnings: [ConversionWarning] = []
    #expect(paragraphTexts(LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)) == [
        "the court declined to follow the rule in any case it had decided before the statute changed",
        "——————", "and the court never explained why it did so",
    ])
    // A transcription of a scan is read as it was: its dashes are the reader's rendering of
    // whatever the scan drew, and a questionnaire's answer blanks look the same.
    page.recognized = true
    let recognized = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    #expect(!recognized.contains { $0.text == "——————" })
    #expect(recognized.contains { $0.text.contains("statute changed ——————") })
}

// The walk and the tail it holds back, block by block.

private let paragraph = ReflowBlock(content: .paragraph(InlineText("an open sentence the page did not finish")), page: 1)
private let rule = ReflowBlock(content: .paragraph(InlineText("——————")), page: 1)
private let footnote = ReflowBlock(content: .paragraph(InlineText("6 A note the page sets at its foot.")),
                                   note: .init(id: "note-fn-1-6", kind: .footnote), page: 1)
private let endnote = ReflowBlock(content: .paragraph(InlineText("6 An endnote of the book's own.")),
                                  note: .init(id: "note-6", kind: .endnote), page: 1)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func theJoinReachesPastAPagesFootnotesAndTheRuleAboveThem() {
    #expect(LayoutReconstructor.continuationAnchor(in: [paragraph, rule, footnote]) == 0)
    #expect(LayoutReconstructor.continuationAnchor(in: [paragraph, footnote, footnote]) == 0)
    #expect(LayoutReconstructor.continuationAnchor(in: [paragraph, rule, footnote, LayoutReconstructor.imageBlock(assetID: "box", page: 1)]) == 0)
    // A rule is stepped over only where a footnote stands directly beneath it; a page of
    // endnotes is back matter, not a page's foot.
    #expect(LayoutReconstructor.continuationAnchor(in: [paragraph, rule]) == 1)
    #expect(LayoutReconstructor.continuationAnchor(in: [paragraph, endnote]) == 1)
    #expect(LayoutReconstructor.continuationAnchor(in: [paragraph, rule, endnote]) == 2)
    // Reconstruction holds back everything the join may still move (#203, decision 0008), and
    // no more: a page marker stops the walk.
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, rule, footnote]) == 3)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, footnote]) == 2)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, endnote]) == 1)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, ReflowBlock(content: .sourcePage(2), page: 2), footnote]) == 1)
    #expect(LayoutReconstructor.isTypedRule("——————") && LayoutReconstructor.isTypedRule("_____"))
    #expect(!LayoutReconstructor.isTypedRule("—") && !LayoutReconstructor.isTypedRule("— 6 —"))
}

/// A page's last lines and the next page's first, for joins tested block by block.
private func pages() -> (previous: PageContent, next: PageContent) {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    return (PageContent(number: 1, bounds: bounds, lines: [
        .init(text: "an open sentence", rect: CGRect(x: 40, y: 200, width: 300, height: 12), fontSize: 12),
        .init(text: "6 A note the page sets at its foot.", rect: CGRect(x: 40, y: 40, width: 300, height: 9), fontSize: 9),
    ], graphics: []), PageContent(number: 2, bounds: bounds, lines: [
        .init(text: "carries on here.", rect: CGRect(x: 40, y: 750, width: 300, height: 12), fontSize: 12),
    ], graphics: []))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aHeadingThatOpensTheNextPageLeavesTheNotesWhereThePagePutThem() {
    // Block by block, so that the heading's words can open in lowercase and its being a heading
    // is the only thing that refuses the join. Nothing moves: the notes stay after the paragraph
    // and page 2 keeps a marker of its own.
    let (previous, next) = pages()
    let heading = ReflowBlock(content: .heading(id: "heading-2-0", text: InlineText("the question of reliance")), page: 2)
    var blocks = [paragraph, rule, footnote]
    var warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage([heading], page: next, previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks == [paragraph, rule, footnote, ReflowBlock(content: .sourcePage(2), page: 2), heading])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aParagraphThatRanIntoTheNotesRuleIsNotJoinedPastTheNotes() {
    // Loper Bright page 67 reads its rule into the paragraph above it: `…concurring in
    // judgment).5 ——————`. Such a block ends on the separator, not on a sentence the page broke.
    let (previous, next) = pages()
    let opening = [ReflowBlock(content: .paragraph(InlineText("carries on here.")), page: 2)]
    var warnings: [ConversionWarning] = []
    var ran = [ReflowBlock(content: .paragraph(InlineText("the court declined to follow the rule ——————")), page: 1), footnote]
    LayoutReconstructor.appendPage(opening, page: next, previousPage: previous, to: &ran, vocabulary: [], warnings: &warnings)
    #expect(ran.map(\.text) == ["the court declined to follow the rule ——————", footnote.text, "", "carries on here."])
    // The control: the same paragraph without the rule joins past the note, which keeps page 1's
    // side of the boundary. A dash that ends a word carries the sentence on and is not a rule.
    for ending in ["the court declined to follow the rule", "the court declined to follow the rule—"] {
        var open = [ReflowBlock(content: .paragraph(InlineText(ending)), page: 1), footnote]
        LayoutReconstructor.appendPage(opening, page: next, previousPage: previous, to: &open, vocabulary: [], warnings: &warnings)
        #expect(open.map(\.text) == [footnote.text, ending + " carries on here."])
        #expect(open.last?.sourcePages == [2])
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func notesAreNeverCarriedBackPastTheirOwnPagesMarker() {
    // A paragraph that opened on page 1 and runs on through page 2 carries page 2's marker inside
    // it. Page 2's note, placed before that paragraph, would stand on page 1's side of the
    // boundary, so the join to page 3 is refused and every block keeps its page.
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let (previousLines, nextLines) = (pages().previous.lines, pages().next.lines)
    let previous = PageContent(number: 2, bounds: bounds, lines: previousLines, graphics: [])
    let next = PageContent(number: 3, bounds: bounds, lines: nextLines, graphics: [])
    let opening = [ReflowBlock(content: .paragraph(InlineText("carries on here.")), page: 3)]
    let note = ReflowBlock(content: footnote.content, note: .init(id: "note-fn-2-6", kind: .footnote), page: 2)
    var warnings: [ConversionWarning] = []
    let spanning = ReflowBlock(content: .paragraph(InlineText("a paragraph that opened a page before this one")), page: 1)
    var blocks = [spanning, note]
    LayoutReconstructor.appendPage(opening, page: next, previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks == [spanning, note, ReflowBlock(content: .sourcePage(3), page: 3)] + opening)
    // The control: the same paragraph opening on the note's own page joins past it.
    let own = ReflowBlock(content: spanning.content, page: 2)
    var joined = [own, note]
    LayoutReconstructor.appendPage(opening, page: next, previousPage: previous, to: &joined, vocabulary: [], warnings: &warnings)
    #expect(joined.map(\.text) == [note.text, "a paragraph that opened a page before this one carries on here."])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func aNoteCarriedOverBeneathTheRuleIsNotTakenForTheBody() {
    // Loper Bright page 99 sets the end of note 3, carried over from page 98, between its rule and
    // note 4. Nothing recognizes that as a note, so it is a paragraph; reached past note 4, it
    // would take the next page's opening words into a note. The join refuses rather than guess
    // that the body stands above the rule.
    let (previous, next) = pages()
    let opening = [ReflowBlock(content: .paragraph(InlineText("carries on here.")), page: 2)]
    let carried = ReflowBlock(content: .paragraph(InlineText("the end of a note the page before began, set under the rule")), page: 1)
    var blocks = [paragraph, rule, carried, footnote]
    var warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage(opening, page: next, previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks == [paragraph, rule, carried, footnote, ReflowBlock(content: .sourcePage(2), page: 2)] + opening)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/306"))
func theIdentityAJoinComparesIsTheOneTheEarlierBlockEndsOn() {
    // Loper Bright page 76 opens a block on the four lines that finish a paragraph tagged from
    // page 75, and its geometry carries that block on through lines the tags never reached to the
    // foot of the body. Page 77 opens with a paragraph tagged as another. The block's end states
    // no identity, so the geometric rule decides, as it does against a page with no tags (#67).
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    func line(_ text: String, y: Double, group: Int?, count: Int) -> TextLine {
        var line = TextLine(text: text, rect: CGRect(x: 40, y: y, width: 300, height: 12), fontSize: 12)
        if let group { line.structure = .init(group: group, order: Int(800 - y), headingLevel: 0, lineCount: count) }
        return line
    }
    func page(tagged: Int) -> PageContent {
        let texts = ["the close of a paragraph the tags", "carried over from the page before,",
                     "then more of the page's own prose", "that the tags never reached, and at",
                     "the foot a sentence still open for"]
        return PageContent(number: 1, bounds: bounds, lines: texts.enumerated().map { index, text in
            line(text, y: 200 - Double(index) * 14, group: index < tagged ? 7 : nil, count: tagged)
        }, graphics: [])
    }
    let next = PageContent(number: 2, bounds: bounds,
                           lines: [line("the next page to finish.", y: 750, group: 9, count: 1)], graphics: [])
    var warnings: [ConversionWarning] = []
    let opening = LayoutReconstructor.blocks(page: next, images: [], vocabulary: [], warnings: &warnings)
    #expect(opening.map(\.structureGroup) == [9])

    let partly = page(tagged: 2)
    let partlyBlocks = LayoutReconstructor.blocks(page: partly, images: [], vocabulary: [], warnings: &warnings)
    #expect(partlyBlocks.count == 1)
    #expect(partlyBlocks.first?.structureGroup == 7)
    #expect(partlyBlocks.first?.closingStructure == .untagged)
    var joined = partlyBlocks
    LayoutReconstructor.appendPage(opening, page: next, previousPage: partly, to: &joined, vocabulary: [], warnings: &warnings)
    #expect(joined.count == 1)
    #expect(joined.first?.text.hasSuffix("a sentence still open for the next page to finish.") == true)
    // The joined block now ends in page 2's paragraph.
    #expect(joined.first?.closingStructureGroup == 9)

    // The control: a block the tags carry to its last line ends on its own identity, and two
    // identities that differ still never join (#67).
    let whole = page(tagged: 5)
    let wholeBlocks = LayoutReconstructor.blocks(page: whole, images: [], vocabulary: [], warnings: &warnings)
    #expect(wholeBlocks.first?.closingStructure == .opening)
    var refused = wholeBlocks
    LayoutReconstructor.appendPage(opening, page: next, previousPage: whole, to: &refused, vocabulary: [], warnings: &warnings)
    #expect(refused.map(\.text).last == "the next page to finish.")
    #expect(refused.contains { $0.content == .sourcePage(2) })
}
