import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Word breaks the page's own layout hid (#148) and line-end hyphens the extraction lost (#157):
// a prose row PDFKit split at a raised note marker or a stretched word space, a paragraph a
// tinted box cut, a cross-page break whose anchor line is mostly citations, a compound the
// source set with a space after its hyphen, and a hyphen PDFKit dropped from a justified line.
// Fixtures are native extraction from the checksum-pinned corpus documents; every expected
// phrase was read against the rendered source page, not against converter output.

private let reportSHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"
private let loperSHA256 = "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e"
private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"
private let flagSHA256 = "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8"

private func sourcePage(_ name: String, sha256: String, dropping furniture: [String] = []) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256, "\(name) source identity")
    var page = fixture.styledContent()
    for line in furniture { #expect(page.lines.contains { $0.text == line }, "missing \(line)") }
    page.lines.removeAll { furniture.contains($0.text) }
    return page
}

/// The page's blocks with the preserved regions the pipeline would crop, and the book words the
/// vocabulary supplies beyond this one page.
private func reflow(_ page: PageContent, vocabulary extra: Set<String> = [], crops: Bool = true) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    let regions = crops ? LayoutReconstructor.graphicsWithLabels(page) : []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]).union(extra), warnings: &warnings)
}

private func texts(_ blocks: [ReflowBlock]) -> [String] { blocks.map(\.text) }

/// A fixture read back through native extraction, so a drop-cap line carries the reading rectangle
/// the pipeline gives it, with the initial joined to its word as the pipeline joins it (#135).
private func nativePage(_ name: String, sha256: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256, "\(name) source identity")
    var page = fixture.content()
    for index in page.lines.indices {
        let line = page.lines[index]
        guard let source = fixture.attributedLines.first(where: { $0.text == line.text }) else { continue }
        var native = NativeTextReader.textLine(semantic: line.text, bounds: line.rect,
                                               attributed: source.attributedString())
        native.structure = line.structure
        page.lines[index] = native
    }
    LayoutReconstructor.joinDropCapInitials(&page, vocabulary: [])
    return page
}

private func lines(_ rows: [(String, CGFloat, CGFloat, CGFloat)], size: CGFloat = 10) -> [TextLine] {
    rows.map { TextLine(text: $0.0, rect: CGRect(x: $0.1, y: $0.2, width: $0.3, height: size), fontSize: size) }
}

private func blocks(_ lines: [TextLine], vocabulary: Set<String> = []) -> [String] {
    var warnings: [ConversionWarning] = []
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings).map(\.text)
}

// MARK: - #148 rows PDFKit split outside mathematics

// 9/11 pages 145, 220, 254, 259 and 438: each row PDFKit split reads as one line of its paragraph,
// and the raised marker closes the line it was set over with no space.
@Test func sourceProseRowsPDFKitSplitReadAsOneParagraph() throws {
    let vocabulary: Set<String> = ["briefing", "intelligence"]
    // Page 220: the marker piece `178 In March 2001, the CIA’s brief-` carries the marker's
    // 7.175-point size and starts exactly where `…for the Cole.` ends.
    var page220 = try sourcePage("911-220", sha256: reportSHA256, dropping: ["202 THE 9/11 COMMISSION REPORT"])
    LayoutReconstructor.restoreEqualsHyphens(&page220)
    let marker = try #require(page220.lines.first { $0.text.hasPrefix("178 In March 2001") })
    let over = try #require(page220.lines.first { $0.text.hasSuffix("for the Cole.") })
    #expect(marker.fontSize < over.fontSize * 0.8 && abs(marker.rect.minX - over.rect.maxX) < 1)
    let blocks220 = reflow(page220, vocabulary: vocabulary)
    #expect(texts(blocks220).contains {
        $0.contains("was responsible” for the Cole.178 In March 2001, the CIA’s briefing slides for Rice")
    })
    #expect(!texts(blocks220).contains { $0.hasPrefix("178 In March 2001") })
    // Page 145: the same shape, with marker 105 after a sentence.
    let blocks145 = try reflow(sourcePage("911-145", sha256: reportSHA256,
        dropping: ["RESPONSES TO AL QAEDA’S INITIAL ASSAULTS", "127"]), vocabulary: vocabulary)
    #expect(texts(blocks145).contains { $0.contains("after a leak to the Washington Times.105 This made it much more difficult") })
    // Page 438: `the intel-` is 4.2 points past `…to conduct oversight of` on one row, and the row
    // then carries the word break into the next line.
    var page438 = try sourcePage("911-438", sha256: reportSHA256, dropping: ["420 THE 9/11 COMMISSION REPORT"])
    LayoutReconstructor.restoreEqualsHyphens(&page438)
    let blocks438 = reflow(page438, vocabulary: vocabulary)
    #expect(texts(blocks438).contains {
        $0.contains("to conduct oversight of the intelligence establishment and be clearly accountable")
    })
    #expect(!texts(blocks438).contains { $0.hasPrefix("the intel") })
    // Controls: no block on either page is left holding a bare marker or a broken half, and page
    // 220's `Starting a Review` section still opens its own block.
    for blocks in [blocks220, blocks145, blocks438] {
        #expect(!texts(blocks).contains { $0.range(of: "^[0-9]{1,3} [A-Z]", options: .regularExpression) != nil })
        #expect(!texts(blocks).contains { $0.hasSuffix("-") })
    }
    #expect(blocks220.contains { $0.text.hasPrefix("Starting a Review In early March") })
}

