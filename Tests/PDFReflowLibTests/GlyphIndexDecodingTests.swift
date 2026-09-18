import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Issue #143: the Census report's TeX fonts name their glyphs `G<n>`, where n is a position in the
// font program rather than a character, and carry no ToUnicode map. PDFKit reports U+n, so the text
// reads shifted by three letters. `GlyphIndexDecoder` reads each such font's offset from the
// document's own words, and `FontWeightReader.repairIndexGlyphs` rewrites the lines PDFKit read.

// MARK: - Census source fixture

/// Census pages 2, 3, 12, 17 and 20 captured by `measurements/glyph-index-decoding/capture.swift`: font
/// resources (Differences, Widths), graphics states, decoded content streams and PDFKit's lines.
private struct CensusSource: Decodable {
    struct Font: Decodable {
        var resourceName: String
        var subtype: String
        var baseFont: String?
        var firstChar: Int?
        var widths: [Double]?
        var differences: String
    }
    struct Line: Decodable {
        var text: String
        var rect: [Double]
        var bounds: CGRect { CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]) }
    }
    struct Page: Decodable {
        var page: Int
        var fonts: [Font]
        var extGStates: [String: String]
        var operators: String
        var lines: [Line]
    }
    var sourceSHA256: String
    var pages: [Page]

    static func load() throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("fixtures/census-text-operators.json")))
    }

    /// The captured pages as one PDF. Fonts are written without their programs, with a nonsymbolic
    /// descriptor PDFKit needs to read a non-embedded font, and the bitmap Type3 fonts of page 20 as
    /// Type1 fonts with the same encoding; PDFKit reads the names the same way.
    func pdf(pages numbers: [Int]? = nil) -> Data {
        let selected = pages.filter { numbers?.contains($0.page) ?? true }
        var objects = ["<< /Type /Catalog /Pages 2 0 R >>", ""]
        var kids: [String] = []
        for page in selected {
            var fonts: [String] = []
            for font in page.fonts {
                let name = font.baseFont ?? font.resourceName
                objects.append("<< /Type /FontDescriptor /FontName /\(name) /Flags 32 /FontBBox [-50 -250 1050 900] "
                    + "/ItalicAngle 0 /Ascent 700 /Descent -200 /CapHeight 700 /StemV 80 >>")
                var dictionary = "<< /Type /Font /Subtype /Type1 /BaseFont /\(name) /FontDescriptor \(objects.count) 0 R"
                if let first = font.firstChar, let widths = font.widths {
                    dictionary += " /FirstChar \(first) /LastChar \(first + widths.count - 1) /Widths ["
                        + widths.map { String(format: "%g", $0) }.joined(separator: " ") + "]"
                }
                objects.append(dictionary + " /Encoding << /Differences \(font.differences) >> >>")
                fonts.append("/\(font.resourceName) \(objects.count) 0 R")
            }
            objects.append(testPDFStream(page.operators))
            let contents = objects.count
            let states = page.extGStates.sorted { $0.key < $1.key }.map { "/\($0.key) \($0.value)" }.joined(separator: " ")
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << "
                + fonts.joined(separator: " ") + " >> /ExtGState << \(states) >> >> /Contents \(contents) 0 R >>")
            kids.append("\(objects.count) 0 R")
        }
        objects[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"
        return testPDF(objects: objects)
    }
}

private func cgDocument(_ data: Data) throws -> CGPDFDocument {
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider))
}

