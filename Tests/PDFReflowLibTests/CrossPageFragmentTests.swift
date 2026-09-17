import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Matter outside a page's own text stream must not hide a word the page break cut in half (#107).
// #101 stopped a continuation from vouching for its own join and #148 carried that across a page
// break, but the carried line was replaced by whatever line came last — a folio, a note — and was
// dropped by a running head the book sets in the body's own size. Fixtures are native extraction
// from the checksum-pinned corpus documents, furniture and all, as the pipeline collects them;
// every expected phrase was read against the rendered source page.

private let reportSHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"
private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"
private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"
private let loperSHA256 = "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e"

private func fixturePage(_ name: String, sha256: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256, "\(name) source identity")
    return fixture.styledContent()
}

private func line(_ text: String, size: CGFloat = 10, index: Int) -> TextLine {
    TextLine(text: text, rect: CGRect(x: 72, y: 700 - CGFloat(index) * 14, width: 400, height: 12),
             fontSize: size, monospaced: false)
}

private func synthetic(_ lines: [TextLine], number: Int) -> PageContent {
    PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

// MARK: - the source pages the rule was measured on

@Test func aFolioUnderTheLastBodyLineDoesNotHideAPageBreakInsideAWord() throws {
    // Wallace pages 212 and 213: `…the GCF of the num-` is the page's last body line, the folio
    // `212` is set under it in a smaller size, and page 213 opens `bers using mental math`.
    let first = try fixturePage("algebra-212", sha256: algebraSHA256)
    let second = try fixturePage("algebra-213", sha256: algebraSHA256)
    let body = LayoutReconstructor.bodySize(first.lines)
    let folio = try #require(first.lines.last)
    #expect(folio.text == "212" && abs(folio.fontSize - body) > body * 0.15)
    #expect(first.lines.dropLast().last?.text.hasSuffix("the GCF of the num-") == true)
    #expect(second.lines.first?.text.hasPrefix("bers using mental math") == true)

    let vocabulary = LayoutReconstructor.vocabulary(in: [first, second])
    #expect(!vocabulary.contains("bers"))
    // The folio's own digits were never words, and the rest of the continuation line still is.
    #expect(vocabulary.isSuperset(of: ["using", "mental", "math", "variables"]))
}

@Test func aRunningHeadSetAtTheBodySizeDoesNotHideAPageBreakInsideAWord() throws {
    // The 9/11 report sets `84 THE 9/11 COMMISSION REPORT` within a tenth of the body's size, so
    // the size alone cannot tell it from the page's text; it prints no lowercase letter, and the
    // page's text opens under it with `rorists`, the rest of page 101's `…suspected ter-`.
    let first = try fixturePage("911-101", sha256: reportSHA256)
    let second = try fixturePage("911-102", sha256: reportSHA256)
    let head = try #require(second.lines.first)
    let body = LayoutReconstructor.bodySize(second.lines)
    #expect(head.text == "84 THE 9/11 COMMISSION REPORT")
    #expect(abs(head.fontSize - body) <= body * 0.15 && !head.text.contains(where: \.isLowercase))
    #expect(first.lines.last?.text.hasSuffix("known and suspected ter-") == true)
    #expect(second.lines[1].text.hasPrefix("rorists (some 60,000") == true)

    let vocabulary = LayoutReconstructor.vocabulary(in: [first, second])
    #expect(!vocabulary.contains("rorists"))
    // The book's own `terrorist` stays, and so does the rest of the continuation line.
    #expect(vocabulary.contains("terrorist"))
    #expect(vocabulary.isSuperset(of: ["heard", "mentioned", "hearing"]))
}

@Test func aNoteUnderTheLastBodyLineDoesNotHideAPageBreakInsideAWord() throws {
    // Fed pages 33 and 34: a note in a smaller size closes page 33 under `…Some of these com-`,
    // and page 34 opens with its folio, its running head and then `munications are tied to`.
    // A note is not furniture, so removing furniture would not uncover this break.
    let first = try fixturePage("fed-33", sha256: fedSHA256)
    let second = try fixturePage("fed-34", sha256: fedSHA256)
    let body = LayoutReconstructor.bodySize(first.lines)
    let note = try #require(first.lines.last)
    #expect(note.text == "/monetarypolicy/fomccalendars.htm." && abs(note.fontSize - body) > body * 0.15)
    #expect(first.lines.last(where: { abs($0.fontSize - body) <= body * 0.15 })?.text
        .hasSuffix("avenues for communications. Some of these com-") == true)
    #expect(second.lines[0].text == "30" && second.lines[1].text == "The Fed Explained: What the Central Bank Does")
    #expect(second.lines[2].text.hasPrefix("munications are tied to FOMC") == true)

    let vocabulary = LayoutReconstructor.vocabulary(in: [first, second])
    #expect(!vocabulary.contains("munications"))
    // Page 34 prints `communications` whole two lines further down, so the word itself stays.
    #expect(vocabulary.contains("communications"))
}

