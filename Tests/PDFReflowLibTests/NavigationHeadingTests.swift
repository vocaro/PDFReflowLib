import Foundation
import CoreGraphics
import CoreText
import Testing
#if os(macOS)
import AppKit
private typealias NavigationFont = NSFont
#else
import UIKit
private typealias NavigationFont = UIFont
#endif
@testable import PDFReflowLib

// Navigation headings (#55): a title set over several lines is one heading, a chapter
// opener's pull quote is prose, a contents page's dot-leader entries are neither, and a
// display numeral fused with its title is not a subscript. The Fed Explained pages 5, 8, 14,
// 24 and 25 are checksum-pinned source extractions; controls are synthetic and from other books.

/// The page as the pipeline sees it: lines rebuilt from their attributed runs, so a fused
/// display numeral carries the title's size rather than its own, and a chapter opener's
/// page-sized background graphic cleared as the pipeline clears it for image-backed text.
private func styledPage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    for index in page.lines.indices {
        let line = page.lines[index]
        if let source = fixture.attributedLines.first(where: { $0.text == line.text }) {
            page.lines[index] = NativeTextReader.textLine(semantic: line.text, bounds: line.rect,
                attributed: source.attributedString())
        }
    }
    if page.graphics.contains(where: { $0.width * $0.height > page.bounds.width * page.bounds.height * 0.75 }) {
        page.graphics = []
        page.preservePageReference = true
    }
    return page
}

private func reconstruct(_ page: PageContent) -> [ReflowBlock] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    var blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    LayoutReconstructor.rankHeadingLevels(&blocks)
    return blocks
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

@Test func fedChapterOpenersMergeTitlesAndKeepPullQuotesAsProse() throws {
    let quotes = [
        (8, "1 Overview of the Federal Reserve System",
         "The Federal Reserve performs five key functions in the public interest to promote the health of the U.S. economy and the stability of the U.S. financial system."),
        (14, "2 The Three Key System Entities",
         "The Board of Governors, the Federal Reserve Banks, and the Federal Open Market Committee work together to promote the health of the U.S. economy and the stability of the U.S. financial system."),
        (24, "3 Conducting Monetary Policy",
         "The Federal Reserve sets U.S. monetary policy to promote maximum employment and stable prices in the U.S. economy."),
    ]
    for (number, title, quote) in quotes {
        let page = try styledPage("fed-\(number)")
        let blocks = reconstruct(page)
        #expect(headings(blocks) == [title], "page \(number)")
        #expect(paragraphs(blocks).contains(quote), "page \(number)")
        // The numeral is display type at the title's size, not a subscript of it.
        let heading = try #require(blocks.first { if case .heading = $0.content { true } else { false } })
        #expect(heading.headingSize == 24)
        if case let .heading(_, text, _) = heading.content {
            #expect(!text.elements.contains { if case let .text(_, style) = $0 { style.contains(.subscript) } else { false } })
        }
        // The chapter's own contents list stays prose beneath the quote.
        #expect(paragraphs(blocks).contains { $0.contains("......") })
    }
}

@Test func fedSectionTitleSplitAcrossTwoLinesIsOneHeading() throws {
    let blocks = reconstruct(try styledPage("fed-25"))
    #expect(headings(blocks) == ["The Federal Reserve’s Monetary Policy Mandate and Strategy and Why It Matters"])
    #expect(paragraphs(blocks).contains { $0.hasPrefix("What is monetary policy?") })
    #expect(paragraphs(blocks).contains { $0.hasPrefix("The Federal Reserve was created by Congress in 1913") })
}

@Test func fedContentsPageEntriesAreNotHeadings() throws {
    let blocks = reconstruct(try styledPage("fed-5"))
    #expect(headings(blocks) == ["Contents"])
    let body = paragraphs(blocks)
    #expect(body.contains { $0.hasPrefix("1 Overview of the Federal Reserve System") })
    #expect(body.contains { $0.hasPrefix("7 Promoting Consumer Protection") || $0.hasPrefix("6 Fostering Payment") })
    #expect(body.contains { $0.hasPrefix("The U .S . Approach to Central Banking") })
}

