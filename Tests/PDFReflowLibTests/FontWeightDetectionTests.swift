import CoreGraphics
import Foundation
import PDFKit
import Testing
#if os(macOS)
import AppKit
private typealias WeightTestFont = NSFont
#else
import UIKit
private typealias WeightTestFont = UIFont
#endif
@testable import PDFReflowLib

// Bold weights PDFKit cannot name (#125). PDFKit reports an embedded font by name only when the
// system has one: every Fed, 9/11, Wallace, Our Flag and DGA run is `Helvetica`, and a font named
// `Dm`, `Demi` or `Semibold` never contained `bold`. The page's font resources state the weight
// in `BaseFont` and `FontDescriptor`. Synthetic PDFs reproduce both forms with controls; source
// fixtures (`*-weights`, captured with the `bold` run field) check each book that changes.

// MARK: - Classification

@Test func fontNamesStateBoldWeightsAndLighterWeightsStayRegular() {
    let bold = ["KGIFBZ+FranklinGothicLTPro-Dm", "FZPRJJ+FranklinGothicLTPro-DmCm", "BIUDFR+ITCFranklinGothicStd-Demi",
                "KAGIPE+Bembo-Semibold", "GRUNXH+MinionPro-Semibold", "Arial,Bold", "KAGOIP+Bembo-BoldItalic",
                "HelveticaNeueLTStd-Hv", "HelveticaNeueLTStd-Blk", "Arial-Black", "Roboto-ExtraBold", "MyriadPro-SemiboldIt",
                "Univers-SmBd", "*Times New Roman-Bold-256-Identity-H", "RULTEX+EuropeanComputerModern-BoldExtended12pt",
                "CXWKAE+CMBX12", "FNNCFZ+CMMIB10", "UAECPR+CMBSY10", "FCHKCL+dcbx100120", "cmssbx10", "SnellRoundhand-BoldScript",
                "Bookman-Demi", "ITCBookman-DemiItalic"]
    for name in bold {
        #expect(FontWeightReader.weight(baseFont: name, fontWeight: nil, flags: nil) == .bold, "\(name)")
    }
    let regular = ["NSVCRT+FranklinGothicLTPro-Bk", "QNEFHN+FranklinGothicLTPro-Md", "Roboto-Medium", "ProximaNova-Medium",
                   "FranklinGothic-Medium", "KAFHKN+Bembo", "Bembo-Italic", "Times-Roman", "Lora-Regular", "HelveticaNeueLTPro-Lt",
                   "MyriadPro-SemiLight", "SourceSans-DemiLight", "CMR12", "CMMI12", "cmb", "bbm10", "Courier", "HiddenHorzOCR",
                   "Bookman-Light", "HelveticaNeueLight"]
    for name in regular {
        #expect(FontWeightReader.weight(baseFont: name, fontWeight: nil, flags: nil) == .regular, "\(name)")
    }
}

@Test func descriptorWeightDecidesOnlyWhereTheNameStatesNone() {
    // A name stating no weight: FontWeight 600 or more, or the ForceBold flag, is bold.
    #expect(FontWeightReader.weight(baseFont: "SyntheticSans", fontWeight: 700, flags: 32) == .bold)
    #expect(FontWeightReader.weight(baseFont: "LucidaSansUnicode", fontWeight: 600, flags: 32) == .bold)
    #expect(FontWeightReader.weight(baseFont: "StoneSerif", fontWeight: nil, flags: 262_178) == .bold)
    #expect(FontWeightReader.weight(baseFont: nil, fontWeight: 700, flags: nil) == .bold)
    // Controls: weights below 600, the SmallCap flag (bit 18, not ForceBold) and no evidence.
    #expect(FontWeightReader.weight(baseFont: "SyntheticSans", fontWeight: 500, flags: 32) == .regular)
    #expect(FontWeightReader.weight(baseFont: "Bembo-SC", fontWeight: nil, flags: 131_078) == .regular)
    #expect(FontWeightReader.weight(baseFont: "SyntheticSans", fontWeight: nil, flags: nil) == .regular)
    // Conflicts are read conservatively: a stated lighter weight is never overridden, and a demi or
    // heavy name under a descriptor below 500 is not bold. `Bold` stays bold, as PDFKit's name rule reads it.
    #expect(FontWeightReader.weight(baseFont: "Synthetic-Medium", fontWeight: 700, flags: 262_144) == .regular)
    #expect(FontWeightReader.weight(baseFont: "Synthetic-Dm", fontWeight: 400, flags: nil) == .regular)
    #expect(FontWeightReader.weight(baseFont: "Synthetic-Bold", fontWeight: 400, flags: nil) == .bold)
}

