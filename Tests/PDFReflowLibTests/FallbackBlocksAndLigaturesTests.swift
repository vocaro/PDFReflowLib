import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #122 and #123 items 1–2: blocks that interleave by baseline in `ordered()`'s reading-order sort,
// rotated OCR lines, ligatures in hyphen evidence, and a spaced example line under a list item.
// Fixtures are extraction from the checksum-pinned sources (`cdc-17-ocr` is Vision output captured
// with `tools/capture-ocr-layout-fixture.swift`); expected orders were read from the rendered pages.

private let cdcSHA256 = "d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3"
private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

/// The page as the pipeline reflows it. CDC pages report `unverifiedTextLayer`, so the pipeline
/// clears their graphics and crops nothing; Wallace keeps its preserved regions.
private func reflow(_ name: String, vocabulary: Set<String> = [], regions: Bool = false)
    throws -> (page: PageContent, blocks: [ReflowBlock], warnings: [ConversionWarning]) {
    let page = try SourceLayoutFixture.load(name).content()
    let crops = regions ? LayoutReconstructor.graphicsWithLabels(page) : []
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: vocabulary, warnings: &warnings)
    return (page, blocks, warnings)
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 10,
                  size: CGFloat = 10) -> LayoutReconstructor.Element {
    let rect = CGRect(x: x, y: y, width: width, height: height)
    return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: size))
}

/// A centred stack of lines: each entry is (text, width), `pitch` apart from `top` down.
private func centred(_ lines: [(String, CGFloat)], centre: CGFloat, top: CGFloat, pitch: CGFloat) -> [LayoutReconstructor.Element] {
    lines.enumerated().map { index, entry in
        line(entry.0, x: centre - entry.1 / 2, y: top - CGFloat(index) * pitch, width: entry.1)
    }
}

private func texts(_ elements: [LayoutReconstructor.Element]) -> [String] { elements.compactMap { $0.line?.text } }

// MARK: - #122: a balloon beside a caption box

// Pages 14, 23 and 34 set a speech balloon beside a caption box. The inherited text layer's
// rectangles overhang the lettering, so no whitespace separates them, and the row sort alternated
// their lines (page 34: `wow... THAT` / `.severe…` / `o ld THINg STILL` / `in effect…` / `works!`).
// Each unit now reads whole, the left one first.
@Test(arguments: [
    ("cdc-14", ["Nothing eut snow .", "le t 's tr y the radio...",
                "sray in your Homes. do nor go ourside. if you o r your FAMiLy eegin showing symptoms such a s",
                "slow bo MovBMenr, sLurred spbbch , o r viOLenr eBHAviors. iso la t b",
                "thbm ro a secure area of thb House.",
                "sray runed For more inForMArion on where ro go... stay in your...",
                "uhm.. todd...", "W hat's going on n o w ?"]),
    ("cdc-34", ["what Are you L o o k in g", "f o r ?", "SoMeTHINg THAT c o u ld coMe IN reAL HANDy..",
                "what i f we w ere st u c k in THe House o r HAD TO evAcuAte?", "we Need to HAVe A PLAN!",
                "wow... THAT o ld THINg STILL", "w o r k s !", ".severe TttuaeesTom wACNiNg",
                "in effect fo r THe FOLLowiNg couNTies: peiNce georges, BACToW, WAYNe..."]),
])
func sourceBalloonBesideACaptionBoxReadsWhole(name: String, expected: [String]) throws {
    #expect(try SourceLayoutFixture.load(name).sourceSHA256 == cdcSHA256)
    let (_, blocks, _) = try reflow(name)
    #expect(blocks.map(\.text) == expected)
}

// Page 23: the `we're almost out of food` balloon in the left panel, then the radio broadcast in
// the right panel, each whole; the lower panels are unchanged.
@Test func sourceFoodBalloonReadsBeforeTheBroadcast() throws {
    #expect(try SourceLayoutFixture.load("cdc-23").sourceSHA256 == cdcSHA256)
    let (page, blocks, _) = try reflow("cdc-23")
    #expect(Array(blocks.map(\.text).prefix(8)) == [
        "w e're aLmosT ou t o f fQQ d. It 's eeen", "aLm ost a week, todd, and we haven't le f t the", "H o u s e !",
        "...coNr/Nues ro spreAd.", "cdc is ure/Ne everyone ro prAcr/ce iso lat io n.", "stay in your Homes.",
        "if you must lbavb, eo d/recrLy ro a des/eNAred sa f b zqnb.", "vacc/n b s w/ll bb shipped",
    ])
    #expect(blocks.map(\.text).joined().filter { !$0.isWhitespace }.sorted()
        == page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted())
}

