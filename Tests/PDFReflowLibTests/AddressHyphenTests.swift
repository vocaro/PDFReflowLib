import Foundation
import Testing
@testable import PDFReflowLib

// A line-end hyphen inside a web address before a lowercase letter is resolved by the book's own
// addresses, not by prose compounds (#88): Fed page 36's `federalreserve.gov/monetary-` +
// `policy/…` is `monetarypolicy` elsewhere in the book, and page 46's `publications/page1-` +
// `econ/…` has no unbroken form, so its hyphen stays with a warning.

private func addressVocabulary(_ lines: [String], words: [String] = []) -> Set<String> {
    var vocabulary = Set(words)
    for line in lines { LayoutReconstructor.addAddressVocabulary(of: line, to: &vocabulary) }
    return vocabulary
}

private func joined(_ left: String, _ right: String, _ vocabulary: Set<String>) -> (String, [ConversionWarning.Code]) {
    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.join(left, right, vocabulary: vocabulary, page: 1, warnings: &warnings)
    var inlineWarnings: [ConversionWarning] = []
    let inline = LayoutReconstructor.join(InlineText(left), InlineText(right), vocabulary: vocabulary, page: 1,
                                          warnings: &inlineWarnings)
    #expect(inline.text == text)
    #expect(inlineWarnings.map(\.code) == warnings.map(\.code))
    return (text, warnings.map(\.code))
}

@Test func addressHyphenIsRemovedWhenTheJoinedAddressIsSeenUnbroken() {
    // Fed 36: the prose vocabulary knows the compound `monetary-policy`, which kept the hyphen.
    let vocabulary = addressVocabulary(["timeline is available at https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm."],
                                       words: ["monetary", "policy", "monetary-policy", "monetarypolicy"])
    let (text, warnings) = joined("time, see https://www.federalreserve.gov/monetary-", "policy/bst_crisisresponse.htm.", vocabulary)
    #expect(text == "time, see https://www.federalreserve.gov/monetarypolicy/bst_crisisresponse.htm.")
    #expect(warnings.isEmpty)
    // 9/11 580: `www.white-` + `house.gov/…` against `whitehouse.gov` elsewhere, with another scheme.
    let house = addressVocabulary(["(online at http://www.whitehouse.gov/news/releases/2002/12/20021211-8.html)."],
                                  words: ["white", "house", "white-house"])
    #expect(joined("Feb. 2003 (online at www.white-", "house.gov/news/releases/2003/02/20030214-7.html).", house).0
        == "Feb. 2003 (online at www.whitehouse.gov/news/releases/2003/02/20030214-7.html).")
}

@Test func addressHyphenIsKeptWhenTheHyphenatedAddressIsSeenUnbroken() {
    // Fed 46: the prose vocabulary holds `econ`, which removed the hyphen.
    let vocabulary = addressVocabulary(["See https://research.stlouisfed.org/publications/page1-econ/2019/01/02/other."],
                                       words: ["page", "econ"])
    let (text, warnings) = joined("https://research.stlouisfed.org/publications/page1-", "econ/2020/08/03/the-feds-new-monetary-policy-tools.", vocabulary)
    #expect(text == "https://research.stlouisfed.org/publications/page1-econ/2020/08/03/the-feds-new-monetary-policy-tools.")
    #expect(warnings.isEmpty)
}

@Test func addressHyphenFallsBackToTheBrokenSegmentSeenInAnyAddress() {
    // The segment `dfa-stress-tests` under another path, and `supervisionreg` under another domain.
    let vocabulary = addressVocabulary(["archived at www.example.gov/old/dfa-stress-tests.pdf and",
                                        "see https://example.org/supervisionreg/index.htm today"],
                                       words: ["dfastress"])
    #expect(joined("https://www.federalreserve.gov/supervisionreg/dfa-", "stress-tests.htm.", vocabulary)
        == ("https://www.federalreserve.gov/supervisionreg/dfa-stress-tests.htm.", []))
    #expect(joined("https://www.federalreserve.gov/supervi-", "sionreg/caletters/caletters.htm.", vocabulary)
        == ("https://www.federalreserve.gov/supervisionreg/caletters/caletters.htm.", []))
}

