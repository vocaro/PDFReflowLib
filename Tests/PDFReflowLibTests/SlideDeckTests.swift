import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// A slide deck's titles, its diagram labels and its per-slide note (#165). Fixtures are native
// extraction from checksum-pinned sources; every expected phrase was read against the rendered
// slides, not converter output.
//
// `slides-19-overprints` is slide 19 captured with `--keep-overprints`, so it holds PDFKit's lines
// as they come, before extraction drops a line that only overprints another; `slides-19` is the
// same page as the pipeline sees it. `noaa-100` is a page of the one landscape book in the corpus.

private let slidesSHA256 = "f0a1ea3f5711228a9de2544fd1a94b05cfb8d9323fe3a4c253542f5a6ead5c94"
private let noaaSHA256 = "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf"

private func slide(_ name: String, styled: Bool = false) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == slidesSHA256)
    return styled ? fixture.styledContent() : fixture.content()
}

private func reconstruct(_ page: PageContent, slideDeck: Bool = true) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
                                      slideDeck: slideDeck)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private func levels(_ blocks: [ReflowBlock]) -> [(String, Int)] {
    blocks.compactMap { block in
        if case let .heading(_, text, level) = block.content { (text.text, level) } else { nil }
    }
}

// MARK: The slide's title

// Slide 3 sets `Over time, EOSDIS archive volumes` / `increase exponentially` at 32 points over a
// chart whose only extracted word is the 16-point `projected`. The title's own 55 characters
// outweigh that word, so the page's character-weighted body size is the title's own type and no
// line on the page reaches the heading threshold.
@Test func aSlideTitleIsAHeadingWhateverTheSlidesBodySizeSays() throws {
    let page = try slide("slides-3")
    #expect(LayoutReconstructor.bodySize(page.lines) == 32)
    let blocks = reconstruct(page)
    #expect(headings(blocks) == ["Over time, EOSDIS archive volumes increase exponentially"])
    // The chart's one word and the slide number, which furniture removal takes before the pipeline
    // reconstructs the page but this fixture still carries.
    #expect(paragraphs(blocks) == ["projected", "3"])
    // Negative control: outside a deck the same page reads as two paragraphs and no heading.
    let book = reconstruct(page, slideDeck: false)
    #expect(headings(book).isEmpty)
    #expect(paragraphs(book) == ["Over time, EOSDIS archive volumes", "increase exponentially", "projected", "3"])
}

// Slide 10 sets `Architectural Concept` at 26 points over a 28-point statement: the slide's title
// is *smaller* than its body, so no size rule can find it. Its place at the head of the slide can.
@Test func aTitleSetSmallerThanTheSlidesBodyIsStillItsTitle() throws {
    let page = try slide("slides-10")
    let title = LayoutReconstructor.slideTitle(in: page.lines, bounds: page.bounds)
    #expect(title.map(\.text) == ["Architectural Concept"])
    #expect(title[0].fontSize < LayoutReconstructor.bodySize(page.lines))
    let blocks = reconstruct(page)
    #expect(headings(blocks) == ["Architectural Concept"])
    #expect(paragraphs(blocks).first == "Earth Science Data Analytics the Cloud-Native Way:")
    // Negative control: outside a deck the page has no heading and the title opens its prose.
    let book = reconstruct(page, slideDeck: false)
    #expect(headings(book).isEmpty)
    #expect(paragraphs(book).first == "Architectural Concept")
}

// Slide 19's pipeline boxes are 13- and 14-point labels above the end-user labels at 10 points.
// The overprinted copies of `End-User`, `Interpretation` and `Cumulus` put more 10-point
// characters on the page than 14-point ones, so the page's estimate read 10 points as its body and
// the boxes as 40% over it: they became `<h5>` and `<h6>` under the real title, `Cumulus Cumulus
// Data Archive` among them. Each of the two rules closes it on its own.
private let slide19Title = "Open Pipeline Provides Outputs at Different Stages Appropriate for a Diverse User Base"

@Test func aSlidesDiagramLabelsAreItsBodyNotItsHeadings() throws {
    let page = try slide("slides-19", styled: true)
    let blocks = reconstruct(page)
    #expect(headings(blocks) == [slide19Title])
    for label in ["Preprocessing as-a-service", "AODS1 as-a-service", "Analysis as-a-service",
                  "Visualization as-a-service", "Cumulus Data Archive"] {
        #expect(paragraphs(blocks).contains(label))
    }
    // The reproducer, with the overprinted lines PDFKit returns: six headings, the boxes among them.
    let raw = try slide("slides-19-overprints", styled: true)
    let defect = headings(reconstruct(raw, slideDeck: false))
    #expect(defect.count == 6)
    #expect(defect.contains("Preprocessing as-a-service"))
    #expect(defect.contains("Cumulus Cumulus Data Archive"))
    // Either rule alone leaves the slide one heading: the deck's own evidence on the raw lines,
    // and — because the boxes are then the page's own body type — the overprint removal without it.
    #expect(headings(reconstruct(raw)) == [slide19Title])
    #expect(headings(reconstruct(page, slideDeck: false)) == [slide19Title])
}