// The FAA's page-367 heading `ATC Instructions—` and `“Hold Short”` are two pieces of one row,
// but the row is not a full line of the body's measure, so it is not read as prose that runs on
// into the paragraph beneath it.
@Test func sourceShortSplitRowIsNoProseRow() throws {
    let page = try sourcePage("faa-367", sha256: faaSHA256)
    let heading = try #require(page.lines.first { $0.text == "ATC Instructions—" })
    let rest = try #require(page.lines.first { $0.text == "“Hold Short”" })
    #expect(abs(heading.rect.maxX - rest.rect.minX) < 1 && abs(heading.rect.minY - rest.rect.minY) < 1)
    let reflowed = texts(reflow(page))
    #expect(!reflowed.contains { $0.contains("Hold Short” The most important sign") })
    #expect(reflowed.contains { $0.hasPrefix("The most important sign and marking on the airport") })
}

// Synthetic rows: what the prose tier joins and what it leaves apart. A justified column of
// 10-point lines on one 300-point measure, whose third row PDFKit split.
private func splitRowColumn(_ split: [(String, CGFloat, CGFloat, CGFloat)]) -> [String] {
    blocks(lines([("The committee should conduct continuing studies of every agency and report", 72, 712, 300),
                  ("the problems it finds to all the members of the House and of the Senate", 72, 700, 300)]
        + split
        + [("ligence establishment and be clearly accountable for the whole of their work", 72, 676, 300),
           ("The staff of this committee should be nonpartisan and work for the whole house", 72, 664, 300)]),
        vocabulary: ["intelligence"])
}

@Test func splitProseRowsJoinOnlyWhereTheirTextRunsOn() {
    // A word space between the pieces, the left leaving its sentence open: one row, and the word
    // break it now ends on joins the line beneath it.
    #expect(splitRowColumn([("and the agencies, and to conduct oversight of", 72, 688, 250),
                            ("the intel-", 326, 688, 46)])
        .contains { $0.contains("to conduct oversight of the intelligence establishment and be clearly") })
    // Controls, each leaving the pieces apart: a gap wider than half the type size, which is no
    // word space; a sentence that ends at the junction with no raised marker beside it; something
    // of the page standing in the junction; and a row too short to be a full line of the measure.
    // The two halves of `intelligence` still join as adjacent blocks (#131), so what says the row
    // did not rejoin is that the left piece does not run into it.
    func joins(_ split: [(String, CGFloat, CGFloat, CGFloat)], reading phrase: String) -> Bool {
        splitRowColumn(split).contains { $0.contains(phrase) }
    }
    #expect(!joins([("and the agencies, and to conduct oversight of", 72, 688, 240),
                    ("the intel-", 326, 688, 46)], reading: "oversight of the intelligence"))
    #expect(!joins([("and the agencies. We have conducted our oversight.", 72, 688, 250),
                    ("The intel-", 326, 688, 46)], reading: "oversight. The intelligence"))
    #expect(!joins([("and the agencies, and to conduct oversight of", 72, 688, 244),
                    (".", 318, 688, 4), ("the intel-", 326, 688, 46)], reading: "oversight of the intelligence"))
    #expect(!joins([("and the agencies, and to conduct", 72, 688, 180),
                    ("the intel-", 256, 688, 46)], reading: "to conduct the intelligence"))
}

