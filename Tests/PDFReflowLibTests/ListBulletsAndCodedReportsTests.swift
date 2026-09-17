import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #115: a tall list marker line keeps its wrapped line (Wallace page 2), and a line-end hyphen
// whose joined word the book uses in another inflected form is repaired (Wallace page 9's
// `sep-` + `arates`). #96: a coded weather report set over several lines is one preformatted
// block (FAA pages 316-319). Fixtures are native extraction from the checksum-pinned sources;
// expected text was read against rendered source pages.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func reflow(_ page: PageContent, vocabulary: Set<String>? = nil, crops: Bool = true,
                    warnings: inout [ConversionWarning]) -> [ReflowBlock] {
    let regions = crops ? LayoutReconstructor.graphicsWithLabels(page) : []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: vocabulary ?? LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func reflow(_ page: PageContent, crops: Bool = true) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return reflow(page, crops: crops, warnings: &warnings)
}

private func algebra(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("algebra-\(number)")
    #expect(fixture.sourceSHA256 == algebraSHA256)
    var page = fixture.styledContent()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    return page
}

private func faa(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("faa-\(number)-tagged")
    #expect(fixture.sourceSHA256 == faaSHA256)
    var page = fixture.styledContent()
    page.lines.removeAll { $0.rect.maxY < page.bounds.height * 0.07 && $0.text.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil }
    return page
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { text.text } else { nil } }
}

private func line(_ text: String, x: Double, y: Double, width: Double, height: Double = 9.9, size: Double = 10) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height), fontSize: size)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 594, height: 774), lines: lines, graphics: [])
}

// MARK: - Tall list marker lines (#115)

// Wallace page 2: the license's bullet and minus lines stand 17 points tall against the page's
// 9.9-point lines, so each overlaps its wrapped line by 4.8 points against 4.0 of tolerance.
@Test func sourceTallLicenseBulletsKeepTheirWrappedLines() throws {
    let blocks = reflow(try algebra(2))
    let items = preformatted(blocks)
    #expect(items == [
        "• to Share: to copy, distribute and transmit the work",
        "• to Remix: to adapt the work",
        "• Attribution: You must attribute the work in the manner specified by the author or licensor (but not in any way that suggests that they endorse you or your use of the work).",
        "• Waiver: Any of the above conditions can be waived if you get permission from the copyright holder.",
        "• Public Domain: Where the work or any of its elements is in the public domain under applicable law, that status is in no way aﬀected by the license.",
        "• Other Rights: In no way are any of the following rights aﬀected by the license:",
        "− Your fair dealing or fair use rights, or other applicable copyright exceptions and limitations;",
        "− The author’s moral rights;",
        "− Rights other persons may have either in the work itself or in how the work is used such as publicity or privacy rights",
        "• Notice: For any reuse or distribution, you must make clear to others the license term of this work. The best way to do this is with a link to the following web page:",
    ])
    let texts = paragraphs(blocks)
    for fragment in ["licensor", "right holder", "applicable law", "limitations", "such as publicity", "this work."] {
        #expect(!texts.contains { $0.hasPrefix(fragment) }, "\(fragment)")
    }
    // Controls: the notice's address, set off by added space, and the labels between the lists.
    #expect(texts.contains("http://creativecommons.org/licenses/by/3.0/"))
    #expect(texts.contains("With the understanding that:"))
    #expect(texts.contains("You are free:"))
}

private func licensePage(markerHeight: Double, gap: Double, marker: String = "• Waiver: Any of the above conditions can be waived if you get permission from the copy-",
                         extra: [TextLine] = []) -> PageContent {
    // Ordinary 9.9-point lines establish the page's line height at this size.
    var lines = (0..<6).map { line("Ordinary prose line \($0) of the license summary that fills the measure.", x: 85, y: 700 - Double($0) * 12.2, width: 425) }
    let markerY = 400.0
    lines.append(line(marker, x: 98.3, y: markerY, width: 411.9, height: markerHeight))
    lines.append(line("right holder.", x: 115, y: markerY - gap - 9.9, width: 54.2))
    return page(lines + extra)
}

