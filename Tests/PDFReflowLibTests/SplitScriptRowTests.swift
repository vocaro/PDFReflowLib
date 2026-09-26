import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// A printed row of stacked scripts that PDFKit returns as several lines is read back as one
// (#303), and so is a row PDFKit splits at a raised note number (#314), and nothing else is.
// Every fixture sets Helvetica on a 400 × 300 page; each run is
// placed where the one before it leaves off unless the stream moves it, and a subscript set
// under a superscript is moved back under it, as TeX does.

private func page(_ content: String) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])
}

/// The page's lines, read as a conversion reads them: with the page's painted marks.
private func lines(_ content: String) throws -> [TextLine] {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("source.pdf")
    try page(content).write(to: url)
    return try PageReader.read(pageIndex: 0, from: PDFPageSource(url: url), limit: 100_000,
                               options: ConversionOptions(), structure: nil).content.lines
}

private func converted(_ content: String) async throws -> (html: String, images: Int) {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try page(content).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    return (try Archive(url: epub, accessMode: .read).chapter(), report.imageCount)
}

/// Whether any one line reads both `a` and `b`: the lines they stand on were joined.
private func joins(_ lines: [TextLine], _ a: String, _ b: String) -> Bool {
    lines.contains { $0.text.contains(a) && $0.text.contains(b) }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func aRowOfStackedScriptsPDFKitSplitsReadsAsOneLine() async throws {
    // The issue's reproducer: `n` raised from STA, `i` raised from `n`, an inner `h` lowered from
    // `n` and the outer `h` under STA. PDFKit breaks the row where the 5-point glyphs step down
    // 5.1 points from `i` to `h`, into `For each STAni` and `hh in the schedule.`
    let content = """
    BT /F1 10 Tf 40 240 Td (For each STA) Tj /F1 7 Tf 3.6 Ts (n) Tj /F1 5 Tf 6.6 Ts (i) Tj 1.5 Ts (h) Tj \
    /F1 7 Tf -2 Ts (h) Tj /F1 10 Tf 0 Ts ( in the schedule.) Tj ET
    """
    let read = try lines(content)
    #expect(read.count == 1)
    #expect(read.map { EPUBTextEncoder.inline($0.content) }
            == ["For each STA<sup>n<sup>i</sup><sub>h</sub></sup><sub>h</sub> in the schedule."])
    let (html, images) = try await converted(content)
    #expect(images == 0)
    #expect(html.contains("<p>For each STA<sup>n<sup>i</sup><sub>h</sub></sup><sub>h</sub> in the schedule.</p>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func stackedScriptsMidLineReadWithTheirRow() throws {
    // DASC page 5's rows, placed glyph by glyph with no text rise: each subscript is moved back
    // under the superscript it stacks with, so PDFKit starts a new line there and carries the
    // rest of the row into it.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 240 Tm (Step 2. For each STA) Tj /F1 7 Tf 1 0 0 1 136.16 243.6 Tm (n) Tj \
    /F1 5 Tf 1 0 0 1 140.05 246.6 Tm (i) Tj 1 0 0 1 140.05 241.5 Tm (h) Tj /F1 7 Tf 1 0 0 1 136.16 238 Tm (h) Tj \
    /F1 10 Tf 1 0 0 1 145.61 240 Tm (occurring in the computed schedules) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 228 Tm (\\(6\\), i.e. for every flight h such that h < f and every) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 216 Tm (node n) Tj /F1 7 Tf 1 0 0 1 70.58 219.62 Tm (i) Tj 1 0 0 1 70.58 213.18 Tm (h) Tj \
    /F1 10 Tf 1 0 0 1 77.25 216 Tm (on the route of flight h, if this node also) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 204 Tm (occurs on the route of f.) Tj ET
    """)
    #expect(read.map { EPUBTextEncoder.inline($0.content) } == [
        "Step 2. For each STA<sup>n<sup>i</sup><sub>h</sub></sup><sub>h </sub>occurring in the computed schedules",
        "(6), i.e. for every flight h such that h &lt; f and every",
        "node n<sup>i</sup><sub>h </sub>on the route of flight h, if this node also",
        "occurs on the route of f.",
    ])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func aStackPDFKitReturnsAheadOfItsPlaceJoinsItsRow() throws {
    // DASC page 2's display (1), n¹_f, n²_f, …, n^{N_f}_f, at its own glyph positions. PDFKit
    // returns the row as five lines and hands `N f` back before the `, ..., n` it follows.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 240 Tm (with the terminology used in graph theory:) Tj ET
    BT /F1 10 Tf 1 0 0 1 98.9 222.03 Tm (n) Tj /F1 7 Tf 1 0 0 1 104.88 226.14 Tm (1) Tj \
    1 0 0 1 104.88 219.57 Tm (f) Tj /F1 10 Tf 1 0 0 1 110.05 222.03 Tm (, n) Tj \
    /F1 7 Tf 1 0 0 1 123.22 226.14 Tm (2) Tj 1 0 0 1 123.22 219.57 Tm (f) Tj \
    /F1 10 Tf 1 0 0 1 128.39 222.03 Tm (, ..., n) Tj /F1 7 Tf 1 0 0 1 153.41 227.49 Tm (N) Tj \
    /F1 5 Tf 1 0 0 1 158.46 226.43 Tm (f) Tj /F1 7 Tf 1 0 0 1 153.41 219.02 Tm (f) Tj \
    /F1 10 Tf 1 0 0 1 160.4 222.03 Tm (.) Tj 1 0 0 1 250 222.03 Tm (\\(1\\)) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 204 Tm (We now form the smallest possible graph.) Tj ET
    """)
    // One line, in the order the row is printed. The reading of `N` over its own subscript is the
    // first-level test's (#304), so only the stacks this reading already settles are pinned.
    #expect(read.map(\.text) == ["with the terminology used in graph theory:", "n1f , n 2f , ..., nNff. (1)",
                                 "We now form the smallest possible graph."])
    #expect(EPUBTextEncoder.inline(read[1].content).hasPrefix("n<sup>1</sup><sub>f </sub>, n <sup>2</sup><sub>f </sub>, ..., n"))
    #expect(EPUBTextEncoder.inline(read[1].content).hasSuffix("<sub>f</sub>. (1)"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func columnsWhoseRowsAlignAreNotJoined() throws {
    // Two columns set on one set of baselines, each left line closing with a script and each right
    // line opening with one. The gutter is not a script's width.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 260 Tm (Energy and mass are E = mc) Tj /F1 7 Tf 1 0 0 1 176.05 263.6 Tm (2) Tj ET
    BT /F1 7 Tf 1 0 0 1 194 263.6 Tm (3) Tj /F1 10 Tf 1 0 0 1 198 260 Tm (The right column starts here.) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 246 Tm (A second left line) Tj /F1 7 Tf 1 0 0 1 124.5 243 Tm (i) Tj ET
    BT /F1 7 Tf 1 0 0 1 194 243 Tm (j) Tj /F1 10 Tf 1 0 0 1 197 246 Tm (and a second right line.) Tj ET
    """)
    #expect(!joins(read, "E = mc", "right column"))
    #expect(!joins(read, "second left", "second right"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func tableCellsAcrossAColumnRuleAreNotJoined() throws {
    // A cell closing with a note mark and the next cell opening with a lowered mass number, two
    // points apart on one baseline: the rule painted between them makes them cells.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 260 Tm (Isotope) Tj 1 0 0 1 110 260 Tm (Mass) Tj 1 0 0 1 180 260 Tm (Share) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 244 Tm (Carbon) Tj /F1 7 Tf 1 0 0 1 72.79 247.6 Tm (a) Tj 1 0 0 1 78.8 241 Tm (12) Tj \
    /F1 10 Tf 1 0 0 1 86.6 244 Tm (C) Tj 1 0 0 1 110 244 Tm (12.000) Tj 1 0 0 1 180 244 Tm (98.9) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 228 Tm (Carbon) Tj /F1 7 Tf 1 0 0 1 72.79 231.6 Tm (b) Tj 1 0 0 1 78.8 225 Tm (13) Tj \
    /F1 10 Tf 1 0 0 1 86.6 228 Tm (C) Tj 1 0 0 1 110 228 Tm (13.003) Tj 1 0 0 1 180 228 Tm (1.1) Tj ET
    0.5 w 77.7 222 m 77.7 270 l S
    """)
    #expect(!joins(read, "Carbon", "12.000"))
    #expect(!joins(read, "Carbon", "13.003"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func aMarginalNoteBesideBodyTextIsNotJoined() throws {
    // Small type in the margin, raised off the body's baseline, beside a line that closes with a
    // superscript.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 260 Tm (The body text sets the square x) Tj /F1 7 Tf 1 0 0 1 186.2 263.6 Tm (2) Tj ET
    BT /F1 7 Tf 1 0 0 1 198 262 Tm (Margin: see 2.1) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 248 Tm (and the body carries on below it.) Tj ET
    BT /F1 7 Tf 1 0 0 1 198 250 Tm (and 2.4 too) Tj ET
    """)
    #expect(!joins(read, "square x", "Margin"))
    #expect(!joins(read, "carries on", "2.4 too"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func pageFootNotesAndTheirMarkersAreNotJoinedToTheBody() throws {
    // Body lines closing with raised note numbers, then the notes under a rule, each opened by its
    // own raised number: the notes stand a line below, and their numbers are not the body's.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 260 Tm (The court held that the rule applies to every vessel.) Tj \
    /F1 7 Tf 1 0 0 1 280.5 263.6 Tm (1) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 248 Tm (A second sentence closes the paragraph with x) Tj \
    /F1 7 Tf 1 0 0 1 255.2 251.6 Tm (2) Tj ET
    0.5 w 40 238 m 120 238 l S
    BT /F1 6 Tf 1 0 0 1 40 231 Tm (1) Tj /F1 8 Tf 1 0 0 1 44 228 Tm (The first note explains the vessel rule.) Tj ET
    BT /F1 6 Tf 1 0 0 1 40 222 Tm (2) Tj /F1 8 Tf 1 0 0 1 44 219 Tm (The second note gives the square.) Tj ET
    """)
    #expect(!joins(read, "every vessel", "first note"))
    #expect(!joins(read, "closes the paragraph", "first note"))
    #expect(!joins(read, "first note", "second note"))
    #expect(read.contains { EPUBTextEncoder.inline($0.content) == "<sup>1</sup>The first note explains the vessel rule." })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func aNextLineOfSmallTypeIsNotJoinedToTheScriptsAboveIt() throws {
    // A caption and a 7-point note directly under body lines that close with scripts, one of them
    // starting right under the script: they are a line below, beyond any script's reach.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 260 Tm (Figure 1 plots the area of the square side x) Tj /F1 7 Tf 1 0 0 1 247.3 263.6 Tm (2) Tj ET
    BT /F1 7 Tf 1 0 0 1 247.3 252 Tm (below) Tj ET
    BT /F1 7 Tf 1 0 0 1 40 252 Tm (Caption: the area grows as the square of the side, shown) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 238 Tm (The text goes on under the caption with y) Tj /F1 7 Tf 1 0 0 1 225.5 235 Tm (k) Tj ET
    BT /F1 7 Tf 1 0 0 1 225.5 229.5 Tm (7 pt note text directly under it.) Tj ET
    """)
    #expect(!joins(read, "square side", "below"))
    #expect(!joins(read, "square side", "Caption"))
    #expect(!joins(read, "caption with y", "7 pt note"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/303"))
func aFractionPreservedAsAnImageIsNotReadAsScripts() async throws {
    // A numerator raised and a denominator lowered and set back under it, with the bar painted
    // between: the shape of a stacked superscript and subscript, but a fraction. PDFKit keeps the
    // numerator in the prose line and returns the denominator with the words after it, as it
    // does for Wallace's inline fractions; the bar keeps them apart, and the row is preserved.
    let content = """
    BT /F1 10 Tf 1 0 0 1 40 260 Tm (The ratio is written so that y =) Tj /F1 7 Tf 1 0 0 1 173 265 Tm (a + 1) Tj \
    1 0 0 1 177.8 255.2 Tm (b) Tj /F1 10 Tf 1 0 0 1 193 260 Tm (for every a.) Tj ET
    0.5 w 172.5 262.5 m 190.5 262.5 l S
    BT /F1 10 Tf 1 0 0 1 40 240 Tm (The next paragraph is plain prose again.) Tj ET
    """
    let read = try lines(content)
    #expect(!joins(read, "a + 1", "for every"))
    let (html, images) = try await converted(content)
    #expect(images == 1)
    #expect(!html.contains("<sub>b"))
    #expect(html.contains("<p>The next paragraph is plain prose again.</p>"))
}

// A raised note number PDFKit returns as a line of its own is read with its row (#314). PDFKit
// splits a printed row at a full stop, and the 9/11 report, NOAA's assessment and Loper Bright
// set a note number by a text matrix of its own straight after the stop: `selectionsByLine` ends
// the line there and returns the number, alone or with the words after it on the row, as a line
// that starts where the first one ends. These rows are set with the 9/11 report's own operators:
// a unit font scaled by `Tm`, the stop shown on its own after a `TD`, and the number placed by
// `Tm` a hundredth of a point inside the stop's end.

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func aNoteNumberPDFKitSplitsOffMidRowIsReadWithItsRow() async throws {
    // The 9/11 report's page 145: PDFKit returns `…to the Washington Times.` and
    // `105 This made it`, and the paragraph broke in two at the note.
    let content = """
    BT /F1 10 Tf 1 0 0 1 40 272 Tm (The officials recalled that the source went quiet soon) Tj ET
    BT /F1 1 Tf 10 0 0 10 40 260 Tm (after a leak to the Washington Times) Tj 16.285 0 TD 0 Tc 0 Tw (.) Tj \
    7 0 0 7 205.62 263 Tm -0.0002 Tc (105) Tj 10 0 0 10 220.1 260 Tm 0.0002 Tc (This made it ) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 248 Tm (much more difficult to intercept the calls.) Tj ET
    """
    let read = try lines(content)
    #expect(read.count == 3)
    #expect(read.contains {
        EPUBTextEncoder.inline($0.content).hasPrefix("after a leak to the Washington Times.<sup>105 </sup>This made it")
    })
    let (html, _) = try await converted(content)
    #expect(html.contains("<p>The officials recalled that the source went quiet soon after a leak to the "
        + "Washington Times.<sup>105 </sup>This made it much more difficult to intercept the calls.</p>"))
}

/// Loper Bright's page 13 in miniature: the number closes its row alone, a page-foot note carries
/// it, and an ordinal in the next sentence is raised inline.
private let aNoteNumberAloneOnItsPiece = """
BT /F1 10 Tf 1 0 0 1 40 272 Tm (Petitioners own two vessels that operate in the herring) Tj ET
BT /F1 1 Tf 10 0 0 10 40 260 Tm (fishery: the F/V Relentless and the F/V Persistence) Tj 22.621 0 TD 0 Tc 0 Tw (.) Tj \
7 0 0 7 268.98 264 Tm -0.0002 Tc (1) Tj ET
BT /F1 10 Tf 1 0 0 1 40 248 Tm (These vessels have fished these waters since the 19) Tj /F1 7 Tf 3.6 Ts (th) Tj \
/F1 10 Tf 0 Ts ( century.) Tj ET
BT /F1 5 Tf 1 0 0 1 40 53 Tm (1) Tj /F1 8 Tf 1 0 0 1 44 50 Tm (For any landlubbers, F/V is simply the designation for a fishing vessel.) Tj ET
"""

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func aNoteNumberAloneOnItsPieceIsReadWithItsRowAndLinkedToItsNote() async throws {
    // PDFKit returns the `1` as a line of its own after `…the F/V Persistence.`; it was written
    // as a plain `1` in a paragraph of its own, and the page-foot note it refers to was not linked.
    let read = try lines(aNoteNumberAloneOnItsPiece)
    #expect(read.contains { EPUBTextEncoder.inline($0.content) == "fishery: the F/V Relentless and the F/V Persistence.<sup>1</sup>" })
    #expect(!read.contains { $0.text == "1" })
    let (html, _) = try await converted(aNoteNumberAloneOnItsPiece)
    #expect(html.contains("the F/V Persistence.<a epub:type=\"noteref\" role=\"doc-noteref\" "
        + "href=\"chapter-1.xhtml#note-fn-1-1\"><sup>1</sup></a> These vessels have fished these waters"))
    #expect(html.contains("<aside epub:type=\"footnote\" role=\"doc-footnote\" id=\"note-fn-1-1\">"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func aRaisedOrdinalIsNotTakenForANoteNumber() async throws {
    // Control: the ordinal raised inline on the same page stays a superscript of its word, and the
    // page's one note is linked from its number alone.
    let (html, _) = try await converted(aNoteNumberAloneOnItsPiece)
    #expect(html.contains("since the 19<sup>th</sup> century."))
    #expect(html.components(separatedBy: "epub:type=\"noteref\"").count == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func aStopPDFKitReturnsOnItsOwnIsReadBeforeTheNoteNumberAfterIt() async throws {
    // NOAA's page 145: PDFKit returns `…W/m²`, the stop and `² Since NCA4, the` as three lines. The
    // stop is the row's next character, so it is taken with the piece after it, and read before it.
    let content = """
    BT /F1 10 Tf 1 0 0 1 40 272 Tm (Changes in aerosols over the period have had) Tj ET
    BT /F1 1 Tf 10 0 0 10 40 260 Tm (an overall cooling effect of 1.3 W/m) Tj 7 0 0 7 196.18 263.6 Tm (2) Tj \
    10 0 0 10 200.07 260 Tm 0 Tc 0 Tw (.) Tj 7 0 0 7 202.85 263.6 Tm -0.0002 Tc (2) Tj \
    10 0 0 10 206.74 260 Tm 0.0002 Tc ( Since NCA4, the) Tj ET
    BT /F1 10 Tf 1 0 0 1 40 248 Tm (uncertainty in the total has been reduced.) Tj ET
    """
    let read = try lines(content)
    #expect(read.map { EPUBTextEncoder.inline($0.content) }.contains(
        "an overall cooling effect of 1.3 W/m<sup>2</sup>.<sup>2</sup> Since NCA4, the"))
    let (html, _) = try await converted(content)
    #expect(html.contains("<p>Changes in aerosols over the period have had an overall cooling effect of "
        + "1.3 W/m<sup>2</sup>.<sup>2</sup> Since NCA4, the uncertainty in the total has been reduced.</p>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func aNoteNumberAfterAnUnderlinedRowIsReadWithIt() throws {
    // NOAA underlines its links up to the stop a note number follows (page 26's `Table 1.1.9.` and
    // its note 12). A rule under the baseline is the row's own; one standing above it, where a
    // fraction's bar would, still keeps the pieces apart.
    func content(_ rule: String) -> String {
        """
        BT /F1 10 Tf 1 0 0 1 40 272 Tm (Unless noted, the estimates in this report have been) Tj ET
        BT /F1 1 Tf 10 0 0 10 40 260 Tm (converted with the Price Deflators, Table 1.1.9) Tj 20.509 0 TD 0 Tc 0 Tw (.) Tj \
        7 0 0 7 247.86 264 Tm -0.0002 Tc (12) Tj 10 0 0 10 255.65 260 Tm 0.0002 Tc ( Where documented,) Tj ET
        BT /F1 10 Tf 1 0 0 1 40 248 Tm (discount rates are noted next to the projections.) Tj ET
        \(rule)
        """
    }
    let underlined = try lines(content("0.75 w 170 258 m 245.09 258 l S"))
    #expect(underlined.contains { $0.text.hasSuffix("Table 1.1.9.12 Where documented,") })
    let barred = try lines(content("0.5 w 170 262.5 m 247.5 262.5 l S"))
    #expect(!joins(barred, "Table 1.1.9", "Where documented"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func noteNumbersThatOpenTheirLinesAreNotJoinedToTheLineAbove() throws {
    // Control: a list of notes, each number raised at the head of its note and drawn after the
    // notes' text, so PDFKit returns every number as a line of its own. A number that opens a
    // line starts no row's end: none is joined to the note above it.
    let read = try lines("""
    BT /F1 10 Tf 1 0 0 1 40 272 Tm (The body of the page closes with its last full sentence here.) Tj ET
    BT /F1 8 Tf 1 0 0 1 45 80 Tm (The first note explains the rule and ends at the margin here.) Tj ET
    BT /F1 8 Tf 1 0 0 1 45 70 Tm (The second note opens at its own number.) Tj ET
    BT /F1 8 Tf 1 0 0 1 45 60 Tm (The third note opens at its number too.) Tj ET
    BT /F1 5 Tf 1 0 0 1 40 83 Tm (1) Tj 1 0 0 1 40 73 Tm (2) Tj 1 0 0 1 40 63 Tm (3) Tj ET
    """)
    #expect(read.filter { ["1", "2", "3"].contains($0.text) }.count == 3)
    #expect(!read.contains { $0.text.hasSuffix("here.2") || $0.text.hasSuffix("number.3") })
}