// A raised note marker closes the line it was set over with no space; the same piece set in the
// body's own type meets its row at a word space.
@Test func raisedMarkerPieceClosesItsRowWithoutASpace() {
    var text = InlineText("178", style: .superscript)
    text.append(InlineText(" In March 2001, the CIA’s briefing slides for Rice were still"))
    let marker = TextLine(content: text, rect: CGRect(x: 280, y: 688, width: 92, height: 10), fontSize: 7.2)
    let over = ("that al-Qida was responsible” for the Cole.", CGFloat(72), CGFloat(688), CGFloat(208))
    let joined = splitRowColumn([over]) { [marker] }
    #expect(joined.contains { $0.contains("for the Cole.178 In March 2001, the CIA’s briefing slides") })
    #expect(!joined.contains { $0.hasPrefix("178 In March 2001") })
    // Without the raised style the piece is prose after a sentence end, so the row stays apart.
    let plain = TextLine(text: "178 In March 2001, the CIA’s briefing slides for Rice were still",
                         rect: marker.rect, fontSize: 10)
    #expect(splitRowColumn([over]) { [plain] }.contains { $0.hasPrefix("178 In March 2001") })
}

/// `splitRowColumn` with extra lines whose content the caller builds (a styled marker piece).
private func splitRowColumn(_ split: [(String, CGFloat, CGFloat, CGFloat)],
                            extra: () -> [TextLine]) -> [String] {
    blocks(lines([("The committee should conduct continuing studies of every agency and report", 72, 712, 300),
                  ("the problems it finds to all the members of the House and of the Senate", 72, 700, 300)]
        + split
        + [("the strong circumstantial case that could be made against them, while noting", 72, 676, 300),
           ("The staff of this committee should be nonpartisan and work for the whole house", 72, 664, 300)])
        + extra(), vocabulary: ["intelligence"])
}

// MARK: - #148 a paragraph a box or figure cut

// Fed page 22: the `More on Federal Reserve Advisory Councils` sidebar is read between
// `…stress tests of banking insti-` and `tutions. Stress tests are required…`, which are the
// two halves of one word on consecutive lines of one column.
@Test func sourceParagraphCutByABoxJoinsAcrossIt() throws {
    let page = try sourcePage("fed-22b", sha256: fedSHA256,
        dropping: ["14", "The Fed Explained: What the Central Bank Does"])
    let broken = try #require(page.lines.first { $0.text.hasSuffix("stress tests of banking insti-") })
    let rest = try #require(page.lines.first { $0.text.hasPrefix("tutions. Stress tests") })
    #expect(LayoutReconstructor.nextLineInColumn(broken, rest, page: page, body: 10))
    let reflowed = reflow(page)
    #expect(texts(reflowed).contains { $0.contains("stress tests of banking institutions. Stress tests are required under") })
    #expect(!texts(reflowed).contains { $0.hasPrefix("tutions.") })
    // The box keeps its own blocks and follows the joined item.
    #expect(texts(reflowed).contains("More on Federal Reserve Advisory Councils"))
    #expect(texts(reflowed).contains { $0.hasPrefix("For a current roster of Federal Reserve advisory council members") })
}

