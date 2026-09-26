import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import PDFReflowLib

// MARK: - A space glyph whose advance the page takes back (#316)

/// A page drawing `stream` in one simple font whose `Widths` give the space 250 units, the hyphen
/// 333, the en dash (code 150, through `Differences`) 500 and every other code 500, which is how
/// *The First Hebrew Shakespeare Translations* draws its allowed breaks: a space glyph, and a
/// `TJ` adjustment of the space's own width that takes it back before the next glyph.
private func takenBackData(_ stream: String) -> Data {
    let widths = (32...150).map { $0 == 32 ? "250" : $0 == 45 ? "333" : "500" }.joined(separator: " ")
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 32 /LastChar 150 /Widths [\(widths)]"
            + " /Encoding << /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [150 /endash] >> >>",
        testPDFStream(stream),
    ])
}

/// The spacing reader's shows for `stream`, each with the text it decodes and the offsets in it
/// of the space glyphs the page takes back.
private func takenBack(_ stream: String) throws -> [(text: String, spaces: [Int])] {
    let provider = try #require(CGDataProvider(data: takenBackData(stream) as CFData))
    let document = try #require(CGPDFDocument(provider))
    let page = try #require(document.page(at: 1))
    return NativeSpacingReader.read(page).map { ($0.unicode ?? "", $0.takenBackSpaces.sorted()) }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func aSpaceGlyphWhoseAdvanceATJKernTakesBackIsNoWordSpace() throws {
    // Page 14's `117–18` and page 35's `back-translation`: the space after the dash or the
    // hyphen, taken back by an adjustment of its own width.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(pages 117\\226 )250(18 in all)] TJ ET")
        .map(\.spaces) == [[10]])
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(the back- )250(translation)] TJ ET")
        .map(\.spaces) == [[9]])
    // Word and character spacing the show adds to the space are taken back with it (page 14 sets
    // `254` against 0.222 em and 0.0319 of word spacing).
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm 0.3 Tw [(117\\226 )280(18)] TJ ET")
        .map(\.spaces) == [[4]])
    // A kern between the two marks is no word space either (`Bar-|Yosef`, -0.064 em).
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(Bar-)64( )250(Yosef)] TJ ET")
        .map(\.spaces) == [[4]])
    // The same taken back in front of the space: the book's ligatures set the space inside the
    // `ﬁ` and its advance brings the next letter to the ligature's end.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(of)250( )(ce)] TJ ET")
        .map(\.spaces) == [[2]])
    // A run of spaces taken back together (the bibliography's `763 –   4`).
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(763\\226   )750(4)] TJ ET")
        .map(\.spaces) == [[4, 5, 6]])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func aSpaceTheShowBeforeOrAfterTakesBackIsNoWordSpace() throws {
    // A linked citation is its own show: `( )254(1993)` and then `( )254(:)`, the space opening the
    // next show taken back to where the last figure of the one before ends.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(Shavit 1993)] TJ [( )250(: 117)] TJ ET")
        .map(\.spaces) == [[], [0]])
    // Page 35's title ends its show on `- ` and positions `translation` at the hyphen's end.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(The English back- )] TJ 78.33 0 Td (translation) Tj ET")
        .map(\.spaces) == [[17], []])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func everySpaceThePageDrawsKeepsItsReading() throws {
    // An ordinary word space, and a spaced dash: the mark after it stands a space's width on.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm (nineteenth- and twentieth-century) Tj ET")
        .map(\.spaces) == [[]])
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(18\\) \\226 )250( although)] TJ ET")
        .map(\.spaces) == [[]])
    // A space justified narrower but not taken back: 9/11 sets `New York` 0.044 em apart with
    // word spacing, and the narrowest by an adjustment here leaves 0.05 em.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm -2.06 Tw (in New York) Tj ET").map(\.spaces) == [[]])
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(New )200(York)] TJ ET").map(\.spaces) == [[]])
    // Word spacing that keeps a gap after the glyph's own width is taken back: the page still
    // draws that gap, and the Hebrew study's `52– 3` keeps it (0.07 em).
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm 0.7 Tw [(52\\226 )250(3)] TJ ET").map(\.spaces) == [[]])
    // A gap opened before the space is the page's word space: 9/11's `price. . . . One` carries
    // its letter spacing into the space, and the next mark stands where that gap ends.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(price.)-200( )250(One)] TJ ET").map(\.spaces) == [[]])
    // A TJ gap with no space glyph at all is not this rule's to read.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(word)-250(gap)] TJ ET").map(\.spaces) == [[]])
    // A space drawn as a show of its own between two others is placed by its own positioning,
    // like FAA's leader tabs, and a mark drawn far back over the one before is a repositioning.
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm (Rudder) Tj ET BT /F 10 Tf 1 0 0 1 70 700 Tm ( ) Tj ET"
                          + " BT /F 10 Tf 1 0 0 1 70 700 Tm (....) Tj ET").map(\.spaces) == [[], [], []])
    #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm [(4 )1500(3)] TJ ET").map(\.spaces) == [[]])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func aTakenBackSpaceIsNoWordSpaceWithinAFractionOfAHundredthOfAnEm() {
    // Measured over every corpus book: taken-back spaces leave nothing within 0.001 em, or a
    // kern (to -0.064 em); the narrowest gap a word space leaves is 9/11's 0.044 em, and the
    // Fed's leader spaces narrowed to 0.02 em keep their reading.
    for gap: CGFloat in [0, -0.0001, 0.0003, -0.064, 0.01, -0.1] { #expect(NativeSpacingReader.takesBackSpace(gap: gap)) }
    for gap: CGFloat in [0.0101, 0.02, 0.044, 0.07, 0.25, -0.11, -1.98, .nan, .infinity] {
        #expect(!NativeSpacingReader.takesBackSpace(gap: gap))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func aTakenBackSpaceIsRemovedWhereTheLineHoldsItsShows() {
    func removed(_ extracted: String, _ source: String, _ closures: Set<Int>) -> [Int] {
        NativeSpacingReader.closedSpaces(in: Array(extracted.utf16), source: Array(source.utf16), closures: closures)
    }
    // The closure is the space itself, between the two marks it separates.
    #expect(removed("form (Shavit 1993: 117– 18)", "form (Shavit 1993: 117– 18)", [23]) == [23])
    // A run of taken-back spaces is one closure where every space in it is one; PDFKit reads one.
    #expect(removed("763 – 4 .", "763 –   4 .", [5, 6, 7]) == [5])
    #expect(removed("763 – 4 .", "763 –   4 .", [5, 7]).isEmpty)
    // A space the page draws beside the closure is the page's own.
    #expect(removed("18) – although", "18) –  although", [5]).isEmpty)
    // PDFKit splits one printed row into two lines that each hold part of a show: the note's
    // number and its text. Each line owns the run of the show's marks it holds, where they stand
    // in exactly one place; the closure belongs to the line that holds both its marks.
    let note = "     40     This and the next line form a couplet (2.1.129– 30).  "
    let at = Array(note.utf16).firstIndex(of: 0x2013)! + 1
    #expect(removed("This and the next line form a couplet (2.1.129– 30).", note, [at]) == [47])
    #expect(removed("40 ", note, [at]).isEmpty)
    // A line whose marks stand twice among the shows' is not placed, and one the shows do not
    // spell — a Hebrew word the reader cannot decode is a hole in the source — removes nothing.
    #expect(removed("ab– c", "ab– cab– c", [3, 9]).isEmpty)
    #expect(removed("נכלים (1925: 39– 41)", "(1925: 39– 41)", [10]).isEmpty)
    // A ligature is the letters it joins: PDFKit reads the study's `ﬁ` as `fi`.
    #expect(removed("non- fi ction", "non- \u{FB01} ction", [4, 6]) == [4, 7])
    #expect(removed("non- \u{FB01} ction", "non- fi ction", [4, 7]) == [4, 6])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func strokedTextIsReadLikeFilledText() throws {
    // The Hebrew study strokes its pointed Hebrew (`1 Tr`, `2 Tr`) on the pages whose English
    // notes carry most of its ranges; the glyphs are placed alike, so the page is read.
    for mode in ["1 Tr", "2 Tr"] {
        #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm \(mode) [(117\\226 )250(18)] TJ ET").map(\.spaces) == [[4]])
    }
    // Invisible and clipping modes are not visible text, and refuse the page as before.
    for mode in ["3 Tr", "4 Tr", "7 Tr"] {
        #expect(try takenBack("BT /F 10 Tf 1 0 0 1 40 700 Tm \(mode) [(117\\226 )250(18)] TJ ET").isEmpty)
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/316"))
func aLineReadsTheRangeAndTheCompoundThePagePrints() throws {
    // End to end through PDFKit's own reading of the line: the taken-back space goes, the
    // controls on the lines beneath keep theirs.
    let document = try #require(PDFDocument(data: takenBackData("""
        BT /F 10 Tf 1 0 0 1 40 700 Tm [(pages 117\\226 )250(18 in all)] TJ ET
        BT /F 10 Tf 1 0 0 1 40 650 Tm [(the English back- )250(translation)] TJ ET
        BT /F 10 Tf 1 0 0 1 40 600 Tm (nineteenth- and twentieth-century) Tj ET
        BT /F 10 Tf 1 0 0 1 40 550 Tm [(18\\) \\226 )250( although)] TJ ET
        """)))
    defer { withExtendedLifetime(document) {} }
    let page = try #require(document.page(at: 0))
    let lines = try NativeTextReader.lines(on: page, limit: 10_000)
    #expect(lines.map(\.text) == ["pages 117–18 in all", "the English back-translation",
                                  "nineteenth- and twentieth-century", "18) – although"])
}
