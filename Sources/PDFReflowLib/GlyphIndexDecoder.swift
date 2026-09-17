import Foundation
import CoreGraphics

/// Establishes the characters of fonts that name their glyphs by index (#143).
///
/// The Census report's TeX fonts (`dcr10084`, `dcbx100120`, `dcti10084`) were distilled with
/// `Differences` names `G<n>` and no ToUnicode map. `n` is the glyph's position in the font program
/// Distiller read, not a character: the embedded CFF fonts name their glyphs the same way and their
/// built-in encodings place `G<n>` at code `n`, so nothing in the PDF states which letter a glyph is.
/// PDFKit reports U+n, which shifted every letter of those fonts by three. The positions follow the
/// fonts' TeX encoding at a constant offset, but a different one per font (`dcr` +3, the math italic
/// `cmmi` +0 for its letters and not constant elsewhere).
///
/// The offset is therefore read from the document's own words. Every show in such a font across the
/// document is split into words at word-sized gaps, and each offset that turns at least half the
/// glyphs into ASCII letters is judged with `TextEncodingCheck`'s English tables: at least
/// `minimumWords` words (`minimumLongWords` of four letters or more), `minimumStopwordRate` function words, at most `maximumRareBigramRate` rare
/// letter pairs, `minimumLowercaseRate` lowercase letters (the case-swapped offset scores like English
/// otherwise), and capitals where English sets them (`maximumInnerCapitalRate`). A font is decoded only when exactly one offset passes. Its codes then read
/// through the Cork (T1) table for an EC or DC font name, whose ligatures, quotes and dashes TeX places
/// below 32, or through letters, digits and the punctuation every TeX and standard Latin encoding
/// shares for any other name. Math fonts (`cmmi`, `cmsy`, `cmex`, the bitmap Type3 fonts) set too few
/// words to pass and stay undecoded, so their pages keep #38's damaged-encoding path.
enum GlyphIndexDecoder {
    static let minimumWords = 20
    /// Words of at least four letters: math fonts' variables and indexes (`cmmi`'s `dY`, `ij`) form
    /// two-letter "words" that can land on function words (`in`, `at`) under a wrong offset.
    static let minimumLongWords = 10
    static let minimumStopwordRate = 0.10
    static let maximumRareBigramRate = 0.10
    static let minimumLowercaseRate = 0.5
    /// A font of capitals alone also reads as English lowercase at the offset 32 below its own, where
    /// its digits and punctuation become capitals inside words (`noise.` reads `noiseN`). English sets
    /// capitals at word starts: a reading needs a capitalized word and at most this share of words
    /// with a capital after a lowercase letter.
    static let maximumInnerCapitalRate = 0.02
    /// Glyph occurrences read per font, and distinct words kept per font.
    static let maximumGlyphs = 500_000
    static let maximumDistinctWords = 50_000

    /// One offset's English statistics over a font's words.
    struct Candidate: Equatable {
        var offset: Int
        var words: Int
        var longWords: Int
        /// Words of a capital followed only by lowercase letters, and the share of words with a capital
        /// after a lowercase letter.
        var capitalizedWords: Int
        var innerCapitalRate: Double
        var stopwordRate: Double
        var rareBigramRate: Double
        var lowercaseRate: Double

        var passes: Bool {
            words >= GlyphIndexDecoder.minimumWords && longWords >= GlyphIndexDecoder.minimumLongWords
                && stopwordRate >= GlyphIndexDecoder.minimumStopwordRate
                && rareBigramRate <= GlyphIndexDecoder.maximumRareBigramRate && lowercaseRate >= GlyphIndexDecoder.minimumLowercaseRate
                && capitalizedWords > 0 && innerCapitalRate <= GlyphIndexDecoder.maximumInnerCapitalRate
        }
    }

    /// A font's words (glyph indexes, -1 where a code has none) with their counts.
    struct FontEvidence {
        var baseFont: String?
        var indexes: [UInt8: Int]
        var names: [UInt8: String] = [:]
        var words: [[Int]: Int] = [:]
        var glyphs = 0
    }

