import Foundation
import Testing
@testable import PDFReflowLib

// A line broken inside a web address continues it without a space: after an underscore (Fed page
// 37's `bst_` + `openmarketops.htm`), a dot, a query character, a hyphen before a digit or capital,
// or before a slash or dot that opens the next line (#79). Sentence ends and the hyphen policy are
// unchanged.

@Test(arguments: [
    // Fed 37, 64, 19, 33; 9/11 581 (twice), 570; FAA 34, 92; NOAA DOIs.
    ("More information on LSAPs is available at https://www.federalreserve.gov/monetarypolicy/bst_", "openmarketops.htm.",
     "More information on LSAPs is available at https://www.federalreserve.gov/monetarypolicy/bst_openmarketops.htm."),
    ("Website: https://www.bis.org/central_bank_hub_", "overview.htm", "Website: https://www.bis.org/central_bank_hub_overview.htm"),
    ("see the Board’s website, https://www.", "federalreserve.gov/aboutthefed/directors.htm.",
     "see the Board’s website, https://www.federalreserve.gov/aboutthefed/directors.htm."),
    ("FOMC meeting at https://www.federalreserve.gov", "/monetarypolicy/fomccalendars.htm.",
     "FOMC meeting at https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm."),
    ("(online at www.pewtrusts.com/ideas/ideas_item.cfm?content_", "item_id=1645&content_type_id=7).",
     "(online at www.pewtrusts.com/ideas/ideas_item.cfm?content_item_id=1645&content_type_id=7)."),
    ("(online at http://english.daralhayat.com/Spec/02-", "2004/Article-20040213-ac40bdaf",
     "(online at http://english.daralhayat.com/Spec/02-2004/Article-20040213-ac40bdaf"),
    ("(online at www.panynj.gov/AboutthePortAuthority", "/PortAuthorityPolice/InMemoriam/). For",
     "(online at www.panynj.gov/AboutthePortAuthority/PortAuthorityPolice/InMemoriam/). For"),
    ("database located at http://av-info.faa.gov/PilotSchool.", "asp, lists", "database located at http://av-info.faa.gov/PilotSchool.asp, lists"),
    ("Another website (www.wahiduddin.net/calc/density_", "altitude.htm) provides", "Another website (www.wahiduddin.net/calc/density_altitude.htm) provides"),
    ("https://doi.org/10.1080/14693062.", "2022.2061405", "https://doi.org/10.1080/14693062.2022.2061405"),
    ("https://doi.org/10.1038/s41598-", "020-62188-4", "https://doi.org/10.1038/s41598-020-62188-4"),
    ("https://cfvi.net/uploads/2020-Final-USVI-", "Snapshot_red.pdf", "https://cfvi.net/uploads/2020-Final-USVI-Snapshot_red.pdf"),
    ("https://doi.org/10.1080/00207543", ".2019.1629670", "https://doi.org/10.1080/00207543.2019.1629670"),
    ("https://nca.gov/a.aspx?id=", "89&page=2", "https://nca.gov/a.aspx?id=89&page=2"),
    // FAA 372: the address follows an em dash with no space.
    ("• FAA National Aeronautical Navigation Services (AeroNav), formerly known as the National Aeronautical Charting Office (NACO)—www.faa.",
     "gov/air_traffic/flight_info/aeronav",
     "• FAA National Aeronautical Navigation Services (AeroNav), formerly known as the National Aeronautical Charting Office (NACO)—www.faa.gov/air_traffic/flight_info/aeronav"),
    ("https://www.nsf.gov/files/FCAB%20National%20Blueprint%20Lithium%20", "Batteries%200621_0.pdf",
     "https://www.nsf.gov/files/FCAB%20National%20Blueprint%20Lithium%20Batteries%200621_0.pdf"),
    // Controls: the sentence ends after a closing parenthesis, before a capital or before a bare
    // number; words that are not addresses; an address followed by an opening quote.
    ("(online at www.markle.org).", "42.General Accounting Office", "(online at www.markle.org). 42.General Accounting Office"),
    ("https://www.federalreserve.gov/publications/files/monetary-policy.htm.", "A shorter, educators piece",
     "https://www.federalreserve.gov/publications/files/monetary-policy.htm. A shorter, educators piece"),
    ("https://doi.org/10.1016/j.crm.2021.100387.", "2004 was", "https://doi.org/10.1016/j.crm.2021.100387. 2004 was"),
    ("https://doi.org/10.1016/j.crm.2021.100387.", "45.", "https://doi.org/10.1016/j.crm.2021.100387. 45."),
    ("the variable snake_", "case name", "the variable snake_ case name"),
    ("See section 3.", "4 of the", "See section 3. 4 of the"),
    ("the ratio x=", "3 and", "the ratio x= 3 and"),
    ("visit www.fed.gov.", "“Quoted”", "visit www.fed.gov. “Quoted”"),
    ("pages A.PK/.(...", "- PerCenl", "pages A.PK/.(... - PerCenl"),
    ("OCR l.t/ff", ".J'.7", "OCR l.t/ff .J'.7"),
    ("at www.faa.gov", "-based rules", "at www.faa.gov -based rules"),
    ("the Oct.-", "Nov. report", "the Oct.- Nov. report"),
    ("rates rose 20%", "in 2004", "rates rose 20% in 2004"),
    ("the office (NACO)—", "www.faa.gov", "the office (NACO)— www.faa.gov"),
])
func lineBrokenInsideAnAddressJoinsWithoutASpace(left: String, right: String, joined: String) {
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join(left, right, vocabulary: [], page: 1, warnings: &warnings) == joined)
    #expect(LayoutReconstructor.join(InlineText(left), InlineText(right), vocabulary: [], page: 1, warnings: &warnings).text == joined)
    #expect(warnings.isEmpty)
}

