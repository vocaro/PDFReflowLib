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
    /// `WinAnsiEncoding` by name; without it (and without ToUnicode) the codes cannot be decoded.
    var encoding = true
    var italicAngle = 0
    var flags = 32
    /// The ToUnicode map's codespace declaration.
    var codespace = "1 begincodespacerange <00> <FF> endcodespacerange"
}

/// One page whose shows each select one of `fonts` (non-embedded Type1, 600-unit widths).
private func weightDocument(_ fonts: [WeightFont], shows: [(font: Int, x: Int, y: Int, text: String)]) throws -> PDFDocument {
    var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "", ""]
    var names: [String] = []
    for (index, font) in fonts.enumerated() {
        let fontObject = objects.count + 1
        var entries = "/Type /Font /Subtype /Type1 /BaseFont /\(font.baseFont)" + (font.encoding ? " /Encoding /WinAnsiEncoding" : "")
            + " /FirstChar 32 /LastChar 126 /Widths [\(Array(repeating: "600", count: 95).joined(separator: " "))]"
        objects.append("")
        // Core Graphics lays out a font it cannot find only with a descriptor's metrics.
        objects.append("<< /Type /FontDescriptor /FontName /\(font.baseFont) /Flags \(font.flags) /FontBBox [0 -200 1000 900]"
            + " /ItalicAngle \(font.italicAngle) /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80"
            + (font.fontWeight.map { " /FontWeight \($0)" } ?? "") + " >>")
        entries += " /FontDescriptor \(objects.count) 0 R"
        if font.toUnicode {
            objects.append(testPDFStream("""
                /CIDInit /ProcSet findresource begin 12 dict begin begincmap
                \(font.codespace)
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
    // Without ToUnicode maps, a Type1 font's WinAnsi encoding still decodes its codes (Wallace's
    // Computer Modern fonts, #133), so the label is marked.
    let encoded = fonts.map { WeightFont(baseFont: $0.baseFont, toUnicode: false) }
    let winAnsi = try line(try styledLines(try weightDocument(encoded, shows: [(0, 72, 700, "NEADS:"), (1, 124, 700, "He is heading into Washington?")])), "NEADS:")
    #expect(boldText(winAnsi).trimmingCharacters(in: .whitespaces) == "NEADS:")
    // Negative control: with neither a map nor an encoding the shows cannot be aligned with PDFKit's
    // characters, so a line mixing weights is left as PDFKit read it.
    let undecoded = fonts.map { WeightFont(baseFont: $0.baseFont, toUnicode: false, encoding: false) }
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

@Test func readerFindsNoEvidenceOnPagesWithoutABoldOrItalicFont() throws {
    let document = try weightDocument([WeightFont(baseFont: "SyntheticSerif-Roman"), WeightFont(baseFont: "CMMI12", italicAngle: -14)],
                                      shows: [(0, 72, 700, "Plain"), (1, 72, 650, "x")])
    let page = try #require(document.page(at: 0)?.pageRef)
    #expect(FontWeightReader.read(page).isEmpty)
    #expect(FontWeightReader.read(page, fonts: nil).count == 2)
    // Positive control: an italic text font is evidence since #133.
    let italic = try weightDocument([WeightFont(baseFont: "SyntheticSerif-Roman"), WeightFont(baseFont: "SyntheticSerif-Italic")],
                                    shows: [(0, 72, 700, "Plain"), (1, 72, 650, "Italic")])
    #expect(FontWeightReader.read(try #require(italic.page(at: 0)?.pageRef)).count == 2)
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

// MARK: - Slope, Libertine weights, composite maps and run merging (#133)

// PDFKit's `Helvetica` renaming hides italic as it hid bold: `Bembo-Italic` (9/11),
// `FranklinGothicLTPro-BkIt` (Fed), `CenturySchoolbook-Italic` (Supreme Court) and `LinLibertineTI`
// (arXiv) reach extraction as upright Helvetica. The same resources state the slope in the name
// and the descriptor's Italic flag and ItalicAngle. Math italic and script faces lean without
// emphasis and stay upright.

/// The text of a line's runs set in italic.
private func italicText(_ line: TextLine) -> String {
    line.content.elements.map {
        if case let .text(value, style) = $0, style.contains(.italic) { value } else { "" }
    }.joined()
}

@Test func fontNamesStateItalicAndUprightSlopes() {
    let italic = ["KAFJDA+Bembo-Italic", "WODUNB+FranklinGothicLTPro-BkIt", "CSBZTP+FranklinGothicLTPro-DmIt", "OFKQWA+Lora-Italic",
                  "TimesNewRomanPS-ItalicMT", "TimesNewRoman,Italic", "Helvetica-Oblique", "Roboto-BoldItalic", "MyriadPro-SemiboldIt",
                  "SJYHJJ+FrutigerLTStd-LightItalic", "FGHYMC+EuropeanComputerModern-ItalicRegular12pt", "cmti10", "CMBXTI10", "cmsl10",
                  "cmitt10", "FCHMDC+dcti10084", "ecbi1000", "SFTI1000", "MWZXMA+LinLibertineTI", "LinLibertineTBI", "LinBiolinumTO",
                  "QSABOY+Corbel-BoldItalic", "PGIBGF+CenturySchoolbook-Italic", "Garamond-Kursiv"]
    for name in italic {
        #expect(FontWeightReader.nameSlope(name) == .italic, "\(name)")
        #expect(FontWeightReader.isItalic(baseFont: name, italicAngle: nil, flags: nil), "\(name)")
    }
    let upright = ["KAFHKN+Bembo", "Times-Roman", "TimesNewRoman", "Sabon-Roman", "ZMRZBV+LinLibertineT", "HCPGUR+LinLibertineTB",
                   "PZGVTZ+CMR12", "GQFBEA+CMSY10", "cmex10", "FCHKGB+dcr10084", "SFRM1000", "Lora-Regular", "Bembo-Semibold",
                   "FranklinGothicLTPro-Bk", "Italian-Old-Style-Unit"]
    for name in upright {
        #expect(FontWeightReader.nameSlope(name) != .italic, "\(name)")
        // A name stating upright or a TeX shape overrides a leaning descriptor (TeX's `CMSY10` leans at -14°).
        if FontWeightReader.nameSlope(name) == .upright {
            #expect(!FontWeightReader.isItalic(baseFont: name, italicAngle: -14, flags: 96), "\(name)")
        }
    }
    #expect(FontWeightReader.nameSlope("Italian-Old-Style-Unit") == .unstated)
}

@Test func mathItalicAndScriptFacesAreNotEmphasis() {
    // TeX's and newtx's math italic set variables, a notation: Wallace would gain 14,183 `<em>` runs.
    for name in ["MXANZU+CMMI12", "cmmib10", "FCHMEI+cmmi10084", "RXIKPM+LibertineMathMI", "ICKJDT+LibertineMathMI7",
                 "ZMKHJD+NewTXMI", "OYHSJR+NewTXMI5", "PPKSGE+txmiaX"] {
        #expect(FontWeightReader.nameSlope(name) == .mathItalic, "\(name)")
        #expect(!FontWeightReader.isItalic(baseFont: name, italicAngle: -14, flags: 68), "\(name)")
    }
    // A name stating no slope: the Italic flag or an angle of 5° or more is italic.
    #expect(FontWeightReader.isItalic(baseFont: "SyntheticSans", italicAngle: 0, flags: 96))
    #expect(FontWeightReader.isItalic(baseFont: "SyntheticSans", italicAngle: -12, flags: 32))
    #expect(FontWeightReader.isItalic(baseFont: nil, italicAngle: -12, flags: 34))
    // Controls: a slight angle, no evidence, a symbol font, and script faces by flag or name
    // (Our Flag's `SnellRoundhand-BoldScript` titles: Flags 262240, ItalicAngle -40).
    #expect(!FontWeightReader.isItalic(baseFont: "SyntheticSans", italicAngle: -1, flags: 32))
    #expect(!FontWeightReader.isItalic(baseFont: "SyntheticSans", italicAngle: nil, flags: nil))
    #expect(!FontWeightReader.isItalic(baseFont: "txsys", italicAngle: -12, flags: 4))
    #expect(!FontWeightReader.isItalic(baseFont: "SnellRoundhand-BoldScript", italicAngle: -40, flags: 262_240))
    #expect(!FontWeightReader.isItalic(baseFont: "SyntheticHand", italicAngle: -20, flags: 104))
    #expect(FontWeightReader.weight(baseFont: "SnellRoundhand-BoldScript", fontWeight: nil, flags: 262_240) == .bold)
}

@Test func libertineAndCMSuperNamesStateTheirWeight() {
    for name in ["HCPGUR+LinLibertineTB", "IVKDOT+LinBiolinumTB", "LinLibertineTZ", "LinLibertineTBI", "LinLibertineOB",
                 "sfbx1200", "ecbi1000", "SFSX1000"] {
        #expect(FontWeightReader.weight(baseFont: name, fontWeight: nil, flags: 4) == .bold, "\(name)")
    }
    for name in ["ZMRZBV+LinLibertineT", "MWZXMA+LinLibertineTI", "ZIZFHV+LinBiolinumT", "LinBiolinumTO", "LinLibertineO",
                 "sfrm1000", "SFTI1000", "LinLibertineTX", "LinLibertineDisplay"] {
        #expect(FontWeightReader.weight(baseFont: name, fontWeight: nil, flags: 4) == .regular, "\(name)")
    }
}

@Test func italicFontsReadItalicThroughPDFKitsSubstitutedName() throws {
    let fonts = [WeightFont(baseFont: "SyntheticSerif-Italic", italicAngle: -12, flags: 98), WeightFont(baseFont: "SyntheticGothic-BkIt"),
                 WeightFont(baseFont: "SyntheticSans", italicAngle: -12, flags: 96), WeightFont(baseFont: "CMMI12", italicAngle: -14, flags: 96),
                 WeightFont(baseFont: "SyntheticRoundhand-BoldScript", italicAngle: -40, flags: 96),
                 WeightFont(baseFont: "SyntheticSerif-Roman", italicAngle: -12, flags: 96)]
    let document = try weightDocument(fonts, shows: [(0, 72, 700, "The Sullivans attack"), (1, 72, 650, "Annual Report tables"),
                                                     (2, 72, 600, "Leaning descriptor"), (3, 72, 550, "xyz"),
                                                     (4, 72, 500, "The History of"), (5, 72, 450, "Upright roman")])
    let page = try #require(document.page(at: 0))
    let names = (page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? []).compactMap {
        ($0.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? WeightTestFont)?.fontName.lowercased()
    }
    #expect(names.count == 6 && names.allSatisfy { !$0.contains("italic") && !$0.contains("oblique") })
    let lines = try styledLines(document)
    #expect(try italicText(line(lines, "The Sullivans")) == "The Sullivans attack")
    #expect(try italicText(line(lines, "Annual Report")) == "Annual Report tables")
    #expect(try italicText(line(lines, "Leaning")) == "Leaning descriptor")
    // Controls: math italic, a script face and a name stating roman stay upright.
    #expect(try italicText(line(lines, "xyz")) == "")
    #expect(try italicText(line(lines, "The History")) == "")
    #expect(try italicText(line(lines, "Upright")) == "")
}

@Test func mixedSlopeLineMarksOnlyTheItalicShipName() throws {
    let fonts = [WeightFont(baseFont: "SyntheticSerif"), WeightFont(baseFont: "SyntheticSerif-Italic", italicAngle: -12, flags: 96)]
    let lines = try styledLines(try weightDocument(fonts, shows: [(0, 72, 700, "the USS"), (1, 128, 700, "Cole"), (0, 162, 700, "bombing")]))
    let text = try line(lines, "the USS")
    #expect(text.text == "the USS Cole bombing")
    #expect(italicText(text).trimmingCharacters(in: .whitespaces) == "Cole")
    #expect(boldText(text).isEmpty)
    // PScript5's symbol-style codespace over the same one-byte entries (the Supreme Court's opinions).
    let pscript = fonts.map { WeightFont(baseFont: $0.baseFont, italicAngle: $0.italicAngle, flags: $0.flags,
                                         codespace: "2 begincodespacerange <00> <EF> <F000> <FFFF> endcodespacerange") }
    let opinion = try line(try styledLines(try weightDocument(pscript, shows: [(0, 72, 700, "the USS"), (1, 128, 700, "Cole"), (0, 162, 700, "bombing")])), "the USS")
    #expect(italicText(opinion).trimmingCharacters(in: .whitespaces) == "Cole")
    // Negative control: shows that cannot be decoded leave a mixed line upright.
    let undecoded = fonts.map { WeightFont(baseFont: $0.baseFont, toUnicode: false, encoding: false, italicAngle: $0.italicAngle, flags: $0.flags) }
    let plain = try line(try styledLines(try weightDocument(undecoded, shows: [(0, 72, 700, "the USS"), (1, 128, 700, "Cole"), (0, 162, 700, "bombing")])), "the USS")
    #expect(italicText(plain).isEmpty)
}

@Test func lineMatchingMarksBoldAndItalicIndependently() {
    let bounds = CGRect(x: 72, y: 698, width: 300, height: 14)
    var boldItalic = show(72, 700, "Demand Shocks", .bold, size: 10)
    boldItalic.italic = true
    var italic = show(150, 700, " in brief", .regular, size: 10)
    italic.italic = true
    let result = FontWeightReader.apply([boldItalic, italic], to: pdfkitRuns(["Demand Shocks in brief"]), bounds: bounds, allBounds: [bounds])
    #expect(marked(result) == "[Demand Shocks ]in brief")
    var slanted = ""
    result.enumerateAttribute(FontWeightReader.italicAttribute, in: NSRange(location: 0, length: result.length)) { value, range, _ in
        slanted += value == nil ? "" : (result.string as NSString).substring(with: range)
    }
    #expect(slanted == "Demand Shocks in brief")
    // Undecoded shows mark a style only where every show carries it.
    let undecoded = [boldItalic, italic].map { var copy = $0; copy.text = nil; return copy }
    let whole = FontWeightReader.apply(undecoded, to: pdfkitRuns(["Demand Shocks in brief"]), bounds: bounds, allBounds: [bounds])
    #expect(marked(whole) == "Demand Shocks in brief")
    #expect(whole.attribute(FontWeightReader.italicAttribute, at: 0, effectiveRange: nil) != nil)
}

@Test func compositeAndPScriptToUnicodeMapsDecode() throws {
    let wide = Data("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        1 begincodespacerange
        <0000> <FFFF>
        endcodespacerange
        2 beginbfchar
        <0005> <0020>
        <0502> <2154>
        endbfchar
        1 beginbfrange
        <0024> <003D> <0041>
        endbfrange
        endcmap CMapName currentdict /CMap defineresource pop end end
        """.utf8)
    let map = try #require(FontWeightReader.wideUnicodeMap(wide))
    #expect(map[0x0024] == "A" && map[0x003D] == "Z" && map[0x0005] == " " && map[0x0502] == "\u{2154}")
    // Controls: a one-byte codespace and an inherited map are not composite maps.
    #expect(FontWeightReader.wideUnicodeMap(Data(String(decoding: wide, as: UTF8.self)
        .replacingOccurrences(of: "<0000> <FFFF>", with: "<00> <FF>").utf8)) == nil)
    #expect(FontWeightReader.wideUnicodeMap(Data(String(decoding: wide, as: UTF8.self)
        .replacingOccurrences(of: "begincmap", with: "/Identity-H usecmap begincmap").utf8)) == nil)
    // PScript5's symbol-style codespace over one-byte entries (Supreme Court's Century Schoolbook).
    let pscript = Data("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        2 begincodespacerange
        <00> <EF>
        <F000> <FFFF>
        endcodespacerange
        3 beginbfchar
        <00> <FFFD>
        <43> <0043>
        <68> <0068>
        endbfchar
        endcmap CMapName currentdict /CMap defineresource pop end end
        """.utf8)
    #expect(NativeSpacingReader.simpleFontUnicodeMap(pscript) == nil)
    let simple = try #require(FontWeightReader.oneByteUnicodeMap(pscript))
    #expect(simple[0x43] == "C" && simple[0x68] == "h")
    // Control: a two-byte entry still fails the one-byte parse.
    #expect(FontWeightReader.oneByteUnicodeMap(Data(String(decoding: pscript, as: UTF8.self)
        .replacingOccurrences(of: "<68> <0068>", with: "<F068> <0068>").utf8)) == nil)
}

@Test func compositeIdentityHShowsDecodeTwoBytesPerCode() throws {
    let map = testPDFStream("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        1 begincodespacerange <0000> <FFFF> endcodespacerange
        1 beginbfrange <0024> <003D> <0041> endbfrange
        1 beginbfchar <0003> <0020> endbfchar
        endcmap CMapName currentdict /CMap defineresource pop end end
        """)
    func document(encoding: String) -> PDFDocument? {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F0 5 0 R >> >> /Contents 4 0 R >>",
            testPDFStream("BT /F0 12 Tf 72 700 Td <002B002C0003002B002C> Tj ET"),
            "<< /Type /Font /Subtype /Type0 /BaseFont /SyntheticSans-Bold /Encoding /\(encoding) /DescendantFonts [6 0 R] /ToUnicode 8 0 R >>",
            "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /SyntheticSans-Bold /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 7 0 R /DW 600 >>",
            "<< /Type /FontDescriptor /FontName /SyntheticSans-Bold /Flags 32 /FontBBox [0 -200 1000 900] /ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 140 /FontWeight 700 >>",
            map,
        ]
        return PDFDocument(data: testPDF(objects: objects))
    }
    let shows = FontWeightReader.read(try #require(document(encoding: "Identity-H")?.page(at: 0)?.pageRef))
    #expect(shows.count == 1 && shows.first?.text == "HI HI" && shows.first?.weight == .bold)
    // Control: a composite font under another CMap is not decoded.
    let other = FontWeightReader.read(try #require(document(encoding: "UniJIS-UCS2-H")?.page(at: 0)?.pageRef))
    #expect(other.count == 1 && other.first?.text == nil)
}

/// PDFKit-like runs with the reader's marks: `(text, bold, italic)`.
private func resourceRuns(_ pieces: [(String, Bool, Bool)]) -> NSAttributedString {
    let value = NSMutableAttributedString()
    for (index, piece) in pieces.enumerated() {
        var attributes: [NSAttributedString.Key: Any] = [.font: WeightTestFont(name: "Helvetica", size: 10)!, NSAttributedString.Key("run"): index]
        if piece.1 { attributes[FontWeightReader.boldAttribute] = true }
        if piece.2 { attributes[FontWeightReader.italicAttribute] = true }
        value.append(NSAttributedString(string: piece.0, attributes: attributes))
    }
    return value
}

private func styledRuns(_ text: InlineText) -> [String] {
    text.elements.compactMap {
        guard case let .text(value, style) = $0 else { return nil }
        return (style.contains(.bold) ? "B" : "") + (style.contains(.italic) ? "I" : "") + ":" + value
    }
}

@Test func listMarkerInAStyleItsItemDoesNotShareCarriesNoEmphasis() {
    // DGA's bullets: a bold `+` before a regular item.
    #expect(styledRuns(NativeTextReader.inlineText(from: resourceRuns([("+ ", true, false), ("Prioritize protein foods", false, false)])))
            == [":+ ", ":Prioritize protein foods"])
    #expect(styledRuns(NativeTextReader.inlineText(from: resourceRuns([("• ", false, true), ("Plain item", false, false)])))
            == [":• ", ":Plain item"])
    // Controls: a label with letters, a marker before an item in its own style, and punctuation inside a line.
    #expect(styledRuns(NativeTextReader.inlineText(from: resourceRuns([("NEADS: ", true, false), ("He is heading", false, false)])))
            == ["B:NEADS: ", ":He is heading"])
    #expect(styledRuns(NativeTextReader.inlineText(from: resourceRuns([("• ", true, false), ("Bold item", true, false)])))
            == ["B:• ", "B:Bold item"])
    #expect(styledRuns(NativeTextReader.inlineText(from: resourceRuns([("the USS ", false, false), ("; ", false, true), ("Cole", false, true)])))
            == [":the USS ", "I:; ", "I:Cole"])
}

