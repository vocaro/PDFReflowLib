import CoreGraphics
import Foundation

/// Repairs PDFKit word boundaries only where a supported text-show operation contradicts them:
/// it removes spaces that a Type3 TJ array places inside a word, and inserts the space a font
/// change, a kerned word space or a kerned sentence boundary hides. This is deliberately a small
/// evidence reader, not a replacement text extractor: every boundary traces to a measured gap
/// between two glyph advances the page's own content stream places, and a line whose shows do not
/// account for PDFKit's own characters supplies no evidence at all.
///
/// Ported onto `main`'s `ContentStreamWalk` from the abandoned
/// `claude/fable-agents-coordination-d95da7` branch's commits `9bf4e76` (#43/#110, font-change
/// spaces), `e002972` (#119, same-font word spaces from TJ adjustments) and `fbe5805` (#128/#120,
/// kerned sentence spaces, shows that continue the text cursor, character-spaced column gaps),
/// under the hand-porting convention of decision 0005. The branch carried its own scanner, written
/// before `d78ee1b` drove the text-anchor readers through one walk; the scanner here is that walk,
/// with the text matrix the visitor's own state, and the rule layer's thresholds are the branch's
/// as measured (#225).
enum NativeSpacingReader {
    struct Evidence {
        var origin: CGPoint
        var text: String?
        // UTF-16 boundaries with a positive gap of at most 0.01 em in the source TJ array.
        var smallGaps: Set<Int> = []
        /// The show decoded through any supported one-byte ToUnicode map; nil when a code
        /// has no mapping or the map is unsupported.
        var unicode: String?
        /// Page-space x where the show's glyph advances end; nil without complete widths.
        var end: CGFloat?
        /// Font size in page space and the font resource's identity, for gap and boundary tests.
        var size: CGFloat = 0
        var font: Int = 0
        /// UTF-16 offsets in `unicode` where a TJ adjustment between two glyphs of this show sets
        /// a word space without a space glyph (`sameFontWordSpace`), #119.
        var wordSpaces: Set<Int> = []
        /// UTF-16 offsets in `unicode` where sentence punctuation meets a capital or an opening
        /// quote with no measurable gap (`sentenceSpace`), #128.
        var sentenceSpaces: Set<Int> = []
        /// Sentence-space candidates whose word before or after reaches the edge of the show, with
        /// their gaps in em; `missingSpaces` decides them with the neighboring shows on the line.
        var sentenceCandidates: [Int: CGFloat] = [:]
        /// Whether the show sets nonzero character or word spacing, the producer condition of #119.
        var spaced = false

        /// The characters of the show's last word (after its last space character, word space or
        /// sentence space), and whether that word begins the show.
        var lastWord: (word: [Unicode.Scalar], startsShow: Bool)? {
            guard let unicode else { return nil }
            return NativeSpacingReader.word(in: Array(unicode.unicodeScalars), offsets: NativeSpacingReader.offsets(unicode),
                                            before: unicode.unicodeScalars.count, breaks: wordSpaces.union(sentenceSpaces))
        }

        /// The show's first word, with a trailing space where a space, word space or sentence space
        /// ends it.
        var firstWord: [Unicode.Scalar] {
            guard let unicode else { return [] }
            return NativeSpacingReader.word(in: Array(unicode.unicodeScalars), offsets: NativeSpacingReader.offsets(unicode),
                                            from: 0, breaks: wordSpaces.union(sentenceSpaces))
        }

        func extraSpaces(in native: String) -> [Int]? {
            guard let text else { return nil }
            let source = Array(text.utf16), extracted = Array(native.utf16)
            var i = 0, j = 0, removed: [Int] = []
            func letter(_ value: UInt16) -> Bool { (65...90).contains(value) || (97...122).contains(value) }
            while i < source.count, j < extracted.count {
                if source[i] == extracted[j] { i += 1; j += 1; continue }
                guard extracted[j] == 32, i > 0, smallGaps.contains(i),
                      letter(source[i - 1]), letter(source[i]),
                      j + 1 < extracted.count, extracted[j + 1] == source[i] else { return nil }
                removed.append(j); j += 1
            }
            return i == source.count && j == extracted.count && !removed.isEmpty ? removed : nil
        }
    }

    // MARK: - The line's boundaries

    /// Word boundaries that PDFKit drops at a font change: two consecutive shows on one
    /// baseline in different fonts, separated by at least 0.15 em (TeX's interword glue can
    /// shrink to about 0.17 em), with a letter or digit on either side. Returns the UTF-16
    /// offsets in `native` where a space is missing, or nil unless the shows spell the line
    /// exactly apart from PDFKit's own spaces.
    ///
    /// Two same-font boundaries are also restored (#119, the 9/11 report): a word space that a
    /// TJ adjustment sets between two glyphs of one show (`Evidence.wordSpaces`), and a note
    /// reference, a raised show of digits in a smaller size, followed by a capital at a word gap.
    static func missingSpaces(in native: String, shows: [Evidence]) -> [Int]? {
        let (source, boundaries) = line(of: shows)
        guard !source.isEmpty, !boundaries.isEmpty else { return nil }
        return ownedInsertions(in: Array(native.utf16), source: source, boundaries: boundaries)
    }

    /// How much of a PDFKit line the shows must account for before their boundaries are applied.
    /// `NativeSpacingOwnership` replaces this with the segmented walk of #139 item 1.
    static func ownedInsertions(in extracted: [UInt16], source: [UInt16], boundaries: Set<Int>) -> [Int]? {
        segmentedInsertions(in: extracted, source: source, boundaries: boundaries)
    }

    /// The offsets in `extracted` where a boundary the source draws without a space glyph is
    /// missing, provided the shows spell the whole line exactly apart from PDFKit's own spaces.
    /// The line is owned as a whole or not at all: one disagreement discards every boundary.
    static func wholeLineInsertions(in extracted: [UInt16], source: [UInt16], boundaries: Set<Int>) -> [Int]? {
        var i = 0, j = 0, inserted: [Int] = []
        while i < source.count, j < extracted.count {
            if source[i] == extracted[j] {
                if boundaries.contains(i), j > 0, !whitespace(extracted[j - 1]) { inserted.append(j) }
                i += 1; j += 1
            } else if whitespace(extracted[j]) {
                j += 1
            } else { return nil }
        }
        while j < extracted.count, whitespace(extracted[j]) { j += 1 }
        // A space glyph that ends the source line draws nothing; PDFKit trims it (9/11, #119).
        while i < source.count, j == extracted.count, whitespace(source[i]) { i += 1 }
        return i == source.count && j == extracted.count && !inserted.isEmpty ? inserted : nil
    }

