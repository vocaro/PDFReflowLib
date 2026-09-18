import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// #186, read against renders of USDA ARS *Agricultural Research*, November/December 2012:
//
// - the back cover's bullet is drawn from `WVUHWN+MonotypeSorts`, whose ToUnicode map reads its glyph
//   as `l` (the Zapf Dingbats code for ●), so it read `<sup>l</sup>`;
// - the photo credits are set in capitals with the lower-case letters in `ActualText`, and
//   `Helvetica-Condensed`'s map reads code `Z` (glyph `/Z`, the only Z its `CharSet` lists) as `z`,
//   so page 15's credit read `BRAD FRITz`;
// - the back cover's return address, `Official Business` and web line, and the cover's `pages 2,
//   4-14`, were headings: those pages set too little text to state a body, and the back cover's
//   estimate came from the 8-point subscribe box inside its crop;
// - `com-` + `panies`, `infec-` + `tions` and `compli-` + `ance` kept their hyphen because the
//   magazine prints none of the three words whole;
// - page 9's `Fighting Filth Flies` heads a sidebar over the sidebar's photograph, 142 points above
//   the sidebar's first line, so no paragraph opened beneath it.
//
// Fixtures `usda-1` and `usda-24` are captured from the checksum-pinned source (text and geometry
// only); expected text was read against 60 DPI Poppler renders. The in-memory PDFs copy the source's
// font dictionaries and maps without any font program.

private let usdaSHA256 = "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761"

private func usdaPage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("usda-\(number)")
    #expect(fixture.sourceSHA256 == usdaSHA256)
    var pages = [fixture.styledContent()]
    _ = LayoutReconstructor.stripFurniture(&pages)
    return pages[0]
}

private func reflow(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = [],
                    documentBody: CGFloat? = nil, regions keeping: Bool = true) -> [ReflowBlock] {
    let regions = keeping ? LayoutReconstructor.graphicsWithLabels(page) : []
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                      vocabulary: [], warnings: &warnings, labelStyles: labelStyles,
                                      documentBody: documentBody)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

// MARK: - Glyphs a font's map misreports