@Test func adjacentRunsOfOneStyleAreOneElement() {
    // The FAA cover: PDFKit splits `FAA-H-8083-25C` into nine bold runs.
    let cover = InlineText(elements: ["F", "AA", "-", "H", "-", "8083", "-", "2", "5C"].map { .text($0, .bold) })
    #expect(EPUBTextEncoder.inline(cover) == "<strong>FAA-H-8083-25C</strong>")
    let caption = InlineText(elements: [.text("Figure 14-59. ", .bold), .text("EMAS information (formerly Airport/", .italic),
                                        .text("Facility Directory).", .italic)])
    #expect(EPUBTextEncoder.inline(caption)
            == "<strong>Figure 14-59. </strong><em>EMAS information (formerly Airport/Facility Directory).</em>")
    // Controls: different styles, a page boundary and a note reference stay apart.
    let mixed = InlineText(elements: [.text("Demand", [.bold, .italic]), .text(" Shocks", .bold), .sourcePage(31), .text("next", .bold),
                                      .noteReference("3", .superscript, NoteKey(number: 3, scope: .page(31))), .text("4", .superscript)])
    #expect(EPUBTextEncoder.inline(mixed).hasPrefix("<strong><em>Demand</em></strong><strong> Shocks</strong><span epub:type=\"pagebreak\""))
    #expect(EPUBTextEncoder.inline(mixed).contains("aria-label=\"31\"/><strong>next</strong><sup><a "))
    #expect(EPUBTextEncoder.inline(mixed).hasSuffix("</a></sup><sup>4</sup>"))
    // A note's opening number and its text are merged before the number is read.
    let note = InlineText(elements: [.text("1", .superscript), .text("2", .superscript), .text(" See the report.", [])])
    #expect(EPUBTextEncoder.note(note, number: 12, backlink: "noteref-p1-12").hasPrefix("<sup><a href=\"#noteref-p1-12\""))
}

