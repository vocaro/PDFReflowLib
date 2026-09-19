import Foundation
import CoreGraphics
import CoreText
import Testing
#if os(macOS)
import AppKit
private typealias GlyphTestFont = NSFont
#else
import UIKit
private typealias GlyphTestFont = UIFont
#endif
@testable import PDFReflowLib

/// A dingbat font's `ToUnicode` reports code `<004F>` (the bullet's position in Zapf Dingbats,
/// which reads as `l` in the ASCII Dingbats-block offset table) as the letter `l`.
private func dingbatMap() -> String {
    "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n1 beginbfchar\n<004F> <006C>\nendbfchar\nendcmap"
}

/// A non-symbolic Type1 font whose `ToUnicode` reports code `0x5A` ('Z' under WinAnsiEncoding) as
/// lower-case `z`, matching the magazine's small-caps credit (#217). Every other character the
/// test's content stream draws (`Z (D2697-1)`) passes through unchanged.
private func caseMap() -> String {
    var entries: [Character: String] = [:]
    for character in "FRITD26971-() " { entries[character] = String(character) }
    entries["Z"] = "z"
    return simpleFontUnicodeCMap(entries)
}

private func simpleFontUnicodeCMap(_ entries: [Character: String]) -> String {
    var body = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n\(entries.count) beginbfchar\n"
    for (code, text) in entries {
        let byte = String(format: "%02X", code.asciiValue!)
        let hex = text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined()
        body += "<\(byte)> <\(hex)>\n"
    }
    return body + "endbfchar\nendcmap"
}

private func glyphPDF(objects: [String], contents: String, fontObjects: [String],
                      fontNames: [String], rotate: Int = 0) throws -> CGPDFDocument {
    var fontEntries = ""
    for (name, ref) in zip(fontNames, 5..<(5 + fontNames.count)) { fontEntries += "/\(name) \(ref) 0 R " }
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate \(rotate) /Resources << /Font << \(fontEntries)>> >> /Contents 4 0 R >>",
        testPDFStream(contents),
    ] + fontObjects)
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider))
}

/// A Type0/Identity-H dingbat font (`WVUHWN+MonotypeSorts`, matching the magazine's actual
/// embedded font), a descendant CIDFontType2 and its ToUnicode stream.
private func dingbatFontObjects() -> [String] {
    [
        "<< /Type /Font /Subtype /Type0 /BaseFont /WVUHWN+MonotypeSorts /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>",
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /WVUHWN+MonotypeSorts /CIDToGIDMap /Identity /FontDescriptor 8 0 R >>",
        testPDFStream(dingbatMap()),
        "<< /Type /FontDescriptor /FontName /WVUHWN+MonotypeSorts /FontFamily (Monotype Sorts) /Flags 4 >>",
    ]
}

/// A non-symbolic Type1 font (`WVUHWN+Helvetica-Condensed`, matching the magazine's actual
/// embedded font) with `/CharSet` listing `Z` but not `z`.
private func caseFontObjects(flags: Int = 32, charSet: String? = "(/F/R/I/T/Z/space/parenleft/parenright)") -> [String] {
    let descriptor = charSet != nil
        ? "<< /Type /FontDescriptor /FontName /WVUHWN+Helvetica-Condensed /Flags \(flags) /CharSet \(charSet!) >>"
        : "<< /Type /FontDescriptor /FontName /WVUHWN+Helvetica-Condensed /Flags \(flags) >>"
    return [
        "<< /Type /Font /Subtype /Type1 /BaseFont /WVUHWN+Helvetica-Condensed /Encoding /WinAnsiEncoding /FontDescriptor 6 0 R /ToUnicode 7 0 R >>",
        descriptor,
        testPDFStream(caseMap()),
    ]
}

