import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The 9/11 report's hearing lists and Table of Names after #134 (#161): a one-line witness entry as
// wide as its page's widest line still ran into the next, page 457 (no entry long enough to wrap) kept
// its panels fused, page 461's title wrapped from a full-measure first line stayed a paragraph, and the
// Table of Names read every name before every description where a long name left a wide gutter.

private func reflow(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, labelStyles: labelStyles)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

/// The appendix's label style, as the book's page evidence establishes it (#134's three pages).
private func appendixStyles() throws -> Set<LayoutReconstructor.LabelStyle> {
    var counts: [LayoutReconstructor.LabelStyle: Int] = [:]
    for name in ["911-458", "911-460", "911-462"] {
        for style in LayoutReconstructor.labelEvidence(on: try SourceLayoutFixture.load(name).styledContent()) {
            counts[style, default: 0] += 1
        }
    }
    return LayoutReconstructor.labelStyles(from: counts)
}

private func source(_ name: String) throws -> [ReflowBlock] {
    reflow(try SourceLayoutFixture.load(name).styledContent(), labelStyles: try appendixStyles())
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 9, bold: Bool = false) -> TextLine {
    TextLine(content: InlineText(text, style: bold ? .bold : []), rect: CGRect(x: x, y: y, width: width, height: size * 0.9),
             fontSize: size, monospaced: false)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func titleStyles() -> Set<LayoutReconstructor.LabelStyle> {
    [LayoutReconstructor.LabelStyle(line("Title", x: 40, y: 0, width: 20, bold: true), body: 9)]
}

@Test func source911OneLineEntriesAsWideAsTheirPageStandApart() throws {
    let recto = paragraphs(try source("911-463"))
    for witness in ["The Honorable Louis J. Freeh, former Director, Federal Bureau of Investigation",
                    "The Honorable Janet Reno, former Attorney General of the United States",
                    "The Honorable Robert S. Mueller III, Director, Federal Bureau of Investigation",
                    "Maureen Baginski, Executive Assistant Director for Intelligence, Federal Bureau of Investigation",
                    // Wrapped entries stay whole.
                    "The Honorable Samuel R. Berger, former Assistant to the President for National Security Affairs",
                    "Ambassador J. Cofer Black, former Director, Counterterrorism Center, Central Intelligence Agency"] {
        #expect(recto.contains(witness), "\(witness)")
    }
    let verso = paragraphs(try source("911-464"))
    for witness in ["Joseph F. Bruno, Director, New York City Office of Emergency Management",
                    "The Honorable Rudolph W. Giuliani, former Mayor, City of New York",
                    "Adam B. Drucker, Supervisory Special Agent, Federal Bureau of Investigation",
                    "Alan Reiss, former Director, World Trade Center, Port Authority of New York and New Jersey",
                    "National Transportation Safety Board Conference Center, Washington, D.C."] {
        #expect(verso.contains(witness), "\(witness)")
    }
    #expect(verso.filter { $0 == "CIA Officials" }.count == 2)
}

@Test func source911PanelsWithoutAWrappedEntryAreTitledByTheBooksStyle() throws {
    let blocks = try source("911-457")
    #expect(headings(blocks).suffix(3) == ["The Experience of the Attack", "Representatives of the Victims",
                                          "The Attackers, Intelligence, and Counterterrorism Policy"])
    let entries = paragraphs(blocks)
    for witness in ["The Honorable George Pataki, Governor, State of New York",
                    "The Honorable Michael R. Bloomberg, Mayor, City of New York",
                    "Harry Waizer, survivor, Cantor Fitzgerald, LP",
                    "David Lim, Police Department, Port Authority of New York and New Jersey",
                    "Lee Ielpi, Fire Department of New York (retired)",
                    "Allison Vadhan, Families of Flight 93", "Daniel Byman, Georgetown University",
                    "Magnus Ranstorp, University of St. Andrews"] {
        #expect(entries.contains(witness), "\(witness)")
    }
    // The justified paragraph over the list, on the same edge in the body's larger size, stays whole.
    #expect(entries.contains { $0.hasPrefix("The Commission held 12 public hearings") && $0.hasSuffix("testified under oath.") })
    // Negative control: without the book's label style the page has no evidence, and reads as before.
    let plain = reflow(try SourceLayoutFixture.load("911-457").styledContent())
    #expect(!headings(plain).contains("The Attackers, Intelligence, and Counterterrorism Policy"))
    #expect(paragraphs(plain).contains { $0.contains("Harry Waizer") && $0.contains("David Lim") })
}

