import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Line-end hyphens that still joined with a space (#131): prose compounds broken before a capital or
// a digit (9/11 `non- Muslims`, FAA `Single- Pilot`, Loper Bright `pre- APA`), word breaks whose
// halves layout set in two blocks (9/11 `train- ing`, `brief- ing`, `intel- ligence`), and number
// codes (`CTC 96- 30015`, `SD 108- 00`).

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

private func join(_ left: String, _ right: String, vocabulary: Set<String> = []) -> (text: String, warnings: [ConversionWarning]) {
    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.join(left, right, vocabulary: vocabulary, page: 1, warnings: &warnings)
    return (text, warnings)
}

private func vocabulary(_ lines: [String]) -> Set<String> {
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines.enumerated().map {
        TextLine(text: $1, rect: CGRect(x: 72, y: 700 - CGFloat($0) * 14, width: 400, height: 12), fontSize: 10)
    }, graphics: [])
    return LayoutReconstructor.vocabulary(in: [page])
}

@Test func compoundsBrokenBeforeACapitalKeepTheirHyphenWithNoSpace() {
    // Corpus line pairs, as the lanes join them.
    let compounds: [(String, String)] = [
        ("West, since he refused to meet with non-", "Muslims. The United States"),
        ("issues such as North Korea and the Israeli-", "Palestinian peace process.160"),
        ("Tenet for a Small Group meeting in mid-", "November, the Counterterrorist"),
        ("organizing national defense, the Goldwater-", "Nichols legislation of 1986"),
        ("to free ‘Abd al-", "Rahman and the other prisoners"),
        ("Crew Resource Management (CRM) and Single-", "Pilot Resource Management"),
        ("Electronic Flight Displays (EFD) /Multi-", "Function Display (MFD) Weather"),
        ("ready to acknowledge that in the pre-", "APA period, a deference regime"),
        ("Passengers and Crew Who Fought Back (Harper-", "Collins, 2002), p. 107;"),
        ("the pre-", "Columbian era"),
    ]
    for (left, right) in compounds {
        let result = join(left, right)
        #expect(result.text == left + right, "\(left) | \(right)")
        #expect(result.warnings.isEmpty)
    }
    // The book prints the halves as one word and never the compound: the break was the typesetter's.
    #expect(join("Commander, U.S. Central Command (CENT-", "COM), 2001–2003", vocabulary: ["centcom"]).text
        == "Commander, U.S. Central Command (CENTCOM), 2001–2003")
    #expect(join("Fought Back (Harper-", "Collins, 2002)", vocabulary: ["harpercollins"]).text == "Fought Back (HarperCollins, 2002)")
    // Both forms seen: the compound stands.
    #expect(join("the Goldwater-", "Nichols Act", vocabulary: ["goldwaternichols", "goldwater-nichols"]).text
        == "the Goldwater-Nichols Act")
    // Controls outside the rule: a lowercase continuation still goes through the hyphen policy, and
    // a dash set apart, a slash or a period before the break keep today's space.
    #expect(join("hijack train-", "ing, according", vocabulary: ["training"]).text == "hijack training, according")
    #expect(join("a dash -", "More text").text == "a dash - More text")
    #expect(join("the Banner.-", "Glorious").text == "the Banner.- Glorious")
    #expect(join("see U.S.-", "Saudi relations").text == "see U.S.- Saudi relations")
}

