import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// #152: the US Courts Pro Se 1 form. Its ruled blanks are printed structure, not figures: a blank
// set in a row of type takes its place in that row's text, so fill-in sentences read whole and
// each field label stands on its own. Its outline labels (`I.`, `A.`, `1.`) are headings ranked by
// tier, a label split from its title at the tab rejoins it, a caption's brace of `)` is decoration,
// the `Page N of 5` folio and the rule under the running head go with the furniture, and a row
// PDFKit cut at a sentence's two spaces reads as one line. Pages 1–5 are checksum-pinned source
// extractions (`uscourts-N`); controls are synthetic and from other layouts.

private let proSeSHA256 = "9fe218570d311b0deab9413e39efda41210e60f2a5221eb360d43912ce05a118"

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

private func line(_ text: String, _ frame: CGRect, size: Double = 11, style: TextStyle = []) -> TextLine {
    TextLine(content: InlineText(text, style: style), rect: frame, fontSize: size)
}

private func page(_ lines: [TextLine], blanks: [FormBlank] = [], number: Int = 1) -> PageContent {
    var page = PageContent(number: number, bounds: rect(0, 0, 612, 792), lines: lines, graphics: [])
    page.blanks = blanks
    return page
}

private func headings(_ blocks: [ReflowBlock]) -> [(text: String, level: Int)] {
    blocks.compactMap { if case let .heading(_, text, level) = $0.content { (text.text, level) } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private func listLines(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { $0.text } else { nil } }
}

/// The five form pages as the pipeline reconstructs them: furniture stripped document-wide, each
/// page's crops, its blocks, and heading levels ranked over the whole form. `fields: false` reads
/// the form as a printed one, with no field over any rule (#197).
private func reconstructForm(fields: Bool = true) throws -> (pages: [PageContent], crops: [[CGRect]], blocks: [ReflowBlock]) {
    var pages = try (1...5).map { number -> PageContent in
        let fixture = try SourceLayoutFixture.load("uscourts-\(number)")
        #expect(fixture.sourceSHA256 == proSeSHA256)
        return fixture.styledContent(fields: fields)
    }
    _ = LayoutReconstructor.stripFurniture(&pages)
    var crops: [[CGRect]] = [], blocks: [ReflowBlock] = []
    let vocabulary = LayoutReconstructor.vocabulary(in: pages)
    for page in pages {
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        crops.append(regions)
        var warnings: [ConversionWarning] = []
        blocks += LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                             vocabulary: vocabulary, warnings: &warnings)
    }
    LayoutReconstructor.rankHeadingLevels(&blocks)
    return (pages, crops, blocks)
}

// MARK: - The form, end to end

