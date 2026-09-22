import CoreText
import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// PDFKit text extraction: union slicing of attributed text (#4), word boundaries from baseline
// offsets, inline superscripts and subscripts, and endnote markers.

/// #4: PDFKit leaks every attributed string it returns (FB24783799), so a page's styled lines are
/// read with one request for their union and sliced, instead of one request per line. Each slice
/// must carry exactly what the line's own request returns; a page whose union does not align
/// with its lines falls back to requests per line.
private let page = testPDF(objects: [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> >> /Contents 4 0 R >>",
    testPDFStream("""
    BT /F2 18 Tf 1 0 0 1 72 720 Tm (A Heading Set in Bold) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 690 Tm (The body opens with an ordinary line of prose,) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 674 Tm (and it continues with ) Tj /F3 12 Tf (an italic phrase) Tj /F1 12 Tf ( inside.) Tj ET
    BT /F1 10 Tf 1 0 0 1 72 640 Tm (Associate Editor:) Tj ET
    BT /F1 10 Tf 1 0 0 1 400 640 Tm (\\(301\\) 504-1623) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 610 Tm (A last line closes the page.) Tj ET
    """),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>",
])

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/4")) func unionSlicesCarryEachLinesOwnAttributedText() throws {
    let document = try #require(PDFDocument(data: page))
    let pdfPage = try #require(document.page(at: 0))
    // `attributedTexts` (private, gated only via its caller `extractLines`) is not reachable from
    // a test in another file; this fetches the union the same way and hands it to `sliceUnion`,
    // the pure alignment-and-slice step it delegates to, which makes no PDFKit call and needs
    // no gate of its own.
    let selections = try #require(pdfKitGated { pdfPage.selection(for: pdfPage.bounds(for: .cropBox))?.selectionsByLine() })
    let texts = selections.map(\.string)
    let ownAttributed = pdfKitGated { selections.map(\.attributedString) }
    let pdfDocument = try #require(pdfPage.document)
    let union = PDFSelection(document: pdfDocument)
    union.add(selections)
    let plainUnion = try #require(pdfKitGated { union.string })
    let attributedUnion = try #require(pdfKitGated { union.attributedString })

    let indices = selections.indices.filter { !(texts[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // PDFKit reads the two pieces of the `Associate Editor:` row as one line.
    #expect(indices.count == 5)
    let sliced = NativeTextReader.sliceUnion(of: indices, texts: texts, plainUnion: plainUnion, attributedUnion: attributedUnion)
    // Every styled line comes from the one request: none is left to a request of its own.
    #expect(Set(sliced.keys) == Set(indices))
    for index in indices {
        let own = try #require(ownAttributed[index])
        let slice = try #require(sliced[index])
        #expect(slice.isEqual(to: own), "line \(index): \(own.string)")
    }
    let fonts = indices.compactMap { (sliced[$0]?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName }
    #expect(fonts.contains { $0.contains("Bold") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/4")) func unionTextAlignsOnlyWithLinesInOrder() {
    // PDFKit separates rows with a newline and runs the pieces of one row together.
    #expect(NativeTextReader.lineRanges(of: ["One", "Two", "Three"], in: "One\nTwoThree")
        == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 7, length: 5)])
    #expect(NativeTextReader.lineRanges(of: ["a\u{FFFC}b", "c"], in: "a\u{FFFC}b\nc")
        == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 1)])
    // A line the union repeats (a row piece equal to the next line's start) still lies at the cursor.
    #expect(NativeTextReader.lineRanges(of: ["ab", "abc"], in: "ababc")
        == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 3)])
    // Anything else falls back to requests per line: lines out of order, text left over,
    // a separator other than one newline, an empty line, or characters that differ only by
    // canonical equivalence.
    #expect(NativeTextReader.lineRanges(of: ["Two", "One"], in: "One\nTwo") == nil)
    #expect(NativeTextReader.lineRanges(of: ["One"], in: "One\nTwo") == nil)
    #expect(NativeTextReader.lineRanges(of: ["One", "Two"], in: "One\n\nTwo") == nil)
    #expect(NativeTextReader.lineRanges(of: ["One", "Two"], in: "One Two") == nil)
    #expect(NativeTextReader.lineRanges(of: ["", "One"], in: "One") == nil)
    #expect(NativeTextReader.lineRanges(of: ["caf\u{E9}"], in: "cafe\u{301}") == nil)
}

