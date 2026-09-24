import Foundation
import CoreGraphics
import Testing
@testable import PDFReflowLib

@Test(arguments: [8, 11]) func magazineSourceDiscretionaryHyphens(page: Int) throws {
    let fixture = try SpacingSourceFixture.load("usda-magazine-\(page)")
    let layout = try SourceLayoutFixture.load("usda-magazine-\(page)")
    #expect(fixture.sourceSHA256 == layout.sourceSHA256)
    let document = try fixture.document()
    let shows = DiscretionaryHyphenReader.read(try #require(document.page(at: 1)))
    let lines = layout.attributedLines
    let rects = lines.map { line in let r = line.rect!; return CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) }
    let selected = DiscretionaryHyphenReader.lines(shows: shows, texts: lines.map(\.text), bounds: rects)
    #expect(selected.count == (page == 8 ? 9 : 10))
    let words = Set(selected.values)
    #expect(page == 8 ? words.isSuperset(of: ["pyrethroids", "neonicotinoids"]) : words.contains("assay"))
    // Original source hyphens and styles remain literal until the actual continuation is joined.
    for (index, word) in selected {
        let original = lines[index].attributedString()
        let marked = DiscretionaryHyphenReader.apply(to: original, word: word)
        #expect(marked.string == original.string)
        #expect(NativeTextReader.inlineText(from: marked).sourceDiscretionaryWord == word)
        for position in 0..<original.length {
            let before = original.attributes(at: position, effectiveRange: nil)
            var after = marked.attributes(at: position, effectiveRange: nil)
            after.removeValue(forKey: DiscretionaryHyphenReader.attribute)
            #expect(NSDictionary(dictionary: before).isEqual(to: after))
        }
    }
    if page == 11 {
        let index = try #require(selected.first(where: { $0.value == "assay" })?.key)
        let next = try #require(lines.first(where: { $0.text.hasPrefix("say to test") }))
        let original = lines[index].attributedString()
        let left = NativeTextReader.inlineText(from: DiscretionaryHyphenReader.apply(to: original, word: "assay"))
        let right = NativeTextReader.inlineText(from: next.attributedString())
        var warnings: [ConversionWarning] = []
        let joined = LayoutReconstructor.join(left, right, hyphens: HyphenContext(usesEnglishLexicon: true),
            page: 11, warnings: &warnings)
        #expect(joined.text.contains("bite-protection assay to test"))
        #expect(!joined.text.contains("as-say"))
        #expect(!warnings.contains { $0.code == .uncertainHyphen })
    }
    #expect(!selected.keys.contains { lines[$0].text.hasSuffix("sugar-") || lines[$0].text.hasSuffix("fire-") })
}

private struct BreakPage {
    var shows: [DiscretionaryHyphenReader.Show] = []
    var texts: [String] = []
    var bounds: [CGRect] = []
    var y: CGFloat = 700
    mutating func line(_ text: String, font: Int = 1, x: CGFloat = 40) {
        shows.append(.init(font: font, family: "Example", text: text, origin: CGPoint(x: x, y: y), size: 10, object: 1))
    }
    mutating func pair(_ prefix: String, _ suffix: String, separate: Bool = true) {
        line(prefix + (separate ? "" : "-"))
        if separate { line("-", font: 2, x: 120) }
        texts.append(prefix + "-"); bounds.append(CGRect(x: 40, y: y - 3, width: 90, height: 13))
        y -= 12
        line(suffix)
        texts.append(suffix); bounds.append(CGRect(x: 40, y: y - 3, width: 90, height: 13))
        y -= 28
    }
    init() {
        pair("com", "panies"); pair("infec", "tions"); pair("devel", "opment"); pair("pyre", "throids")
        pair("fire", "resistant", separate: false)
        line("fire-resistant")
        texts.append("fire-resistant"); bounds.append(CGRect(x: 40, y: y - 3, width: 90, height: 13))
    }
    var selected: [Int: String] { DiscretionaryHyphenReader.lines(shows: shows, texts: texts, bounds: bounds) }
}

