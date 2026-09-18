import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Crops that held a page's running text (#158, #166). A magazine's columns, pull quotes, index
// entries and captions, and a web print's header band, sidebar and gallery captions, were kept
// inside preserved-region images: a cluster's bounding box bridged art across the text between
// its parts, a background gradient or a faded flag under the columns seeded a crop, a caption's
// own band over a photograph went with the photograph, and a transparency group's box read as
// solid ink over the prose on it. Fixtures are native extraction from the checksum-pinned
// sources; expectations were read from the rendered pages.

private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

private func crops(_ page: PageContent) -> [CGRect] { LayoutReconstructor.graphicsWithLabels(page) }

/// Every line the page's crops take.
private func taken(_ page: PageContent, _ regions: [CGRect]) -> [TextLine] {
    page.lines.filter { line in regions.contains { $0.intersects(line.rect) } }
}

private func expectOutsideCrops(_ page: PageContent, _ regions: [CGRect], _ phrases: [String],
                                _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let held = taken(page, regions).map(\.text)
    for phrase in phrases {
        #expect(page.lines.contains { $0.text.contains(phrase) }, "\(label): the source has no \(phrase)",
                sourceLocation: sourceLocation)
        #expect(!held.contains { $0.contains(phrase) }, "\(label): a crop still holds \(phrase)",
                sourceLocation: sourceLocation)
    }
}

/// The page as it composed before this change: every painted footprint clusters into a crop seed
/// by its bounding box, as `GraphicsReader.Result.regions` does.
private func clusteredPage(_ fixture: SourceLayoutFixture) -> PageContent {
    var page = fixture.content(tinted: false)
    page.graphics = clusters(page.graphics, distance: 4)
    return page
}

private func rect(_ values: [Double]) -> CGRect {
    CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}

private func line(_ text: String, x: CGFloat, baseline: CGFloat, width: CGFloat, size: CGFloat = 9) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: baseline - 2.5, width: width, height: size * 1.25), fontSize: size)
}

private func paint(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                   frame: Bool = false, image: Bool = false, filled: Bool = false) -> GraphicsReader.Paint {
    GraphicsReader.Paint(rect: CGRect(x: x, y: y, width: width, height: height), frame: frame, image: image, filled: filled)
}

/// Six lines of a column, wrapped: the running text every rule here is about.
private func column(x: CGFloat, top: CGFloat, width: CGFloat = 200, count: Int = 6, size: CGFloat = 9) -> [TextLine] {
    (0..<count).map {
        line("agriculture is exposed to negative influences from nature \($0)",
             x: x, baseline: top - CGFloat($0) * (size * 1.4), width: width, size: size)
    }
}

// MARK: The magazine (#158)

@Test func magazineForumColumnsLeaveTheFootRuleAndSignatureBox() throws {
    let fixture = try SourceLayoutFixture.load("usda-2")
    let page = fixture.content()
    let regions = crops(page)
    // The running-foot rule and the signature box come within a point and a half of each other
    // across the foot of three columns; their hull took every line below 163 pt.
    #expect(regions.count == 2)
    expectOutsideCrops(page, regions, ["Agriculture is about producing food,", "cockroaches, mosquitoes, and stored-",
                                       "war-fighters often find themselves in places", "research provided solutions for termites,"],
                       "usda-2")
    #expect(taken(page, regions).map(\.text).contains("Daniel Strickman"))
    // Control: clustered as the reader's regions were, one crop takes the columns' feet.
    let defect = crops(clusteredPage(fixture))
    #expect(taken(clusteredPage(fixture), defect).map(\.text).contains { $0.contains("research provided solutions for termites,") })
}

