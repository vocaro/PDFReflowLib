import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Rows PDFKit splits at inline radicals (#95) and paragraphs set off by a blank line that the
// line rectangles' height hides under the paragraph threshold (#71). Fixtures are native extraction
// from the checksum-pinned corpus documents; expected text was read from the rendered source pages.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

private func sourcePage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    if name.hasPrefix("algebra-") { #expect(fixture.sourceSHA256 == algebraSHA256, "\(name) source identity") }
    var page = fixture.styledContent()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    return page
}

/// The page's blocks with the preserved regions the pipeline would crop.
private func reflow(_ page: PageContent, crops: Bool = true) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    let regions = crops ? LayoutReconstructor.graphicsWithLabels(page) : []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private func paragraph(_ texts: [String], containing phrase: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
    try #require(texts.first { $0.contains(phrase) }, "no paragraph holds \(phrase)", sourceLocation: sourceLocation)
}

// MARK: - #95 split radical rows

// Wallace page 288: each sentence with an inline radical reads as one line of its paragraph, in
// order; no radical piece is a block of its own.
@Test func sourceRadicalRowPiecesJoinTheirParagraphsInOrder() throws {
    let texts = paragraphs(reflow(try sourcePage("algebra-288")))
    for piece in ["√ on", "√ by spliting", "36· 5", "25 √ .", "= 25 we say the square root of 25 is 5.",
                  "√ is currently undefined as negatives have no square root.",
                  "√ , and simplifying the first root, 6 5 √ . The trick in this"] {
        #expect(!texts.contains(piece), "row piece left as its own paragraph: \(piece)")
    }
    let opening = try paragraph(texts, containing: "Square roots are the most common type of radical used.")
    #expect(opening.hasSuffix("For example, because 52 = 25 we say the square root of 25 is 5. The square root of 25 is written as 25 √ ."))
    let final = try paragraph(texts, containing: "The final example,")
    #expect(final.hasPrefix("The final example,− 81 √ is currently undefined as negatives have no square root. This is because"))
    let calculator = try paragraph(texts, containing: "Not all numbers have a nice even square root.")
    #expect(calculator.contains("if we found 8 √ on our calculator, the answer would be"))
    #expect(calculator.hasSuffix("known as the product rule of radicals"))
    let product = try paragraph(texts, containing: "We can use the product rule")
    #expect(product == "We can use the product rule to simplify an expression such as 36· 5 √ by spliting it into two roots, 36 √ · 5 √ , and simplifying the first root, 6 5 √ . The trick in this")
}

// Wallace page 289: the page's opening sentence, split around `√180` and `√36·5`, is one paragraph
// with the lines beneath it; the three derivations stay preserved.
@Test func sourceOpeningRadicalRowJoinsTheParagraphBeneathIt() throws {
    let blocks = reflow(try sourcePage("algebra-289"))
    let texts = paragraphs(blocks)
    #expect(!texts.contains("√ . There are sev-"))
    let opening = try #require(texts.first)
    #expect(opening.hasPrefix("process is being able to translate a problem like 180 √ into 36· 5 √ . There are sev"))
    #expect(opening.hasSuffix("eral ways this can be done. The most common and, with a bit of practice, the fastest method, is to find perfect squares that divide evenly into the radicand, or number under the radical. This is shown in the next example."))
    #expect(blocks.filter { if case .image = $0.content { true } else { false } }.count == 3)
}

// Wallace page 299: the World View Note's last row, split at `√2`, closes its paragraph.
@Test func sourceRadicalRowClosesItsNoteParagraph() throws {
    let texts = paragraphs(reflow(try sourcePage("algebra-299")))
    #expect(!texts.contains("√ accurate to five decimal places (1.41421)"))
    let note = try paragraph(texts, containing: "World View Note: Clay tablets")
    #expect(note.hasSuffix("In one of the tables there is an approximation of 2 √ accurate to five decimal places (1.41421)"))
}

// Rows whose pieces meet at inline algebra join; lines of the next row never do. Each page was
// reviewed against its render after a first candidate joined across rows: a short line at the left
// edge inside the tall rectangle of the full line above it (pages 9, 120, 180), a chain through a
// tall piece into the next row (pages 198, 212), and a derivation annotation beside its step
// (page 189).
@Test func sourceAlgebraRowsJoinOnlyWithinTheirRow() throws {
    func texts(_ name: String) throws -> [String] { paragraphs(reflow(try sourcePage(name))) }
    let page9 = try texts("algebra-9")
    #expect(!page9.contains { $0.contains("=− 21.") })
    // `21.` closes the sentence it continues (#109 keeps it in that paragraph), after the row above.
    #expect(page9.contains { $0.hasSuffix("the answer is positive, (− 3)(− 7) = 21.") })
    #expect(try !texts("algebra-120").contains { $0.contains("equal to Graph starts") })
    let page180 = try texts("algebra-180")
    #expect(!page180.contains { $0.contains("example. rather") })
    #expect(page180.contains { $0.contains("does not mean we multipy 5 by 3, rather we multiply 5 three times, 5 × 5 × 5 = 125.") })
    let page189 = try texts("algebra-189")
    #expect(!page189.contains { $0.contains("standard notation Positiveexponentmeansstandardnotation") })
    #expect(!page189.contains { $0.contains("standard notation Negativeexponentmeansstandardnotation") })
    #expect(try texts("algebra-198").contains {
        $0.contains("come up with 12x2 − 8xy + 21xy− 14y2 and then combine like terms to come up with the final solution.")
    })
    #expect(try texts("algebra-212").contains { $0.contains("solving problems such as 4x2(2x2 − 3x + 8) = 8x4 − 12x3") })
    // Joins those guards must still allow: a word-space gap with no sign at the join (page 185), a
    // sign in the right piece's second token (page 292), a radicand inside its sign's piece (page
    // 290) and a short staggered sign piece (page 305). On page 321 the radicand `− 1` opens its
    // row with a minus sign, which is not a list marker (#109): no preserved list line appears.
    #expect(try texts("algebra-185").contains { $0.contains("tury wrote 121m¯ to indicate 12x−1. This was the first known use of the negative") })
    #expect(try texts("algebra-290").contains { $0.contains("For example, x8 √ = x4, because we divide the exponent of 8 by 2.") })
    #expect(try texts("algebra-292").contains { $0.contains("check the index on the root. 81 √ = 9 but 814√ = 3. This is because 92 = 81") })
    #expect(try texts("algebra-305").contains { $0.contains("So for our example with 3 √ − 5 in the denominator, the conjugate would be 3 √ +") })
    let page321 = reflow(try sourcePage("algebra-321"))
    #expect(!page321.contains { if case .preformatted = $0.content { $0.text.contains("and it is in the denominator") } else { false } })
    #expect(paragraphs(page321).contains { $0.contains("If i is − 1 √ , and it is in the denominator of a fraction") })
    // Page 318: two rows split at their equations rejoin, and the World View Note, set off by
    // added space, is its own paragraph (#71).
    let page318 = try texts("algebra-318")
    #expect(page318.contains { $0.contains("manipulating our definition of i2 =− 1. If we multiply both sides of the definition by i,") })
    #expect(page318.contains { $0.contains("equation again by i, the equation becomes i4 =− i2 =− (− 1) = 1, or simply i4 = 1. Multiplying") })
    let note = try paragraph(page318, containing: "World View Note: When mathematics was first used")
    #expect(!note.contains("In mathematics, when the current number system"))
}