/// Each captured line of a page repaired as `NativeTextReader` does, with the outcomes.
private func repairedCensusLines(_ page: CensusSource.Page, in document: CGPDFDocument, at index: Int,
                                 decodings: [String: [UInt8: String]])
    throws -> (lines: [String], outcomes: [FontWeightReader.IndexGlyphRepair], abandoned: Int, leftover: Bool) {
    let shows = FontWeightReader.read(try #require(document.page(at: index)), decodings: decodings)
    let bounds = page.lines.map(\.bounds)
    var carry: FontWeightReader.IndexGlyphCarry?
    var lines: [String] = [], outcomes: [FontWeightReader.IndexGlyphRepair] = [], abandoned = 0
    for line in page.lines {
        let repair = FontWeightReader.repairIndexGlyphs(shows, in: NSAttributedString(string: line.text), bounds: line.bounds,
                                                        allBounds: bounds, carry: &carry)
        lines.append(repair.text.string)
        outcomes.append(repair.outcome)
        if repair.abandoned { abandoned += 1 }
    }
    return (lines, outcomes, abandoned, carry != nil)
}

private func key(of baseFont: String, in document: CGPDFDocument) throws -> String {
    for number in 1...document.numberOfPages {
        var fonts: [Int: FontWeightReader.FontInfo] = [:]
        _ = FontWeightReader.read(try #require(document.page(at: number)), fonts: { fonts[$0] = $1 })
        if let font = fonts.values.first(where: { $0.baseFont == baseFont })?.indexGlyphs { return font.key }
    }
    Issue.record("no index-glyph font \(baseFont)")
    return ""
}

@Test func censusTextFontsDecodeThroughTheOffsetTheirOwnWordsEstablish() throws {
    let source = try CensusSource.load()
    #expect(source.sourceSHA256 == (try SourceLayoutFixture.load("census-3")).sourceSHA256)
    let document = try cgDocument(source.pdf())
    let decodings = try GlyphIndexDecoder.read(document, language: "en")
    let roman = try key(of: "FCHKGB+dcr10084", in: document)
    let bold = try key(of: "FCHKCL+dcbx100120", in: document)
    let italic = try key(of: "FCHMDC+dcti10084", in: document)
    // The three EC text fonts are decoded; the math fonts (cmmi, cmr, cmsy, cmex, the bitmap fonts) are not.
    #expect(Set(decodings.keys) == [roman, bold, italic])
    // dcr's Differences: code 30 /G87, 37 /G31, 70 /G19, 71 /G20, 77 /G24, 59 /G30.
    let dcr = try #require(decodings[roman])
    #expect(dcr[30] == "T" && dcr[37] == "\u{FB01}" && dcr[70] == "\u{201C}" && dcr[71] == "\u{201D}")
    #expect(dcr[77] == "\u{2013}" && dcr[59] == "\u{FB00}" && dcr[7] == "." && dcr[13] == ",")
    // Every code the font's Differences names decodes.
    #expect(dcr.count == 80)

    // Offsets: +3 passes; the case-swapped +35 reads the same words in capitals and fails.
    var fonts: [Int: FontWeightReader.FontInfo] = [:], evidence: [String: GlyphIndexDecoder.FontEvidence] = [:]
    for number in 1...document.numberOfPages {
        fonts = [:]
        let shows = FontWeightReader.read(try #require(document.page(at: number)), fonts: { fonts[$0] = $1 })
        GlyphIndexDecoder.collect(shows, fonts: fonts, into: &evidence)
    }
    let words = try #require(evidence[roman]?.words)
    #expect(GlyphIndexDecoder.offset(for: words)?.offset == 3)
    let swapped = GlyphIndexDecoder.candidate(words, offset: 35)
    #expect(swapped.stopwordRate > 0.3 && swapped.rareBigramRate < 0.05 && swapped.lowercaseRate == 0 && !swapped.passes)
    let shifted = GlyphIndexDecoder.candidate(words, offset: 0)
    #expect(shifted.stopwordRate < 0.01 && shifted.rareBigramRate > 0.5 && !shifted.passes)

    // Controls: another declared language establishes nothing, and neither does the table page (12) alone.
    #expect(try GlyphIndexDecoder.read(try cgDocument(source.pdf(pages: [12])), language: "en").isEmpty)
    #expect(try GlyphIndexDecoder.read(document, language: "fr").isEmpty)
    // Page 20 alone: its sentences decode dcr, and its mathematics decodes nothing.
    let math = try cgDocument(source.pdf(pages: [20]))
    #expect(Set(try GlyphIndexDecoder.read(math, language: "en").keys) == [try key(of: "FCHKGB+dcr10084", in: math)])
}

@Test func censusLinesAreRewrittenFromTheirShowsAndMathLinesAreNot() throws {
    let source = try CensusSource.load()
    let document = try cgDocument(source.pdf())
    let decodings = try GlyphIndexDecoder.read(document, language: "en")
    var repaired: [Int: [String]] = [:]
    for (index, page) in source.pages.enumerated() {
        let result = try repairedCensusLines(page, in: document, at: index + 1, decodings: decodings)
        repaired[page.page] = result.lines
        if page.page == 20 {
            // cmmi's `d` and `μ`, cmr's `=` and the display equations are undecoded: every line stays as PDFKit read it.
            #expect(result.outcomes.allSatisfy { $0 == .unrepaired })
            #expect(result.lines == page.lines.map(\.text))
        } else if page.page == 2 {
            // The title's footnote mark (cmmib, a bitmap font) and the typewriter e-mail line (dctt, 63 glyphs)
            // are undecoded; every other line is repaired.
            #expect(result.outcomes.enumerated().filter { $0.element != .repaired }.map(\.offset) == [1, 4])
            #expect(result.lines[0] == "Disclosure risk assessment in perturbative")
            #expect(result.lines[5] == "Abstract. This paper describes methods for data perturbation that in-")
            #expect(result.lines[13] == "1Introduction")
            #expect(result.lines[31] == "Section 5, we give discussion. The ﬁnal section 6 consists of concluding remarks.")
            #expect(result.lines[34] == "to oﬃcial Census Bureau publications. This report is released to inform interested")
        } else {
            #expect(result.outcomes.allSatisfy { $0 == .repaired }, "page \(page.page)")
            #expect(result.abandoned == 0 && !result.leftover, "page \(page.page)")
        }
    }
    // Reviewed against the source pages: ligatures (`ﬁ`, `ﬂ`, `ﬃ`), digits, punctuation and dashes.
    let page3 = try #require(repaired[3])
    #expect(page3[0] == "2DataFiles")
    #expect(page3[1] == "Two data ﬁles were used.")
    #expect(page3[2] == "2.1 Domingo-Ferrer and Mateo-Sanz")
    #expect(page3[4] == "was used by [ 5]. The Data Extraction System (http://www.census.gov/DES)")
    #expect(page3[22] == "12. Aged exemption ﬂag")
    #expect(page3[27] == "The ﬁle also has match code and a variety of identiﬁers and data from the")
    #expect(page3[30] == "suﬃciently well masked so that they cannot easily be used in re-identiﬁcations")
    let page12 = try #require(repaired[12])
    #expect(page12[0] == "Table 2. DomingoDataReidentiﬁcationRates")
    // One show sets a row's label and figures; PDFKit reads them as two lines, and the second spells the rest.
    #expect(page12[18] == "rnkswp05 " && page12[19] == "46.11 47.06 46.66 49.90 50.85 49.45")
    #expect(page12[22] == "rnkswp15 6.11 8.36 5.91 20.87 23.12 30.67")
    let page17 = try #require(repaired[17])
    #expect(page17[3] == "additional scoring metrics and more applications to diﬀerent data situations are")
    #expect(page17[7] == "7 References")
    #expect(page17[11] == "B, 39 (1977) 1–38.")
    // A reference number read as its own line carries its show into the entry's line, whose italic
    // journal title is a show of its own.
    #expect(page17[25] == "[ 6] ")
    #expect(page17[26] == "Fellegi, I. P., and Sunter, A. B.: A Theory for Record Linkage, Journal of the")
    #expect(page17[30] == "ofOﬃcialStatistics, 9, (1993) 383–406.")
    #expect(page17[44] == "[ 12] ")
    #expect(page17[45] == "Lambert, D.: Measures of Disclosure Risk and Harm, JournalofOﬃcialStatistics,")

    // Table pages keep #38's path: page 12's repaired rows form a numeric grid; the prose, numbered
    // fields and references of pages 2, 3 and 17 do not.
    func grid(_ lines: [String]) -> Bool {
        PDFReflowLibPipeline.holdsNumericGrid(lines.map { TextLine(text: $0, rect: .zero, fontSize: 10) })
    }
    #expect(grid(page12))
    for number in [2, 3, 17] { #expect(!grid(try #require(repaired[number])), "page \(number)") }
    #expect(!grid(["rnkswp05 0.8861 0.9620", "rnkswp10 0.2694 0.7287"]))
    #expect(!grid(["Table 2 lists 0.8861 and 0.9620 for the first metric of the rank swap", "a", "b"].map { $0 + " 0.1 0.2 text" }))
    // Negative control: without established characters every line with an index-glyph show is unrepaired.
    for (index, page) in source.pages.enumerated() {
        let result = try repairedCensusLines(page, in: document, at: index + 1, decodings: [:])
        #expect(result.outcomes.allSatisfy { $0 != .repaired }, "page \(page.page)")
        #expect(result.lines == page.lines.map(\.text))
    }
}

@Test func censusWordGapsAreReadFromCompensatedCharacterSpacing() throws {
    let source = try CensusSource.load()
    let document = try cgDocument(source.pdf())
    let decodings = try GlyphIndexDecoder.read(document, language: "en")
    func spaced(_ number: Int, decodings: [String: [UInt8: String]]) throws -> [String] {
        let index = try #require(source.pages.firstIndex { $0.page == number })
        let page = source.pages[index]
        let repaired = try repairedCensusLines(page, in: document, at: index + 1, decodings: decodings).lines
        let evidence = NativeSpacingReader.read(try #require(document.page(at: index + 1)), decodings: decodings)
        let bounds = page.lines.map(\.bounds)
        return zip(repaired, bounds).map { text, rect in
            NativeSpacingReader.apply(evidence, to: NSAttributedString(string: text), bounds: rect, allBounds: bounds).string
        }
    }
    // The heading sets Tc 1.10 em against +1123 between letters; the quad after its number is in-string.
    let page3 = try spaced(3, decodings: decodings)
    #expect(page3[0] == "2 Data Files")
    let page17 = try spaced(17, decodings: decodings)
    // Tc 0.46 em against +446 between letters: a zero adjustment and an in-string pair are word gaps.
    #expect(page17[9] == "[1] Dempster, A. P., Laird, N. M. and Rubin, D. B.: Maximum Likelihood from")
    #expect(page17[30] == "of Oﬃcial Statistics, 9, (1993) 383–406.")
    #expect(page17[10] == "Incomplete Data via the EM Algorithm, Journal of the Royal Statistical Society,")
    let page12 = try spaced(12, decodings: decodings)
    #expect(page12[0] == "Table 2. Domingo Data Reidentiﬁcation Rates")
    // Control: without established characters the shows do not decode and no space is read.
    #expect(try spaced(3, decodings: [:])[0] == "5GdwdIlohv")
}

// MARK: - Rows PDFKit splits inside one show (#149)

/// Each pair of captured lines `NativeTextReader` reads as one (`joinsSplitShow`), keyed by the first
/// line's index, as the joined line's text after spacing evidence.
private func joinedCensusRows(_ source: CensusSource, _ number: Int, in document: CGPDFDocument,
                              decodings: [String: [UInt8: String]]) throws -> [Int: String] {
    let index = try #require(source.pages.firstIndex { $0.page == number })
    let page = source.pages[index]
    let pdfPage = try #require(document.page(at: index + 1))
    let shows = FontWeightReader.read(pdfPage, decodings: decodings)
    let evidence = NativeSpacingReader.read(pdfPage, decodings: decodings)
    let bounds = page.lines.map(\.bounds)
    var carry: FontWeightReader.IndexGlyphCarry?
    var held: Int?, joined: [Int: String] = [:]
    for (offset, line) in page.lines.enumerated() {
        let handed = carry != nil, previous = held
        let text = NSAttributedString(string: line.text)
        let repair = FontWeightReader.repairIndexGlyphs(shows, in: text, bounds: line.bounds, allBounds: bounds, carry: &carry)
        held = repair.outcome == .repaired && carry != nil ? offset : nil
        guard let left = previous, handed, !repair.abandoned, repair.outcome == .repaired, carry == nil,
              let pair = NativeTextReader.joinsSplitShow(NSAttributedString(string: page.lines[left].text), bounds[left],
                                                         text, line.bounds, continuation: repair.text.string, weights: shows,
                                                         allBounds: bounds) else { continue }
        #expect(pair.bounds == bounds[left].union(line.bounds))
        joined[left] = NativeSpacingReader.apply(evidence, to: pair.text, bounds: pair.bounds, allBounds: bounds).string
    }
    return joined
}

@Test func censusReferenceRowsThatOneShowSetsAreReadAsOneLine() throws {
    let source = try CensusSource.load()
    let document = try cgDocument(source.pdf())
    let decodings = try GlyphIndexDecoder.read(document, language: "en")
    // Page 17: PDFKit reads eight reference numbers as lines of their own although one show sets each
    // number with its entry's first line; repair carries the show on, and the two read as one line.
    let page17 = try joinedCensusRows(source, 17, in: document, decodings: decodings)
    #expect(page17.count == 8)
    #expect(page17.values.map { String($0.prefix(while: { $0 != "," })) }.sorted() == [
        "[ 12] Lambert", "[ 3] De Waal", "[ 4] De Waal", "[ 5] Domingo-Ferrer", "[ 6] Fellegi", "[ 7] Fuller", "[ 8] Kim",
        "[2] Dalenius",
    ])
    #expect(page17.values.contains("[2] Dalenius, T. and Reiss, S. P. Data-swapping: A Technique for Disclosure Control"))
    // The italic title's word gaps are read once the joined line owns the whole row's shows.
    #expect(page17.values.contains("[ 12] Lambert, D.: Measures of Disclosure Risk and Harm, Journal of Oﬃcial Statistics,"))
    // Control: the entry's line alone does not own the show that begins at its number, so its
    // shows do not spell it and no word gap is read.
    let index = try #require(source.pages.firstIndex { $0.page == 17 })
    let lines = source.pages[index].lines
    let entry = try #require(lines.firstIndex { $0.text.hasPrefix("Odpehuw") })
    let evidence = NativeSpacingReader.read(try #require(document.page(at: index + 1)), decodings: decodings)
    let alone = "Lambert, D.: Measures of Disclosure Risk and Harm, JournalofOﬃcialStatistics,"
    #expect(NativeSpacingReader.apply(evidence, to: NSAttributedString(string: alone), bounds: lines[entry].bounds,
                                      allBounds: lines.map(\.bounds)).string == alone)
    // Page 12: one show also sets each table row's label and figures, and PDFKit splits them the same way,
    // but a continuation in figures stays a separate piece for the table path.
    #expect(try joinedCensusRows(source, 12, in: document, decodings: decodings).isEmpty)
    // Negative control: without established characters nothing repairs, nothing carries and nothing joins.
    #expect(try joinedCensusRows(source, 17, in: document, decodings: [:]).isEmpty)
}

@Test func continuationsInWordsAreProseAndFiguresAreNot() {
    #expect(NativeTextReader.continuesInWords("Dalenius, T. and Reiss, S. P. Data-swapping: A Technique"))
    #expect(NativeTextReader.continuesInWords("Lambert, D.: Measures of Disclosure Risk and Harm,"))
    #expect(!NativeTextReader.continuesInWords("46.11 47.06 46.66 49.90 50.85 49.45"))
    #expect(!NativeTextReader.continuesInWords("0.8861 0.9620"))
    // Two words of three or more letters are not enough, nor are words drowned in figures.
    #expect(!NativeTextReader.continuesInWords("of Microdata, Survey"))
    #expect(!NativeTextReader.continuesInWords("mean 46.11 47.06 46.66 49.90 median 50.85 49.45 total 0.12"))
    #expect(!NativeTextReader.continuesInWords(""))
}

@Test func censusReferencePageReadsEachEntryAsOneParagraph() async throws {
    let source = try CensusSource.load()
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("census-fixture.pdf")
    try source.pdf().write(to: url)
    var options = ConversionOptions(); options.ocr = .never
    options.removeRepeatedHeadersAndFooters = false
    let result = try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    // Under `.never` the page's lines are read repaired whatever the page-level decision (the rebuilt page,
    // without font programs, keeps #38's warning with or without #149).
    let page = try #require(source.pages.firstIndex { $0.page == 17 }) + 1
    let blocks = result.document.blocks.filter { $0.page == page }.map(\.text)
    #expect(blocks.contains { $0.hasPrefix("[2] Dalenius, T. and Reiss, S. P. Data-swapping:") }, "\(blocks)")
    // PDFKit reads this row whole in the rebuilt page; the captured split is `censusReferenceRowsThatOneShowSets…`'s.
    #expect(blocks.contains { $0.hasPrefix("[ 12] Lambert, D.: Measures of Disclosure Risk and Harm, Journal of Oﬃcial Statistics, 9,") },
            "\(blocks)")
    // No reference number stands alone as a block.
    #expect(!blocks.contains { $0.range(of: #"^\[ ?\d+\]$"#, options: .regularExpression) != nil }, "\(blocks)")
}

// MARK: - Tables and names

@Test func corkAndSharedTablesDecodeOnlyCharactersTheirEncodingsFix() {
    let cork = GlyphIndexDecoder.corkEncoding
    #expect(cork[27] == "\u{FB00}" && cork[28] == "\u{FB01}" && cork[29] == "\u{FB02}" && cork[30] == "\u{FB03}" && cork[31] == "\u{FB04}")
    #expect(cork[16] == "\u{201C}" && cork[17] == "\u{201D}" && cork[21] == "\u{2013}" && cork[22] == "\u{2014}")
    #expect(cork[39] == "\u{2019}" && cork[96] == "\u{2018}" && cork[65] == "A" && cork[127] == "-" && cork[32] == "\u{2423}")
    #expect(cork[128] == "Ă" && cork[159] == "§" && cork[191] == "£" && cork[223] == "SS" && cork[247] == "œ" && cork[255] == "ß")
    // Accents, the compound-word mark and the per-mille zero draw nothing of their own.
    #expect((0...12).allSatisfy { cork[$0] == nil } && cork[23] == nil && cork[24] == nil)
    // Codes whose meaning differs between OT1, T1, standard and WinAnsi encodings are not shared.
    for code in [0, 27, 34, 39, 60, 62, 92, 94, 95, 96, 123, 124, 125, 126, 127, 200] {
        #expect(GlyphIndexDecoder.sharedCharacter(code) == nil, "\(code)")
    }
    for (code, text) in [(65, "A"), (122, "z"), (48, "0"), (46, "."), (44, ","), (40, "("), (93, "]"), (61, "=")] {
        #expect(GlyphIndexDecoder.sharedCharacter(code) == text)
    }
    // An EC or DC name reads through Cork; any other name through the shared set.
    #expect(GlyphIndexDecoder.characters(indexes: [1: 31], offset: 3, baseFont: "ABCDEF+ecrm1000") == [1: "\u{FB01}"])
    #expect(GlyphIndexDecoder.characters(indexes: [1: 31], offset: 3, baseFont: "ABCDEF+cmr10").isEmpty)
    #expect(GlyphIndexDecoder.characters(indexes: [1: 3, 2: 300], offset: 3, baseFont: nil).isEmpty)
    #expect(GlyphIndexDecoder.characters(indexes: [:], names: [5: "space", 6: "quoteright", 7: "bullet"], offset: 3, baseFont: nil)
        == [5: " ", 6: "\u{2019}"])

    #expect(FontWeightReader.glyphIndex("G87") == 87 && FontWeightReader.glyphIndex("g3") == 3)
    #expect(FontWeightReader.glyphIndex("c63") == 63 && FontWeightReader.glyphIndex("C5") == 5)
    for name in ["glyph12", "uni0041", "G", "Gx1", "G1234567", "a1", "cid7", "space"] {
        #expect(FontWeightReader.glyphIndex(name) == nil, "\(name)")
    }
    // PDFKit's characters for index names (measured on macOS 27): U+n for 33–126 and 161–255, else nothing.
    #expect(FontWeightReader.pdfKitText(index: 33) == "!" && FontWeightReader.pdfKitText(index: 126) == "~")
    #expect(FontWeightReader.pdfKitText(index: 161) == "¡" && FontWeightReader.pdfKitText(index: 255) == "ÿ")
    for index in [0, 31, 32, 127, 160, 256, 1000] { #expect(FontWeightReader.pdfKitText(index: index).isEmpty, "\(index)") }
}

// MARK: - Synthetic offsets and line repair

/// Index-glyph words for `text` at `offset`, split at spaces, as `GlyphIndexDecoder.collect` gathers them.
private func words(_ text: String, offset: (Int) -> Int) -> [[Int]: Int] {
    var result: [[Int]: Int] = [:]
    for word in text.split(separator: " ") { result[word.unicodeScalars.map { Int($0.value) + offset(Int($0.value)) }, default: 0] += 1 }
    return result
}

private let prose = "This paper describes methods for data perturbation that include rank swapping and additive noise. "
    + "It also describes enhanced methods of re-identification using probabilistic record linkage. The empirical "
    + "comparisons use variants of the framework for measuring information loss and re-identification risk that were "
    + "introduced by the authors of the other study and the data files that were used in the experiments."

@Test func offsetsNeedEnglishWordsLowercaseLettersAndOneAnswer() {
    #expect(GlyphIndexDecoder.offset(for: words(prose, offset: { _ in 3 }))?.offset == 3)
    #expect(GlyphIndexDecoder.offset(for: words(prose, offset: { _ in 0 }))?.offset == 0)
    #expect(GlyphIndexDecoder.offset(for: words(prose, offset: { _ in -29 }))?.offset == -29)
    // A permutation without a constant offset gives no usable evidence.
    #expect(GlyphIndexDecoder.offset(for: words(prose, offset: { $0 % 2 == 0 ? 3 : 5 })) == nil)
    // Capitals only: the reading 32 below is English lowercase whose punctuation becomes inner capitals.
    let capitals = words(prose.uppercased(), offset: { _ in 3 })
    let lowered = GlyphIndexDecoder.candidate(capitals, offset: -29)
    #expect(lowered.stopwordRate > 0.4 && lowered.rareBigramRate < 0.05 && lowered.lowercaseRate > 0.9 && lowered.innerCapitalRate > 0.02)
    #expect(GlyphIndexDecoder.offset(for: capitals) == nil)
    // Lowercase only (an address font): no capitalized word, no case evidence.
    #expect(GlyphIndexDecoder.offset(for: words(prose.lowercased().filter { $0.isLetter || $0 == " " }, offset: { _ in 3 })) == nil)
    // Too few words, and mathematics: two-letter variable runs that land on function words.
    #expect(GlyphIndexDecoder.offset(for: words("This paper describes methods for data", offset: { _ in 3 })) == nil)
    let variables = Array(repeating: "In at it is on of to be as by an or if", count: 5).joined(separator: " ")
    let candidate = GlyphIndexDecoder.candidate(words(variables, offset: { _ in 3 }), offset: 3)
    #expect(candidate.words >= 20 && candidate.stopwordRate > 0.5 && candidate.rareBigramRate < 0.1 && candidate.lowercaseRate > 0.5)
    #expect(candidate.capitalizedWords > 0 && candidate.innerCapitalRate == 0 && candidate.longWords == 0 && !candidate.passes)
    // Mostly capitals: a heading font's case is not read from a few capitalized words.
    let headings = words(Array(repeating: "SECTION The DATA FILES AND THE RECORDS WERE USED FOR THE ANALYSIS OF THE PUBLIC DATA", count: 3)
        .joined(separator: " "), offset: { _ in 3 })
    let capitalHeadings = GlyphIndexDecoder.candidate(headings, offset: 3)
    #expect(capitalHeadings.words >= 20 && capitalHeadings.longWords >= 10 && capitalHeadings.stopwordRate > 0.1)
    #expect(capitalHeadings.rareBigramRate < 0.1 && capitalHeadings.capitalizedWords > 0 && capitalHeadings.innerCapitalRate == 0)
    #expect(capitalHeadings.lowercaseRate < 0.5 && GlyphIndexDecoder.offset(for: headings) == nil)
}

private func show(_ text: String, x: CGFloat, y: CGFloat = 100, font: String? = "F",
                  dropped: [Int: String] = [:]) -> FontWeightReader.Show {
    // Each character but a space is a glyph whose index is its scalar plus three, and a space is a word
    // gap before the next glyph, as TeX sets it; `dropped` replaces the glyph at that character offset
    // by one PDFKit reports as nothing (index 31) that draws the given text.
    var glyphs: [FontWeightReader.IndexGlyph] = [], gap = true
    for (offset, scalar) in text.unicodeScalars.enumerated() {
        guard scalar != " " else { gap = true; continue }
        let replaced = dropped[offset]
        glyphs.append(.init(code: UInt8(truncatingIfNeeded: scalar.value), index: replaced == nil ? Int(scalar.value) + 3 : 31,
                            wordStart: gap, text: replaced ?? String(scalar)))
        gap = false
    }
    let decoded = text.unicodeScalars.enumerated().map { dropped[$0.offset] ?? String($0.element) }.joined()
    return FontWeightReader.Show(origin: CGPoint(x: x, y: y), size: 10, font: 1, weight: .regular, text: font == nil ? text : decoded,
                                 placed: true, italic: false, glyphs: font == nil ? nil : glyphs, indexFont: font)
}

private func pdfKitView(_ text: String, dropped: Set<Int> = []) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.enumerated().compactMap { offset, scalar in
        dropped.contains(offset) ? nil : scalar == " " ? scalar : UnicodeScalar(scalar.value + 3)
    }))
}