// A centred balloon beside a centred box at a different leading, as on the CDC pages, and the
// controls that each isolate one guard of `interleavedBlocks`.
@Test func interleavedBlocksNeedTwoCentredUnitsSideBySide() {
    let balloon = centred([("NOTHING BUT SNOW.", 90), ("LET'S TRY", 45), ("THE RADIO...", 56)], centre: 110, top: 225, pitch: 10.6)
    // The box's first rectangle overhangs the balloon, as the CDC layer's merged lines do, so no
    // whitespace cut separates the units and the region reaches the reading-order sort.
    var box = centred([("STAY IN YOUR HOMES. DO NOT GO", 160), ("SLOWED MOVEMENT, SLURRED", 150), ("OR VIOLENT BEHAVIORS.", 130),
                       ("THEM TO A SECURE AREA", 160)], centre: 290, top: 230, pitch: 9.1)
    box[0] = line("STAY IN YOUR HOMES. DO NOT GO OUTSIDE.", x: 121, y: 230, width: 326)
    #expect(texts(LayoutReconstructor.sortedByRows(box + balloon, bodySize: 10)).first == "STAY IN YOUR HOMES. DO NOT GO OUTSIDE.")
    let positive = LayoutReconstructor.interleavedBlocks(box + balloon, bodySize: 10)
    #expect(positive.map { $0.map(texts) } == [texts(balloon), texts(box)])
    // The whole `ordered()` path reads the balloon, then the box.
    #expect(texts(LayoutReconstructor.ordered(box + balloon, bodySize: 10)) == texts(balloon) + texts(box))

    // Rows sharing baselines: a name beside its description (9/11 page 452).
    let names = [line("Ali Abdul Aziz Ali", x: 40, y: 700, width: 90), line("Mohamed Atta", x: 40, y: 670, width: 70)]
    let descriptions = [line("Pakistani; nephew of KSM", x: 160, y: 700, width: 200), line("and facilitator", x: 160, y: 690, width: 120),
                        line("Egyptian; tactical leader", x: 160, y: 670, width: 200), line("of the plot", x: 160, y: 660, width: 90)]
    #expect(LayoutReconstructor.interleavedBlocks(names + descriptions, bodySize: 10) == nil)
    // Left-aligned columns a few points off each other's baselines (Project Blue Book's tables).
    let labels = (0..<4).map { line("\($0)-Label", x: 40, y: 700 - CGFloat($0) * 12, width: CGFloat(50 + $0 * 12)) }
    let figures = (0..<4).map { line("\($0) 12 4.5", x: 150, y: 696 - CGFloat($0) * 12, width: CGFloat(90 - $0 * 10)) }
    #expect(LayoutReconstructor.interleavedBlocks(labels + figures, bodySize: 10) == nil)
    // The same centred units without the left-edge spread that marks centring.
    let flush = balloon.map { element -> LayoutReconstructor.Element in
        line(element.line!.text, x: 65, y: element.rect.minY, width: element.rect.width)
    }
    #expect(LayoutReconstructor.interleavedBlocks(box + flush, bodySize: 10) == nil)
    // A third block in the region.
    let third = centred([("UHM.. TODD...", 60), ("WHAT'S GOING ON NOW?", 110)], centre: 450, top: 226, pitch: 11)
    #expect(LayoutReconstructor.interleavedBlocks(box + balloon + third, bodySize: 10) == nil)
    // Units that do not share their height read one after the other already.
    let lower = balloon.map { element -> LayoutReconstructor.Element in
        line(element.line!.text, x: element.rect.minX, y: element.rect.minY - 60, width: element.rect.width)
    }
    #expect(LayoutReconstructor.interleavedBlocks(box + lower, bodySize: 10) == nil)
    // Centres close together: one column, not two units beside each other.
    let stacked = centred([("A LINE SET CENTRED", 150), ("UNDER ANOTHER LINE", 140), ("AND A THIRD", 146)], centre: 280, top: 225, pitch: 10.6)
    #expect(LayoutReconstructor.interleavedBlocks(box + stacked, bodySize: 10) == nil)
    // A list line in the region leaves it to the row logic.
    var listed = balloon
    listed[1] = line("• LET'S TRY", x: 87, y: listed[1].rect.minY, width: 46)
    #expect(LayoutReconstructor.interleavedBlocks(box + listed, bodySize: 10) == nil)
    // A box that begins at the balloon's last line: the row sort reads them one after the other.
    let after = centred([("STAY IN YOUR HOMES. DO NOT GO", 160), ("SLOWED MOVEMENT, SLURRED", 150), ("OR VIOLENT BEHAVIORS.", 130),
                         ("THEM TO A SECURE AREA", 160)], centre: 290, top: 204, pitch: 9.1)
    #expect(LayoutReconstructor.interleavedBlocks(after + balloon, bodySize: 10) == nil)
    // A box line whose overhanging rectangle reaches under the balloon's last line on its row is
    // not a piece of that row: pieces of one row stand apart.
    var overhanging = box
    overhanging[3] = line("THEM TO A SECURE AREA OF THE HOUSE", x: 130, y: 202.7, width: 240)
    #expect(LayoutReconstructor.interleavedBlocks(overhanging + balloon, bodySize: 10).map { $0.map(texts) }
        == [texts(balloon), texts(overhanging)])
    // A shared baseline for most of the smaller unit's lines.
    let aligned = centred([("NOTHING BUT SNOW.", 90), ("LET'S TRY", 45), ("THE RADIO...", 56)], centre: 110, top: 230, pitch: 9.1)
    #expect(LayoutReconstructor.interleavedBlocks(box + aligned, bodySize: 10) == nil)
}