    /// The gap, in ems, a font change must show before it separates two words.
    ///
    /// A page sets a number against the word after it more tightly than it spaces words: Wallace's
    /// `8cent stamps`, `3times as many` and `3places` sit at 0.12 to 0.13 em where this rule wants
    /// 0.15, and stayed fused. The narrower gap is admitted only where the run after the number
    /// opens with an English word of three letters or more, which is what keeps it off algebra —
    /// that book also sets `30qpr` and `5q`, whose runs open with no word at all (#120, #139).
    static func fontChangeGap(_ previous: Evidence, _ following: String) -> CGFloat {
        guard previous.unicode?.last?.isNumber == true,
              EnglishText.openingWord(following) != nil else { return 0.15 }
        return 0.10
    }

    static func whitespace(_ value: UInt16) -> Bool {
        UnicodeScalar(value).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
    }

    /// The line the shows spell, left to right, and the UTF-16 offsets in it where the source
    /// separates two words but draws no space glyph. The shows are the ones whose origins belong
    /// to one PDFKit line; the returned text is the source's own reading of that line, which
    /// `missingSpaces` then walks against PDFKit's.
    static func line(of shows: [Evidence]) -> (source: [UInt16], boundaries: Set<Int>) {
        var source: [UInt16] = [], boundaries: Set<Int> = []
        var previous: Evidence?
        // The line's characters with their UTF-16 offsets in `source`, the sentence-space candidates
        // at show edges, and the show transitions that separate words (#128).
        var scalars: [Unicode.Scalar] = [], scalarOffsets: [Int] = [], candidates: [(Int, CGFloat)] = [], separated: Set<Int> = []
        func word(_ character: Character?) -> Bool { character.map { $0.isLetter || $0.isNumber } ?? false }
        // Punctuation that closes a word or a formula (Wallace's `6)|when`, `Second:|m`, #120): it
        // follows a character of its own show, or its one-character show follows the one before
        // without a word gap (a space, or 0.15 em on one baseline; a subscript's shift is no gap).
        var previousStart = 0, wordGaps: Set<Int> = []
        func closesWord(_ show: Evidence, start: Int) -> Bool {
            guard let characters = show.unicode.map(Array.init), let last = characters.last, ")],;:".contains(last) else { return false }
            if characters.count >= 2 { return !characters[characters.count - 2].isWhitespace }
            return start > 0 && !wordGaps.contains(start)
        }
        for show in shows.sorted(by: { $0.origin.x < $1.origin.x }) {
            guard source.count + (show.unicode?.utf16.count ?? 0) <= 8192 else { return ([], []) }
            // A show whose text the reader cannot decode is a hole in the source's reading of the
            // line, not a reason to discard the line: the segmented walk resynchronizes across it
            // (#120, #139). One radical on Wallace page 120 discarded every boundary of
            // `5− 2x 11 Subtract 5from both sides`, including the font change between `5` and
            // `from` that the rules had already admitted. Nothing is read across the hole: the
            // show after it has no predecessor, so no boundary is computed against a character
            // the reader never saw.
            guard let unicode = show.unicode, !unicode.isEmpty else {
                previous = nil
                previousStart = source.count
                continue
            }
            if let previous {
                let size = max(previous.size, show.size)
                if abs(previous.origin.y - show.origin.y) > size * 0.1 || previous.end.map({ show.origin.x - $0 >= size * 0.1 }) != false {
                    separated.insert(source.count)
                }
                if previous.unicode?.last?.isWhitespace == true
                    || abs(previous.origin.y - show.origin.y) <= size * 0.1 && previous.end.map({ show.origin.x - $0 >= size * 0.15 }) == true {
                    wordGaps.insert(source.count)
                }
            }
            scalars += unicode.unicodeScalars
            scalarOffsets += offsets(unicode).dropLast().map { source.count + $0 }
            candidates += show.sentenceCandidates.map { (source.count + $0.key, $0.value) }
            if let previous, let end = previous.end, previous.font != show.font,
               abs(previous.origin.y - show.origin.y) <= max(previous.size, show.size) * 0.1,
               show.origin.x - end >= max(previous.size, show.size) * fontChangeGap(previous, unicode),
               word(previous.unicode?.last) || closesWord(previous, start: previousStart) && unicode.first?.isLetter == true,
               word(unicode.first) {
                boundaries.insert(source.count)
            }
            if let previous, let end = previous.end, noteReference(previous, before: show, end: end) {
                boundaries.insert(source.count)
            }
            // A sentence boundary split across two shows on one baseline (9/11's semibold speaker
            // labels, `FAA:|Yes.`), in a producer that justifies with character or word spacing (#128).
            if let previous, let end = previous.end, previous.spaced || show.spaced,
               previous.size > 0, show.size > 0, min(previous.size, show.size) >= max(previous.size, show.size) * 0.8,
               abs(previous.origin.y - show.origin.y) <= max(previous.size, show.size) * 0.1,
               let (word, startsShow) = previous.lastWord,
               sentenceSpace(word: word, startsShow: startsShow, following: show.firstWord,
                             gap: (show.origin.x - end) / max(previous.size, show.size)) {
                boundaries.insert(source.count)
            }
            for offset in show.wordSpaces.union(show.sentenceSpaces) where offset > 0 && offset < unicode.utf16.count {
                boundaries.insert(source.count + offset)
            }
            previousStart = source.count
            source += unicode.utf16
            previous = show
        }
        if !candidates.isEmpty {
            let index = Dictionary(scalarOffsets.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let lineOffsets = scalarOffsets + [source.count]
            for (offset, gap) in candidates.sorted(by: { $0.0 < $1.0 }) {
                guard let k = index[offset] else { continue }
                let breaks = boundaries.union(separated)
                let (before, startsLine) = NativeSpacingReader.word(in: scalars, offsets: lineOffsets, before: k, breaks: breaks)
                let after = NativeSpacingReader.word(in: scalars, offsets: lineOffsets, from: k, breaks: breaks)
                if sentenceSpace(word: before, startsShow: startsLine, following: after, gap: gap) { boundaries.insert(offset) }
            }
        }
        return (source, boundaries)
    }

    // MARK: - The rules

    /// Word-space gaps measured on the 9/11 report's TJ arrays (#119), as min(adjustment,
    /// adjustment + Tc) in em between two glyphs of one show with no space glyph. Before a
    /// letter, a digit or `(`, kerns end at 0.059 em and word spaces begin at 0.075 em. After a
    /// lowercase letter or punctuation, a capital that overhangs to the left (A T V W Y) or an
    /// opening quote takes the space's kern into the gap: kerns, abbreviations and initials
    /// (`N.Y.`, `W. W.`) lie at or below 0.001 em and word spaces begin at 0.003 em. Between
    /// capitals the narrow mode is kerning (Replay Clocks' Libertine small caps, `WI|TH`,
    /// +0.037 em), so it takes the letter threshold.
    static let wordSpaceGap: CGFloat = 0.066
    static let overhangWordSpaceGap: CGFloat = 0.005
    /// Character spacing of at least this many em between the two glyphs of a show is a column
    /// gap (#120: FAA's chart tables set 0.59–1.58 em; its letter-spacing stays at or below 0.2 em).
    static let characterSpacingColumnGap: CGFloat = 0.5

    /// Whether a same-font gap of `gap` em between `left` and `right` (after `before`, the
    /// character preceding `left`) is a word space. The left side ends a word (a letter, a digit,
    /// sentence punctuation or a closing quote or parenthesis) and the right side starts one (a
    /// letter, a digit, an opening quote or parenthesis). A period or colon between digits (`3.5`, `8:46`)
    /// is never a boundary, nor is a mathematical letter (TeX math italic sets kerns and italic
    /// corrections, Replay Clocks' `ℎ𝑙𝑐.𝑓`), and gaps above one em are not word spaces.
    ///
    /// A chained initial, a capital and a period before a capital that `after` (the character
    /// following `right`) makes an initial too (`C.|A.`), takes the letter threshold like two
    /// capitals: NOAA's Lora kerns `.|A` by +0.027 em inside initials it sets closed (`B.A. Muhling`)
    /// on lines with word spacing of -0.002 em (#120, reached once shows that continue the cursor
    /// were read).
    static func sameFontWordSpace(before: Unicode.Scalar?, left: Unicode.Scalar, right: Unicode.Scalar, gap: CGFloat,
                                  after: Unicode.Scalar? = nil) -> Bool {
        let letters = CharacterSet.letters, digits = CharacterSet.decimalDigits
        let closing = ".,;:?!\u{201D}\u{2019})".unicodeScalars.contains(left)
        let leftWord = letters.contains(left) || digits.contains(left) || closing
        let overhang = "ATVWY\u{201C}\u{2018}".unicodeScalars.contains(right)
        let rightWord = overhang || letters.contains(right) || digits.contains(right) || right == "("
        guard leftWord, rightWord, !mathematical(left), !mathematical(right), gap.isFinite, gap <= 1,
              // East Asian writing sets no space between characters, and justification stretches
              // the gaps between them, so a wide gap here is the line being set, not a word
              // boundary the extraction lost (#42).
              !CJKText.setsNoSpace(between: left, and: right) else { return false }
        if ".:".unicodeScalars.contains(left), let before, digits.contains(before), digits.contains(right) { return false }
        let chained = left == "." && before.map(CharacterSet.uppercaseLetters.contains) == true && after == "."
        let narrow = overhang && (closing || CharacterSet.lowercaseLetters.contains(left)) && !chained
        return gap >= (narrow ? overhangWordSpaceGap : wordSpaceGap)
    }

    /// A letter of a mathematical alphabet or a letterlike symbol, which TeX's math mode kerns and
    /// italic-corrects by amounts no prose threshold can tell from a word space.
    static func mathematical(_ scalar: Unicode.Scalar) -> Bool {
        (0x1D400...0x1D7FF).contains(scalar.value) || (0x2100...0x214F).contains(scalar.value)
    }

    /// A note reference set as its own show (9/11: a 7.2-point digit raised 2.25 points before
    /// 10.25-point text): one to four digits at most 0.8 of the next show's size, raised by 0.15
    /// to 0.6 of it, followed on the text's baseline by a capital or an opening quote at a word
    /// gap in em of the reference's size.
    static func noteReference(_ note: Evidence, before show: Evidence, end: CGFloat) -> Bool {
        guard let digits = note.unicode, (1...4).contains(digits.unicodeScalars.count),
              digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let first = show.unicode?.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) || first == "\u{201C}",
              note.size > 0, show.size > 0, note.size <= show.size * 0.8 else { return false }
        let raise = note.origin.y - show.origin.y, gap = (show.origin.x - end) / note.size
        return raise >= show.size * 0.15 && raise <= show.size * 0.6 && gap >= wordSpaceGap && gap <= 1
    }