// A block further down the page joins a broken word only where it is the next line of the
// anchor's own column: the Fed page-22 shape, with the sidebar's title and text read between
// the two halves. The continuation must be directly beneath the anchor on its edge, with
// nothing of the column between, and the book must print the joined word.
@Test func distantBlocksJoinOnlyAsTheNextLineOfTheColumn() {
    let column = [("This council was established by the Board of Governors in 2012 to give", CGFloat(103), CGFloat(724), CGFloat(190)),
                  ("expert and independent advice on its process to rigorously assess the", 103, 712, 190),
                  ("models that are used in the stress tests of the banking insti-", 103, 700, 190)]
    let box = [("More on Federal Reserve Advisory Councils", CGFloat(323), CGFloat(704), CGFloat(156)),
               ("For a current roster of council members, visit the About the Fed", 323, 690, 187)]
    let rest = ("tutions. Stress tests are required under the Dodd-Frank Act of 2010", CGFloat(103), CGFloat(688), CGFloat(190))
    let joined = blocks(lines(column + box + [rest]), vocabulary: ["institutions"])
    #expect(joined.contains { $0.contains("the banking institutions. Stress tests are required") })
    #expect(joined.contains { $0.contains("More on Federal Reserve Advisory Councils") })
    // The same blocks with the continuation set in the other column stay apart.
    let beside = ("tutions. Stress tests are required under the Dodd-Frank Act of 2010", CGFloat(323), CGFloat(660), CGFloat(190))
    #expect(!blocks(lines(column + box + [beside]), vocabulary: ["institutions"])
        .contains { $0.contains("banking institutions") })
    // And the same blocks with a line of the column between the halves stay apart.
    let between = ("stress tests of every one of the banks the Board supervises today", CGFloat(103), CGFloat(688), CGFloat(190))
    let lower = ("tutions. Stress tests are required under the Dodd-Frank Act of 2010", CGFloat(103), CGFloat(676), CGFloat(190))
    #expect(!blocks(lines(column + box + [between, lower]), vocabulary: ["institutions"])
        .contains { $0.contains("banking institutions") })
    // Without the book's word the halves stay apart wherever they are.
    #expect(!blocks(lines(column + box + [rest])).contains { $0.contains("banking institutions") })
}

// MARK: - #148 a word break across a page

// Loper Bright pages 11 and 12: page 11's last line is under half letters, so it does not read as
// prose, but the word break it ends on is continuation evidence of its own.
@Test func sourceCrossPageWordBreakJoinsWhereTheLineIsMostlyCitations() throws {
    let first = try sourcePage("loper-11", sha256: loperSHA256,
        dropping: ["3", "Cite as: 603 U. S. ____ (2024)", "Opinion of the Court"])
    let second = try sourcePage("loper-12", sha256: loperSHA256,
        dropping: ["4 LOPER BRIGHT ENTERPRISES v. RAIMONDO", "Opinion of the Court"])
    let last = try #require(first.lines.last)
    #expect(last.text.hasSuffix("And in general, it author-"))
    #expect(last.text.filter(\.isLetter).count * 2 < last.text.filter { !$0.isWhitespace }.count)

    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    // The opinion prints `authorize` and `authorized` on other pages, and `authorizes` nowhere,
    // so the inflected form is what vouches for the join (#115).
    let vocabulary = LayoutReconstructor.vocabulary(in: [first, second]).union(["authorize", "authorized"])
    // `izes` opens page 12 after the break, so it is the rest of a broken word and no book word.
    #expect(!vocabulary.contains("izes") && !vocabulary.contains("authorizes"))
    for (page, previous) in [(first, nil), (second, Optional(first))] {
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: previous, to: &blocks,
            vocabulary: vocabulary, warnings: &warnings)
    }
    let joined = try #require(blocks.first { $0.text.contains("And in general, it authorizes the Secretary to impose") })
    #expect(joined.page == 11 && joined.sourcePages.contains(12))
    #expect(!blocks.contains { $0.text.hasPrefix("izes the Secretary") })
    #expect(!joined.text.contains("author-izes") && !joined.text.contains("author izes"))
}

@Test func aWordBreakContinuesOnlyOnTheBooksEvidence() {
    let vocabulary: Set<String> = ["authorize", "authorized", "sharp-edged", "sharp", "edged"]
    #expect(LayoutReconstructor.continuesWordBreak("And in general, it author-", "izes the Secretary",
                                                   vocabulary: vocabulary))
    // Controls: no hyphen, one letter before it, a capital continuation, and a break the book
    // vouches for neither way (which would warn `uncertainHyphen`).
    #expect(!LayoutReconstructor.continuesWordBreak("And in general, it author", "izes the", vocabulary: vocabulary))
    #expect(!LayoutReconstructor.continuesWordBreak("a 5-", "izes the", vocabulary: vocabulary))
    #expect(!LayoutReconstructor.continuesWordBreak("And in general, it author-", "Izes the", vocabulary: vocabulary))
    #expect(!LayoutReconstructor.continuesWordBreak("a bun-", "galow stood", vocabulary: vocabulary))
    // A compound whose halves are both book words is no word break either.
    #expect(!LayoutReconstructor.continuesWordBreak("a sharp-", "edged tool", vocabulary: ["sharp", "edged"]))
}

