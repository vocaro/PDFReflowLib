import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Which lines become headings: size against the page and document body, image text excluded from
// the evidence, lowercase display lines, and recurring bold sub-heading labels (#186, #218).

private func headingBlocks(_ page: PageContent) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images,
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

@Test func fedTableTypographyDoesNotPromoteSurroundingProse() throws {
    let page = try SourceLayoutFixture.load("fed-46").content()
    let blocks = headingBlocks(page)
    #expect(headingTexts(blocks).isEmpty)
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return block.text }; return nil
    }
    #expect(paragraphs.contains { $0.contains("funds rate and other short-term interest rates is exercised primarily through the setting of") })
    #expect(paragraphs.contains { $0.contains("risks to the economic outlook were implemented") })
    #expect(blocks.filter { if case .image = $0.content { true } else { false } }.count >= 2)
}

@Test func neighboringFedProseAndSourceChapterTitlesKeepTheirSemantics() throws {
    let page = try SourceLayoutFixture.load("fed-45").content()
    #expect(headingTexts(headingBlocks(page)).isEmpty)
    for (name, title) in [("911-19", "WE HAVE"), ("911-65", "THE FOUNDATION")] {
        let blocks = headingBlocks(try SourceLayoutFixture.load(name).content())
        #expect(headingTexts(blocks).contains { $0.contains(title) })
    }
}

private func mixedTypographyPage(bodyLines: Int = 6) -> PageContent {
    var lines = (0..<12).map { i in
        TextLine(text: "Small table text repeated to dominate page typography and character counts.",
                 rect: CGRect(x: 40, y: 40 + i * 12, width: 500, height: 9), fontSize: 8)
    }
    lines += (0..<bodyLines).map { i in
        TextLine(text: "Ordinary body prose remains a paragraph outside the preserved table region.",
                 rect: CGRect(x: 40, y: 600 - i * 16, width: 400, height: 12), fontSize: 10)
    }
    lines.append(TextLine(text: "A legitimate heading", rect: CGRect(x: 40, y: 670, width: 250, height: 18), fontSize: 16))
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800),
                       lines: lines, graphics: [CGRect(x: 30, y: 30, width: 530, height: 170)])
}

@Test func imageTextCannotSetHeadingThresholdButRealHeadingSurvives() {
    let blocks = headingBlocks(mixedTypographyPage())
    #expect(headingTexts(blocks) == ["A legitimate heading"])
    #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains("Ordinary body prose") } else { false } })
}

@Test func imageBesideShortTitleDoesNotEraseTitleEvidence() {
    #expect(headingTexts(headingBlocks(mixedTypographyPage(bodyLines: 0))) == ["A legitimate heading"])
}

@Test func noPreservedRegionsKeepExistingHeadingEvidence() {
    var page = mixedTypographyPage()
    page.graphics = []
    // Without preservation the 8-point material remains reflowable body text.
    #expect(headingTexts(headingBlocks(page)).contains("A legitimate heading"))
}

@Test func modestSourceSectionHeadingsSurviveSmallTableText() throws {
    let titles = [(32, "How the FOMC Determines the Appropriate Stance of Monetary Policy"),
                  (54, "Asset Valuations and Risk Appetite"), (77, "Examination Report"),
                  (103, "Establishing and Maintaining a Reliable U.S. Currency"),
                  (109, "Expedited Funds Availability Act"), (123, "Interagency Initiatives")]
    for (number, title) in titles {
        let blocks = headingBlocks(try SourceLayoutFixture.load("fed-\(number)").content())
        #expect(headingTexts(blocks).contains(title))
    }
}

@Test func graphicDominatedFedPagesRetainBodyAsParagraphs() throws {
    let phrases = [(13, "Despite the need for coordination and consistency"),
                   (54, "These vulnerability assessments inform internal"),
                   (75, "By statute, state member banks must be examined"),
                   (77, "BHCs and SLHCs with less than $100 billion"),
                   (103, "Although the issuance of paper money"),
                   (109, "During the last two decades, Congress has directed")]
    for (number, phrase) in phrases {
        let blocks = headingBlocks(try SourceLayoutFixture.load("fed-\(number)").content())
        #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains(phrase) } else { false } })
        #expect(!headingTexts(blocks).contains { $0.contains(phrase) })
    }
}

private let usdaSHA256 = "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761"