// Exercise columns, answer keys, derivations and tables whose entries share rows keep every block:
// their pieces carry operators but do not read as prose on a paragraph's measure. The `withoutCrops`
// counts are the reconstruction at `0d4f24e`, before rows were joined, with no crop at all, so every
// derivation row is exposed to the join. The `withCrops` counts are the same reconstruction except
// on the seven pages where a crop now takes the piece its edge used to leave outside (#46, #48):
// 471 52 → 49, 343 9 → 8, 16 45 → 39, 479 14 → 12, 424 30 → 28, 448 48 → 44 and 487 64 → 49.
@Test func sourceExerciseColumnsKeepTheirRowPiecesApart() throws {
    for (name, withCrops, withoutCrops) in [("algebra-10", 47, 47), ("algebra-26", 54, 54), ("algebra-438", 71, 71),
                                            ("algebra-471", 49, 57), ("algebra-101", 44, 51), ("algebra-343", 8, 93),
                                            ("algebra-16", 39, 74), ("algebra-40", 16, 30), ("algebra-479", 12, 194),
                                            ("algebra-186", 12, 35), ("algebra-424", 28, 45), ("algebra-448", 44, 68),
                                            ("algebra-449", 28, 74), ("algebra-487", 49, 88), ("algebra-291", 7, 53)] {
        let page = try sourcePage(name)
        #expect(reflow(page).count == withCrops, "\(name) with crops \(reflow(page).count)")
        #expect(reflow(page, crops: false).count == withoutCrops, "\(name) without crops \(reflow(page, crops: false).count)")
    }
}

// Synthetic 12-point justified prose (14.6-point leading) around a row split at an inline radical.
private func mathLine(_ text: String, x: CGFloat = 85, baseline: CGFloat, width: CGFloat = 425, height: CGFloat = 12) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: baseline - 3, width: width, height: height), fontSize: 12)
}

