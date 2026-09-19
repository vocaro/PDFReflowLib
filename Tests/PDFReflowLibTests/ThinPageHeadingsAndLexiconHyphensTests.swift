import Foundation
import Testing
@testable import PDFReflowLib

// #186, ported: two of five upstream fixes, read against USDA ARS *Agricultural Research*,
// November/December 2012 (corpus/regressions.json case usda-ars-agresearch-2012-11):
//
// - the back cover's return address, "Official Business" and web line, and the cover's lowercase
//   cross-reference line "pages 2, 4-14", were headings: those pages set too little text to state
//   a body of their own, so a document-wide body floor is needed to hold their heading-size type
//   down to a paragraph;
// - "com-" + "panies" and "infec-" + "tions" kept their hyphen because the magazine prints neither
//   word whole; the system's English lexicon, not the book's own vocabulary, must decide the join.
//
// The other three upstream fixes (dingbat font reading, a letter-case glyph disagreement, and a
// subhead's text opening past a picture) are not ported: they depend on FontWeightReader's
// content-stream font/glyph scanning and a sub-heading label system, neither of which exists on
// main. These fixtures are synthetic (not captured from the source PDF) and exercise the two
// ported behaviors directly through LayoutReconstructor's public entry points.

private func blocks(_ page: PageContent, vocabulary: Set<String> = [], documentBody: CGFloat? = nil) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: vocabulary,
        warnings: &warnings, documentBody: documentBody)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

// MARK: - A document body floor for pages too bare to state their own