@Test func hyphenPolicyStillDecidesLowercaseBreaksInsideAddresses() {
    var warnings: [ConversionWarning] = []
    // The Fed's typesetter hyphenated inside this address: `communi` and `cations` are not book
    // words and `communications` is, so the hyphen goes (#88 decides address hyphens).
    #expect(LayoutReconstructor.join("https://www.federalreserve.gov/monetarypolicy/review-of-monetary-policy-strategy-tools-and-communi-",
        "cations.htm.", vocabulary: ["communications"], page: 1, warnings: &warnings)
        == "https://www.federalreserve.gov/monetarypolicy/review-of-monetary-policy-strategy-tools-and-communications.htm.")
    #expect(warnings.isEmpty)
    // A real hyphen at the break, with no address evidence, stays with the uncertainty warning.
    #expect(LayoutReconstructor.join("https://www.federalreserve.gov/aboutthefed/structure-federal-open-",
        "market-committee.htm.", vocabulary: [], page: 1, warnings: &warnings)
        == "https://www.federalreserve.gov/aboutthefed/structure-federal-open-market-committee.htm.")
    #expect(warnings.map(\.code) == [.uncertainHyphen])
    // Prose hyphens are untouched: a capital or digit after a prose hyphen keeps its space.
    warnings = []
    #expect(LayoutReconstructor.join("the pre-", "Columbian era", vocabulary: [], page: 1, warnings: &warnings) == "the pre- Columbian era")
    #expect(LayoutReconstructor.join("a mid-", "1990s peak", vocabulary: [], page: 1, warnings: &warnings) == "a mid- 1990s peak")
    #expect(LayoutReconstructor.join("state-of-the-", "art", vocabulary: ["stateoftheart"], page: 1, warnings: &warnings) == "state-of-the-art")
}

@Test func trailingAddressNeedsAnAddressShape() {
    #expect(LayoutReconstructor.trailingAddress("at https://www.federalreserve.gov/monetarypolicy/bst_") == "https://www.federalreserve.gov/monetarypolicy/bst_")
    #expect(LayoutReconstructor.trailingAddress("(www.wahiduddin.net/calc/density_") == "www.wahiduddin.net/calc/density_")
    #expect(LayoutReconstructor.trailingAddress("the FSOC website (ffiec.gov/NPW_") == "ffiec.gov/NPW_")
    #expect(LayoutReconstructor.trailingAddress("Charting Office (NACO)—www.faa.") == "www.faa.")
    #expect(LayoutReconstructor.trailingAddress("see “https://www.fed.gov/a_") == "https://www.fed.gov/a_")
    for text in ["the variable snake_", "e.g._", "l.t/ff", "www", "“Quoted”_", "résumé.gov/a_", "3.14/2_"] {
        #expect(LayoutReconstructor.trailingAddress(text) == nil, "\(text)")
    }
}

@Test func faaPage372AddressesAfterAnEmDashRejoinAfterTheirPeriod() throws {
    let fixture = try SourceLayoutFixture.load("faa-372")
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    let page = fixture.content()
    #expect(page.lines.contains { $0.text == "Aeronautical Charting Office (NACO)—www.faa." })
    #expect(page.lines.contains { $0.text == "gov/air_traffic/flight_info/aeronav" })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                            warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: "\n")
    #expect(text.contains("formerly known as the National Aeronautical Charting Office (NACO)—www.faa.gov/air_traffic/flight_info/aeronav"))
    #expect(text.contains("Aeronautical Information Manual (AIM)—www.faa.gov/air_traffic/publications/atpubs/aim/"))
    #expect(!text.contains("www.faa. gov"))
    // #70's slash joins on the same page are unchanged.
    #expect(text.contains("Directory)—www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dafd/search/"))
}

@Test func fedPage37AddressRejoinsAfterItsUnderscore() throws {
    let fixture = try SourceLayoutFixture.load("fed-37")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    let page = fixture.content()
    #expect(page.lines.contains { $0.text == "www.federalreserve.gov/monetarypolicy/bst_" })
    #expect(page.lines.contains { $0.text == "openmarketops.htm." })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                            warnings: &warnings)
    #expect(blocks.contains { $0.text.hasSuffix("More information on LSAPs is available at https://www.federalreserve.gov/monetarypolicy/bst_openmarketops.htm.") })
    #expect(!blocks.contains { $0.text.contains("bst_ openmarketops") })
}