@Test func aWordBeforeADigitKeepsItsHyphenOnlyWhereTheBookUsesItAsAPrefix() {
    let book = vocabulary(["In the mid-1980s, it had been set up", "The pre-9/11 FBI", "Normal Category Airplanes—14 CFR part 23",
                           "lessons in the mid-", "1990s), Atta started", "varies inversely as the pres-", "62"])
    #expect(join("had taken lessons in the mid-", "1990s), Atta started", vocabulary: book).text
        == "had taken lessons in the mid-1990s), Atta started")
    #expect(join("On the pre-", "9/11 number of JTTFs", vocabulary: book).text == "On the pre-9/11 number of JTTFs")
    // A line-end `mid-` is not evidence: every such break leaves one.
    let breaksOnly = vocabulary(["lessons in the mid-", "1990s), Atta started", "Beginning in the mid-", "1980s, however"])
    #expect(join("had taken lessons in the mid-", "1990s), Atta started", vocabulary: breaksOnly).text
        == "had taken lessons in the mid- 1990s), Atta started")
    // A hyphen set for a dash before a citation, a word broken before a folio or note number, a
    // one-letter prefix, and a compound's inner word keep the space.
    #expect(join("Commuter Category Airplanes-", "14 CFR part 23", vocabulary: book).text
        == "Commuter Category Airplanes- 14 CFR part 23")
    #expect(join("varies inversely as the pres-", "62", vocabulary: book).text == "varies inversely as the pres- 62")
    #expect(join("on the results of the investi-", "22S. 50 U.S.C.", vocabulary: book).text
        == "on the results of the investi- 22S. 50 U.S.C.")
    #expect(join("in the less-than-", "5-second group.").text == "in the less-than- 5-second group.")
    // The inner word counts once the book sets it before a number inside a line.
    #expect(join("in the less-than-", "5-second group.", vocabulary: vocabulary(["the less-than-5-second"])).text
        == "in the less-than-5-second group.")
    #expect(join("tln s-", "6- ,. II-", vocabulary: vocabulary(["s-6"])).text == "tln s- 6- ,. II-")
}

@Test func numberVocabularyRecordsOnlyPrefixesInsideALine() {
    let book = vocabulary(["In the mid-1980s and the pre-9/11 era", "lessons in the mid-", "the Post-9/11 inquiry", "C-130H 737-700"])
    #expect(book.contains("\u{1}number-prefix:mid"))
    #expect(book.contains("\u{1}number-prefix:pre"))
    #expect(book.contains("\u{1}number-prefix:post"))
    #expect(book.contains("\u{1}number-prefix:c"))
    #expect(!book.contains { $0.hasPrefix("\u{1}number-prefix:") && $0.contains("lessons") })
    #expect(!book.contains("\u{1}number-prefix:"))
    // The plain word entries are unchanged.
    #expect(book.contains("mid-") && book.contains("pre-") && book.contains("lessons"))
}

@Test func numberCodesAndRangesBrokenAtAHyphenJoin() {
    let numbers: [(String, String)] = [
        ("Bin Ladin All Suspects,” CTC 96-", "30015, July 5, 1996;"),
        ("Suspects,” CTC 96-", "30015,July 5,1996;"),
        ("2001; SD 108-00, July 27, 2001; SD 108-", "00, July 27, 2001;"),
        ("transactions processed, 1989-", "2019"),
        ("(pages 112-", "118)."),
    ]
    for (left, right) in numbers {
        #expect(join(left, right).text == left + right, "\(left) | \(right)")
    }
    let others: [(String, String)] = [
        ("14 H 601-", "CE 1318; see also"),   // a citation range running into the next citation
        ("12 H 183-", "WFAA-TV reel PKF-10"),
        ("40-", "I"),
        ("100-", "Location"),
        ("a dash -", "5 more"),
        ("5- 6-", "7. g. ,,,"),               // single digits: OCR column labels
        ("rates of 3.5-", "40 percent"),       // a decimal is no code
        ("formula x=12-", "15"),
        ("serial 12-", "15a3 held"),
    ]
    for (left, right) in others {
        #expect(join(left, right).text == left + " " + right, "\(left) | \(right)")
    }
}

@Test func aNumberBeforeALowercaseWordKeepsItsCompoundHyphen() {
    // NASA GWL page 13 (#155): `45-` + `degree-increment`, where the page prints `degrees` and the
    // book `degree`, read `45degree-increment`.
    let result = join("plots of data acquired in 45-", "degree-increment azimuth regions.", vocabulary: ["degree", "degrees"])
    #expect(result.text == "plots of data acquired in 45-degree-increment azimuth regions.")
    #expect(result.warnings.isEmpty)
    #expect(join("a 3-", "dimensional model").text == "a 3-dimensional model")
    // Controls: letters before the hyphen still go through the hyphen policy, and a soft hyphen after a
    // digit and an address segment keep their rules.
    #expect(join("hijack train-", "ing, according", vocabulary: ["training"]).text == "hijack training, according")
    #expect(join("item 45\u{00AD}", "degree", vocabulary: ["degree"]).text == "item 45degree")
    #expect(join("see www.example.org/page1-", "econ/x", vocabulary: ["address"]).text.hasPrefix("see www.example.org/page1-econ/x"))
}