private func boundaryText(_ values: [(String, Double, Double)], foundationKey: Bool = false) -> InlineText {
    let input = NSMutableAttributedString(string: "")
    for (text, offset, size) in values {
        input.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { PlatformFont(name: "Helvetica", size: size) }!,
            (foundationKey ? .baselineOffset : NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)): offset,
        ]))
    }
    return NativeTextReader.inlineText(from: input)
}

@Test func dgaSourceBaselineRestoresTitleWordBoundary() throws {
    let source = try SourceLayoutFixture.load("dga-1")
    let title = try #require(source.attributedLines.first { $0.text == "GuidelinesFor Americans" })
    let model = NativeTextReader.inlineText(from: title.attributedString())
    #expect(model.text == "Guidelines For Americans")
    #expect(!EPUBTextEncoder.inline(model).contains("<sup>"))
    #expect(!EPUBTextEncoder.inline(model).contains("<sub>"))
}

@Test(arguments: [false, true])

func nativeCombinedLinesGetBoundariesWithEitherBaselineKey(foundationKey: Bool) {
    let model = boundaryText([("First", 24, 12), ("second", 12, 12), ("third", 0, 12)], foundationKey: foundationKey)
    #expect(model.text == "First second third")
    #expect(EPUBTextEncoder.inline(model) == "First second third")
}

@Test func existingWhitespaceAndLineEndHyphensDoNotGainExtraSpaces() {
    for (left, right, expected) in [("First ", "second", "First second"),
                                    ("First", "\nsecond", "First\nsecond"),
                                    ("well-", "known", "well-known"),
                                    ("soft\u{00ad}", "ware", "soft\u{00ad}ware")] {
        #expect(boundaryText([(left, 12, 12), (right, 0, 12)]).text == expected)
    }
}

@Test func oppositeInlineScriptsDoNotBecomeWordBoundaries() {
    let model = boundaryText([("x", 0, 12), ("upper", 8, 12), ("lower", -8, 12), ("base", 0, 12)])
    #expect(model.text == "xupperlowerbase")
    #expect(EPUBTextEncoder.inline(model).contains("<sup>upper</sup><sub>lower</sub>"))
}

@Test func dropCapsAndOrdinaryStyleRunsDoNotSplitWords() {
    #expect(boundaryText([("I", 24, 36), ("nitial", 0, 12)]).text == "Initial")
    #expect(boundaryText([("con", 0, 12), ("tinu", 0.1, 12), ("ation", 0, 12)]).text == "continuation")
    #expect(boundaryText([("single", 24, 12)]).text == "single")
}

@Test func uncertainSpacingWithinOneSourceRunStaysUnchanged() throws {
    let source = try SourceLayoutFixture.load("dga-1")
    for phrase in ["Protein, Dair y", "Ve getables"] {
        let line = try #require(source.attributedLines.first { $0.text == phrase })
        #expect(NativeTextReader.inlineText(from: line.attributedString()).text == phrase)
    }
}

@Test func flagSourceNegativeBaselineRestoresHeadingWordBoundary() throws {
    let source = try SourceLayoutFixture.load("flag-31")
    let title = try #require(source.attributedLines.first { $0.text == "How to Obtain a Burial Flagfor a Veteran" })
    let model = NativeTextReader.inlineText(from: title.attributedString())
    #expect(model.text == "How to Obtain a Burial Flag for a Veteran")
    #expect(!EPUBTextEncoder.inline(model).contains("<sub>"))
}

@Test func sourceEndnoteMarkerRetainsNativeSuperscriptEvidence() throws {
    let fixture = try SourceLayoutFixture.load("911-20")
    let source = try #require(fixture.attributedLines.first { $0.text.contains("7:45.") })
    #expect(EPUBTextEncoder.inline(NativeTextReader.inlineText(from: source.attributedString()))
        .contains("7:45.<sup>4</sup>"))
}

@Test(arguments: [false, true])

