import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #75: a page that draws a Form XObject used to discard all of its tags, whatever the form drew.
// A form that shows no text cannot place or own a line, so the page's tags now apply; a form that
// shows text, directly or through a nested form, still invalidates the page.
// #84: once those pages' tags apply, FAA chapter openers tagged `P` must stay headings.

// MARK: - Form XObjects (#75)

/// One tagged paragraph (`Tagged body text`, MCID 0) and a `Do` of form 8 after it. Form 8's
/// content and resources are `form`; `nested`, when set, is form 9, which form 8 may draw as `/Fn`.
private func formObjects(form: String, nested: String? = nil) -> [String] {
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /MarkInfo << /Marked true >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> /XObject << /Fm 8 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream("""
        /P << /MCID 0 >> BDC BT /F1 10 Tf 1 0 0 1 72 700 Tm (Tagged body text) Tj ET EMC
        q 1 0 0 1 72 400 cm /Fm Do Q
        """),
        "<< /Type /StructTreeRoot /K [9 0 R] /ParentTree 7 0 R >>",
        "<< /Nums [0 [9 0 R]] >>",
        testPDFStream(form, extra: "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >>"
                      + (nested == nil ? "" : " /XObject << /Fn 10 0 R >>") + " >>"),
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K 0 >>",
    ]
    if let nested {
        objects.append(testPDFStream(nested, extra: "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >>"))
    }
    return objects
}

private enum FormShape: String, CaseIterable {
    /// A rule and a filled box: a figure drawn through a form (DGA's 38 forms).
    case textFree
    /// A text-free form drawing another text-free form.
    case nestedTextFree
    /// A form that shows text, unmarked (FAA's back-matter pages).
    case showsText
    /// A text-free form drawing a form that shows text.
    case nestedShowsText
    /// A form drawing a resource it does not have: nothing proves it text-free.
    case unresolvable

    var applies: Bool { self == .textFree || self == .nestedTextFree }

    var objects: [String] {
        let drawing = "0.5 g 0 0 100 50 re f 0 G 0 60 m 200 60 l S"
        switch self {
        case .textFree: return formObjects(form: drawing)
        case .nestedTextFree: return formObjects(form: drawing + " /Fn Do", nested: drawing)
        case .showsText: return formObjects(form: "BT /F1 9 Tf 1 0 0 1 10 10 Tm (Label) Tj ET")
        case .nestedShowsText:
            return formObjects(form: drawing + " /Fn Do", nested: "BT /F1 9 Tf 1 0 0 1 10 10 Tm (Label) Tj ET")
        case .unresolvable: return formObjects(form: drawing + " /Missing Do")
        }
    }
}

@Test(arguments: FormShape.allCases)
private func aFormInvalidatesThePageTagsOnlyWhenItCouldShowText(_ shape: FormShape) throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("form.pdf")
    try testPDF(objects: shape.objects).write(to: url)
    let document = try #require(CGPDFDocument(url as CFURL))
    let page = try #require(document.page(at: 1))
    let tree = try StructureTreeReader.read(url)
    let tags = try #require(tree.pages[1])
    #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
    // Independent geometry for the one explicit origin above.
    var lines = [TextLine(text: "Tagged body text", rect: CGRect(x: 72, y: 697, width: 80, height: 12), fontSize: 10)]
    #expect(MarkedTextReader.apply(tags, page: page, lines: &lines) == shape.applies, "\(shape.rawValue)")
    #expect((lines[0].structure != nil) == shape.applies, "\(shape.rawValue)")
}

// MARK: - Chapter openers tagged as paragraphs (#84)

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 11.5, size: CGFloat,
                  bold: Bool = false, group: Int? = nil, order: Int = 0, count: Int = 1) -> TextLine {
    var line = TextLine(content: InlineText(text, style: bold ? .bold : []),
                        rect: CGRect(x: x, y: y, width: width, height: height), fontSize: size)
    if let group { line.structure = TextStructure(group: group, order: order, headingLevel: 0, lineCount: count) }
    return line
}

private let prose = "the atmosphere is an envelope of air that surrounds the Earth and"

