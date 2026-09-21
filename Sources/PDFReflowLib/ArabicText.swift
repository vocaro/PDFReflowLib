import CoreGraphics
import Foundation

/// The writing that runs right to left, and what that means for order (#41).
///
/// Arabic, Hebrew and the scripts beside them set their words from right to left while the
/// numbers, Latin terms and web addresses inside those words still run from left to right. A page
/// resolves that mixture with the Unicode Bidirectional Algorithm and then paints glyphs in one
/// direction only, so the reading has to invert a layout rather than read a string. Four rules in
/// this library were measured on writing that runs the other way and say the opposite here:
///
/// - the extracted text of a line is in logical order for the Arabic and in the page's own visual
///   order for the separators inside a number or a form identifier, because PDFKit's inversion
///   resolves `-` between `I` and `551` as right-to-left where the page resolved it as part of
///   the number (`logicalOrder`);
/// - a line the page prints with no right-to-left letter in it at all is inverted with the wrong
///   base direction, so its pieces arrive in the order the page painted them (`readsVisualOrder`);
/// - a printed row the extractor splits arrives as pieces ordered left to right, where the reader
///   takes the rightmost piece first (`LayoutReconstructor.ordered`, `BlockAssembler`);
/// - a paragraph's lines stand on one right edge, not one left edge, so the column test that
///   joins them has to measure the edge the writing starts at (`BlockAssembler`).
///
/// Every rule here keys off the writing the page itself carries, never off the declared language:
/// the corpus converts this book at library defaults, which declare English for it, and
/// `LayoutReconstructor.releasesProse` already reasons the same way about the same book.
enum ArabicText {
    /// Whether a scalar is a letter of a right-to-left script: Hebrew, Arabic, Syriac, Thaana,
    /// NKo, Samaritan and Mandaic, the Arabic supplements and extensions, and the Arabic
    /// presentation forms a font may hand back in place of the letters it shapes.
    static func isRightToLeftLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x05FF, 0x0600...0x06FF, 0x0700...0x074F, 0x0750...0x077F, 0x0780...0x07BF,
             0x07C0...0x07FF, 0x0800...0x085F, 0x0860...0x08FF, 0xFB1D...0xFB4F, 0xFB50...0xFDFF,
             0xFE70...0xFEFF:
            scalar.properties.isAlphabetic
        default:
            false
        }
    }

    /// The letters of each direction `text` carries, counted into a running total.
    private static func countLetters(_ text: some StringProtocol, rightToLeft: inout Int, latin: inout Int) {
        for scalar in text.unicodeScalars {
            if isRightToLeftLetter(scalar) { rightToLeft += 1 }
            else if EnglishText.isLatinLetter(scalar), scalar.properties.isAlphabetic { latin += 1 }
        }
    }

    /// Whether `text` is written right to left: it carries a letter of such a script, and at
    /// least as many of them as it carries Latin letters. A line of Latin inside an Arabic
    /// paragraph is not one; a page of Arabic prose with an English term in it is.
    static func readsRightToLeft(_ text: some StringProtocol) -> Bool {
        var rightToLeft = 0, latin = 0
        countLetters(text, rightToLeft: &rightToLeft, latin: &latin)
        return rightToLeft > 0 && rightToLeft >= latin
    }

    /// The same judgment over a page's lines, read from all of them together.
    static func readsRightToLeft(_ texts: [String]) -> Bool {
        var rightToLeft = 0, latin = 0
        for text in texts { countLetters(text, rightToLeft: &rightToLeft, latin: &latin) }
        return rightToLeft > 0 && rightToLeft >= latin
    }

    /// Whether a page is written right to left, read from the text of its own lines.
    static func readsRightToLeft(_ lines: [TextLine]) -> Bool {
        readsRightToLeft(lines.map(\.text))
    }

    /// Whether a run of styled text is written right to left: it carries a letter of such a
    /// script and no letter of any other.
    ///
    /// A run like this is never an inline superscript or subscript, however its metrics place it
    /// (#41). Arabic raises no letter of a word above its own line — a note mark set in Arabic
    /// text is a digit or a Latin letter — while the shaping a page applies to a joined word does
    /// shift single letters off the baseline: USCIS M-618-A page 21 raises the `ا` of `إذا` by
    /// 2.34 points and the `ف` of `للتعرف` by 1.52 on a twelve-point body, against the 1.44 an
    /// inline script needs, and both were written `<sup>` in the middle of their own words.
    static func isRightToLeftRun(_ text: some StringProtocol) -> Bool {
        var rightToLeft = false
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            guard isRightToLeftLetter(scalar) else { return false }
            rightToLeft = true
        }
        return rightToLeft
    }

    /// A mark that attaches to the text before it rather than opening what follows: the stops,
    /// commas and closing brackets both scripts set tight against the preceding word.
    static func isAttachingMark(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return switch scalar.value {
        case 0x21, 0x22, 0x27, 0x29, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F, 0x5D, 0x7D,     // ! " ' ) , . : ; ? ] }
             0x060C, 0x061B, 0x061F, 0x06D4,                                        // ، ؛ ؟ ۔
             0x2019, 0x201D:
            true
        default:
            false
        }
    }

    /// Whether a line break in right-to-left writing carries no space: the next piece opens with
    /// a mark the page set tight against the word the previous piece ended (#41).
    ///
    /// A printed row the extractor splits at a full stop hands back the stop at the head of the
    /// left-hand piece, with the space the page set after it: `…الولايات المتحدة` and
    /// `. ويطلق بعض الأشخاص`. Joining those with a space of this library's own puts the stop a
    /// space away from the sentence it ends. The test asks the left side for a right-to-left
    /// letter, so no Latin join can reach it.
    static func setsNoSpace(between left: String, and right: String) -> Bool {
        guard let last = left.reversed().first(where: { !$0.isWhitespace }),
              last.unicodeScalars.contains(where: isRightToLeftLetter),
              let first = right.first(where: { !$0.isWhitespace }) else { return false }
        return isAttachingMark(first)
    }

    // MARK: - Order

    /// The separators a number or an identifier sets between its parts: the Unicode bidirectional
    /// classes ES and CS, which the algorithm folds into the number beside them and PDFKit's
    /// inversion resolves as right-to-left instead.
    private static func isSeparator(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        return switch scalar.value {
        case 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x3A, 0x060C, 0x2010...0x2015, 0x2212: true
        default: false
        }
    }

    /// A character of a left-to-right island: a Latin letter or a digit.
    private static func isIslandLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return (scalar.value >= 0x30 && scalar.value <= 0x39)
            || (EnglishText.isLatinLetter(scalar) && scalar.properties.isAlphabetic)
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first.map { $0.value >= 0x30 && $0.value <= 0x39 } == true
    }

    /// Whether a line's brackets close before they open: a closing bracket standing where nothing
    /// has opened. A page that paints `(USCIS).` right to left paints the stop first and mirrors
    /// both brackets, and a reading that inverts it with a left-to-right base hands the
    /// characters back in that painted order, `.)USCIS(`. Nothing a page writes left to right
    /// looks like that unless a marker opened it, which is why only a right-to-left page asks.
    static func readsVisualOrder(_ text: String) -> Bool {
        var depth = 0, closedFirst = false, opened = false
        for character in text {
            switch character {
            case "(", "[", "{": depth += 1; opened = true
            case ")", "]", "}":
                if depth == 0 { closedFirst = true } else { depth -= 1 }
            default: break
            }
        }
        return closedFirst && opened
    }

    /// The order the writing states for a line the page painted right to left, as a permutation
    /// of the line's character offsets, or nil where the line already reads as it was written.
    ///
    /// `onRightToLeftPage` is the page's own writing (`readsRightToLeft`), which is what tells a
    /// line with no right-to-left letter of its own — `.)USCIS(` — from the same characters in a
    /// Latin book.
    static func logicalOrder(of characters: [Character], onRightToLeftPage: Bool) -> [Int]? {
        // Only a page whose own writing runs right to left is reordered at all, so a book set in
        // the Latin alphabet cannot reach any of this however its lines are punctuated.
        guard onRightToLeftPage else { return nil }
        let hasRightToLeft = characters.contains { $0.unicodeScalars.contains(where: isRightToLeftLetter) }
        if !hasRightToLeft {
            guard readsVisualOrder(String(characters)) else { return nil }
            return islandsRestored(in: Array(characters.indices.reversed()), of: characters)
        }
        guard hasRightToLeft else { return nil }
        return identifiersRestored(in: characters)
    }

    /// Reverses each left-to-right island back into its own order after the whole line has been
    /// reversed. An island is a run of Latin letters and digits with the separators their own
    /// neighbours make part of them, so `www.uscis.gov` is one island and the stop that ends a
    /// sentence is not part of the word before it.
    private static func islandsRestored(in order: [Int], of characters: [Character]) -> [Int] {
        var island = characters.map(isIslandLetter)
        for index in characters.indices where !island[index] && isSeparator(characters[index]) {
            if index > 0, index + 1 < characters.count, island[index - 1], island[index + 1] { island[index] = true }
        }
        var result = order
        var start = 0
        while start < result.count {
            guard island[result[start]] else { start += 1; continue }
            var end = start
            while end + 1 < result.count, island[result[end + 1]] { end += 1 }
            result.replaceSubrange(start...end, with: result[start...end].reversed())
            start = end + 1
        }
        return result
    }

    /// Restores the order of every number and identifier whose separators the reading resolved
    /// right to left: `551-I` for the form `I-551`, `3676-870-800-1` for the telephone number
    /// `1-800-870-3676` (#41).
    ///
    /// A chain is two or more runs of Latin letters and digits joined by single separators. It is
    /// repaired only where one of those separators has a digit directly beside it, because that
    /// is exactly where the page's own resolution and the reading's differ: the algorithm folds a
    /// separator between two numbers, or between a Latin term and the number after it, into the
    /// left-to-right run, and PDFKit's inversion resolves it as right-to-left and reverses the
    /// parts around it. A chain of words alone — `www.uscis.gov/uscis-elis` — is resolved the
    /// same way by both and is left exactly as it was read.
    private static func identifiersRestored(in characters: [Character]) -> [Int]? {
        var result = Array(characters.indices)
        var changed = false
        var index = 0
        while index < characters.count {
            guard isIslandLetter(characters[index]) else { index += 1; continue }
            // The chain of runs and separators that starts here, run by run. A run keeps its own
            // order — `551` is the number the page printed — and it is the runs and the
            // separators between them whose order the reading reversed.
            var segments: [ClosedRange<Int>] = []
            var separators: [Int] = []
            var end = index
            while true {
                var run = end
                while run + 1 < characters.count, isIslandLetter(characters[run + 1]) { run += 1 }
                segments.append(end...run)
                end = run
                guard end + 2 < characters.count, isSeparator(characters[end + 1]),
                      isIslandLetter(characters[end + 2]) else { break }
                separators.append(end + 1)
                segments.append((end + 1)...(end + 1))
                end += 2
            }
            defer { index = end + 1 }
            guard !separators.isEmpty else { continue }
            // A separator with a digit directly beside it is the one the two resolutions differ on.
            guard separators.contains(where: { isDigit(characters[$0 - 1]) || isDigit(characters[$0 + 1]) })
            else { continue }
            result.replaceSubrange(index...end, with: segments.reversed().flatMap { Array($0) })
            changed = true
        }
        return changed ? result : nil
    }

    /// The line's text in the order the writing states, with every attribute of every character
    /// carried with it (#41).
    static func logicalOrder(_ attributed: NSAttributedString, onRightToLeftPage: Bool) -> NSAttributedString {
        let characters = Array(attributed.string)
        guard let order = logicalOrder(of: characters, onRightToLeftPage: onRightToLeftPage) else { return attributed }
        // UTF-16 offsets are what an attributed string slices by, so each character's own span is
        // measured once and the slices are taken in the order the permutation gives.
        var spans: [NSRange] = []
        var offset = 0
        for character in characters {
            let width = String(character).utf16.count
            spans.append(NSRange(location: offset, length: width))
            offset += width
        }
        let result = NSMutableAttributedString()
        for index in order { result.append(attributed.attributedSubstring(from: spans[index])) }
        return result
    }

    /// The same reordering over plain text, for a line that carries no styled content.
    static func logicalOrder(_ text: String, onRightToLeftPage: Bool) -> String {
        let characters = Array(text)
        guard let order = logicalOrder(of: characters, onRightToLeftPage: onRightToLeftPage) else { return text }
        return String(order.map { characters[$0] })
    }
}
