import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import PDFReflowLib

// A whole sentence of the book's prose seeds no crop for the relation it states (#312): DASC page
// 9's `Let N = N_f be the length of the route.` seeded a crop that took the display above it and
// `with`, the word before the display. A display row, a worked step and a short equation line
// still seed, and a crop's rows still take the annotation only their union reaches.

/// DASC page 9's shape in Helvetica: the paragraph that ends `…these are the time windows (11),`
/// and breaks before `with`, the display `(a, a) = A` with its scripts, the sentence
/// `Let N = M be the length of the route.` at the margin, and the paragraph after it. As on the
/// page, the display's line reaches 1.2 points into the rectangle of `with`, and the eight-point
/// margins of the display's and the sentence's seeds each reach 0.6 point into the other's line.
private func timeWindowsPage(sentence: String = "Let N = M be the length of the route.",
                             at x: CGFloat = 72) throws -> PageContent {
    let display = 150 + helveticaAdvance("(a, a) = A", size: 10)
    let escaped = sentence.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
    return try accentFixturePage("""
        BT /F1 10 Tf 72 280 Td (Furthermore, let T be the nominal travel time for f from) Tj ET
        BT /F1 10 Tf 72 268 Td (node n to the next node on route, and a the time window) Tj ET
        BT /F1 10 Tf 72 256 Td (available to flight f at node n; these are the time windows) Tj ET
        BT /F1 10 Tf 72 244 Td (with) Tj ET
        BT /F1 10 Tf 150 232 Td (\\(a, a\\) = A) Tj ET
        BT /F1 7 Tf \(display + 0.5) 237.5 Td (n, j) Tj ET
        BT /F1 7 Tf \(display + 0.5) 229 Td (f) Tj ET
        BT /F1 10 Tf \(x) 212.3 Td (\(escaped)) Tj ET
        BT /F1 10 Tf 82 198.9 Td (The problem of scheduling flight f can then be written as) Tj ET
        BT /F1 10 Tf 72 186.9 Td (the Quadratic Program that the solver reads next.) Tj ET
        """)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/312"))
func aSentenceStatingARelationSeedsNoCrop() throws {
    let page = try timeWindowsPage()
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let with = try #require(page.lines.first { $0.text == "with" })
    let sentence = try #require(page.lines.first { $0.text.hasPrefix("Let N") })
    let display = try #require(page.lines.first { $0.text.hasPrefix("(a, a)") })
    // The shape that carried both into the picture: the display's line overlaps `with`, and a
    // crop's eight-point margin around it reaches into the sentence.
    #expect(display.rect.maxY > with.rect.minY)
    #expect(display.rect.minY - 8 < sentence.rect.maxY)
    try #require(crops.count == 1)
    #expect(LayoutReconstructor.takes(crops[0], display))
    #expect(!crops.contains { LayoutReconstructor.takes($0, with) })
    #expect(!crops.contains { LayoutReconstructor.takes($0, sentence) })
    // The crop is the display's own, and holds none of the sentence's middle or of `with`.
    #expect(crops[0].minX > with.rect.maxX)
    #expect(crops[0].minY > sentence.rect.midY)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/312"))
func aLineThatIsNoWholeSentenceStillSeedsItsCrop() throws {
    // The same place on the page, holding a display row, an exercise row, a worked step, an
    // annotation, a sentence with no full stop and a question: none is a whole sentence by the
    // rule, so each still seeds a crop for its relation, and the crop takes it.
    for text in ["x = 2y + 3", "1) 4x + 2y = 0", "5x = 25 Divide both sides by 5", "Then we get our solution x = 5",
                 "Let N = M be the length of the route", "If 1 pound = 16 ounces, how many are 435 ounces?"] {
        let page = try timeWindowsPage(sentence: text)
        let crops = LayoutReconstructor.graphicsWithLabels(page)
        let line = try #require(page.lines.first { $0.text == text }, "\(text)")
        #expect(crops.contains { LayoutReconstructor.takes($0, line) }, "\(text)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/312"))
func onlyAWholeEnglishSentenceIsReadAsOne() {
    func line(_ text: String) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 48.96, y: 196.94, width: 163.16, height: 9.76), fontSize: 9.96)
    }
    // DASC page 9, and Wallace page 112's example, which opens a worked example with a sentence.
    #expect(LayoutReconstructor.readsAsWholeSentence(line("Let N= Nf be the length of the route."), language: "en"))
    #expect(LayoutReconstructor.readsAsWholeSentence(line("Find the slope of a line parallel to 5y− 2x = 7."),
                                                     language: "en-US"))
    #expect(LayoutReconstructor.readsAsWholeSentence(line("Let N ≤ 10 be the number of flights on the route."),
                                                     language: "en"))
    for text in [
        // Wallace's worked steps: an equation and its annotation on one line open with the term.
        "5x = 25 Divide both sides by 5.",
        // No full stop: a display row's annotation, and a question.
        "Then we get our solution x = 5",
        "If 1 pound = 16 ounces, how many pounds 435 ounces?",
        // DASC page 6's display, which opens with its relation; and its STA update, which is no
        // English.
        "= ETAcurrent node + 3600.0distance betw. the nodes.",
        "STArf (k+1) f= STArf (k) f + ETAr(k+1)f−ETAr(k)f.",
        // The display itself, a lone capital, and TeX's mathematical italic, which English
        // words cannot judge.
        "(a̱k,āk) = Ankf ,jkf.",
        "A = lw is the area of the rectangle.",
        "Figure 5: 𝜏 vs E when varying 𝐼, 𝛿= 8𝜇𝑠.",
    ] {
        #expect(!LayoutReconstructor.readsAsWholeSentence(line(text), language: "en"), "\(text)")
    }
    // The test is English's: a book declared otherwise is not judged by it.
    #expect(!LayoutReconstructor.readsAsWholeSentence(line("Let N= Nf be the length of the route."), language: "fr"))
}

