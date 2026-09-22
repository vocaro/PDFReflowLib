import Foundation
import Testing
@testable import PDFReflowLib

/// One page's blocks as the pipeline makes them, with the crops `graphicsWithLabels` finds
/// standing in for the images the writer would place.
private func pageBlocks(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated()
        .map { ($0.element, "page-\(page.number)-region-\($0.offset)") }
    return LayoutReconstructor.blocks(page: page, images: images,
                                      vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                      warnings: &warnings)
}

private func reflowedTexts(_ page: PageContent) -> [String] {
    pageBlocks(page).filter(\.hasReflowedText).map(\.text)
}

/// Whether `texts` holds each of `phrases` exactly once, in this order.
private func runInOrder(_ phrases: [String], through texts: [String]) -> Bool {
    var positions: [Int] = []
    for phrase in phrases {
        let found = texts.indices.filter { texts[$0].contains(phrase) }
        guard found.count == 1 else { return false }
        positions.append(found[0])
    }
    return positions == positions.sorted() && Set(positions).count == positions.count
}

// MARK: - The contents pages a corner drawing was burying (#207, item 3)

/// `noaa-nca5-2023` page 9 is the first of ten contents pages. Each sets its entries from the
/// left margin to a page number at the right edge, with a painted leader between them, and each
/// places a decorative line drawing over its top right corner. Two mechanisms buried the text:
/// the drawing's rectangle covers the right end of the first nine rows, so the crop admitted
/// every one of them whole and grew across the page; and PDFKit reads a long entry and its page
/// number as two lines, so the leader between them ended far beyond its own line's right edge,
/// owned nothing, and seeded a figure of its own on every long entry.
///
/// Measured over pages 9–18 on `49e4586`: 9,281 of 14,808 characters stood inside crops, 47% to
/// 73% of a page. None does now.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func aContentsPageKeepsItsEntriesOutOfTheDrawingInItsCorner() throws {
    let fixture = try SourceLayoutFixture.load("noaa-9")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    #expect(fixture.page == 9)
    let page = fixture.content()
    // The page's own evidence: one placed drawing in the top right corner, and twenty painted
    // marks, nineteen of which are the leaders.
    let drawing = try #require(page.pictures.first)
    #expect(page.pictures.count == 1)
    #expect(drawing.maxX >= page.bounds.maxX - 1 && drawing.maxY >= page.bounds.maxY - 1)
    #expect(drawing.minX > page.bounds.minX + page.bounds.width * 0.4)
    #expect(page.graphics.count == 20)

    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let texts = reflowedTexts(page)
    // Every entry of the four chapters this page lists reflows, with the page number it runs to.
    for entry in ["Chapter 4. Water", "Key Message 4.1. Climate Change Will Continue to Cause Profound Change",
                  "Traceable Accounts", "References", "Chapter 5. Energy Supply, Delivery, and Demand",
                  "Key Message 5.2. Compounding Factors Affect Energy-System",
                  "Chapter 6. Land Cover and Land-Use Change", "Chapter 7. Forests"] {
        #expect(texts.contains { $0.contains(entry) }, Comment(rawValue: "lost: \(entry)"))
    }
    for number in ["4-1", "4-6", "4-16", "5-1", "5-9", "6-17", "7-1", "7-28"] {
        #expect(texts.contains { $0.contains(number) }, Comment(rawValue: "lost page number: \(number)"))
    }
    // No line of the page is inside a crop at all: a contents page has no figure to preserve.
    let headers = TableRegionDetector.columnHeaders(in: page, body: max(4, LayoutReconstructor.bodySize(page.lines)))
    for line in page.lines {
        #expect(!crops.contains { crop in
            LayoutReconstructor.takes(crop, line)
                && !LayoutReconstructor.reachesInto(crop, line, among: page.lines,
                                                    pictures: page.pictures, bounds: page.bounds,
                                                    columnHeaders: headers)
        }, Comment(rawValue: "buried: \(line.text)"))
    }
    // The entries read down the page, in the order it prints them.
    #expect(runInOrder(["Chapter 4. Water", "Chapter 5. Energy Supply", "Chapter 6. Land Cover",
                        "Chapter 7. Forests"], through: texts))
}