@Test func magazineMastheadBoxIsATintOnceItsGroupBoxIsNotInk() throws {
    let fixture = try SourceLayoutFixture.load("usda-3")
    let page = fixture.content()
    #expect(page.tints.contains { $0.width > 200 && $0.height > 600 })
    expectOutsideCrops(page, crops(page), ["Agricultural Research is published 10 times a year by",
                                           "Editor: Robert Sowers", "DWFP: A Battle Plan To Protect U.S. Troops From"],
                       "usda-3")
    // The cover photograph keeps its own crop.
    #expect(crops(page).contains { $0.contains(CGRect(x: 280, y: 470, width: 280, height: 170)) })
    // Control: the transparency group's box recorded as a paint of its own (as before #158) is
    // solid ink over the staff list, so the box is no tint and its prose stays in a crop.
    var paints = try #require(fixture.paints).map {
        GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame, image: $0.image ?? false,
                             filled: $0.filled ?? false, grouped: $0.grouped ?? false)
    }
    let box = try #require(paints.first { $0.frame && $0.rect.height > 600 })
    paints.append(GraphicsReader.Paint(rect: box.rect, frame: false))
    var defect = fixture.content(tinted: false)
    let composed = TintDetector.compose(paints, lines: defect.lines, bounds: defect.bounds)
    defect.graphics = composed.graphics
    defect.tints = composed.tints
    #expect(composed.tints.isEmpty)
    #expect(taken(defect, crops(defect)).map(\.text).contains { $0.contains("Editor: Robert Sowers") })
}

@Test func magazineFlagBackgroundKeepsOnlyItsStripBelowTheColumns() throws {
    let fixture = try SourceLayoutFixture.load("usda-14")
    let page = fixture.content()
    let regions = crops(page)
    // The flag is a picture at the foot of the page whose upper part lies under the columns.
    #expect(regions.count == 1)
    let flag = try #require(regions.first)
    #expect(flag.maxY < 220 && flag.width > 500)
    #expect(taken(page, regions).isEmpty)
    expectOutsideCrops(page, regions, ["Studies have shown that insecticide", "the Coachella Valley in",
                                       "Sandra Avant, ARS"], "usda-14")
    // The pull quote's photograph is gone with the text over it; its box reflows as a tint.
    #expect(page.tints.contains { $0.contains(CGRect(x: 240, y: 220, width: 130, height: 160)) })
    // Control: every painted footprint as a crop seed keeps the columns inside one crop.
    let defect = clusteredPage(fixture)
    #expect(taken(defect, crops(defect)).map(\.text).contains { $0.contains("Studies have shown that insecticide") })
}

@Test func magazineTitleBoxAndCaptionBandLeaveThePhotograph() throws {
    let fixture = try SourceLayoutFixture.load("usda-16")
    let page = fixture.content()
    let regions = crops(page)
    expectOutsideCrops(page, regions, ["Finding Ways To Save", "Water in Peach Orchards",
                                       "Agricultural engineer Huihui Zhang measures peach tree leaf",
                                       "harvested in late May and early June, but the trees take"], "usda-16")
    // The photograph keeps its part beyond the title that crosses its edge and beyond the
    // caption's own band over it.
    let photograph = try #require(regions.first { $0.height > 300 })
    #expect(photograph.minX > 340 && photograph.minY > 377)
    #expect(page.tints.contains { $0.contains(CGRect(x: 330, y: 336, width: 215, height: 30)) })
    // Control: as the reader clustered it, one crop held the title, the caption and the column.
    let defect = clusteredPage(fixture)
    #expect(taken(defect, crops(defect)).map(\.text).contains { $0.contains("harvested in late May and early June") })
}

@Test func magazineIndexRuleAndOrnamentsTakeNoEntries() throws {
    let fixture = try SourceLayoutFixture.load("usda-22")
    let page = fixture.content()
    let regions = crops(page)
    // A holly ornament beside a letter head keeps only that head; the rule under the title, which
    // strikes no line, seeds nothing at all.
    #expect(regions.allSatisfy { taken(page, [$0]).count <= 1 })
    expectOutsideCrops(page, regions, ["Air quality, no-till spring cereal rotations and, Jul-19",
                                       "compounds in hulls may benefit health, Feb-22",
                                       "2012 INDEX", "Cattle"], "usda-22")
    // Control: clustered by bounding box, the title's ornament and the rule bridged three columns.
    let defect = clusteredPage(fixture)
    #expect(taken(defect, crops(defect)).count > 100)
}