@Test func dingbatBulletIsReadThroughItsOwnEncoding() throws {
    let document = try glyphPDF(
        objects: [], contents: "BT /C0 6 Tf 6 0 0 6 275.0787 46.4281 Tm <004F>Tj ET",
        fontObjects: dingbatFontObjects(), fontNames: ["C0"])
    let shows = GlyphIdentityReader.read(try #require(document.page(at: 1)))
    let match = try #require(shows.first)
    #expect(match.reported == "l")
    #expect(match.drawn == "\u{25CF}")
    let rect = CGRect(x: 270, y: 40, width: 20, height: 10)
    let original = NSAttributedString(string: "l")
    let repaired = GlyphIdentityReader.apply(shows, to: original, bounds: rect, allBounds: [rect])
    #expect(repaired.string == "\u{25CF}")
}

@Test func caseDisagreementTrustsTheEncodedCapital() throws {
    let document = try glyphPDF(
        objects: [], contents: "BT /T0 6 Tf 6 0 0 6 62.582 761.1871 Tm (Z \\(D2697-1\\))Tj ET",
        fontObjects: caseFontObjects(), fontNames: ["T0"])
    let shows = GlyphIdentityReader.read(try #require(document.page(at: 1)))
    let match = try #require(shows.first)
    #expect(match.reported == "z (D2697-1)")
    #expect(match.drawn == "Z (D2697-1)")
    let rect = CGRect(x: 30, y: 755, width: 100, height: 10)
    let original = NSAttributedString(string: "BRAD FRITz (D2697-1)")
    let repaired = GlyphIdentityReader.apply(shows, to: original, bounds: rect, allBounds: [rect])
    #expect(repaired.string == "BRAD FRITZ (D2697-1)")
    // The corrected "Z" sits inside "FRITZ", not between word spaces, so it is not flagged as an
    // isolated dingbat-style redraw: NativeTextReader's superscript check is unaffected here.
    #expect(repaired.attribute(GlyphIdentityReader.isolatedAttribute, at: 9, effectiveRange: nil) == nil)
}

@Test func caseDisagreementRequiresNonsymbolicFlagsAndUnlistedReportedGlyph() throws {
    // Symbolic (flags without bit 32, or with bit 4) never vouches for the encoded letter.
    for flags in [0, 4, 36] {
        let document = try glyphPDF(
            objects: [], contents: "BT /T0 6 Tf 6 0 0 6 0 0 Tm (Z)Tj ET",
            fontObjects: caseFontObjects(flags: flags), fontNames: ["T0"])
        #expect(GlyphIdentityReader.read(try #require(document.page(at: 1))).isEmpty)
    }
    // A CharSet that also lists the reported (lower-case) glyph does not disambiguate a case swap.
    let bothListed = try glyphPDF(
        objects: [], contents: "BT /T0 6 Tf 6 0 0 6 0 0 Tm (Z)Tj ET",
        fontObjects: caseFontObjects(charSet: "(/Z/z)"), fontNames: ["T0"])
    #expect(GlyphIdentityReader.read(try #require(bothListed.page(at: 1))).isEmpty)
}

@Test func nonDingbatFontsWithMatchingCaseSupplyNoEvidence() throws {
    // A plain (non-dingbat, non-case-mismatched) font is never a candidate; the page yields none.
    let map = simpleFontUnicodeCMap(["A": "A"])
    let document = try glyphPDF(
        objects: [], contents: "BT /T0 6 Tf 6 0 0 6 0 0 Tm (A)Tj ET",
        fontObjects: [
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>",
            testPDFStream(map),
        ], fontNames: ["T0"])
    #expect(GlyphIdentityReader.read(try #require(document.page(at: 1))).isEmpty)
}

@Test func rotatedPagesAndUnsupportedGeometrySupplyNoEvidence() throws {
    let rotated = try glyphPDF(
        objects: [], contents: "BT /C0 6 Tf 6 0 0 6 0 0 Tm <004F>Tj ET",
        fontObjects: dingbatFontObjects(), fontNames: ["C0"], rotate: 90)
    #expect(GlyphIdentityReader.read(try #require(rotated.page(at: 1))).isEmpty)
}

@Test func applyLeavesTextUnchangedOnAmbiguousOrMissingMatches() throws {
    let document = try glyphPDF(
        objects: [], contents: "BT /C0 6 Tf 6 0 0 6 275.0787 46.4281 Tm <004F>Tj ET",
        fontObjects: dingbatFontObjects(), fontNames: ["C0"])
    let shows = GlyphIdentityReader.read(try #require(document.page(at: 1)))
    let rect = CGRect(x: 270, y: 40, width: 20, height: 10)
    // No occurrence of the reported text in the line.
    #expect(GlyphIdentityReader.apply(shows, to: NSAttributedString(string: "nothing here"),
        bounds: rect, allBounds: [rect]).string == "nothing here")
    // Two lines both claim the show's origin: ambiguous, so neither is rewritten.
    #expect(GlyphIdentityReader.apply(shows, to: NSAttributedString(string: "l"),
        bounds: rect, allBounds: [rect, rect]).string == "l")
    // Two occurrences, neither standing alone between word spaces: still ambiguous.
    #expect(GlyphIdentityReader.apply(shows, to: NSAttributedString(string: "lull"),
        bounds: rect, allBounds: [rect]).string == "lull")
    // Two occurrences that both stand alone between word spaces: still ambiguous.
    #expect(GlyphIdentityReader.apply(shows, to: NSAttributedString(string: "l and l again"),
        bounds: rect, allBounds: [rect]).string == "l and l again")
}