/// The baseline this rule was measured against: on the rule `takes` alone applies, the drawing's
/// crop holds the middle of every one of those rows, so the page's own reading is the picture's.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func theDrawingsCropStillHoldsTheRowsItReachesInto() throws {
    let page = try SourceLayoutFixture.load("noaa-9").content()
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let entry = try #require(page.lines.first { $0.text.hasPrefix("Key Message 4.1") })
    let number = try #require(page.lines.first { $0.text == "4-6" })
    let crop = try #require(crops.first { LayoutReconstructor.takes($0, entry) })
    // Both halves of the row stand inside the crop, and the row begins outside it, so both are
    // released: releasing the entry alone would leave the page number behind in the picture.
    #expect(LayoutReconstructor.takes(crop, number))
    #expect(LayoutReconstructor.reachesInto(crop, entry, among: page.lines, pictures: page.pictures,
                                            bounds: page.bounds))
    #expect(LayoutReconstructor.reachesInto(crop, number, among: page.lines, pictures: page.pictures,
                                            bounds: page.bounds))
    // A picture is what makes the difference: a region a page merely paints can still be carved,
    // which is why an exercise number beside its own fraction stays with it (#59, #255).
    #expect(!LayoutReconstructor.reachesInto(crop, entry, among: page.lines, pictures: [],
                                             bounds: page.bounds))
    // Nor by a picture that covers the page, which is the page — a scan, whose inherited layer
    // #93 and #176 already decide. The CIA report's own crops sit on such pages, and reading
    // their rows this way let 8,340 characters of the charts' OCR noise out into the prose.
    #expect(!LayoutReconstructor.reachesInto(crop, entry, among: page.lines, pictures: [page.bounds],
                                             bounds: page.bounds))
}

/// A leader is decoration whether PDFKit reads the row it crosses as one line or as two (#207).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func aLeaderBetweenAnEntryAndItsPageNumberIsDecoration() throws {
    let page = try SourceLayoutFixture.load("noaa-9").content()
    let body = max(4, LayoutReconstructor.bodySize(page.lines))
    let leaders = page.graphics.filter { LayoutReconstructor.isThinRule($0) && $0.width > 20 }
    #expect(leaders.count >= 15)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    // Not one leader survives as a region of its own; only the drawing does.
    #expect(crops.count == 1)
    for leader in leaders {
        #expect(!crops.contains { $0.insetBy(dx: -1, dy: -1).contains(leader) && $0.height < 100 },
                Comment(rawValue: "leader kept a crop at \(leader)"))
    }
    // The row is the measure. The leader below reaches from the end of `Key Message 5.1…` to the
    // `5-4` the entry runs to, which is 175 points past that line's own right edge.
    let entry = try #require(page.lines.first { $0.text.hasPrefix("Key Message 5.1") })
    let leader = try #require(leaders.first { LayoutReconstructor.isThinRule($0)
        && $0.midY >= entry.rect.minY && $0.midY <= entry.rect.maxY })
    #expect(leader.maxX > entry.rect.maxX + body * 2)
}

// MARK: - Positive controls from other books

/// A photograph keeps its own lettering. The magazine sets a sixty-word caption *inside* the
/// photograph on page 4, and that run begins inside the picture, so the crop still holds it and
/// only #239's own rule lets it reflow — this change frees rows the page prints across a picture,
/// not text the picture carries.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func aCaptionInsideAPhotographIsStillThePicturesOwn() throws {
    let fixture = try SourceLayoutFixture.load("usda-4")
    #expect(fixture.sourceSHA256 == "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761")
    let page = fixture.content()
    let photograph = try #require(page.pictures.first { $0.height > 500 })
    let caption = try #require(page.lines.first { $0.text.hasPrefix("At the Center for Medical") })
    #expect(photograph.contains(caption.rect))
    #expect(!LayoutReconstructor.reachesInto(photograph, caption, among: page.lines,
                                             pictures: page.pictures, bounds: page.bounds))
    // #239 still reads it as prose the page prints over the picture and reflows it.
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let freed = PageDiagnosis.proseOverPictures(lines: page.lines, pictures: page.pictures,
                                                crops: crops, bounds: page.bounds, language: "en")
    #expect(!freed.isEmpty)
    #expect(reflowedTexts(page).contains { $0.contains("spatial repellent delivery devices for testing.") })
}