// MARK: The TechPort print (#166)

@Test func techPortHeaderBandReflowsBesideTheInsignia() throws {
    let fixture = try SourceLayoutFixture.load("thm-1")
    let page = fixture.content()
    let regions = crops(page)
    #expect(page.tints.contains { $0.width > 500 && $0.minY > 660 })
    expectOutsideCrops(page, regions, ["Advanced Exploration Systems Division", "Tank Health Monitoring",
                                       "Completed Technology Project (2015", "Project Introduction 1",
                                       "Anticipated Benefits 2"], "thm-1")
    // The insignia keeps its own crop rather than a band across the title beside it.
    let insignia = try #require(regions.first { $0.minY > 660 })
    #expect(insignia.minX > 480 && insignia.width < 100)
    // The sidebar panel is a tint; the photograph in it keeps a crop.
    #expect(page.tints.contains { $0.minX > 400 && $0.height > 500 })
    #expect(regions.contains { $0.minX > 400 && $0.contains(CGRect(x: 420, y: 560, width: 145, height: 60)) })
}

@Test func techPortGalleryPicturesLeaveTheirCaptions() throws {
    let fixture = try SourceLayoutFixture.load("thm-5")
    let page = fixture.content()
    let regions = crops(page)
    // Three pictures 3 pt apart: their hull covered the captions under the shorter two.
    #expect(regions.filter { $0.minY > 500 && $0.maxY < 660 }.count == 3)
    expectOutsideCrops(page, regions, ["Tank Health Monitoring - In-", "Accurate measurement of cryogenic",
                                       "The Basic Formula", "Existing propellant gauging"], "thm-5")
    let defect = clusteredPage(fixture)
    #expect(taken(defect, crops(defect)).map(\.text).contains { $0.contains("Accurate measurement of cryogenic") })
}

// MARK: Running text (`blockText`)

@Test func blockTextIsAColumnOfRunningText() {
    let prose = column(x: 60, top: 700)
    #expect(TintDetector.blockText(prose).count == prose.count)
    // An index's hanging entries are one block; its letter head joins them.
    let index = [line("Almonds", x: 36, baseline: 700, width: 30, size: 8),
                 line("compounds in hulls may benefit health, Feb-22", x: 45, baseline: 689, width: 140, size: 8),
                 line("infrared heating kills Salmonella on, Feb-20", x: 45, baseline: 678, width: 135, size: 8)]
    #expect(TintDetector.blockText(index).count == 3)
    // A caption of short wrapped lines carries no four-word line but opens two in mid sentence.
    let caption = [line("Accurate measurement of", x: 418, baseline: 530, width: 117),
                   line("cryogenic liquid propellant", x: 418, baseline: 518, width: 119),
                   line("quantity in space without", x: 418, baseline: 506, width: 114)]
    #expect(TintDetector.blockText(caption).count == 3)
    // Controls: a derivation's annotations beside its steps (each opening with a capital and only
    // one reading as prose), two lines alone, a column of variables, and lines a line apart.
    let annotations = [line("Distribute 2x and− 5", x: 376, baseline: 640, width: 108, size: 12),
                       line("Multiply out each term", x: 376, baseline: 624, width: 114, size: 12),
                       line("Combine like terms", x: 376, baseline: 605, width: 96, size: 12),
                       line("Our Solution", x: 376, baseline: 588, width: 65, size: 12)]
    #expect(TintDetector.blockText(annotations).isEmpty)
    #expect(TintDetector.blockText(Array(prose.prefix(2))).isEmpty)
    let variables = [line("q", x: 120, baseline: 700, width: 6), line("d", x: 120, baseline: 688, width: 6),
                     line("25q", x: 120, baseline: 676, width: 14)]
    #expect(TintDetector.blockText(variables).isEmpty)
    let spread = (0..<4).map { line("agriculture is exposed to negative influences \($0)", x: 60, baseline: 700 - CGFloat($0) * 30, width: 200) }
    #expect(TintDetector.blockText(spread).isEmpty)
    // One line of prose and one wrapped line are not two: a heading over two labels is no block.
    let label = [line("Total for the year", x: 60, baseline: 700, width: 70),
                 line("and the quarter", x: 60, baseline: 688, width: 60),
                 line("Reserve Banks", x: 60, baseline: 676, width: 62)]
    #expect(TintDetector.blockText(label).isEmpty)
    // A figure's two labels set far inside a paragraph's measure are not part of its block.
    let wide = (0..<3).map { line("agriculture is exposed to negative influences from nature \($0)", x: 36, baseline: 700 - CGFloat($0) * 12.6, width: 500) }
    let inset = [line("Nose-up trim", x: 300, baseline: 662, width: 60), line("Nose-down trim", x: 300, baseline: 650, width: 66)]
    let block = TintDetector.blockText(wide + inset)
    #expect(block.count == 3 && !block.contains { $0.text == "Nose-up trim" })
}