@Test func addressHyphenWithoutEvidenceIsKeptWithAWarning() {
    // Page 46 with only prose words: neither address form is seen, and `page1` is not a word.
    let prose = addressVocabulary([], words: ["page", "econ", "monetary", "policy", "monetary-policy", "monetarypolicy"])
    #expect(joined("https://research.stlouisfed.org/publications/page1-", "econ/2020/08/03/tools.", prose)
        == ("https://research.stlouisfed.org/publications/page1-econ/2020/08/03/tools.", [.uncertainHyphen]))
    // Page 36 with only prose words: both pieces are words, so nothing says the hyphen is the typesetter's.
    #expect(joined("see https://www.federalreserve.gov/monetary-", "policy/bst_crisisresponse.htm.", prose)
        == ("see https://www.federalreserve.gov/monetary-policy/bst_crisisresponse.htm.", [.uncertainHyphen]))
    // Both forms seen at both levels: undecided.
    let both = addressVocabulary(["a https://a.gov/x/monetarypolicy b", "c https://a.gov/x/monetary-policy d"])
    #expect(joined("https://a.gov/x/monetary-", "policy/y.htm", both) == ("https://a.gov/x/monetary-policy/y.htm", [.uncertainHyphen]))
}

@Test func addressHyphenInsideAWordIsRemovedByTheBookWords() {
    // Fed 27: `communications` is a book word and `communi` is not. `cations` is, as the start of a
    // line after a prose hyphen (`appli-` + `cations`).
    let vocabulary = addressVocabulary([], words: ["communications", "cations", "tools", "and"])
    #expect(joined("https://www.federalreserve.gov/monetarypolicy/review-of-monetary-policy-strategy-tools-and-communi-",
                   "cations.htm.", vocabulary)
        == ("https://www.federalreserve.gov/monetarypolicy/review-of-monetary-policy-strategy-tools-and-communications.htm.", []))
    // Letters beside a digit are not a word's pieces (`page1-` + `econ`, `a-` + `b2`).
    let digits = addressVocabulary([], words: ["econ", "pageecon", "ab"])
    #expect(joined("https://a.org/page1-", "econ/x", digits).1 == [.uncertainHyphen])
    #expect(joined("https://a.org/x/a-", "b2/y", digits).1 == [.uncertainHyphen])
    // A real hyphen between words stays (Fed 36's `timeline-forward-` + `guidance-…`).
    let words = addressVocabulary([], words: ["forward", "guidance", "forwardguidance"])
    #expect(joined("https://www.federalreserve.gov/monetarypolicy/timeline-forward-", "guidance-about-the-federal-funds-rate.htm.", words)
        == ("https://www.federalreserve.gov/monetarypolicy/timeline-forward-guidance-about-the-federal-funds-rate.htm.", [.uncertainHyphen]))
}

@Test func addressEvidenceIgnoresSegmentsThatMayBeBroken() {
    // An address ending its line may continue: its last segment is not evidence.
    let ending = addressVocabulary(["see https://www.federalreserve.gov/monetary-"])
    #expect(joined("x https://www.federalreserve.gov/monetary-", "policy/a.htm", ending).1 == [.uncertainHyphen])
    #expect(ending.contains { $0.hasSuffix("federalreserve.gov") })
    #expect(!ending.contains { $0.hasSuffix("monetary-") || $0.hasSuffix("monetary") })
    // A line's first word without a scheme may be the rest of a broken address (`federalre-` +
    // `serve.gov/…`): its first segment is not evidence, its later segments are.
    let fragment = addressVocabulary(["serve.gov/supervisionreg/srletters/srletters.htm and more"])
    #expect(joined("https://www.re-", "serve.gov/x.htm", fragment).1 == [.uncertainHyphen])
    #expect(joined("https://www.a.gov/supervi-", "sionreg/x.htm", fragment).0 == "https://www.a.gov/supervisionreg/x.htm")
    // After `https://www.` the next line's `federalreserve.gov/monetarypolicy/…` is whole evidence.
    let continued = addressVocabulary(["federalreserve.gov/monetarypolicy/timeline-forward-"])
    #expect(joined("see https://www.federalreserve.gov/monetary-", "policy/bst_crisisresponse.htm.", continued).0
        == "see https://www.federalreserve.gov/monetarypolicy/bst_crisisresponse.htm.")
    // Address entries never answer a prose word lookup.
    #expect(!continued.contains("monetarypolicy"))
    #expect(joined("the monetary-", "policy review", addressVocabulary(["https://a.gov/monetarypolicy/x now"])).0
        == "the monetary-policy review")
}

