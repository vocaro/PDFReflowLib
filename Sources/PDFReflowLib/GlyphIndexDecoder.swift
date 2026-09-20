import Foundation
import CoreGraphics

/// Establishes the characters of fonts that name their glyphs by index (#143, ported onto main
/// for #226 with the relaxed family gate #149 item 2 asks for).
///
/// The Census report's TeX fonts (`dcr10084`, `dcbx100120`, `dcti10084`, `dctt10075`) were
/// distilled with `Differences` names `G<n>` and no `ToUnicode` map. `n` is the glyph's position
/// in the font program Distiller read, not a character: the embedded CFF program names its own
/// glyphs the same way, its built-in encoding places `G<n>` at code `n`, and the descriptor's
/// `CharSet` repeats the names, so **nothing in the file states which character a slot holds**.
/// PDFKit reports the index as the character, which shifted every letter of those fonts by three
/// (`Wklv sdshu`) and dropped the ligatures, and `TextEncodingCheck` (#38) sent the pages to
/// recognition.
///
/// The offset is therefore read from the document's own words, never assumed: every show in such
/// a font across the document is split into words at word-sized gaps, and each offset that turns
/// at least half the glyph occurrences into ASCII letters is judged with #38's embedded English
/// tables. A font is decoded only when exactly one offset passes. Its codes then read through
/// TeX's Cork (T1) table for an `ec`/`dc` name, whose ligatures, quotes and dashes sit below 32,
/// or through the letters, digits and punctuation every TeX and standard Latin encoding shares
/// for any other name.
///
/// Two fonts of the document's own Cork family that pass this test lend their offset to a third
/// (`corroboratedOffset`): `dctt10075` draws one e-mail address — 24 glyphs, too few words for
/// any statistics — while `dcr`, `dcti` and `dcbx` establish the same offset from thousands.
/// That is the whole of the relaxation; nothing else inherits an offset, and in particular the
/// `cm` math fonts do not, since the document itself disagrees inside that family (`cmmib` sits
/// three slots on from `cmmi`).
///
/// A glyph whose font this cannot establish is written as U+FFFD rather than guessed at: a
/// plausible-looking wrong letter is worse than an admitted gap, and `PageDiagnosis` already
/// counts replacement characters, so a page whose mathematics this cannot read keeps #38's
/// diagnosis and its recognition exactly as before.
enum GlyphIndexDecoder {
    // MARK: - Thresholds

    static let minimumWords = 20
    /// Words of at least four letters: a math font's variable runs (`dY`, `ij`) form two-letter
    /// "words" that can land on function words (`in`, `at`) under a wrong offset.
    static let minimumLongWords = 10
    static let minimumStopwordRate = 0.10
    static let maximumRareBigramRate = 0.10
    static let minimumLowercaseRate = 0.5
    /// A font of capitals alone also reads as English lower case at the offset 32 below its own,
    /// where its digits and punctuation become capitals inside words (`noise.` reads `noiseN`).
    /// English sets capitals at word starts: a reading needs a capitalized word and at most this
    /// share of words with a capital after a lower-case letter.
    static let maximumInnerCapitalRate = 0.02
    /// Corroboration needs this many independently decoded Cork-named fonts agreeing.
    static let minimumCorroboratingFonts = 2
    /// A gap this wide, in ems, separates words. Census's body kerns measure 0.00 em and its
    /// word gaps 0.43 em; its letter-spaced headings set 1.10 em of character spacing between two
    /// glyphs of one string and cancel it with a +1120 adjustment between the others.
    static let wordGapEms: CGFloat = 0.15

    static let maximumGlyphs = 500_000
    static let maximumDistinctWords = 50_000
    static let maximumFontsPerDocument = 256
    static let maximumPages = 4_096

    /// The character this writes where a font states no character for a glyph.
    static let unknownCharacter = "\u{FFFD}"

    // MARK: - Index-glyph fonts

    /// One simple font whose `Differences` names its glyphs by index.
    struct Font: Equatable {
        /// Subtype, `BaseFont` and the whole `Differences` array: a font shared across pages, or
        /// reopened in another document, is one font.
        var key: String
        var baseFont: String?
        /// The index each code's name states (`G108` at code 3 is 108).
        var indexes: [UInt8: Int]
        /// Codes named with an ordinary glyph name (`space`, `quoteright`), which state a
        /// character of their own whatever the offset is.
        var names: [UInt8: String]
        /// Index-named codes whose name carries a one-letter prefix (`G108`, `c63`): the only
        /// ones PDFKit reads as a character at all (`GlyphIdentityReader.reportedCharacter`).
        var shortPrefixedCodes: Set<UInt8> = []
    }

