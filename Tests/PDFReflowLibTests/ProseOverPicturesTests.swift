import CoreGraphics
import Testing
@testable import PDFReflowLib

/// A figure crop takes every line it intersects. That is right for a picture's own lettering and
/// wrong for prose the page prints *over* a picture (#239). Every page below is built from
/// geometry and text measured on the source PDF — `PageReader`'s reading of the page, never a
/// converted EPUB — so each case states what the page sets, not what the converter produced.
private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 1.33), fontSize: size)
}

/// `usda-ars-agresearch-2012-11` page 4: a full-bleed photograph clipped to the area below the
/// masthead (69% of the page), with the magazine's sixty-word caption printed over it. The page
/// sets every caption line twice, one over the other, for a knockout.
private func usdaPage4() -> PageContent {
    let photograph = CGRect(x: 36, y: 52.5, width: 540, height: 619.2)
    let caption: [(String, CGFloat, CGFloat)] = [
        ("At the Center for Medical, Agricultural, and Veterinary", 128.8, 183.8),
        ("Entomology in Gainesville, Florida, scientists set up a tent", 119.0, 199.4),
        ("previously used in Iraq to evaluate how effective different", 109.2, 196.1),
        ("compounds are at protecting an occupant from mosquitoes and", 99.4, 218.5),
        ("stable flies. In the foreground, technician Joyce Urban releases", 89.7, 217.6),
        ("mosquitoes as entomologists Gary Clark (left) and Dan Kline", 79.9, 208.9),
        ("place spatial repellent delivery devices for testing.", 70.1, 171.7),
    ]
    let masthead = CGRect(x: 58.3, y: 704.8, width: 158, height: 50.5)
    var lines = caption.flatMap { text, y, width in
        [line(text, x: 55.1, y: y, width: width, size: 7.8),
         line(text, x: 55.1, y: y, width: width, size: 7.8)]
    }
    lines.append(line("STEPHEN AUSMUS (D2627-12)", x: 36.5, y: 673.6, width: 75.7, size: 6))
    lines.append(line("Agricultural Research \u{25CF} November/December 2012", x: 373.7, y: 24.6, width: 202.2, size: 9))
    return PageContent(number: 4, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines,
                       graphics: [CGRect(x: 34.5, y: 39, width: 544, height: 4),
                                  CGRect(x: 35.4, y: 688.4, width: 544, height: 7), photograph,
                                  CGRect(x: 56.3, y: 700.4, width: 520.6, height: 56.9)],
                       pictures: [photograph, masthead])
}

private func crops(_ page: PageContent) -> [CGRect] {
    LayoutReconstructor.graphicsWithLabels(page)
}

private func freed(_ page: PageContent, language: String = "en") -> Set<Int> {
    PageDiagnosis.proseOverPictures(lines: page.lines, pictures: page.pictures, crops: crops(page),
                                    bounds: page.bounds, language: language)
}