private func cmap(_ codespace: String, _ entries: String) -> String {
    testPDFStream("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        /CMapName /Test-UCS def /CMapType 2 def
        1 begincodespacerange \(codespace) endcodespacerange
        \(entries)
        endcmap CMapName currentdict /CMap defineresource pop end end
        """)
}

/// One page: `F1` is Helvetica, `F2` the font given as object strings (its first object the font
/// dictionary; `NEXT1`, `NEXT2`, … name the objects after it).
private func document(_ content: String, font: [String]) throws -> PDFDocument {
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ]
    objects += font.map { object in
        (1...4).reduce(object) { $0.replacingOccurrences(of: "NEXT\($1)", with: "\(6 + $1)") }
    }
    return try #require(PDFDocument(data: testPDF(objects: objects)))
}

private func lines(_ document: PDFDocument) throws -> [TextLine] {
    try NativeTextReader.lines(on: #require(document.page(at: 0)), limit: 100_000)
}

/// The magazine's composite Monotype Sorts: Identity-H, one glyph, mapped to `l` (page 24, object 880).
private func sorts(_ name: String = "WVUHWN+MonotypeSorts") -> [String] {
    [
        "<< /Type /Font /Subtype /Type0 /BaseFont /\(name) /Encoding /Identity-H /DescendantFonts [NEXT1 0 R] /ToUnicode NEXT3 0 R >>",
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /\(name) /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /CIDToGIDMap /Identity /DW 1000 /FontDescriptor NEXT2 0 R >>",
        "<< /Type /FontDescriptor /FontName /\(name) /Flags 4 /FontBBox [0 -143 981 820] /ItalicAngle 0 /Ascent 820 /Descent -143 /CapHeight 700 /StemV 80 >>",
        cmap("<0000> <FFFF>", "1 beginbfchar <004F> <006C> endbfchar"),
    ]
}

/// The back cover's web line: the bullet a 6-point show raised one point between two 11-point addresses.
private let webLine = "BT /F1 11 Tf 115.1 45.4 Td (Visit us at ars.usda.gov/ar ) Tj /F2 6 Tf 1 Ts <004f> Tj /F1 11 Tf 0 Ts ( Follow us at twitter.com/USDA_ARS) Tj ET"

@Test func aDingbatFontsLetterReadsAsItsPictograph() throws {
    let line = try #require(lines(document(webLine, font: sorts())).first { $0.text.hasPrefix("Visit us") })
    #expect(line.text == "Visit us at ars.usda.gov/ar ● Follow us at twitter.com/USDA_ARS", "\(line.text)")
    // Only the bullet is rewritten: `Follow`'s letters are the same code point in another font.
    #expect(line.text.filter { $0 == "l" }.count == 2)
    // Set apart between two words, the raised bullet is no superscript.
    #expect(!EPUBTextEncoder.inline(line.content).contains("<sup>"), "\(EPUBTextEncoder.inline(line.content))")
    // Zapf Dingbats by name, and its ITC name, read the same table.
    for name in ["ZapfDingbats", "ABCDEF+ITCZapfDingbats"] {
        let other = try #require(lines(document(webLine, font: sorts(name))).first { $0.text.hasPrefix("Visit us") })
        #expect(other.text.contains("ar ● Follow"), "\(name): \(other.text)")
    }
}

@Test func aLetterMappedByAnyOtherFontStays() throws {
    // Control: the same composite font and map under a text font's name keeps its letter.
    let line = try #require(lines(document(webLine, font: sorts("WVUHWN+SyntheticSans"))).first { $0.text.hasPrefix("Visit us") })
    #expect(line.text.contains("ar l Follow"), "\(line.text)")
    // The table: Adobe's Zapf Dingbats codes, where Unicode's Dingbats block did not hold the pictograph.
    #expect(FontWeightReader.zapfDingbats[0x6C] == "●" && FontWeightReader.zapfDingbats[0x6E] == "■")
    #expect(FontWeightReader.zapfDingbats[0x21] == "✁" && FontWeightReader.zapfDingbats[0x48] == "★")
    #expect(FontWeightReader.zapfDingbats[0xAC] == "①" && FontWeightReader.zapfDingbats[0xD5] == "→")
    #expect(FontWeightReader.zapfDingbats[0x20] == nil && FontWeightReader.zapfDingbats[0xF0] == nil)
    #expect(FontWeightReader.isDingbatFamily("WVUHWN+MonotypeSorts") && FontWeightReader.isDingbatFamily("Dingbats"))
    #expect(!FontWeightReader.isDingbatFamily("Wingdings-Regular") && !FontWeightReader.isDingbatFamily("SymbolMT"))
}

/// The magazine's credit font (page 15, object 1007): Type 1, WinAnsi, `Nonsymbolic`, its map reading
/// code `Z` as `z`; `charSet` and `flags` vary for the controls.
private func creditFont(charSet: String = "/parenleft/parenright/hyphen/one/two/six/seven/nine/A/B/D/F/I/R/T/Z",
                        flags: Int = 32, zed: String = "007A") -> [String] {
    let identity = [0x20, 0x28, 0x29, 0x2D, 0x31, 0x32, 0x36, 0x37, 0x39, 0x41, 0x42, 0x44, 0x46, 0x49, 0x52, 0x54]
        .map { String(format: "<%02X> <%04X>", $0, $0) }.joined(separator: " ")
    return [
        "<< /Type /Font /Subtype /Type1 /BaseFont /WVUHWN+Helvetica-Condensed /Encoding /WinAnsiEncoding /FontDescriptor NEXT1 0 R /ToUnicode NEXT2 0 R >>",
        "<< /Type /FontDescriptor /FontName /WVUHWN+Helvetica-Condensed /Flags \(flags) /CharSet (\(charSet)) /FontBBox [-174 -224 1071 990] /ItalicAngle 0 /Ascent 990 /Descent -224 /CapHeight 750 /StemV 80 >>",
        cmap("<00> <FF>", "17 beginbfchar \(identity) <5A> <\(zed)> endbfchar"),
    ]
}

private let credit = "BT /F2 6 Tf 36.08 761.19 Td (BRAD FRITZ \\(D2697-1\\)) Tj ET BT /F1 10 Tf 36 700 Td (Applying pesticides is no simple task.) Tj ET"

@Test func aMapThatContradictsItsEncodingInCaseReadsTheCapitalDrawn() throws {
    let texts = try lines(document(credit, font: creditFont())).map(\.text)
    #expect(texts.contains("BRAD FRITZ (D2697-1)"), "\(texts)")
    #expect(texts.contains("Applying pesticides is no simple task."))
}

@Test func aMapIsTrustedWithoutTheFontsOwnEvidence() throws {
    // Controls: a `CharSet` listing the map's `/z` too, a symbolic font (whose built-in encoding
    // PDFKit's name cannot tell), and a map naming another letter altogether each keep the map's reading.
    for (font, expected) in [
        (creditFont(charSet: "/parenleft/parenright/hyphen/one/two/six/seven/nine/A/B/D/F/I/R/T/Z/z"), "BRAD FRITz (D2697-1)"),
        (creditFont(flags: 4), "BRAD FRITz (D2697-1)"),
        (creditFont(zed: "0071"), "BRAD FRITq (D2697-1)"),
    ] {
        let texts = try lines(document(credit, font: font)).map(\.text)
        #expect(texts.contains(expected), "\(texts)")
    }
}

// MARK: - Display lines on bare pages

@Test func aBareBackCoverSetsNoHeadingUnderTheDocumentsBody() throws {
    let page = try usdaPage(24)
    // The glyph is captured as the pipeline redraws it (the fixture's attributed runs).
    let blocks = reflow(page, documentBody: 10.5)
    #expect(headings(blocks).isEmpty, "\(headings(blocks))")
    let texts = paragraphs(blocks)
    for phrase in ["5601 Sunnyside Ave.", "Official Business", "Visit us at ars.usda.gov/ar ● Follow us at twitter.com/USDA_ARS"] {
        #expect(texts.contains { $0.contains(phrase) }, "\(phrase) in \(texts)")
    }
    // Control: measured against the page's own 8-point estimate, as before, they are headings. The
    // return address reads as one, its logo no longer between its lines (#201).
    let before = headings(reflow(page))
    #expect(before.contains("Official Business") && before.contains { $0.contains("5601 Sunnyside Ave.") }, "\(before)")
}

@Test func theDocumentsBodyDoesNotLowerAPageThatStatesItsOwn() {
    // A page of 9-point prose in a document whose body is 12 points: its own 11-point section title
    // stays a heading, and the document's body changes nothing.
    var lines: [TextLine] = [TextLine(text: "Methods of Evaluation", rect: CGRect(x: 72, y: 700, width: 160, height: 14), fontSize: 11.5)]
    for row in 0..<8 {
        lines.append(TextLine(text: "Ordinary prose of the section set in the page's own small type, line \(row).",
                              rect: CGRect(x: 72, y: 680 - CGFloat(row) * 11, width: 300, height: 11), fontSize: 9))
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    #expect(headings(reflow(page, documentBody: 12)) == ["Methods of Evaluation"])
    #expect(LayoutReconstructor.documentHeadingFloor(lines, documentBody: 12) == 0)
    #expect(LayoutReconstructor.documentHeadingFloor(Array(lines.prefix(2)), documentBody: 12) == 12 * 1.1)
}

@Test func aLowercaseLineAloneOnTheCoverHeadsNothing() throws {
    // The cover's photograph fills the page; the pipeline keeps it in the page's reference image and
    // reflows the lines over it, so no region takes them here either.
    let page = try usdaPage(1)
    let blocks = reflow(page, documentBody: 10.5, regions: false)
    let found = headings(blocks)
    #expect(found.contains("Keeping Our Troops Safe") && found.contains("From Insects"), "\(found)")
    #expect(!found.contains("pages 2, 4-14"), "\(found)")
    #expect(paragraphs(blocks).contains("pages 2, 4-14"))
}

@Test func aLowercaseLineStackedInATitleKeepsItsReading() {
    // A two-line display title whose second line opens in lowercase is still one heading's lines, and
    // a lone capitalized line of the same size is still a heading.
    let lines = [
        TextLine(text: "The Role of", rect: CGRect(x: 72, y: 700, width: 200, height: 28), fontSize: 24),
        TextLine(text: "the Federal Reserve", rect: CGRect(x: 72, y: 672, width: 260, height: 28), fontSize: 24),
        TextLine(text: "Monetary Policy", rect: CGRect(x: 72, y: 400, width: 200, height: 28), fontSize: 24),
    ] + (0..<8).map { row in
        TextLine(text: "Ordinary prose of the chapter set in its body type, line number \(row) of eight.",
                 rect: CGRect(x: 72, y: 640 - CGFloat(row) * 13, width: 400, height: 13), fontSize: 10)
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    let found = headings(reflow(page))
    #expect(found.contains("The Role of the Federal Reserve") && found.contains("Monetary Policy"), "\(found)")
}

// MARK: - A sub-heading over its sidebar's picture

@Test func aSidebarTitleHeadsTheTextPastItsPicture() throws {
    let page = try usdaPage(9)
    let styles = try LayoutReconstructor.labelEvidence(on: usdaPage(19))
    let blocks = reflow(page, labelStyles: styles)
    #expect(headings(blocks) == ["Fighting Filth Flies"], "\(headings(blocks))")
    // The title stands before the sidebar's picture and text.
    let order = blocks.map { block -> String in
        if case .image = block.content { return "image" }
        return String(block.text.prefix(20))
    }
    let title = try #require(order.firstIndex(of: "Fighting Filth Flies"))
    let opening = try #require(order.firstIndex { $0.hasPrefix("Nonbiting flies") })
    #expect(title < opening)
}

@Test func aTitleOverAPictureNeedsItsTextCloseBeneath() throws {
    let page = try usdaPage(9)
    let styles = try LayoutReconstructor.labelEvidence(on: usdaPage(19))
    // Control: without the picture the title has nothing beneath it within reach.
    var bare = page
    bare.graphics = page.graphics.filter { !($0.minX > 200 && $0.minX < 230) }
    #expect(!headings(reflow(bare, labelStyles: styles)).contains("Fighting Filth Flies"))
    // Control: the sidebar's text moved five bodies further down is no longer the title's opening.
    var far = page
    far.lines = page.lines.map { line in
        guard line.rect.minX > 215, line.rect.maxX < 400, line.rect.maxY < 570 else { return line }
        var moved = line
        moved.rect.origin.y -= 52
        return moved
    }
    #expect(!headings(reflow(far, labelStyles: styles)).contains("Fighting Filth Flies"))
    // Control: without the book's recurring nine-point bold style the line has no label evidence.
    #expect(!headings(reflow(page)).contains("Fighting Filth Flies"))
}

// MARK: - Word breaks the lexicon decides

@Test func anEnglishLexiconDecidesABreakTheBookCannot() throws {
    guard TextLayerPlausibility.lexiconContains("companies") != nil else { return }
    let english: Set<String> = [LayoutReconstructor.englishLexiconKey]
    for (left, right, joined) in [("commercial com-", "panies interested", "commercial companies interested"),
                                  ("a range of infec-", "tions in humans", "a range of infections in humans"),
                                  ("label compli-", "ance with many", "label compliance with many")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: english, page: 6, warnings: &warnings) == joined)
        #expect(warnings.isEmpty)
        // Control: without the declared language the break stays undecided, hyphen kept and warned.
        var undecided: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: [], page: 6, warnings: &undecided) == left + right)
        #expect(undecided.map(\.code) == [.uncertainHyphen])
    }
}

@Test func theLexiconLeavesCompoundsAndShortHalves() throws {
    guard TextLayerPlausibility.lexiconContains("companies") != nil else { return }
    let english: Set<String> = [LayoutReconstructor.englishLexiconKey]
    // Halves that are both words (`on-going`), a one-letter half (`e-mail`), a joined word the lexicon
    // does not hold, and a compound the book prints keep the hyphen.
    for (left, right, vocabulary) in [("on-", "going work", english), ("e-", "mail it", english),
                                      ("zorbu-", "latinex tonight", english),
                                      ("com-", "panies", english.union(["com-panies"]))] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: vocabulary, page: 1, warnings: &warnings) == left + right,
                "\(left)\(right)")
    }
}