/// The back cover's shape: two lines of small 8-point boilerplate (permit line, web line — too few
/// lines to establish a body of their own even though their combined length outweighs the mailing
/// panel below) set the page's own naive estimate to 8, so the panel's ordinary 10-point address
/// lines clear the page-local heading threshold (8 * 1.25 = 10) and read as headings — unless a
/// document body around 10.5 raises the floor past them.
private func backCoverLike() -> PageContent {
    let lines = [
        TextLine(text: "Presorted Standard U.S. Postage Paid Permit Number 95 Beltsville Maryland",
                 rect: CGRect(x: 40, y: 760, width: 300, height: 10), fontSize: 8),
        TextLine(text: "This publication is available online at www.ars.usda.gov",
                 rect: CGRect(x: 40, y: 748, width: 300, height: 10), fontSize: 8),
        TextLine(text: "U.S. Department of Agriculture", rect: CGRect(x: 40, y: 726, width: 260, height: 13), fontSize: 10),
        TextLine(text: "5601 Sunnyside Ave.", rect: CGRect(x: 40, y: 712, width: 180, height: 13), fontSize: 10),
        TextLine(text: "Official Business", rect: CGRect(x: 40, y: 690, width: 150, height: 13), fontSize: 10),
        TextLine(text: "Visit us at ars.usda.gov/ar", rect: CGRect(x: 115, y: 45, width: 220, height: 13), fontSize: 10),
    ]
    return PageContent(number: 24, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func aBareBackCoverSetsNoHeadingUnderTheDocumentsBody() {
    let page = backCoverLike()
    let found = blocks(page, documentBody: 10.5)
    #expect(headings(found).isEmpty, "\(headings(found))")
    let texts = paragraphs(found)
    for phrase in ["5601 Sunnyside Ave.", "Official Business", "Visit us at ars.usda.gov/ar"] {
        #expect(texts.contains { $0.contains(phrase) }, "\(phrase) in \(texts)")
    }
}

@Test func withoutADocumentBodyTheSamePageReadsItsLinesAsHeadings() {
    // Control: measured only against the page's own bare estimate, as before this fix, several of
    // these lines cross the page-local threshold and read as headings.
    let found = headings(blocks(backCoverLike()))
    #expect(found.contains("Official Business") && found.contains("5601 Sunnyside Ave."), "\(found)")
}

@Test func theDocumentsBodyDoesNotLowerAPageThatStatesItsOwn() {
    // A page of 9-point prose in a document whose body is 12 points: its own 11.5-point section
    // title stays a heading, and the document's body changes nothing because this page establishes
    // its own body (at least 3 lines and 200 characters at one size).
    var lines = [TextLine(text: "Methods of Evaluation", rect: CGRect(x: 72, y: 700, width: 220, height: 14), fontSize: 11.5)]
    for row in 0..<8 {
        lines.append(TextLine(text: "Ordinary prose of the section set in the page's own small type, line \(row).",
                              rect: CGRect(x: 72, y: 680 - CGFloat(row) * 11, width: 400, height: 11), fontSize: 9))
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    #expect(headings(blocks(page, documentBody: 12)) == ["Methods of Evaluation"])
    #expect(LayoutReconstructor.documentHeadingFloor(lines, documentBody: 12) == 0)
    // Control: the same page's first two lines alone establish no body, so the floor applies.
    #expect(LayoutReconstructor.documentHeadingFloor(Array(lines.prefix(2)), documentBody: 12) == 12 * 1.1)
}

@Test func aLowercaseLineAloneOnACoverHeadsNothing() {
    // A title stacks three capitalized lines at 24 points above eight lines of ordinary 10-point
    // prose (which establish the page's own body, so this exercises the lowercase-standalone
    // exclusion on its own, independent of the document-body floor). Well clear of the title and
    // the prose, an isolated 24-point line opening in lowercase — like the cover's cross-reference
    // "pages 2, 4-14" — stands alone at heading size but heads nothing.
    var lines = [
        TextLine(text: "Keeping Our", rect: CGRect(x: 60, y: 760, width: 220, height: 28), fontSize: 24),
        TextLine(text: "Troops Safe", rect: CGRect(x: 60, y: 732, width: 220, height: 28), fontSize: 24),
        TextLine(text: "From Insects", rect: CGRect(x: 60, y: 704, width: 220, height: 28), fontSize: 24),
    ]
    lines += (0..<8).map { row in
        TextLine(text: "Ordinary prose of the cover blurb set in its body type, line number \(row) of eight.",
                 rect: CGRect(x: 60, y: 660 - CGFloat(row) * 13, width: 400, height: 13), fontSize: 10)
    }
    lines.append(TextLine(text: "pages 2, 4-14", rect: CGRect(x: 60, y: 420, width: 160, height: 24), fontSize: 24))
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    let found = blocks(page)
    let headingTexts = headings(found)
    #expect(headingTexts == ["Keeping Our", "Troops Safe", "From Insects"], "\(headingTexts)")
    #expect(!headingTexts.contains { $0.contains("pages 2, 4-14") }, "\(headingTexts)")
    #expect(paragraphs(found).contains { $0.contains("pages 2, 4-14") })
}

@Test func aLowercaseLineStackedInATitleKeepsItsReading() {
    // A two-line display title whose second line opens in lowercase is still read as a heading
    // (stacked directly beneath the first line at the same size, so stacksWithDisplay vouches for
    // it even though it opens lowercase), and a lone capitalized line of the same size elsewhere is
    // still a heading on its own. main keeps each source line as its own heading block (unrelated
    // to #186), so this checks that neither line is suppressed, not that they merge into one text.
    let lines = [
        TextLine(text: "The Role of", rect: CGRect(x: 72, y: 700, width: 200, height: 28), fontSize: 24),
        TextLine(text: "the Federal Reserve", rect: CGRect(x: 72, y: 672, width: 260, height: 28), fontSize: 24),
        TextLine(text: "Monetary Policy", rect: CGRect(x: 72, y: 400, width: 200, height: 28), fontSize: 24),
    ] + (0..<8).map { row in
        TextLine(text: "Ordinary prose of the chapter set in its body type, line number \(row) of eight.",
                 rect: CGRect(x: 72, y: 640 - CGFloat(row) * 13, width: 400, height: 13), fontSize: 10)
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    let found = headings(blocks(page))
    #expect(found == ["The Role of", "the Federal Reserve", "Monetary Policy"], "\(found)")
    // Control: verified directly, since this is the specific relation the exclusion rule tests.
    #expect(LayoutReconstructor.stacksUnderHeading(lines[1], after: lines[0]))
}

// MARK: - Word breaks the lexicon decides

@Test func anEnglishLexiconDecidesABreakTheBookCannot() throws {
    guard TextLayerPlausibility.lexiconContains("companies") != nil else { return }
    let english = HyphenContext(usesEnglishLexicon: true)
    for (left, right, joined) in [("commercial com-", "panies interested", "commercial companies interested"),
                                  ("a range of infec-", "tions in humans", "a range of infections in humans")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, hyphens: english, page: 6, warnings: &warnings) == joined)
        #expect(warnings.isEmpty)
        // Control: without the declared language the break stays undecided, hyphen kept and warned.
        var undecided: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: [], page: 6, warnings: &undecided) == left + right)
        #expect(undecided.map(\.code) == [.uncertainHyphen])
    }
}