@Test func headMatterStandsAsTheLineAboveTheLineBelowIt() throws {
    // Before this change no line before the page's first body-sized line was read as the line
    // above the next, so a break among a page's opening lines was lost wherever the page's own
    // dominant size is set further down — Wallace's worked examples and the Fed's box pages.
    // Here the page's body size is the eight-point note it is mostly set in.
    let page = synthetic([line("either the numerator or denomi-", size: 12, index: 0),
                          line("nator, we cannot divide out common factors.", size: 12, index: 1)]
        + (2..<12).map { line("a note line set in the size this page is mostly set in.", size: 8, index: $0) },
        number: 1)
    #expect(LayoutReconstructor.bodySize(page.lines) == 8)
    let vocabulary = LayoutReconstructor.vocabulary(in: [page])
    #expect(!vocabulary.contains("nator"))
    #expect(vocabulary.isSuperset(of: ["numerator", "divide", "factors"]))

    // Fed page 13 is the ordinary shape the rule must leave alone: its running head stands over
    // five lines of prose, the fifth ending `…private and public charac-` and the sixth opening
    // `teristics, envisioned by`, all inside the page's own body size.
    let fed = try fixturePage("fed-13", sha256: fedSHA256)
    #expect(fed.lines[5].text.hasSuffix("private and public charac-"))
    #expect(fed.lines[6].text.hasPrefix("teristics, envisioned by"))
    let fedVocabulary = LayoutReconstructor.vocabulary(in: [fed])
    #expect(!fedVocabulary.contains("teristics"))
    #expect(fedVocabulary.isSuperset(of: ["envisioned", "creators", "features"]))
}

@Test func aFragmentTheRunningHeadHidDecidesAHyphenLaterInTheBook() throws {
    // Page 228 opens `ing director during the summer` under its running head, continuing page
    // 227's `…Thomas Pickard was the act-`. Counted as a book word, `ing` made both halves of
    // page 344's `grounded, strand-` + `ing tens of thousands` book words, and the report's own
    // rule then kept the hyphen and warned. The source reads `stranding`.
    let before = try fixturePage("911-227", sha256: reportSHA256)
    let after = try fixturePage("911-228", sha256: reportSHA256)
    let page344 = try fixturePage("911-344", sha256: reportSHA256)
    #expect(before.lines.last?.text.hasSuffix("Thomas Pickard was the act-") == true)
    #expect(after.lines[1].text.hasPrefix("ing director during the summer") == true)
    #expect(page344.lines[10].text.hasSuffix("were grounded, strand-"))
    #expect(page344.lines[11].text.hasPrefix("ing tens of thousands"))

    // The report prints `strand` once, on page 240 (`Mihdhar’s decision to strand Hazmi`), and
    // `stranding` only here, so that one inflected form is what vouches for the join (#115).
    let vocabulary = LayoutReconstructor.vocabulary(in: [before, after, page344]).union(["strand"])
    #expect(!vocabulary.contains("ing") && !vocabulary.contains("stranding"))
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("were grounded, strand-", "ing tens of thousands", vocabulary: vocabulary,
                                     page: 344, warnings: &warnings) == "were grounded, stranding tens of thousands")
    #expect(warnings.isEmpty)
    // Negative control: with `ing` a book word again, both halves are words and the hyphen stays.
    var control: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("were grounded, strand-", "ing tens of thousands",
                                     vocabulary: vocabulary.union(["ing"]), page: 344, warnings: &control)
        == "were grounded, strand-ing tens of thousands")
    #expect(control.map(\.code) == [.uncertainHyphen])
}