/// A page's blocks, with the book's `=` hyphen restored (#126). The vocabulary is the page's own
/// words and the joined words the whole book prints (`training` 275 times, `briefing` 221,
/// `intelligence` 1,421), none of them as compounds.
private func reconstructed(_ name: String) throws -> (blocks: [ReflowBlock], warnings: [ConversionWarning]) {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == gpo911SHA256)
    var page = fixture.styledContent()
    LayoutReconstructor.restoreEqualsHyphens(&page)
    var warnings: [ConversionWarning] = []
    let vocabulary = LayoutReconstructor.vocabulary(in: [page]).union(["training", "briefing", "intelligence"])
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
    return (blocks, warnings)
}

@Test func wordBreaksSplitAcrossBlocksJoinThroughTheHyphenPolicy() throws {
    // Page 147: item 2's wrapped lines sit flush with its marker, so they opened a paragraph. Since
    // #118 the item's same-column next lines continue it; the break stays joined either way.
    let page147 = try reconstructed("911-147").blocks
    let item = try #require(page147.first { $0.text.hasPrefix("2. Some members") })
    guard case .preformatted = item.content else { Issue.record("item 2 is no list item"); return }
    #expect(item.text.contains("have received hijack training, according to various sources"))
    #expect(item.text.hasSuffix("a US military or civilian aircraft."))
    // Page 220: note marker 178 set the line in note type, so its wrap opened a paragraph.
    let page220 = try reconstructed("911-220").blocks
    #expect(page220.contains { $0.text.contains("In March 2001, the CIA’s briefing slides for Rice were still describing") })
    // Page 438: PDFKit split `the intel-` from its row.
    let page438 = try reconstructed("911-438").blocks
    #expect(page438.contains { $0.text.hasPrefix("the intelligence establishment and be clearly accountable") })
    for (number, blocks) in [(147, page147), (220, page220), (438, page438)] {
        let texts = blocks.map(\.text)
        #expect(!texts.contains { $0.range(of: "[A-Za-z]- [a-z]", options: .regularExpression) != nil }, "\(number)")
        for (left, right) in zip(texts, texts.dropFirst()) {
            #expect(!(left.hasSuffix("-") && right.first?.isLowercase == true), "\(number): \(left.suffix(30)) | \(right.prefix(30))")
        }
    }
    // Controls on the same pages: page 147's bullets keep their items, and page 220's run-in
    // section after the joined paragraph, which opens with a capital, stays a paragraph of its own.
    #expect(page147.filter { $0.text.hasPrefix("• ") }.count == 5)
    #expect(page220.contains { $0.text.hasPrefix("Starting a Review In early March, the administration postponed") })
    #expect(!page220.contains { $0.text.contains("slides for Rice") && $0.text.contains("Starting a Review") })
}

@Test func blocksThatDoNotContinueAWordStayApart() {
    func blocks(_ lines: [(String, CGFloat, CGFloat)]) -> [String] {
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines.map {
            TextLine(text: $0.0, rect: CGRect(x: $0.1, y: $0.2, width: 300, height: 10), fontSize: 10)
        }, graphics: [])
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: page, images: [], vocabulary: ["training"], warnings: &warnings).map(\.text)
    }
    // A paragraph gap between the halves, with and without the hyphen evidence.
    #expect(blocks([("Some members of the network have received train-", 72, 700), ("ing, according to sources.", 72, 660)])
        == ["Some members of the network have received training, according to sources."])
    #expect(blocks([("Some members of the network have received training.", 72, 700), ("according to sources.", 72, 660)]).count == 2)
    // A capital after the break is a new block's own opening (Fed `institu-` + `Figure 6.6.`).
    #expect(blocks([("That is, all institu-", 72, 700), ("Figure 6.6. Commercial automated clearinghouse", 72, 660)]).count == 2)
    // Without the book's evidence for the word or the compound, the blocks' separation stands: reading
    // order can set a fragment beside the wrong neighbour (NOAA `acidifica-` + `oceans, animal`).
    #expect(blocks([("the effects of ocean acidifica-", 72, 700), ("oceans, animal migrations and fisheries.", 72, 660)]).count == 2)
    // A single letter before the hyphen is no word break (Blue Book OCR `/9, Z-` + `r.,mbel`).
    #expect(blocks([("If Si? /9, Z-", 72, 700), ("r.,mbel Per Cent Number", 72, 660)]).count == 2)
}