// MARK: - #122: a rotated OCR caption

// Page 17 is recognized: its caption is set sideways, running down the page, so its three lines
// stack from right to left. Their rectangles are 9 points wide and up to 225 tall, and the row sort
// read them left to right, last line first. Vision's quadrilaterals give each line's direction.
@Test func sourceRotatedOCRCaptionReadsInLineOrder() throws {
    let fixture = try SourceLayoutFixture.load("cdc-17-ocr")
    #expect(fixture.sourceSHA256 == cdcSHA256)
    #expect(fixture.lines.allSatisfy { ($0.readingDirection?[1] ?? 0) < -0.99 })
    let (_, blocks, _) = try reflow("cdc-17-ocr")
    #expect(blocks.map(\.text) == ["SEVERAL DAYS LATER AT THE CENTERS FOR", "DISEASE CONTROL AND PREVENTION IN", "ATLANTA, GEORGIA..."])
}

@Test func rotatedLinesReadAlongTheirAdvance() throws {
    func rotated(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat, direction: CGVector) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: 9, height: height)
        var textLine = TextLine(text: text, rect: rect, fontSize: height)
        textLine.readingDirection = direction
        return .init(rect: rect, line: textLine)
    }
    let down = CGVector(dx: 0, dy: -1), up = CGVector(dx: 0, dy: 1)
    // Running down the page, lines stack leftward; running up it, rightward.
    let downward = [rotated("third", x: 330, y: 140, height: 100, direction: down),
                    rotated("first", x: 355, y: 20, height: 220, direction: down),
                    rotated("second", x: 342, y: 45, height: 195, direction: down)]
    #expect(LayoutReconstructor.rotatedLineOrder(downward).map(texts) == ["first", "second", "third"])
    let upward = [rotated("second", x: 60, y: 100, height: 200, direction: up),
                  rotated("third", x: 73, y: 100, height: 90, direction: up),
                  rotated("first", x: 47, y: 100, height: 220, direction: up)]
    #expect(LayoutReconstructor.rotatedLineOrder(upward).map(texts) == ["first", "second", "third"])
    // Controls: upright text, mixed directions and a rotated line among upright ones.
    #expect(LayoutReconstructor.rotatedLineOrder([line("a", x: 0, y: 10, width: 50), line("b", x: 0, y: 0, width: 50)]) == nil)
    #expect(LayoutReconstructor.rotatedLineOrder([downward[0], upward[0]]) == nil)
    #expect(LayoutReconstructor.rotatedLineOrder([downward[0], line("caption", x: 0, y: 0, width: 50)]) == nil)

    let page = CGRect(x: 0, y: 0, width: 392, height: 613)
    #expect(OCRReader.readingDirection(from: (0.1, 0.5), to: (0.6, 0.5), in: page) == nil)
    #expect(OCRReader.readingDirection(from: (0.1, 0.5), to: (0.6, 0.6), in: page) == nil)
    #expect(OCRReader.readingDirection(from: (0.928, 0.406), to: (0.928, 0.04), in: page) == CGVector(dx: 0, dy: -1))
    #expect(OCRReader.readingDirection(from: (0.1, 0.1), to: (0.1, 0.5), in: page) == CGVector(dx: 0, dy: 1))
    #expect(OCRReader.readingDirection(from: (0.6, 0.5), to: (0.1, 0.5), in: page) == CGVector(dx: -1, dy: 0))

    // A line recognized in a retry band (#116) keeps its direction in page proportions: the band's
    // normalized height is a fraction of the page's.
    let band = OCRReader.Recognition(lines: [.init(text: "caption", box: CGRect(x: 0.9, y: 0.2, width: 0.02, height: 0.5),
                                                   wraps: nil, topEdge: CGVector(dx: 0, dy: -0.5))])
    let merged = OCRReader.mergeBands([(band, 0.4, 0.6)])
    #expect(merged.lines.map(\.topEdge) == [CGVector(dx: 0, dy: -0.3)])

    // The direction survives the page store's encoding.
    var encoded = TextLine(text: "caption", rect: .init(x: 1, y: 2, width: 9, height: 100), fontSize: 100)
    encoded.readingDirection = down
    #expect(try JSONDecoder().decode(TextLine.self, from: JSONEncoder().encode(encoded)) == encoded)
}