@Test func source911TitleWrappedFromAFullMeasureLineHeadsItsEntries() throws {
    let blocks = try source("911-461")
    // Hyphenation across the title's lines is resolved later in the pipeline (`joinWordBreaks`).
    #expect(headings(blocks).contains { $0.hasPrefix("Preventive Detention: Use of Immigration Laws") && $0.hasSuffix("to Combat Terrorism") })
    #expect(headings(blocks).contains("Protecting Privacy, Preventing Terrorism"))
    #expect(paragraphs(blocks).contains("Jan Ting, Temple University"))
    #expect(!paragraphs(blocks).contains { $0.contains("Preventive Detention") })
}

@Test func entriesAsWideAsTheEdgeSplitOnlyWhereEntriesOnlyHang() {
    // Two wrapped entries on the edge, and a one-line entry that is the edge's widest line.
    let entries = [line("Richard A. Clarke, former National Coordinator for Counterterrorism,", x: 40, y: 500, width: 250),
                   line("National Security Council", x: 49, y: 489, width: 100),
                   line("John O. Brennan, Director, Terrorist Threat Integration Center,", x: 40, y: 478, width: 230),
                   line("Central Intelligence Agency", x: 49, y: 467, width: 110),
                   line("The Honorable Louis J. Freeh, former Director, Federal Bureau of Investigation", x: 40, y: 456, width: 282),
                   line("The Honorable Janet Reno, former Attorney General of the United States", x: 40, y: 445, width: 264)]
    #expect(paragraphs(reflow(page(entries))).suffix(2) == [
        "The Honorable Louis J. Freeh, former Director, Federal Bureau of Investigation",
        "The Honorable Janet Reno, former Attorney General of the United States"])
    // One wrapped entry is not enough.
    #expect(paragraphs(reflow(page(Array(entries.suffix(4))))).count == 2)
    // An entry that runs on flush in lowercase shows the edge's lines also continue flush.
    let flush = [line("A ragged line on the edge that does not end its thought and", x: 40, y: 434, width: 240),
                 line("continues on the edge in lowercase", x: 40, y: 423, width: 150)]
    #expect(paragraphs(reflow(page(entries + flush))).contains {
        $0.hasPrefix("The Honorable Louis J. Freeh") && $0.contains("Janet Reno") })
    // Lines filling the page's justified measure are prose, and run on.
    let justified = (0..<4).map { index in
        line("Justified prose line number \(index) filling the measure of the page", x: 40, y: 400 - CGFloat(index) * 11, width: 282)
    }
    #expect(paragraphs(reflow(page(Array(entries.prefix(4)) + justified))).last?.hasPrefix("Justified prose line number 0") == true)
    #expect(paragraphs(reflow(page(Array(entries.prefix(4)) + justified))).count == 3)
}

@Test func titledEdgesNeedTwoTitlesInTheBooksStyleAndNoMeasure() {
    let panel = [line("The Experience of the Attack", x: 40, y: 560, width: 119, bold: true),
                 line("Harry Waizer, survivor, Cantor Fitzgerald, LP", x: 40, y: 549, width: 160),
                 line("David Lim, Police Department, Port Authority of New York and New Jersey", x: 40, y: 538, width: 272),
                 line("Lee Ielpi, Fire Department of New York (retired)", x: 40, y: 527, width: 174)]
    let next = [line("The Attackers, Intelligence, and Counterterrorism Policy", x: 40, y: 511, width: 229, bold: true),
                line("Daniel Byman, Georgetown University", x: 40, y: 500, width: 140),
                line("Abraham D. Sofaer, Hoover Institution", x: 40, y: 489, width: 137)]
    #expect(LayoutReconstructor.hangingEntryEdges((panel + next), body: 9, titles: titleStyles()).map(\.titled) == [true])
    let blocks = reflow(page(panel + next), labelStyles: titleStyles())
    #expect(headings(blocks) == ["The Experience of the Attack", "The Attackers, Intelligence, and Counterterrorism Policy"])
    #expect(paragraphs(blocks) == ["Harry Waizer, survivor, Cantor Fitzgerald, LP",
                                   "David Lim, Police Department, Port Authority of New York and New Jersey",
                                   "Lee Ielpi, Fire Department of New York (retired)",
                                   "Daniel Byman, Georgetown University", "Abraham D. Sofaer, Hoover Institution"])
    // Negative controls: one title, no book style, a justified measure in the entries' size, or an
    // entry running on flush in lowercase.
    #expect(LayoutReconstructor.hangingEntryEdges(panel, body: 9, titles: titleStyles()).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges(panel + next, body: 9).isEmpty)
    let measure = (0..<3).map { index in
        line("A justified line of prose number \(index) that fills the measure", x: 40, y: 450 - CGFloat(index) * 11, width: 272)
    }
    #expect(LayoutReconstructor.hangingEntryEdges(panel + next + measure, body: 9, titles: titleStyles()).isEmpty)
    let lowercase = [line("Brian Jenkins, RAND Corporation, and the", x: 40, y: 478, width: 160),
                     line("office of the director", x: 40, y: 467, width: 90)]
    #expect(LayoutReconstructor.hangingEntryEdges(panel + next + lowercase, body: 9, titles: titleStyles()).isEmpty)
}