@Test func proSeFormReadsAsTheFormReads() throws {
    let (pages, crops, blocks) = try reconstructForm()
    func on(_ number: Int) -> [ReflowBlock] { blocks.filter { $0.page == number } }

    // No page keeps a crop: every rule is a blank or the running head's rule.
    #expect(crops.allSatisfy { $0.isEmpty }, "\(crops)")
    // The running head and the counted folio go on every page, and the head's rule with them.
    for page in pages {
        #expect(!page.lines.contains { $0.text.hasPrefix("Pro Se 1 (Rev. 12/16)") || $0.text.hasPrefix("Page ") }, "page \(page.number)")
        #expect(!page.graphics.contains { $0.minY > 730 }, "page \(page.number)")
    }

    // Page 1: the outline under the form's titles, the labels one to a paragraph, no brace.
    #expect(headings(on(1)).map(\.text) == ["UNITED STATES DISTRICT COURT", "COMPLAINT FOR A CIVIL CASE",
        "I. The Parties to This Complaint", "A. The Plaintiff(s)", "B. The Defendant(s)"])
    #expect(headings(on(1)).map(\.level) == [2, 3, 4, 5, 5])
    let first = paragraphs(on(1))
    for label in ["Name", "Street Address", "City and County", "State and Zip Code", "Telephone Number", "E-mail Address"] {
        #expect(first.contains(label + " " + FormBlank.text), "\(label)")
    }
    #expect(first.contains("Case No. " + FormBlank.text))
    #expect(!blocks.contains { $0.text.contains(")  )") || $0.text.contains(") )") })
    // The brace still divides the caption: the parties read before the case number.
    let caption = on(1).map(\.text)
    let defendants = try #require(caption.firstIndex { $0.hasPrefix("(Write the full name of each defendant") })
    let caseNumber = try #require(caption.firstIndex { $0.hasPrefix("Case No.") })
    #expect(defendants < caseNumber)
    // The caption's name boxes and the answer areas under II.A, 3, III and IV each read as a blank
    // of their own where they close (#197): above the party label, after the prompt.
    func follows(_ page: Int, _ prompt: String) -> String? {
        let texts = on(page).map(\.text)
        return texts.firstIndex { $0.hasPrefix(prompt) }.flatMap { $0 + 1 < texts.count ? texts[$0 + 1] : nil }
    }
    #expect(follows(1, "-v-") == FormBlank.text)
    #expect(caption[try #require(caption.firstIndex(of: "Plaintiff(s)")) - 1] == FormBlank.text)
    #expect(caption[try #require(caption.firstIndex(of: "Defendant(s)")) - 1] == FormBlank.text)
    #expect(follows(3, "List the specific federal statutes") == FormBlank.text)
    #expect(follows(4, "The amount in controversy") == FormBlank.text)
    #expect(follows(4, "Write a short and plain statement") == FormBlank.text)
    #expect(on(5).first?.text == FormBlank.text)
    #expect(on(2).allSatisfy { $0.text != FormBlank.text })
    #expect(blocks.filter { $0.text == FormBlank.text }.count == 6)

    // Page 2: every defendant label stands alone.
    #expect(paragraphs(on(2)).filter { $0 == "Name " + FormBlank.text }.count == 4)
    #expect(paragraphs(on(2)).filter { $0 == "Job or Title (if known) " + FormBlank.text }.count == 4)

    // Page 3: headings ranked roman, lettered, numbered; the fill-in sentences whole; the lettered
    // items apart from their sentences.
    #expect(headings(on(3)).map(\.text) == ["II. Basis for Jurisdiction", "A. If the Basis for Jurisdiction Is a Federal Question",
        "B. If the Basis for Jurisdiction Is Diversity of Citizenship", "1. The Plaintiff(s)", "2. The Defendant(s)"])
    #expect(headings(on(3)).map(\.level) == [4, 5, 5, 6, 6])
    #expect(paragraphs(on(3)).contains("The plaintiff, (name) ____, is a citizen of the State of (name) ____."))
    #expect(paragraphs(on(3)).contains("The plaintiff, (name) ____, is incorporated under the laws of the State of (name) ____, "
        + "and has its principal place of business in the State of (name) ____."))
    #expect(paragraphs(on(3)).contains("The defendant, (name) ____, is a citizen of the State of (name) ____. "
        + "Or is a citizen of (foreign nation) ____."))
    #expect(listLines(on(3)) == ["a. If the plaintiff is an individual", "b. If the plaintiff is a corporation",
                                 "a. If the defendant is an individual"])

    // Page 4: the Statement of Claim is one paragraph; III and IV are sections.
    #expect(headings(on(4)).map(\.text) == ["3. The Amount in Controversy", "III. Statement of Claim", "IV. Relief"])
    #expect(headings(on(4)).map(\.level) == [6, 4, 4])
    #expect(paragraphs(on(4)).contains { $0.hasPrefix("Write a short and plain statement of the claim. Do not make legal arguments. "
        + "State as briefly as possible the facts showing that each plaintiff") })
    #expect(paragraphs(on(4)).contains { $0.hasPrefix("The defendant, (name) ____, is incorporated under the laws of the State of (name) ____, and has its") })

    // Page 5: the closing sections and the signature labels.
    #expect(headings(on(5)).map(\.text) == ["V. Certification and Closing", "A. For Parties Without an Attorney", "B. For Attorneys"])
    #expect(headings(on(5)).map(\.level) == [4, 5, 5])
    for label in ["Date of signing:", "Signature of Plaintiff", "Printed Name of Plaintiff", "Signature of Attorney", "Bar Number"] {
        #expect(paragraphs(on(5)).contains(label + " " + FormBlank.text), "\(label)")
    }
}

// MARK: - Blanks