@Test func droppedLigaturesJoinTheirWordAndCarriedGlyphsContinueTheRow() {
    let rect = CGRect(x: 10, y: 95, width: 300, height: 12)
    func repair(_ shows: [FontWeightReader.Show], _ line: String, bounds: CGRect = rect, all: [CGRect]? = nil,
                carry: inout FontWeightReader.IndexGlyphCarry?) -> (String, FontWeightReader.IndexGlyphRepair, Bool) {
        let result = FontWeightReader.repairIndexGlyphs(shows, in: NSAttributedString(string: line), bounds: bounds,
                                                        allBounds: all ?? [bounds], carry: &carry)
        return (result.text.string, result.outcome, result.abandoned)
    }
    var carry: FontWeightReader.IndexGlyphCarry?
    // `different`: the `ff` glyph between `i` and `e` joins the glyph before it.
    let different = show("dixerent", x: 10, dropped: [2: "\u{FB00}"])
    #expect(repair([different], pdfKitView("dixerent", dropped: [2]), carry: &carry) == ("di\u{FB00}erent", .repaired, false))
    // `the final`: the `fi` glyph after a word gap joins the glyph after it.
    let final = show("the xnal", x: 10, dropped: [4: "\u{FB01}"])
    let finalSlots = FontWeightReader.indexGlyphSlots([final])
    #expect(finalSlots?.map { $0.text ?? "" }.joined() == "the\u{FB01}nal")
    #expect(repair([final], pdfKitView("the xnal", dropped: [4]), carry: &carry) == ("the \u{FB01}nal", .repaired, false))
    // A dropped glyph between two word gaps has no word to join.
    let alone = show("a x b", x: 10, dropped: [2: "\u{FB01}"])
    #expect(FontWeightReader.indexGlyphSlots([alone]) == nil)
    #expect(repair([alone], pdfKitView("a x b", dropped: [2]), carry: &carry).1 == .unrepaired)
    // PDFKit's letters must match the glyphs exactly.
    #expect(repair([show("data", x: 10)], "gdwx", carry: &carry) == ("gdwx", .unrepaired, false))
    // A glyph without an established character, and a show in another font that does not decode.
    var undecided = show("data", x: 10)
    undecided.glyphs?[1].text = nil
    #expect(repair([undecided], "gdwd", carry: &carry).1 == .unrepaired)
    #expect(repair([show("data", x: 10), show("x", x: 60, font: nil)], "gdwd x", carry: &carry) == ("data x", .repaired, false))
    var undecodedOther = show("x", x: 60, font: nil)
    undecodedOther.text = nil
    #expect(repair([show("data", x: 10), undecodedOther], "gdwd x", carry: &carry).1 == .unrepaired)
    #expect(carry == nil)

    // A row PDFKit splits: the label line carries the figures to the next line of the row.
    let label = CGRect(x: 10, y: 95, width: 40, height: 12), figures = CGRect(x: 70, y: 95, width: 60, height: 12)
    let row = show("add05 0.79", x: 10)
    #expect(repair([row], pdfKitView("add05 "), bounds: label, all: [label, figures], carry: &carry) == ("add05 ", .repaired, false))
    #expect(carry != nil)
    #expect(repair([row], pdfKitView("0.79"), bounds: figures, all: [label, figures], carry: &carry) == ("0.79", .repaired, false))
    #expect(carry == nil)
    // A carry that no line of its row continues is abandoned.
    let below = CGRect(x: 70, y: 60, width: 60, height: 12)
    _ = repair([row], pdfKitView("add05 "), bounds: label, all: [label, below], carry: &carry)
    #expect(repair([row], "3179", bounds: below, all: [label, below], carry: &carry) == ("3179", .none, true))
    #expect(carry == nil)
    #expect(FontWeightReader.unplacedIndexShows([row, show("x", x: 500, y: 500)], allBounds: [label]) == 1)
}

