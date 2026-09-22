import CoreGraphics
import Testing
@testable import PDFReflowLib

/// An item the page broke mid-word keeps the rest of its word, whichever kind of marker opened it
/// (#245, #266).
///
/// #245 reads the item from `itemLine`, which only the `.listItem` branch of the assembler ever
/// set. A bullet, a minus or a hyphen opens that role; a number or a letter with a point opens
/// `.markedLine` instead, because the same token also ends a citation and only the page can say
/// which it is. A numbered item therefore reached the same preformatted block by the other branch
/// and left `itemLine` nil, so the rest of its broken word was never offered to it.
///
/// The source page here is a checksum-pinned extraction fixture, read against the printed page,
/// never converter output.
private let ourFlagSHA256 = "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8"

private func reconstruct(_ page: PageContent, vocabulary: Set<String> = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
}

private func reconstruct(_ lines: [TextLine], vocabulary: Set<String> = []) -> [ReflowBlock] {
    reconstruct(PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                            lines: lines, graphics: []), vocabulary: vocabulary)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { return $0.text } else { return nil } }
}

/// Lines stacked on one left edge at the page's own leading, each as wide as its own text needs.
private func stack(_ texts: [String], top: Double = 700, pitch: Double = 14,
                   x: Double = 60, size: Double = 12, gaps: [Int: Double] = [:]) -> [TextLine] {
    var y = top
    return texts.enumerated().map { index, text in
        if index > 0 { y -= gaps[index] ?? pitch }
        return TextLine(text: text, rect: CGRect(x: x, y: y, width: Double(text.count) * size * 0.5,
                                                 height: size), fontSize: size)
    }
}

/// Our Flag's folding instructions, page 26 of the PDF (printed folio 20). The page numbers seven
/// items and breaks the first at a printed hyphen: `1. Two persons, facing each other, hold the
/// flag waist high and horizon-` is followed by `tally between them.` one leading below it, in the
/// same 9-point type, on the same left edge.
///
/// This is the one word-split in the converted book that is not the soft hyphen PDFKit drops
/// (`measurements/box-placement-and-split-rows/record.md`, item 3), and the page draws U+002D for
/// it: Poppler and PDFKit both return the character.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/266"))
func aNumberedItemBrokenAtAHyphenKeepsTheRestOfItsWord() throws {
    let fixture = try SourceLayoutFixture.load("flag-26")
    #expect(fixture.sourceSHA256 == ourFlagSHA256)
    let page = fixture.content()

    // The page's own evidence, before any reconstruction. The item is a marked line — a number
    // and a point — and the line beneath it is the rest of its word.
    let item = try #require(page.lines.first { $0.text.hasPrefix("1. Two persons") })
    let rest = try #require(page.lines.first { $0.text == "tally between them." })
    #expect(item.text.hasSuffix("horizon-"))
    #expect(LayoutReconstructor.isMarked(item.text))
    let typography = PageTypography(page: page)
    #expect(LayoutReconstructor.markerColumn(of: item, in: page.lines, body: typography.body).setsAList)
    #expect(item.rect.minX == rest.rect.minX)
    #expect(item.hasSize(rest.fontSize))
    // One leading, well inside the bound #245 states: 3.1 points at 9-point type.
    #expect((item.rect.minY - rest.rect.maxY) < rest.fontSize * 0.8)

    // The book prints the joined word whole elsewhere — page 22 displays the flag `horizontally
    // or vertically against a wall` — so its own vocabulary decides the hyphen, as it does for a
    // break inside a paragraph.
    let blocks = reconstruct(page, vocabulary: ["horizontally"])
    let items = preformatted(blocks)
    #expect(items.contains("1. Two persons, facing each other, hold the flag waist high and horizontally between them."))
    #expect(!paragraphs(blocks).contains { $0.hasPrefix("tally") })
    #expect(!items.contains { $0.hasSuffix("horizon-") })
    // The other six items are untouched: only the broken one takes the line beneath it, and the
    // wraps that carry on in whole words stay where the page put them (#265 is that question).
    for marker in ["2. ", "3. ", "4. ", "5. ", "6. ", "7. "] {
        #expect(items.contains { $0.hasPrefix(marker) }, Comment(rawValue: marker))
    }
}