@Test func clusteringKeepsRunningTextOutOfHulls() {
    // Two pictures three points apart, the left one shorter, with a caption under it.
    let left = CGRect(x: 36, y: 584, width: 153, height: 72), right = CGRect(x: 192, y: 556, width: 155, height: 100)
    let caption = [line("Accurate measurement of cryogenic liquid", x: 36, baseline: 578, width: 150),
                   line("propellant quantity in space without", x: 36, baseline: 566, width: 146),
                   line("propulsive settling maneuvers", x: 36, baseline: 554, width: 130)]
    #expect(clusters([left, right], distance: 4).count == 1)
    #expect(TintDetector.seedClusters([left, right], lines: caption + column(x: 36, top: 500)).count == 2)
    // Controls: labels rather than running text in the gap, no text at all, and parts that
    // overlap (a rectangle cannot hold one without the other).
    let labels = [line("Figure 1", x: 36, baseline: 578, width: 40), line("Figure 2", x: 36, baseline: 566, width: 40)]
    #expect(TintDetector.seedClusters([left, right], lines: labels + column(x: 36, top: 500)).count == 1)
    #expect(TintDetector.seedClusters([left, right], lines: column(x: 36, top: 500)).count == 1)
    let overlapping = CGRect(x: 150, y: 560, width: 155, height: 100)
    #expect(TintDetector.seedClusters([left, overlapping], lines: caption + column(x: 36, top: 500)).count == 1)
}

@Test func aGrazingCornerTakesNoLineOfRunningText() {
    // The magazine's index pages end their rule a tenth of a point inside the first entry of a
    // column; the crop grew from that entry through every column of the page.
    let ornament = CGRect(x: 35, y: 726.3, width: 551, height: 30)
    let entries = (0..<6).map { line("biocontrol methods in greenhouses, Sep-2\($0)",
                                     x: 229.8, baseline: 718.9 - CGFloat($0) * 11.5, width: 127, size: 8) }
    var page = PageContent(number: 1, bounds: pageBounds, lines: entries + column(x: 36, top: 600), graphics: [ornament])
    #expect(taken(page, crops(page)).isEmpty)
    // The art keeps all but the tenth of a point the entry reaches into.
    let crop = try? #require(crops(page).first)
    #expect(crop?.minY ?? 0 >= ornament.minY && crop?.maxY == ornament.maxY && crop?.minX == ornament.minX)
    // Control: a label the crop overlaps by three points is the art's own and is taken whole.
    let label = line("Figure 3 legend", x: 229.8, baseline: 721.5, width: 70, size: 8)
    page.lines = [label] + column(x: 36, top: 600)
    #expect(taken(page, crops(page)).map(\.text) == ["Figure 3 legend"])
    #expect(crops(page).contains { $0.contains(label.rect) })
    // Control: a caption beside the figure's head widens the crop over a column beside it, and
    // cutting that column away would cost the figure two thirds of itself. The crop keeps its art
    // whole and takes the line instead (FAA page 195's clipped form box).
    let figure = CGRect(x: 300, y: 100, width: 200, height: 400)
    let caption = line("Figure 7-40. High performance airplane pressurization system.", x: 280, baseline: 483, width: 240)
    let beside = column(x: 80, top: 299, width: 215, count: 5)
    var deep = PageContent(number: 1, bounds: pageBounds, lines: [caption] + beside, graphics: [figure])
    #expect(crops(deep).contains { $0.contains(figure) })
    deep.lines = []
    #expect(crops(deep) == [figure])
}