@Test func contentsEntriesEndInDotLeaders() {
    for entry in ["1 Overview of the Federal Reserve System  . . . . . . . . . . ", "The U.S. Approach to Central Banking ......................2",
                  "Notes . . . . . . . . xiv", "Why It Matters ....................................21"] {
        #expect(LayoutReconstructor.isContentsEntry(entry), Comment(rawValue: entry))
    }
    for other in ["Wait...", "An ellipsis . . . in a heading", "Section 2.3.4", "Care of Your Flag", "1.1 INSIDE THE FOUR FLIGHTS",
                  "Notes 449", "3.1"] {
        #expect(!LayoutReconstructor.isContentsEntry(other), Comment(rawValue: other))
    }
    // A lone heading-size contents entry is prose even without two more folio entries.
    var lines = (0..<4).map {
        TextLine(text: "Ordinary body prose remains a paragraph beneath the contents entry on this page.",
                 rect: CGRect(x: 60, y: 500 - CGFloat($0) * 13, width: 420, height: 10), fontSize: 10)
    }
    lines.append(TextLine(text: "1 Overview of the Federal Reserve System . . . . . . . . 1", rect: CGRect(x: 60, y: 600, width: 400, height: 16), fontSize: 14))
    lines.append(TextLine(text: "A Genuine Heading", rect: CGRect(x: 60, y: 660, width: 200, height: 16), fontSize: 14))
    let blocks = reconstruct(PageContent(number: 1, bounds: letter, lines: lines, graphics: []))
    #expect(headings(blocks) == ["A Genuine Heading"])
    #expect(paragraphs(blocks).contains { $0.hasPrefix("1 Overview") })
}

/// Body prose under a heading of `lines`, each line at `size` and `x`, stacked at `leading`.
private func headingPage(_ titles: [(text: String, size: CGFloat, x: CGFloat, width: CGFloat)], leading: CGFloat = 1.2,
                         proseBetween: Bool = false) -> PageContent {
    var lines: [TextLine] = []
    var top: CGFloat = 700
    for (index, title) in titles.enumerated() {
        lines.append(TextLine(text: title.text, rect: CGRect(x: title.x, y: top - title.size, width: title.width, height: title.size * 1.15),
                              fontSize: title.size))
        top -= title.size * leading
        if proseBetween, index == 0 {
            lines.append(TextLine(text: "A paragraph of ordinary prose between the two headings fills its measure here.",
                                  rect: CGRect(x: 60, y: top - 14, width: 420, height: 10), fontSize: 10))
            top -= 20
        }
    }
    lines += (0..<6).map {
        TextLine(text: "Ordinary body prose remains a paragraph beneath the headings of the page as usual.",
                 rect: CGRect(x: 60, y: 500 - CGFloat($0) * 13, width: 420, height: 10), fontSize: 10)
    }
    return PageContent(number: 1, bounds: letter, lines: lines, graphics: [])
}

@Test func stackedHeadingLinesMergeUnlessTheyOpenTheirOwnHeading() throws {
    // A title over two lines, left-aligned; a centred one; a right-aligned one.
    #expect(headings(reconstruct(headingPage([("The Federal Reserve’s Monetary Policy Mandate and", 16, 90, 378), ("Strategy and Why It Matters", 16, 90, 205)])))
            == ["The Federal Reserve’s Monetary Policy Mandate and Strategy and Why It Matters"])
    #expect(headings(reconstruct(headingPage([("How to Obtain a Flag Flown", 18, 140, 330), ("Over the Capitol", 18, 205, 200)])))
            == ["How to Obtain a Flag Flown Over the Capitol"])
    #expect(headings(reconstruct(headingPage([("Fostering Payment and", 20, 250, 250), ("Settlement Safety", 20, 300, 200)])))
            == ["Fostering Payment and Settlement Safety"])
    // A colon ends a first line, not the heading.
    #expect(headings(reconstruct(headingPage([("The Federal Open Market Committee:", 14, 90, 300), ("Selection and Function", 14, 90, 200)])))
            == ["The Federal Open Market Committee: Selection and Function"])
    // Distinct headings: a chapter label at another size, a numbered section beneath a title,
    // a sentence-ending line, prose between, a wide gap, and a different alignment.
    #expect(headings(reconstruct(headingPage([("Chapter 1", 12, 60, 60), ("Introduction to Flying", 24, 60, 300)])))
            == ["Chapter 1", "Introduction to Flying"])
    #expect(headings(reconstruct(headingPage([("WE HAVE SOME PLANES", 16, 60, 250), ("1.1 INSIDE THE FOUR FLIGHTS", 16, 60, 280)])))
            == ["WE HAVE SOME PLANES", "1.1 INSIDE THE FOUR FLIGHTS"])
    #expect(headings(reconstruct(headingPage([("Part II", 16, 60, 80), ("Chapter 3", 16, 60, 80)])))
            == ["Part II", "Chapter 3"])
    #expect(headings(reconstruct(headingPage([("Summary.", 16, 60, 80), ("Next Steps", 16, 60, 120)])))
            == ["Summary.", "Next Steps"])
    #expect(headings(reconstruct(headingPage([("First Heading", 16, 60, 150), ("Second Heading", 16, 60, 150)], proseBetween: true)))
            == ["First Heading", "Second Heading"])
    #expect(headings(reconstruct(headingPage([("First Heading", 16, 60, 150), ("Second Heading", 16, 60, 150)], leading: 3)))
            == ["First Heading", "Second Heading"])
    #expect(headings(reconstruct(headingPage([("Left Heading", 16, 60, 150), ("Indented Heading", 16, 200, 150)])))
            == ["Left Heading", "Indented Heading"])
    // The 9/11 report's split chapter title is one heading above its section label.
    let opening = reconstruct(try SourceLayoutFixture.load("911-19").content())
    #expect(headings(opening).contains { $0.contains("WE HAVE SOME PLANES") })
    #expect(headings(opening).contains("1.1 INSIDE THE FOUR FLIGHTS"))
    #expect(!headings(opening).contains { $0.hasSuffix("WE HAVE") })
}

