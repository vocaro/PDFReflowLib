import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The leading a page states, and what it says about where one paragraph ends (#123).
//
// Wallace page 64 hangs an item's second line under a bullet and then sets that item's example a
// further half-line down. Measured as white between PDFKit's rectangles that extra space is
// 9.74 points against the 10.76 the paragraph rule allowed, so the example was swallowed by the
// item's own sentence. Measured against the leading the page's own prose is set on — 14.40 points,
// top to top — it is 1.51 times as far down, which is the page saying the two are not one
// paragraph.

private func line(_ text: String, x: CGFloat = 40, top: CGFloat, width: CGFloat = 300,
                  size: CGFloat = 10, height: CGFloat = 12) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: top - height, width: width, height: height), fontSize: size)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 600), lines: lines, graphics: [])
}

/// One page's reflowed text, with the crops the page's own graphics state and its own words as
/// the hyphen vocabulary, which is what the pipeline reconstructs a page with.
private func reflowedTexts(_ page: PageContent) -> [String] {
    var warnings: [ConversionWarning] = []
    let images = LayoutReconstructor.graphicsWithLabels(page, language: "en")
        .enumerated().map { ($0.element, "image-\($0.offset).png") }
    return LayoutReconstructor.blocks(page: page, images: images,
                                      vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                      warnings: &warnings)
        .filter(\.hasReflowedText).map(\.text)
}

/// The lines a page's crops leave in the prose: the lines whose leading the assembler reads.
private func reflowableLines(_ page: PageContent) -> [TextLine] {
    let crops = LayoutReconstructor.graphicsWithLabels(page, language: "en")
    return page.lines.filter { line in !crops.contains { LayoutReconstructor.takes($0, line) } }
}

private func rounded(_ value: CGFloat) -> CGFloat { (value * 100).rounded() / 100 }

/// Five lines of one paragraph, on a leading of 14 points.
private let paragraph: [TextLine] = (0..<5).map {
    line("The quick brown fox jumps over the lazy dog and runs on", top: 500 - CGFloat($0) * 14)
}

private let algebraDigest = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

// MARK: - The source page the defect was found on

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func wallaceSpacedExampleLinesAreTheirOwnBlocks() throws {
    let fixture = try SourceLayoutFixture.load("algebra-64")
    #expect(fixture.sourceSHA256 == algebraDigest)
    let content = fixture.content()

    // The page's own leading, read from the lines its crops leave in the prose, as the assembler
    // reads it. PDFKit's rectangles are no guide to it: the bulleted item's box is 20.46 points
    // tall where the line beneath it has 11.98, so the white between them is negative although
    // the page set them one line apart.
    #expect(LayoutReconstructor.statedLeading(reflowableLines(content)) == 14.5)
    let item = try #require(content.lines.first { $0.text.hasPrefix("• More than") })
    let rest = try #require(content.lines.first { $0.text == "writing the second part plus the first" })
    let example = try #require(content.lines.first { $0.text == "Three more than a number becomes x + 3" })
    #expect(rounded(item.rect.height) == 20.46 && rounded(rest.rect.height) == 11.98)
    #expect(item.rect.minY - rest.rect.maxY < 0)
    #expect(rounded(rest.rect.maxY - example.rect.maxY) == 21.72)
    // The white between the two rectangles is inside the bound this rule already allowed, which
    // is why the example was appended to the item's own sentence.
    #expect(rounded(rest.rect.minY - example.rect.maxY) == 9.74)
    #expect(9.74 < LayoutReconstructor.bodySize(content.lines) * 0.9)

    let texts = reflowedTexts(content)
    #expect(texts.contains("writing the second part plus the first"))
    #expect(texts.contains("Three more than a number becomes x + 3"))
    #expect(texts.contains("well, writing the second part minus the first"))
    #expect(texts.contains("Four less than a number becomes x− 4"))
    #expect(!texts.contains { $0.contains("the first Three more") || $0.contains("the first Four less") })
    // The page's own paragraph break between its two opening paragraphs is kept too.
    #expect(texts.contains { $0.hasPrefix("Word problems can be tricky.") && $0.hasSuffix("and parts problems.") })
    #expect(texts.contains("A few important phrases are described below that can give us clues for how to set up a problem."))
    // Control: a paragraph the page wraps at its own leading is still one paragraph.
    #expect(texts.contains("Objective: Solve number and geometry problems by creating and solving a linear equation."))
    #expect(texts.contains { $0.hasPrefix("Using these key phrases") && $0.hasSuffix("and solve.") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func aFurtherHalfLineEndsAParagraphAndOrdinaryLeadingDoesNot() {
    // A sixth line the page set 20 points below the fifth, where its own leading is 14. The white
    // between the two rectangles is 8 points, inside the 9 this rule allows at a ten-point body,
    // so only the page's own leading separates them.
    let spaced = line("An example the page set apart from the paragraph above", top: 500 - 4 * 14 - 20)
    let separated = page(paragraph + [spaced])
    #expect(LayoutReconstructor.statedLeading(separated.lines) == 14)
    #expect(paragraph[4].rect.minY - spaced.rect.maxY == 8)
    let texts = reflowedTexts(separated)
    #expect(texts.count == 2)
    #expect(texts.last == spaced.text)

    // Control: the same line on the page's own leading is the same paragraph.
    let onLeading = line(spaced.text, top: 500 - 5 * 14)
    let joined = reflowedTexts(page(paragraph + [onLeading]))
    #expect(joined.count == 1)
    #expect(joined.first?.hasSuffix(spaced.text) == true)
}