@Test func formBlanksAreTheRulesUnderTextFields() {
    let paints = [
        rect(276.6, 241.6, 301.3, 4.1),                              // under the Name field
        rect(250.0, 306.9, 30.5, 4.1), rect(276.6, 306.9, 173.1, 4.1), // one blank drawn twice
        rect(34, 734.5, 543.9, 5.0),                                  // the running head's rule
        rect(111.8, 412.5, 466.1, 4.1),                               // an answer area's closing rule
        rect(300, 500, 40, 30),                                       // a box, not a rule
    ]
    let fields = [rect(276.9, 242.7, 298.2, 16.4), rect(251.8, 310.0, 195.6, 13.9),
                  rect(113.1, 412.3, 464.1, 67.8), rect(214.4, 663.3, 181.8, 19.6), rect(290, 495, 60, 40)]
    let blanks = FormBlank.blanks(fields: fields, paints: paints)
    #expect(blanks.map(\.rule) == [paints[0], paints[1].union(paints[2]), paints[4]])
    // A one-line field shares the row of the label beside it; an answer area shares no row.
    #expect(blanks[0].sharesRow(with: rect(146.9, 246.9, 26.1, 12.2)))
    #expect(!blanks[2].sharesRow(with: rect(110.9, 398.8, 252.7, 12.2)))
    #expect(!blanks[0].sharesRow(with: rect(146.9, 228.1, 64.4, 12.2)))
}

@Test func blankRowsJoinTheirPiecesAndEndAtATrailingBlank() {
    let nameBlank = FormBlank(rule: rect(276.6, 241.6, 301.3, 4.1), field: rect(276.9, 242.7, 298.2, 16.4))
    let streetBlank = FormBlank(rule: rect(276.6, 222.9, 301.3, 4.1), field: rect(276.9, 225.3, 298.2, 16.4))
    let sentenceBlank = FormBlank(rule: rect(276.6, 324.9, 211.4, 4.1), field: rect(278.4, 328.0, 208.2, 13.9))
    let trailingBlank = FormBlank(rule: rect(182.5, 198.9, 206.4, 4.1), field: rect(184.2, 201.0, 204.7, 13.9))
    let lines = [
        line("Name", rect(146.9, 246.9, 26.1, 12.2)),
        line("Street Address", rect(146.9, 228.1, 64.4, 12.2)),
        line("The plaintiff, (name)", rect(182.9, 329.5, 89.1, 12.2)),
        line(", is a citizen of the", rect(488.9, 329.5, 80.7, 12.2)),
        line(".", rect(389.9, 203.5, 2.7, 12.2)),
    ]
    let joined = LayoutReconstructor.joiningBlankRows(lines, blanks: [nameBlank, streetBlank, sentenceBlank, trailingBlank])
    #expect(joined.map(\.text) == ["Name ____", "Street Address ____", "The plaintiff, (name) ____, is a citizen of the", "____."])
    // A row ending in its blank is complete; a row ending in text wraps as its last piece does.
    #expect(joined[0].wraps == false && joined[1].wraps == false && joined[3].wraps == nil)
    #expect(joined[2].wraps == nil)
    // The row spans its pieces and its blanks, on the type's row.
    #expect(joined[2].rect.minX == 182.9 && abs(joined[2].rect.maxX - 569.6) < 0.01 && joined[2].rect.minY == 329.5)
    #expect(joined[3].rect.minX == 184.5)

    // Controls. Text standing over the rule (a value printed on it) leaves the row alone; an answer
    // area's rule joins no row; a tagged line is the structure tree's; no blank, no change.
    let filled = [line("The plaintiff, Jane Q. Public, is a citizen of the", rect(182.9, 329.5, 386.7, 12.2))]
    #expect(LayoutReconstructor.joiningBlankRows(filled, blanks: [sentenceBlank]).map(\.text) == filled.map(\.text))
    let area = FormBlank(rule: rect(111.8, 412.5, 466.1, 4.1), field: rect(113.1, 412.3, 464.1, 67.8))
    let beside = [line("are at issue in this case.", rect(110.9, 419.4, 103.2, 12.2))]
    #expect(LayoutReconstructor.joiningBlankRows(beside, blanks: [area]) == beside)
    var tagged = lines[0]
    tagged.structure = TextStructure(group: 1, order: 0, headingLevel: 0)
    #expect(LayoutReconstructor.joiningBlankRows([tagged], blanks: [nameBlank]) == [tagged])
    #expect(LayoutReconstructor.joiningBlankRows(lines, blanks: []) == lines)
}