/// The magazine's actual back-cover line: the bullet's reported text (`l`) also spells two
/// letters inside "Follow" (#217). A raw substring count sees three occurrences and would stay
/// ambiguous; the one occurrence that stands alone between word spaces disambiguates it, matching
/// how the misread bullet actually prints (a word space on each side).
@Test func applyResolvesARepeatedReportedLetterByWordSpaceIsolation() throws {
    let document = try glyphPDF(
        objects: [], contents: "BT /C0 6 Tf 6 0 0 6 275.0787 46.4281 Tm <004F>Tj ET",
        fontObjects: dingbatFontObjects(), fontNames: ["C0"])
    let shows = GlyphIdentityReader.read(try #require(document.page(at: 1)))
    let rect = CGRect(x: 270, y: 40, width: 20, height: 10)
    let line = "ars.usda.gov/ar l Follow us at twitter.com/USDA_ARS"
    let repaired = GlyphIdentityReader.apply(shows, to: NSAttributedString(string: line), bounds: rect, allBounds: [rect])
    #expect(repaired.string == "ars.usda.gov/ar \u{25CF} Follow us at twitter.com/USDA_ARS")
    // The replaced bullet is flagged as standing alone between word spaces...
    var isolatedRange = NSRange()
    let flagged = repaired.attribute(GlyphIdentityReader.isolatedAttribute,
        at: repaired.string.distance(from: repaired.string.startIndex, to: repaired.string.range(of: "\u{25CF}")!.lowerBound),
        effectiveRange: &isolatedRange) != nil
    #expect(flagged)
    // ...but the letters inside "Follow" that also spelled the reported text are untouched.
    #expect(repaired.string.contains("Follow"))
}

/// The magazine's substituted dingbat font sits at a different point size than its neighbours, so
/// PDFKit can report a baseline offset for it large enough to cross NativeTextReader's superscript
/// tolerance. A bullet GlyphIdentityReader redrew and found standing alone between word spaces is
/// never read as an inline superscript, however that offset falls; an ordinary raised character
/// elsewhere on the same line is unaffected (#217).
@Test func anIsolatedRedrawnGlyphIsNeverReadAsAnInlineSuperscript() throws {
    let value = NSMutableAttributedString(string: "")
    let key = NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)
    value.append(NSAttributedString(string: "ar ", attributes: [.font: pdfKitGated { GlyphTestFont(name: "Helvetica", size: 11) }!, key: 0]))
    let bulletRange = NSRange(location: value.length, length: 1)
    value.append(NSAttributedString(string: "\u{25CF}", attributes: [.font: pdfKitGated { GlyphTestFont(name: "Helvetica", size: 6) }!, key: 4]))
    value.addAttribute(GlyphIdentityReader.isolatedAttribute, value: true, range: bulletRange)
    value.append(NSAttributedString(string: " Follow", attributes: [.font: pdfKitGated { GlyphTestFont(name: "Helvetica", size: 11) }!, key: 0]))
    value.append(NSAttributedString(string: "2", attributes: [.font: pdfKitGated { GlyphTestFont(name: "Helvetica", size: 8) }!, key: 4]))
    let model = NativeTextReader.inlineText(from: value)
    let html = EPUBTextEncoder.inline(model)
    #expect(!html.contains("<sup>\u{25CF}</sup>"))
    #expect(html.contains("\u{25CF}"))
    // Control: an ordinary raised run without the isolated-redraw flag still reads as a superscript.
    #expect(html.contains("<sup>2</sup>"))
}
