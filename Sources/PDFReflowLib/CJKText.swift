import Foundation

/// The characters East Asian writing sets one em wide, and what that means for spacing.
///
/// Chinese, Japanese and Korean set no space between the characters of a word, and a justified
/// line stretches the gaps between characters rather than between words. Two rules in this
/// library assume the opposite, because both were measured on Latin text: the spacing reader
/// reads a stretched gap as a missing word space, and paragraph joining puts a space between the
/// end of one line and the start of the next. Neither is true here (#42).
enum CJKText {
    /// Whether a scalar is drawn about one em wide: the East Asian Wide and Fullwidth blocks.
    /// Ideographs, kana, Hangul, and the CJK punctuation that is set on the same body.
    static func isFullWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            true
        default:
            false
        }
    }

    /// Whether a boundary falls between two characters East Asian writing sets without a space.
    /// A boundary against Latin text is not one of these: the source's own spacing decides there,
    /// and this library neither adds nor removes it.
    static func setsNoSpace(between left: Unicode.Scalar?, and right: Unicode.Scalar?) -> Bool {
        guard let left, let right else { return false }
        return isFullWidth(left) && isFullWidth(right)
    }

    /// Whether a scalar is a Han ideograph: the Unified blocks, Extension A and the compatibility
    /// ideographs. Deliberately narrower than `isFullWidth`, which also holds the CJK punctuation
    /// a source may legitimately set a space after — a run-in heading ends `联合报税表。` and the
    /// paragraph follows it on the same line — and the fullwidth Latin forms.
    static func isIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3FFFD: true
        default: false
        }
    }

    /// Removes the spaces an extracted text layer carries between two Han ideographs, keeping
    /// every attribute of the text either side (#42).
    ///
    /// Chinese sets no space between the characters of a word, so a space here was never in the
    /// writing: it is a wide letter-spaced heading read one character at a time, or a justified
    /// line whose stretched gaps were read as words. Only a space with an ideograph directly on
    /// both sides is removed, which is why `isIdeograph` and not `isFullWidth` decides it: a
    /// space the source really does set after `。` or `，`, and every boundary with Latin text,
    /// is left exactly as read.
    static func joinIdeographs(_ attributed: NSAttributedString) -> NSAttributedString {
        let text = attributed.string as NSString
        guard text.length > 2, attributed.string.unicodeScalars.contains(where: isIdeograph) else { return attributed }
        let scalars = Array(attributed.string.unicodeScalars)
        // UTF-16 offsets are what NSAttributedString deletes by, and every character concerned
        // here is outside the BMP only for the extension blocks, so the two are walked together.
        var removals: [NSRange] = []
        var offset = 0, index = 0
        var runStart = -1, runOffset = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let width = String(scalar).utf16.count
            if scalar == " " {
                if runStart < 0 { runStart = index; runOffset = offset }
            } else {
                if runStart >= 0, runStart > 0, isIdeograph(scalars[runStart - 1]), isIdeograph(scalar) {
                    removals.append(NSRange(location: runOffset, length: offset - runOffset))
                }
                runStart = -1
            }
            offset += width
            index += 1
        }
        guard !removals.isEmpty else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        for range in removals.reversed() { result.deleteCharacters(in: range) }
        return result
    }

    /// The same test over the last character of one string and the first of another, ignoring
    /// whitespace the source already has: the join that decides whether a line break becomes a
    /// space.
    static func setsNoSpace(between left: String, and right: String) -> Bool {
        setsNoSpace(between: left.reversed().first(where: { !$0.isWhitespace })?.unicodeScalars.first,
                    and: right.first(where: { !$0.isWhitespace })?.unicodeScalars.last)
    }
}