    /// The ordinary glyph names a TeX text font mixes into an otherwise index-named
    /// `Differences`. Each states its character whatever the offset turns out to be, so it is
    /// read directly and left out of the offset evidence. Only names whose character is the same
    /// in every Latin encoding are listed; anything else is left undecoded.
    static let standardGlyphs: [String: String] = [
        "space": " ", "exclam": "!", "quotedbl": "\"", "numbersign": "#", "dollar": "$", "percent": "%",
        "ampersand": "&", "quotesingle": "'", "parenleft": "(", "parenright": ")", "asterisk": "*",
        "plus": "+", "comma": ",", "hyphen": "-", "period": ".", "slash": "/", "colon": ":",
        "semicolon": ";", "equal": "=", "question": "?", "at": "@", "bracketleft": "[",
        "bracketright": "]", "underscore": "_", "braceleft": "{", "braceright": "}",
        "quoteleft": "\u{2018}", "quoteright": "\u{2019}", "quotedblleft": "\u{201C}",
        "quotedblright": "\u{201D}", "endash": "\u{2013}", "emdash": "\u{2014}",
        "fi": "\u{FB01}", "fl": "\u{FB02}", "ff": "\u{FB00}", "ffi": "\u{FB03}", "ffl": "\u{FB04}",
    ]

    /// `G108`, `c63`: a letter prefix and a decimal index, as `TextEncodingCheck` recognizes them.
    static func index(of name: String) -> Int? {
        guard TextEncodingCheck.isIndexStyleGlyphName(name) else { return nil }
        let digits = name.drop { $0.isLetter }
        guard digits.count <= 6, let value = Int(digits) else { return nil }
        return value
    }

    /// The index-glyph font a font dictionary describes, or nil for anything else: a composite
    /// font, a font with a `ToUnicode` map, or one whose `Differences` names fewer than half its
    /// codes by index. This is `TextEncodingCheck.hasUnmappedFont`'s rule for one font, with the
    /// names kept.
    static func font(_ dict: CGPDFDictionaryRef) -> Font? {
        guard let subtype = CGPDFObjects.name(dict, "Subtype"),
              ["Type1", "TrueType", "MMType1", "Type3"].contains(subtype) else { return nil }
        var stream: CGPDFStreamRef?
        guard !CGPDFDictionaryGetStream(dict, "ToUnicode", &stream) else { return nil }
        guard let encoding = CGPDFObjects.dictionary(dict, "Encoding"),
              let differences = CGPDFObjects.array(encoding, "Differences") else { return nil }
        let count = CGPDFArrayGetCount(differences)
        guard count <= 1_024 else { return nil }
        var indexes: [UInt8: Int] = [:], names: [UInt8: String] = [:], shortPrefixed: Set<UInt8> = []
        var signature = "\(subtype)|\(CGPDFObjects.name(dict, "BaseFont") ?? "")|"
        var next = 0
        for position in 0..<count {
            var code: CGPDFInteger = 0, pointer: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(differences, position, &code) {
                guard (0...255).contains(code) else { return nil }
                next = code
                signature += "\(code) "
            } else if CGPDFArrayGetName(differences, position, &pointer), let pointer {
                guard (0...255).contains(next) else { return nil }
                let name = String(cString: pointer)
                guard name.count <= 64 else { return nil }
                signature += "/\(name) "
                if let value = index(of: name) {
                    indexes[UInt8(next)] = value
                    if name.prefix(while: \.isLetter).count == 1 { shortPrefixed.insert(UInt8(next)) }
                } else if let character = standardGlyphs[name] { names[UInt8(next)] = character }
                next += 1
            } else { return nil }
        }
        let named = indexes.count + names.count
        guard !indexes.isEmpty, indexes.count * 2 >= named else { return nil }
        return Font(key: signature, baseFont: CGPDFObjects.name(dict, "BaseFont"), indexes: indexes,
                    names: names, shortPrefixedCodes: shortPrefixed)
    }