@Test func syntheticTallMarkerLineKeepsItsWrappedLine() {
    // Wallace geometry: a 17-point marker rectangle over its wrapped line, overlapping by 4.8 points.
    let joined = preformatted(reflow(licensePage(markerHeight: 17, gap: -4.8)))
    #expect(joined.contains("• Waiver: Any of the above conditions can be waived if you get permission from the copy-right holder."))
    // Control: ordinary rectangles overlapping by as much are not a wrapped line.
    let ordinary = reflow(licensePage(markerHeight: 9.9, gap: -4.8))
    #expect(paragraphs(ordinary).contains("right holder."))
    // Control: an overlap past the extra height stays apart.
    let deeper = reflow(licensePage(markerHeight: 17, gap: -12))
    #expect(paragraphs(deeper).contains("right holder."))
    // Control: a rectangle more than twice the ordinary height is a display.
    let display = reflow(licensePage(markerHeight: 21, gap: -9))
    #expect(paragraphs(display).contains("right holder."))
    // Controls for a marker line of terms, not a sentence. Crops are off: with them, the formula
    // crop takes these lines before any guard is consulted (as in #109's exercise-column checks).
    // Terms alone on their row, and beside another column's exercise (Wallace's exercise
    // columns), earn no allowance.
    let exercise = line("2) 5x− 2=− 7", x: 330, y: 400, width: 80, height: 17)
    for (marker, extra) in [("1) 3x+ 4y=− 2x− 6y+ 12", []), ("1) 3x+ 4y=− 2x− 6y+ 12", [exercise])] {
        let blocks = reflow(licensePage(markerHeight: 17, gap: -4.8, marker: marker, extra: extra), crops: false)
        #expect(!preformatted(blocks).contains { $0.contains("right holder.") }, "\(marker)")
        #expect(paragraphs(blocks).contains("right holder."), "\(marker)")
    }
    // The sentence alone on its row joins with crops off too.
    let sentence = reflow(licensePage(markerHeight: 17, gap: -4.8, marker: "1) Solve the equation for the value of the"), crops: false)
    #expect(preformatted(sentence).contains("1) Solve the equation for the value of the right holder."))
}

// MARK: - Inflected forms vouch for a hyphen join (#115)

@Test func sourceSeparatesJoinsWhereTheBookUsesAnotherForm() throws {
    // Wallace prints `Separate`, `separated` and `separately` elsewhere, never `separates`.
    let page9 = try algebra(9)
    var vocabulary = LayoutReconstructor.vocabulary(in: [page9])
    #expect(!vocabulary.contains("separates"))
    var warnings: [ConversionWarning] = []
    let before = paragraphs(reflow(page9, vocabulary: vocabulary, warnings: &warnings))
    #expect(before.contains { $0.contains("subtraction sep-arates the 3") })
    #expect(warnings.contains { $0.code == .uncertainHyphen })

    vocabulary.formUnion(["separate", "separated", "separately"])
    warnings = []
    let after = paragraphs(reflow(page9, vocabulary: vocabulary, warnings: &warnings))
    #expect(after.contains { $0.contains("The− 3− 8 problem, is subtraction because the subtraction separates the 3 from what comes after it.") })
    #expect(!warnings.contains { $0.code == .uncertainHyphen })
}