// MARK: - #148 a compound set with a space after its hyphen

@Test func spacedCompoundsCloseOnlyOnTheBooksOwnSetting() {
    let vocabulary: Set<String> = ["check-collection", "low-wing", "community-oriented", "service-broadcast",
                                   "\u{1}dash:airplanes\u{2014}14"]
    func closed(_ text: String) -> String { LayoutReconstructor.closingSpacedCompounds(text, vocabulary: vocabulary) ?? text }
    #expect(closed("remove original paper checks from the check- collection system (called check")
        == "remove original paper checks from the check-collection system (called check")
    #expect(closed("pilot of a low- wing aircraft should momentarily lower the") == "pilot of a low-wing aircraft should momentarily lower the")
    #expect(closed("Flight Information Service- Broadcast (FIS-B)") == "Flight Information Service-Broadcast (FIS-B)")
    // A suspended hyphen keeps its space: the book prints neither `consumer-and` nor `community-and`.
    #expect(closed("with consumer- and community- oriented laws commensurate with")
        == "with consumer- and community-oriented laws commensurate with")
    // The source prints a hyphen where its neighbours print the dash the book itself sets.
    #expect(closed("• Normal, Utility, Acrobatic, and Commuter Category Airplanes- 14 CFR part 23")
        == "• Normal, Utility, Acrobatic, and Commuter Category Airplanes\u{2014}14 CFR part 23")
    // Controls. Nothing without evidence; no dash before a lowercase word, which is where a
    // suspended hyphen carries on; no numbers, which word splitting can never record; nothing
    // inside an address; and nothing where the halves are not whole words.
    #expect(LayoutReconstructor.closingSpacedCompounds("a well- known result", vocabulary: vocabulary) == nil)
    #expect(LayoutReconstructor.closingSpacedCompounds("often region- and scale-dependent",
        vocabulary: ["\u{1}dash:region\u{2014}and"]) == nil)
    #expect(LayoutReconstructor.closingSpacedCompounds("the range 12- 15 inclusive", vocabulary: vocabulary) == nil)
    #expect(LayoutReconstructor.closingSpacedCompounds("see www.faa.gov/low- wing/index.html", vocabulary: vocabulary) == nil)
    #expect(LayoutReconstructor.closingSpacedCompounds("the check- c system", vocabulary: vocabulary) == nil)
    // The dash vocabulary records only pairs the book sets tight around an em dash.
    var dashes: Set<String> = []
    LayoutReconstructor.addDashVocabulary(of: "• Transport Category Airplanes\u{2014}14 CFR part 25", to: &dashes)
    LayoutReconstructor.addDashVocabulary(of: "the region \u{2014} and its people", to: &dashes)
    #expect(dashes == ["\u{1}dash:airplanes\u{2014}14"])
}

// Fed page 95 as the source sets it: `check- collection` inside one printed line closes up, and
// the page's other hyphens are untouched.
@Test func sourceSpacedCompoundClosesInsideItsLine() throws {
    var page = try sourcePage("fed-95", sha256: fedSHA256, dropping: ["Fostering Payment and Settlement System Safety and Efficiency", "91"])
    let vocabulary = LayoutReconstructor.vocabulary(in: [page])
    #expect(vocabulary.contains("check-collection"))
    LayoutReconstructor.closeSpacedCompounds(&page, vocabulary: vocabulary)
    #expect(page.lines.contains { $0.text.contains("from the check-collection system (called check truncation)") })
    #expect(!page.lines.contains { $0.text.contains("check- collection") })
    // The line that ends in `check-` before the page's next line is a line-end break, not this rule's.
    #expect(page.lines.contains { $0.text.hasSuffix("the nation’s check-") })
}