/// A synthetic form end to end: widgets over printed rules, one row a single text show that
/// PDFKit reads across its blank, and a rule under no field as the control.
@Test func formPagesReflowTheirBlanksAndCropNoRule() async throws {
    let content = """
    BT /F1 11 Tf 1 0 0 1 147 700 Tm (Name) Tj ET
    277 696.5 301 0.5 re f
    BT /F1 11 Tf 1 0 0 1 147 681 Tm (Street Address) Tj ET
    277 677.5 301 0.5 re f
    BT /F1 11 Tf 1 0 0 1 183 650 Tm [(State of \\(name\\)) -20000 (.)] TJ ET
    270 646.5 200 0.5 re f
    BT /F1 11 Tf 1 0 0 1 72 600 Tm (A rule under no field stands below this sentence.) Tj ET
    300 520 80 0.5 re f
    BT /F1 11 Tf 1 0 0 1 72 440 Tm (The page closes with a sentence of ordinary prose.) Tj ET
    """
    let fields = [
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /F 4 /Rect [277 696 578 712] >>",
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (street) /F 4 /Rect [277 677 578 693] >>",
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (state) /F 4 /Rect [270 646 470 660] >>",
    ].joined(separator: " ")
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R /Annots [\(fields)] >>",
        testPDFStream(content),
    ])
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("form.pdf")
    try data.write(to: source)

    // The single show comes back as one line, and extraction cuts it at the blank.
    let document = try #require(PDFDocument(url: source))
    let pdfPage = try #require(document.page(at: 0))
    let paints = GraphicsReader.read(try #require(pdfPage.pageRef)).paints.map(\.rect)
    let blanks = AnnotationEvidence.blanks(on: pdfPage, paints: paints)
    #expect(blanks.count == 3)
    let plain = try NativeTextReader.lines(on: pdfPage, limit: 100_000)
    #expect(plain.contains { $0.text == "State of (name) ." }, "\(plain.map { ($0.text, $0.rect) })")
    let cut = try NativeTextReader.lines(on: pdfPage, limit: 100_000, blanks: blanks)
    #expect(cut.contains { $0.text == "State of (name)" } && cut.contains { $0.text == "." })

    var options = ConversionOptions(); options.ocr = .never
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    let text = result.document.blocks.map(\.text)
    #expect(text.contains("Name ____") && text.contains("Street Address ____") && text.contains("State of (name) ____."))
    // The rule under no field is still the page's one crop; the blanks' rules are none.
    #expect(result.document.blocks.filter { if case .image = $0.content { true } else { false } }.count == 1,
            "\(result.document.blocks.map(\.text)) \(result.warnings)")
    #expect(text.contains("The page closes with a sentence of ordinary prose."))
    // Without the fields the page is a printed form (#197): a rule beside a label on its row is
    // still its blank. The row PDFKit reads across its rule has text over the rule, which no
    // printed blank may have, and the rule under no field is still the page's crop.
    let unfilled = dir.appendingPathComponent("unfilled.pdf")
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>",
        testPDFStream(content),
    ]).write(to: unfilled)
    let bare = try await PDFReflowLibPipeline.reconstruct(from: unfilled, options: options,
        workspace: dir.appendingPathComponent("work-unfilled"), progress: { _ in })
    let printed = bare.document.blocks.map(\.text)
    #expect(printed.contains("Name ____") && printed.contains("Street Address ____"), "\(printed)")
    #expect(!printed.contains { $0.hasPrefix("State of (name)") && $0.contains(FormBlank.text) }, "\(printed)")
    #expect(printed.contains("The page closes with a sentence of ordinary prose."))
}

// MARK: - Printed blanks