/// The real page, with each line's actual bold/italic runs restored from the fixture's attributed
/// text (`fixture.content()` alone carries plain, unstyled text; `LabelStyle` needs the real bold
/// run to tell "Fighting Filth Flies" apart from the body text around it), following the same
/// pattern as `PreformattedStyleTests.styledSourcePage`.
private func usdaPage9() throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("usda-9")
    #expect(fixture.sourceSHA256 == usdaSHA256)
    #expect(fixture.page == 9)
    var page = fixture.content()
    for i in page.lines.indices {
        // The capture tool's line-selection text can carry a trailing space the plain `lines`
        // entry for the same line does not (PDFKit's `selectionsByLine` versus `NativeTextReader`),
        // so match with both trimmed rather than requiring an exact match.
        if let source = fixture.attributedLines.first(where: {
            $0.text.trimmingCharacters(in: .whitespaces) == page.lines[i].text.trimmingCharacters(in: .whitespaces)
        }) {
            let line = page.lines[i]
            page.lines[i] = TextLine(content: NativeTextReader.inlineText(from: source.attributedString()),
                rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
        }
    }
    return page
}

private func labelBlocks(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings,
                                      labelStyles: labelStyles)
}


// MARK: - The real page's geometry

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func fightingFilthFliesIsBoldAndBelowBody() throws {
    let page = try usdaPage9()
    let title = try #require(page.lines.first { $0.text == "Fighting Filth Flies" })
    let body = LayoutReconstructor.bodySize(page.lines)
    #expect(title.fontSize < body * 0.95, "\(title.fontSize) vs body \(body)")
    #expect(LayoutReconstructor.LabelStyle(title, body: body).bold)
    // A photograph (no thin rule) stands between the title and its paragraph.
    let figure = try #require(page.graphics.first { $0.minY > 590 && $0.minY < 610 })
    #expect(!LayoutReconstructor.isThinRule(figure))
}

// MARK: - labelEvidence and labelStyles

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func labelEvidenceRecordsTheTitleAsABoldSubheadingCandidate() throws {
    let page = try usdaPage9()
    let body = LayoutReconstructor.bodySize(page.lines)
    let title = try #require(page.lines.first { $0.text == "Fighting Filth Flies" })
    let evidence = LayoutReconstructor.labelEvidence(on: page)
    #expect(evidence.contains(LayoutReconstructor.LabelStyle(title, body: body)), "\(evidence)")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func labelStylesKeepsOnlyStylesRecurringOnAtLeastThreePages() {
    let style = LayoutReconstructor.LabelStyle(
        TextLine(text: "Some Bold Title", rect: CGRect(x: 0, y: 0, width: 100, height: 12), fontSize: 9), body: 10.5)
    #expect(LayoutReconstructor.labelStyles(from: [style: 2]).isEmpty)
    #expect(LayoutReconstructor.labelStyles(from: [style: 3]) == [style])
}

// MARK: - The end-to-end promotion on the real page

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func withDocumentWideEvidenceTheTitleBecomesAHeadingOnTheRealPage() throws {
    // Page 9 sets three columns that interleave in reading order (a separate, pre-existing gap
    // tracked as #153 and out of #218's scope: `corpus/manifest.json`'s knownFidelityIssues for
    // this case), so the block right after this heading in the converted output is not always its
    // own paragraph's opening line — `opens(beneath:)`/`pastFigure` decide only whether "Fighting
    // Filth Flies" is classified as a heading at all, which the dedicated `sectionLabels` and
    // synthetic `pastFigure` tests above check directly against this exact adjacency. This test
    // checks the classification end to end, through `labelBlocks(page:...)` itself, on the real page.
    let page = try usdaPage9()
    let body = LayoutReconstructor.bodySize(page.lines)
    let title = try #require(page.lines.first { $0.text == "Fighting Filth Flies" })
    let styles: Set<LayoutReconstructor.LabelStyle> = [LayoutReconstructor.LabelStyle(title, body: body)]
    let found = labelBlocks(page, labelStyles: styles)
    #expect(headingTexts(found) == ["Fighting Filth Flies"], "\(headingTexts(found))")
    // The paragraph it opens is still present in the output, not lost or merged away.
    #expect(found.contains { $0.text.hasPrefix("Nonbiting flies that shuttle between filth") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func withoutDocumentWideEvidenceTheSameTitleStaysAParagraph() throws {
    // Control: the pre-#218 behavior (and the style-consistency gate's purpose) — a bold,
    // body-adjacent line with no corroborating style elsewhere in the book is not promoted, so
    // its own paragraph's opening line runs into it instead.
    let page = try usdaPage9()
    let found = labelBlocks(page, labelStyles: [])
    #expect(!headingTexts(found).contains("Fighting Filth Flies"), "\(headingTexts(found))")
}