// MARK: Pictures under and behind text

@Test func picturesUnderTextGiveUpWhatTheirColumnsCover() {
    let background = paint(36, 54, 540, 165, image: true)
    let columns = column(x: 40, top: 214, width: 160, count: 12) + column(x: 240, top: 214, width: 160, count: 12)
    // A faded flag under two columns: the text covers it, so it seeds nothing.
    #expect(TintDetector.withoutTextBackdrops([background], lines: columns).isEmpty)
    // A picture whose column runs on past it keeps the part beyond that column.
    let tall = paint(36, 54, 540, 400, image: true)
    let running = column(x: 40, top: 480, width: 200, count: 8)
    let carved = try? #require(TintDetector.withoutTextBackdrops([tall], lines: running).first)
    #expect(carved?.rect.maxY ?? 0 < 400 && carved?.rect.minY == 54 && carved?.rect.width == 540)
    // Control: a caption block set inside a photograph stands alone there, and the photograph is
    // left with it.
    let photograph = paint(36, 54, 540, 620, image: true)
    let inside = column(x: 55, top: 140, width: 220, count: 5, size: 8)
    #expect(TintDetector.withoutTextBackdrops([photograph], lines: inside) == [photograph])
    // Control: one line of prose across a picture's middle is a label, not a text block over it,
    // however little of the picture lies beyond it.
    let middle = paint(36, 54, 540, 400, image: true)
    let across = [line("agriculture is exposed to negative influences from nature", x: 60, baseline: 250, width: 300)]
    #expect(TintDetector.withoutTextBackdrops([middle], lines: across) == [middle])
    // Control: a picture over another picture gives up nothing of its own; the covered one goes.
    let over = paint(36, 54, 360, 440, image: true)
    let beside = column(x: 404, top: 210, width: 170)
    #expect(TintDetector.withoutTextBackdrops([background, over], lines: beside) == [over])
}