@Test func printedBlanksAreRulesBesideARowOfType() {
    let lines = [
        line("Provide the information below for each plaintiff named in the complaint. Attach additional pages if",
             rect(110.9, 278.1, 439.3, 12.2)),
        line("Name", rect(146.9, 246.9, 26.1, 12.2)),
        line("Street Address", rect(146.9, 228.1, 64.4, 12.2)),
        line("The plaintiff, (name)", rect(182.9, 629.5, 89.1, 12.2)),
        line(", is a citizen of the", rect(488.9, 629.5, 80.7, 12.2)),
    ]
    let paints = [
        rect(274.6, 241.6, 305.3, 4.1),                                  // Name's rule
        rect(274.6, 222.9, 150.0, 4.1), rect(420.0, 222.9, 160.0, 4.1),  // one rule drawn in two pieces
        rect(274.6, 624.9, 215.4, 4.1),                                  // the sentence's blank
    ]
    let blanks = FormBlank.printed(paints: paints, lines: lines)
    // Bottom to top; the rule drawn in pieces is one.
    #expect(blanks.map(\.rule) == [paints[1].union(paints[2]), paints[0], paints[3]])
    // Each blank's field is its row, so the row sets it in its text as a field's blank.
    #expect(blanks.allSatisfy { blank in lines.contains { blank.sharesRow(with: $0.rect) } })
    #expect(LayoutReconstructor.joiningBlankRows(lines, blanks: blanks).map(\.text)
            == [lines[0].text, "Name ____", "Street Address ____", "The plaintiff, (name) ____, is a citizen of the"])
    // A rule a field already claims is the field's.
    let field = FormBlank(rule: paints[0], field: rect(276.9, 242.7, 298.2, 16.4))
    #expect(FormBlank.printed(paints: paints, lines: lines, fields: [field]).map(\.rule) == [paints[1].union(paints[2]), paints[3]])

    // Controls, each a rule on a row of type that is no blank.
    func none(_ lines: [TextLine], _ paints: [CGRect], _ comment: Comment) {
        #expect(FormBlank.printed(paints: paints, lines: lines).isEmpty, comment)
    }
    let label = line("Total", rect(146.9, 400, 26.1, 12.2))
    let rule = rect(274.6, 394.6, 305.3, 4.1)
    none([label], [rule, rect(272.6, 380, 4.1, 40)], "a rule meeting a grid's vertical rule")
    none([label], [rule, rect(300, 380, 60, 16)], "a rule meeting a box")
    none([label, line("Jane Q. Public", rect(300, 400, 80, 12.2))], [rule], "a value printed on the rule")
    none([line("Underlined words in a sentence", rect(270, 400, 140, 12.2))], [rule], "an underline")
    none([line("5)", rect(250, 400, 10, 12.2)), line("7", rect(283, 400, 6, 12.2))],
         [rect(263, 398, 16, 4)], "a radical's bar beside its sign")
    none([line("10 ____ 11", rect(72, 60, 300, 10))], [rect(70, 80, 150, 4.1)], "a footnote separator on no row")
    var far = label
    far.rect.origin.x = rule.maxX + 11 * 2
    none([far], [rule], "text after the rule beyond a font size")
    far.rect.origin.x = rule.minX - 11 * 11 - far.rect.width
    none([far], [rule], "a label more than ten font sizes before the rule")
    // Two columns: the left column's line sits on the baseline of the right column's rules.
    let left = line("associated with the statements in their Key Messages (Tables 1, 2).", rect(72, 400, 230, 12.2))
    let floatRule = rect(313, 394.6, 259, 4.1)
    none([left, line("A paper's float rule as wide as the column's own lines, set here.", rect(315, 420, 255, 12.2))],
         [floatRule], "a column's rule as wide as its lines")
    none([left, line("Rising temperatures and extreme rainfall damage buildings,", rect(342, 378, 212, 12.2))],
         [floatRule], "a separator across the next column's ragged list")
    // A caption under the blank, short of its end, leaves it a blank (`Case No.`).
    #expect(FormBlank.printed(paints: [floatRule], lines: [left,
        line("(to be filled in by the Clerk’s Office)", rect(317, 380, 131, 10), size: 9)]).count == 1)
}

@Test func printedFormReadsItsLabelsAndSentencesAsTheFieldsDo() throws {
    // Pro Se 1 without its fields: the same rules beside the same rows are blanks by themselves.
    let (_, _, blocks) = try reconstructForm(fields: false)
    let text = blocks.map(\.text)
    for label in ["Name", "Street Address", "Case No.", "Date of signing:", "Signature of Attorney", "Bar Number"] {
        #expect(text.contains(label + " " + FormBlank.text), "\(label)")
    }
    #expect(blocks.filter { $0.page == 2 && $0.text == "Name " + FormBlank.text }.count == 4)
    #expect(text.contains("The plaintiff, (name) ____, is a citizen of the State of (name) ____."))
    #expect(text.contains("The defendant, (name) ____, is a citizen of the State of (name) ____. Or is a citizen of (foreign nation) ____."))
    // An answer area without its field is a set of rules on no row: no blank is made of it.
    #expect(!text.contains(FormBlank.text))
}

// MARK: - Answer areas