func explicitBaselineOffsetsPreserveScriptWithoutGuessingFromSmallFonts(useFoundationKey: Bool) {
    let value = NSMutableAttributedString(string: "")
    for (text, offset, size) in [("base", 0.0, 12.0), ("small", 0, 8), ("raised", 4, 12),
                                ("lowered", -3, 8), ("noise", 0.1, 12)] {
        value.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { PlatformFont(name: "Helvetica-BoldOblique", size: size) }!,
            (useFoundationKey ? .baselineOffset : NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)): offset,
        ]))
    }
    let model = NativeTextReader.inlineText(from: value)
    #expect(model.text == "basesmallraisedlowerednoise")
    let html = EPUBTextEncoder.inline(model)
    #expect(html.contains("<sup><strong><em>raised</em></strong></sup>"))
    #expect(html.contains("<sub><strong><em>lowered</em></strong></sub>"))
    #expect(!html.contains("<sup><strong><em>small"))
    #expect(!html.contains("<sup><strong><em>noise"))
}

@Test func nativeRaisedAndLoweredGlyphsReachTheEPUBAsSelectableText() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("BT /F1 12 Tf 40 240 Td (Read ax) Tj /F1 8 Tf 4 Ts (2) Tj /F1 12 Tf 0 Ts ( and H) Tj /F1 8 Tf -3 Ts (2) Tj /F1 12 Tf 0 Ts (O carefully.) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.imageCount == 0 && report.reflowedPageCount == 1)
    let html = try Archive(url: epub, accessMode: .read).chapter()
    #expect(html.contains("ax<sup>2</sup>"))
    #expect(html.contains("H<sub>2</sub>O"))
    #expect(html.contains("carefully."))
}

// A run of whitespace alone is not an inline script (#273). The shapes below are the four books
// that carried `<sup> </sup>` or `<sub> </sub>` at library defaults with `--no-ocr`, measured run
// by run; see measurements/whitespace-only-inline-scripts/record.md.
/// Each tuple is one run as PDFKit hands it over. A marker no style reads keeps neighboring runs
/// of identical font and offset apart, which is what the source strings do: the CDC page's raised
/// caption and the space after it carry the same font and the same 4.9-point offset and are still
/// two runs, and `enumerateAttributes` splits at every attribute change, including ones no style
/// reads.
private func scriptRuns(_ values: [(String, Double, Double)], font: String = "Helvetica") -> String {
    let input = NSMutableAttributedString(string: "")
    for (index, value) in values.enumerated() {
        let (text, offset, size) = value
        input.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { PlatformFont(name: font, size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
            NSAttributedString.Key("test.run"): index,
        ]))
    }
    return EPUBTextEncoder.inline(NativeTextReader.inlineText(from: input))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/273"))