// MARK: - Synthetic reproducers

private struct WeightFont {
    var baseFont: String
    var fontWeight: Int?
    var toUnicode = true
}

/// One page whose shows each select one of `fonts` (non-embedded Type1, WinAnsi, 600-unit widths).
private func weightDocument(_ fonts: [WeightFont], shows: [(font: Int, x: Int, y: Int, text: String)]) throws -> PDFDocument {
    var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "", ""]
    var names: [String] = []
    for (index, font) in fonts.enumerated() {
        let fontObject = objects.count + 1
        var entries = "/Type /Font /Subtype /Type1 /BaseFont /\(font.baseFont) /Encoding /WinAnsiEncoding"
            + " /FirstChar 32 /LastChar 126 /Widths [\(Array(repeating: "600", count: 95).joined(separator: " "))]"
        objects.append("")
        // Core Graphics lays out a font it cannot find only with a descriptor's metrics.
        objects.append("<< /Type /FontDescriptor /FontName /\(font.baseFont) /Flags 32 /FontBBox [0 -200 1000 900]"
            + " /ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80"
            + (font.fontWeight.map { " /FontWeight \($0)" } ?? "") + " >>")
        entries += " /FontDescriptor \(objects.count) 0 R"
        if font.toUnicode {
            objects.append(testPDFStream("""
                /CIDInit /ProcSet findresource begin 12 dict begin begincmap
                1 begincodespacerange <00> <FF> endcodespacerange
                1 beginbfrange <20> <7E> <0020> endbfrange
                endcmap CMapName currentdict /CMap defineresource pop end end
                """))
            entries += " /ToUnicode \(objects.count) 0 R"
        }
        objects[fontObject - 1] = "<< \(entries) >>"
        names.append("/F\(index) \(fontObject) 0 R")
    }
    objects[2] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << \(names.joined(separator: " ")) >> >> /Contents 4 0 R >>"
    objects[3] = testPDFStream(shows.map { "BT /F\($0.font) 12 Tf \($0.x) \($0.y) Td (\($0.text)) Tj ET" }.joined(separator: "\n"))
    return try #require(PDFDocument(data: testPDF(objects: objects)))
}