@Test func discretionaryFontRequiresCompleteIndependentSourceEvidence() {
    let original = BreakPage()
    #expect(original.selected.count == 4)
    for changed in ["−", "•", "-x", ""] {
        var page = original; page.shows[1].text = changed
        #expect(page.selected.isEmpty)
    }
    var page = original; page.texts[0] = "com-panies"
    #expect(page.selected.isEmpty) // An interior hyphen is not a break.
    page = original; page.shows[1].text = nil
    #expect(page.selected.isEmpty) // An unsupported use spoils the resource census.
    page = original; page.shows[1].family = "Other"
    #expect(page.selected.isEmpty)
    page = original; page.shows[2].text = "Pan ies"
    #expect(page.selected.isEmpty)
    page = original; page.bounds.append(page.bounds[0]); page.texts.append(page.texts[0])
    #expect(page.selected.isEmpty) // Shared native ownership.
    page = original; page.shows.removeLast()
    #expect(page.selected.isEmpty) // No independently attested hard compound.
    page = original; page.shows[12].text = "fire"
    #expect(page.selected.isEmpty) // Interior hard hyphens alone cannot distinguish fallback fonts.
    page = original
    for i in [4, 7, 10] { page.shows[i].font = 3 }
    #expect(page.selected.isEmpty) // One separate occurrence proves nothing.
    page = original
    for i in [0, 3, 6] { page.shows[i].text = "xyzq" }
    #expect(page.selected.isEmpty) // No lexical calibration.
}

@Test func sourceBreakMetadataPreservesCompoundAndUnknownContinuationGuards() throws {
    func marked(_ value: String, word: String) -> InlineText {
        let source = NSAttributedString(string: value, attributes: [.underlineStyle: 1])
        return NativeTextReader.inlineText(from: DiscretionaryHyphenReader.apply(to: source, word: word))
    }
    var warnings: [ConversionWarning] = []
    let context = HyphenContext(usesEnglishLexicon: true)
    let left = marked("pyre-", word: "pyrethroids")
    let joined = LayoutReconstructor.join(left, InlineText("throids", style: .italic), hyphens: context, page: 8, warnings: &warnings)
    #expect(joined.text == "pyrethroids")
    #expect(joined.elements == [.text("pyre", .underline), .text("throids", .italic)])
    #expect(joined.sourceDiscretionaryWord == nil)
    #expect(LayoutReconstructor.join(left, InlineText("other"), hyphens: context, page: 8, warnings: &warnings).text == "pyre-other")
    #expect(LayoutReconstructor.join(left, InlineText("throids"), hyphens: HyphenContext(), page: 8, warnings: &warnings).text == "pyre-throids")
    let compoundContext = HyphenContext(vocabulary: ["pyre-throids"], usesEnglishLexicon: true)
    #expect(LayoutReconstructor.join(left, InlineText("throids"), hyphens: compoundContext, page: 8, warnings: &warnings).text == "pyre-throids")
    for (a, b) in [("camera", "man"), ("by", "law"), ("as", "say")] {
        // Plain dictionary evidence retains two independently valid halves.
        #expect(LayoutReconstructor.join(InlineText(a + "-"), InlineText(b), hyphens: context,
            page: 8, warnings: &warnings).text == a + "-" + b)
        // The strict source census is stronger evidence, authorized by the owner policy.
        let candidate = marked(a + "-", word: a + b)
        #expect(LayoutReconstructor.join(candidate, InlineText(b), hyphens: context,
            page: 8, warnings: &warnings).text == a + b)
        // A printed compound wins even when its separate halves and its closed form are known.
        let attested = HyphenContext(vocabulary: [a + "-" + b, a + b], usesEnglishLexicon: true)
        #expect(LayoutReconstructor.join(candidate, InlineText(b), hyphens: attested,
            page: 8, warnings: &warnings).text == a + "-" + b)
    }
    // The source evidence survives ordinary inline serialization and leaves older payloads readable.
    let encoded = try JSONEncoder().encode(left)
    #expect(try JSONDecoder().decode(InlineText.self, from: encoded) == left)
    #expect(try JSONDecoder().decode(InlineText.self, from: Data(#"{"elements":[]}"#.utf8)).sourceDiscretionaryWord == nil)
    var appended = left
    appended.append(InlineText(" trailing"))
    #expect(appended.sourceDiscretionaryWord == nil)
}