    /// The UTF-16 offset of each Unicode scalar of `string`, plus the string's length.
    static func offsets(_ string: String) -> [Int] {
        var result: [Int] = [], offset = 0
        for scalar in string.unicodeScalars { result.append(offset); offset += scalar.utf16.count }
        return result + [offset]
    }

    /// The word that ends before scalar `index`: the scalars back to a whitespace character or
    /// to a scalar whose UTF-16 offset is a break, and whether it reaches the start.
    static func word(in scalars: [Unicode.Scalar], offsets: [Int], before index: Int,
                     breaks: Set<Int>) -> (word: [Unicode.Scalar], startsShow: Bool) {
        var start = index
        while start > 0, !scalars[start - 1].properties.isWhitespace, !breaks.contains(offsets[start]) { start -= 1 }
        return (Array(scalars[start..<index]), start == 0 && !breaks.contains(offsets[0]))
    }

    /// The word that starts at scalar `index`, up to a whitespace character or a break, with a
    /// space appended where one of those ends it (none where the show ends).
    static func word(in scalars: [Unicode.Scalar], offsets: [Int], from index: Int, breaks: Set<Int>) -> [Unicode.Scalar] {
        var end = index
        while end < scalars.count, !scalars[end].properties.isWhitespace, end == index || !breaks.contains(offsets[end]) { end += 1 }
        return Array(scalars[index..<end]) + (end < scalars.count ? [" "] : [])
    }