// MARK: - Source fixtures (#133)

private func sourceItalic(_ name: String, fontWeights: Bool = true) throws -> [String: String] {
    let lines = try SourceLayoutFixture.load(name).styledContent(fontWeights: fontWeights).lines
    return Dictionary(lines.map { ($0.text, italicText($0)) }, uniquingKeysWith: { first, _ in first })
}

@Test func sourceSupremeCourtCaseNamesCarryItalicInsideProseLines() throws {
    // Century Schoolbook's ToUnicode maps declare PScript5's two-range codespace.
    let italic = try sourceItalic("scotus-9-styles")
    #expect(italic["Since our decision in Chevron U. S. A. Inc. v. Natural Re-"] == "Chevron U. S. A. Inc. Natural Re-")
    #expect(italic["Our Chevron doctrine requires courts to use a two-step"] == "Chevron ")
    #expect(italic.values.contains { !$0.isEmpty })
    #expect(try sourceItalic("scotus-9-styles", fontWeights: false).values.allSatisfy { $0.isEmpty })
}

@Test func sourceNineElevenShipNamesAndFedSummariesCarryItalic() throws {
    let report = try sourceItalic("911-171-styles")
    #expect(report["USS Cole."] == "Cole")
    #expect(report["October 6, 2002, bombing of the French tanker Limburg in the Gulf of Aden"] == "Limburg ")
    let fed = try sourceItalic("fed-8-styles")
    #expect(fed["The Federal Reserve performs five key functions"] == "The Federal Reserve performs five key functions")
    // Controls: the contents entries in the book weight stay upright.
    #expect(fed["The U.S. Approach to Central Banking ......................2"] == "")
    for name in ["911-171-styles", "fed-8-styles"] {
        #expect(try sourceItalic(name, fontWeights: false).values.allSatisfy { $0.isEmpty }, "\(name)")
    }
}

