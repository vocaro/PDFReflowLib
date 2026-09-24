import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/157"))
func ourFlagSourceSoftHyphensSurvivePDFKitLineLoss() throws {
    let fixture = try SourceLayoutFixture.load("flag-5")
    #expect(fixture.sourceSHA256 == "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8")
    let document = try #require(PDFDocument(url: URL(fileURLWithPath: "corpus/cache/CDOC-108hdoc97.pdf")))
    let page = try #require(document.page(at: 4))
    let reference = try #require(page.pageRef)
    let shows = DiscretionaryHyphenReader.read(reference)
    let lines = fixture.attributedLines
    let bounds = lines.map { line in
        let values = line.rect!
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    let restored = DiscretionaryHyphenReader.explicitSoftHyphenLines(
        shows: shows, texts: lines.map(\.text), bounds: bounds)
    #expect(shows.filter { $0.text?.contains("\u{00AD}") == true }.count == 3)
    #expect(restored.count == 3)
    #expect(restored.allSatisfy { !lines[$0].text.contains("\u{00AD}") })
    let extracted = try NativeTextReader.lines(on: page, limit: 100_000)
    #expect(extracted.contains { $0.text.hasSuffix("bom\u{00AD}") })
    #expect(extracted.contains { $0.text.hasSuffix("follow\u{00AD}") })
    #expect(extracted.contains { $0.text.hasSuffix("appro\u{00AD}") })
    let first = try #require(shows.firstIndex { $0.text == "\u{00AD}" })
    var missingSource = shows; missingSource[first].text = nil
    #expect(DiscretionaryHyphenReader.explicitSoftHyphenLines(
        shows: missingSource, texts: lines.map(\.text), bounds: bounds).count == 2)
    var wrongContinuation = shows; wrongContinuation[first + 1].text = "other words"
    #expect(DiscretionaryHyphenReader.explicitSoftHyphenLines(
        shows: wrongContinuation, texts: lines.map(\.text), bounds: bounds).count == 2)
    var hardHyphen = lines.map(\.text)
    let firstLine = try #require(restored.first { lines[$0].text.hasSuffix("bom") })
    hardHyphen[firstLine] += "-"
    #expect(DiscretionaryHyphenReader.explicitSoftHyphenLines(
        shows: shows, texts: hardHyphen, bounds: bounds).count == 2)
    var ambiguous = bounds
    ambiguous.insert(contentsOf: [bounds[firstLine], bounds[firstLine + 1]], at: firstLine + 2)
    var repeatedText = lines.map(\.text)
    repeatedText.insert(contentsOf: [lines[firstLine].text, lines[firstLine + 1].text], at: firstLine + 2)
    #expect(DiscretionaryHyphenReader.explicitSoftHyphenLines(
        shows: shows, texts: repeatedText, bounds: ambiguous).count == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/157"))
func ourFlagOtherSourceSoftHyphenPages() throws {
    let document = try #require(PDFDocument(url: URL(fileURLWithPath: "corpus/cache/CDOC-108hdoc97.pdf")))
    let expected: [(Int, [String])] = [
        (9, ["alter"]), (27, ["fab", "rec"]), (46, ["sym", "pop", "obser"]),
        (47, ["real", "mean", "inno"]), (52, ["PEO", "CONSTITU", "occu"]),
    ]
    for (number, endings) in expected {
        let page = try #require(document.page(at: number - 1))
        let extracted = try NativeTextReader.lines(on: page, limit: 100_000)
        let marked = extracted.filter { $0.text.hasSuffix("\u{00AD}") }
        #expect(marked.count == endings.count)
        for ending in endings { #expect(marked.contains { $0.text.hasSuffix(ending + "\u{00AD}") }) }
    }
}

@Test func oneByteScalarRangesRequireCompleteNonoverlappingEvidence() {
    func map(_ body: String) -> [UInt32: String]? {
        DiscretionaryHyphenReader.scalarRangeMap(Data((
            "1 begincodespacerange <00> <ff> endcodespacerange\n" + body
        ).utf8))
    }
    let valid = map("2 beginbfrange <20> <22> <0020> <ad> <ad> <00ad> endbfrange")
    #expect(valid?[0x20] == " ")
    #expect(valid?[0x22] == "\"")
    #expect(valid?[0xAD] == "\u{00AD}")
    #expect(map("1 beginbfrange <20> <22> <0020> <ad> <ad> <00ad> endbfrange") == nil)
    #expect(map("2 beginbfrange <20> <22> <0020> <22> <23> <0041> endbfrange") == nil)
    #expect(map("1 beginbfrange <ad> <ad> <d800> endbfrange") == nil)
    #expect(map("1 beginbfrange <ad> <ad> [<00ad>] endbfrange") == nil)
    #expect(map("1 beginbfrange <ad> <ad> <00ad> endbfrange /Parent usecmap") == nil)
}