func aRunHoldingOnlyWhitespaceIsNeverAnInlineScript() {
    // The FAA handbook's glossary, physical pages 509 and 510: each V-speed entry is a row whose
    // word space between the term and its definition is reported on its own, lowered 2 points on
    // a 7-point body, with both neighbors on the baseline.
    #expect(scriptRuns([("VLO.", 0, 7), (" ", -2, 7), ("Landing gear operating speed.", 0, 7)])
            == "VLO. Landing gear operating speed.")
    // The CDC graphic novel, page 12: a raised caption and a lowered one meet at a space that
    // takes the raised one's offset. Both captions keep their own script; the space keeps none.
    #expect(scriptRuns([("Are sHow/ng up", 4.9, 11.5), (" ", 4.9, 11.5), ("THrougHour thb", -4.9, 11.5)])
            == "<sup>Are sHow/ng up</sup> <sub>THrougHour thb</sub>")
    // The USCIS Arabic guide, page 103: Arabic shaping raises a word space by 1.98 on a 12-point
    // body — the same evidence #41 holds for a letter, over a character that draws nothing.
    #expect(scriptRuns([("التفكير في", 0, 12), (" ", 1.98, 12), ("أن تصبح مواطنًا أمريكيًا", 0, 12)])
            == "التفكير في أن تصبح مواطنًا أمريكيًا")
    // The census report, page 4: PDFKit reports `ij ` as one lowered run on a 7.08-point body
    // inside a 10.08-point line, and the glyph redraw (#217) rebuilds the line character by
    // character, leaving that trailing space standing as a run of its own, still lowered.
    #expect(scriptRuns([("in", -1.55928, 7.0781), (" ", -1.55928, 7.0781)]) == "<sub>in</sub>")
    #expect(scriptRuns([("represented by U", 0, 10.08), (" ", -1.55928, 7.0781), (", 1 i n,", 0.00072, 10.08)])
            == "represented by U , 1 i n,")
    // Every kind of whitespace a page can set between two words, raised or lowered: a tab, a
    // non-breaking space, a figure space and the placeholder an image attachment leaves behind
    // draw no more than a space does.
    for blank in [" ", "\t", "\u{00a0}", "\u{2007}", "\u{FFFC}"] {
        #expect(!scriptRuns([("before", 0, 12), (blank, 4, 12), ("after", 0, 12)]).contains("<sup>"))
        #expect(!scriptRuns([("before", 0, 12), (blank, -4, 12), ("after", 0, 12)]).contains("<sub>"))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/273"))
func aRaisedRunWithAGlyphInItStillReadsAsAnInlineScript() {
    // Positive controls. One raised character is the exponent and the endnote marker this library
    // exists to keep, and the guard must not reach either.
    #expect(scriptRuns([("ax", 0, 12), ("2", 4, 8), (" + bx + c", 0, 12)]) == "ax<sup>2</sup> + bx + c")
    #expect(scriptRuns([("H", 0, 12), ("2", -3, 8), ("O", 0, 12)]) == "H<sub>2</sub>O")
    #expect(scriptRuns([("at 7:45.", 0, 12), ("4", 4, 8)]) == "at 7:45.<sup>4</sup>")
    // A script the page sets over several glyphs keeps the spaces inside it: whitespace beside a
    // glyph in the same run is that script's own, and only a run with no glyph at all is barred.
    #expect(scriptRuns([("note", 0, 12), ("1 2", 4, 8), (".", 0, 12)]) == "note<sup>1 2</sup>.")
    #expect(scriptRuns([("x", 0, 12), (" a ", 4, 8), ("y", 0, 12)]) == "x<sup> a </sup>y")
    // And one raised character is still one raised character where a space stands beside it in a
    // run of its own: the character keeps the script and the space is written as the page set it.
    #expect(scriptRuns([("x", 0, 12), (" ", 4, 8), ("2", 4, 8), ("y", 0, 12)]) == "x <sup>2</sup>y")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/273"))
func aPageThatRaisesOnlyASpaceReachesTheEPUBWithThatSpaceAndNoScript() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("BT /F1 12 Tf 40 240 Td (Read ax) Tj /F1 8 Tf 4 Ts (2) Tj"
                      + " /F1 12 Tf 0 Ts ( names a square) Tj 4 Ts ( ) Tj"
                      + " 0 Ts (and this clause follows a raised space.) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.imageCount == 0 && report.reflowedPageCount == 1)
    let html = try Archive(url: epub, accessMode: .read).chapter()
    #expect(!html.contains("<sup> </sup>"))
    #expect(!html.contains("<sub> </sub>"))
    // The page's own space between the two clauses is kept, and the exponent beside it survives.
    #expect(html.contains("ax<sup>2</sup> names a square and this clause follows a raised space."))
}

@Test func comicOCRLineSpacingIsNotAnInlineScript() throws {
    let source = try SourceLayoutFixture.load("cdc-5")
    let line = try #require(source.attributedLines.first)
    let model = NativeTextReader.inlineText(from: line.attributedString())
    #expect(model.text == line.text)
    let html = EPUBTextEncoder.inline(model)
    #expect(!html.contains("<sup>"))
    #expect(!html.contains("<sub>"))
}

// A run of whitespace alone takes no emphasis from its font (#278). Weaker than #273 and
// deliberately separate from it: a bold space renders as a space, so the case here is markup that
// does not claim what the page never set. See measurements/whitespace-only-emphasis/record.md.
/// Each tuple is one run as PDFKit hands it over: its text, the font it names, and whether
/// `markUnderlines` painted a rule under it. A whitespace run only ever reaches the writer as an
/// element of its own where its neighbours read differently, which is the shape the books produce
/// — the space between two links, or between a bold term and the prose after it.
private func emphasisRuns(_ values: [(String, String, Bool)]) -> String {
    let input = NSMutableAttributedString(string: "")
    for (index, value) in values.enumerated() {
        let (text, font, underlined) = value
        var attributes: [NSAttributedString.Key: Any] = [
            .font: pdfKitGated { PlatformFont(name: font, size: 12) }!,
            NSAttributedString.Key("test.run"): index,
        ]
        if underlined { attributes[.underlineStyle] = 1 }
        input.append(NSAttributedString(string: text, attributes: attributes))
    }
    return EPUBTextEncoder.inline(NativeTextReader.inlineText(from: input))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/278"))
func aRunHoldingOnlyWhitespaceTakesNoEmphasisFromItsFont() {
    // The USCIS Arabic guide's page 1, between two links: the word space between them is reported
    // in the bold font the linked terms are set in, and no neighbour can absorb it.
    #expect(emphasisRuns([("أو", "Helvetica", false), (" ", "Helvetica-Bold", false),
                          ("www.socialsecurity.gov", "Helvetica", false)])
            == "أو www.socialsecurity.gov")
    // The FAA handbook and *Agricultural Research*: an italic space between two upright runs.
    #expect(emphasisRuns([("see", "Helvetica", false), (" ", "Helvetica-Oblique", false),
                          ("the table", "Helvetica", false)])
            == "see the table")
    // Every kind of whitespace a page can set between two words draws no more than a space does,
    // including the placeholder an image attachment leaves behind.
    for blank in [" ", "\t", "\u{00a0}", "\u{2007}", "\u{FFFC}"] {
        let html = emphasisRuns([("before", "Helvetica", false), (blank, "Helvetica-Bold", false),
                                 ("after", "Helvetica", false)])
        #expect(!html.contains("<strong>"), "blank U+\(String(format: "%04X", blank.unicodeScalars.first!.value))")
        #expect(!html.contains("<em>"))
    }
    // Dropping the inner run's style collapses the shape whole: the FAA handbook's nine
    // `<sub><strong> </strong></sub>` elements are a space and nothing else once it is gone.
    #expect(!emphasisRuns([("VLO.", "Helvetica", false), (" ", "Helvetica-BoldOblique", false),
                           ("Landing gear operating speed.", "Helvetica", false)]).contains("<"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/278"))
func emphasisOverAGlyphAndARulePaintedUnderASpaceBothSurvive() {
    // Positive controls. Whitespace beside a glyph in the same run is that run's own, and a run
    // of glyphs keeps every style its font names.
    #expect(emphasisRuns([("x", "Helvetica", false), (" bold phrase ", "Helvetica-Bold", false),
                          ("y", "Helvetica", false)])
            == "x<strong> bold phrase </strong>y")
    #expect(emphasisRuns([("Read ", "Helvetica", false), ("Moby-Dick", "Helvetica-Oblique", false),
                          (" today.", "Helvetica", false)])
            == "Read <em>Moby-Dick</em> today.")
    // A rule the page painted under a space is ink the page really put there (#235), and is not
    // the font's claim this guard drops. No corpus case produces one, so this is the whole record
    // of what the library does with it.
    #expect(emphasisRuns([("signed", "Helvetica", false), (" ", "Helvetica", true),
                          ("here", "Helvetica", false)])
            == "signed<u> </u>here")
    // The rule survives with the font's emphasis dropped from underneath it.
    #expect(emphasisRuns([("signed", "Helvetica", false), (" ", "Helvetica-Bold", true),
                          ("here", "Helvetica", false)])
            == "signed<u> </u>here")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/278"))
func aPageThatSetsOnlyASpaceInBoldReachesTheEPUBWithThatSpaceAndNoEmphasis() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("BT /F1 12 Tf 40 240 Td (One clause closes) Tj /F2 12 Tf ( ) Tj"
                      + " /F1 12 Tf (and the next one opens after a bold space.) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    ]).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.imageCount == 0 && report.reflowedPageCount == 1)
    let html = try Archive(url: epub, accessMode: .read).chapter()
    #expect(!html.contains("<strong> </strong>"))
    #expect(!html.contains("<em> </em>"))
    // The page's own space between the two clauses is kept.
    #expect(html.contains("One clause closes and the next one opens after a bold space."))
}