@Test func sourceReplayClocksLibertineTitlesBoldAndVenueItalicButNotMathItalic() throws {
    let fixture = try SourceLayoutFixture.load("arxiv-1-styles")
    let lines = fixture.styledContent().lines
    let bold = Dictionary(lines.map { ($0.text, boldText($0)) }, uniquingKeysWith: { first, _ in first })
    #expect(bold["Replay Clocks"] == "Replay Clocks")
    #expect(bold["1 INTRODUCTION"] == "1 INTRODUCTION")
    let italic = try sourceItalic("arxiv-1-styles")
    #expect(italic["ings of ACM Conference (Conference’17). ACM, New York, NY, USA, 12 pages."]?.hasPrefix("ings of ACM Conference") == true)
    // Libertine math italic is already slanted Unicode (`𝑅𝑒𝑝𝐶𝑙`) and gains no emphasis.
    let math = try #require(lines.first { $0.text.hasPrefix("In this work, we focus on the problem of replay clocks") })
    #expect(italicText(math).isEmpty && boldText(math).isEmpty)
    #expect(fixture.styledContent(fontWeights: false).lines.allSatisfy { boldText($0).isEmpty && italicText($0).isEmpty })
}

@Test func sourceAlgebraWorldViewNoteLabelOpensItsParagraphAndVariablesStayUpright() throws {
    // `World View Note:` is set in bold on a line of regular text; the Computer Modern fonts have no
    // ToUnicode map, only a WinAnsi encoding.
    let fixture = try SourceLayoutFixture.load("algebra-18-styles")
    let note = try #require(fixture.styledContent().lines.first { $0.text.hasPrefix("World View Note:") })
    #expect(boldText(note).trimmingCharacters(in: .whitespaces) == "World View Note:")
    let paragraphs = paragraphTexts(reflow(fixture.styledContent(), labelStyles: []))
    #expect(paragraphs.contains { $0.hasPrefix("World View Note: The first use of grouping symbols") })
    #expect(paragraphs.contains { $0.hasSuffix("start with.") })
    // Negative control: without resource styles the note runs on from the paragraph above.
    let fused = paragraphTexts(reflow(fixture.styledContent(fontWeights: false), labelStyles: []))
    #expect(fused.contains { $0.contains("start with. World View Note:") })
    // Math italic control: page 23's CMMI variables gain no italic, while its bold labels are marked.
    let algebra = try SourceLayoutFixture.load("algebra-23-styles").styledContent().lines
    #expect(algebra.contains { $0.text == "Example 32." && boldText($0) == "Example 32." })
    #expect(algebra.contains { $0.text.contains("5x") })
    #expect(algebra.allSatisfy { italicText($0).isEmpty })
}

@Test func sourceDGABulletsAndOurFlagScriptTitleGainNoEmphasis() throws {
    let dga = try SourceLayoutFixture.load("dga-3-styles")
    let bullet = try #require(dga.styledContent().lines.first { $0.text.hasPrefix("+ Prioritize high-quality") })
    #expect(boldText(bullet).isEmpty)
    #expect(dga.attributedLines.contains { $0.text.hasPrefix("+ Prioritize high-quality") && $0.runs.first?.bold == true })
    #expect(dga.styledContent().lines.contains { $0.text == "Prioritize Protein Foods at Every Meal" && boldText($0) == $0.text })
    let flag = try SourceLayoutFixture.load("flag-7-styles").styledContent().lines
    let title = try #require(flag.first { $0.text == "The History of the Stars and Stripes" })
    #expect(boldText(title) == title.text && italicText(title).isEmpty)
    let quote = try #require(flag.first { $0.text.hasPrefix("stripes, alternate red and white") })
    #expect(italicText(quote) == quote.text)
    #expect(try SourceLayoutFixture.load("flag-7-styles").styledContent(fontWeights: false).lines.allSatisfy { italicText($0).isEmpty })
}