private func censusPDF(form: String = "", contentSuffix: String = "") throws -> CGPDFDocument {
    let source = BreakPage()
    var builder = PDFBytes()
    let map = builder.addStream("1 begincodespacerange <00> <FF> endcodespacerange\n95 beginbfchar\n"
        + (32...126).map { String(format: "<%02X> <%04X>", $0, $0) }.joined(separator: "\n") + "\nendbfchar")
    let body = builder.add("<< /Type /Font /Subtype /TrueType /BaseFont /Example /ToUnicode \(map) >>")
    let separate = builder.add("<< /Type /Font /Subtype /TrueType /BaseFont /ABCDEF+Example /ToUnicode \(map) >>")
    let artwork = builder.addStream(form, extra: " /Type /XObject /Subtype /Form /BBox [0 0 612 792]")
    let contents = builder.addStream("BT\n" + source.shows.map { show in
        let point = show.origin!
        return "/\(show.font == 1 ? "B" : "S") 10 Tf 1 0 0 1 \(point.x) \(point.y) Tm (\(show.text!)) Tj"
    }.joined(separator: "\n") + " ET /Art Do " + contentSuffix)
    let parent = builder.reserve()
    let page = builder.add("<< /Type /Page /Parent \(parent) /MediaBox [0 0 612 792] /Resources << /Font << /B \(body) /S \(separate) >> /XObject << /Art \(artwork) >> >> /Contents \(contents) >>")
    builder.fill(parent, "<< /Type /Pages /Kids [\(page)] /Count 1 >>")
    let root = builder.add("<< /Type /Catalog /Pages \(parent) >>")
    let provider = try #require(CGDataProvider(data: builder.data(root: root) as CFData))
    return try #require(CGPDFDocument(provider))
}

@Test func discretionaryCensusIncludesFormUsesAndRefusesUnsupportedOrExcessiveState() throws {
    let source = BreakPage()
    let blank = try censusPDF()
    let shows = DiscretionaryHyphenReader.read(try #require(blank.page(at: 1)))
    #expect(DiscretionaryHyphenReader.lines(shows: shows, texts: source.texts, bounds: source.bounds).count == 4)
    let form = try censusPDF(form: "BT /S 10 Tf 1 0 0 1 40 50 Tm (hard-hyphen) Tj ET")
    let contradictory = DiscretionaryHyphenReader.read(try #require(form.page(at: 1)))
    #expect(contradictory.last?.text == "hard-hyphen")
    #expect(DiscretionaryHyphenReader.lines(shows: contradictory, texts: source.texts, bounds: source.bounds).isEmpty)
    for suffix in ["1 Ts", "3 Tr", "90 Tz", "/Missing gs", "q", "BT /S 10 Tf " + String(repeating: "(-) Tj ", count: 10_001) + "ET"] {
        let document = try censusPDF(contentSuffix: suffix)
        #expect(DiscretionaryHyphenReader.read(try #require(document.page(at: 1))).isEmpty)
    }
}

@Test func discretionaryCensusHonorsCancellation() async {
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        let page = BreakPage()
        return page.selected
    }
    task.cancel()
    #expect(await task.value.isEmpty)
}

@Test func discretionaryCMapSequencesDoNotRelaxGlyphIdentityDecoding() {
    func map(_ value: String) -> Data { Data("1 beginbfchar <0001> <\(value)> endbfchar".utf8) }
    #expect(GlyphIdentityReader.bfCharMap(map("00660069"), codeDigits: 4) == nil)
    #expect(GlyphIdentityReader.bfCharMap(map("00660069"), codeDigits: 4, allowSequences: true)?[1] == "fi")
    #expect(GlyphIdentityReader.bfCharMap(map("D83DDE00"), codeDigits: 4, allowSequences: true)?[1] == "😀")
    for invalid in ["006600", "D83D", "DE00D83D"] {
        #expect(GlyphIdentityReader.bfCharMap(map(invalid), codeDigits: 4, allowSequences: true) == nil)
    }
}