// FAA page 73 prints a hyphen where its own neighbours print an em dash. The book's dashes are
// the evidence: the page itself sets `Transport Category Airplanes—14 CFR part 25` two lines on.
@Test func sourceHyphenSetForADashTakesTheBooksDash() throws {
    var page = try sourcePage("faa-73", sha256: faaSHA256)
    #expect(page.lines.contains { $0.text == "Airplanes- 14 CFR part 23" })
    let vocabulary = LayoutReconstructor.vocabulary(in: [page])
    #expect(vocabulary.contains("\u{1}dash:airplanes\u{2014}14"))
    LayoutReconstructor.closeSpacedCompounds(&page, vocabulary: vocabulary)
    #expect(page.lines.contains { $0.text == "Airplanes\u{2014}14 CFR part 23" })
    // Its neighbours are untouched, and so is every other hyphen on the page.
    #expect(page.lines.contains { $0.text.hasSuffix("Airplanes\u{2014}14 CFR part 25") })
    #expect(!page.lines.contains { $0.text.contains("- ") && $0.text.range(of: "[a-z]- [a-z]",
        options: .regularExpression) != nil })
}

// MARK: - #157 a line-end hyphen the extraction lost

@Test func justifiedMeasureIsTheCommonestLineEndNotTheFurthest() {
    // Three lines flush on 369 and one that overhangs by a hyphen the book prints wide.
    let column = lines([("a line of the paragraph set to the measure", 64, 700, 305),
                        ("another line of the paragraph set flush", 64, 688, 305),
                        ("a third line of the paragraph set flush", 64, 676, 305),
                        ("a line ending in the book's own wide hyphen=", 64, 664, 311),
                        ("the paragraph's short last line", 64, 652, 120)], size: 9)
    #expect(LayoutReconstructor.justifiedMeasures(column)[9] == 369)
    // A ragged column, and a size too few lines share, have no measure.
    let ragged = lines([("one", 64, 700, 40), ("two lines", 64, 688, 90), ("three", 64, 676, 60),
                        ("four words here", 64, 664, 140)], size: 9)
    #expect(LayoutReconstructor.justifiedMeasures(ragged)[9] == nil)
}

@Test func lostLineEndHyphensCloseOnlyAHyphensWidthShortOfTheMeasure() {
    let measures: [Int: CGFloat] = [9: 369]
    let vocabulary: Set<String> = ["bombarded", "fabric", "people", "reality"]
    func line(_ text: String, _ width: CGFloat, size: CGFloat = 9) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 64, y: 500, width: width, height: size), fontSize: size)
    }
    let next = line("barded Fort McHenry in the harbor", 250)
    // 2.97 points short of the measure at 9 point: a hyphen's advance.
    #expect(LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom", 302.02), next,
        measures: measures, vocabulary: vocabulary))
    // A line flush on the measure, and one a whole word short, are no evidence.
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom", 305), next,
        measures: measures, vocabulary: vocabulary))
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom", 290), next,
        measures: measures, vocabulary: vocabulary))
    // The book must print the joined word and not the compound, exactly as for a hyphen it did
    // print: `reality` is in the vocabulary here, `alternately` is not.
    #expect(LayoutReconstructor.lostLineEndHyphen(line("did not become a real", 302.02),
        line("ity until June 20, 1782.", 98), measures: measures, vocabulary: vocabulary))
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("consisted of 13 stripes, alter", 302.02),
        line("nately red and white", 250), measures: measures, vocabulary: vocabulary))
    // Controls: a line that does not end in a letter, a continuation that does not open with one,
    // a size with no measure, and a continuation set in another type.
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom,", 302.02), next,
        measures: measures, vocabulary: vocabulary))
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom", 302.02),
        line("“barded Fort McHenry", 250), measures: measures, vocabulary: vocabulary))
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom", 302.02), next,
        measures: [:], vocabulary: vocabulary))
    #expect(!LayoutReconstructor.lostLineEndHyphen(line("the British fleet bom", 302.02),
        line("barded Fort McHenry in the harbor", 250, size: 11), measures: measures, vocabulary: vocabulary))
}