@Test func overhangingTitlesAndCaptionBandsTrimAPicture() {
    let photograph = paint(288, 329, 288, 427, image: true)
    let title = [line("Finding Ways To Save", x: 34, baseline: 730, width: 268, size: 23.5),
                 line("Water in Peach Orchards", x: 34, baseline: 700, width: 308, size: 23.5)]
    let body = column(x: 36, top: 640, width: 234, count: 8, size: 10.5)
    let trimmed = try? #require(TintDetector.withoutTextBackdrops([photograph], lines: title + body).first)
    #expect(trimmed?.rect.minX ?? 0 > 300 && trimmed?.rect.maxX == 576)
    // Controls: a one-word label over the edge is the picture's own, and a title that would cost
    // it more than half its area keeps it whole.
    let label = [line("Fig. 3", x: 250, baseline: 700, width: 40, size: 8)]
    #expect(TintDetector.withoutTextBackdrops([photograph], lines: label + body) == [photograph])
    let across = [line("Finding Ways To Save Water in Peach Orchards", x: 34, baseline: 540, width: 500, size: 23.5)]
    #expect(TintDetector.withoutTextBackdrops([photograph], lines: across + body) == [photograph])
    // A caption on its own band over a picture is an overlay: the picture gives up the strip.
    let band = paint(311, 334, 239, 43, frame: true, filled: true)
    let caption = (0..<3).map { line("Agricultural engineer Huihui Zhang measures peach tree leaf \($0)",
                                     x: 324, baseline: 370 - CGFloat($0) * 10, width: 213, size: 7.9) }
    let above = try? #require(TintDetector.withoutTextBackdrops([photograph, band], lines: caption + body).first)
    #expect(above?.rect.minY ?? 0 > 377)
    // Control: a legend box holding art of its own is part of the picture.
    let legend = paint(311, 334, 239, 43, frame: true, filled: true)
    let swatch = paint(315, 340, 10, 10, filled: true)
    #expect(TintDetector.withoutTextBackdrops([photograph, legend, swatch], lines: caption + body).first?.rect == photograph.rect)
}

// MARK: Bands and panels of text (#166)

private func bannerPage(_ paints: [GraphicsReader.Paint], lines: [TextLine]) -> PageContent {
    var page = PageContent(number: 1, bounds: pageBounds, lines: lines, graphics: [])
    let composed = TintDetector.compose(paints, lines: lines, bounds: pageBounds)
    page.graphics = composed.graphics
    page.tints = composed.tints
    page.separators = composed.separators
    return page
}

@Test func bannerBandsReflowWhileTheirArtStaysBesideThem() {
    let band = paint(36, 669, 540, 87, frame: true, filled: true)
    let insignia = paint(487, 683, 78, 64, filled: true)
    let banner = [line("Advanced Exploration Systems Division", x: 43, baseline: 741, width: 183, size: 8.2),
                  line("Tank Health Monitoring", x: 43, baseline: 715, width: 148, size: 13.5),
                  line("Completed Technology Project (2015", x: 43, baseline: 682, width: 154, size: 8.2),
                  line("-", x: 200, baseline: 682, width: 4, size: 8.2),
                  line("2020)", x: 207, baseline: 682, width: 25, size: 8.2)]
    let body = column(x: 36, top: 620, width: 350)
    let page = bannerPage([band, insignia], lines: banner + body)
    #expect(page.tints.contains(band.rect))
    #expect(taken(page, crops(page)).isEmpty)
    #expect(crops(page).contains { $0.contains(insignia.rect) && $0.width < 120 })
    // Controls: a band in the middle of the page, a band whose rows read as neither prose nor a
    // title, and a band narrower than four fifths of the page keep their crop.
    let middle = paint(36, 400, 540, 87, frame: true, filled: true)
    let moved = banner.map { line($0.text, x: $0.rect.minX, baseline: $0.rect.minY + 2.5 - 269, width: $0.rect.width, size: $0.fontSize) }
    #expect(!bannerPage([middle, paint(487, 414, 78, 64, filled: true)], lines: moved + body).tints.contains(middle.rect))
    let codes = [line("TX12", x: 43, baseline: 741, width: 30, size: 8.2),
                 line("Tank Health Monitoring", x: 43, baseline: 715, width: 148, size: 13.5),
                 line("KSC", x: 43, baseline: 682, width: 20, size: 8.2)]
    #expect(!bannerPage([band, insignia], lines: codes + body).tints.contains(band.rect))
    // A band of prose alone carries no title of the page: it keeps its crop.
    let untitled = [line("Advanced Exploration Systems Division", x: 43, baseline: 741, width: 183, size: 8.2),
                    line("Completed Technology Project (2015 - 2020)", x: 43, baseline: 715, width: 190, size: 8.2)]
    #expect(!bannerPage([band, insignia], lines: untitled + body).tints.contains(band.rect))
    let narrow = paint(36, 669, 300, 87, frame: true, filled: true)
    #expect(!bannerPage([narrow, paint(250, 683, 78, 64, filled: true)], lines: banner + body).tints.contains(narrow.rect))
}