@Test func proseHyphenPolicyIsUnchanged() {
    #expect(joined("repair of the commu-", "nications link", addressVocabulary([], words: ["communications"]))
        == ("repair of the communications link", []))
    #expect(joined("the monetary-", "policy framework", addressVocabulary([], words: ["monetary-policy", "monetarypolicy"]))
        == ("the monetary-policy framework", []))
    #expect(joined("an unusual cross-", "wind", addressVocabulary([])) == ("an unusual cross-wind", [.uncertainHyphen]))
    // An address hyphen before a digit or capital joins as #79 decides, whatever the evidence says.
    #expect(joined("(online at http://english.daralhayat.com/Spec/02-", "2004/Article", addressVocabulary(["x http://english.daralhayat.com/Spec/022004/y z"]))
        == ("(online at http://english.daralhayat.com/Spec/02-2004/Article", []))
}

@Test func fedPage36AddressHyphenIsTheTypesettersAndPage46sIsReal() throws {
    let page36 = try SourceLayoutFixture.load("fed-36")
    let page46 = try SourceLayoutFixture.load("fed-46")
    #expect(page36.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    #expect(page46.sourceSHA256 == page36.sourceSHA256)
    let content36 = page36.content(), content46 = page46.content()
    #expect(content36.lines.contains { $0.text.hasSuffix("https://www.federalreserve.gov/monetary-") })
    #expect(content36.lines.contains { $0.text == "federalreserve.gov/monetarypolicy/timeline-forward-" })
    #expect(content46.lines.contains { $0.text == "https://research.stlouisfed.org/publications/page1-" })
    // As in the whole book, page 46's `monetary-policy.htm.` puts the compound in the vocabulary,
    // which kept page 36's typesetter hyphen, and its `econ` removed page 46's real one.
    #expect(content46.lines.contains { $0.text == "monetary-policy.htm." })
    let vocabulary = LayoutReconstructor.vocabulary(in: [content36, content46])
    #expect(vocabulary.contains("monetary-policy") && vocabulary.contains("econ"))

    var warnings: [ConversionWarning] = []
    let text36 = LayoutReconstructor.blocks(page: content36, images: [], vocabulary: vocabulary, warnings: &warnings)
        .map(\.text).joined(separator: "\n")
    #expect(text36.contains("time, see https://www.federalreserve.gov/monetarypolicy/bst_crisisresponse.htm."))
    #expect(!text36.contains("monetary-policy/bst_"))
    // The box above it breaks at a real hyphen, with no address evidence either way.
    #expect(text36.contains("https://www.federalreserve.gov/monetarypolicy/timeline-forward-guidance-about-the-federal-funds-rate.htm."))

    warnings = []
    let text46 = LayoutReconstructor.blocks(page: content46, images: [], vocabulary: vocabulary, warnings: &warnings)
        .map(\.text).joined(separator: "\n")
    #expect(text46.contains("https://research.stlouisfed.org/publications/page1-econ/2020/08/03/the-feds-new-monetary-policy-tools."))
    #expect(!text46.contains("page1econ"))
    #expect(warnings.contains { $0.code == .uncertainHyphen && $0.page == content46.number })
}