// Our Flag pages 5 and 9: the drop-cap paragraph's first line and the line before `nately` each
// stop a hyphen's width short of the measure, and the book's words close both breaks. `real ity`
// stays as extracted: the book prints neither `reality` nor any inflected form of it.
@Test func sourceLostLineEndHyphensCloseInTheirParagraphs() throws {
    // The book prints `bombarded` on page 14 and `following` on pages 10, 12, 17 and later.
    let page5 = try nativePage("our-flag-page-5", sha256: flagSHA256)
    let reflowed5 = texts(reflow(page5, vocabulary: ["bombarded", "following"]))
    #expect(reflowed5.contains { $0.contains("the British fleet bombarded") })
    #expect(reflowed5.contains { $0.contains("As the battle ceased on the following") })
    #expect(!reflowed5.contains { $0.contains("bom barded") || $0.contains("follow ing") })
    // Every other line end on the page keeps its word space: the quotation's lines, which are set
    // to a narrower measure of their own, and the paragraphs' short last lines.
    #expect(reflowed5.contains { $0.contains("the strength and pride of my native State") })
    #expect(reflowed5.contains { $0.contains("completed the poem.") })
    // Page 9, where `alternately` is nowhere in the book: `nately` opens the line after the break,
    // so it is no book word, and `alternate` (pages 7 and 13) vouches for the join (#115).
    let page9 = try nativePage("our-flag-page-9", sha256: flagSHA256)
    let vocabulary = LayoutReconstructor.vocabulary(in: [page9])
    #expect(!vocabulary.contains("nately") && !vocabulary.contains("alternately"))
    #expect(texts(reflow(page9, vocabulary: ["alternate"])).contains { $0.contains("13 stripes, alternately") })
    // Without that evidence the halves keep their space, as `real ity` does in the book.
    #expect(texts(reflow(page9)).contains { $0.contains("13 stripes, alter nately") })
}

@Test func aBrokenWordAtALostHyphenIsNoVocabulary() {
    // A justified column whose third line lost its hyphen: `nately` is the rest of `alternately`.
    let column = lines([("its design consisted of 13 stripes, and every one of", 64, 700, 305),
                        ("them is set in the order the Congress resolved on", 64, 688, 305),
                        ("its design consisted of 13 stripes, alter", 64, 676, 302),
                        ("nately red and white, representing the Thirteen", 64, 664, 305)], size: 9)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 423, height: 652), lines: column, graphics: [])
    let vocabulary = LayoutReconstructor.vocabulary(in: [page])
    #expect(vocabulary.contains("alter") && !vocabulary.contains("nately"))
    // A recognized page has no typographic measure, so its words are all words.
    var recognized = page
    recognized.recognized = true
    #expect(LayoutReconstructor.vocabulary(in: [recognized]).contains("nately"))
}

// A page's head matter stands outside the text, so the fragment rule reads across it to the
// previous page's last line (#148).
@Test func aPageBreakInsideAWordCarriesPastTheRunningHead() {
    func page(_ number: Int, _ rows: [(String, CGFloat, CGFloat, CGFloat)], head: [(String, CGFloat, CGFloat, CGFloat)] = [])
        -> PageContent {
        PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                    lines: lines(head, size: 9) + lines(rows, size: 11), graphics: [])
    }
    let body = [("observers be carried on board domestic vessels for the purpose of", CGFloat(156), CGFloat(688), CGFloat(300)),
                ("collecting the data necessary for the conservation of the fishery", 156, 674, 300),
                ("and, where the Secretary of Commerce so requires, of paying for it", 156, 660, 300)]
    let first = page(1, body + [("the statute and, in general, it author-", 156, 646, 300)])
    let second = page(2, [("izes the Secretary to impose sanctions", 156, 700, 300)] + body,
                      head: [("4 LOPER BRIGHT ENTERPRISES v. RAIMONDO", 156, 740, 253),
                             ("Opinion of the Court", 263, 726, 86)])
    #expect(!LayoutReconstructor.vocabulary(in: [first, second]).contains("izes"))
    // The head matter itself is still vocabulary, and a page opening lowercase after a line that
    // ends in no hyphen keeps its first word.
    #expect(LayoutReconstructor.vocabulary(in: [first, second]).contains("opinion"))
    let open = page(1, body + [("the statute and, in general, it authorizes", 156, 646, 300)])
    #expect(LayoutReconstructor.vocabulary(in: [open, second]).contains("izes"))
}