@Test func inflectedFormsVouchOnlyForAWordBrokenInsideItself() {
    func decide(_ left: String, _ right: String, _ words: Set<String>) -> (String, Bool) {
        var warnings: [ConversionWarning] = []
        let text = LayoutReconstructor.join(left, right, vocabulary: words, page: 1, warnings: &warnings)
        return (text, warnings.contains { $0.code == .uncertainHyphen })
    }
    // Survey cases: Wallace 9, Fed 19, arXiv 3, 9/11 104.
    #expect(decide("subtraction sep-", "arates the 3", ["separate", "separated"]) == ("subtraction separates the 3", false))
    #expect(decide("including distribut-", "ing the", ["distribute"]) == ("including distributing the", false))
    #expect(decide("func-", "tions, Shift", ["function"]) == ("functions, Shift", false))
    #expect(decide("dis-", "seminates intelligence", ["disseminated", "dis"]) == ("disseminates intelligence", false))
    // The joined word itself still decides first, and the compound too.
    #expect(decide("sep-", "arate", ["separate"]) == ("separate", false))
    #expect(decide("self-", "contained", ["self-contained", "selfcontained"]) == ("self-contained", false))
    // Controls. No form seen: kept with a warning (Wallace's `dif-` + `ferent` beside `diﬀerent`).
    #expect(decide("dif-", "ferent form", ["diﬀerent"]) == ("dif-ferent form", true))
    // Both halves are words, as a compound's are (Wallace 301's `re-` + `writing`).
    #expect(decide("re-", "writing the", ["rewrite", "re", "writing"]) == ("re-writing the", true))
    // A form of the compound is seen.
    #expect(decide("co-", "operates with", ["cooperate", "co-operate"]) == ("co-operates with", true))
    // Too short to be evidence.
    #expect(decide("ca-", "se", ["cases"]) == ("ca-se", true))
    #expect(!LayoutReconstructor.inflectionVouches(prefix: "sharp", suffix: "edged", vocabulary: ["sharp", "edged", "sharpedge"]))
    #expect(LayoutReconstructor.inflectedForms("separates").isSuperset(of: ["separate", "separated", "separately", "separating"]))
    #expect(LayoutReconstructor.inflectedForms("distributing").contains("distribute"))
}

// MARK: - Coded weather reports (#96)

@Test func sourceMetarAndPirepExamplesAreOneBlockEach() throws {
    let metar = "METAR KGGG 161753Z AUTO 14021G26KT 3/4SM +TSRA BR BKN008 OVC012CB 18/17 A2970 RMK PRESFR"
    for number in [316, 317] {
        let blocks = reflow(try faa(number))
        #expect(preformatted(blocks).contains(metar), "\(number)")
        #expect(!paragraphs(blocks).contains { $0.hasPrefix("METAR KGGG") || $0.hasPrefix("+TSRA") || $0 == "PRESFR" }, "\(number)")
        #expect(paragraphs(blocks).contains("Example:"), "\(number)")
    }
    let page316 = reflow(try faa(316))
    #expect(paragraphs(page316).contains("A typical METAR report contains the following information in sequential order:"))
    // The explanation's items, whose prose quotes report groups, are untouched.
    #expect(preformatted(page316).contains { $0.hasPrefix("5. Wind—reported with five digits (14021KT) unless") })

    let page318 = reflow(try faa(318))
    #expect(preformatted(page318).contains("UA/OV GGG 090025/TM 1450/FL 060/TP C182/SK 080 OVC/WX FV04SM RA/TA 05/WV 270030KT/TB LGT/RM HVY RAIN"))
    #expect(!paragraphs(page318).contains { $0.hasPrefix("UA/OV") || $0.hasPrefix("080 OVC") })
    #expect(paragraphs(page318).contains("Explanation:"))
}

