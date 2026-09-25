import CoreText
import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// A second inline script level, read from the page (#302). `NestedInlineScriptEncodingTests`
// covers how the writer spells one; these cover where extraction finds one and where it must not.

/// Each tuple is one run as PDFKit hands it over: text, baseline offset, font size.
private func runs(_ values: [(String, Double, Double)]) -> String {
    let input = NSMutableAttributedString(string: "")
    for (index, value) in values.enumerated() {
        let (text, offset, size) = value
        input.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { PlatformFont(name: "Helvetica", size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
            NSAttributedString.Key("test.run"): index,
        ]))
    }
    return EPUBTextEncoder.inline(NativeTextReader.inlineText(from: input))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aScriptRaisedOrLoweredFromAScriptIsItsSecondLevel() {
    // DASC (corpus/cache/20190030725.pdf) page 3, measured run by run: `STA` in a 9.96-point line,
    // `n` at 6.97 points raised 3.62, and `i` at 4.98 points raised 6.63, which is 3.01 above `n`.
    #expect(runs([("STA", 0, 9.96), ("n", 3.62, 6.97), ("i", 6.63, 4.98), (" occurring", 0, 9.96)])
            == "STA<sup>n<sup>i</sup></sup> occurring")
    // Its page 5 prints STA with `n` raised, `i` raised from `n` and `h` lowered from `n`, then
    // the outer `h` lowered from STA. The inner `h` still stands above the line's baseline; it is
    // the `n` it is lowered from that makes it a subscript.
    #expect(runs([("STA", 0, 10), ("n", 3.6, 7), ("i", 6.6, 5), ("h", 1.5, 5), ("h", -2, 7), (" follows", 0, 10)])
            == "STA<sup>n<sup>i</sup><sub>h</sub></sup><sub>h</sub> follows")
    // Lowered from a lowered script: x sub i sub j.
    #expect(runs([("x", 0, 12), ("i", -2.4, 8), ("j", -4.6, 6), (" = 0", 0, 12)])
            == "x<sub>i<sub>j</sub></sub> = 0")
    // A second-level glyph more than three quarters of the script's size out from it is not
    // that script's: the step is a line's, not a script's.
    #expect(!runs([("x", 0, 12), ("i", 2, 8), ("j", 8.5, 6)]).contains("<sup>i<sup>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func wallaceScriptsDrawnAgainstAnotherScriptReadAtTheirOwnLevel() {
    // Wallace page 178, Example 202: `(a²)³` with tall parentheses the text layer does not carry.
    // The ³ is the ²'s size and stands 3.12 points above it; measured against its own size it was
    // too far from the baseline to be a script at all, and it was written `a<sup>2 </sup>3`. It
    // is the same level as the ², not a second one: it is not smaller, and `(a²)³` is not a^(2^3).
    // The lost parentheses that run the two exponents together are #305.
    #expect(runs([("a", 0, 11.96), ("2 ", 4.32, 7.97), ("3 ", 7.44, 7.97), ("This means", 0, 11.96)])
            == "a<sup>2 3 </sup>This means")
    // Wallace page 205: the denominator of an inline 4x²/4x² is lowered as a whole, and its ² is
    // raised 2.28 from it at a smaller size again. It is x's exponent inside the lowered run.
    #expect(runs([("4x", -4.92, 7.97), ("2 ", -2.64, 5.98), ("divided out", 0, 11.96)])
            == "<sub>4x<sup>2 </sup></sub>divided out")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func singleLevelScriptsStayAtOneLevel() {
    // Negative controls. Exponents, chemical formulas, ordinals and note markers are one level.
    #expect(runs([("ax", 0, 12), ("2", 4, 8), (" + bx + c", 0, 12)]) == "ax<sup>2</sup> + bx + c")
    #expect(runs([("C", 0, 12), ("6", -3, 8), ("H", 0, 12), ("12", -3, 8), ("O", 0, 12), ("6", -3, 8)])
            == "C<sub>6</sub>H<sub>12</sub>O<sub>6</sub>")
    #expect(runs([("the 21", 0, 12), ("st", 4, 8), (" century", 0, 12)]) == "the 21<sup>st</sup> century")
    #expect(runs([("at 7:45.", 0, 12), ("4", 4, 8), (" In another", 0, 12)]) == "at 7:45.<sup>4</sup> In another")
    // A superscript over a subscript of the same size is two first-level scripts, not a nest.
    #expect(runs([("x", 0, 12), ("2", 4, 8), ("i", -3, 8), (" + y", 0, 12)]) == "x<sup>2</sup><sub>i</sub> + y")
    // A smaller run in the script's own baseline is more of the script.
    #expect(runs([("10", 0, 12), ("th", 4, 8), ("*", 4, 6), (" item", 0, 12)]) == "10<sup>th*</sup> item")
    // A glyph back on the baseline ends the script: a smaller run after it is measured from the
    // line, not from the script before.
    #expect(runs([("H", 0, 12), ("2", -3, 8), ("O", 0, 12), ("x", 2, 6)]) == "H<sub>2</sub>O<sup>x</sup>")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func onlyAFirstLevelScriptSmallerThanTheLineAnchorsASecondLevel() {
    // Wallace page 51, `E = mv²/2` set inline: the numerator is raised 6.24 on 7.97 points, too far
    // for a script of its size, so it stays on the line and its exponent is not nested in it.
    #expect(runs([("10) E =", 0, 11.96), ("mv", 6.24, 7.97), ("2", 9.12, 5.98)]) == "10) E =mv2")
    // Wallace page 178, `a² · a²`: PDFKit measures the line from the exponent's baseline, so the
    // body-sized `a` reads lowered. A run the line's own size is no script to nest in.
    #expect(runs([("a", -4.32, 11.96), ("2", 0, 7.97), (" · a", 0, 11.96)]) == "<sub>a</sub>2 · a")
    // Wallace page 187: a smaller glyph on the line's baseline after a lowered one is not raised
    // from it, however far above the lowered run it stands.
    #expect(runs([("a ", -2.52, 7.97), ("1 ", 0, 5.98)]) == "<sub>a </sub>1")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/302"))