/// A crop reaches into a row only where a picture is what it preserves, and never into a table's
/// column header, which is its table's however the page paints across it (#257).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func aRowIsReachedIntoOnlyByAPicturesCropAndNeverAColumnHeader() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
    let crop = CGRect(x: 200, y: 90, width: 120, height: 40)
    let reaching = TextLine(text: "The entry runs from the margin into the picture",
                            rect: CGRect(x: 40, y: 100, width: 220, height: 12), fontSize: 10)
    let inside = TextLine(text: "Figure 2", rect: CGRect(x: 210, y: 100, width: 40, height: 12), fontSize: 10)
    let number = TextLine(text: "17", rect: CGRect(x: 290, y: 100, width: 14, height: 12), fontSize: 10)
    let lines = [reaching, inside, number]
    // The row begins outside the crop, so neither its opening nor the number it runs to is the
    // picture's; a label that begins inside it is.
    #expect(LayoutReconstructor.reachesInto(crop, reaching, among: lines, pictures: [crop], bounds: bounds))
    #expect(LayoutReconstructor.reachesInto(crop, number, among: lines, pictures: [crop], bounds: bounds))
    #expect(!LayoutReconstructor.reachesInto(crop, inside, among: lines, pictures: [crop], bounds: bounds))
    // Without a picture the crop is a region the page painted, which a cut can still carve.
    #expect(!LayoutReconstructor.reachesInto(crop, reaching, among: lines, pictures: [], bounds: bounds))
    // A picture that covers the page is the page.
    #expect(!LayoutReconstructor.reachesInto(crop, reaching, among: lines, pictures: [bounds], bounds: bounds))
    // A column header is its table's, read as the label of the columns beneath it.
    #expect(!LayoutReconstructor.reachesInto(crop, reaching, among: lines, pictures: [crop], bounds: bounds,
                                             columnHeaders: [reaching.rect]))
    #expect(bounds.contains(crop))
}

// MARK: - The two items of #207 that main already answers

/// Appendix A's abbreviations. PDFKit merges most rows of the list into one line and reads five
/// of them apart, and the page itself prints `DIA` above `DCI` and `NTSB` second. Every entry is
/// its own preformatted block, carrying its abbreviation and its expansion, in the page's order:
/// nothing runs two entries together. Measured on `49e4586` before any change of this commit.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func theAbbreviationsListKeepsOneEntryPerBlock() throws {
    let fixture = try SourceLayoutFixture.load("911-448")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    #expect(fixture.page == 448)
    var page = fixture.content()
    // The running head the full-document furniture pass removes.
    page.lines.removeAll { $0.text == "430 APPENDIX" }
    // PDFKit reads five of the twenty rows apart and merges the other fifteen.
    #expect(page.lines.count == 25)
    #expect(page.lines.filter { $0.text == "NORAD" || $0.text == "OMB" }.count == 2)

    let texts = reflowedTexts(page)
    let entries = ["NORAD North American Aerospace Defense Command",
                   "NTSB National Transportation Safety Board",
                   "NSA National Security Agency", "NSC National Security Council",
                   "NSPD national security policy directive", "NYPD New York Police Department",
                   "OEM Office of Emergency Management (New York City)",
                   "OFAC Office of Foreign Assets Control",
                   "OIPR Office of Intelligence Policy and Review",
                   "OMB Office of Management and Budget",
                   "PAPD Port Authority Police Department",
                   "PDD presidential decision directive",
                   "PEOC Presidential Emergency Operations Center",
                   "SEC Securities and Exchange Commission",
                   "TSA Transportation Security Administration",
                   "TTIC Terrorist Threat Integration Center", "UBL Usama Bin Ladin",
                   "WMD weapons of mass destruction", "WTC World Trade Center",
                   "WTO World Trade Organization"]
    #expect(texts == entries)
    // One entry a block, so no block holds two abbreviations.
    for text in texts {
        #expect(text.split(whereSeparator: \.isWhitespace).filter {
            $0.count >= 3 && $0.allSatisfy(\.isUppercase)
        }.count <= 1, Comment(rawValue: "two entries run together: \(text)"))
    }
}