private func styledLines(_ document: PDFDocument) throws -> [TextLine] {
    try NativeTextReader.lines(on: try #require(document.page(at: 0)), limit: 100_000)
}

/// The text of a line's runs set in bold.
private func boldText(_ line: TextLine) -> String {
    line.content.elements.map {
        if case let .text(value, style) = $0, style.contains(.bold) { value } else { "" }
    }.joined()
}

private func line(_ lines: [TextLine], _ prefix: String) throws -> TextLine {
    try #require(lines.first { $0.text.hasPrefix(prefix) }, "no line \(prefix)")
}

@Test func demiNamedFontReadsBoldThroughPDFKitsSubstitutedName() throws {
    let document = try weightDocument([WeightFont(baseFont: "KGIFBZ+SyntheticGothic-Dm"), WeightFont(baseFont: "SyntheticGothic-Demi"),
                                       WeightFont(baseFont: "SyntheticGothic-Bk")],
                                      shows: [(0, 72, 700, "Tool Definition"), (1, 72, 650, "Discount window"), (2, 72, 600, "Interest paid on funds")])
    let lines = try styledLines(document)
    // PDFKit names none of these fonts bold, so its name rule alone reads every line regular; the
    // resources do not.
    let page = try #require(document.page(at: 0))
    let names = (page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? []).compactMap {
        ($0.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? WeightTestFont)?.fontName
    }
    #expect(names.count == 3 && names.allSatisfy { !$0.lowercased().contains("bold") })
    #expect(try boldText(line(lines, "Tool Definition")) == "Tool Definition")
    #expect(try boldText(line(lines, "Discount window")) == "Discount window")
    // Control: the book weight of the same family.
    #expect(try boldText(line(lines, "Interest paid")) == "")
}

@Test func fontWeight700DescriptorUnderANameWithoutAWeightReadsBold() throws {
    let document = try weightDocument([WeightFont(baseFont: "SyntheticSans", fontWeight: 700), WeightFont(baseFont: "SyntheticSans", fontWeight: 400),
                                       WeightFont(baseFont: "SyntheticSans-Medium", fontWeight: 700), WeightFont(baseFont: "Helvetica-Bold")],
                                      shows: [(0, 72, 700, "Weighted title"), (1, 72, 650, "Regular prose line"),
                                              (2, 72, 600, "Medium conflict"), (3, 72, 550, "Named bold control")])
    let lines = try styledLines(document)
    #expect(try boldText(line(lines, "Weighted title")) == "Weighted title")
    #expect(try boldText(line(lines, "Regular prose")) == "")
    #expect(try boldText(line(lines, "Medium conflict")) == "")
    // Positive control: PDFKit's own name rule is unchanged.
    #expect(try boldText(line(lines, "Named bold")) == "Named bold control")
}

@Test func mixedWeightLineMarksOnlyTheBoldFontsCharactersWhenItsShowsSpellIt() throws {
    let fonts = [WeightFont(baseFont: "SyntheticSerif-Semibold"), WeightFont(baseFont: "SyntheticSerif")]
    let lines = try styledLines(try weightDocument(fonts, shows: [(0, 72, 700, "NEADS:"), (1, 124, 700, "He is heading into Washington?")]))
    let transcript = try line(lines, "NEADS:")
    #expect(transcript.text == "NEADS: He is heading into Washington?")
    #expect(boldText(transcript).trimmingCharacters(in: .whitespaces) == "NEADS:")
    // Negative control: without ToUnicode maps the shows cannot be aligned with PDFKit's
    // characters, so a line mixing weights is left as PDFKit read it.
    let undecoded = fonts.map { WeightFont(baseFont: $0.baseFont, toUnicode: false) }
    let plain = try line(try styledLines(try weightDocument(undecoded, shows: [(0, 72, 700, "NEADS:"), (1, 124, 700, "He is heading into Washington?")])), "NEADS:")
    #expect(boldText(plain) == "")
    // ... while a wholly bold line needs no alignment.
    let whole = try line(try styledLines(try weightDocument(undecoded, shows: [(0, 72, 700, "The Hijacking of")])), "The Hijacking")
    #expect(boldText(whole) == "The Hijacking of")
}

// MARK: - Line matching

private func show(_ x: CGFloat, _ y: CGFloat, _ text: String?, _ weight: FontWeightReader.Weight, size: CGFloat = 24,
                  font: Int = 1) -> FontWeightReader.Show {
    FontWeightReader.Show(origin: CGPoint(x: x, y: y), size: size, font: font, weight: weight, text: text, placed: true)
}

/// PDFKit-like runs: each piece its own run (a distinct attribute value), all named Helvetica.
private func pdfkitRuns(_ pieces: [String]) -> NSAttributedString {
    let value = NSMutableAttributedString()
    for (index, piece) in pieces.enumerated() {
        value.append(NSAttributedString(string: piece, attributes: [.font: WeightTestFont(name: "Helvetica", size: 10)!,
                                                                    NSAttributedString.Key("run"): index]))
    }
    return value
}

private func marked(_ attributed: NSAttributedString) -> String {
    var result = ""
    attributed.enumerateAttribute(FontWeightReader.boldAttribute, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
        let text = (attributed.string as NSString).substring(with: range)
        result += value == nil ? text : "[\(text)]"
    }
    return result
}

@Test func showInSeveralLinesBelongsToTheClearlyTighterLine() {
    // Fed page 66's opener: the first line is as tall as its 70-point numeral and reaches over the
    // second title line's baseline.
    let tall = CGRect(x: 89, y: 636.48, width: 372.48, height: 81.48)
    let second = CGRect(x: 167, y: 653.54, width: 273.24, height: 28.42)
    let shows = [show(89, 653.98, "5", .regular, size: 70, font: 1), show(167, 685.54, "Supervising and Regulating ", .bold, font: 2),
                 show(167, 659.54, "Financial Institutions and ", .bold, font: 2)]
    let first = FontWeightReader.apply(shows, to: pdfkitRuns(["5 Supervising and Regulating"]), bounds: tall, allBounds: [tall, second])
    #expect(marked(first) == "5 [Supervising and Regulating]")
    let next = FontWeightReader.apply(shows, to: pdfkitRuns(["Financial Institutions and"]), bounds: second, allBounds: [tall, second])
    #expect(marked(next) == "[Financial Institutions and]")
    // Controls: lines of like height overlapping stay ambiguous, and a line that needed the choice
    // is not marked without decoded text to confirm it.
    let alike = CGRect(x: 167, y: 640, width: 273, height: 70)
    #expect(marked(FontWeightReader.apply(shows, to: pdfkitRuns(["5 Supervising and Regulating"]), bounds: tall, allBounds: [tall, alike]))
            == "5 Supervising and Regulating")
    let undecoded = shows.map { var copy = $0; copy.text = nil; return copy }
    #expect(marked(FontWeightReader.apply(undecoded.filter { $0.weight == .bold }, to: pdfkitRuns(["Supervising and Regulating"]),
                                          bounds: tall, allBounds: [tall, second])) == "Supervising and Regulating")
}