// MARK: - #123 item 1: ligatures in hyphen evidence

// Wallace prints `diﬀerent` with U+FB00 wherever the word is whole, but a line break extracts
// plain letters, so `dif-` + `ferent` (pages 50 and 218) kept its hyphen with a warning. The
// vocabulary now also records such words with their ligatures spelled out; emitted text keeps them.
@Test func sourceDifferentJoinsOnTheBooksLigatureSpelling() throws {
    #expect(try SourceLayoutFixture.load("algebra-50").sourceSHA256 == algebraSHA256)
    #expect(try SourceLayoutFixture.load("algebra-218").sourceSHA256 == algebraSHA256)
    var vocabulary: Set<String> = []
    for name in ["algebra-50", "algebra-218"] {
        LayoutReconstructor.addVocabulary(of: try SourceLayoutFixture.load(name).content(), to: &vocabulary)
    }
    #expect(vocabulary.contains("different"))
    #expect(vocabulary.contains("di\u{FB00}erent"))
    let (_, page50, warnings50) = try reflow("algebra-50", vocabulary: vocabulary, regions: true)
    let text50 = page50.map(\.text).joined(separator: "\n")
    #expect(text50.contains("they are just written in a different form because we solved them in diﬀerent ways."))
    #expect(text50.contains("slightly diﬀerent manner"))
    #expect(!text50.contains("dif-ferent"))
    #expect(!warnings50.contains { $0.code == .uncertainHyphen })
    let (_, page218, warnings218) = try reflow("algebra-218", vocabulary: vocabulary, regions: true)
    #expect(page218.map(\.text).joined(separator: "\n").contains("more than just the signs are different. In this case"))
    #expect(!warnings218.contains { $0.code == .uncertainHyphen })

    // Negative control: the same pages without the spelled-out word keep the hyphen and warn.
    var unfolded = vocabulary
    unfolded.remove("different")
    let (_, before, beforeWarnings) = try reflow("algebra-50", vocabulary: unfolded, regions: true)
    #expect(before.map(\.text).joined(separator: "\n").contains("dif-ferent form"))
    #expect(beforeWarnings.contains { $0.code == .uncertainHyphen })
}