// MARK: - End to end

/// A PDF of TeX-like shows (one TJ per line, words apart by -333, no space glyph) in Type1 fonts on
/// Helvetica's metrics whose Differences name code c `G<index(c)>`: `F1` at a constant offset of three,
/// `F2` without one. `H` is plain WinAnsi Helvetica. Each page lists (font resource, text) lines.
private func indexGlyphPDF(_ pages: [[(font: String, text: String)]]) -> Data {
    let codes = Set(pages.flatMap { $0 }.flatMap { $0.text.unicodeScalars.map(\.value) }.filter { $0 != 32 }).sorted()
    func differences(_ index: (UInt32) -> UInt32) -> String {
        "[" + codes.map { "\($0) /G\(index($0))" }.joined(separator: " ") + "]"
    }
    // Glyphs named by index have no Helvetica width, so every code is given one.
    let widths = "/FirstChar 0 /LastChar 255 /Widths [" + Array(repeating: "520", count: 256).joined(separator: " ") + "]"
    var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "",
                   "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica \(widths) /Encoding << /Differences \(differences { $0 + 3 }) >> >>",
                   "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica \(widths) /Encoding << /Differences \(differences { $0 % 2 == 0 ? $0 + 7 : $0 + 11 }) >> >>",
                   "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]
    var kids: [String] = []
    for page in pages {
        var content = ""
        for (number, line) in page.enumerated() {
            let words = line.text.split(separator: " ").map { "(\($0))" }
            content += "BT /\(line.font) 11 Tf 1 0 0 1 \(line.font == "H" ? 151 : 72) \(700 - (line.font == "H" ? number - 1 : number) * 16) Tm "
                + "[\(words.joined(separator: " -333 "))] TJ ET\n"
        }
        objects.append(testPDFStream(content))
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R /F2 4 0 R /H 5 0 R >> >> "
            + "/Contents \(objects.count) 0 R >>")
        kids.append("\(objects.count) 0 R")
    }
    objects[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"
    return testPDF(objects: objects)
}