private func reflowedText(_ page: PageContent) -> String {
    var warnings: [ConversionWarning] = []
    let images = crops(page).enumerated().map { ($0.element, "image-\($0.offset).png") }
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    return blocks.filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func captionPrintedOverAPhotographReflows() {
    let page = usdaPage4()
    // The photograph is a crop of the page, and it takes the caption's fourteen lines.
    #expect(crops(page).contains(CGRect(x: 36, y: 52.5, width: 540, height: 619.2)))
    // One row of a paragraph reflows once: the page paints each caption row twice.
    #expect(freed(page).count == 7)
    let text = reflowedText(page)
    #expect(text.contains("Entomology in Gainesville, Florida, scientists set up a tent"))
    #expect(text.contains("place spatial repellent delivery devices for testing."))
    // Once, not twice: the knockout copy stays inside the crop.
    #expect(text.components(separatedBy: "place spatial repellent delivery devices").count == 2)
    // The credit line above the photograph never was in a crop and is unaffected.
    #expect(text.contains("STEPHEN AUSMUS"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func thePhotographIsStillCroppedAndShown() {
    var warnings: [ConversionWarning] = []
    let page = usdaPage4()
    let images = crops(page).enumerated().map { ($0.element, "image-\($0.offset).png") }
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    let assets = blocks.compactMap { block -> String? in
        if case let .image(image) = block.content { return image.assetID }
        return nil
    }
    #expect(assets.count == images.count)
}

/// `faa-phak-8083-25c` page 374: the airport diagram clipped to the top two thirds of the page,
/// and the figure caption set beneath it, whose line box overlaps the picture's padded foot by
/// under two points. The caption is not printed over the diagram, so it is not this rule's
/// business; the page's 71 words were Vision's reading of the diagram's own labels and belong to
/// the picture the crop preserves.
private func faaPage374() -> PageContent {
    let diagram = CGRect(x: 73.2, y: 244.8, width: 484.8, height: 485.2)
    return PageContent(number: 374, bounds: CGRect(x: 0, y: 0, width: 594, height: 774),
                       lines: [line("Figure 14-60. An airport diagram with EMAS information.",
                                    x: 72.1, y: 235.7, width: 216.8, size: 8),
                               line("14-40", x: 42.4, y: 32.4, width: 25.6, size: 10)],
                       graphics: [CGRect(x: 73.2, y: 244.8, width: 484.8, height: 486)],
                       pictures: [diagram])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func aCaptionBeneathAPictureIsNotProsePrintedOverIt() {
    let page = faaPage374()
    #expect(crops(page).contains { $0.intersects(page.lines[0].rect) })
    #expect(freed(page).isEmpty)
}

/// `faa-phak-8083-25c` page 475: the airport-signs legend, set inside the picture it explains.
/// Every entry is the picture's own lettering; entries stand a whole entry apart, so no three of
/// them are one paragraph's leading.
private func faaPage475() -> PageContent {
    let picture = CGRect(x: 371.8, y: 402.8, width: 185.2, height: 320.6)
    let entries: [(String, CGFloat, CGFloat)] = [
        ("Taxiway location sign", 703.5, 54.5),
        ("Runway holding position sign at takeoff end", 689.8, 110.6),
        ("Runway holding position sign at other than takeoff end", 676.1, 138.0),
        ("Runway holding position marking", 662.5, 84.1),
        ("Holding position marking for runway approach area", 648.8, 129.7),
        ("Elevated runway guard lights", 635.1, 73.6),
        ("Surface painted runway hold position sign", 621.4, 106.1),
        ("Enhanced centerline marking (located 150' prior to", 607.7, 127.9),
        ("runway hold position marking)", 601.2, 76.2),
        ("Holding position sign for a runway approach area", 587.5, 124.6),
    ]
    return PageContent(number: 475, bounds: CGRect(x: 0, y: 0, width: 594, height: 774),
                       lines: entries.map { line($0.0, x: 397.6, y: $0.1, width: $0.2, size: 5.7) },
                       graphics: [CGRect(x: 0, y: 221, width: 557.6, height: 507.3)],
                       pictures: [picture])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func aFigureLegendInsideAPictureStaysInItsCrop() {
    let page = faaPage475()
    #expect(page.lines.allSatisfy { line in crops(page).contains { $0.intersects(line.rect) } })
    #expect(freed(page).isEmpty)
    #expect(reflowedText(page).isEmpty)
}

/// `cdc-zombie-pandemic-2011` page 5 and `cia-blue-book-14-1955` page 136: a picture that covers
/// the page is the page. The comic's balloons and the sighting table's handwritten cells are its
/// artwork, and #93's and #176's readings of such a page already decide what becomes of them.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func aPageSizedPictureIsNotSomethingThePagePrintsOver() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let balloons = [
        line("in otHee News, seveeAL people HAve eeeN Hosp/rAL/zed Afree", x: 76.3, y: 706.6, width: 241.7, size: 9.2),
        line("a sreANee v/eus eeeAN", x: 76.3, y: 696.7, width: 235.0, size: 9.2),
        line("speeAd/Ng eAp/dLy rheoueh rhe sourheAsr and the whole country",
             x: 76.3, y: 686.8, width: 240.0, size: 9.2),
    ]
    let page = PageContent(number: 5, bounds: bounds, lines: balloons, graphics: [bounds], pictures: [bounds])
    #expect(PageDiagnosis.coversPage(bounds, bounds: bounds))
    #expect(PageDiagnosis.proseOverPictures(lines: page.lines, pictures: page.pictures,
                                            crops: [bounds], bounds: bounds, language: "en").isEmpty)
}