/// A numbered item that genuinely ends at a hyphenated word does not swallow the paragraph
/// beneath it. The page sets that paragraph a paragraph's space below the list rather than on the
/// column's own leading, which is the evidence #245 reads, so the two stay apart.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/266"))
func anItemEndingAtAHyphenatedWordKeepsAnUnrelatedParagraphOut() {
    let lines = stack([
        "1. Fold the flag lengthwise, keeping the blue field uppermost and square-",
        "2. Turn the outer point inward until the open edge is parallel.",
        "the remainder of this note stands on its own and belongs to nobody above it.",
    ], gaps: [2: 40])
    let blocks = reconstruct(lines)
    #expect(preformatted(blocks).contains { $0.hasSuffix("square-") })
    #expect(paragraphs(blocks) == ["the remainder of this note stands on its own and belongs to nobody above it."])
}

/// A new sentence is not the rest of a broken word. An item ending in a hyphen followed, on the
/// page's own leading, by a line that opens in uppercase keeps its own block.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/266"))
func anItemEndingInAHyphenDoesNotTakeACapitalizedLineBeneathIt() {
    let lines = stack([
        "1. Fold the flag lengthwise, keeping the blue field uppermost and square-",
        "Two persons hold the folded flag while a third inspects the seams.",
    ])
    let blocks = reconstruct(lines)
    #expect(preformatted(blocks).contains { $0.hasSuffix("square-") })
    #expect(paragraphs(blocks) == ["Two persons hold the folded flag while a third inspects the seams."])
}

/// What becomes of the hyphen is the book's own words to decide, exactly as inside a paragraph.
/// The 9/11 report's endnotes stand both kinds on one edge: `Febru-` is a word the page broke and
/// loses its hyphen, and `explosives-` is a printed compound and keeps it. The item join reads the
/// same vocabulary `HyphenRepair` reads, so an item that swallowed the line beneath it never
/// silently welds two words the book prints apart.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/266"))
func theItemJoinLeavesTheHyphenToTheBooksOwnWords() {
    let broken = reconstruct(stack([
        "4. Flight 11 pushed back from Gate 32. See the response to the Commission’s Febru-",
        "ary 3, 2004, requests, Mar. 15, 2004.",
    ]), vocabulary: ["february"])
    #expect(preformatted(broken) == [
        "4. Flight 11 pushed back from Gate 32. See the response to the Commission’s February 3, 2004, requests, Mar. 15, 2004.",
    ])

    // Neither the joined form nor the compound is a word this page's book prints, so the hyphen
    // stays and the two halves run on with no space of the library's own.
    let compound = reconstruct(stack([
        "1. The center did not analyze how an aircraft, hijacked or explosives-",
        "laden, might be used as a weapon by a suicide operative.",
    ]))
    #expect(preformatted(compound) == [
        "1. The center did not analyze how an aircraft, hijacked or explosives-laden, might be used as a weapon by a suicide operative.",
    ])
}

/// A list whose items each end in a hyphen does not fuse. Every item opens a marked line of its
/// own, which is not the prose the rest of a broken word arrives as, so no item takes the one
/// beneath it however close the page sets them.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/266"))
func alistWhoseItemsEachEndInAHyphenKeepsThemApart() {
    let texts = [
        "1. the first instruction ends in a printed compound such as half-",
        "2. the second instruction ends in a printed compound such as half-",
        "3. the third instruction ends in a printed compound such as half-",
        "4. the fourth instruction ends in a printed compound such as half-",
    ]
    let blocks = reconstruct(stack(texts))
    #expect(preformatted(blocks) == texts)
    #expect(paragraphs(blocks).isEmpty)
}