@Test func sourceTafKeepsItsChangeGroupsOnSeparateLines() throws {
    let blocks = reflow(try faa(319))
    #expect(preformatted(blocks).contains("""
        TAF
        KPIR 111130Z 1112/1212
        TEMPO 1112/1114 5SM BR
        FM1500 16015G25KT P6SM SCT040 BKN250
        FM120000 14012KT P6SM BKN080 OVC150 PROB30 1200/1204 3SM TSRA BKN030CB
        FM120400 1408KT P6SM SCT040 OVC080
        TEMPO 1204/1208 3SM TSRA OVC030CB
        """))
    #expect(!paragraphs(blocks).contains { $0.contains("KPIR") || $0.contains("FM1500") || $0.hasPrefix("TEMPO") })
    #expect(paragraphs(blocks).contains { $0.hasPrefix("Routine TAF for Pierre, South Dakota") })
}

@Test func codedReportGroupsAreTheReportFormatsTokens() {
    #expect(LayoutReconstructor.codedReportGroupCount("METAR KGGG 161753Z AUTO 14021G26KT 3/4SM") == 6)
    #expect(LayoutReconstructor.codedReportGroupCount("+TSRA BR BKN008 OVC012CB 18/17 A2970 RMK") == 7)
    #expect(LayoutReconstructor.codedReportGroupCount("UA/OV GGG 090025/TM 1450/FL 060/TP C182/SK") == 6)
    #expect(LayoutReconstructor.codedReportGroupCount("KPIR 111130Z 1112/1212") == 3)
    #expect(LayoutReconstructor.codedReportGroupCount("PRESFR") == 0)
    // Prose, even quoting groups, cannot be a report line; capitals alone carry no groups.
    #expect(LayoutReconstructor.codedReportGroupCount("Wind—reported with five digits (14021KT) unless") == nil)
    #expect(LayoutReconstructor.codedReportGroupCount("PILOT WEATHER REPORTS") == 0)
    #expect(LayoutReconstructor.codedReportGroupCount("VFR IFR MVFR LIFR") == 0)
    #expect(LayoutReconstructor.codedReportGroupCount("ICAO NOAA FAA NWS") == 0)
    #expect(LayoutReconstructor.isCodedReportType("TAF"))
    #expect(!LayoutReconstructor.isCodedReportType("TAF KPIR"))
}

@Test func syntheticCodedReportRunsFollowTheFormatNotTheGeometry() {
    func runs(_ texts: [String], gaps: [Double]? = nil, x: [Double]? = nil) -> [[(Int, Bool)]] {
        var y = 500.0
        let lines = texts.enumerated().map { offset, text -> TextLine in
            if offset > 0 { y -= 11.5 + (gaps?[offset - 1] ?? 1) }
            return TextLine(text: text, rect: CGRect(x: x?[offset] ?? 36, y: y, width: 220, height: 11.5), fontSize: 10)
        }
        return LayoutReconstructor.codedReportRuns(lines, body: 10).map { $0.map { ($0.index, $0.lineBreak) } }
    }
    func same(_ a: [[(Int, Bool)]], _ b: [[(Int, Bool)]]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.count == $1.count && zip($0, $1).allSatisfy { $0 == $1 } }
    }
    let metar = ["METAR KGGG 161753Z AUTO 14021G26KT 3/4SM", "+TSRA BR BKN008 OVC012CB 18/17 A2970 RMK", "PRESFR"]
    #expect(same(runs(metar), [[(0, false), (1, false), (2, false)]]))
    // Free capitals end the report unless they follow `RMK`.
    #expect(same(runs(["METAR KGGG 161753Z AUTO 14021G26KT 3/4SM", "PRESFR"]), []))
    // Prose after the report ends it; another report opens its own run.
    #expect(same(runs(metar + ["A typical METAR report contains the following"]), [[(0, false), (1, false), (2, false)]]))
    #expect(same(runs(metar + metar), [[(0, false), (1, false), (2, false)], [(3, false), (4, false), (5, false)]]))
    // Change groups keep their breaks.
    #expect(same(runs(["TAF", "KPIR 111130Z 1112/1212", "TEMPO 1112/1114 5SM BR"]), [[(0, false), (1, true), (2, true)]]))
    // A single coded line is not a run, and a lone report type needs a coded line under it.
    #expect(same(runs(["FM1500 16015G25KT P6SM SCT040 BKN250"]), []))
    #expect(same(runs(["TAF", "Explanation:"]), []))
    // Two groups do not open a report: a line must carry three.
    #expect(same(runs(["KPIR 111130Z", "A2970 RMK"]), []))
    // Geometry still bounds a run: added space or another column ends it.
    #expect(same(runs(metar, gaps: [12, 1]), [[(1, false), (2, false)]]))
    #expect(same(runs(metar, x: [36, 300, 300]), [[(1, false), (2, false)]]))
}