@Test func source911TableOfNamesReadsEachNameBesideItsDescription() throws {
    // Page 456: a long name leaves a gutter wide enough to cut the page into two columns.
    let last = paragraphs(reflow(try SourceLayoutFixture.load("911-456").styledContent()))
    #expect(Array(last.dropFirst()) == [
        "during the 1990s",
        "Prince Turki bin Faisal", "Saudi intelligence chief prior to 9/11",
        "Ramzi Yousef", "(a.k.a.Abdul Basit) Pakistani; convicted master-mind of and co-conspirator in 1993 WTC bombing and Manila air (Bojinka) plots",
        "Khalid Saeed Ahmad al Zahrani", "Saudi; candidate 9/11 hijacker",
        "Mohammed Haydar Zammar", "German citizen from Syria; jihadist; possible recruiter of Hamburg cell members",
        "Ayman al Zawahiri", "Egyptian; UBL’s deputy and leader of Egyptian Islamic Jihad terrorist group",
        "Hamdan Bin Zayid", "Emirati; Minister of State for Foreign Affairs of the United Arab Emirates",
        "Abu Zubaydah", "see Zein al Abideen Mohamed Hussein"])
    let first = paragraphs(reflow(try SourceLayoutFixture.load("911-450").styledContent()))
    #expect(first.prefix(5) == ["432 APPENDIX", "Roger Cressey", "NSC counterterrorism official, 1999–2001",
                                "Ralph Eberhart", "Commander in Chief, NORAD and U.S. Space Command, 2000–"])
    // Page 451: a name wrapped beside its description's two lines reads whole, then the description.
    let wrapped = paragraphs(reflow(try SourceLayoutFixture.load("911-451").styledContent()))
    #expect(wrapped.suffix(2) == ["Mohammed Farrah Aidid", "Somali warlord who challenged U.S. presence in Somalia in the early 1990s (deceased)"])
}

@Test func namedEntriesNeedNamesNarrowerThanTheirDescriptions() throws {
    func elements(_ lines: [TextLine]) -> [LayoutReconstructor.Element] { lines.map { .init(rect: $0.rect, line: $0) } }
    var rows: [TextLine] = []
    for index in 0..<5 {
        let y = 500 - CGFloat(index) * 22
        rows += [line("Name Number \(index)", x: 40, y: y, width: 70, size: 10),
                 line("A description of the person set beside the name", x: 148, y: y, width: 200, size: 10),
                 line("and its second line in the indent", x: 160, y: y - 11, width: 140, size: 10)]
    }
    let ordered = LayoutReconstructor.namedEntries(elements(rows))?.compactMap(\.line?.text)
    #expect(ordered?.prefix(4) == ["Name Number 0", "A description of the person set beside the name",
                                   "and its second line in the indent", "Name Number 1"])
    // Two prose columns set their lines about equally wide.
    let columns = (0..<8).flatMap { index -> [TextLine] in
        let y = 500 - CGFloat(index) * 11
        return [line("A left column line of prose \(index) set to its measure", x: 40, y: y, width: 190, size: 10),
                line("A right column line of prose \(index) set to its measure", x: 250, y: y, width: 190, size: 10)]
    }
    #expect(LayoutReconstructor.namedEntries(elements(columns)) == nil)
    // Lines standing anywhere but the two edges and their indents are some other layout.
    #expect(LayoutReconstructor.namedEntries(elements(rows + [line("A stray line", x: 100, y: 300, width: 60, size: 10)])) == nil)
    // Project Blue Book page 303 sets two scanned code tables side by side, single-character codes
    // beside their meanings (`0`, `Days`, `5 second and less`): codes are no names.
    let codes = try SourceLayoutFixture.load("blue-303").content().lines.filter { $0.rect.minY > 325 && $0.rect.maxY < 485 }
    #expect(LayoutReconstructor.namedEntries(elements(codes)) == nil)
    // The hearing lists have no descriptions beside their entries.
    for name in ["911-458", "911-463"] {
        let lines = try SourceLayoutFixture.load(name).styledContent().lines
        #expect(LayoutReconstructor.namedEntries(elements(lines)) == nil)
    }
}