// MARK: - opens(beneath:)/pastFigure edge cases (synthetic)

private let bodySize: CGFloat = 10.5

private let boldStyleLine = TextLine(content: InlineText(elements: [.text("Sidebar Title", .bold)]),
    rect: CGRect(x: 72, y: 700, width: 90, height: 12), fontSize: 9)

private func syntheticStyles() -> Set<LayoutReconstructor.LabelStyle> {
    [LayoutReconstructor.LabelStyle(boldStyleLine, body: bodySize)]
}

/// One evidence "paragraph group" `firstLineIndentRun` can read: three flush lines ending a
/// paragraph, an indented opening line directly beneath (touching, so the gap is zero), and three
/// flush continuation lines directly beneath that. Lines stack at a 13-pt pitch equal to their own
/// height, so every gap in the group is exactly zero — comfortably inside the leading `pastFigure`
/// and `firstLineIndentRun` both tolerate.
private func paragraphGroup(topY: CGFloat, indent: CGFloat) -> [TextLine] {
    var y = topY
    var lines: [TextLine] = []
    for row in 0..<3 {
        lines.append(TextLine(text: "Flush line \(row) ending a paragraph.",
            rect: CGRect(x: 72, y: y, width: 140, height: 13), fontSize: bodySize))
        y -= 13
    }
    lines.append(TextLine(text: "Indented opening line of the next paragraph.",
        rect: CGRect(x: 72 + indent, y: y, width: 130, height: 13), fontSize: bodySize))
    y -= 13
    for row in 0..<3 {
        lines.append(TextLine(text: "Flush continuation line \(row).",
            rect: CGRect(x: 72, y: y, width: 140, height: 13), fontSize: bodySize))
        y -= 13
    }
    return lines
}

