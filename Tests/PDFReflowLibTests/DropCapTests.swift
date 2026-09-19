import Foundation
import Testing
@testable import PDFReflowLib

private func dropCapPage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    for index in page.lines.indices {
        let line = page.lines[index]
        if let source = fixture.attributedLines.first(where: { $0.text == line.text }) {
            page.lines[index] = NativeTextReader.textLine(semantic: line.text, bounds: line.rect,
                attributed: source.attributedString())
        }
    }
    return page
}

private func dropCapBlocks(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

@Test func flagDropCapOpeningPrecedesItsIndentedContinuation() throws {
    let page = try dropCapPage("flag-7")
    let blocks = dropCapBlocks(page)
    let texts = blocks.map(\.text).joined(separator: "\n")
    let opening = try #require(texts.range(of: "he Stars and Stripes originated"))
    let continuation = try #require(texts.range(of: "adopted by the Marine Committee"))
    #expect(opening.lowerBound < continuation.lowerBound)
    #expect(!blocks.contains { if case .heading = $0.content { $0.text.contains("he Stars and Stripes originated") } else { false } })
    let firstLine = try #require(page.lines.first { $0.text.contains("he Stars and Stripes originated") })
    #expect(firstLine.fontSize == 9)
    #expect(!EPUBTextEncoder.inline(firstLine.content).contains("<sub>"))
}

@Test func secondFlagDropCapRetainsBodySemanticsAndGenuineHeading() throws {
    let page = try dropCapPage("flag-31")
    let blocks = dropCapBlocks(page)
    let texts = blocks.map(\.text).joined(separator: "\n")
    let opening = try #require(texts.range(of: "ny honorably discharged veteran"))
    let continuation = try #require(texts.range(of: "The funeral director"))
    #expect(opening.lowerBound < continuation.lowerBound)
    #expect(blocks.contains { if case .heading = $0.content { $0.text == "How to Obtain a Burial Flag for a Veteran" } else { false } })
    #expect(!blocks.contains { if case .heading = $0.content { $0.text.contains("ny honorably") } else { false } })
}

@Test func dropCapInkBoundsRemainAvailableForRegionPreservation() throws {
    let original = try SourceLayoutFixture.load("flag-7").content()
    let normalized = try dropCapPage("flag-7")
    #expect(normalized.lines.map(\.rect) == original.lines.map(\.rect))
    let line = try #require(normalized.lines.first { $0.text.contains("he Stars and Stripes originated") })
    // A graphic touching the bottom of the drop cap must still preserve the entire selection.
    let graphic = CGRect(x: line.rect.minX, y: line.rect.minY, width: 10, height: 5)
    var page = normalized; page.graphics = [graphic]
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(regions.contains { $0.contains(line.rect) })
}

private func opening(_ initial: String = "T ", capSize: Double = 44, offset: Double = -24,
                     continuation: String = "he opening of this paragraph uses a large initial.",
                     bodySize: Double = 9) -> NSAttributedString {
    let result = NSMutableAttributedString(string: initial, attributes: [
        .font: pdfKitGated { PlatformFont(name: "Helvetica", size: capSize) }!, .baselineOffset: offset,
    ])
    result.append(NSAttributedString(string: continuation, attributes: [
        .font: pdfKitGated { PlatformFont(name: "Helvetica", size: bodySize) }!, .baselineOffset: 0,
    ]))
    return result
}

@Test func ordinaryInitialsScriptsAndMultiLetterLabelsAreNotDropCaps() {
    for attributed in [opening(capSize: 9, offset: -3), opening("AB "), opening(offset: 0),
                       opening(offset: 24), opening(continuation: "he"), opening(continuation: "UPPERCASE LABEL") ] {
        let line = NativeTextReader.textLine(semantic: attributed.string,
            bounds: CGRect(x: 40, y: 400, width: 300, height: 45), attributed: attributed)
        #expect(line.fontSize == (attributed.attribute(.font, at: 0, effectiveRange: nil) as! PlatformFont).pointSize)
    }
    let script = NativeTextReader.inlineText(from: opening(capSize: 9, offset: -3))
    #expect(EPUBTextEncoder.inline(script).contains("<sub>T </sub>"))
}


@Test func uncertainRunEvidenceAndMissingNativeStylesDoNotMoveText() {
    let bounds = CGRect(x: 40, y: 400, width: 300, height: 45)
    for mode in 0..<4 {
        let value = NSMutableAttributedString(attributedString: opening())
        if mode == 0 { value.addAttribute(.baselineOffset, value: 3, range: NSRange(location: 2, length: 1)) }
        if mode == 1 { value.addAttribute(.font, value: pdfKitGated { PlatformFont(name: "Helvetica", size: 14) }!, range: NSRange(location: 2, length: 1)) }
        if mode == 2 { value.removeAttribute(.font, range: NSRange(location: 0, length: value.length)) }
        let line = NativeTextReader.textLine(semantic: value.string, bounds: bounds, attributed: mode == 3 ? nil : value)
        #expect(line.readingRect == nil)
        #expect(line.rect == bounds)
        #expect(line.text == value.string)
    }
}

@Test func dropCapReadingPositionTracksOffsetBoundsWithoutChangingText() {
    let attributed = opening()
    for bounds in [CGRect(x: 40, y: 400, width: 300, height: 45),
                   CGRect(x: -30, y: -60, width: 300, height: 45)] {
        let line = NativeTextReader.textLine(semantic: attributed.string, bounds: bounds, attributed: attributed)
        #expect(line.rect == bounds)
        #expect(line.readingRect?.maxY == bounds.maxY)
        #expect(line.readingRect?.height == 9)
        #expect(line.fontSize == 9)
        #expect(line.text == attributed.string)
    }
}


@Test func monospacedAndInsufficientGeometryRetainTheirLayout() {
    let code = NSMutableAttributedString(attributedString: opening())
    code.addAttribute(.font, value: pdfKitGated { PlatformFont(name: "Courier", size: 44) }!, range: NSRange(location: 0, length: 2))
    let line = NativeTextReader.textLine(semantic: code.string,
        bounds: CGRect(x: 40, y: 400, width: 300, height: 45), attributed: code)
    #expect(line.monospaced)
    #expect(line.readingRect == nil)
    #expect(line.fontSize == 44)
    #expect(EPUBTextEncoder.inline(line.content).contains("<sub>T </sub>"))
    let text = opening()
    for rect in [CGRect(x: 40, y: 400, width: 300, height: 9),
                 CGRect(x: 40, y: 400, width: 20, height: 45)] {
        let result = NativeTextReader.textLine(semantic: text.string, bounds: rect, attributed: text)
        #expect(result.readingRect == nil)
        #expect(result.fontSize == 44)
    }
}

@Test func midPageDropCapNoLongerInterruptsHyphenContinuation() throws {
    let page = try dropCapPage("flag-9")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: ["sometimes"], warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: "\n")
    let first = try #require(text.range(of: "first flag of the colonists"))
    let next = try #require(text.range(of: "present Stars and Stripes was the Grand Union Flag, sometimes referred to"))
    #expect(first.lowerBound < next.lowerBound)
    #expect(page.lines.filter { $0.readingRect != nil }.count == 1)
}

@Test func twoDropCapsDoNotConsumeTheNumericTableOrRealHeadings() throws {
    let source = try SourceLayoutFixture.load("flag-27").content()
    let page = try dropCapPage("flag-27")
    #expect(page.lines.filter { $0.readingRect != nil }.count == 2)
    #expect(LayoutReconstructor.graphicsWithLabels(page) == LayoutReconstructor.graphicsWithLabels(source))
    let headings = dropCapBlocks(page).compactMap { block -> String? in
        if case .heading = block.content { return block.text }; return nil
    }
    #expect(headings == ["Care of Your Flag", "Sizes of Flags"])
}

@Test func realFractionsSurviveBesideANormalizedDropCap() throws {
    let page = try dropCapPage("flag-30")
    #expect(page.lines.filter { $0.readingRect != nil }.count == 1)
    let html = page.lines.map { EPUBTextEncoder.inline($0.content) }.joined(separator: "\n")
    #expect(!html.contains("<sub>T </sub>"))
    #expect(html.components(separatedBy: "<sup>1</sup>").count - 1 == 2)
}