@Test func answerAreasReadAsABlankOfTheirOwn() {
    let area = FormBlank(rule: rect(111.8, 412.5, 466.1, 4.1), field: rect(113.1, 412.3, 464.1, 67.8))
    let prompt = line("are at issue in this case.", rect(110.9, 482.4, 103.2, 12.2))
    let next = line("B. If the Basis for Jurisdiction Is Diversity of Citizenship", rect(74.9, 390.0, 300, 12.2))
    let lines = [prompt, next]
    let areas = LayoutReconstructor.answerAreas(lines, blanks: [area], images: [], body: 11)
    #expect(areas.map(\.text) == [FormBlank.text])
    #expect(areas.first?.wraps == false && areas.first?.fontSize == 11)
    #expect(areas.first.map { $0.rect.minX == 113.8 && $0.rect.minY == area.rule.midY } == true)
    // It reads between the prompt and the next section, apart from both.
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page(lines, blanks: [area]), images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.map(\.text) == [prompt.text, FormBlank.text, next.text], "\(blocks.map(\.text))")

    // Controls: a one-line field is a row's blank; an area with type in it, or under a crop, is left.
    let oneLine = FormBlank(rule: rect(276.6, 241.6, 301.3, 4.1), field: rect(276.9, 242.7, 298.2, 16.4))
    #expect(LayoutReconstructor.answerAreas(lines, blanks: [oneLine], images: [], body: 11).isEmpty)
    let filled = lines + [line("The Clean Water Act, 33 U.S.C. § 1251", rect(120, 450, 200, 12.2))]
    #expect(LayoutReconstructor.answerAreas(filled, blanks: [area], images: [], body: 11).isEmpty)
    #expect(LayoutReconstructor.answerAreas(lines, blanks: [area], images: [rect(100, 420, 300, 40)], body: 11).isEmpty)
    #expect(LayoutReconstructor.answerAreas(lines, blanks: [], images: [], body: 11).isEmpty)
}

// MARK: - Marker pieces on tab stops

@Test func markerPiecesJoinTheirTitlesAcrossATabStop() {
    // Page 1's `I.` and its title, 29 points apart at 11 points, each on an edge other lines share.
    let lines = [
        line("I.", rect(38.9, 322.1, 7.0, 12.2), style: .bold),
        line("The Parties to This Complaint", rect(74.9, 322.1, 142.3, 12.2), style: .bold),
        line("A. The Plaintiff(s)", rect(74.9, 303.4, 107.1, 12.2), style: .bold),
        line("(Write the full name of each plaintiff.", rect(38.9, 551.0, 234.8, 10.0), size: 9),
    ]
    let joined = LayoutReconstructor.joiningMarkerPieces(lines)
    #expect(joined.map(\.text).contains("I. The Parties to This Complaint"))
    // Controls: the same gap where the title's edge is its own, and a gap wider than the tab.
    let lone = LayoutReconstructor.joiningMarkerPieces([lines[0], lines[1], lines[3]])
    #expect(lone.map(\.text).contains("I.") && lone.count == 3)
    var far = lines
    far[1].rect.origin.x = 38.9 + 7 + 11 * 3.6
    far[2].rect.origin.x = far[1].rect.minX
    #expect(LayoutReconstructor.joiningMarkerPieces(far).map(\.text).contains("I."))
    // Within two font sizes the join needs no tab stop, as before.
    var near = [lines[0], lines[1]]
    near[1].rect.origin.x = 38.9 + 7 + 20
    #expect(LayoutReconstructor.joiningMarkerPieces(near).map(\.text) == ["I. The Parties to This Complaint"])
}

// MARK: - A row cut at a sentence's two spaces

@Test func aRowCutAtASentenceSpaceJoinsTheParagraphBeneathIt() {
    var left = line("Write a short and plain statement of the claim.", rect(74.9, 374.9, 203.6, 12.2))
    left.trailingSpace = true
    let right = line("Do not make legal arguments. State as briefly as possible the", rect(284.0, 374.9, 270.6, 12.2))
    let beneath = [
        line("facts showing that each plaintiff is entitled to the damages or other relief sought. State how each defendant was",
             rect(74.9, 362.2, 491.8, 12.2)),
        line("involved and what each defendant did that caused the plaintiff harm or violated the plaintiff's rights, including",
             rect(74.9, 349.5, 484.7, 12.2)),
    ]
    let joined = LayoutReconstructor.joiningRowPieces([left, right] + beneath, images: [], body: 11)
    #expect(joined.first?.text == "Write a short and plain statement of the claim. Do not make legal arguments. State as briefly as possible the")

    // Controls: a piece PDFKit ended without its space, a row that is no line of the paragraph
    // beneath (a short row beside it), and a gap wider than two spaces.
    var bare = left
    bare.trailingSpace = false
    #expect(LayoutReconstructor.joiningRowPieces([bare, right] + beneath, images: [], body: 11).count == 4)
    var short = right
    short.rect.size.width = 120
    #expect(LayoutReconstructor.joiningRowPieces([left, short] + beneath, images: [], body: 11).count == 4)
    var wide = right
    wide.rect.origin.x = 278.5 + 11 * 0.8
    #expect(LayoutReconstructor.joiningRowPieces([left, wide] + beneath, images: [], body: 11).count == 4)
    #expect(LayoutReconstructor.joiningRowPieces([left, right], images: [], body: 11).count == 2)
}

// MARK: - Outline labels