private func splitRowPage(right: TextLine, left: TextLine? = nil, extra: [TextLine] = []) -> PageContent {
    let lines = [
        mathLine("Square roots are the most common type of radical used in the lessons that follow here", baseline: 700),
        mathLine("and every one of them is written with the radical sign over the number it applies to.", baseline: 685.4),
        left ?? mathLine("Not all numbers have a nice even square root. For example, if we found 8", baseline: 670.8, width: 407),
        right,
        mathLine("our calculator, the answer would be a long decimal that goes on without any end at all", baseline: 656.2),
        mathLine("and even this number is a rounded approximation of the square root we were looking for.", baseline: 641.6),
    ] + extra
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 595, height: 842), lines: lines, graphics: [])
}

@Test func syntheticSplitRadicalRowJoinsOnlyAsProse() throws {
    // The source geometry: the radical piece overlaps the row's end and rises above it.
    let radical = TextLine(text: "√ on", rect: CGRect(x: 476, y: 667.8, width: 34, height: 22), fontSize: 12)
    let joined = paragraphs(reflow(splitRowPage(right: radical), crops: false))
    #expect(joined.count == 1)
    #expect(joined.first?.contains("if we found 8 √ on our calculator") == true)

    // A crop between the pieces keeps them apart; the same pieces without it form one row.
    let gapPiece = TextLine(text: "√ on", rect: CGRect(x: 495, y: 667.8, width: 15, height: 22), fontSize: 12)
    let short = mathLine("Not all numbers have a nice even square root. For example, if we found", baseline: 670.8, width: 395)
    let gapped = splitRowPage(right: gapPiece, left: short)
    #expect(paragraphs(reflow(gapped, crops: false)).contains { $0.contains("if we found √ on our calculator") })
    var warnings: [ConversionWarning] = []
    let cropped = LayoutReconstructor.blocks(page: gapped, images: [(CGRect(x: 482, y: 668, width: 11, height: 10), "image-0")],
                                             vocabulary: [], warnings: &warnings)
    #expect(!paragraphs(cropped).contains { $0.contains("found √ on") })

    // A short line of the next row at the column's edge, without words and not a list marker, lies
    // within a tall full line above it; it is not that line's radicand. (Page 9's `21.` has the
    // same geometry but would also read as a list marker.)
    let tall = TextLine(text: "Not all numbers have a nice even square root. For example, if we found √ 8 on", rect: CGRect(x: 85, y: 664, width: 425, height: 22), fontSize: 12)
    let edge = TextLine(text: "(2.828)", rect: CGRect(x: 85, y: 658, width: 40, height: 12), fontSize: 12)
    let edgePage = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 595, height: 842), lines: [
        mathLine("Square roots are the most common type of radical used in the lessons that follow here", baseline: 700),
        mathLine("and every one of them is written with the radical sign over the number it applies to.", baseline: 685.4),
        tall, edge,
        mathLine("our calculator, the answer would be a long decimal that goes on without any end at all", baseline: 641.6),
        mathLine("and even this number is a rounded approximation of the square root we were looking for.", baseline: 627),
    ], graphics: [])
    #expect(!paragraphs(reflow(edgePage, crops: false)).contains { $0.contains("(2.828) Not all numbers") })

    // Without a mathematical sign the pieces are one row too, since #148: the row is a full line of
    // its paragraph and its text runs on across a gap no wider than a word space.
    let plain = TextLine(text: "on", rect: CGRect(x: 494, y: 667.8, width: 16, height: 12), fontSize: 12)
    #expect(paragraphs(reflow(splitRowPage(right: plain), crops: false)).contains { $0.contains("if we found 8 on our calculator") })
    // A piece the left one does not run on into stays apart without a sign: the sentence ends, and
    // no raised note marker opens the piece beside it.
    let ended = mathLine("Not all numbers have a nice even square root. For example, we found it.", baseline: 670.8, width: 407)
    #expect(paragraphs(reflow(splitRowPage(right: plain, left: ended), crops: false)).contains("on"))

    // A piece that starts on an edge other lines share is a column, not the rest of a row.
    let column = TextLine(text: "= 5 and y = 6 for the second system", rect: CGRect(x: 496, y: 667.8, width: 90, height: 12), fontSize: 12)
    let columnLines = [mathLine("x = 1 and y = 2 in the table", x: 496, baseline: 740, width: 90),
                       mathLine("x = 3 and y = 4 in the table", x: 496, baseline: 725.4, width: 90)]
    let columns = paragraphs(reflow(splitRowPage(right: column, extra: columnLines), crops: false))
    #expect(!columns.contains { $0.contains("if we found 8 = 5 and y = 6") })

    // Pieces that do not read as prose on the paragraph's measure (a row of exercise answers)
    // stay apart.
    let answers = [TextLine(text: "1) √ 245 = 7", rect: CGRect(x: 85, y: 600, width: 60, height: 22), fontSize: 12),
                   TextLine(text: "2) √ 125 = 5", rect: CGRect(x: 140, y: 600, width: 60, height: 22), fontSize: 12)]
    let exercises = reflow(splitRowPage(right: radical, extra: answers), crops: false)
    #expect(!exercises.contains { $0.text.contains("245 = 7 2)") })
}