    /// Sentence spaces that a kern before an overhanging capital absorbs entirely (#128). 9/11 sets
    /// 331 sentence boundaries such as `casualties.The` at -0.13 to +0.005 em, where abbreviations
    /// and initials also lie, so no gap separates them. Measured on the book's own boundaries after a
    /// period before a capital, a word followed by a capitalized word or an acronym is spaced in 5,646
    /// of 5,977 (`U.S.|Army` 157 of 157, an initial `H.|Kean` 230 of 236); the only form set closed is
    /// a capital that continues an abbreviation, a capital followed by a period (`U.|S.`, `D.|C.`,
    /// `N.|Y.`: 781 of 791). So a boundary is a sentence space when:
    /// - `word`, the characters before it back to a space, ends with `. , ; : ? !`, optionally
    ///   followed by closing quotes, parentheses or brackets (`Jews.”|The`);
    /// - the punctuation follows a letter or digit, or a closing parenthesis, bracket or quote
    ///   (`(OMB).|They`); an apostrophe after a letter (`O’|Neill`, `QAEDA’|S`) and an ellipsis are not;
    /// - `following`, the word after it (with a trailing space where a space or word space ends it),
    ///   starts with a capital not followed by a period, or with an opening quote before a letter or
    ///   digit;
    /// - an initial (a capital and at most one more letter) is not followed by a capitalized
    ///   abbreviation of at most four letters that ends with a period, which is set closed (Our Flag's
    ///   title page `H.Doc. 108-97`);
    /// - the word holds no address characters (`/ @ = \`, `www`: `print.php3?|ReportID`) and no
    ///   mathematical letters;
    /// - a period does not end a number that begins the show (list and note numbers, `10.|August 2001`,
    ///   `21.|While`);
    /// - the gap is between -0.15 and 1 em.
    static func sentenceSpace(word: [Unicode.Scalar], startsShow: Bool, following: [Unicode.Scalar], gap: CGFloat) -> Bool {
        let alphanumerics = CharacterSet.alphanumerics, letters = CharacterSet.letters
        guard gap.isFinite, gap >= -0.15, gap <= 1, following.count > 1 else { return false }
        let right = following[0], next = following[1]
        guard !mathematical(right), !mathematical(next) else { return false }
        if right == "\u{201C}" || right == "\u{2018}" {
            guard alphanumerics.contains(next) else { return false }
        } else {
            guard CharacterSet.uppercaseLetters.contains(right), next != "." else { return false }
        }
        let closers = "\u{201D}\u{2019})]".unicodeScalars
        var end = word.count
        while end > 0, closers.contains(word[end - 1]) { end -= 1 }
        guard end > 1, ".,;:?!".unicodeScalars.contains(word[end - 1]) else { return false }
        let body = word[..<(end - 1)], last = body[body.endIndex - 1]
        guard !body.contains(where: { "/@=\\".unicodeScalars.contains($0) || mathematical($0) }),
              !String(String.UnicodeScalarView(body)).lowercased().contains("www") else { return false }
        if closers.contains(last) { return !body.dropLast().allSatisfy { closers.contains($0) } }
        guard alphanumerics.contains(last) else { return false }
        guard word[end - 1] == "." else { return true }
        if startsShow, body.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return false }
        let initial = Array(body.reversed().prefix { letters.contains($0) }.reversed())
        let abbreviation = following.last == " " ? Array(following.dropLast()) : following
        return !((1...2).contains(initial.count) && CharacterSet.uppercaseLetters.contains(initial[0])
                 && (3...5).contains(abbreviation.count) && abbreviation.last == "."
                 && abbreviation.dropLast().allSatisfy { letters.contains($0) })
    }

    // MARK: - Fonts

    /// Only complete one-byte bfchar maps are supported. Ranges, inherited maps, duplicate
    /// codes, ligatures and non-ASCII text fall back. A final mapped line break is tolerated.
    static func characterMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let input = String(data: data, encoding: .ascii) else { return nil }
        let text = input.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        guard !text.contains("beginbfrange"), !text.contains("usecmap"),
              text.components(separatedBy: "begincodespacerange").count == 2,
              text.range(of: #"1\s+begincodespacerange\s*<00>\s*<[fF][fF]>\s*endcodespacerange"#,
                         options: .regularExpression) != nil else { return nil }
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+beginbfchar\s*([\s\S]*?)\s*endbfchar"#)
        let pairs = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]{4}(?:000[Aa])?)>"#)
        let ns = text as NSString
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 256,
              matches.count == text.components(separatedBy: "beginbfchar").count - 1 else { return nil }
        var result: [UInt8: String] = [:]
        for block in matches {
            let body = ns.substring(with: block.range(at: 2)), bodyNS = ns.substring(with: block.range(at: 2)) as NSString
            let entries = pairs.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
            guard Int(ns.substring(with: block.range(at: 1))) == entries.count,
                  pairs.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: bodyNS.length), withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            for entry in entries {
                guard let code = UInt8(bodyNS.substring(with: entry.range(at: 1)), radix: 16), result[code] == nil else { return nil }
                let hex = bodyNS.substring(with: entry.range(at: 2))
                guard let value = UInt32(hex.prefix(4), radix: 16), let scalar = UnicodeScalar(value) else { return nil }
                // Keep the entire map, but unsupported characters disqualify a show that uses them.
                result[code] = String(scalar) + (hex.count == 8 ? "\n" : "")
            }
        }
        return result
    }

    /// A one-byte ToUnicode map with bfchar and bfrange entries whose destinations are any
    /// number of UTF-16 code units (ligatures, surrogate pairs for mathematical alphanumerics).
    /// Inherited maps, multi-byte codespaces, duplicate codes and malformed entries fall back.
    static func unicodeMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let input = String(data: data, encoding: .isoLatin1) else { return nil }
        let text = input.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        guard !text.contains("usecmap"), text.contains("begincmap"),
              text.components(separatedBy: "begincodespacerange").count == 2,
              text.range(of: #"begincodespacerange\s*<[0-9a-fA-F]{2}>\s*<[0-9a-fA-F]{2}>\s*endcodespacerange"#,
                         options: .regularExpression) != nil else { return nil }
        func units(_ hex: String) -> [UInt16]? {
            guard hex.count % 4 == 0, !hex.isEmpty, hex.count <= 64 else { return nil }
            var result: [UInt16] = [], index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 4)
                guard let unit = UInt16(hex[index..<next], radix: 16) else { return nil }
                result.append(unit); index = next
            }
            return result
        }
        func string(_ values: [UInt16]) -> String? {
            let value = String(utf16CodeUnits: values, count: values.count)
            return Array(value.utf16) == values ? value : nil
        }
        var result: [UInt8: String] = [:]
        func assign(_ code: Int, _ values: [UInt16]) -> Bool {
            guard (0...255).contains(code), result[UInt8(code)] == nil, let value = string(values) else { return false }
            result[UInt8(code)] = value
            return true
        }
        let ns = text as NSString
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+begin(bfchar|bfrange)\s*([\s\S]*?)\s*end\2"#)
        let chars = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]+)>"#)
        let ranges = try! NSRegularExpression(
            pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]{2})>\s*(?:<([0-9a-fA-F]+)>|\[((?:\s*<[0-9a-fA-F]+>)+)\s*\])"#)
        let hexes = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]+)>"#)
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 256,
              matches.count == text.components(separatedBy: "beginbf").count - 1 else { return nil }
        for block in matches {
            let kind = ns.substring(with: block.range(at: 2))
            let body = ns.substring(with: block.range(at: 3)) as NSString
            let whole = NSRange(location: 0, length: body.length)
            let expression = kind == "bfchar" ? chars : ranges
            let entries = expression.matches(in: body as String, range: whole)
            guard Int(ns.substring(with: block.range(at: 1))) == entries.count,
                  expression.stringByReplacingMatches(in: body as String, range: whole, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            for entry in entries {
                guard let low = Int(body.substring(with: entry.range(at: 1)), radix: 16) else { return nil }
                if kind == "bfchar" {
                    guard let values = units(body.substring(with: entry.range(at: 2))), assign(low, values) else { return nil }
                    continue
                }
                guard let high = Int(body.substring(with: entry.range(at: 2)), radix: 16), high >= low else { return nil }
                if entry.range(at: 3).location != NSNotFound {
                    guard var values = units(body.substring(with: entry.range(at: 3))), let last = values.last else { return nil }
                    for code in low...high {
                        guard Int(last) + (code - low) <= 0xFFFF else { return nil }
                        values[values.count - 1] = last + UInt16(code - low)
                        guard assign(code, values) else { return nil }
                    }
                } else {
                    let list = body.substring(with: entry.range(at: 4)) as NSString
                    let items = hexes.matches(in: list as String, range: NSRange(location: 0, length: list.length))
                    guard items.count == high - low + 1 else { return nil }
                    for (offset, item) in items.enumerated() {
                        guard let values = units(list.substring(with: item.range(at: 1))), assign(low + offset, values) else { return nil }
                    }
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    /// A simple font's ToUnicode map (Type1, TrueType, MMType1). A simple font's codes are one
    /// byte whatever its map declares, and Adobe PDF Library writes one-byte entries under a
    /// two-byte `<0000> <FFFF>` codespace (FAA, DGA, Fed), so that codespace is read as one byte.
    /// Any entry that is not one byte, and any other codespace, still fails the parse (#91, #104).
    static func simpleFontUnicodeMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let text = String(data: data, encoding: .isoLatin1),
              let normalized = text.replacingOccurrences(
                of: #"begincodespacerange\s*<0000>\s*<[fF]{4}>\s*endcodespacerange"#,
                with: "begincodespacerange <00> <FF> endcodespacerange", options: .regularExpression
              ).data(using: .isoLatin1) else { return nil }
        return unicodeMap(normalized)
    }

    /// One `Differences` array element: a code that starts a run, or the next code's glyph name.
    enum EncodingDifference: Equatable {
        case code(Int)
        case name(String)
    }

    /// Adobe Glyph List names a `Differences` array may assign: printable ASCII, and the quotes,
    /// dashes and ligatures TeX text fonts encode there. Any other name leaves its code undecoded.
    private static let differenceGlyphs: [String: String] = {
        var table: [String: String] = [
            "space": " ", "exclam": "!", "quotedbl": "\"", "numbersign": "#", "dollar": "$", "percent": "%",
            "ampersand": "&", "quotesingle": "'", "parenleft": "(", "parenright": ")", "asterisk": "*",
            "plus": "+", "comma": ",", "hyphen": "-", "period": ".", "slash": "/", "colon": ":",
            "semicolon": ";", "less": "<", "equal": "=", "greater": ">", "question": "?", "at": "@",
            "bracketleft": "[", "backslash": "\\", "bracketright": "]", "asciicircum": "^",
            "underscore": "_", "grave": "`", "braceleft": "{", "bar": "|", "braceright": "}",
            "asciitilde": "~", "quoteleft": "\u{2018}", "quoteright": "\u{2019}",
            "quotedblleft": "\u{201C}", "quotedblright": "\u{201D}", "endash": "\u{2013}",
            "emdash": "\u{2014}", "ff": "\u{FB00}", "fi": "\u{FB01}", "fl": "\u{FB02}",
            "ffi": "\u{FB03}", "ffl": "\u{FB04}",
        ]
        for (index, name) in ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"].enumerated() {
            table[name] = String(index)
        }
        for scalar in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            let upper = String(UnicodeScalar(scalar))
            table[upper] = upper
            table[upper.lowercased()] = upper.lowercased()
        }
        return table
    }()

    /// The codes of a Type1 font without a ToUnicode map, read through `WinAnsiEncoding` (#110).
    /// Ghostscript's TeX output (Wallace) writes no ToUnicode for its Computer Modern fonts, only
    /// this encoding, by name or as the `BaseEncoding` of a `Differences` dictionary. A Type1
    /// font draws the glyph its encoding names, so codes 32–126 read as the ASCII characters
    /// WinAnsi names, and a `Differences` entry gives its code the character of its glyph name
    /// (`differenceGlyphs`). An unknown name removes its code, so no line that draws it can be
    /// matched. More than 256 entries, a name before any code, or a code outside 0–255 fails.
    static func winAnsiUnicodeMap(differences: [EncodingDifference]) -> [UInt8: String]? {
        guard differences.count <= 256 else { return nil }
        var result: [UInt8: String] = [:]
        for code in UInt8(32)...126 { result[code] = String(UnicodeScalar(code)) }
        var next: Int?
        for entry in differences {
            switch entry {
            case .code(let code):
                guard (0...255).contains(code) else { return nil }
                next = code
            case .name(let name):
                guard let code = next, code <= 255 else { return nil }
                result[UInt8(code)] = differenceGlyphs[name]
                next = code + 1
            }
        }
        return result
    }

    private static func encodingUnicodeMap(_ dict: CGPDFDictionaryRef) -> [UInt8: String]? {
        if let name = CGPDFObjects.name(dict, "Encoding") {
            return name == "WinAnsiEncoding" ? winAnsiUnicodeMap(differences: []) : nil
        }
        guard let encoding = CGPDFObjects.dictionary(dict, "Encoding"),
              CGPDFObjects.name(encoding, "BaseEncoding") == "WinAnsiEncoding" else { return nil }
        guard let array = CGPDFObjects.array(encoding, "Differences") else {
            return winAnsiUnicodeMap(differences: [])
        }
        let count = CGPDFArrayGetCount(array)
        guard count <= 256 else { return nil }
        var differences: [EncodingDifference] = []
        for index in 0..<count {
            var code: CGPDFInteger = 0, glyph: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(array, index, &code) {
                differences.append(.code(code))
            } else if CGPDFArrayGetName(array, index, &glyph), let glyph {
                differences.append(.name(String(cString: glyph)))
            } else { return nil }
        }
        return winAnsiUnicodeMap(differences: differences)
    }

    private struct Font {
        /// The font dictionary's identity, which distinguishes fonts; never dereferenced.
        var id: Int
        /// The Type3 identity-matrix bfchar map that authorizes space removal.
        var map: [UInt8: String]?
        /// Any supported one-byte ToUnicode map, or a Type1 font's WinAnsi encoding without one,
        /// for word-boundary evidence.
        var unicode: [UInt8: String]?
        /// Simple-font glyph advances in text space per unit of font size.
        var widths: [UInt8: CGFloat]?
    }

    private static let simpleFontKinds: Set<String> = ["Type1", "TrueType", "MMType1"]

    private static func font(_ dict: CGPDFDictionaryRef) -> Font? {
        guard let kind = CGPDFObjects.name(dict, "Subtype") else { return nil }
        var result = Font(id: unsafeBitCast(dict, to: Int.self))
        let data = CGPDFObjects.rawData(dict, "ToUnicode")
        if kind == "Type3" {
            if CGPDFObjects.matrix(dict, "FontMatrix") == .identity, let data { result.map = characterMap(data) }
            return result
        }
        guard simpleFontKinds.contains(kind) else { return result }
        if let data {
            result.unicode = simpleFontUnicodeMap(data)
        } else if kind != "TrueType" {
            result.unicode = encodingUnicodeMap(dict)
        }
        if let first = CGPDFObjects.integer(dict, "FirstChar"), first >= 0, first <= 255,
           let widths = CGPDFObjects.array(dict, "Widths"), CGPDFArrayGetCount(widths) <= 256 {
            var table: [UInt8: CGFloat] = [:]
            for index in 0..<CGPDFArrayGetCount(widths) where first + index <= 255 {
                var width: CGPDFReal = 0
                guard CGPDFArrayGetNumber(widths, index, &width), width.isFinite, width >= 0 else { table = [:]; break }
                table[UInt8(first + index)] = width / 1000
            }
            if !table.isEmpty { result.widths = table }
        }
        return result
    }

    /// A Type3 font, or a simple font whose ToUnicode map and Widths can supply word-boundary
    /// evidence. Pages without either skip the operator scan entirely.
    private static func hasSupportedFont(_ page: CGPDFPage) -> Bool {
        guard let resources = CGPDFObjects.inheritedResources(of: page) else { return false }
        return CGPDFObjects.fonts(in: resources).contains { dict in
            guard let kind = CGPDFObjects.name(dict, "Subtype") else { return false }
            if kind == "Type3" { return true }
            guard simpleFontKinds.contains(kind), CGPDFObjects.array(dict, "Widths") != nil else { return false }
            return CGPDFObjects.stream(dict, "ToUnicode") != nil
                || kind != "TrueType" && encodingUnicodeMap(dict) != nil
        }
    }

    // MARK: - The scan

    /// Text state and placement this reader does not model disqualifies the whole page. The text
    /// matrix is not the walk's: a show that draws straight after another advances it by the
    /// glyphs' own widths, which only a visitor that measures them knows (`Visitor.text`).
    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.operators = ["Tc", "Tw", "Ts", "Tr", "Tz", "gs", "BI", "Do"]
        options.refusesStateChangesInText = true
        options.beginTextPositions = false
        options.selectsFonts = true
        options.maximumShowElements = 4096
        options.moveAndShow = .invalidate
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        var font: Font?
        var size: CGFloat = 0
        /// Character and word spacing (`Tc`, `Tw`) in unscaled text space units (#119).
        var characterSpacing: CGFloat = 0
        var wordSpacing: CGFloat = 0
        var saved: [(Font?, CGFloat, CGFloat, CGFloat)] = []
        /// The text matrix (Tm), which a show advances, as against the walk's line matrix (Tlm),
        /// which only `Td`, `TD`, `T*` and `Tm` move (#120: Replay Clocks' reference list draws
        /// `[([8])]TJ 0 g 0 G [-571(D)…]TJ`, where the second show continues the first's cursor).
        var text = CGAffineTransform.identity
        /// Whether the previous show left a complete advance for a show that does not position.
        var continuing = false
        var fontSelections = 0
        var fonts: [Int: Font?] = [:]
        var evidence: [Evidence] = []

        func saveState() { saved.append((font, size, characterSpacing, wordSpacing)) }
        func restoreState() {
            guard let state = saved.popLast() else { return }
            (font, size, characterSpacing, wordSpacing) = state
        }
        func beginText(_ walk: ContentStreamWalk) { text = .identity; continuing = false }
        func endText(_ walk: ContentStreamWalk) { continuing = false }

        /// TeX output reselects a font at every mathematical symbol, so a page can carry
        /// hundreds of selections; each distinct font dictionary is parsed once.
        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            fontSelections += 1
            var dict: CGPDFDictionaryRef?
            guard fontSelections <= 10_000, let resource,
                  CGPDFObjectGetValue(resource, .dictionary, &dict), let dict else { walk.invalid = true; return }
            self.size = size
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = fonts[id] { font = cached } else {
                guard fonts.count < 256 else { walk.invalid = true; return }
                font = NativeSpacingReader.font(dict)
                fonts[id] = font
            }
        }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard walk.inText, evidence.count < 10_000 else { walk.invalid = true; return }
            // A show that continues the text cursor needs the previous show's complete advance.
            if walk.positioned { text = walk.lineMatrix } else if !continuing { walk.invalid = true; return }
            continuing = false
            let transform = text.concatenating(walk.matrix)
            guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite else { walk.invalid = true; return }
            // Rotated or mirrored text (a margin stamp) supplies no word-boundary evidence and
            // does not disqualify the page's upright text.
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else { return }
            var item = Evidence(origin: CGPoint(x: transform.tx, y: transform.ty), size: size * transform.a, font: font?.id ?? 0)
            // Type3 space removal models no character or word spacing.
            var value = "", gaps: Set<Int> = [], valid = font?.map != nil && size > 0 && characterSpacing == 0 && wordSpacing == 0
            var unicode = "", advance: CGFloat = 0, trailingSpacing: CGFloat = 0, glyphStarts: Set<Int> = []
            var decodable = font?.unicode != nil && size > 0, measurable = font?.widths != nil && size > 0
            let spacing = (characterSpacing, wordSpacing)
            func append(_ string: CGPDFStringRef) {
                let count = CGPDFStringGetLength(string)
                guard count <= 4096, value.utf16.count + count <= 4096,
                      let bytes = CGPDFStringGetBytePtr(string), let font else {
                    valid = false; decodable = false; measurable = false; return
                }
                for index in 0..<count {
                    let code = bytes[index]
                    if valid, let decoded = font.map?[code] { value += decoded } else { valid = false }
                    if decodable, let decoded = font.unicode?[code], unicode.utf16.count + decoded.utf16.count <= 4096 {
                        glyphStarts.insert(unicode.utf16.count)
                        unicode += decoded
                    } else { decodable = false }
                    // A simple font's code 32 is the space that word spacing widens.
                    trailingSpacing = spacing.0 + (code == 32 ? spacing.1 : 0)
                    if measurable, let width = font.widths?[code] { advance += width * size + trailingSpacing } else { measurable = false }
                }
            }
            /// Adjusted boundaries between strings: the UTF-16 offset, the gap in em, the index of
            /// the non-empty string after it and the code count of the one before it.
            var boundaries: [(offset: Int, gap: CGFloat, string: Int, before: Int)] = []
            var previousWasString = false
            // An adjustment moves the glyphs after it. A trailing one moves none of this show's
            // glyphs, so it cannot shorten the measured end (#110: Ghostscript ends each TeX math
            // show with one, `[(5)178.4]TJ`); it moves only a show that continues the cursor.
            var pending: CGFloat = 0
            // Adjustment units since the last glyph, the number of non-empty strings so far,
            // and the code count of the last one.
            var sinceGlyph: CGFloat = 0, strings = 0, lastCount = 0
            for argument in arguments {
                switch argument {
                case .string(let string):
                    advance -= pending; pending = 0
                    let offset = unicode.utf16.count, count = CGPDFStringGetLength(string)
                    if count > 0, strings > 0, sinceGlyph != 0, size > 0 {
                        // The glyphs' own gap in em: the adjustment, less any negative character
                        // spacing that cancels it (9/11's `9:34` sets +31 against Tc -0.031 em).
                        let adjustment = -sinceGlyph / 1000
                        boundaries.append((offset, min(adjustment, adjustment + spacing.0 / size), strings, lastCount))
                    }
                    append(string); previousWasString = true
                    if count > 0 { strings += 1; lastCount = count; sinceGlyph = 0 }
                case .adjustment(let number):
                    sinceGlyph += number
                    // Consecutive/initial adjustments and actual word-size gaps are ambiguous.
                    if !previousWasString || number < -10 { valid = false }
                    if number < 0 && number >= -10 { gaps.insert(value.utf16.count) }
                    previousWasString = false
                    pending += number / 1000 * size
                case .other:
                    valid = false; decodable = false; measurable = false
                }
            }
            let trailingAdjustment = pending
            if value.hasSuffix("\n") { value.removeLast() }
            if valid, !value.isEmpty, value.utf16.allSatisfy({ (32...126).contains($0) }) {
                item.text = value; item.smallGaps = gaps
            }
            if decodable, !unicode.isEmpty {
                item.unicode = unicode
            }
            // Word spaces inside a show are read only where the producer justifies with character or
            // word spacing and folds a kerned space into an adjustment (9/11's Distiller output: 99.9%
            // of its dropped spaces). Without that state, TeX and InDesign write word spaces as space
            // glyphs or full adjustments that PDFKit keeps, and narrow gaps are kerns: NOAA's Lora
            // `E.|A.` at +0.027 em, Wallace's juxtaposed CMMI variables `x|y`.
            if decodable, !unicode.isEmpty, spacing.0 != 0 || spacing.1 != 0 {
                let scalars = unicode.utf16
                func scalar(before offset: Int) -> (Unicode.Scalar, Int)? {
                    guard offset > 0 else { return nil }
                    let index = String.Index(utf16Offset: offset, in: unicode)
                    guard let previous = unicode.unicodeScalars.index(index, offsetBy: -1, limitedBy: unicode.unicodeScalars.startIndex)
                    else { return nil }
                    return (unicode.unicodeScalars[previous], previous.utf16Offset(in: unicode))
                }
                let words = boundaries.map { boundary -> Bool in
                    guard boundary.offset > 0, boundary.offset < scalars.count,
                          let (left, leftOffset) = scalar(before: boundary.offset) else { return false }
                    let rightIndex = String.Index(utf16Offset: boundary.offset, in: unicode)
                    let right = unicode.unicodeScalars[rightIndex]
                    let afterIndex = unicode.unicodeScalars.index(after: rightIndex)
                    return NativeSpacingReader.sameFontWordSpace(
                        before: scalar(before: leftOffset)?.0, left: left, right: right, gap: boundary.gap,
                        after: afterIndex < unicode.unicodeScalars.endIndex ? unicode.unicodeScalars[afterIndex] : nil)
                }
                // Letter-spaced type (`C H A P`) adjusts every glyph alike: a boundary beside a
                // one-glyph string whose other side is also a word gap is not a word space.
                for (k, boundary) in boundaries.enumerated() where words[k] {
                    let spaced = boundaries.indices.contains { n in
                        words[n] && (boundaries[n].string == boundary.string - 1 && boundary.before == 1
                            || boundaries[n].string == boundary.string + 1 && boundaries[n].before == 1)
                    }
                    if !spaced { item.wordSpaces.insert(boundary.offset) }
                }
                // A column gap set as character spacing (#120, FAA page 458's chart table:
                // `(68)Tj 1.465 Tc -1.465 Tw (52)Tj` draws `1,685 2,599`). FAA's letter-spacing ends at
                // 0.2 em; its column gaps start at 0.6 em. Only a two-glyph show is read, so
                // letter-spaced type cannot split.
                let characterGap = spacing.0 / size
                if boundaries.isEmpty, glyphStarts.count == 2, characterGap >= NativeSpacingReader.characterSpacingColumnGap,
                   characterGap <= 10, let offset = glyphStarts.max(), offset > 0, offset < unicode.utf16.count,
                   let (left, _) = scalar(before: offset) {
                    let right = unicode.unicodeScalars[String.Index(utf16Offset: offset, in: unicode)]
                    // The characters follow the in-show word-space classes; the gap itself is above them.
                    if NativeSpacingReader.sameFontWordSpace(before: nil, left: left, right: right, gap: 1) {
                        item.wordSpaces.insert(offset)
                    }
                }
                // Sentence spaces with no measurable gap (#128): at every glyph boundary between
                // sentence punctuation and a capital or opening quote that is not already a word
                // space. A boundary without an adjustment has the character spacing as its gap.
                item.spaced = true
                let characters = Array(unicode.unicodeScalars), offsets = NativeSpacingReader.offsets(unicode)
                let gaps = Dictionary(boundaries.map { ($0.offset, $0.gap) }, uniquingKeysWith: { first, _ in first })
                let lefts = ".,;:?!\u{201D}\u{2019})]".unicodeScalars
                for k in characters.indices.dropFirst() where lefts.contains(characters[k - 1]) {
                    let offset = offsets[k]
                    guard glyphStarts.contains(offset), !item.wordSpaces.contains(offset) else { continue }
                    let breaks = item.wordSpaces.union(item.sentenceSpaces)
                    let (word, startsShow) = NativeSpacingReader.word(in: characters, offsets: offsets, before: k, breaks: breaks)
                    let following = NativeSpacingReader.word(in: characters, offsets: offsets, from: k, breaks: breaks)
                    let gap = gaps[offset] ?? min(0, spacing.0 / size)
                    if NativeSpacingReader.sentenceSpace(word: word, startsShow: startsShow, following: following, gap: gap) {
                        item.sentenceSpaces.insert(offset)
                    } else if startsShow || following.last != " " {
                        // The word or the capital's word continues into another show (an italic
                        // title, `Encyclopedia|.Six`; a show split inside a word, `June,T|enet`).
                        item.sentenceCandidates[offset] = gap
                    }
                }
            }
            // A glyph's ink ends at its width; the spacing after the last one moves no glyph.
            if measurable, advance.isFinite, advance >= 0 { item.end = transform.tx + (advance - trailingSpacing) * transform.a }
            evidence.append(item)
            // The next show may continue from this one's full advance, spacing and adjustments
            // included (Replay Clocks page 10's reference list, #120).
            let full = advance - trailingAdjustment
            if measurable, full.isFinite, abs(full) <= 100_000 {
                text = text.translatedBy(x: full, y: 0); continuing = true
            }
        }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            switch op {
            // Character and word spacing move glyphs along the baseline and are measured (#119:
            // every 9/11 page justifies with them). A value beyond one em per glyph is not
            // typesetting.
            case "Tc":
                guard let n = ContentStreamWalk.numbers(scanner, 1), abs(n[0]) <= 1000 else { walk.invalid = true; return }
                characterSpacing = n[0]
            case "Tw":
                guard let n = ContentStreamWalk.numbers(scanner, 1), abs(n[0]) <= 1000 else { walk.invalid = true; return }
                wordSpacing = n[0]
            case "Ts", "Tr":
                if ContentStreamWalk.numbers(scanner, 1) != [0] { walk.invalid = true }
            case "Tz":
                if ContentStreamWalk.numbers(scanner, 1) != [100] { walk.invalid = true }
            case "gs":
                // A graphics state parameter dictionary moves no text unless it selects a font; one
                // that does, or a missing resource, is unmodeled (#110: every Wallace page sets
                // `/OPM` by `gs`).
                guard let name = ContentStreamWalk.popName(scanner),
                      let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ExtGState", name),
                      let dict = CGPDFObjects.dictionary(of: object),
                      CGPDFObjects.object(dict, "Font") == nil else { walk.invalid = true; return }
            case "Do":
                // An XObject is opaque: an image carries no text, and a Form's content is not
                // scanned, so its text can neither supply nor contradict evidence (a line mixing
                // Form and page text fails the exact-match requirement). A missing resource
                // disqualifies the page.
                guard !walk.inText, let name = ContentStreamWalk.popName(scanner),
                      let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                      let stream = CGPDFObjects.stream(of: object), let dict = CGPDFStreamGetDictionary(stream),
                      let subtype = CGPDFObjects.name(dict, "Subtype"),
                      ["Image", "Form"].contains(subtype) else { walk.invalid = true; return }
            default:
                walk.invalid = true
            }
        }
    }

    static func read(_ page: CGPDFPage) -> [Evidence] {
        guard page.rotationAngle == 0, hasSupportedFont(page) else { return [] }
        let visitor = Visitor()
        guard ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor) else { return [] }
        return visitor.evidence
    }

    // MARK: - The line

    /// Which of the page's shows a PDFKit line's evidence is. `NativeSpacingOwnership` replaces
    /// this with the spanning rule of #139 item 1 over the held shows of #258.
    static func owningShows(_ evidence: [Evidence], bounds: CGRect, allBounds: [CGRect]) -> [Evidence] {
        spanningShows(evidence, bounds: bounds, allBounds: allBounds)
    }

    /// The shows whose origin lies in `bounds`; nil when any of them lies in another line's bounds
    /// too, because every show must belong to one line alone and overlapping rectangles are
    /// ambiguous. `NativeSpacingOwnership.heldShows` keeps the unambiguous ones instead (#258).
    static func anchoredShows(_ evidence: [Evidence], bounds: CGRect, allBounds: [CGRect]) -> [Evidence]? {
        let matches = evidence.filter { AnchorMatcher.contains(bounds, $0.origin) }
        guard matches.allSatisfy({ match in
            allBounds.filter({ AnchorMatcher.contains($0, match.origin) }).count == 1
        }) else { return nil }
        return matches
    }

    static func apply(_ evidence: [Evidence], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        guard evidence.count <= AnchorMatcher.maximumAnchors, allBounds.count <= AnchorMatcher.maximumAnchors,
              evidence.count * allBounds.count <= AnchorMatcher.maximumComparisons else { return attributed }
        let matches = owningShows(evidence, bounds: bounds, allBounds: allBounds)
        guard !matches.isEmpty else { return attributed }
        let repaired = NSMutableAttributedString(attributedString: attributed)
        if matches.count == 1, let offsets = matches[0].extraSpaces(in: attributed.string) {
            for offset in offsets.reversed() { repaired.deleteCharacters(in: NSRange(location: offset, length: 1)) }
            return repaired
        }
        // One show can carry word spaces of its own (#119); a font change needs two.
        guard let offsets = missingSpaces(in: attributed.string, shows: matches) else { return attributed }
        for offset in offsets.reversed() {
            let attributes = repaired.attributes(at: offset - 1, effectiveRange: nil)
            repaired.insert(NSAttributedString(string: " ", attributes: attributes), at: offset)
        }
        return repaired
    }
}