    /// Characters for every index-glyph font of the document whose words establish them, keyed
    /// by `FontWeightReader.IndexGlyphFont.key`. Only pages whose resources hold index-style names
    /// without ToUnicode (`TextEncodingCheck.hasUnmappedFont`) are scanned; other languages than
    /// English establish nothing.
    static func read(_ url: URL, language: String) throws -> [String: [UInt8: String]] {
        guard TextEncodingCheck.supports(language: language), let document = CGPDFDocument(url as CFURL) else { return [:] }
        return try read(document, language: language)
    }

    static func read(_ document: CGPDFDocument, language: String) throws -> [String: [UInt8: String]] {
        guard TextEncodingCheck.supports(language: language), document.isUnlocked, document.numberOfPages > 0 else { return [:] }
        var evidence: [String: FontEvidence] = [:]
        for number in 1...document.numberOfPages {
            try Task.checkCancellation()
            autoreleasepool {
                guard let page = document.page(at: number), TextEncodingCheck.hasUnmappedFont(page) else { return }
                var fonts: [Int: FontWeightReader.FontInfo] = [:]
                let shows = FontWeightReader.read(page, fonts: { fonts[$0] = $1 })
                collect(shows, fonts: fonts, into: &evidence)
            }
        }
        var result: [String: [UInt8: String]] = [:]
        for (key, font) in evidence {
            guard let chosen = offset(for: font.words) else { continue }
            let characters = characters(indexes: font.indexes, names: font.names, offset: chosen.offset, baseFont: font.baseFont)
            if !characters.isEmpty { result[key] = characters }
        }
        return result
    }

    static func collect(_ shows: [FontWeightReader.Show], fonts: [Int: FontWeightReader.FontInfo],
                        into evidence: inout [String: FontEvidence]) {
        for show in shows {
            guard let key = show.indexFont, let glyphs = show.glyphs, let font = fonts[show.font]?.indexGlyphs else { continue }
            var entry = evidence[key] ?? FontEvidence(baseFont: font.baseFont, indexes: font.indexes, names: font.names)
            guard entry.glyphs + glyphs.count <= maximumGlyphs else { continue }
            entry.glyphs += glyphs.count
            var word: [Int] = []
            func flush() {
                if !word.isEmpty, entry.words[word] != nil || entry.words.count < maximumDistinctWords {
                    entry.words[word, default: 0] += 1
                }
                word.removeAll(keepingCapacity: true)
            }
            for glyph in glyphs {
                if glyph.wordStart { flush() }
                word.append(glyph.index ?? -1)
            }
            flush()
            evidence[key] = entry
        }
    }

    /// The statistics of `words` read with glyph index `n` as the character code `n - offset`.
    static func candidate(_ words: [[Int]: Int], offset: Int) -> Candidate {
        var count = 0, long = 0, capitalized = 0, inner = 0, stopwords = 0, bigrams = 0, rare = 0, lowercase = 0, letters = 0
        for (word, occurrences) in words {
            var token: [UInt8] = []
            func flush() {
                defer { token.removeAll(keepingCapacity: true) }
                guard token.count >= 2 else { return }
                count += occurrences
                if token.count >= 4 { long += occurrences }
                let upper = token.map { $0 < 97 }
                if upper[0], !upper.dropFirst().contains(true) { capitalized += occurrences }
                if zip(upper, upper.dropFirst()).contains(where: { !$0 && $1 }) { inner += occurrences }
                let lowered = token.map { $0 | 0x20 }
                if TextEncodingCheck.stopwordList.contains(String(decoding: lowered, as: UTF8.self)) { stopwords += occurrences }
                for index in 1..<lowered.count {
                    bigrams += occurrences
                    if !TextEncodingCheck.commonBigrams.contains(UInt16(lowered[index - 1]) << 8 | UInt16(lowered[index])) {
                        rare += occurrences
                    }
                }
            }
            for index in word {
                let code = index - offset
                if (65...90).contains(code) || (97...122).contains(code) {
                    token.append(UInt8(code))
                    letters += occurrences
                    if code >= 97 { lowercase += occurrences }
                } else { flush() }
            }
            flush()
        }
        return Candidate(offset: offset, words: count, longWords: long, capitalizedWords: capitalized,
                         innerCapitalRate: count > 0 ? Double(inner) / Double(count) : 0,
                         stopwordRate: count > 0 ? Double(stopwords) / Double(count) : 0,
                         rareBigramRate: bigrams > 0 ? Double(rare) / Double(bigrams) : 1,
                         lowercaseRate: letters > 0 ? Double(lowercase) / Double(letters) : 0)
    }