// MARK: - #71 paragraphs set off by added space

// USGS copper page 2: the COMEX paragraph, set a blank line below the Events section's last line,
// is its own paragraph, and every other paragraph on the page keeps its extent.
@Test func sourceUSGSCOMEXParagraphOpensUnderTightBoxSpacing() throws {
    let page = try SourceLayoutFixture.load("usgs-2").styledContent()
    let texts = paragraphs(reflow(page, crops: false))
    let events = try paragraph(texts, containing: "Events, Trends, and Issues:")
    let comex = try paragraph(texts, containing: "The COMEX copper price reached a record high")
    #expect(events != comex)
    #expect(events.hasSuffix("were expected to begin operating by yearend 2024."))
    #expect(comex.hasPrefix("The COMEX copper price reached a record high in May 2024"))
    #expect(comex.hasSuffix("and decreasing inflation in the United States."))
    // The table and prose around it are unchanged.
    #expect(try paragraph(texts, containing: "World Mine and Refinery Production").hasSuffix("industry association reports."))
    #expect(try paragraph(texts, containing: "Substitutes:").hasSuffix("Titanium and steel are used in heat exchangers."))
}

/// USGS geometry: 10-point type in 13.8-point rectangles at 11-point leading (a box gap of -2.8),
/// then a line set `gap` points below the previous one.
private func spacedPage(previous: String = "Kentucky and a new smelter in Georgia were expected to begin operating by yearend.",
                        next: String = "The COMEX copper price reached a record high in May and was projected to average",
                        gap: CGFloat = 8, indent: CGFloat = 0, size: CGFloat = 10, previousWidth: CGFloat = 480) -> PageContent {
    let height: CGFloat = 13.8, leading: CGFloat = -2.8
    var lines: [TextLine] = []
    var top: CGFloat = 700
    for (text, width) in [("In 2024, production decreased at a majority of copper mines in the United States, and", 510.0),
                          ("domestic mined copper output declined by an estimated 3% from that in 2023. At the", 500.0),
                          (previous, previousWidth)] {
        lines.append(TextLine(text: text, rect: CGRect(x: 45, y: top - height, width: width, height: height), fontSize: 10))
        top -= height + leading
    }
    top += leading
    lines.append(TextLine(text: next, rect: CGRect(x: 45 + indent, y: top - height - gap, width: 505, height: height), fontSize: size))
    lines.append(TextLine(text: "year 2024, an increase of 9% from the annual average price in 2023. Analysts said so.",
                          rect: CGRect(x: 45, y: top - 2 * height - gap - leading, width: 500, height: height), fontSize: 10))
    return PageContent(number: 2, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func syntheticBlankLineOpensAParagraphOnlyAfterASentence() {
    #expect(paragraphs(reflow(spacedPage(), crops: false)).count == 2)
    // A full-width previous line (a justified column) splits the same way: the right edge is not consulted.
    #expect(paragraphs(reflow(spacedPage(previousWidth: 510), crops: false)).count == 2)
    // At the paragraph's own leading, a sentence end followed by a capital is a wrapped line.
    #expect(paragraphs(reflow(spacedPage(gap: -2.8), crops: false)).count == 1)
    // Space short of half the body size over the leading is not a blank line.
    #expect(paragraphs(reflow(spacedPage(gap: 2), crops: false)).count == 1)
    // The previous line does not end a sentence.
    #expect(paragraphs(reflow(spacedPage(previous: "Kentucky and a new smelter in Georgia were expected to begin operating by"), crops: false)).count == 1)
    // The next line opens in lower case.
    #expect(paragraphs(reflow(spacedPage(next: "the COMEX copper price reached a record high in May and was projected to average"), crops: false)).count == 1)
    // Indented past the column's edge (not far enough for the column test): not this rule's evidence.
    #expect(paragraphs(reflow(spacedPage(indent: 6), crops: false)).count == 1)
}