@Test func lineIsMarkedOnlyWhenItsShowsExplainItsStart() {
    let bounds = CGRect(x: 72, y: 698, width: 300, height: 14)
    // Wholly bold without decoded text: the leftmost show starts at the line's edge.
    #expect(marked(FontWeightReader.apply([show(72.4, 700, nil, .bold, size: 12)], to: pdfkitRuns(["Boarding the Flights"]),
                                          bounds: bounds, allBounds: [bounds])) == "[Boarding the Flights]")
    // Control: the first show on the line starts two ems in, so a show begun on another line may draw
    // its opening glyphs.
    #expect(marked(FontWeightReader.apply([show(96, 700, nil, .bold, size: 12)], to: pdfkitRuns(["Boarding the Flights"]),
                                          bounds: bounds, allBounds: [bounds])) == "Boarding the Flights")
    // Control: decoded shows that do not spell the line leave it unmarked.
    #expect(marked(FontWeightReader.apply([show(72, 700, "Boarding", .bold, size: 12)], to: pdfkitRuns(["Boarding the Flights"]),
                                          bounds: bounds, allBounds: [bounds])) == "Boarding the Flights")
}

@Test func whitespaceFollowsPDFKitsRunsBesideMarkedCharacters() {
    let bounds = CGRect(x: 72, y: 698, width: 300, height: 14)
    let shows = [show(72, 700, "Figure 2-8.", .bold, size: 10), show(125, 700, " Caption text", .regular, size: 10)]
    // A space inside a run whose other characters are bold is bold; one inside a regular run is not.
    #expect(marked(FontWeightReader.apply(shows, to: pdfkitRuns(["Figure 2-8. ", "Caption text"]), bounds: bounds, allBounds: [bounds]))
            == "[Figure 2-8. ]Caption text")
    #expect(marked(FontWeightReader.apply(shows, to: pdfkitRuns(["Figure 2-8.", " Caption text"]), bounds: bounds, allBounds: [bounds]))
            == "[Figure 2-8.] Caption text")
    // A run of spaces alone stays unmarked; in a run PDFKit merged across fonts a space takes the weight before it.
    #expect(marked(FontWeightReader.apply(shows, to: pdfkitRuns(["Figure 2-8.", " ", "Caption text"]), bounds: bounds, allBounds: [bounds]))
            == "[Figure 2-8.] Caption text")
    #expect(marked(FontWeightReader.apply(shows, to: pdfkitRuns(["Figure 2-8. Caption text"]), bounds: bounds, allBounds: [bounds]))
            == "[Figure 2-8. ]Caption text")
}