    /// The name without a subset tag, lower-cased (`FCHKIB+dctt10075` is `dctt10075`).
    static func strippedName(_ baseFont: String) -> String {
        guard let plus = baseFont.firstIndex(of: "+"), baseFont.distance(from: baseFont.startIndex, to: plus) == 6,
              baseFont[..<plus].allSatisfy({ $0.isUppercase && $0.isLetter }) else { return baseFont.lowercased() }
        return String(baseFont[baseFont.index(after: plus)...]).lowercased()
    }

    /// Whether a name follows TeX's EC/DC convention (`dcr10084`, `ecti1000`), which names the
    /// Cork (T1) encoding: shape letters then a design size.
    static func isCorkNamed(_ baseFont: String?) -> Bool {
        guard let baseFont else { return false }
        return strippedName(baseFont).range(of: #"^(dc|ec)[a-z]+[0-9]+$"#, options: .regularExpression) != nil
    }

    // MARK: - Reading a page's glyphs

    /// One shown glyph: the code, the index its name states (nil for an ordinary glyph name) and
    /// whether a word-sized gap stands before it.
    struct Glyph: Equatable {
        var code: UInt8
        var index: Int?
        var startsWord: Bool
    }

    /// One text show drawn in an index-glyph font.
    struct Show {
        var origin: CGPoint
        var fontKey: String
        var glyphs: [Glyph]
    }

    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.operators = ["Tc"]
        options.maximumOperations = 200_000
        options.maximumSavedStates = 256
        // A stray positioning operator is tolerated: this reader records shows, it does not
        // validate the stream, and a page it cannot follow simply supplies no evidence.
        options.strictTextObjects = false
        options.selectsFonts = true
        options.maximumShowElements = 4_096
        // `'` and `"` carry their own word spacing, which this reader does not model, and a page
        // that mixes them with `Tj`/`TJ` would be half read: repairing only the shows this saw
        // would leave the rest of the page shifted with nothing to say so. Such a page supplies
        // no evidence at all and keeps #38's path untouched.
        options.moveAndShow = .invalidate
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        var font: Font?
        var size: CGFloat = 0
        var spacing: CGFloat = 0
        var saved: [(Font?, CGFloat)] = []
        var lastOrigin: CGPoint?
        var cache: [Int: Font?] = [:]
        var fonts: [String: Font] = [:]
        var shows: [Show] = []

        func saveState() { saved.append((font, size)) }
        func restoreState() { (font, size) = saved.removeLast() }
        func beginText(_ walk: ContentStreamWalk) { lastOrigin = nil }
        func endText(_ walk: ContentStreamWalk) { lastOrigin = nil }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            guard op == "Tc", let values = ContentStreamWalk.numbers(scanner, 1), values[0].isFinite else { return }
            spacing = values[0]
        }

        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            self.size = size
            var dict: CGPDFDictionaryRef?
            guard let resource, CGPDFObjectGetValue(resource, .dictionary, &dict), let dict else { font = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = cache[id] { font = cached; return }
            guard cache.count < 1_024 else { walk.invalid = true; return }
            let found = GlyphIndexDecoder.font(dict)
            cache[id] = found
            font = found
            if let found, fonts[found.key] == nil {
                guard fonts.count < maximumFontsPerDocument else { walk.invalid = true; return }
                fonts[found.key] = found
            }
        }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard shows.count < 10_000 else { walk.invalid = true; return }
            let transform = walk.textTransform
            guard transform.tx.isFinite, transform.ty.isFinite else { return }
            // Rotated or mirrored text supplies no evidence for upright lines.
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else { lastOrigin = nil; return }
            let origin: CGPoint
            if walk.positioned { origin = CGPoint(x: transform.tx, y: transform.ty) }
            else if let last = lastOrigin { origin = last }
            else { return }
            lastOrigin = origin
            guard let font, size > 0, size.isFinite else { return }
            // A show begins a word; within it, a gap is the character spacing the operands do not
            // cancel. Both are measured in ems of the selected size, as `wordGapEms` is.
            let perGlyph = spacing.isFinite ? spacing / size : 0
            var glyphs: [Glyph] = []
            var gap = CGFloat.infinity
            var ok = true
            for argument in arguments {
                switch argument {
                case .string(let string):
                    let count = CGPDFStringGetLength(string)
                    guard count <= 4_096, glyphs.count + count <= 8_192, let bytes = CGPDFStringGetBytePtr(string) else {
                        ok = false; continue
                    }
                    for position in 0..<count {
                        let code = bytes[position]
                        glyphs.append(Glyph(code: code, index: font.indexes[code], startsWord: gap >= wordGapEms))
                        gap = perGlyph
                    }
                case .adjustment(let number) where number.isFinite:
                    gap = (gap.isFinite ? gap : 0) - number / 1_000
                case .adjustment, .other:
                    ok = false
                }
            }
            guard ok, !glyphs.isEmpty else { return }
            shows.append(Show(origin: origin, fontKey: font.key, glyphs: glyphs))
        }
    }

    /// Every index-glyph show on `page`, with the fonts they name, or nil when the page's content
    /// stream cannot be followed or the page is rotated (this reader's transform math assumes an
    /// upright page, matching `NativeSpacingReader` and `GlyphIdentityReader`).
    static func scan(_ page: CGPDFPage) -> (shows: [Show], fonts: [String: Font])? {
        guard page.rotationAngle == 0 else { return nil }
        let visitor = Visitor()
        guard ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor) else { return nil }
        return (visitor.shows, visitor.fonts)
    }

    // MARK: - Judging an offset

    /// One offset's English statistics over a font's words.
    struct Candidate: Equatable {
        var offset: Int
        var words: Int
        var longWords: Int
        var capitalizedWords: Int
        var innerCapitalRate: Double
        var stopwordRate: Double
        var rareBigramRate: Double
        var lowercaseRate: Double

        var passes: Bool {
            words >= minimumWords && longWords >= minimumLongWords
                && stopwordRate >= minimumStopwordRate
                && rareBigramRate <= maximumRareBigramRate
                && lowercaseRate >= minimumLowercaseRate
                && capitalizedWords > 0 && innerCapitalRate <= maximumInnerCapitalRate
        }
    }

    /// The statistics of `words` (glyph indexes, -1 where a code names no index) read with the
    /// index `n` as the character code `n - offset`.
    static func candidate(_ words: [[Int]: Int], offset: Int) -> Candidate {
        var count = 0, long = 0, capitalized = 0, inner = 0
        var stopwords = 0, bigrams = 0, rare = 0, lowercase = 0, letters = 0
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
                if TextEncodingCheck.stopwordList.contains(String(decoding: lowered, as: UTF8.self)) {
                    stopwords += occurrences
                }
                for position in 1..<lowered.count {
                    bigrams += occurrences
                    let pair = UInt16(lowered[position - 1]) << 8 | UInt16(lowered[position])
                    if !TextEncodingCheck.commonBigrams.contains(pair) { rare += occurrences }
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

    /// Every offset under which at least half a font's glyph occurrences read as ASCII letters.
    static func candidates(for words: [[Int]: Int]) -> [Candidate] {
        var histogram: [Int: Int] = [:], total = 0
        for (word, occurrences) in words {
            for index in word {
                histogram[index, default: 0] += occurrences
                total += occurrences
            }
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

    // MARK: - Character tables

    /// TeX's Cork (T1) encoding, which every EC and DC font names. The accents (0–12), the
    /// compound-word mark and the per-mille zero (23, 24) set no character of their own and stay
    /// undecoded.
    static let corkEncoding: [String?] = {
        var table = [String?](repeating: nil, count: 256)
        for code in 33...126 { table[code] = String(UnicodeScalar(UInt8(code))) }
        let low: [Int: String] = [
            13: "\u{201A}", 14: "\u{2039}", 15: "\u{203A}", 16: "\u{201C}", 17: "\u{201D}", 18: "\u{201E}",
            19: "\u{00AB}", 20: "\u{00BB}", 21: "\u{2013}", 22: "\u{2014}", 25: "\u{0131}", 26: "\u{0237}",
            27: "\u{FB00}", 28: "\u{FB01}", 29: "\u{FB02}", 30: "\u{FB03}", 31: "\u{FB04}", 32: "\u{00A0}",
            39: "\u{2019}", 96: "\u{2018}", 127: "-",
        ]
        for (code, text) in low { table[code] = text }
        let high = Array("ĂĄĆČĎĚĘĞĹĽŁŃŇŊŐŔŘŚŠŞŤŢŰŮŸŹŽŻĲİđ§ăąćčďěęğĺľłńňŋőŕřśšşťţűůÿźžżĳ¡¿£"
            + "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖŒØÙÚÛÜÝÞ_àáâãäåæçèéêëìíîïðñòóôõöœøùúûüýþß")
        precondition(high.count == 128)
        for (position, character) in high.enumerated() { table[128 + position] = String(character) }
        table[223] = "SS"
        return table
    }()

    /// The letters, digits and punctuation that sit at the same code in TeX's OT1 and T1 and in
    /// Adobe's Standard and WinAnsi encodings: all a font whose encoding the document does not
    /// name can be read for.
    static func sharedCharacter(_ code: Int) -> String? {
        guard (0...255).contains(code) else { return nil }
        if (65...90).contains(code) || (97...122).contains(code) || (48...57).contains(code) {
            return String(UnicodeScalar(UInt8(code)))
        }
        return "!#$%&()*+,-./:;=?@[]".unicodeScalars.contains(UnicodeScalar(UInt8(code)))
            ? String(UnicodeScalar(UInt8(code))) : nil
    }

    /// A font's characters at `offset`: its index-named codes through the Cork table for an EC or
    /// DC name and through the shared table otherwise, plus the codes it names outright.
    static func characters(of font: Font, offset: Int) -> [UInt8: String] {
        let cork = isCorkNamed(font.baseFont)
        var result = font.names
        for (code, index) in font.indexes {
            let position = index - offset
            guard (0...255).contains(position) else { continue }
            if let character = cork ? corkEncoding[position] : sharedCharacter(position) { result[code] = character }
        }
        return result
    }

    /// Whether `offset` states a character for every index-named code of `font`: what a
    /// corroborated offset must do, since its font's own words cannot confirm it.
    static func statesEveryCode(_ font: Font, offset: Int) -> Bool {
        let characters = characters(of: font, offset: offset)
        return font.indexes.keys.allSatisfy { characters[$0] != nil }
    }

    // MARK: - The document's own words

    /// A font's words with their counts, gathered across the document.
    struct Evidence {
        var font: Font
        var words: [[Int]: Int] = [:]
        var glyphs = 0
    }

    static func collect(_ shows: [Show], fonts: [String: Font], into evidence: inout [String: Evidence]) {
        for show in shows {
            guard let font = fonts[show.fontKey] else { continue }
            var entry = evidence[show.fontKey] ?? Evidence(font: font)
            guard entry.glyphs + show.glyphs.count <= maximumGlyphs else { continue }
            entry.glyphs += show.glyphs.count
            var word: [Int] = []
            func flush() {
                if !word.isEmpty, entry.words[word] != nil || entry.words.count < maximumDistinctWords {
                    entry.words[word, default: 0] += 1
                }
                word.removeAll(keepingCapacity: true)
            }
            for glyph in show.glyphs {
                if glyph.startsWord { flush() }
                word.append(glyph.index ?? -1)
            }
            flush()
            evidence[show.fontKey] = entry
        }
    }

    /// The offset a document's own Cork-named fonts establish for one that could not establish
    /// its own: the offset that at least `minimumCorroboratingFonts` of them agree on, when that
    /// offset states a character for every one of this font's codes. Both conditions matter — the
    /// `ec`/`dc` name is what says the font carries the Cork encoding, and a font whose codes do
    /// not all land in it is not the same kind of font however its name reads.
    static func corroboratedOffset(for font: Font, among decoded: [(font: Font, offset: Int)]) -> Int? {
        guard isCorkNamed(font.baseFont) else { return nil }
        var agreeing: [Int: Int] = [:]
        for entry in decoded where isCorkNamed(entry.font.baseFont) && entry.font.key != font.key {
            agreeing[entry.offset, default: 0] += 1
        }
        let established = agreeing.filter { $0.value >= minimumCorroboratingFonts }
        guard established.count == 1, let offset = established.first?.key,
              statesEveryCode(font, offset: offset) else { return nil }
        return offset
    }

    /// The characters of every index-glyph font of `document` whose words, or whose family's
    /// words, establish them. Only pages whose resources hold an index-style font are scanned.
    static func read(_ document: CGPDFDocument) -> [String: [UInt8: String]] {
        guard document.isUnlocked, document.numberOfPages > 0, document.numberOfPages <= maximumPages else { return [:] }
        var evidence: [String: Evidence] = [:]
        for number in 1...document.numberOfPages {
            autoreleasepool {
                guard let page = document.page(at: number), TextEncodingCheck.hasUnmappedFont(page),
                      let scanned = scan(page) else { return }
                collect(scanned.shows, fonts: scanned.fonts, into: &evidence)
            }
        }
        var decoded: [(font: Font, offset: Int)] = []
        for entry in evidence.values.sorted(by: { $0.font.key < $1.font.key }) {
            guard let candidate = offset(for: entry.words) else { continue }
            decoded.append((entry.font, candidate.offset))
        }
        var result: [String: [UInt8: String]] = [:]
        for entry in decoded { result[entry.font.key] = characters(of: entry.font, offset: entry.offset) }
        for entry in evidence.values where result[entry.font.key] == nil {
            guard let offset = corroboratedOffset(for: entry.font, among: decoded) else { continue }
            result[entry.font.key] = characters(of: entry.font, offset: offset)
        }
        return result.filter { !$0.value.isEmpty }
    }

    // MARK: - What a page's extracted text did not take

    /// Runs of this many stated characters are looked for in a page's extracted text. Shorter
    /// runs (a lone italic variable, a bracketed reference number) occur in ordinary prose by
    /// chance and would say nothing about whether their line was rewritten.
    static let minimumCheckedRun = 4

    /// The number of index glyphs on `page` whose characters `text` does not carry: the evidence
    /// that a line drawn in an index-glyph font was left exactly as PDFKit read it, because no
    /// show could be attributed to it or because its glyphs did not spell what PDFKit reported.
    /// Such a line ships PDFKit's index-shifted reading, which is precisely #38's diagnosis, so a
    /// page with more than a stray few keeps that diagnosis and its recognition.
    ///
    /// The comparison ignores every space, since the decoder restores word gaps PDFKit's
    /// character spacing hid, and stops at a glyph the document states no character for, since
    /// nothing can be looked for. Only runs the decoder read as English sentences count: a run
    /// holds one of #38's function words, split at the run's own word gaps. A table row
    /// (`rnkswp05 0.129 0.091 …`) or a column heading holds none, and rows a detector lifts into
    /// a preserved image never reach a reader as text at all, so an unrepaired one says nothing
    /// about whether the page's prose can be trusted. Only the document's own reading is
    /// consulted, and no line geometry, so this runs where the extracted page is assembled rather
    /// than inside PDFKit's line loop.
    static func unreadGlyphs(on page: CGPDFPage, in text: String) -> Int {
        guard TextEncodingCheck.hasUnmappedFont(page) else { return 0 }
        let table = table(for: page)
        guard !table.isEmpty, let scanned = scan(page) else { return 0 }
        let haystack = text.filter { !$0.isWhitespace }
        var unread = 0
        for show in scanned.shows {
            guard let characters = table[show.fontKey] else { continue }
            var run = "", word = "", glyphs = 0, english = false
            func endWord() {
                defer { word = "" }
                let letters = word.lowercased().filter(\.isLetter)
                if letters.count >= 2, TextEncodingCheck.stopwordList.contains(letters) { english = true }
            }
            func flush() {
                endWord()
                defer { run = ""; glyphs = 0; english = false }
                guard english, run.count >= minimumCheckedRun, !haystack.contains(run) else { return }
                unread += glyphs
            }
            for glyph in show.glyphs {
                guard let character = characters[glyph.code], !character.isEmpty,
                      !character.contains(where: \.isWhitespace) else { flush(); continue }
                if glyph.startsWord { endWord() }
                run += character
                word += character
                glyphs += 1
            }
            flush()
        }
        return unread
    }

    // MARK: - One document's table, read once

    private static let lock = NSLock()
    /// The last document read, held strongly so its address cannot be reused while it is the key,
    /// and its table. Every call runs inside `NativeTextReader`'s extraction gate, so one entry
    /// serves a conversion; a second document simply replaces it.
    private nonisolated(unsafe) static var memo: (document: CGPDFDocument, table: [String: [UInt8: String]])?

    /// The characters of `page`'s document's index-glyph fonts, read from the whole document the
    /// first time a page of it asks.
    static func table(for page: CGPDFPage) -> [String: [UInt8: String]] {
        guard let document = page.document else { return [:] }
        lock.lock()
        defer { lock.unlock() }
        if let memo, memo.document === document { return memo.table }
        let table = read(document)
        memo = (document, table)
        return table
    }

    /// Forgets the memoized document. Tests that read two documents built from the same bytes
    /// call this; conversions do not need it.
    static func forgetMemoizedDocument() {
        lock.lock()
        defer { lock.unlock() }
        memo = nil
    }
}