@Test func vocabularyRecordsLigatureWordsSpelledOut() throws {
    #expect(LayoutReconstructor.ligaturesSpelledOut("diﬀerent ﬁre ﬂow oﬃce baﬄe ﬅ ﬆ") == "different fire flow office baffle st st")
    // Only the Latin ligatures are spelled out: other compatibility forms stay.
    #expect(LayoutReconstructor.ligaturesSpelledOut("x² ½ ｆ") == "x² ½ ｆ")
    var vocabulary: Set<String> = []
    LayoutReconstructor.addVocabulary(of: PageContent(number: 1, bounds: .init(x: 0, y: 0, width: 600, height: 800), lines: [
        TextLine(text: "The eﬀect of an oﬃcial ﬁgure", rect: .init(x: 0, y: 700, width: 300, height: 12), fontSize: 12),
    ], graphics: []), to: &vocabulary)
    #expect(vocabulary.isSuperset(of: ["effect", "official", "figure", "eﬀect", "oﬃcial", "ﬁgure", "the", "of", "an"]))
    #expect(vocabulary.count == 9)
    var warnings: [ConversionWarning] = []
    // Plain halves find the spelled-out word, a ligature in a half the printed one; the text keeps its glyphs.
    #expect(LayoutReconstructor.join("the ef-", "fect of", vocabulary: vocabulary, page: 1, warnings: &warnings) == "the effect of")
    #expect(LayoutReconstructor.join("an oﬃ-", "cial figure", vocabulary: vocabulary, page: 1, warnings: &warnings) == "an oﬃcial figure")
    #expect(LayoutReconstructor.join("a ﬁg-", "ure", vocabulary: vocabulary, page: 1, warnings: &warnings) == "a ﬁgure")
    #expect(warnings.isEmpty)
    // Control: a word the book never prints, ligature or not, keeps its hyphen and warns.
    #expect(LayoutReconstructor.join("a baf-", "fle", vocabulary: vocabulary, page: 1, warnings: &warnings) == "a baf-fle")
    #expect(warnings.map(\.code) == [.uncertainHyphen])
}

// MARK: - #123 item 2: a spaced example line under a list item

// Page 64 sets `Three more than a number becomes x + 3` 9.7 points under the `More than` item's
// wrapped line, where the page's wrapped lines stand 2.4 apart; before, it ran on into the item
// (`…plus the first Three more than…`). The same holds for `Four less than…`.
@Test func sourceSpacedExampleLinesStandApartFromTheirItems() throws {
    #expect(try SourceLayoutFixture.load("algebra-64").sourceSHA256 == algebraSHA256)
    for regions in [true, false] {
        let (_, blocks, _) = try reflow("algebra-64", regions: regions)
        let text = blocks.map(\.text)
        #expect(text.contains("• More than often represents addition and is usually built backwards, writing the second part plus the first"))
        #expect(text.contains("Three more than a number becomes x + 3"))
        #expect(text.contains("• Less than often represents subtraction and is usually built backwards as well, writing the second part minus the first"))
        #expect(text.contains("Four less than a number becomes x− 4"))
    }
}

@Test func addedSpaceUnderAWrappedItemOpensALine() {
    func page(_ lines: [TextLine]) -> [String] {
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: PageContent(number: 1, bounds: .init(x: 0, y: 0, width: 600, height: 800),
            lines: lines, graphics: []), images: [], vocabulary: [], warnings: &warnings).map(\.text)
    }
    func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat = 400) -> TextLine {
        TextLine(text: value, rect: .init(x: x, y: y, width: width, height: 12), fontSize: 12)
    }
    // Prose at 14.4-point leading establishes the page's ordinary 2.4-point gap.
    let prose = (0..<4).map { text("Word problems can be tricky and it takes practice to convert sentences line \($0)", x: 85, y: 700 - CGFloat($0) * 14.4, width: 425) }
    let item = [text("• More than often represents addition and is usually built backwards,", x: 101, y: 600),
                text("writing the second part plus the first", x: 121, y: 585.6, width: 190)]
    #expect(page(prose + item + [text("Three more than a number becomes x + 3", x: 121, y: 563.9, width: 215)]).suffix(2)
        == ["• More than often represents addition and is usually built backwards, writing the second part plus the first",
            "Three more than a number becomes x + 3"])
    // Controls: a wrapped line at the ordinary gap, and a spaced line opening lowercase, stay in the item.
    #expect(page(prose + item + [text("and more of the item", x: 121, y: 571.2, width: 100)]).last
        == "• More than often represents addition and is usually built backwards, writing the second part plus the first and more of the item")
    #expect(page(prose + item + [text("three more than a number becomes x + 3", x: 121, y: 563.9, width: 215)]).last
        == "• More than often represents addition and is usually built backwards, writing the second part plus the first three more than a number becomes x + 3")
    // Without other lines to measure an ordinary gap, the spaced line joins as before.
    #expect(page(item + [text("Three more than a number becomes x + 3", x: 121, y: 563.9, width: 215)]).last
        == "• More than often represents addition and is usually built backwards, writing the second part plus the first Three more than a number becomes x + 3")
}
