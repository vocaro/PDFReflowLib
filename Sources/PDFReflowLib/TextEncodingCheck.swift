import Foundation
import CoreGraphics

/// Detects born-digital text layers whose extracted characters are not the characters drawn (#38).
///
/// Two independent signals must agree. The structural signal is a simple font reachable from
/// the page resources with no `ToUnicode` map and a custom `Differences` encoding made of
/// index-style glyph names (`G108`, `c63`, `glyph12`) that no reader can map to Unicode; PDFKit
/// then reports the index as the character, which shifted every letter of the Census report.
/// The text signal is an English plausibility test over the extracted words: almost no common
/// function words together with an implausible share of letter pairs. Fonts with standard
/// glyph names, `uniXXXX` names or any `ToUnicode` map are never evidence, and ordinary prose,
/// name-heavy indexes, answer keys and inherited OCR keep a plausible profile on at least one
/// of the two text statistics. Neither signal alone flags a page.
enum TextEncodingCheck {
    // MARK: Structural font evidence

    private static let maximumFonts = 256
    private static let maximumFormDepth = 4

    /// True when a Type1, TrueType, MMType1 or Type3 font in the page resources (including
    /// nested Form XObjects) lacks `ToUnicode` and encodes at least half of its `Differences`
    /// names as index-style names. Composite (Type0) fonts use CMaps and are not examined.
    static func hasUnmappedFont(_ page: CGPDFPage) -> Bool {
        guard let dictionary = page.dictionary else { return false }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return false }
        var examined = 0
        return hasUnmappedFont(in: resources, depth: 0, examined: &examined)
    }

    private static func hasUnmappedFont(in resources: CGPDFDictionaryRef, depth: Int, examined: inout Int) -> Bool {
        var found = false
        var count = examined
        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
            CGPDFDictionaryApplyBlock(fonts, { _, value, _ in
                guard count < maximumFonts else { return false }
                count += 1
                var font: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(value, .dictionary, &font), let font, isUnmapped(font) {
                    found = true
                    return false
                }
                return true
            }, nil)
        }
        examined = count
        if found || depth >= maximumFormDepth { return found }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return false }
        var nested: [CGPDFDictionaryRef] = []
        CGPDFDictionaryApplyBlock(xobjects, { _, value, _ in
            guard nested.count < maximumFonts else { return false }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream), CGPDFObjects.name(dictionary, "Subtype") == "Form" else { return true }
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources {
                nested.append(resources)
            }
            return true
        }, nil)
        for resources in nested where examined < maximumFonts {
            if hasUnmappedFont(in: resources, depth: depth + 1, examined: &examined) { return true }
        }
        return false
    }

    private static func isUnmapped(_ font: CGPDFDictionaryRef) -> Bool {
        guard let subtype = CGPDFObjects.name(font, "Subtype"),
              ["Type1", "TrueType", "MMType1", "Type3"].contains(subtype) else { return false }
        var stream: CGPDFStreamRef?
        guard !CGPDFDictionaryGetStream(font, "ToUnicode", &stream) else { return false }
        var encoding: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(font, "Encoding", &encoding), let encoding else { return false }
        var differences: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences else { return false }
        var names = 0, indexStyle = 0
        for index in 0..<min(CGPDFArrayGetCount(differences), 512) {
            var pointer: UnsafePointer<CChar>?
            guard CGPDFArrayGetName(differences, index, &pointer), let pointer else { continue }
            names += 1
            if isIndexStyleGlyphName(String(cString: pointer)) { indexStyle += 1 }
        }
        return indexStyle > 0 && indexStyle * 2 >= names
    }

    /// `G108`, `c63`, `g3`, `glyph12`, `index5`, `cid7`, `gid7`: a short letter prefix and a decimal
    /// index. `uniXXXX` and `uXXXX` are mappable by convention and are never index-style.
    static func isIndexStyleGlyphName(_ name: String) -> Bool {
        let prefix = name.prefix { $0.isLetter }
        let digits = name.dropFirst(prefix.count)
        guard !prefix.isEmpty, !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let lowered = prefix.lowercased()
        if lowered == "u" || lowered == "uni" { return false }
        return prefix.count <= 2 || ["glyph", "index", "cid", "gid"].contains(lowered)
    }

    // MARK: English plausibility

    struct Statistics: Equatable {
        /// Alphabetic tokens of at least two letters.
        var words: Int
        /// Share of words in the embedded function-word list.
        var stopwordRate: Double
        /// Share of within-word ASCII letter pairs outside the embedded common-bigram list.
        var rareBigramRate: Double
    }

    /// Fewer words leave a table, caption or formula page unjudged.
    static let minimumWords = 20
    static let maximumStopwordRate = 0.05
    static let minimumRareBigramRate = 0.30

    /// Only English statistics are embedded; other declared languages are not judged.
    static func supports(language: String) -> Bool {
        let primary = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
        return primary == "en" || primary == "eng"
    }

    static func isImplausible(_ text: String, language: String) -> Bool {
        guard supports(language: language) else { return false }
        let statistics = statistics(of: text)
        return statistics.words >= minimumWords
            && statistics.stopwordRate < maximumStopwordRate
            && statistics.rareBigramRate >= minimumRareBigramRate
    }

    static func statistics(of text: String) -> Statistics {
        var words = 0, stopwords = 0, bigrams = 0, rare = 0
        var current: [Character] = []
        func flush() {
            defer { current.removeAll(keepingCapacity: true) }
            guard current.count >= 2 else { return }
            words += 1
            let word = String(current).lowercased()
            if stopwordList.contains(word) { stopwords += 1 }
            guard word.allSatisfy(\.isASCII) else { return }
            let letters = Array(word.utf8)
            for index in 1..<letters.count {
                bigrams += 1
                if !commonBigrams.contains(UInt16(letters[index - 1]) << 8 | UInt16(letters[index])) { rare += 1 }
            }
        }
        for character in text {
            if character.isLetter { current.append(character) } else { flush() }
        }
        flush()
        return Statistics(words: words,
            stopwordRate: words > 0 ? Double(stopwords) / Double(words) : 0,
            rareBigramRate: bigrams > 0 ? Double(rare) / Double(bigrams) : 0)
    }

    /// 148 English function words and report vocabulary. Ordinary prose scores 0.3–0.5; the
    /// shifted Census pages score at most 0.004 (measurements/damaged-text-encoding/record.md).
    private static let stopwordList: Set<String> = Set("""
    the of and to in a is that for it as was with be by on not he this are or his from at which but
    have an had they you were their one all we can her has there been if more when will would who so no
    than into them its two out then up also only new some could time these first any may other such
    each about how because between under over after before both those most while where through many
    during three now must does do did being made make used use using data page table figure section
    number see chapter part per within without same different against however should very much still
    even here just like every another might well since great little our own way too
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    /// The 300 most frequent within-word letter pairs by type frequency over the ASCII entries of
    /// macOS `/usr/share/dict/words` (web2; 235,974 words; 97.7% of pair occurrences). Derived by
    /// `measurements/damaged-text-encoding/bigrams.py`. Prose pages score 0.02–0.07 rare pairs;
    /// the shifted Census pages score 0.54–0.70.
    private static let commonBigrams: Set<UInt16> = {
        let pairs = "erintionteanalaticenisreralerirostnearliesntorunitlacoiotoianicaedustasstrlydemachphngloouelnaacolhe"
            + "omdimenothsietsellmioppeosidvecehihoileaasulprndhaaburotblpomoncpaecemocgeogamshciapctpisuschynsdary"
            + "soumadsaepsprtsmdobiodtyagcrbeutgibaivimcuipgaplkermaegrtuooiziriglumpifvieobooiglfibrieeeruaircovqu"
            + "fockrdrsrrzeaudrubexclgoptttobfevaibhreuupwaylucbucyrnuaypeimbfuuiowegkimupuflguoarpnnudysmyltwiefsl"
            + "pstlwonufanfsywedlduavakppmmrgueevebrbikgnrlhuymiuoeffghynycgyzafrhtytrhyrsnvoccayofnppyewyakaxiugzo"
            + "ldoxafnkdyhlnynryonlrkggydawrvlpoktcdnddnvsknmlmrfnbyeehwhbbnhaxeyjuazahlcswftbsjaxttsklohhnxamnlvyg"
        let bytes = Array(pairs.utf8)
        precondition(bytes.count == 600)
        return Set(stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) })
    }()
}
