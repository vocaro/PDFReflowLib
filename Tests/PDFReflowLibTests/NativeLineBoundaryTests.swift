import Foundation
import CoreText
import Testing
#if os(macOS)
import AppKit
private typealias BoundaryFont = NSFont
#else
import UIKit
private typealias BoundaryFont = UIFont
#endif
@testable import PDFReflowLib

private func boundaryText(_ values: [(String, Double, Double)], foundationKey: Bool = false) -> InlineText {
    let input = NSMutableAttributedString(string: "")
    for (text, offset, size) in values {
        input.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { BoundaryFont(name: "Helvetica", size: size) }!,
            (foundationKey ? .baselineOffset : NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)): offset,
        ]))
    }
    return NativeTextReader.inlineText(from: input)
}

@Test func dgaSourceBaselineRestoresTitleWordBoundary() throws {
    let source = try SourceLayoutFixture.load("dga-1")
    let title = try #require(source.attributedLines.first { $0.text == "GuidelinesFor Americans" })
    let model = NativeTextReader.inlineText(from: title.attributedString())
    #expect(model.text == "Guidelines For Americans")
    #expect(!EPUBTextEncoder.inline(model).contains("<sup>"))
    #expect(!EPUBTextEncoder.inline(model).contains("<sub>"))
}

@Test(arguments: [false, true])
func nativeCombinedLinesGetBoundariesWithEitherBaselineKey(foundationKey: Bool) {
    let model = boundaryText([("First", 24, 12), ("second", 12, 12), ("third", 0, 12)], foundationKey: foundationKey)
    #expect(model.text == "First second third")
    #expect(EPUBTextEncoder.inline(model) == "First second third")
}

@Test func existingWhitespaceAndLineEndHyphensDoNotGainExtraSpaces() {
    for (left, right, expected) in [("First ", "second", "First second"),
                                    ("First", "\nsecond", "First\nsecond"),
                                    ("well-", "known", "well-known"),
                                    ("soft\u{00ad}", "ware", "soft\u{00ad}ware")] {
        #expect(boundaryText([(left, 12, 12), (right, 0, 12)]).text == expected)
    }
}

@Test func oppositeInlineScriptsDoNotBecomeWordBoundaries() {
    let model = boundaryText([("x", 0, 12), ("upper", 8, 12), ("lower", -8, 12), ("base", 0, 12)])
    #expect(model.text == "xupperlowerbase")
    #expect(EPUBTextEncoder.inline(model).contains("<sup>upper</sup><sub>lower</sub>"))
}

@Test func dropCapsAndOrdinaryStyleRunsDoNotSplitWords() {
    #expect(boundaryText([("I", 24, 36), ("nitial", 0, 12)]).text == "Initial")
    #expect(boundaryText([("con", 0, 12), ("tinu", 0.1, 12), ("ation", 0, 12)]).text == "continuation")
    #expect(boundaryText([("single", 24, 12)]).text == "single")
}

@Test func uncertainSpacingWithinOneSourceRunStaysUnchanged() throws {
    let source = try SourceLayoutFixture.load("dga-1")
    for phrase in ["Protein, Dair y", "Ve getables"] {
        let line = try #require(source.attributedLines.first { $0.text == phrase })
        #expect(NativeTextReader.inlineText(from: line.attributedString()).text == phrase)
    }
}

@Test func flagSourceNegativeBaselineRestoresHeadingWordBoundary() throws {
    let source = try SourceLayoutFixture.load("flag-31")
    let title = try #require(source.attributedLines.first { $0.text == "How to Obtain a Burial Flagfor a Veteran" })
    let model = NativeTextReader.inlineText(from: title.attributedString())
    #expect(model.text == "How to Obtain a Burial Flag for a Veteran")
    #expect(!EPUBTextEncoder.inline(model).contains("<sub>"))
}