// MARK: - What a page must say before its leading decides anything

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func tooFewPairsStateNoLeadingAndTheParagraphRuleIsUnchanged() {
    // Three lines make two pairs, short of the four a page must show; five make four.
    let sparse = Array(paragraph.prefix(3))
    #expect(LayoutReconstructor.statedLeading(sparse) == nil)
    #expect(LayoutReconstructor.statedLeading(paragraph) == 14)

    // A page that states no leading judges the same spaced line by the gap alone, as before.
    let spaced = line("An example the page set apart from the paragraph above", top: 500 - 2 * 14 - 20)
    #expect(LayoutReconstructor.statedLeading(sparse + [spaced]) == nil)
    #expect(reflowedTexts(page(sparse + [spaced])).count == 1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func eachColumnStatesItsOwnLeadingAndTheGutterIsNeverMeasured() {
    // Two columns interleave down the page. The neighbour below a line is the one in its own
    // column, so four pairs of 12 points are counted and no pair crosses the gutter.
    let left = (0..<3).map { line("Left column line of prose", x: 40, top: 500 - CGFloat($0) * 12, width: 150) }
    let right = (0..<3).map { line("Right column line of prose", x: 220, top: 494 - CGFloat($0) * 12, width: 150) }
    #expect(LayoutReconstructor.statedLeading(left + right) == 12)
    // Neither column alone states one: two pairs each.
    #expect(LayoutReconstructor.statedLeading(left) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func linesSetAtDifferentSizesAreNotJudgedByTheirTops() {
    // Two lines of one size sit one ascent above their baselines, so their tops are a leading
    // apart. A line set at another size is not, and this rule says nothing about it.
    let spaced = line("An example the page set apart from the paragraph above", top: 500 - 4 * 14 - 20, size: 12)
    #expect(spaced.rect.maxY != paragraph[4].rect.maxY)
    #expect(paragraph[4].rect.minY - spaced.rect.maxY == 8)
    #expect(reflowedTexts(page(paragraph + [spaced])).count == 1)
    // The same line at the paragraph's own size is separated.
    #expect(reflowedTexts(page(paragraph + [line(spaced.text, top: spaced.rect.maxY)])).count == 2)
}

// MARK: - Positive controls from other books

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func otherBooksKeepTheirWrappedParagraphsWhole() throws {
    // Each control names a paragraph its source prints over several lines at that page's own
    // leading: the 9/11 report at 11.25 points, the Fed's report at 16, the FAA handbook at 12.5
    // and a Supreme Court opinion at 13.2. A rule that read ordinary leading as a separation
    // would break one of them.
    for (name, opening, ending) in [
        ("911-20", "The security checkpoints through which passengers", "under a contract with American Airlines."),
        ("fed-21", "Once the FOMC determines the appropriate stance of policy", "foreign central banks."),
        ("faa-91", "Pressure altitude is the height above a standard datum plane", "or above 18,000 feet."),
        ("loper-13", "A divided panel of the D. C. Circuit affirmed.", "Atlantic herring fishermen to pay for observers."),
    ] {
        let content = try SourceLayoutFixture.load(name).content()
        #expect(LayoutReconstructor.statedLeading(reflowableLines(content)) != nil, "\(name) states no leading")
        let texts = reflowedTexts(content)
        #expect(texts.contains { $0.contains(opening) && $0.contains(ending) },
                "\(name): the source's paragraph no longer reads whole from \(opening)")
    }
}

// MARK: - A bullet released from a formula crop

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func theBulletBesideWallacesFormulaReflowsAndOnlyTheFormulaIsPreserved() throws {
    let fixture = try SourceLayoutFixture.load("algebra-64")
    #expect(fixture.sourceSHA256 == algebraDigest)
    let content = fixture.content()
    let bullet = try #require(content.lines.first { $0.text.hasPrefix("• Is (or other forms of is") })
    let formula = try #require(content.lines.first { $0.text == "x is 5 becomes x =5" })
    let crops = LayoutReconstructor.graphicsWithLabels(content, language: "en")
    // The formula seeds a crop of its own. The bullet above it is the book's own prose, which no
    // crop admits, so the crop keeps its own extent rather than growing over the bullet (#255).
    let crop = try #require(crops.first { LayoutReconstructor.takes($0, formula) })
    #expect(!LayoutReconstructor.takes(crop, bullet))
    #expect(!crops.contains { LayoutReconstructor.takes($0, bullet) })
    #expect(crop.height < bullet.rect.maxY - formula.rect.minY)
    let texts = reflowedTexts(content)
    #expect(texts.contains { $0.hasPrefix("• Is (or other forms of is") })
    #expect(!texts.contains { $0.contains("x is 5 becomes") })
}
