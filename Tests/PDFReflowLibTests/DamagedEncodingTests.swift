import Foundation
import CoreText
import PDFKit
import Testing
@testable import PDFReflowLib

// Issue #38: the Census report's LaTeX pages use Type 1C fonts whose Differences names are
// `G<index>` with no ToUnicode, so PDFKit reports every letter shifted by three. The original
// fixture below reproduces that mechanism with a Type3 font whose glyph procedures draw the
// correct letters through Helvetica while its encoding names each code `G<code + 3>`.

private actor RecognizedPages {
    var pages: [Int] = []
    func record(_ event: ConversionProgress) { if event.stage == .recognizing, let page = event.page { pages.append(page) } }
}

/// `mapped` adds a correct ToUnicode CMap, the control that keeps every other object identical.
func shiftedGlyphNamePDF(_ lines: [String], mapped: Bool) -> Data {
    shiftedGlyphNamePDF(pages: [(lines, mapped)])
}

/// One page per entry, each with its own Type3 font; built from raw objects because PDFKit's
/// document writer merges identical font resources when pages are inserted from other documents.
func shiftedGlyphNamePDF(pages: [(lines: [String], mapped: Bool)]) -> Data {
    let helvetica = CTFontCreateWithName("Helvetica" as CFString, 1000, nil)
    func width(_ code: Int) -> Int {
        var character = UniChar(code), glyph = CGGlyph()
        CTFontGetGlyphsForCharacters(helvetica, &character, &glyph, 1)
        return Int(CTFontGetAdvancesForGlyphs(helvetica, .horizontal, &glyph, nil, 1).rounded())
    }
    func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
    }
    // Objects: 1 catalog, 2 pages, 3 Helvetica, then per page: page, content, font, encoding,
    // CharProcs, one glyph procedure per code, the space procedure and the ToUnicode CMap.
    var objects = ["", "", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]
    var kids: [String] = []
    for (lines, mapped) in pages {
        let codes = Set(lines.joined().unicodeScalars.map(\.value).filter { $0 != 32 }).sorted().map(Int.init)
        let base = objects.count + 1
        let page = base, content = base + 1, font = base + 2, encoding = base + 3, charProcs = base + 4
        let procedure = { (code: Int) in base + 5 + codes.firstIndex(of: code)! }
        let space = base + 5 + codes.count, toUnicode = space + 1
        let first = 32, last = codes.max() ?? 32
        let widths = (first...last).map { $0 == 32 ? 278 : codes.contains($0) ? width($0) : 0 }
        kids.append("\(page) 0 R")
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /T \(font) 0 R >> >> /Contents \(content) 0 R >>")
        objects.append(testPDFStream("BT /T 12 Tf 14 TL 20 260 Td " + lines.map { "(\(escaped($0))) '" }.joined(separator: " ") + " ET"))
        objects.append("<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 800] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs \(charProcs) 0 R "
            + "/Encoding \(encoding) 0 R /FirstChar \(first) /LastChar \(last) /Widths [\(widths.map(String.init).joined(separator: " "))] "
            + "/Resources << /Font << /F1 3 0 R >> >>" + (mapped ? " /ToUnicode \(toUnicode) 0 R" : "") + " >>")
        objects.append("<< /Type /Encoding /Differences [32 /space " + codes.map { "\($0) /G\($0 + 3)" }.joined(separator: " ") + "] >>")
        objects.append("<< " + codes.map { "/G\($0 + 3) \(procedure($0)) 0 R" }.joined(separator: " ") + " /space \(space) 0 R >>")
        for code in codes {
            objects.append(testPDFStream("\(width(code)) 0 d0 BT /F1 1000 Tf 0 0 Td (\(escaped(String(UnicodeScalar(code)!)))) Tj ET"))
        }
        objects.append(testPDFStream("278 0 d0"))
        objects.append(testPDFStream("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        /CMapName /ShiftedGlyphNames def /CMapType 2 def
        1 begincodespacerange <00> <FF> endcodespacerange
        \(codes.count + 1) beginbfchar
        \((codes + [32]).map { String(format: "<%02X> <%04X>", $0, $0) }.joined(separator: "\n"))
        endbfchar
        endcmap CMapName currentdict /CMap defineresource pop end end
        """))
    }
    objects[0] = "<< /Type /Catalog /Pages 2 0 R >>"
    objects[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"
    return testPDF(objects: objects)
}

private let sampleLines = ["Two data files were used.", "Data Files", "Schedule D flag and the other fields",
                           "were selected from the public use data set", "and the records having missing values were removed."]

private func fontPDF(font: String, extra: [String] = []) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /F1 5 0 R >> "
            + (extra.isEmpty ? "" : "/XObject << /Fm 6 0 R >> ") + ">> /Contents 4 0 R >>",
        testPDFStream("BT /F1 12 Tf 10 50 Td (Hello) Tj ET" + (extra.isEmpty ? "" : " /Fm Do")),
        font,
    ] + extra)
}

private func hasImage(_ block: ReflowBlock) -> Bool {
    if case .image = block.content { return true } else { return false }
}

@Test func shiftedGlyphNamesWithoutToUnicodeReproduceTheCensusMechanism() throws {
    let damaged = try #require(PDFDocument(data: shiftedGlyphNamePDF(sampleLines, mapped: false)))
    let page = try #require(damaged.page(at: 0))
    let text = try #require(page.string)
    #expect(text.contains("Wzr gdwd ilohv zhuh xvhg1"))
    #expect(TextEncodingCheck.hasUnmappedFont(try #require(page.pageRef)))
    #expect(TextEncodingCheck.isImplausible(text, language: "en"))

    let control = try #require(PDFDocument(data: shiftedGlyphNamePDF(sampleLines, mapped: true)))
    let controlPage = try #require(control.page(at: 0))
    let controlText = try #require(controlPage.string)
    #expect(controlText.contains("Two data files were used."))
    #expect(!TextEncodingCheck.hasUnmappedFont(try #require(controlPage.pageRef)))
    #expect(!TextEncodingCheck.isImplausible(controlText, language: "en"))
}

@Test func fontEvidenceRequiresIndexStyleDifferencesWithoutToUnicode() throws {
    func evidence(_ data: Data) throws -> Bool {
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        return TextEncodingCheck.hasUnmappedFont(try #require(page.pageRef))
    }
    let named = "/Type /Font /Subtype /Type1 /BaseFont /Helvetica"
    #expect(try evidence(fontPDF(font: "<< \(named) /Encoding << /Differences [65 /G68 /G69 /G70] >> >>")))
    // At least half of the names must be index-style: three of five here, two of five below.
    #expect(try evidence(fontPDF(font: "<< /Type /Font /Subtype /TrueType /BaseFont /Arial /Encoding << /Differences [1 /g3 /g4 /g5 /a /b] >> >>")))
    #expect(try !evidence(fontPDF(font: "<< /Type /Font /Subtype /TrueType /BaseFont /Arial /Encoding << /Differences [1 /g3 /g4 /a /b /c] >> >>")))
    #expect(try evidence(fontPDF(font: "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << >> /Encoding << /Differences [63 /c63] >> /FirstChar 63 /LastChar 63 /Widths [1] >>")))
    // Standard names, uniXXXX names, named base encodings, mostly standard names and a ToUnicode map are not evidence.
    #expect(try !evidence(fontPDF(font: "<< \(named) /Encoding << /Differences [65 /a /b /fi /quoteright] >> >>")))
    #expect(try !evidence(fontPDF(font: "<< \(named) /Encoding << /Differences [65 /uni0041 /uni0042 /u1F600] >> >>")))
    #expect(try !evidence(fontPDF(font: "<< \(named) /Encoding /WinAnsiEncoding >>")))
    #expect(try !evidence(fontPDF(font: "<< \(named) /Encoding << /Differences [65 /a /b /c /G68] >> >>")))
    #expect(try !evidence(fontPDF(font: "<< \(named) /Encoding << /Differences [65 /G68 /G69] >> /ToUnicode 6 0 R >>",
        extra: [testPDFStream("BT ET", extra: "/Type /XObject /Subtype /Form /BBox [0 0 1 1]")])))
    #expect(try !evidence(fontPDF(font: "<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H /DescendantFonts [] >>")))
    // Fonts inside a nested Form XObject count.
    #expect(try evidence(fontPDF(font: "<< \(named) /Encoding /WinAnsiEncoding >>",
        extra: [testPDFStream("BT /F2 12 Tf (x) Tj ET", extra: "/Type /XObject /Subtype /Form /BBox [0 0 200 100] /Resources << /Font << /F2 7 0 R >> >>"),
                "<< \(named) /Encoding << /Differences [65 /G68 /G69] >> >>"])))
    for name in ["G108", "g3", "c63", "glyph12", "index5", "cid7", "gid9", "Ab12"] {
        #expect(TextEncodingCheck.isIndexStyleGlyphName(name), "\(name)")
    }
    for name in ["a", "fi", "quoteright", "uni0041", "u1F600", "one", "G", "108", "a1b", "glyph", "period"] {
        #expect(!TextEncodingCheck.isIndexStyleGlyphName(name), "\(name)")
    }
}

@Test func englishPlausibilitySeparatesShiftedTextFromProseTablesIndexesAndOCR() throws {
    let census3 = try SourceLayoutFixture.load("census-3").lines.map(\.text).joined(separator: "\n")
    let census3Statistics = TextEncodingCheck.statistics(of: census3)
    #expect(census3Statistics.words >= 200 && census3Statistics.stopwordRate < 0.01 && census3Statistics.rareBigramRate > 0.5)
    #expect(TextEncodingCheck.isImplausible(census3, language: "en"))
    #expect(TextEncodingCheck.isImplausible(census3, language: "en-US"))
    // Only English statistics are embedded; other declared languages are not judged.
    #expect(!TextEncodingCheck.isImplausible(census3, language: "fr"))
    #expect(!TextEncodingCheck.isImplausible(census3, language: "zh-Hans"))

    let census1 = try SourceLayoutFixture.load("census-1").lines.map(\.text).joined(separator: "\n")
    #expect(!TextEncodingCheck.isImplausible(census1, language: "en"))
    #expect(TextEncodingCheck.statistics(of: census1).stopwordRate > 0.2)
    // Source-derived controls: inherited OCR, answer keys, name tables, a glossary, a numeric table, a comic.
    for name in ["blue-12", "blue-5", "algebra-438", "algebra-471", "911-451", "faa-511", "flag-27", "cdc-5", "911-585", "usgs-1"] {
        let text = try SourceLayoutFixture.load(name).lines.map(\.text).joined(separator: "\n")
        #expect(!TextEncodingCheck.isImplausible(text, language: "en"), Comment(rawValue: name))
    }

    let prose = "The committee reviewed the data files that were used for the assessment and found that the records "
        + "having missing values were removed before the analysis of the public use data set began in the following year."
    #expect(!TextEncodingCheck.isImplausible(prose, language: "en"))
    let shifted = String(prose.unicodeScalars.map { scalar -> Character in
        guard scalar.isASCII, scalar.properties.isAlphabetic else { return Character(scalar) }
        let base: UInt32 = scalar.properties.isUppercase ? 65 : 97
        return Character(UnicodeScalar(base + (scalar.value - base + 3) % 26)!)
    })
    #expect(shifted.hasPrefix("Wkh frpplwwhh"))
    #expect(TextEncodingCheck.isImplausible(shifted, language: "en"))
    // Too few words leave a page unjudged; numbers and punctuation are not words.
    #expect(!TextEncodingCheck.isImplausible("Wzr gdwd ohv zhuh xvhg1 461 Vfkhgxoh G dj", language: "en"))
    #expect(TextEncodingCheck.statistics(of: "12 34 ... ; x").words == 0)
}

@Test func bundledFixturesAndControlsCarryNoDamagedEncodingEvidence() throws {
    for name in ["prose", "scanned", "columns", "graphics", "lists-code", "rotated"] {
        let url = Bundle.module.resourceURL!.appendingPathComponent("fixtures/\(name).pdf")
        let document = try #require(PDFDocument(url: url))
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            #expect(!TextEncodingCheck.hasUnmappedFont(try #require(page.pageRef)), "\(name) page \(index + 1)")
            #expect(!TextEncodingCheck.isImplausible(page.string ?? "", language: "en"), "\(name) page \(index + 1)")
        }
    }
}

@Test func damagedEncodingIsFlaggedRetainedOrRecognizedByPolicy() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("shifted.pdf")
    try shiftedGlyphNamePDF(sampleLines, mapped: false).write(to: source)
    for policy in [ConversionOptions.OCRPolicy.never, .automatic, .automaticIncludingImageBackedText, .always] {
        var options = ConversionOptions(); options.ocr = policy
        let log = RecognizedPages()
        let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
            workspace: dir.appendingPathComponent("work-\(policy)"), progress: { await log.record($0) })
        let warning = try #require(result.warnings.first { $0.code == .damagedTextEncoding })
        #expect(warning.page == 1)
        #expect(warning.message.contains("no usable Unicode mapping"))
        #expect(result.warnings.filter { $0.code == .damagedTextEncoding }.count == 1)
        #expect(result.reflowedPageCount == 1)
        #expect(result.document.assets.count == 1)
        #expect(result.document.blocks.contains(where: hasImage))
        let text = result.document.blocks.map(\.text).joined(separator: "\n")
        if policy == .never {
            #expect(await log.pages.isEmpty)
            #expect(result.recognizedPageCount == 0)
            #expect(warning.message.contains("retained") && warning.message.contains("source-page image"))
            #expect(text.contains("Wzr gdwd ilohv zhuh xvhg1"))
            #expect(!result.warnings.contains { $0.code == .ocrUsed })
        } else {
            #expect(await log.pages == [1])
            #expect(result.recognizedPageCount == 1)
            #expect(warning.message.contains("Recognition of the page image replaces it"))
            #expect(result.warnings.contains { $0.code == .ocrUsed && $0.page == 1 })
            #expect(text.contains("Two data files were used"), "\(policy): \(text)")
            #expect(!text.contains("Wzr"))
        }
    }
}

@Test func damagedEncodingWithoutReferencesReportsTheOmittedImage() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("shifted.pdf")
    try shiftedGlyphNamePDF(sampleLines, mapped: false).write(to: source)
    var options = ConversionOptions(); options.ocr = .never; options.referenceImages = .never
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    let warning = try #require(result.warnings.first { $0.code == .damagedTextEncoding })
    #expect(warning.message.contains("supplementary references are disabled"))
    #expect(result.warnings.contains { $0.code == .referenceImageOmitted && $0.page == 1 })
    #expect(result.document.assets.isEmpty)
    #expect(result.reflowedPageCount == 1)
    let decoded = try JSONDecoder().decode(ConversionWarning.self, from: JSONEncoder().encode(warning))
    #expect(decoded == warning)
}

@Test func mappedEncodingControlKeepsNativeTextUnderEveryPolicy() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("mapped.pdf")
    try shiftedGlyphNamePDF(sampleLines, mapped: true).write(to: source)
    for policy in [ConversionOptions.OCRPolicy.never, .automatic, .automaticIncludingImageBackedText] {
        var options = ConversionOptions(); options.ocr = policy
        let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
            workspace: dir.appendingPathComponent("work-\(policy)"), progress: { _ in })
        #expect(!result.warnings.contains { $0.code == .damagedTextEncoding || $0.code == .ocrUsed || $0.code == .referenceImageOmitted })
        #expect(result.recognizedPageCount == 0)
        #expect(result.reflowedPageCount == 1)
        #expect(result.document.assets.isEmpty)
        #expect(result.document.blocks.map(\.text).joined(separator: "\n").contains("Two data files were used."))
    }
}

@Test func onlyTheDamagedPageOfAMixedBookIsFlaggedAndReferenced() async throws {
    // A clean page followed by a damaged page: only the damaged page is flagged, retained and referenced.
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("mixed.pdf")
    try shiftedGlyphNamePDF(pages: [(sampleLines, true), (sampleLines, false)]).write(to: source)
    var options = ConversionOptions(); options.ocr = .never
    options.removeRepeatedHeadersAndFooters = false
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.warnings.filter { $0.code == .damagedTextEncoding }.map(\.page) == [2])
    #expect(result.reflowedPageCount == 2)
    #expect(result.document.assets.count == 1)
    #expect(result.document.blocks.filter(hasImage).map(\.page) == [2])
    let pageOne = result.document.blocks.filter { $0.page == 1 }.map(\.text).joined(separator: "\n")
    let pageTwo = result.document.blocks.filter { $0.page == 2 }.map(\.text).joined(separator: "\n")
    #expect(pageOne.contains("Two data files were used.") && !pageOne.contains("Wzr"))
    #expect(pageTwo.contains("Wzr gdwd ilohv zhuh xvhg1") && !pageTwo.contains("Two data"))
}