@Test func outlineLabelsAreRankedByTier() {
    let outline = [
        line("I. The Parties to This Complaint", rect(38.9, 600, 178.3, 12.2), style: .bold),
        line("A. The Plaintiff(s)", rect(74.9, 580, 107.1, 12.2), style: .bold),
        line("1. The Plaintiff(s)", rect(110.9, 560, 103.5, 12.2)),
        line("a. If the plaintiff is an individual", rect(146.9, 540, 168.8, 12.2)),
        line("II. Basis for Jurisdiction", rect(38.9, 520, 136.2, 12.2), style: .bold),
        line("Federal courts are courts of limited jurisdiction (limited power). Generally, only two types",
             rect(74.9, 500, 469.7, 12.2)),
    ]
    let labels = LayoutReconstructor.outlineSectionLabels(in: outline, body: 11)
    #expect(labels.map(\.line.text) == ["I. The Parties to This Complaint", "A. The Plaintiff(s)", "1. The Plaintiff(s)",
                                        "II. Basis for Jurisdiction"])
    #expect(labels.map(\.depth) == [0, 1, 2, 0])
    // `V.` beside lettered labels inside it is Roman; alone on its edge, `C.` is a letter.
    let fifth = [line("V. Certification and Closing", rect(38.9, 600, 154.5, 12.2), style: .bold),
                 line("A. For Parties Without an Attorney", rect(74.9, 580, 190, 12.2), style: .bold),
                 line("C. For Attorneys", rect(74.9, 560, 90, 12.2), style: .bold)]
    #expect(LayoutReconstructor.outlineSectionLabels(in: fifth, body: 11).map(\.depth) == [0, 1, 1])

    // Controls: a numbered list is one tier; numbered sentences are no titles; tiers nested the
    // other way round, or with no bold label, are no outline; a label off the body's size is none.
    let list = [line("1. Remove the Cowling", rect(72, 600, 120, 12.2), style: .bold),
                line("2. Inspect the Engine", rect(72, 580, 120, 12.2), style: .bold)]
    #expect(LayoutReconstructor.outlineSectionLabels(in: list, body: 11).isEmpty)
    let sentences = [line("I. Remove the cowling and inspect the engine.", rect(38.9, 600, 220, 12.2), style: .bold),
                     line("A. Check the oil level before every flight.", rect(74.9, 580, 220, 12.2), style: .bold)]
    #expect(LayoutReconstructor.outlineSectionLabels(in: sentences, body: 11).isEmpty)
    let reversed = [line("1. The Plaintiff(s)", rect(38.9, 600, 103.5, 12.2), style: .bold),
                    line("A. The Plaintiff(s)", rect(74.9, 580, 107.1, 12.2), style: .bold)]
    #expect(LayoutReconstructor.outlineSectionLabels(in: reversed, body: 11).isEmpty)
    let plain = outline.map { line($0.text, $0.rect) }
    #expect(LayoutReconstructor.outlineSectionLabels(in: plain, body: 11).isEmpty)
    #expect(LayoutReconstructor.outlineSectionLabels(in: outline, body: 9).isEmpty)
}

@Test func outlineHeadingsRankBeneathTheSizeScale() {
    func heading(_ text: String, size: CGFloat, depth: Int?) -> ReflowBlock {
        var block = ReflowBlock(content: .heading(id: text, text: InlineText(text)), page: 1)
        block.headingSize = size
        block.outlineDepth = depth
        return block
    }
    var blocks = [heading("UNITED STATES DISTRICT COURT", size: 20, depth: nil), heading("COMPLAINT", size: 13, depth: nil),
                  heading("I. Parties", size: 11, depth: 0), heading("A. Plaintiff", size: 11, depth: 1),
                  heading("1. Plaintiff", size: 11, depth: 2)]
    LayoutReconstructor.rankHeadingLevels(&blocks)
    #expect(headings(blocks).map(\.level) == [2, 3, 4, 5, 6])
    // An outline alone ranks from the top; without depths every body-size label is one tier.
    var alone = Array(blocks.dropFirst(2))
    LayoutReconstructor.rankHeadingLevels(&alone)
    #expect(headings(alone).map(\.level) == [2, 3, 4])
    // An outline that opens at capitals ranks them where a Roman tier would stand (#197): its
    // tiers count from the outermost the document sets, not from a Roman tier it never uses.
    var lettered = [blocks[0], blocks[1], heading("A. Plaintiff", size: 11, depth: 1), heading("1. Plaintiff", size: 11, depth: 2),
                    heading("B. Defendant", size: 11, depth: 1)]
    LayoutReconstructor.rankHeadingLevels(&lettered)
    #expect(headings(lettered).map(\.level) == [2, 3, 4, 5, 4])
    // A Roman tier anywhere in the document keeps the lettered one beneath it, on every page.
    var mixed = lettered + [heading("II. Jurisdiction", size: 11, depth: 0)]
    mixed[mixed.count - 1].page = 3
    LayoutReconstructor.rankHeadingLevels(&mixed)
    #expect(headings(mixed).map(\.level) == [2, 3, 5, 6, 5, 4])
    var flat = blocks.map { block -> ReflowBlock in var copy = block; copy.outlineDepth = nil; return copy }
    LayoutReconstructor.rankHeadingLevels(&flat)
    #expect(headings(flat).map(\.level) == [2, 3, 4, 4, 4])
}