// Slide 1 centres its 52-point title on the slide instead of setting it in the head band, so it has
// no slide title: the ordinary size rule still makes it the page's one heading, and the deck's
// evidence neither invents a title from the byline beneath it nor suppresses the real one.
@Test func aTitleSlideWithNoTitleInTheHeadBandKeepsTheOrdinaryRules() throws {
    let page = try slide("slides-1")
    #expect(LayoutReconstructor.slideTitle(in: page.lines, bounds: page.bounds).isEmpty)
    let blocks = reconstruct(page)
    #expect(headings(blocks) == ["Earthdata Cloud Analytics Project"])
    #expect(paragraphs(blocks) == ["Chris Lynnes* and Rahul Ramachandran*", "NASA", "*U.S. Civil Servant"])
    #expect(headings(reconstruct(page, slideDeck: false)) == headings(blocks))
}

// A deck sets each slide's title to fit the words on it, so the deck's titles run 52, 32 and 28
// points; ranked by size those are three tiers and three levels. A slide carries one title.
@Test func everySlideTitleOfADeckRanksAlike() throws {
    var deck = try reconstruct(slide("slides-1")) + reconstruct(slide("slides-3")) + reconstruct(slide("slides-19"))
    var ranked = deck
    LayoutReconstructor.rankHeadingLevels(&ranked, slideDeck: true)
    #expect(levels(ranked).map(\.1) == [2, 2, 2])
    #expect(levels(ranked).map(\.0) == ["Earthdata Cloud Analytics Project",
                                        "Over time, EOSDIS archive volumes increase exponentially",
                                        "Open Pipeline Provides Outputs at Different Stages Appropriate for a Diverse User Base"])
    // Negative control: the size tiers, which a book needs, rank the same three titles apart.
    LayoutReconstructor.rankHeadingLevels(&deck)
    #expect(levels(deck).map(\.1) == [2, 3, 4])
}

// MARK: What a slide is

/// A landscape page with one title line at `top` points from the head of the page and a body line
/// `gap` points below it, in the deck's proportions.
private func landscape(titleTop: CGFloat, gap: CGFloat) -> PageContent {
    let bounds = CGRect(x: 0, y: 0, width: 720, height: 405)
    let title = TextLine(text: "Solution: Data-proximal Analysis",
                         rect: CGRect(x: 150, y: bounds.maxY - titleTop - 30, width: 470, height: 30), fontSize: 32)
    let body = TextLine(text: "Data Archive",
                        rect: CGRect(x: 220, y: title.rect.minY - gap - 22, width: 80, height: 22), fontSize: 24)
    return PageContent(number: 1, bounds: bounds, lines: [title, body], graphics: [])
}

// The two place tests are separate guards, and the deck's own slides leave each other's case
// uncovered: slide 1's centred title misses the band by 50 pt and clears its byline by 24.3 pt
// against a 24.4 pt bar, so either guard alone still refuses it.
@Test func aSlideTitleNeedsBothItsBandAndItsClearance() {
    func title(_ page: PageContent) -> [String] {
        LayoutReconstructor.slideTitle(in: page.lines, bounds: page.bounds).map(\.text)
    }
    #expect(title(landscape(titleTop: 20, gap: 40)) == ["Solution: Data-proximal Analysis"])
    // Below the head band (the outer eighth is 50.6 pt), whatever the clearance beneath it.
    #expect(title(landscape(titleTop: 60, gap: 40)).isEmpty)
    #expect(title(landscape(titleTop: 51, gap: 40)).isEmpty)
    #expect(title(landscape(titleTop: 49, gap: 40)) == ["Solution: Data-proximal Analysis"])
    // In the band but running straight into the text beneath it (under half the title's height).
    #expect(title(landscape(titleTop: 20, gap: 14)).isEmpty)
    #expect(title(landscape(titleTop: 20, gap: 16)) == ["Solution: Data-proximal Analysis"])
    // Portrait pages have no slide titles at all.
    var portrait = landscape(titleTop: 20, gap: 40)
    portrait.bounds = CGRect(x: 0, y: 0, width: 405, height: 720)
    #expect(LayoutReconstructor.slideTitle(in: portrait.lines, bounds: portrait.bounds).isEmpty)
}