/// A page with a bold title near the top, a figure beneath it, then an indented paragraph beneath
/// the figure — the shape `pastFigure` reads, with the caller free to omit or move the figure. Two
/// ordinary paragraph groups elsewhere on the page establish the page's first-line-indent pattern
/// (`firstLineIndentRun` needs at least two such steps; the title's own interrupted paragraph,
/// opening right after a caption rather than after an ordinary flush line, supplies none itself).
private func pastFigurePage(figure: CGRect?, openingIndent: CGFloat = 10) -> PageContent {
    var lines = [boldStyleLine]
    lines += paragraphGroup(topY: 500, indent: openingIndent)
    lines += paragraphGroup(topY: 300, indent: openingIndent)
    // A small caption sits directly under the figure; the paragraph the title should open opens
    // beneath the caption, on the page's own first-line indent.
    lines.append(TextLine(text: "A small caption under the photo.",
        rect: CGRect(x: 72, y: 592, width: 120, height: 9), fontSize: 8))
    lines.append(TextLine(text: "The paragraph the title heads opens here on the page's indent.",
        rect: CGRect(x: 72 + openingIndent, y: 578, width: 140, height: 13), fontSize: bodySize))
    for row in 0..<3 {
        lines.append(TextLine(text: "Ordinary continuation line \(row) of the title's own paragraph.",
            rect: CGRect(x: 72, y: 565 - CGFloat(row) * 13, width: 140, height: 13), fontSize: bodySize))
    }
    return PageContent(number: 9, bounds: CGRect(x: 0, y: 0, width: 300, height: 792), lines: lines,
        graphics: figure.map { [$0] } ?? [])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func aTitleReadsPastAFigureToTheParagraphBeneathItsCaption() {
    // The figure spans the title's column, stands close beneath the title, and stops short enough
    // of the caption/opening line beneath it that `pastFigure` can find them.
    let figure = CGRect(x: 60, y: 608, width: 160, height: 88)
    let page = pastFigurePage(figure: figure)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels == [boldStyleLine])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func withNoFigureTheSameTitleIsNotPromoted() {
    // Without a figure between the title and the (far-away) paragraph, neither the direct nor the
    // past-figure path finds an opening, so the title stays a plain line.
    let page = pastFigurePage(figure: nil)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func aThinRuleBeneathTheTitleIsNeverMistakenForAFigure() {
    // A one-point underline the width of a rule, not a photograph: `isThinRule` excludes it from
    // `pastFigure`'s figure search.
    let rule = CGRect(x: 60, y: 690, width: 160, height: 1)
    #expect(LayoutReconstructor.isThinRule(rule))
    let page = pastFigurePage(figure: rule)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func aCaptionLineIsNeverPromotedAsATitleOverItsOwnFigure() {
    // A line that itself reads as a figure caption (`isCaption`) is excluded from `pastFigure`
    // even when it otherwise has every other mark of a bold sub-heading.
    let caption = TextLine(content: InlineText(elements: [.text("Figure 3. A caption, not a title", .bold)]),
        rect: CGRect(x: 72, y: 700, width: 150, height: 12), fontSize: 9)
    var page = pastFigurePage(figure: CGRect(x: 60, y: 608, width: 160, height: 88))
    page.lines[0] = caption
    let style = LayoutReconstructor.LabelStyle(caption, body: bodySize)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: [style])
    #expect(labels.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func anOpeningLineFarBelowTheCaptionIsNotTheTitlesParagraph() {
    // The figure is present, but the first heading-size line beneath its caption stands more than
    // four bodies below the caption's own top: too far to be this title's opening, so `pastFigure`
    // returns nil and the title is not promoted.
    var lines = [boldStyleLine]
    for row in 0..<3 {
        lines.append(TextLine(text: "Ordinary column prose line \(row) of the paragraph above.",
            rect: CGRect(x: 72, y: 500 - CGFloat(row) * 13, width: 140, height: 13), fontSize: bodySize))
    }
    lines.append(TextLine(text: "First indented line opens the paragraph above.",
        rect: CGRect(x: 82, y: 461, width: 130, height: 13), fontSize: bodySize))
    lines.append(TextLine(text: "A caption under the photo.", rect: CGRect(x: 72, y: 592, width: 120, height: 9), fontSize: 8))
    // Far below the caption (over four bodies: 4 * 10.5 = 42 points beneath the caption's own top).
    lines.append(TextLine(text: "The opening line stands too far below to be this title's paragraph.",
        rect: CGRect(x: 82, y: 530, width: 140, height: 13), fontSize: bodySize))
    let page = PageContent(number: 9, bounds: CGRect(x: 0, y: 0, width: 300, height: 792), lines: lines,
        graphics: [CGRect(x: 60, y: 608, width: 160, height: 88)])
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels.isEmpty)
}

// MARK: - firstLineIndentRun's own boundary

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func aSingleIndentStepIsNotEnoughEvidenceOfAFirstLineIndent() {
    // Only one paragraph on the whole page opens on the candidate indent: not the two the branch's
    // own evidence requires, so a body-adjacent title below body size (needing `onIndent`) is not
    // promoted on that indent alone.
    var lines = [boldStyleLine]
    for row in 0..<3 {
        lines.append(TextLine(text: "Ordinary column prose line \(row) of the only paragraph.",
            rect: CGRect(x: 72, y: 690 - CGFloat(row) * 13, width: 140, height: 13), fontSize: bodySize))
    }
    lines.append(TextLine(text: "The single indented opening line here.",
        rect: CGRect(x: 82, y: 651, width: 130, height: 13), fontSize: bodySize))
    for row in 0..<3 {
        lines.append(TextLine(text: "Ordinary continuation line \(row) of the same paragraph.",
            rect: CGRect(x: 72, y: 638 - CGFloat(row) * 13, width: 140, height: 13), fontSize: bodySize))
    }
    #expect(!LayoutReconstructor.firstLineIndentRun(in: lines, step: 10, size: bodySize))
}

// MARK: - The style-consistency gate guards ordinary bold prose

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/218")) func aOneOffBoldRunInsideProseIsNotPromotedWithoutRecurringEvidence() {
    // A short bold lead-in sits close above its own paragraph's continuation (within clearance) on
    // a page with no other evidence of that bold style: the "above" clearance rejection and the
    // missing style evidence both withhold it, matching the corpus-wide risk #218 flags for a
    // function that runs on every page.
    let lead = TextLine(content: InlineText(elements: [.text("A Bold Lead-In", .bold)]),
        rect: CGRect(x: 72, y: 600, width: 90, height: 12), fontSize: 9)
    var lines = [lead]
    for row in 0..<3 {
        lines.append(TextLine(text: "Ordinary prose line \(row) right above the lead-in.",
            rect: CGRect(x: 72, y: 616 - CGFloat(row) * 13, width: 140, height: 13), fontSize: bodySize))
    }
    for row in 0..<3 {
        lines.append(TextLine(text: "Ordinary prose line \(row) right beneath the lead-in.",
            rect: CGRect(x: 72, y: 588 - CGFloat(row) * 13, width: 140, height: 13), fontSize: bodySize))
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 300, height: 792), lines: lines, graphics: [])
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: [])
    #expect(labels.isEmpty)
}