func aPageDrawingTwoScriptLevelsReachesTheEPUBNested() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    // Text rise (`Ts`) is the whole baseline offset; each run is shown after the one before it.
    // PDFKit splits a row that steps straight from a raised second level to a lowered one into
    // two lines (#303), so each name here carries one second level.
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("""
        BT /F1 10 Tf 40 260 Td (For each STA) Tj /F1 7 Tf 3.6 Ts (n) Tj /F1 5 Tf 6.6 Ts (i) Tj \
        /F1 10 Tf 0 Ts ( in the schedule and each T) Tj /F1 7 Tf 3.6 Ts (n) Tj /F1 5 Tf 1.5 Ts (h) Tj \
        /F1 10 Tf 0 Ts ( before it.) Tj ET
        BT /F1 12 Tf 40 200 Td (Then x) Tj /F1 8 Tf -2.4 Ts (i) Tj /F1 6 Tf -4.6 Ts (j) Tj /F1 12 Tf 0 Ts ( is zero.) Tj ET
        BT /F1 12 Tf 40 160 Td (So a) Tj /F1 8 Tf 4.32 Ts (2) Tj ( ) Tj 7.44 Ts (3) Tj /F1 12 Tf 0 Ts ( is a power.) Tj ET
        BT /F1 12 Tf 40 120 Td (Read ax) Tj /F1 8 Tf 4 Ts (2) Tj /F1 12 Tf 0 Ts ( and H) Tj /F1 8 Tf -3 Ts (2) Tj \
        /F1 12 Tf 0 Ts (O, the 21) Tj /F1 8 Tf 4 Ts (st) Tj /F1 12 Tf 0 Ts ( note.) Tj /F1 8 Tf 4 Ts (4) Tj ET
        """),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.imageCount == 0 && report.reflowedPageCount == 1)
    let html = try Archive(url: epub, accessMode: .read).chapter()
    #expect(html.contains("STA<sup>n<sup>i</sup></sup> in the schedule and each T<sup>n<sub>h</sub></sup> before it."))
    #expect(html.contains("x<sub>i<sub>j</sub></sub> is zero."))
    #expect(html.contains("a<sup>2 3</sup> is a power."))
    // Negative controls on the same page stay at one level.
    #expect(html.contains("ax<sup>2</sup> and H<sub>2</sub>O, the 21<sup>st</sup> note.<sup>4</sup>"))
}
