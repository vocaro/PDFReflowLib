import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #218, the fifth and last #186 leftover left over from #217's scope: a sidebar title set well
// above its own body text, with a photograph between the title and the paragraph it introduces,
// stays a plain paragraph because the title-adjacency test that decides whether a styled line is a
// heading does not read past a figure to find the paragraph it opens.
//
// The coordination branch's fix (`3c794a3`) extends `opens(beneath:)` with `pastFigure(_:)`, but
// `opens(beneath:)` is itself part of an entirely separate sub-heading classification subsystem
// (`sectionLabels`, `LabelStyle`, `boxTitles`, built up across #43, #63, #73, #76, #90, #97, #100
// and #102) that does not exist on main at all: main has no heading tiers and classifies a line as
// a heading purely by size. This port adds only the bold, body-adjacent path that #218's own
// motivating page needs:
//
//   - `LabelStyle` reads main's existing `TextStyle` bold flag (no #217 font-resource dependency);
//   - `sectionLabels` recognizes a bold line at or near body size whose style recurs elsewhere in
//     the document (`labelStyles`, aggregated by `labelEvidence(on:)` across every page, mirroring
//     the pipeline's existing document-body pass);
//   - `opens(beneath:)`/`pastFigure(_:)` decide whether the paragraph beneath it (directly, or past
//     an intervening picture and caption) is the label's own text.
//
// Not ported: `boxTitles` (tinted sidebar boxes; main has no `page.tints` background-region
// extraction at all, a prerequisite this port does not add), italic labels (#97), two-line stacked
// titles (#102), hanging-entry titles (#134) and outline labels (#152) — #218's own case needs none
// of them, and porting any without a corpus document to validate it against would only add
// untested false-positive surface to a function that runs on every page of every conversion.
//
// usda-9-layout.json is a real, checksum-pinned capture of USDA ARS *Agricultural Research*,
// November/December 2012, page 9 (corpus/regressions.json case usda-ars-agresearch-2012-11),
// captured with tools/capture-layout-fixture.swift as documented in doc/regression-testing.md. Its
// "Fighting Filth Flies" sidebar title sits at the top of its column, nine-point Helvetica-Bold
// over a ten-and-a-half-point body (#159's below-body sub-heading case), with a photograph and its
// caption between the title and the paragraph ("Nonbiting flies that shuttle between filth...") it
// opens.

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

private func blocks(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings,
                                      labelStyles: labelStyles)
}


// MARK: - The real page's geometry

@Test func fightingFilthFliesIsBoldAndBelowBody() throws {
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

@Test func labelEvidenceRecordsTheTitleAsABoldSubheadingCandidate() throws {
    let page = try usdaPage9()
    let body = LayoutReconstructor.bodySize(page.lines)
    let title = try #require(page.lines.first { $0.text == "Fighting Filth Flies" })
    let evidence = LayoutReconstructor.labelEvidence(on: page)
    #expect(evidence.contains(LayoutReconstructor.LabelStyle(title, body: body)), "\(evidence)")
}

@Test func labelStylesKeepsOnlyStylesRecurringOnAtLeastThreePages() {
    let style = LayoutReconstructor.LabelStyle(
        TextLine(text: "Some Bold Title", rect: CGRect(x: 0, y: 0, width: 100, height: 12), fontSize: 9), body: 10.5)
    #expect(LayoutReconstructor.labelStyles(from: [style: 2]).isEmpty)
    #expect(LayoutReconstructor.labelStyles(from: [style: 3]) == [style])
}

// MARK: - The end-to-end promotion on the real page

@Test func withDocumentWideEvidenceTheTitleBecomesAHeadingOnTheRealPage() throws {
    // Page 9 sets three columns that interleave in reading order (a separate, pre-existing gap
    // tracked as #153 and out of #218's scope: `corpus/manifest.json`'s knownFidelityIssues for
    // this case), so the block right after this heading in the converted output is not always its
    // own paragraph's opening line — `opens(beneath:)`/`pastFigure` decide only whether "Fighting
    // Filth Flies" is classified as a heading at all, which the dedicated `sectionLabels` and
    // synthetic `pastFigure` tests above check directly against this exact adjacency. This test
    // checks the classification end to end, through `blocks(page:...)` itself, on the real page.
    let page = try usdaPage9()
    let body = LayoutReconstructor.bodySize(page.lines)
    let title = try #require(page.lines.first { $0.text == "Fighting Filth Flies" })
    let styles: Set<LayoutReconstructor.LabelStyle> = [LayoutReconstructor.LabelStyle(title, body: body)]
    let found = blocks(page, labelStyles: styles)
    #expect(headingTexts(found) == ["Fighting Filth Flies"], "\(headingTexts(found))")
    // The paragraph it opens is still present in the output, not lost or merged away.
    #expect(found.contains { $0.text.hasPrefix("Nonbiting flies that shuttle between filth") })
}

@Test func withoutDocumentWideEvidenceTheSameTitleStaysAParagraph() throws {
    // Control: the pre-#218 behavior (and the style-consistency gate's purpose) — a bold,
    // body-adjacent line with no corroborating style elsewhere in the book is not promoted, so
    // its own paragraph's opening line runs into it instead.
    let page = try usdaPage9()
    let found = blocks(page, labelStyles: [])
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

@Test func aTitleReadsPastAFigureToTheParagraphBeneathItsCaption() {
    // The figure spans the title's column, stands close beneath the title, and stops short enough
    // of the caption/opening line beneath it that `pastFigure` can find them.
    let figure = CGRect(x: 60, y: 608, width: 160, height: 88)
    let page = pastFigurePage(figure: figure)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels == [boldStyleLine])
}

@Test func withNoFigureTheSameTitleIsNotPromoted() {
    // Without a figure between the title and the (far-away) paragraph, neither the direct nor the
    // past-figure path finds an opening, so the title stays a plain line.
    let page = pastFigurePage(figure: nil)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels.isEmpty)
}

@Test func aThinRuleBeneathTheTitleIsNeverMistakenForAFigure() {
    // A one-point underline the width of a rule, not a photograph: `isThinRule` excludes it from
    // `pastFigure`'s figure search.
    let rule = CGRect(x: 60, y: 690, width: 160, height: 1)
    #expect(LayoutReconstructor.isThinRule(rule))
    let page = pastFigurePage(figure: rule)
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: bodySize,
        headingThreshold: bodySize * 1.25, page: page, styles: syntheticStyles())
    #expect(labels.isEmpty)
}

@Test func aCaptionLineIsNeverPromotedAsATitleOverItsOwnFigure() {
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

@Test func anOpeningLineFarBelowTheCaptionIsNotTheTitlesParagraph() {
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

@Test func aSingleIndentStepIsNotEnoughEvidenceOfAFirstLineIndent() {
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

@Test func aOneOffBoldRunInsideProseIsNotPromotedWithoutRecurringEvidence() {
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