@Test func panelsOfRunningTextReflowAndGridsDoNot() {
    // A sidebar panel of headings, labelled fields and a contents list, none of it prose on the
    // panel's measure, but its paragraphs stack as running text.
    let panel = paint(408, 86, 168, 572, frame: true, filled: true)
    var sidebar = [line("Accurate measurement of", x: 418, baseline: 530, width: 117),
                   line("cryogenic liquid propellant", x: 418, baseline: 518, width: 119),
                   line("quantity in space without", x: 418, baseline: 506, width: 114),
                   line("propulsive settling maneuvers", x: 418, baseline: 494, width: 136)]
    sidebar += ["Project Introduction 1", "Anticipated Benefits 2", "Organizational Responsibility 2"].enumerated()
        .map { line($0.element, x: 418, baseline: 443 - CGFloat($0.offset) * 12, width: 149) }
    let body = column(x: 36, top: 620, width: 350)
    let page = bannerPage([panel], lines: sidebar + body)
    #expect(page.tints.contains(panel.rect))
    #expect(taken(page, crops(page)).isEmpty)
    // Control: a ratings grid of fragments in three columns beside three lines of prose.
    let grid = (0..<12).map { line("Capital adequacy and positions \($0)", x: 418 + CGFloat($0 % 3) * 45,
                                   baseline: 500 - CGFloat($0 / 3) * 30, width: 40) }
    #expect(!bannerPage([panel], lines: Array(sidebar.prefix(4)) + grid + body).tints.contains(panel.rect))
    // Control: rules between the panel's rows make it a grid, which keeps its image.
    let rules = [paint(410, 300, 164, 4), paint(410, 340, 164, 4)]
    #expect(!bannerPage([panel] + rules, lines: sidebar + body).tints.contains(panel.rect))
    // Control: two lines of a column that runs on above the panel are not a block inside it.
    let tail = (0..<5).map { line("agriculture is exposed to negative influences from nature \($0)",
                                  x: 418, baseline: 690 - CGFloat($0) * 12, width: 150) }
    #expect(!bannerPage([panel], lines: tail + body).tints.contains(panel.rect))
}

// MARK: The reader (#158)

@Test func readerSkipsAGroupBoxItsPaintsCoverAndMarksThem() throws {
    // A sidebar box drawn inside a transparency group whose box is exactly what it fills.
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /Fm 5 0 R /Sm 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("/Fm Do /Sm Do"),
        testPDFStream("0.9 g 30 40 210 640 re f",
                      extra: "/Type /XObject /Subtype /Form /BBox [30 40 240 680] /Group << /S /Transparency >>"),
        testPDFStream("0.5 g 300 300 40 40 re f",
                      extra: "/Type /XObject /Subtype /Form /BBox [280 280 400 400] /Group << /S /Transparency >>"),
    ])
    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    let result = GraphicsReader.read(try #require(document.page(at: 1)))
    #expect(!result.unsupported)
    // The covered box records nothing of its own and marks its paint; the box of a form whose
    // paint covers only a corner of it is still figure ink.
    #expect(result.paints.map(\.rect) == [CGRect(x: 30, y: 40, width: 210, height: 640),
                                          CGRect(x: 298, y: 298, width: 44, height: 44),
                                          CGRect(x: 280, y: 280, width: 120, height: 120)])
    #expect(result.paints.map(\.grouped) == [true, false, false])
    #expect(result.paints.map(\.frame) == [true, true, false])
}