@Test func pagesWhoseIndexGlyphsAllDecodeReflowNativelyUnderEveryPolicy() async throws {
    let prose: [(font: String, text: String)] = [
        ("F1", "This paper describes methods for data perturbation that include rank swapping."),
        ("F1", "It also describes enhanced methods of reidentification using record linkage."),
        ("F1", "The empirical comparisons use variants of the framework for measuring loss."),
        ("F1", "Section 5 gives the discussion and the final section consists of remarks."),
    ]
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("index-glyphs.pdf")
    // Page 2 adds a line in F2, whose names carry no constant offset; page 3 has a line mixing F1 with a mapped font.
    // Page 4 is a table of figures in F1 alone, whose rows no table path reconstructs; with 21 words its
    // shifted text is judged, as Census pages 12 and 15 are.
    let labels = ["rnkswp", "addnoise", "mixadd", "scalmixadd"]
    let table: [(font: String, text: String)] = [("F1", "Table 2. Domingo Data Reidentification Rates")]
        + (0..<16).map { ("F1", "\(labels[$0 % 4])\($0 + 10) 0.\(8861 - $0 * 37) 0.\(9620 - $0 * 41)") }
    try indexGlyphPDF([prose, prose + [("F2", "Masked data set Z")], [("F1", "Figure 2 shows"), ("H", "the masked data.")], table])
        .write(to: url)
    let shifted = try #require(PDFDocument(url: url)?.page(at: 0)?.string)
    #expect(shifted.contains("Wklv sdshu ghvfulehv"))
    for policy in [ConversionOptions.OCRPolicy.never, .automatic] {
        var options = ConversionOptions(); options.ocr = policy
        options.removeRepeatedHeadersAndFooters = false
        let result = try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
            workspace: dir.appendingPathComponent("work-\(policy)"), progress: { _ in })
        let text = { (page: Int) in result.document.blocks.filter { $0.page == page }.map(\.text).joined(separator: "\n") }
        #expect(text(1).contains("This paper describes methods for data perturbation that include rank swapping."), "\(policy): \(text(1))")
        #expect(text(1).contains("Section 5 gives the discussion") && !text(1).contains("Wklv"))
        #expect(text(3).contains("Figure 2 shows the masked data."), "\(policy): \(text(3).debugDescription)")
        // Only the page with an undecodable index font and the table page keep #38's path.
        #expect(result.warnings.filter { $0.code == .damagedTextEncoding }.map(\.page) == [2, 4], "\(policy)")
        if policy == .never {
            #expect(result.recognizedPageCount == 0)
            // Its decodable lines are retained repaired beside the source-page image.
            #expect(text(2).contains("It also describes enhanced methods"), "\(text(2))")
        } else {
            #expect(result.warnings.filter { $0.code == .ocrUsed }.map(\.page) == [2, 4])
        }
    }
    // Control: another declared language decodes nothing, and the shifted text is retained as before.
    var options = ConversionOptions(); options.ocr = .never; options.language = "de"
    options.removeRepeatedHeadersAndFooters = false
    let german = try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
        workspace: dir.appendingPathComponent("work-de"), progress: { _ in })
    #expect(german.document.blocks.filter { $0.page == 1 }.map(\.text).joined().contains("Wklv sdshu"))
}