/// FAA page 88's opener: `Chapter 4` (16 point) and `Principles of Flight` (48 point), each its own
/// `P`, over the 12-point bold `Introduction` and its 10-point paragraph, all tagged.
private func chapterOpener() -> PageContent {
    var lines = [
        line("Chapter 4", x: 321.5, y: 713.6, width: 50.5, height: 18.9, size: 16, group: 1, order: 1),
        line("Principles of Flight", x: 181.6, y: 640, width: 418.2, height: 58, size: 48, group: 2, order: 2),
        line("Introduction", x: 323, y: 595, width: 69.6, height: 15.8, size: 12, bold: true, group: 3, order: 3),
    ]
    for index in 0..<6 {
        lines.append(line(index == 0 ? "This chapter examines the fundamental physical laws governing" : prose,
                          x: 323, y: 580.2 - CGFloat(index) * 12.5, width: 237, size: 10, group: 4, order: 4, count: 6))
    }
    return PageContent(number: 88, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

private func build(_ page: PageContent, headingStyles: Set<LayoutReconstructor.LabelStyle> = [])
    -> (blocks: [ReflowBlock], warnings: [ConversionWarning]) {
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
                                            headingStyles: headingStyles)
    return (blocks, warnings)
}

@Test func aChapterTitleTaggedAsAParagraphIsAHeadingInTheBooksRecurringHeadingStyle() throws {
    let page = chapterOpener()
    // Reproducer: without the book's evidence, #67's column test keeps both titles as the
    // paragraphs they are tagged as, because the next line in each one's column is a heading.
    let alone = build(page)
    #expect(headings(alone.blocks) == ["Introduction"])
    #expect(alone.blocks.contains { $0.text == "Chapter 4" && $0.taggedLevel == 0 })
    // The book repeats both styles on its chapter openers: both read as headings, in order.
    let styles = LayoutReconstructor.headingEvidence(on: page)
    let chapter = LayoutReconstructor.LabelStyle(page.lines[0], body: 10)
    let title = LayoutReconstructor.LabelStyle(page.lines[1], body: 10)
    #expect(styles.isSuperset(of: [chapter, title]))
    let book = build(page, headingStyles: [chapter, title])
    #expect(headings(book.blocks) == ["Chapter 4", "Principles of Flight", "Introduction"])
    #expect(book.blocks.last?.text.hasPrefix("This chapter examines") == true)
    #expect(!book.warnings.contains { $0.code == .structureFallback })
}

@Test func headingEvidenceCountsFromTheThirdPageAndIgnoresFolios() {
    let evidence = LayoutReconstructor.headingEvidence(on: chapterOpener())
    var pages: [LayoutReconstructor.LabelStyle: Int] = [:]
    for _ in 0..<2 { for style in evidence { pages[style, default: 0] += 1 } }
    #expect(LayoutReconstructor.labelStyles(from: pages).isEmpty)
    for style in evidence { pages[style, default: 0] += 1 }
    #expect(LayoutReconstructor.labelStyles(from: pages) == evidence)
    // A folio set at heading size (FAA page 473's `C-1` over small caption text) is no evidence;
    // a title of the same size and style is.
    func page(_ text: String) -> PageContent {
        var lines = (0..<6).map { index in line(prose, x: 72, y: 600 - CGFloat(index) * 12.5, width: 237, size: 10) }
        lines.append(line(text, x: 72, y: 700, width: 60, height: 20, size: 16))
        return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    }
    #expect(LayoutReconstructor.headingEvidence(on: page("Weight")).count == 1)
    #expect(LayoutReconstructor.headingEvidence(on: page("C-1")).isEmpty)
}

/// Our Flag page 4's imprint: `JOINT COMMITTEE ON PRINTING` (12 point) centred 90 points right of
/// the 9-point text beneath it, tagged `P`.
private func titlePageImprint() -> PageContent {
    var lines = [line("JOINT COMMITTEE ON PRINTING", x: 136, y: 700, width: 300, height: 15, size: 12, group: 1, order: 1)]
    for index in 0..<6 {
        lines.append(line("ROBERT W. NEY, Representative from Ohio, Chairman of the committee",
                          x: 45, y: 670 - CGFloat(index) * 11, width: 420, height: 10, size: 9,
                          group: 2 + index, order: 2 + index))
    }
    return PageContent(number: 4, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func aCentredImprintInNoRecurringStyleStaysAParagraph() {
    let page = titlePageImprint()
    // Our Flag repeats its 22-point section headings over the 9-point body, not the imprint's style.
    let bookHeading = LayoutReconstructor.LabelStyle(
        line("Early American Flags", x: 45, y: 700, width: 300, height: 26, size: 22), body: 9)
    let book = build(page, headingStyles: [bookHeading])
    #expect(headings(book.blocks).isEmpty)
    #expect(book.blocks.first?.text == "JOINT COMMITTEE ON PRINTING")
    // Control: were the imprint's own style one the book repeats, the same line would be a title.
    let own = build(page, headingStyles: [LayoutReconstructor.LabelStyle(page.lines[0], body: 9)])
    #expect(headings(own.blocks) == ["JOINT COMMITTEE ON PRINTING"])
}

/// FAA page 203: one `P` holds `Introduction`, its paragraph, `Pitot-Static Flight Instruments` and
/// its paragraph (group 1, first in tag order); the 48-point chapter title above them is group 2.
private func titledParagraphGroup() -> PageContent {
    var lines = [line("Instruments", x: 71, y: 640, width: 181.7, height: 56.8, size: 48, group: 2, order: 2)]
    var y: CGFloat = 585.5
    for title in ["Introduction", "Pitot-Static Flight Instruments"] {
        lines.append(line(title, x: 72, y: y, width: 170, height: 15.8, size: 12, bold: true, group: 1, order: 1, count: 10))
        y -= 14.8
        for _ in 0..<4 {
            lines.append(line(prose, x: 72, y: y, width: 237, size: 10, group: 1, order: 1, count: 10))
            y -= 12.5
        }
        y -= 17
    }
    return PageContent(number: 203, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func aParagraphTagOverATitleAndItsBodyKeepsTheSpatialReading() {
    let page = titledParagraphGroup()
    let title = LayoutReconstructor.LabelStyle(page.lines[0], body: 10)
    let (blocks, warnings) = build(page, headingStyles: [title])
    #expect(warnings.contains { $0.code == .structureFallback && $0.message.hasPrefix("A paragraph tag spanning a heading") })
    // The chapter title leads, and neither section title fuses into a paragraph.
    #expect(headings(blocks) == ["Instruments", "Introduction", "Pitot-Static Flight Instruments"])
    #expect(!blocks.contains { $0.text.hasPrefix("Introduction ") })
}

// MARK: - Paragraphs a source tags in pieces (#75)

/// A tagged paragraph (group 1) over a column whose paragraphs are separated by space, then a
/// paragraph split into group 2 (`upper` closes it) and group 3 (`lower` opens it). `spaced`
/// false sets every line at ordinary leading, as a list is; `short` makes `upper` a short line.
private func splitParagraph(upper: String, lower: String, spaced: Bool = true, short: Bool = false) -> PageContent {
    var lines: [TextLine] = []
    var y: CGFloat = 700
    for _ in 0..<3 {
        lines.append(line(prose, x: 321, y: y, width: 237, size: 10, group: 1, order: 1, count: 6))
        y -= 12.5
    }
    y -= spaced ? 13.5 : 0
    for _ in 0..<3 {
        lines.append(line(prose, x: 321, y: y, width: 237, size: 10, group: 1, order: 1, count: 6))
        y -= 12.5
    }
    y -= spaced ? 13.5 : 0
    lines.append(line(prose, x: 321, y: y, width: 237, size: 10, group: 2, order: 2, count: 2))
    y -= 12.5
    lines.append(line(upper, x: 321, y: y, width: short ? 120 : 236.3, size: 10, group: 2, order: 2, count: 2))
    y -= 12.5
    lines.append(line(lower, x: 321, y: y, width: 123, size: 10, group: 3, order: 3))
    return PageContent(number: 211, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

@Test func twoParagraphTagsSplitAtAWrappedLineReadAsOneParagraph() {
    // FAA page 211: `…are found on placards and in the AFM/` then `POH. These airspeeds include:`.
    let slash = paragraphs(build(splitParagraph(upper: "face of the ASI, but are found on placards and in the AFM/",
                                                lower: "POH. These airspeeds include:")).blocks)
    #expect(slash.count == 2)
    #expect(slash.last?.hasSuffix("in the AFM/POH. These airspeeds include:") == true)
    // FAA page 105: a new sentence at ordinary leading in a column that spaces its paragraphs.
    let sentence = paragraphs(build(splitParagraph(upper: "an aircraft, for its position has a great bearing upon stability.",
                                                   lower: "The allowable location of the CG")).blocks)
    #expect(sentence.count == 2)
    #expect(sentence.last?.hasSuffix("upon stability. The allowable location of the CG") == true)
}

@Test func paragraphTagsStaySeparateWithoutEvidenceOfAWrap() {
    let upper = "an aircraft, for its position has a great bearing upon stability."
    func opensAParagraph(_ lower: String, _ page: PageContent) -> Bool {
        paragraphs(build(page).blocks).contains { $0 == lower }
    }
    // Even leading throughout (FAA's acronym list) gives a new sentence no evidence.
    #expect(opensAParagraph("The allowable location of the CG",
                            splitParagraph(upper: upper, lower: "The allowable location of the CG", spaced: false)))
    // A short last line ends its paragraph, even before a lowercase line.
    #expect(opensAParagraph("the allowable location", splitParagraph(upper: upper, lower: "the allowable location", short: true)))
    // A leader entry never runs on.
    #expect(opensAParagraph("the Decision-Making Process",
                            splitParagraph(upper: "Human Behavior........................................2-11",
                                           lower: "the Decision-Making Process")))
}

@Test func aCaptionContinuationTaggedApartFallsBackWithItsCaption() {
    // FAA page 227: `Figure 8-34. … compensation for` (8 point) and `deviation errors.` (9 point) are
    // two groups; the caption group falls back, so its continuation must fall back with it.
    var lines: [TextLine] = []
    var y: CGFloat = 700
    for _ in 0..<4 {
        lines.append(line(prose, x: 72, y: y, width: 237, size: 10))
        y -= 12.5
    }
    y -= 30
    lines.append(line("Figure 8-34. Utilization of a compass rose aids compensation for", x: 72, y: y, width: 234.9,
                      height: 10.8, size: 8, group: 1, order: 1))
    lines.append(line("deviation errors.", x: 72, y: y - 11.9, width: 60.5, height: 10.2, size: 9, group: 2, order: 2))
    let page = PageContent(number: 227, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    let (blocks, warnings) = build(page)
    #expect(warnings.contains { $0.message.hasPrefix("Caption, list") })
    #expect(paragraphs(blocks).last == "Figure 8-34. Utilization of a compass rose aids compensation for deviation errors.")
    #expect(!blocks.contains { $0.structureGroup != nil })
}
