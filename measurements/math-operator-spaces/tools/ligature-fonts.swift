import CoreText
import Foundation

// usage: swiftc -O ligature-fonts.swift -o <scratch>/ligature-fonts && <scratch>/ligature-fonts
// For each family a Books reader can choose (and the system UI font), whether the font maps each
// Latin ligature code point U+FB00–U+FB04 to a glyph of its own. A family that lacks one draws
// that character from a fallback font, with the fallback's metrics (#189).
let names = ["Iowan Old Style", "Palatino", "Georgia", "Charter", "Athelas", "Seravek", "New York",
             "Times New Roman", "Avenir Next", "Helvetica Neue", "Baskerville", ".AppleSystemUIFont"]
let points: [UInt16] = [0xFB00, 0xFB01, 0xFB02, 0xFB03, 0xFB04]
for name in names {
    let font = CTFontCreateWithName(name as CFString, 12, nil)
    let family = CTFontCopyFamilyName(font) as String
    var row = "\(name)\t\(family)"
    for point in points {
        var characters = [point]
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        let mapped = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1) && glyphs[0] != 0
        row += "\tU+\(String(point, radix: 16, uppercase: true))=\(mapped ? "yes" : "no")"
    }
    print(row)
}