@Test func theTypeThreeReproducerStaysDamagedBecausePDFKitMergesItsLines() throws {
    // #38's Type3 fixture names each code `G<code + 3>`, so its font decodes; PDFKit reads its five
    // shows as one line with no break between them, which no show's glyphs spell alone.
    let lines = ["Two data files were used.", "Data Files", "Schedule D flag and the other fields",
                 "were selected from the public use data set", "and the records having missing values were removed."]
    let data = shiftedGlyphNamePDF(lines, mapped: false)
    let document = try cgDocument(data)
    let decodings = try GlyphIndexDecoder.read(document, language: "en")
    #expect(decodings.count == 1 && decodings.values.first?[84] == "T" && decodings.values.first?[32] == " ")
    let page = try #require(PDFDocument(data: data)?.page(at: 0))
    let shows = FontWeightReader.read(try #require(page.pageRef), decodings: decodings)
    #expect(FontWeightReader.indexGlyphSlots(shows)?.compactMap(\.text).joined().hasPrefix("Twodatafileswereused.") == true)
    let selection = try #require(page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine())
    #expect(selection.count == 1)
    var carry: FontWeightReader.IndexGlyphCarry?
    let line = try #require(selection.first)
    let repair = FontWeightReader.repairIndexGlyphs(shows, in: try #require(line.attributedString), bounds: line.bounds(for: page),
                                                    allBounds: [line.bounds(for: page)], carry: &carry)
    #expect(repair.outcome == .unrepaired)
}
