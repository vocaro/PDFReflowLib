import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private func noaaDisplayPage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("noaa-summary-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    struct Capture: Decodable { var nativePage: PageContent }
    return try JSONDecoder().decode(Capture.self,
        from: Data(contentsOf: fixtureURL("noaa-summary-\(number)-layout.json"))).nativePage
}

@Test(arguments: [69, 74, 1061])
func noaaWrappedSummariesRemainWholeParagraphs(number: Int) throws {
    let page = try noaaDisplayPage(number)
    let size: CGFloat = number == 1061 ? 12 : 15
    let summary = page.lines.filter { $0.fontSize == size }.sorted { $0.rect.maxY > $1.rect.maxY }
    #expect(summary.count == (number == 69 ? 4 : number == 74 ? 6 : 11))
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element,"image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    let first = try #require(summary.first), last = try #require(summary.last)
    let paragraph = try #require(blocks.first { block in
        if case .paragraph = block.content { return block.text.hasPrefix(first.text) && block.text.hasSuffix(last.text) }
        return false
    })
    func letters(_ text: String) -> String { text.lowercased().filter(\.isLetter) }
    #expect(letters(paragraph.text) == letters(summary.map(\.text).joined()))
    let headings = blocks.compactMap { block -> String? in
        if case .heading = block.content { return block.text }
        return nil
    }
    #expect(!headings.contains { heading in summary.contains { $0.text == heading } })
    if number == 69 {
        #expect(headings.contains("The Choices That Will Determine the Future"))
        #expect(headings.contains("Societal choices drive greenhouse"))
        #expect(headings.contains("gas emissions"))
    } else if number == 74 {
        for line in page.lines where line.fontSize == 14 { #expect(headings.contains(line.text)) }
    }
    let images = blocks.compactMap { block -> String? in
        if case let .image(image) = block.content { return image.assetID }
        return nil
    }
    #expect(images.count == crops.count)
    #expect(Set(images) == Set(crops.indices.map { "image-\($0)" }))
}

@Test func wrappedDisplayProseNeedsACompleteNativeParagraph() throws {
    let page = try noaaDisplayPage(69)
    let lines = page.lines.filter { $0.fontSize == 15 }.sorted { $0.rect.maxY > $1.rect.maxY }
    func groups(_ lines: [TextLine]) -> [WrappedDisplayProse.Group] {
        WrappedDisplayProse.groups(in: lines, threshold: 12.5)
    }
    #expect(groups(lines).count == 1)
    #expect(groups(lines).first?.lines == lines)
    #expect(groups(Array(lines.prefix(3))).isEmpty)
    #expect(WrappedDisplayProse.groups(in: lines, threshold: 16).isEmpty)
    var intervening = TextLine(text: "A separate tagged unit", rect: lines[1].rect, fontSize: 9)
    intervening.structure = TextStructure(group: 1, order: 0, headingLevel: 0, lineCount: 1)
    #expect(groups(lines + [intervening]).isEmpty)
    for mode in 0..<7 {
        var control = lines
        switch mode {
        case 0:
            control = lines.map { TextLine(content: InlineText($0.text, style: .bold), rect: $0.rect, fontSize: $0.fontSize) }
        case 1, 2:
            for index in control.indices {
                control[index].structure = TextStructure(group: 1, order: 0, headingLevel: mode == 1 ? 2 : 0, lineCount: 4)
            }
        case 3:
            control[0] = TextLine(text: "“" + lines[0].text, rect: lines[0].rect, fontSize: 15)
        case 4:
            control[0] = TextLine(text: "Figure 1. " + lines[0].text, rect: lines[0].rect, fontSize: 15)
        case 5:
            control[0] = TextLine(text: lines[0].text.replacingOccurrences(of: ".", with: ","), rect: lines[0].rect, fontSize: 15)
        default:
            control[2].rect.origin.y -= 7
        }
        #expect(groups(control).isEmpty, "negative control \(mode)")
    }
}

@Test func wrappedDisplayProsePreservesInlineStyles() throws {
    var page = try noaaDisplayPage(69)
    let index = try #require(page.lines.firstIndex { $0.fontSize == 15 })
    let line = page.lines[index]
    page.lines[index] = TextLine(content: InlineText(elements: [.text("The ", []),
        .text("Choices", .italic), .text(String(line.text.dropFirst("The Choices".count)), [])]),
        rect: line.rect, fontSize: line.fontSize)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [],
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    let paragraph = try #require(blocks.first { block in
        if case .paragraph = block.content { return block.text.hasPrefix("The Choices") }
        return false
    })
    #expect(try EPUBTextEncoder.payload(paragraph, imagePaths: [:]).contains("<em>Choices</em>"))
}