/// `cia-blue-book-14-1955` page 136: rows of a scanned sighting table share a left edge and a
/// leading exactly as a paragraph's lines do, and a majority of the words the lexicon judges read
/// as English on the strength of stray `I`s and `a`s. Their digits say what they are.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func rowsOfANumericTableAreNotProse() {
    let picture = CGRect(x: 60, y: 60, width: 480, height: 400)
    let rows = [
        "0-Balloon 0 0 p d.P 8.0 d.O 0 0 0 R.0 0.1 O.D 0 0 0 0 tf_O P.o o.o 0 0 PR",
        "1-Astronomical 5 2 5 11 14 16.5 4 0 3 12 7 6 1 0 2 9 4 3 11 0 5 2 13 7",
        "2-Aircraft 0 5 1i5 0. 0 11-5 1 1 i 10.O 1P.Q 0 0 Cl C o. a O.p o., ti 6 23.5 0.i 3.6",
        "3-Light 3 0 1 15.8 4.0 15.4 0 1 1 o., 11,Q 1D.P 2. 1 9 1.7 1 0 4 6 2 8 3 1",
    ]
    let lines = rows.enumerated().map { index, text in
        line(text, x: 100, y: 400 - CGFloat(index) * 10, width: 380, size: 7)
    }
    let page = PageContent(number: 136, bounds: CGRect(x: 0, y: 0, width: 610.6, height: 788.9),
                           lines: lines, graphics: [picture], pictures: [picture])
    #expect(freed(page).isEmpty)
}

/// A chart's axis, whose labels stand on one edge at one leading but each at its own width: no
/// row fills the measure, so the run is no paragraph.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func axisLabelsThatDoNotFillTheMeasureAreNotProse() {
    let picture = CGRect(x: 60, y: 60, width: 480, height: 400)
    let labels = ["Total certain sightings reported to the project", "Balloon", "Aircraft",
                  "Astronomical", "Insufficient information"]
    let lines = labels.enumerated().map { index, text in
        line(text, x: 100, y: 400 - CGFloat(index) * 10, width: CGFloat(text.count) * 3, size: 7)
    }
    let page = PageContent(number: 41, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: lines, graphics: [picture], pictures: [picture])
    #expect(freed(page).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func onlyBooksDeclaredEnglishAreJudged() {
    #expect(freed(usdaPage4(), language: "fr").isEmpty)
    #expect(freed(usdaPage4(), language: "en-US").count == 7)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/239"))
func aRunBrokenByItsLeadingIsNotOneParagraph() {
    // The same three caption lines, set a whole line further apart than the page sets them: the
    // rows no longer read as one paragraph's leading.
    let photograph = CGRect(x: 36, y: 52.5, width: 540, height: 619.2)
    let texts = ["At the Center for Medical, Agricultural, and Veterinary",
                 "Entomology in Gainesville, Florida, scientists set up a tent",
                 "previously used in Iraq to evaluate how effective different"]
    func built(leading: CGFloat) -> PageContent {
        PageContent(number: 4, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                    lines: texts.enumerated().map { index, text in
                        line(text, x: 55.1, y: 128.8 - CGFloat(index) * leading, width: 190, size: 7.8)
                    },
                    graphics: [photograph], pictures: [photograph])
    }
    #expect(freed(built(leading: 9.8)).count == 3)
    #expect(freed(built(leading: 24)).isEmpty)
}