@Test func readerFindsNoEvidenceOnPagesWithoutABoldFont() throws {
    let document = try weightDocument([WeightFont(baseFont: "SyntheticSerif-Roman"), WeightFont(baseFont: "SyntheticSerif-Italic")],
                                      shows: [(0, 72, 700, "Plain"), (1, 72, 650, "Italic")])
    let page = try #require(document.page(at: 0)?.pageRef)
    #expect(FontWeightReader.read(page).isEmpty)
    #expect(FontWeightReader.read(page, fonts: nil).count == 2)
}

// MARK: - Source fixtures

private func sourceBold(_ name: String, fontWeights: Bool = true) throws -> [String: String] {
    let lines = try SourceLayoutFixture.load(name).styledContent(fontWeights: fontWeights).lines
    return Dictionary(lines.map { ($0.text, boldText($0)) }, uniquingKeysWith: { first, _ in first })
}

@Test func sourceFedDemiTableTitleAndLabelsCarryBold() throws {
    let bold = try sourceBold("fed-46-weights")
    #expect(bold["Table 3.1 Traditional tools in an ample-reserves regime"] == "Table 3.1 Traditional tools in an ample-reserves regime")
    // The tool labels. The header row reaches layout split at the rule grid's joints; fixtures
    // replay only PDFKit's unsplit selection, so its runs are read directly.
    for label in ["Interest on reserve balances", "(IORB)", "Overnight reverse repurchase"] {
        #expect(bold[label] == label, "\(label)")
    }
    let fixture = try SourceLayoutFixture.load("fed-46-weights")
    let header = try #require(fixture.attributedLines.first { $0.text.hasPrefix("Tool Definition") })
    let headerRuns = NativeTextReader.inlineText(from: header.attributedString())
    #expect(headerRuns.elements.allSatisfy { if case let .text(_, style) = $0 { style.contains(.bold) } else { false } })
    #expect(NativeTextReader.inlineText(from: header.attributedString(fontWeights: false)).elements.allSatisfy {
        if case let .text(_, style) = $0 { !style.contains(.bold) } else { true }
    })
    // Book-weight cells stay regular.
    #expect(bold.filter { $0.key.hasPrefix("Interest paid on funds") }.allSatisfy { $0.value.isEmpty })
    #expect(bold.values.contains { !$0.isEmpty })
    // Negative control: PDFKit's runs alone name every font Helvetica.
    #expect(try sourceBold("fed-46-weights", fontWeights: false).values.allSatisfy { $0.isEmpty })
}

@Test func sourceFedChapterOpenerMarksTheTitleButNotItsBookWeightNumeral() throws {
    // The first line is as tall as the 70-point `5` and reaches over the title's second baseline;
    // that show belongs to the tighter second line.
    let bold = try sourceBold("fed-66-weights")
    #expect(bold["5 Supervising and Regulating"] == "Supervising and Regulating")
    #expect(bold["Financial Institutions and"] == "Financial Institutions and")
    #expect(bold["Activities"] == "Activities")
}

private func reflow(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle>) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                      warnings: &warnings, labelStyles: labelStyles)
}

private func headingTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

private func paragraphTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