@Test func theCarriedLineStillStandsPastAnOpinionLine() throws {
    // Loper Bright pages 11 and 12 with their head matter kept, as the pipeline collects them:
    // `…it author-` closes page 11 over a folio-less foot, and page 12 sets two head lines over
    // `izes the Secretary`. #148's case must keep working now that head matter is read.
    let first = try fixturePage("loper-11", sha256: loperSHA256)
    let second = try fixturePage("loper-12", sha256: loperSHA256)
    #expect(second.lines.contains { $0.text == "4 LOPER BRIGHT ENTERPRISES v. RAIMONDO" })
    #expect(second.lines.contains { $0.text == "Opinion of the Court" })
    let vocabulary = LayoutReconstructor.vocabulary(in: [first, second])
    #expect(!vocabulary.contains("izes"))
    #expect(vocabulary.contains("secretary") && vocabulary.contains("opinion"))
}

// MARK: - what the rule must not do

@Test func theCarriedLineIsConsumedByThePagesOwnFirstTextLine() {
    // A page that opens with its own sentence, not a continuation, ends the carry there: a
    // lowercase line further down is an ordinary line start and its word is a book word.
    let pages = [
        synthetic([line("the committee reviewed the request and recom-", index: 0)], number: 1),
        synthetic([
            line("42 THE REPORT", index: 0),
            line("The Secretary said so.", index: 1),
            line("mended action followed later.", index: 2),
        ], number: 2),
    ]
    let vocabulary = LayoutReconstructor.vocabulary(in: pages)
    #expect(vocabulary.contains("mended"))
    // The same page with the continuation where the book prints it: the fragment is skipped.
    let continued = [
        pages[0],
        synthetic([line("42 THE REPORT", index: 0), line("mended action followed later.", index: 1)], number: 2),
    ]
    #expect(!LayoutReconstructor.vocabulary(in: continued).contains("mended"))
}

@Test func onlyALowercaseFragmentWithNoHyphenOfItsOwnIsSkipped() {
    // Controls on the carried line: a capital opening, a compound keeping its own hyphen, and a
    // page whose previous page ended without a break.
    let capital = [
        synthetic([line("the list ran from Able to Zeb-", index: 0)], number: 1),
        synthetic([line("42 THE REPORT", index: 0), line("Ulon closed the roll.", index: 1)], number: 2),
    ]
    #expect(LayoutReconstructor.vocabulary(in: capital).contains("ulon"))
    let compound = [
        synthetic([line("the aircraft held straight-", index: 0)], number: 1),
        synthetic([line("42 THE REPORT", index: 0), line("and-level flight throughout.", index: 1)], number: 2),
    ]
    #expect(LayoutReconstructor.vocabulary(in: compound).contains("and-level"))
    let unbroken = [
        synthetic([line("the aircraft held its heading", index: 0)], number: 1),
        synthetic([line("42 THE REPORT", index: 0), line("throughout the approach.", index: 1)], number: 2),
    ]
    #expect(LayoutReconstructor.vocabulary(in: unbroken).contains("throughout"))
}

@Test func aScriptWithoutCaseReadsAsTextWhereverItIsSet() {
    // A running head is told from the page's text by the capitals it is set in, which only a
    // cased script has. Arabic and Chinese write letters that are no capitals, so their prose
    // ends the carry as any text line does and the rule says nothing new about those books.
    #expect(LayoutReconstructor.isMinuscule("م") && LayoutReconstructor.isMinuscule("联"))
    #expect(!LayoutReconstructor.isMinuscule("R") && !LayoutReconstructor.isMinuscule("7"))
    let pages = [
        synthetic([line("the applicant may file a peti-", index: 0)], number: 1),
        synthetic([line("مرحبا بكم في الولايات المتحدة", index: 0)], number: 2),
        synthetic([line("tion with the office.", index: 0)], number: 3),
    ]
    #expect(LayoutReconstructor.vocabulary(in: pages).contains("tion"))
}

@Test func aPageWithNoTextStreamOfItsOwnCarriesTheWordOn() {
    // A plate between two text pages: its caption-free label is no text stream, so the word the
    // break cut in half is still the word page 3 opens with.
    let pages = [
        synthetic([line("the survey counted every partici-", index: 0)], number: 1),
        synthetic([line("FIGURE 3", size: 10, index: 0)], number: 2),
        synthetic([line("pant twice over.", index: 0)], number: 3),
    ]
    #expect(!LayoutReconstructor.vocabulary(in: pages).contains("pant"))
    // Control: a plate carrying its own prose ends the carry, and `pant` is a word again.
    let captioned = [
        pages[0],
        synthetic([line("Figure 3 counts the households of the region.", index: 0)], number: 2),
        pages[2],
    ]
    #expect(LayoutReconstructor.vocabulary(in: captioned).contains("pant"))
}