@Test func pullQuotesAreMultiLineSentencesAndHeadingsAreNot() {
    // Three display lines ending in a period read as one sentence: prose.
    let quote = headingPage([("The Federal Reserve sets U.S. monetary policy to", 14, 167, 293),
                             ("promote maximum employment and stable prices", 14, 167, 297), ("in the U.S. economy.", 14, 167, 121)])
    #expect(headings(reconstruct(quote)).isEmpty)
    #expect(paragraphs(reconstruct(quote)).contains("The Federal Reserve sets U.S. monetary policy to promote maximum employment and stable prices in the U.S. economy."))
    // A title above the quote keeps its heading.
    var titled = quote
    titled.lines.insert(TextLine(text: "3 Conducting Monetary Policy", rect: CGRect(x: 89, y: 720, width: 382, height: 28), fontSize: 24), at: 0)
    #expect(headings(reconstruct(titled)) == ["3 Conducting Monetary Policy"])
    // One heading-size line ending in a period is still a heading, and so are two short ones.
    #expect(headings(reconstruct(headingPage([("Why It Matters.", 16, 60, 150)]))) == ["Why It Matters."])
    #expect(headings(reconstruct(headingPage([("Why It", 16, 60, 60), ("Matters.", 16, 60, 80)]))) == ["Why It Matters."])
    // A two-line title without terminal punctuation merges rather than reflowing.
    #expect(headings(reconstruct(headingPage([("The Federal Reserve performs five key functions", 14, 167, 289),
                                              ("in the public interest for the economy", 14, 167, 260)])))
            == ["The Federal Reserve performs five key functions in the public interest for the economy"])
}

private func runs(_ pieces: [(String, CGFloat, Double)]) -> NSAttributedString {
    let value = NSMutableAttributedString(string: "")
    for (text, size, offset) in pieces {
        value.append(NSAttributedString(string: text, attributes: [
            .font: NavigationFont(name: "Helvetica", size: size)!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
        ]))
    }
    return value
}

@Test func displayNumeralIsNeitherASubscriptNorFusedWithItsTitle() throws {
    // Fed page 8's fused line: the 70-point numeral sits 31.6 points below the 24-point title.
    let fixture = try SourceLayoutFixture.load("fed-8")
    let source = try #require(fixture.attributedLines.first { $0.text == "1Overview of the Federal" })
    let model = NativeTextReader.inlineText(from: source.attributedString())
    #expect(model.text == "1 Overview of the Federal")
    #expect(!EPUBTextEncoder.inline(model).contains("<sub>"))
    let line = NativeTextReader.textLine(semantic: source.text, bounds: CGRect(x: 88.9, y: 636.7, width: 331.4, height: 81.5),
                                         attributed: source.attributedString())
    #expect(line.fontSize == 24)
    #expect(line.readingRect == nil)
    // Real scripts keep their marks: a lowered small run and a raised same-size run, and a
    // raised note marker beside body text gains no space.
    let scripts = NativeTextReader.inlineText(from: runs([("H", 12, 0), ("2", 8, -3), ("O and x", 12, 0), ("2", 12, 4)]))
    let html = EPUBTextEncoder.inline(scripts)
    #expect(html == "H<sub>2</sub>O and x<sup>2</sup>")
    let marker = NativeTextReader.inlineText(from: runs([("the rate", 10, 0), ("12", 4, 2.5)]))
    #expect(EPUBTextEncoder.inline(marker) == "the rate<sup>12</sup>")
    // A numeral on the title's baseline is display type without a boundary of its own; one
    // under twice the title's size keeps the line's size.
    #expect(NativeTextReader.inlineText(from: runs([("1", 70, 0), ("Overview", 24, 0)])).text == "1Overview")
    let modest = NativeTextReader.textLine(semantic: "1 Overview", bounds: CGRect(x: 0, y: 0, width: 200, height: 40),
                                           attributed: runs([("1 ", 36, 0), ("Overview", 24, 0)]))
    #expect(modest.fontSize == 36)
    #expect(NativeTextReader.displayNumeralTitleSize(in: runs([("A", 70, -31), ("Overview", 24, 0)])) == nil)
    #expect(NativeTextReader.displayNumeralTitleSize(in: runs([("12", 48, -20), ("Title", 24, 0), ("small", 12, 0)])) == nil)
}