    /// Every offset under which at least half the glyph occurrences are ASCII letters, judged.
    static func candidates(for words: [[Int]: Int]) -> [Candidate] {
        var histogram: [Int: Int] = [:], total = 0
        for (word, occurrences) in words {
            for index in word { histogram[index, default: 0] += occurrences; total += occurrences }
        }
        guard total > 0 else { return [] }
        return (-255...255).compactMap { offset in
            let letters = histogram.reduce(0) { sum, entry in
                let code = entry.key - offset
                return sum + ((65...90).contains(code) || (97...122).contains(code) ? entry.value : 0)
            }
            return letters * 2 >= total ? candidate(words, offset: offset) : nil
        }
    }

    /// The one offset whose letters read as English, or nil when none or several do.
    static func offset(for words: [[Int]: Int]) -> Candidate? {
        let passing = candidates(for: words).filter(\.passes)
        return passing.count == 1 ? passing[0] : nil
    }

    /// The characters of a font's index-named codes at `offset`, and of the codes it names with the
    /// standard names TeX text fonts use (`space`, `quoteright`, `fi`).
    static func characters(indexes: [UInt8: Int], names: [UInt8: String] = [:], offset: Int, baseFont: String?) -> [UInt8: String] {
        let cork = baseFont.map { FontWeightReader.strippedName($0).lowercased() }
            .map { $0.range(of: #"^(dc|ec)[a-z]+[0-9]+$"#, options: .regularExpression) != nil } ?? false
        var result: [UInt8: String] = [:]
        for (code, name) in names {
            if let character = NativeSpacingReader.differenceGlyphs[name] { result[code] = character }
        }
        for (code, index) in indexes {
            let position = index - offset
            guard (0...255).contains(position) else { continue }
            if let character = cork ? corkEncoding[position] : sharedCharacter(position) { result[code] = character }
        }
        return result
    }

    /// Letters, digits and the punctuation at the same codes in TeX's OT1 and T1 encodings and in
    /// Adobe's standard and WinAnsi encodings.
    static func sharedCharacter(_ code: Int) -> String? {
        guard (0...255).contains(code) else { return nil }
        let scalar = UnicodeScalar(UInt8(code))
        let shared = CharacterSet(charactersIn: "!#$%&()*+,-./:;=?@[]")
        return (65...90).contains(code) || (97...122).contains(code) || (48...57).contains(code) || shared.contains(scalar)
            ? String(scalar) : nil
    }

    /// TeX's Cork (T1) encoding, used by the EC and DC fonts: accents (0–12), the compound-word mark
    /// and the per-mille zero (23, 24) set no character of their own and are left undecoded.
    static let corkEncoding: [String?] = {
        var table = [String?](repeating: nil, count: 256)
        let low: [Int: String] = [
            13: "\u{201A}", 14: "\u{2039}", 15: "\u{203A}", 16: "\u{201C}", 17: "\u{201D}", 18: "\u{201E}",
            19: "\u{00AB}", 20: "\u{00BB}", 21: "\u{2013}", 22: "\u{2014}", 25: "\u{0131}", 26: "\u{0237}",
            27: "\u{FB00}", 28: "\u{FB01}", 29: "\u{FB02}", 30: "\u{FB03}", 31: "\u{FB04}", 32: "\u{2423}",
            39: "\u{2019}", 96: "\u{2018}", 127: "-",
        ]
        for code in 33...126 { table[code] = String(UnicodeScalar(UInt8(code))) }
        for (code, text) in low { table[code] = text }
        let high = Array("ĂĄĆČĎĚĘĞĹĽŁŃŇŊŐŔŘŚŠŞŤŢŰŮŸŹŽŻĲİđ§ăąćčďěęğĺľłńňŋőŕřśšşťţűůÿźžżĳ¡¿£"
            + "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖŒØÙÚÛÜÝÞ_àáâãäåæçèéêëìíîïðñòóôõöœøùúûüýþß")
        precondition(high.count == 128)
        for (offset, character) in high.enumerated() { table[128 + offset] = String(character) }
        table[223] = "SS"
        return table
    }()
}