@Test func theLexiconLeavesGenuineCompoundsAndShortHalves() throws {
    guard TextLayerPlausibility.lexiconContains("companies") != nil else { return }
    let english = HyphenContext(usesEnglishLexicon: true)
    // A compound whose halves are both words on their own (camera-man), a one-letter half
    // (e-mail), and a joined word the lexicon does not hold all keep the hyphen.
    for (left, right) in [("camera-", "man arrived"), ("e-", "mail it"), ("zorbu-", "latinex tonight")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, hyphens: english, page: 1, warnings: &warnings) == left + right,
                "\(left)\(right)")
    }
}

// MARK: - The document-body floor's own boundary

@Test func theDocumentFloorTakesEffectAtExactlyOneTenthOverNotBeforeIt() {
    // Two lines of small filler (too few to establish a body of their own) keep the page's own
    // threshold at max(8 * 1.25, 8 * 1.1) = 10; with documentBody 10, the floor is exactly 11.
    // The `>=` at the threshold comparison means a candidate AT 11 must become a heading and one
    // fractionally under must not, not just "comfortably above/below" cases.
    func page(candidateSize: CGFloat) -> PageContent {
        let lines = [
            TextLine(text: "Filler text line one for the page here.", rect: CGRect(x: 40, y: 700, width: 300, height: 10), fontSize: 8),
            TextLine(text: "Filler text line two for the page here.", rect: CGRect(x: 40, y: 688, width: 300, height: 10), fontSize: 8),
            TextLine(text: "Boundary Heading Line", rect: CGRect(x: 40, y: 600, width: 200, height: 14), fontSize: candidateSize),
        ]
        return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    }
    #expect(LayoutReconstructor.documentHeadingFloor(page(candidateSize: 11).lines, documentBody: 10) == 11)
    #expect(headings(blocks(page(candidateSize: 11), documentBody: 10)) == ["Boundary Heading Line"])
    #expect(headings(blocks(page(candidateSize: 10.9), documentBody: 10)).isEmpty)
    #expect(paragraphs(blocks(page(candidateSize: 10.9), documentBody: 10)).contains { $0.contains("Boundary Heading Line") })
}

// MARK: - The document-body floor beside #7's recognized-heading gate

@Test func aRecognizedLineThatClearsTheDocumentFloorButFailsTheWordTestIsStillNoHeading() {
    // A page too bare to state its own body (two lines of small filler, as above), recognized by
    // OCR (#7's `judgesTitleWords` gate applies), whose one heading-size line is not real words —
    // digits and symbols large enough to clear the document floor. Both gates independently
    // exclude it; this pins that the combination still does, not just either alone.
    var lines = [
        TextLine(text: "Filler text line one for the page here.", rect: CGRect(x: 40, y: 700, width: 300, height: 10), fontSize: 8),
        TextLine(text: "Filler text line two for the page here.", rect: CGRect(x: 40, y: 688, width: 300, height: 10), fontSize: 8),
    ]
    let noise = TextLine(text: "48213 // 00921 ::: 5", rect: CGRect(x: 40, y: 600, width: 200, height: 14), fontSize: 11)
    lines.append(noise)
    var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    page.recognized = true
    // Control: cleared floor (11 >= 11), reads as words, unrecognized page — a real heading.
    var wordyLines = lines; wordyLines[2] = TextLine(text: "Boundary Heading Line", rect: noise.rect, fontSize: 11)
    let wordyPage = PageContent(number: 1, bounds: page.bounds, lines: wordyLines, graphics: [])
    #expect(headings(blocks(wordyPage, documentBody: 10)) == ["Boundary Heading Line"])
    // The recognized noise line clears the same floor in size alone, but reads as no words.
    #expect(!TextLayerPlausibility.readsAsWords(noise.text))
    #expect(headings(blocks(page, documentBody: 10)).isEmpty)
    #expect(paragraphs(blocks(page, documentBody: 10)).contains { $0.contains("48213") })
}

@Test func aVocabularyFragmentFromTheOtherHalfOfTheSameBreakDoesNotBlockTheVouch() throws {
    // main's addVocabulary is page-local and has no notion of a line that opens with the second
    // half of a hyphen-broken word: reading "panies interested in..." on its own adds "panies" to
    // the document's vocabulary as if it were an independent whole word. lexiconVouches must not
    // let that fragment count as evidence that "panies" is a real standalone word, or it would
    // wrongly treat "com-panies" as two genuine words and keep the hyphen. The lexicon, not the
    // vocabulary, is what decides a half's standing.
    guard TextLayerPlausibility.lexiconContains("companies") != nil else { return }
    #expect(LayoutReconstructor.lexiconVouches(prefix: "com", suffix: "panies", usesEnglishLexicon: true))
}