private func floorBlocks(_ page: PageContent, vocabulary: Set<String> = [], documentBody: CGFloat? = nil) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: vocabulary,
        warnings: &warnings, documentBody: documentBody)
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

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func aBareBackCoverSetsNoHeadingUnderTheDocumentsBody() {
    let page = backCoverLike()
    let found = floorBlocks(page, documentBody: 10.5)
    #expect(headingTexts(found).isEmpty, "\(headingTexts(found))")
    let texts = paragraphTexts(found)
    for phrase in ["5601 Sunnyside Ave.", "Official Business", "Visit us at ars.usda.gov/ar"] {
        #expect(texts.contains { $0.contains(phrase) }, "\(phrase) in \(texts)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func withoutADocumentBodyTheSamePageReadsItsLinesAsHeadings() {
    // Control: measured only against the page's own bare estimate, as before this fix, several of
    // these lines cross the page-local threshold and read as headings.
    let found = headingTexts(floorBlocks(backCoverLike()))
    #expect(found.contains("Official Business") && found.contains("5601 Sunnyside Ave."), "\(found)")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func theDocumentsBodyDoesNotLowerAPageThatStatesItsOwn() {
    // A page of 9-point prose in a document whose body is 12 points: its own 11.5-point section
    // title stays a heading, and the document's body changes nothing because this page establishes
    // its own body (at least 3 lines and 200 characters at one size).
    var lines = [TextLine(text: "Methods of Evaluation", rect: CGRect(x: 72, y: 700, width: 220, height: 14), fontSize: 11.5)]
    for row in 0..<8 {
        lines.append(TextLine(text: "Ordinary prose of the section set in the page's own small type, line \(row).",
                              rect: CGRect(x: 72, y: 680 - CGFloat(row) * 11, width: 400, height: 11), fontSize: 9))
    }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    #expect(headingTexts(floorBlocks(page, documentBody: 12)) == ["Methods of Evaluation"])
    #expect(LayoutReconstructor.documentHeadingFloor(lines, documentBody: 12) == 0)
    // Control: the same page's first two lines alone establish no body, so the floor applies.
    #expect(LayoutReconstructor.documentHeadingFloor(Array(lines.prefix(2)), documentBody: 12) == 12 * 1.1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func aLowercaseLineAloneOnACoverHeadsNothing() {
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
    let found = floorBlocks(page)
    let headingTexts = headingTexts(found)
    #expect(headingTexts == ["Keeping Our", "Troops Safe", "From Insects"], "\(headingTexts)")
    #expect(!headingTexts.contains { $0.contains("pages 2, 4-14") }, "\(headingTexts)")
    #expect(paragraphTexts(found).contains { $0.contains("pages 2, 4-14") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func aLowercaseLineStackedInATitleKeepsItsReading() {
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
    let found = headingTexts(floorBlocks(page))
    #expect(found == ["The Role of", "the Federal Reserve", "Monetary Policy"], "\(found)")
    // Control: verified directly, since this is the specific relation the exclusion rule tests.
    #expect(LayoutReconstructor.stacksUnderHeading(lines[1], after: lines[0]))
}

// MARK: - Word breaks the lexicon decides

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func theDocumentFloorTakesEffectAtExactlyOneTenthOverNotBeforeIt() {
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
    #expect(headingTexts(floorBlocks(page(candidateSize: 11), documentBody: 10)) == ["Boundary Heading Line"])
    #expect(headingTexts(floorBlocks(page(candidateSize: 10.9), documentBody: 10)).isEmpty)
    #expect(paragraphTexts(floorBlocks(page(candidateSize: 10.9), documentBody: 10)).contains { $0.contains("Boundary Heading Line") })
}

// MARK: - The document-body floor beside #7's recognized-heading gate

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func aRecognizedLineThatClearsTheDocumentFloorButFailsTheWordTestIsStillNoHeading() {
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
    #expect(headingTexts(floorBlocks(wordyPage, documentBody: 10)) == ["Boundary Heading Line"])
    // The recognized noise line clears the same floor in size alone, but reads as no words.
    #expect(!EnglishText.readsAsWords(noise.text))
    #expect(headingTexts(floorBlocks(page, documentBody: 10)).isEmpty)
    #expect(paragraphTexts(floorBlocks(page, documentBody: 10)).contains { $0.contains("48213") })
}

@Test(arguments: [579, 580, 584, 585])
func notesRunningHeadsReadAsHeadingsOnTheirOwnPage(number: Int) throws {
    // #10. A notes page sets its body at 7 pt under a 9.5 pt running head, so the head clears
    // the page's own heading threshold and reaches the reader as an `h2` — navigation, not just
    // stray text. Page-local typography cannot tell it from a title; only the margin slot the
    // whole book keeps can, which is why the repair belongs in furniture detection.
    let page = try SourceLayoutFixture.load("911-\(number)").content()
    let head = try #require(page.lines.max { $0.rect.midY < $1.rect.midY })
    #expect(head.text.uppercased().contains("NOTES TO CHAPTER"))
    let typography = PageTypography(page: page)
    #expect(typography.body < head.fontSize)
    #expect(head.fontSize >= typography.headingThreshold)
    #expect(headingTexts(headingBlocks(page)).contains { $0.contains("NOTES TO CHAPTER") })
    // With the rest of the book present, the line never reaches classification at all.
    var pages = try ([19] + Array(20...26) + Array(65...71) + Array(471...476) + Array(579...585))
        .map { try SourceLayoutFixture.load("911-\($0)").content() }
    _ = LayoutReconstructor.stripFurniture(&pages)
    let stripped = try #require(pages.first { $0.number == number })
    #expect(!stripped.lines.contains { $0.text == head.text })
    #expect(!headingTexts(headingBlocks(stripped)).contains { $0.contains("NOTES TO CHAPTER") })
}

// A chapter opener supplies too little prose to establish a body. A long display title must
// not become its own body merely by carrying more characters than the running head (#296).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/296"), arguments: [33, 80, 139, 384, 526, 815, 1710])
func sparseNoaaChapterTitlesUseTheDocumentBody(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("noaa-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    let page = fixture.content()
    let runningHead = try #require(page.lines.first { $0.fontSize == 12 })
    let titles = page.lines.filter { $0.fontSize > runningHead.fontSize }.map(\.text)
    #expect(!titles.isEmpty)
    let blocks = floorBlocks(page, documentBody: 9)
    #expect(headingTexts(blocks) == titles)
    #expect(paragraphTexts(blocks) == [runningHead.text])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/296"))
func sparseTitleClassificationDoesNotDependOnRelativeTextLength() {
    for title in ["Title", "A Much Longer Title About the Changing World and Its Inhabitants"] {
        let lines = [
            TextLine(text: "Chapter Seven", rect: CGRect(x: 40, y: 700, width: 140, height: 16), fontSize: 12),
            TextLine(text: title, rect: CGRect(x: 40, y: 668, width: 550, height: 32), fontSize: 24),
        ]
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 700, height: 800), lines: lines, graphics: [])
        for documentBody: CGFloat in [8, 9, 10, 11] {
            let blocks = floorBlocks(page, documentBody: documentBody)
            #expect(headingTexts(blocks) == [title])
            #expect(paragraphTexts(blocks) == ["Chapter Seven"])
        }
        // With no document evidence, retain the page-local decision rather than assuming that
        // every sparse page is a title page.
        if title.count > "Chapter Seven".count {
            #expect(headingTexts(floorBlocks(page)).isEmpty)
        }
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/296"))
func establishedLargePrintProseKeepsItsOwnHeadingThreshold() {
    let prose = "Large print prose establishes its own body on this page even in a book with smaller ordinary text."
    let lines = (0..<4).map { row in
        TextLine(text: prose, rect: CGRect(x: 40, y: 640 - row * 32, width: 600, height: 30), fontSize: 24)
    } + [TextLine(text: "Large Print Heading", rect: CGRect(x: 40, y: 690, width: 350, height: 40), fontSize: 32)]
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 700, height: 800), lines: lines, graphics: [])
    let typography = PageTypography(pageLines: lines, reflowableLines: lines, documentBody: 11)
    #expect(typography.establishedBody == 24)
    #expect(typography.headingThreshold == 30)
    let blocks = floorBlocks(page, documentBody: 11)
    #expect(headingTexts(blocks) == ["Large Print Heading"])
    #expect(paragraphTexts(blocks).joined(separator: " ") == Array(repeating: prose, count: 4).joined(separator: " "))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/296"))
func repeatedCoverLabelsDoNotBecomeSparseDisplayTitles() throws {
    let fixture = try SourceLayoutFixture.load("dga-detached-cover")
    #expect(fixture.sourceSHA256 == "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472")
    let page = fixture.content()
    let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
    #expect(typography.establishedBody == nil)
    #expect(typography.body == 18)
    #expect(typography.headingThreshold == 22.5)
    let headings = page.lines.filter {
        LayoutReconstructor.isTitleSized($0, in: page.lines, typography: typography, judgesTitleWords: false)
    }.map(\.text)
    #expect(headings == ["Dietary", "Guidelines For Americans"])
    #expect(!headings.contains { $0.contains("Protein") || $0.contains("Vegetables") || $0.contains("Grains") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/296"))
func sparseFallbackDoesNotPromoteBylinesOrPublicationIdentifiers() throws {
    for name in ["earthdata-sparse-1", "faa-sparse-1"] {
        let page = try SourceLayoutFixture.load(name).content()
        let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
        let headings = page.lines.filter {
            LayoutReconstructor.isTitleSized($0, in: page.lines, typography: typography, judgesTitleWords: false)
        }.map(\.text)
        if name.hasPrefix("earthdata") {
            #expect(headings == ["Earthdata Cloud", "Analytics Project"])
        } else { #expect(headings.isEmpty) }
    }
    for name in ["earthdata-sparse-2", "earthdata-sparse-3", "earthdata-sparse-6", "arabic-sparse-1"] {
        let page = try SourceLayoutFixture.load(name).content()
        let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
        let headings = page.lines.filter {
            LayoutReconstructor.isTitleSized($0, in: page.lines, typography: typography, judgesTitleWords: false)
        }.map(\.text)
        #expect(!headings.isEmpty)
        for title in page.lines.filter({ $0.fontSize >= 30 }).map(\.text) {
            #expect(headings.contains(title))
        }
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/296"))
func sparseRecognizedProseDoesNotBorrowNativeTitleEvidence() throws {
    let capture = try SourceRecognitionFixture.load("census-sparse-7")
    let reading = capture.reading()
    // Fresh OCR is host-variable: this capture finds a different subset than the full-book
    // regression. Replay two actual source lines to pin its sparse, mixed-height condition.
    // The tall line is ordinary explanatory prose below an equation, not a printed heading.
    let tall = try #require(reading.lines.first { $0.text.hasPrefix("where wi,") })
    let small = try #require(reading.lines.first { $0.text == "1o = min" })
    // Pin the observed continuation's text with a minimal synthetic OCR-height contrast as
    // well. These are test geometry, not a claim that Vision repeats one full-book reading.
    let continuation = TextLine(text: "[16]) in that it uses Dijkstra's shortest augmenting path for many computations",
        rect: CGRect(x: 50, y: 500, width: 450, height: 18), fontSize: 14)
    let tiny = TextLine(text: "x = 1", rect: CGRect(x: 50, y: 540, width: 40, height: 10), fontSize: 9)
    for lines in [[tall, small], [continuation, tiny]] {
        let native = PageTypography(pageLines: lines, reflowableLines: lines, documentBody: 8)
        #expect(native.headingThreshold < lines[0].fontSize)
        for synthetic in [false, true] {
            var page = PageContent(number: 7, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                                   lines: lines, graphics: [])
            page.recognized = !synthetic
            page.hasSyntheticTextStyle = synthetic
            let typography = PageTypography(pageLines: lines, reflowableLines: lines, documentBody: 8,
                                           nativeSizeEvidence: !page.recognized && !page.hasSyntheticTextStyle)
            #expect(typography.headingThreshold > lines[0].fontSize)
            #expect(headingTexts(floorBlocks(page, documentBody: 8)).isEmpty)
        }
    }
}