// The one landscape book in the corpus reads as portrait in unrotated page space, and its pages
// carry thousands of characters under a running head that stands in the same band a slide's title
// does. Either fact alone refuses it.
@Test func aLandscapeBooksPagesAreNoSlides() throws {
    let fixture = try SourceLayoutFixture.load("noaa-100")
    #expect(fixture.sourceSHA256 == noaaSHA256)
    var page = fixture.content()
    #expect(page.bounds.width < page.bounds.height)
    #expect(!LayoutReconstructor.isSlide(page))
    // Turned on its side, the page's running head stands where a slide's title does — and is still
    // no slide, because 2,781 characters are not one screenful.
    page.bounds = CGRect(x: 0, y: 0, width: 792, height: 612)
    #expect(!LayoutReconstructor.slideTitle(in: page.lines, bounds: page.bounds).isEmpty)
    #expect(page.lines.reduce(0) { $0 + $1.text.count } > 600)
    #expect(!LayoutReconstructor.isSlide(page))
    // Positive control: the deck's slides qualify.
    for name in ["slides-3", "slides-10", "slides-12", "slides-13", "slides-14", "slides-19"] {
        #expect(LayoutReconstructor.isSlide(try slide(name)))
    }
    // Slide 1 centres its title, so it is no slide either; the deck is decided by the rest.
    #expect(!LayoutReconstructor.isSlide(try slide("slides-1")))
}

// MARK: The slide's own note

// `¹ Analytics Optimized Data Store` explains the `AODS¹` box on the same slide. Slides 12, 13 and
// 14 set it in the same place at the foot, where three pages in a row made it a repeated footer.
@Test func aNoteExplainingAMarkerOnItsSlideIsNoFurniture() throws {
    var pages = try [slide("slides-12", styled: true), slide("slides-13", styled: true),
                     slide("slides-14", styled: true)]
    let note = "1 Analytics Optimized Data Store"
    #expect(pages.allSatisfy { $0.lines.contains { $0.text == note } })
    let warnings = FurnitureDetector.strip(&pages)
    #expect(pages.allSatisfy { $0.lines.contains { $0.text == note } })
    #expect(warnings.isEmpty)
    // Negative control: with the raised marker on the AODS box written as ordinary text, nothing on
    // the slide pairs with the note, and the same three repetitions read as a running foot again.
    var plain = try [slide("slides-12", styled: true), slide("slides-13", styled: true),
                     slide("slides-14", styled: true)]
    for index in plain.indices {
        for line in plain[index].lines.indices where plain[index].lines[line].text.hasPrefix("AODS") {
            plain[index].lines[line].replaceContent(InlineText(plain[index].lines[line].text))
        }
    }
    let removed = FurnitureDetector.strip(&plain)
    #expect(plain.allSatisfy { page in !page.lines.contains { $0.text == note } })
    #expect(removed.count == 3)
    #expect(removed.allSatisfy { $0.code == .furnitureRemoved })
}

// MARK: Text drawn twice in one place

// Google Slides keeps each build step's text boxes on the finished slide, so slide 19 draws
// `Cumulus`, `End-User` and `Interpretation` twice over, glyph for glyph. PDFKit returns a line for
// each and reflow read them as separate paragraphs.
@Test func aLineThatOnlyOverprintsAnotherIsReadOnce() throws {
    let raw = try slide("slides-19-overprints").lines
    let kept = NativeTextReader.withoutOverprints(raw)
    #expect(raw.count == 26)
    #expect(kept.count == 23)
    // `Cumulus` and `Interpretation` are drawn twice and kept once. `End-User` is printed three
    // times on this slide: the pair over `Interpretation`, and the one over `Cloud-Native Analysis`
    // further left, which stands on its own rectangle and survives.
    for word in ["Cumulus", "Interpretation"] {
        #expect(raw.filter { $0.text == word }.count == 2)
        #expect(kept.filter { $0.text == word }.count == 1)
    }
    #expect(raw.filter { $0.text == "End-User" }.count == 3)
    #expect(kept.filter { $0.text == "End-User" }.count == 2)
    #expect(Set(kept.filter { $0.text == "End-User" }.map(\.rect.minX)).count == 2)
    // Every other line survives, in order, and the fixture matches the page the pipeline extracts.
    #expect(kept.map(\.text) == (try slide("slides-19").lines.map(\.text)))
    // Negative controls. A copy offset by three tenths of a point is a second drawing that shows
    // (fake bold set by drawing a line twice), and a word genuinely repeated elsewhere on the page
    // has its own rectangle; both keep two lines.
    guard let original = kept.first(where: { $0.text == "Cumulus" }) else { Issue.record("no line"); return }
    for offset in [CGFloat(0.3), 60] {
        var shifted = original
        shifted.rect.origin.x += offset
        #expect(NativeTextReader.withoutOverprints([original, shifted]).count == 2)
    }
    // Different text on one rectangle is two lines, and a size change keeps both.
    var other = original
    other.replaceContent(InlineText("Cumulus Data"))
    #expect(NativeTextReader.withoutOverprints([original, other]).count == 2)
    var larger = original
    larger.fontSize += 1
    #expect(NativeTextReader.withoutOverprints([original, larger]).count == 2)
    #expect(NativeTextReader.withoutOverprints([original, original]).count == 1)
}