@Test func source911SemiboldSubheadStandsApartFromItsParagraph() throws {
    let fixture = try SourceLayoutFixture.load("911-19-weights")
    let page = fixture.styledContent()
    // The book repeats this label style on 164 pages; the page's own evidence stands for it.
    let styles = LayoutReconstructor.labelEvidence(on: page)
    #expect(!styles.isEmpty)
    let blocks = reflow(page, labelStyles: styles)
    #expect(headingTexts(blocks).contains("Boarding the Flights"))
    #expect(paragraphTexts(blocks).contains { $0.hasPrefix("Boston: American 11 and United 175. Atta and Omari") })
    // Negative control: without resource weights the subhead is not bold, so even with the book's
    // label styles it opens its paragraph, as before #125.
    let plain = fixture.styledContent(fontWeights: false)
    let fused = reflow(plain, labelStyles: styles)
    #expect(!headingTexts(fused).contains("Boarding the Flights"))
    #expect(paragraphTexts(fused).contains { $0.hasPrefix("Boarding the Flights Boston: American 11") })
}

@Test func source911RetagsAStandaloneSemiboldQuestionAsAHeading() throws {
    let styles = LayoutReconstructor.labelEvidence(on: try SourceLayoutFixture.load("911-19-weights").styledContent())
    let fixture = try SourceLayoutFixture.load("911-62-weights")
    #expect(headingTexts(reflow(fixture.styledContent(), labelStyles: styles)).contains("What If?"))
    #expect(paragraphTexts(reflow(fixture.styledContent(fontWeights: false), labelStyles: [])).contains("What If?"))
}

@Test func source911TranscriptSpeakerLabelsOpenTheirOwnParagraphs() throws {
    let fixture = try SourceLayoutFixture.load("911-44-weights")
    let turns = paragraphTexts(reflow(fixture.styledContent(), labelStyles: []))
    // Fixture replay styles only lines whose text PDFKit's selection spells unrepaired; lines the
    // word-space reader repaired (#119: `FAA: Yes. This could be…`) reach layout plain here, though
    // the pipeline applies weights after the repair.
    for turn in ["NEADS: Okay. So American 11 isn’t the hijack at all then, right?", "FAA: No, he is a hijack.",
                 "NEADS: He—American 11 is a hijack?", "FAA: Yes."] {
        #expect(turns.contains(turn), "\(turn)")
    }
    // A run-in head closing with a period is emphasis, not a section opening (#60's rule).
    #expect(turns.contains { $0.hasPrefix("Military Notification and Response. NORAD heard nothing") })
    // Negative control: without resource weights the turns run together.
    let fused = paragraphTexts(reflow(fixture.styledContent(fontWeights: false), labelStyles: []))
    #expect(!fused.contains("FAA: No, he is a hijack."))
    #expect(fused.contains { $0.contains("right? FAA: No, he is a hijack.") })
}

@Test func sourceTitlesAndLeadInsGainBoldEmphasisInOtherBooks() throws {
    let wallace = try sourceBold("algebra-7-weights")
    #expect(wallace["Example 1."] == "Example 1.")
    #expect(wallace["Pre-Algebra - Integers"] == "Pre-Algebra - Integers")
    let dga = try sourceBold("dga-3-weights")
    #expect(dga["Prioritize Protein Foods at Every Meal"] == "Prioritize Protein Foods at Every Meal")
    let flag = try SourceLayoutFixture.load("flag-7-weights")
    let flagBold = try sourceBold("flag-7-weights")
    #expect(flagBold["The History of the Stars and Stripes"] == "The History of the Stars and Stripes")
    // The drop cap is set in a bold script face, but a display initial is ornament: no emphasis.
    let opener = try #require(flag.styledContent().lines.first { $0.text.hasPrefix("T he Stars") || $0.text.hasPrefix("The Stars") })
    #expect(boldText(opener).isEmpty)
    for name in ["algebra-7-weights", "dga-3-weights", "flag-7-weights"] {
        #expect(try sourceBold(name, fontWeights: false).values.allSatisfy { $0.isEmpty }, "\(name)")
    }
}