/// A worked step's rows, `2x = 26 Divide both sides of the equation by 2` over `x = 13`, with
/// `Our solution for x` beside the lower row, as Wallace page 74 sets them.
private func workedStepPage() throws -> PageContent {
    try accentFixturePage("""
        BT /F1 10 Tf 150 700 Td (2x = 26 Divide both sides of the equation by 2) Tj ET
        BT /F1 10 Tf 214 680 Td (x = 13) Tj ET
        BT /F1 10 Tf 290 680 Td (Our solution for x) Tj ET
        """)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/312"))
func aWorkedStepsCropTakesTheAnnotationOnlyItsRowsReach() throws {
    // Neither row's seed reaches `Our solution for x`: the upper row's margin stops above it and
    // the lower row's to its left. Their union holds it, and the crop keeps it with its row, as
    // Wallace's worked steps need: 407 of Wallace's lines are held by a union of seeds and by
    // none of its seeds alone, 168 of them annotations like this one.
    let page = try workedStepPage()
    let upper = try #require(page.lines.first { $0.text.hasPrefix("2x = 26") })
    let lower = try #require(page.lines.first { $0.text == "x = 13" })
    let note = try #require(page.lines.first { $0.text == "Our solution for x" })
    #expect(!upper.rect.insetBy(dx: -4, dy: -8).intersects(note.rect))
    #expect(!lower.rect.insetBy(dx: -4, dy: -8).intersects(note.rect))
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try #require(crops.count == 1)
    for line in [upper, lower, note] { #expect(LayoutReconstructor.takes(crops[0], line), "\(line.text)") }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/312"))
func aDisplaysNextRowJoinsItsCropAndLeavesWith() throws {
    // A display's second row, set under its first where the sentence stood, is the display's: the
    // two rows' seeds make one crop. `with` stays in the text, because neither row nor their union
    // reaches it; the sentence at the margin did, through the display's line.
    let page = try timeWindowsPage(sentence: "= B + C.", at: 160)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let display = try #require(page.lines.first { $0.text.hasPrefix("(a, a)") })
    let row = try #require(page.lines.first { $0.text == "= B + C." })
    let with = try #require(page.lines.first { $0.text == "with" })
    try #require(crops.count == 1)
    #expect(LayoutReconstructor.takes(crops[0], display) && LayoutReconstructor.takes(crops[0], row))
    #expect(!LayoutReconstructor.takes(crops[0], with))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/312"))
func dascPageNinesTimeWindowDisplayLeavesWithAndTheSentence() throws {
    let url = URL(fileURLWithPath: "corpus/cache/20190030725.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    #expect(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        == "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa")
    let page = try PageReader.read(pageIndex: 8, from: PDFPageSource(url: url), limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let with = try #require(page.lines.first { $0.text == "with" })
    let sentence = try #require(page.lines.first { $0.text.hasPrefix("Let N") && $0.text.hasSuffix("route.") })
    let display = try #require(page.lines.first { $0.text.hasPrefix("(a̱k,āk) =") })
    #expect(!crops.contains { LayoutReconstructor.takes($0, with) })
    #expect(!crops.contains { LayoutReconstructor.takes($0, sentence) })
    let crop = try #require(crops.first { LayoutReconstructor.takes($0, display) })
    // The display alone: no other line's middle stands in its crop.
    #expect(page.lines.filter { LayoutReconstructor.takes(crop, $0) }.map(\.text) == [display.text])
}