@Test func pageSizedGradientsKeepTheirTextAndASourceReference() async throws {
    // A boxed-title article over a page-wide gradient: the gradient is the page's background, so
    // the page reflows and keeps a source-page reference rather than becoming an image.
    func article(background: String) -> Data {
        var content = background
        content += "BT /F1 18 Tf 1 0 0 1 40 720 Tm (Livestock Waste Management 2.0) Tj ET\n"
        for index in 0..<12 {
            content += "BT /F1 11 Tf 1 0 0 1 40 \(680 - index * 16) Tm "
                + "(One of the costs of running a farm can include buying nitrogen \(index)) Tj ET\n"
        }
        return testPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> "
                + "/Shading << /Sh 6 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            testPDFStream(content),
            "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 612 0] /Extend [true true] "
                + "/Function << /FunctionType 2 /Domain [0 1] /C0 [0.9 0.95 0.8] /C1 [1 1 1] /N 1 >> >>",
        ])
    }
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    func reconstruct(_ pdf: Data, name: String) async throws -> PDFReflowLibPipeline.Result {
        let url = directory.appendingPathComponent("\(name).pdf")
        try pdf.write(to: url)
        var options = ConversionOptions(); options.ocr = .never
        return try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
            workspace: directory.appendingPathComponent("work-\(name)"), progress: { _ in })
    }
    let shaded = try await reconstruct(article(background: "q 20 40 572 712 re W n /Sh sh Q\n"), name: "shaded")
    #expect(!shaded.warnings.contains { $0.code == .unsupportedGraphics || $0.code == .pageImageFallback })
    let text = shaded.document.blocks.map(\.text).joined(separator: "\n")
    #expect(text.contains("Livestock Waste Management 2.0") && text.contains("can include buying nitrogen 11"))
    // The page-sized paint keeps the review signal and its source-page reference.
    #expect(shaded.warnings.contains { $0.code == .unverifiedTextLayer })
    // Control: the same article without the gradient reflows with no signal at all.
    let plain = try await reconstruct(article(background: ""), name: "plain")
    #expect(plain.warnings.isEmpty)
    #expect(plain.document.blocks.map(\.text).joined(separator: "\n").contains("Livestock Waste Management 2.0"))
}

@Test func aRuledOffFootSurvivesAsASeparatorWhenAPageClearsItsGraphics() {
    // The magazine rules its running foot off under every column and sets a six-point photo
    // credit just above that rule, so the foot's nearest neighbour is nearer than a line height
    // and only the rule admits it as furniture (`ruledOff`, #159). Where this change reflows the
    // columns that stand over a page-wide gradient, the page keeps a source-page reference and
    // clears its graphics: the rule went with them, the foot was not recognized on those pages,
    // the document's run of feet broke, and the foot printed there and on the index pages after
    // them. Such a page now keeps its page-wide rules as separators, which `ruledOff` reads.
    func magazinePage(_ number: Int, cleared: Bool) -> PageContent {
        let rule = CGRect(x: 34.5, y: 39, width: 544, height: 4)
        let lines = column(x: 36, top: 700, size: 10)
            + [line("PEGGY GREB (D2698-1)", x: 40, baseline: 45.5, width: 90, size: 6),
               line("Agricultural Research l November/December 2012", x: 373, baseline: 27, width: 202)]
        var page = PageContent(number: number, bounds: pageBounds, lines: lines,
                               graphics: cleared ? [] : [rule])
        page.separators = cleared ? [rule] : []
        return page
    }
    for cleared in [false, true] {
        var pages = (1...3).map { magazinePage($0, cleared: cleared) }
        let warnings = FurnitureDetector.strip(&pages)
        let label = cleared ? "a page that cleared its graphics" : "a page that kept them"
        #expect(warnings.count == 3, "\(label): every page rules off a foot")
        for page in pages {
            #expect(!page.lines.contains { $0.text.contains("November/December 2012") },
                    "\(label): page \(page.number) still prints its running foot")
            #expect(page.lines.contains { $0.text.contains("PEGGY GREB") },
                    "\(label): the photo credit is not furniture")
        }
    }
}