/// The flight timelines. PDFKit merges a time with its event on some rows (`7:59 Takeoff`) and
/// reads them apart on others (`8:19` beside `Flight attendant notifies AA of`), and the page
/// sets two timelines side by side. Every entry carries its own time, and the left timeline is
/// read whole before the right one begins. Measured on `49e4586` before any change of this
/// commit; the residual defect of these pages is the flight-label row PDFKit fuses across the
/// gutter, which is [#270](https://github.com/vocaro/PDFReflowLib/issues/270).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/207"))
func theTwoFlightTimelinesAreReadColumnByColumn() throws {
    for (name, head) in [("911-50", "32 THE 9/11 COMMISSION REPORT"), ("911-51", "“WE HAVE SOME PLANES” 33")] {
        var page = try SourceLayoutFixture.load(name).content()
        page.lines.removeAll { $0.text == head }
        let texts = reflowedTexts(page)
        let left: [String], right: [String]
        if name == "911-50" {
            left = ["7:59 Takeoff", "8:14 Last routine radio communication; likely takeover",
                    "8:19 Flight attendant notifies AA of hijacking", "8:21 Transponder is turned off",
                    "8:46:40 AA 11 crashes into 1 WTC (North Tower)",
                    "9:24 NEADS scrambles Langley fighter jets in search of AA 11"]
            right = ["8:14 Takeoff", "8:42 Last radio communication", "8:42-8:46 Likely takeover",
                     "9:03:11 Flight 175 crashes into 2 WTC (South Tower)",
                     "9:20 UA headquarters aware that Flight 175 had crashed into WTC"]
        } else {
            left = ["8:20 Takeoff", "8:51 Last routine radio communication", "8:51-8:54 Likely takeover",
                    "9:37:46 AA 77 crashes into the Pentagon",
                    "10:30 AA headquarters confirms Flight 77 crash into Pentagon"]
            right = ["8:42 Takeoff", "9:24 Flight 93 receives warning from UA about possible cockpit intrusion",
                     "9:28 Likely takeover", "10:03:11 Flight 93 crashes in field in Shanksville, PA",
                     "10:07 Cleveland Center advises NEADS of UA 93 hijacking"]
        }
        // Each entry is one block: the time and the event the page sets beside it are together
        // whether PDFKit read them as one line or as two.
        for entry in left + right {
            #expect(texts.contains(entry), Comment(rawValue: "\(name): not one block: \(entry)"))
        }
        // The left timeline is read whole, then the right one: no row of one is woven into the
        // other.
        #expect(runInOrder(left + right, through: texts), Comment(rawValue: texts.joined(separator: " | ")))
        let lastLeft = try #require(texts.firstIndex(of: left[left.count - 1]))
        let firstRight = try #require(texts.firstIndex(of: right[0]))
        #expect(lastLeft < firstRight)
    }
}

// MARK: - The flight-label row PDFKit fused across the gutter (#270)

/// The heading group above each timeline: the airline and flight number, the flight's short name
/// in brackets, and its route. PDFKit reads the first and third of those rows as two lines, one per
/// column, and hands the second back as one line spanning the gutter, which then took the left
/// column's route into itself and stranded the right column's:
///
/// ```
/// American Airlines Flight 11
/// United Airlines Flight 175
/// (AA 11) (UA 175) Boston to Los Angeles
/// Boston to Los Angeles
/// ```
///
/// Cut at the edge the rows above and below it state, no block holds two columns' cells and no
/// route is stranded. Page 50 goes further and reads each flight's three heading rows as one block,
/// because its map is one picture across both columns while page 51 draws two, one per column,
/// which the column reading divides the page at. The captures this replays were taken with the cut
/// in place, so what it pins is the reading those lines reflow to rather than the cut itself;
/// `ColumnGutterCutTests` measures the cut, against the same page's geometry.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/270"))
func eachFlightHeadingIsReadWithItsOwnColumn() throws {
    for (name, headings) in [("911-50", ["American Airlines Flight 11 (AA 11) Boston to Los Angeles",
                                         "United Airlines Flight 175 (UA 175) Boston to Los Angeles"]),
                             ("911-51", ["American Airlines Flight 77", "United Airlines Flight 93",
                                         "(AA 77)", "(UA 93)",
                                         "Washington, D.C., to Los Angeles", "Newark to San Francisco"])] {
        let texts = reflowedTexts(try SourceLayoutFixture.load(name).content())
        for heading in headings {
            #expect(texts.contains(heading), Comment(rawValue: "\(name): \(texts.joined(separator: " | "))"))
        }
        // No block holds both flights' labels, which is what the merged line did, and no block
        // holds one flight's label with the other flight's route.
        #expect(!texts.contains { $0.contains("(AA") && $0.contains("(UA") })
        #expect(runInOrder(headings, through: texts))
    }
}