// MARK: - The caption's brace

@Test func aColumnOfBracketsIsABraceNotText() {
    var lines = (0..<15).map { index in line(")", rect(302.2, 588.7 - Double(index) * 14, 4.0, 13.3), size: 12) }
    lines.append(line("Case No.", rect(328.3, 602.7, 40.2, 12.2)))
    lines.append(line("(to be filled in by the Clerk’s Office)", rect(389.9, 586.9, 131.3, 10.0), size: 9))
    let columns = LayoutReconstructor.bracketColumns(in: lines)
    #expect(columns.count == 1 && columns[0].count == 15)
    var warnings: [ConversionWarning] = []
    let result = LayoutReconstructor.blocks(page: page(lines), images: [], vocabulary: [], warnings: &warnings)
    #expect(result.map(\.text) == ["Case No.", "(to be filled in by the Clerk’s Office)"])

    // Controls: two brackets, brackets on different edges, and a bracket beside words.
    #expect(LayoutReconstructor.bracketColumns(in: Array(lines.prefix(2))).isEmpty)
    let scattered = lines.prefix(3).enumerated().map { index, bracket -> TextLine in
        var copy = bracket; copy.rect.origin.x += Double(index) * 20; return copy
    }
    #expect(LayoutReconstructor.bracketColumns(in: scattered).isEmpty)
    let spaced = lines.prefix(3).enumerated().map { index, bracket -> TextLine in
        var copy = bracket; copy.rect.origin.y -= Double(index) * 30; return copy
    }
    #expect(LayoutReconstructor.bracketColumns(in: spaced).isEmpty)
    #expect(LayoutReconstructor.bracketColumns(in: [line("(see attached)", rect(302.2, 588.7, 60, 13.3))] + lines.prefix(2)).isEmpty)
}

// MARK: - Furniture

@Test func aCountedFolioAndTheRuleUnderARemovedHeadGoWithTheFurniture() {
    func formPage(_ number: Int, pages: Int = 5) -> PageContent {
        var content = page([
            line("Pro Se 1 (Rev. 12/16) Complaint for a Civil Case", rect(38.9, 739.6, 157.5, 8.8), size: 8),
            line("Body text on page \(number) opens here and runs on.", rect(74.9, 713.5, 300, 12.2)),
            line("A rule sits under this heading", rect(74.9, 500, 200, 12.2)),
            line("Page \(number) of \(pages)", rect(537.8, 29.0, 38.2, 8.8), size: 8),
        ], number: number)
        content.graphics = [rect(34, 734.5, 543.9, 6.9), rect(74, 495, 480, 4.1)]
        return content
    }
    var pages = (1...5).map { formPage($0) }
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.count == 5)
    for page in pages {
        #expect(page.lines.map(\.text) == ["Body text on page \(page.number) opens here and runs on.", "A rule sits under this heading"])
        // The head's rule goes; the rule inside the body stays.
        #expect(page.graphics == [rect(74, 495, 480, 4.1)])
    }
    // Controls: a counted folio on two pages is no run, and there the head keeps its rule; a count
    // that does not follow the pages (a procedure's steps) is no folio.
    var two = (1...2).map { formPage($0) }
    _ = LayoutReconstructor.stripFurniture(&two)
    #expect(two.allSatisfy { $0.lines.contains { $0.text.hasPrefix("Page ") } && $0.graphics.count == 2 })
    var steps = [3, 1, 6, 2].enumerated().map { index, step -> PageContent in
        var content = formPage(index + 1)
        content.lines[3] = line("Step \(step) of 7", rect(537.8, 29.0, 38.2, 8.8), size: 8)
        return content
    }
    _ = LayoutReconstructor.stripFurniture(&steps)
    #expect(steps.allSatisfy { $0.lines.contains { $0.text.hasPrefix("Step ") } })
}
