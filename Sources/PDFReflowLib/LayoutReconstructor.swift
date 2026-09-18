import Foundation
import CoreGraphics

enum LayoutReconstructor {
    static func vocabulary(in pages: [PageContent]) -> Set<String> {
        var result: Set<String> = []
        var previous: String?
        for page in pages { addVocabulary(of: page, to: &result, after: &previous) }
        return result
    }

    /// Hyphen repair consults every page's words; accumulating them per page lets extraction
    /// release the page itself.
    /// A line that opens lowercase after a line-end hyphen opens with the rest of a broken word
    /// (`es-` + `timates.html`, `communi-` + `cations`), which vouches for no join: that one
    /// word is not evidence, though the same letters seen anywhere else are (#101). A compound
    /// there keeps its own unbroken hyphen (`straight-` + `and-level`), so it still counts.
    static func addVocabulary(of page: PageContent, to vocabulary: inout Set<String>) {
        var previous: String?
        addVocabulary(of: page, to: &vocabulary, after: &previous)
    }

    /// `previous` carries the line the page before this one carried on with and comes back holding
    /// this page's, so a word the page break cut in half is skipped as a word a line break cut in
    /// half is (#148). Matter outside the page's own text stream — a running head, an opinion line,
    /// a folio, a note under the last body line — neither breaks the word nor carries it on, so it
    /// leaves the carried line standing where it stands above the continuation, and is passed over
    /// where it stands below the broken word (#107). A page's text stream is its lines set in the
    /// body's size that print a letter which is no capital: a running head set in that size prints
    /// none beside its page number (the 9/11 report's `84 THE 9/11 COMMISSION REPORT` over
    /// `rorists…`, page 102), and so does a folio (Wallace page 62's `62` under `…as the pres-`),
    /// while a script without case reads as text wherever it is set. Head matter still stands as
    /// the line above the one below it, so a break among the lines before the first text-stream
    /// line is read too (Wallace page 245's `…denomi-` over `nator,…`).
    static func addVocabulary(of page: PageContent, to vocabulary: inout Set<String>,
                              after previous: inout String?) {
        let body = max(4, bodySize(page.lines))
        // A line the extractor lost its hyphen from broke a word too, so the next line opens with
        // a fragment and not a word (#157: `alter` over `nately`). It is carried with the hyphen
        // the page printed, so the fragment rule below reads it as any other break. Only a native
        // page has a measure to read this from (`blocks`).
        let measures = page.recognized || page.hasSyntheticTextStyle ? [:] : justifiedMeasures(page.lines)
        let carried = previous
        var reachedStream = false
        // The line printed above this one on this page, and the last of the page's own text stream.
        var above: String?, lastInStream: String?
        for line in page.lines {
            let inStream = abs(line.fontSize - body) <= body * 0.15 && line.text.contains(where: isMinuscule)
            var words = line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" })
            if opensBrokenWord(after: above, line: line, first: words.first)
                || (!reachedStream && opensBrokenWord(after: carried, line: line, first: words.first)) {
                words.removeFirst()
            }
            // A drop cap's initial and fragment are one word: `the`, never `he` or `ny` (#135).
            // `A`, `I` and `O` record neither, since the line alone cannot say which reading holds.
            if let split = dropCapSplit(line), words.count >= 2 {
                words.removeFirst(2)
                if !"AIO".contains(split.initial) {
                    vocabulary.insert(String(split.initial).lowercased() + split.fragment.lowercased())
                }
            }
            for word in words {
                vocabulary.insert(String(word))
            }
            addAddressVocabulary(of: line.text, to: &vocabulary)
            addNumberPrefixVocabulary(of: line.text, to: &vocabulary)
            addDashVocabulary(of: line.text, to: &vocabulary)
            above = line.text + (endsShortOfMeasure(line, measures: measures) ? "-" : "")
            if inStream {
                reachedStream = true
                lastInStream = above
            }
        }
        // A page with no text stream of its own — a plate, a full-page table — carries the word on.
        if let lastInStream { previous = lastInStream }
    }

    /// A letter that is not a capital, which is what a running head set in capitals never prints.
    /// A script without case — Arabic, Chinese — writes only such letters, so every prose line of
    /// such a book reads as its page's text, which is all this evidence can say about it.
    static func isMinuscule(_ character: Character) -> Bool { character.isLetter && !character.isUppercase }

    /// Whether a line opens with the rest of a word the line above broke (#101): the line above
    /// carries on with a hyphen, a soft hyphen or the book's own line-end sign, and this line opens
    /// in lower case with a word holding no hyphen of its own (`straight-` + `and-level` keeps its
    /// own unbroken hyphen, so it is a compound the book prints and not a fragment).
    private static func opensBrokenWord(after previous: String?, line: TextLine, first: Substring?) -> Bool {
        guard let previous, previous.hasSuffix("-") || previous.hasSuffix("\u{00ad}") || endsWithEqualsHyphen(previous),
              line.text.first?.isLowercase == true, let first, !first.contains("-") else { return false }
        return true
    }

    /// A line whose last character may be a book's line-end hyphen printed as `=` (#126): the 9/11
    /// report's chapters 5–9 set every word break with the Bembo `equal` glyph (`worship=`, `Feb=`),
    /// which extracts as `=`. The sign follows two ASCII letters with no space, the line holds no
    /// other `=`, and its last word is not a web address (`?letter=`). Math sets its terms as
    /// letters too (`b=`, `slope=`), so this shape alone decides nothing; `EqualsHyphenEvidence`
    /// decides per book.
    static func endsWithEqualsHyphen(_ text: String) -> Bool {
        guard text.hasSuffix("="), !text.dropLast().contains("=") else { return false }
        let letters = text.dropLast().suffix(2)
        guard letters.count == 2, letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        let word = text.split(whereSeparator: \.isWhitespace).last ?? ""
        return !word.contains(where: { "/?&#@".contains($0) }) && !word.lowercased().contains("www.")
    }

    /// Book-level evidence that `=` at a line end is the book's hyphen (#126). A break is a line
    /// `endsWithEqualsHyphen` accepts whose next line opens lowercase; every other line holding
    /// `=` counts against. The 9/11 report has 993 breaks against 5 URL-query lines; no other
    /// English corpus book has a single break (Wallace's `slope=` and `16oz=` lines continue with
    /// numbers, its `b=` + `c` and `sinθ=` + `opposite` fail the letter test). Hundreds of
    /// breaks, outnumbering other `=` lines ten to one, mark the book.
    struct EqualsHyphenEvidence: Equatable {
        var breaks = 0
        var equations = 0

        var marksHyphens: Bool { breaks >= 100 && equations * 10 <= breaks }

        mutating func add(_ page: PageContent) {
            guard !page.recognized else { return }
            for (index, line) in page.lines.enumerated() where line.text.contains("=") {
                if LayoutReconstructor.endsWithEqualsHyphen(line.text) {
                    if index + 1 < page.lines.count, page.lines[index + 1].text.first?.isLowercase == true { breaks += 1 }
                } else {
                    equations += 1
                }
            }
        }
    }

    /// Rewrites each line-end `=` that `endsWithEqualsHyphen` accepts to `-` in a book whose
    /// evidence marks `=` as its hyphen, before any reconstruction reads the page. The hyphen
    /// policy then decides the join (`terror=` + `ist` joins, `mid=` + `1990s` keeps its hyphen),
    /// and the formula seed no longer reads the line as an equation.
    static func restoreEqualsHyphens(_ page: inout PageContent) {
        guard !page.recognized else { return }
        for index in page.lines.indices where endsWithEqualsHyphen(page.lines[index].text) {
            let old = page.lines[index]
            guard case let .text(value, style)? = old.content.elements.last, value.hasSuffix("=") else { continue }
            var content = old.content
            content.elements[content.elements.count - 1] = .text(String(value.dropLast()) + "-", style)
            var line = TextLine(content: content, rect: old.rect, fontSize: old.fontSize, monospaced: old.monospaced,
                                wraps: old.wraps)
            line.readingRect = old.readingRect
            line.structure = old.structure
            line.listTag = old.listTag
            page.lines[index] = line
        }
    }

    /// A drop cap's initial and the rest of its word, when PDFKit reads them apart (#135). The line
    /// must carry `NativeTextReader`'s drop-cap evidence (a `readingRect`: a lowered initial at two to
    /// eight times the size of consistent body prose that opens in lowercase), and its text must open
    /// with one capital letter, whitespace and a lowercase letter. Our Flag sets `T` then `he Stars…`
    /// and PDFKit keeps the space glyph that follows the initial in its script font. A display
    /// numeral (the Fed's chapter openers) is not a letter and never has a `readingRect`.
    static func dropCapSplit(_ line: TextLine) -> (initial: Character, fragment: Substring)? {
        guard line.readingRect != nil, let initial = line.text.first, initial.isUppercase, initial.isLetter else { return nil }
        let rest = line.text.dropFirst()
        guard let start = rest.firstIndex(where: { !$0.isWhitespace }), start != rest.startIndex,
              rest[start].isLowercase else { return nil }
        return (initial, rest[start...].prefix(while: \.isLetter))
    }

    /// Whether a drop cap's initial keeps the space before the rest of its line. A letter that is no
    /// word joins (`T he` → `The`). `A`, `I` and `O` are words: they join unless the book spells the
    /// fragment as a word of its own and never the joined word (`A new` stays; `A ny` → `Any`,
    /// `A rcheological` → `Archeological`). `addVocabulary` never records a drop-cap line's fragment.
    static func dropCapKeepsSpace(initial: Character, fragment: Substring, vocabulary: Set<String>) -> Bool {
        guard "AIO".contains(initial) else { return false }
        let word = fragment.lowercased()
        return vocabulary.contains(word) && !vocabulary.contains(String(initial).lowercased() + word)
    }

    /// Joins each drop cap's initial to its word before reconstruction reads the page (#135).
    static func joinDropCapInitials(_ page: inout PageContent, vocabulary: Set<String>) {
        for index in page.lines.indices {
            let old = page.lines[index]
            guard let split = dropCapSplit(old),
                  !dropCapKeepsSpace(initial: split.initial, fragment: split.fragment, vocabulary: vocabulary) else { continue }
            var elements = old.content.elements
            // Drop the whitespace between the initial and the fragment, across element boundaries.
            var seenInitial = false
            var position = 0
            while position < elements.count {
                guard case let .text(value, style) = elements[position] else { break }
                var kept = ""
                var done = false
                for character in value {
                    if done { kept.append(character); continue }
                    if !seenInitial {
                        kept.append(character)
                        if !character.isWhitespace { seenInitial = true }
                    } else if character.isWhitespace {
                        continue
                    } else {
                        kept.append(character); done = true
                    }
                }
                elements[position] = .text(kept, style)
                if done { break }
                position += 1
            }
            elements.removeAll { if case let .text(value, _) = $0 { value.isEmpty } else { false } }
            page.lines[index].replaceContent(InlineText(elements: elements))
        }
    }

    /// A compound the source sets with a space after its hyphen, inside one printed line
    /// (#148): the Fed's `check- collection` (pages 95 and 96) and `community- oriented` (118),
    /// the FAA's `low- wing` (364), `self- imposed` (447) and `Service- Broadcast` (12 and 333).
    /// No line-end rule reaches these, because no line ends there. The book's own setting decides,
    /// as it decides a line-end hyphen: the hyphen closes up when the book prints the compound as
    /// one word elsewhere (`check-collection` 7 times, `low-wing` 6, `self-imposed` 6).
    ///
    /// Both halves are letters, so a hyphen between numbers is never touched: `12- 15`, a fraction
    /// or a subtraction, can be no vocabulary word, since word splitting reads letters and hyphens
    /// alone. A suspended hyphen keeps its space for the same reason — the book never prints
    /// `low-and` beside `low- and moderate-income`, `consumer-and` or `ultra-high-and`.
    ///
    /// Failing that, the book may print an em dash where this line prints a hyphen: the FAA's
    /// `Commuter Category Airplanes- 14 CFR part 23` stands among `Transport Category
    /// Airplanes—14 CFR part 25` and `Normal Category—14 CFR part 27` (page 73). The dash the book
    /// sets between the same two words replaces the hyphen and its space. Nothing is normalized
    /// without one of these two kinds of evidence, so a source typo the book never resolves stays
    /// as printed.
    static func closeSpacedCompounds(_ page: inout PageContent, vocabulary: Set<String>) {
        for index in page.lines.indices {
            guard page.lines[index].text.contains("- ") else { continue }
            var elements = page.lines[index].content.elements
            var changed = false
            for position in elements.indices {
                guard case let .text(value, style) = elements[position] else { continue }
                guard let replacement = closingSpacedCompounds(value, vocabulary: vocabulary) else { continue }
                elements[position] = .text(replacement, style)
                changed = true
            }
            if changed { page.lines[index].replaceContent(InlineText(elements: elements)) }
        }
    }

    /// `text` with every evidenced `x- y` closed up, or nil where none is (`closeSpacedCompounds`).
    /// The left half is the run of letters and hyphens ending at the hyphen; it must open the word
    /// (nothing but whitespace, an opening bracket or a quote stands before it), so no break inside
    /// a web address is read. The book's own compound decides first, over the halves' letters
    /// alone; then the book's own em dash, over letters or digits, and only before a digit or a
    /// capital, since a dash joins a name to a number or to another name (`Airplanes—14`) while a
    /// suspended hyphen always carries on in lower case (NOAA prints `region- and scale-dependent`
    /// on one page and, in a parenthetical elsewhere, `region—and`).
    static func closingSpacedCompounds(_ text: String, vocabulary: Set<String>) -> String? {
        let opening = Set(" \t\u{a0}([{\u{201C}\u{2018}\"'")
        let characters = Array(text)
        var result = ""
        var index = 0
        var changed = false
        while index < characters.count {
            defer { index += 1 }
            guard characters[index] == "-", index + 1 < characters.count, characters[index + 1] == " " else {
                result.append(characters[index])
                continue
            }
            let left = String(characters[..<index].reversed().prefix(while: { $0.isLetter || $0 == "-" }).reversed())
            let rest = characters[(index + 2)...]
            let letters = String(rest.prefix(while: \.isLetter))
            let coded = String(rest.prefix(while: { $0.isLetter || $0.isNumber }))
            let before = characters[..<(index - left.count)].last
            func closes(_ right: String) -> Bool {
                rest.dropFirst(right.count).first.map { !$0.isLetter && !$0.isNumber && $0 != "-" } ?? true
            }
            guard left.count >= 2, left.first?.isLetter == true, before.map(opening.contains) ?? true else {
                result.append(characters[index])
                continue
            }
            if letters.count >= 2, closes(letters), vocabulary.contains((left + "-" + letters).lowercased()) {
                result.append("-")
            } else if coded.first.map({ $0.isNumber || $0.isUppercase }) ?? false, closes(coded),
                      vocabulary.contains(dashKey + (left + "\u{2014}" + coded).lowercased()) {
                result.append("\u{2014}")
            } else {
                result.append(characters[index])
                continue
            }
            changed = true
            index += 1
        }
        return changed ? result : nil
    }

    /// Words the book sets as a compound's first half before a number, inside a line (`mid-1980s`,
    /// `pre-9/11`), for a line-end hyphen before a digit (#131). Word splitting drops the digits,
    /// so `mid-1980s` would leave only `mid-`, which every line ending `mid-` leaves too; the
    /// entries sit under a prefix no word can hold.
    static func addNumberPrefixVocabulary(of text: String, to vocabulary: inout Set<String>) {
        guard text.contains("-") else { return }
        let characters = Array(text)
        for index in characters.indices.dropFirst().dropLast() where characters[index] == "-" {
            guard characters[index + 1].isASCII, characters[index + 1].isNumber else { continue }
            let word = characters[..<index].reversed().prefix(while: \.isLetter)
            if !word.isEmpty { vocabulary.insert(numberPrefixKey + String(word.reversed()).lowercased()) }
        }
    }

    /// Pairs the book sets around an em dash with no space (`Airplanes—14`), for a mid-line hyphen
    /// the source printed where its neighbours print a dash (#148). The entries sit under a prefix
    /// no word can hold, because a word's own split drops the dash and the digits beside it.
    static func addDashVocabulary(of text: String, to vocabulary: inout Set<String>) {
        guard text.contains("\u{2014}") else { return }
        let characters = Array(text)
        for index in characters.indices where characters[index] == "\u{2014}" {
            let left = characters[..<index].reversed().prefix(while: { $0.isLetter || $0.isNumber })
            let right = characters[(index + 1)...].prefix(while: { $0.isLetter || $0.isNumber })
            guard left.count >= 2, !right.isEmpty else { continue }
            vocabulary.insert(dashKey + (String(left.reversed()) + "\u{2014}" + String(right)).lowercased())
        }
    }

    /// Web addresses seen unbroken, for resolving a line-end hyphen inside an address (#88). The
    /// entries share the word set under prefixes no word can hold: every prefix of an address
    /// that ends at `/ . ? # & = :` or at its end, and every segment between those characters,
    /// lowercased and without scheme or `www.`. An address ending its line may continue on the
    /// next, so its last segment is not evidence.
    static func addAddressVocabulary(of text: String, to vocabulary: inout Set<String>) {
        guard text.contains("/") || text.contains("www.") || text.contains("WWW.") else { return }
        let words = text.split(whereSeparator: \.isWhitespace)
        for (index, word) in words.enumerated() where word.contains("/") || word.lowercased().contains("www.") {
            let run = String(word.reversed().drop { !addressCharacters.contains($0) }.reversed())
            guard let address = trailingAddress(run) else { continue }
            // A line's first word may continue an address broken on the line above (`federalre-` +
            // `serve.gov/…`): without a scheme or `www.`, its first segment is not evidence.
            var fragmentSegment = index == 0
                && address.range(of: "^(?:[A-Za-z][A-Za-z0-9+.-]*://|www\\.)", options: [.regularExpression, .caseInsensitive]) == nil
            var normalized = Substring(normalizedAddress(address))
            while let last = normalized.last, ".,;:)]".contains(last) { normalized.removeLast() }
            if index == words.count - 1 {
                guard let cut = normalized.lastIndex(where: { addressDelimiters.contains($0) }) else { continue }
                normalized = normalized[..<cut]
            }
            guard !normalized.isEmpty else { continue }
            vocabulary.insert(addressPrefixKey + normalized)
            var segmentStart = normalized.startIndex
            for position in normalized.indices where addressDelimiters.contains(normalized[position]) {
                vocabulary.insert(addressPrefixKey + normalized[..<position])
                if segmentStart < position, !fragmentSegment { vocabulary.insert(addressSegmentKey + normalized[segmentStart..<position]) }
                fragmentSegment = false
                segmentStart = normalized.index(after: position)
            }
            if segmentStart < normalized.endIndex, !fragmentSegment { vocabulary.insert(addressSegmentKey + normalized[segmentStart...]) }
        }
    }

    static func stripFurniture(_ pages: inout [PageContent]) -> [ConversionWarning] {
        FurnitureDetector.strip(&pages)
    }

    /// A brace drawn in type (#152): a column of at least three lines, each a single bracket glyph,
    /// on one left edge (within a point) in one size, one under the next at no more than twice
    /// their height. A court caption sets fifteen `)` down the middle of the page between the
    /// parties and the case number, the way a typewriter drew the brace; they read as a paragraph
    /// of fifteen brackets. A bracket in text stands beside words, and a matrix's brackets are
    /// part of a formula's crop. The brace still divides the caption: it stands in the reading
    /// order as a boundary, so the parties on its left read before the case number on its right,
    /// as they did while its brackets were text.
    static func bracketColumns(in lines: [TextLine]) -> [[TextLine]] {
        let brackets = lines.filter { line in
            line.readingDirection == nil && !line.monospaced
                && ["(", ")", "[", "]", "{", "}"].contains(line.text.trimmingCharacters(in: .whitespaces))
        }
        var result: [[TextLine]] = []
        var edges: [[TextLine]] = []
        for line in brackets {
            if let index = edges.firstIndex(where: { abs($0[0].rect.minX - line.rect.minX) <= 1 }) {
                edges[index].append(line)
            } else { edges.append([line]) }
        }
        for edge in edges {
            var column: [TextLine] = []
            func close() {
                if column.count >= 3 { result.append(column) }
                column = []
            }
            for line in edge.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
                if let last = column.last, !(abs(last.fontSize - line.fontSize) <= last.fontSize * 0.1
                    && last.rect.minY - line.rect.maxY <= max(last.rect.height, line.rect.height)
                    && last.rect.minY > line.rect.minY) {
                    close()
                }
                column.append(line)
            }
            close()
        }
        return result
    }

    /// A painted 1-pt rule after GraphicsReader's two-point padding: an underline, a
    /// column-header rule or a separator, never a figure on its own.
    static func isThinRule(_ rect: CGRect) -> Bool {
        rect.height <= 6 && rect.width >= max(12, rect.height * 3)
    }

    /// A thin rule spanning at least half of the page's text that no text sits against: nothing
    /// within one body size above or below it, or only a running head's row of body-sized text
    /// between it and the page edge with all other text beyond it (The Fed Explained's header
    /// rule on every page, #66). It carries nothing a reader needs as an image. A rule set
    /// directly beneath a heading (Our Flag page 27's section rules, 1.6 pt under 22-pt titles)
    /// or beside table text still has text within a body size and is not decoration here.
    static func isDecorationRule(_ rule: CGRect, in lines: [TextLine], bounds: CGRect, body: CGFloat) -> Bool {
        guard isThinRule(rule), !lines.isEmpty, !lines.contains(where: { $0.rect.intersects(rule) }) else { return false }
        let text = union(lines.map(\.rect))
        guard rule.width >= text.width * 0.5 else { return false }
        let near = lines.filter { $0.rect.intersects(rule.insetBy(dx: 0, dy: -body)) }
        guard let first = near.first else { return true }
        let above = first.rect.midY > rule.midY
        guard near.allSatisfy({ ($0.rect.midY > rule.midY) == above && $0.fontSize <= body * 1.2
                                && sameRow($0.rect, first.rect) }) else { return false }
        // The running head sits between the rule and the page edge; everything else lies beyond.
        let beyond = lines.filter { line in !near.contains { $0.rect == line.rect && $0.text == line.text } }
        let margin = bounds.height * 0.12
        return above ? beyond.allSatisfy { $0.rect.maxY <= rule.midY } && first.rect.minY >= bounds.maxY - margin
                     : beyond.allSatisfy { $0.rect.minY >= rule.midY } && first.rect.maxY <= bounds.minY + margin
    }

    /// A short rule between a compact mathematical term above it and a term starting directly
    /// beneath it is a fraction bar, whose numerator and denominator belong in one crop, not an
    /// underline. Label underlines have worded prose above them. PDFKit can merge a denominator
    /// with the annotation or the next numerator beside it, so terms are matched by extent.
    static func isFractionBar(_ rule: CGRect, in lines: [TextLine], body: CGFloat) -> Bool {
        guard isThinRule(rule) else { return false }
        let numerator = lines.contains { line in
            !line.monospaced && line.text.count <= 40
                && line.text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil
                && line.rect.maxY > rule.maxY && line.rect.minY <= rule.maxY + body * 1.2
                && line.rect.maxX > rule.minX && line.rect.minX < rule.maxX
        }
        return numerator && lines.contains { line in
            !line.monospaced && line.text.count <= 40
                && line.rect.minY < rule.minY && line.rect.maxY >= rule.minY - body * 1.2
                && line.rect.minX >= rule.minX - body * 0.5 && line.rect.minX <= rule.maxX
                && line.rect.width >= rule.width * 0.15
        }
    }

    /// The text line a thin rule underlines: the rule lies within the line's horizontal extent
    /// and at or just below its baseline region, not up in the ascenders of the line beneath.
    static func underlinedLine(_ rule: CGRect, in lines: [TextLine]) -> TextLine? {
        guard isThinRule(rule), !isFractionBar(rule, in: lines, body: max(4, bodySize(lines))) else { return nil }
        return lines.filter { line in
            rule.minX >= line.rect.minX - 3 && rule.maxX <= line.rect.maxX + 3
                && rule.midY >= line.rect.minY - 3 && rule.midY <= line.rect.minY + line.rect.height * 0.5
        }.min { $0.rect.width < $1.rect.width }
    }

    /// Whether a seed region captures a text line. Tall PDFKit line rectangles include leading,
    /// so a thin rule touches the rectangles of the lines above and below without crossing
    /// their glyphs; it captures only text it actually strikes through.
    private static func captures(_ seed: CGRect, _ line: TextLine) -> Bool {
        // A corner that grazes a line by a fraction of a point holds none of its glyphs: the
        // magazine's index rules end a tenth of a point inside the first entry of a column, and
        // its holly ornament a half point inside the title beside it (#158).
        let overlap = seed.intersection(line.rect)
        guard !overlap.isNull, overlap.width >= 1, overlap.height >= 1 else { return false }
        guard isThinRule(seed) else { return true }
        let core = line.rect.insetBy(dx: 0, dy: line.rect.height * 0.25)
        return seed.midY >= core.minY && seed.midY <= core.maxY
    }

    /// Pieces of one visual row (PDFKit splits rows at wide gaps; superscripts are separate lines).
    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.5
    }

    /// A piece that is nothing but a list marker: a bullet, or a number of up to three digits or
    /// a single letter followed by `.` or `)`. A minus or hyphen alone is a sign or a rule.
    private static func isMarkerPiece(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces)
            .range(of: "^(?:•|[0-9]{1,3}[.)]|[A-Za-z][.)])$", options: .regularExpression) != nil
    }

    /// PDFKit splits a list marker from its item's text at the gap after the marker: `4.` and
    /// `Neither the intelligence community…` on one baseline (9/11 page 365), and `•` apart from
    /// most FAA and NOAA bullets. Neither piece reads as a list line, so the marker became a
    /// paragraph of its own or joined the end of the block above (FAA page 27's `…reasons: •`),
    /// and its item's text opened an unmarked paragraph. A marker piece that opens its row (no piece on that row ends within one of its
    /// font sizes to its left) joins the nearest piece that starts to its right within two font
    /// sizes, at the same size and in the same structure group, which is not itself a marker
    /// piece. Every other line passes through unchanged (#69).
    ///
    /// Both pieces of a tagged join belong to one validated group (the FAA handbook tags each
    /// bullet item, marker and text, as one `P`). The joined line keeps that group, sorts at the
    /// earlier of the two pieces' orders, and every line of the group counts one line fewer, so the
    /// group stays complete. Its lines record that the group opens with a rejoined marker, which
    /// is what lets `structuredOrder` accept a group holding exactly that one list item (#81).
    ///
    /// An outline sets its markers on tab stops (#152): the US Courts form hangs `I.`, `A.` and `a.`
    /// a half inch left of their titles, 2.3 to 2.6 font sizes of white space after the marker. Such
    /// a gap still joins when both the marker and the text stand on edges the page repeats — its
    /// tab stops, each shared by at least one other line starting there — up to three and a half
    /// font sizes.
    static func joiningMarkerPieces(_ lines: [TextLine]) -> [TextLine] {
        var result = lines
        // Pieces already joined, and the marker pieces absorbed into the piece beside them.
        var claimed = Set<Int>(), absorbed = Set<Int>()
        // Tagged groups that absorbed a marker piece, with the number of pieces each absorbed.
        var joinedGroups: [Int: Int] = [:]
        func tabStop(_ line: TextLine) -> Bool {
            lines.contains { other in other != line && !sameRow(other.rect, line.rect) && abs(other.rect.minX - line.rect.minX) <= 1 }
        }
        for (index, marker) in lines.enumerated() where !claimed.contains(index) && !marker.monospaced
            && isMarkerPiece(marker.text) {
            let size = marker.fontSize
            let row = lines.indices.filter { $0 != index && !claimed.contains($0) && sameRow(lines[$0].rect, marker.rect) }
            guard !row.contains(where: {
                lines[$0].rect.minX < marker.rect.minX && lines[$0].rect.maxX >= marker.rect.minX - size
            }) else { continue }
            let pieces = row.filter { other in
                let line = lines[other]
                let gap = line.rect.minX - marker.rect.maxX
                return gap >= -1 && (gap <= size * 2 || gap <= size * 3.5 && tabStop(marker) && tabStop(line))
                    && abs(line.fontSize - size) <= size * 0.1
                    && !line.monospaced && line.structure?.group == marker.structure?.group
                    && !isMarkerPiece(line.text)
            }
            guard let target = pieces.min(by: { lines[$0].rect.minX < lines[$1].rect.minX }) else { continue }
            let text = lines[target]
            var content = marker.content
            content.append(InlineText(" "))
            content.append(text.content)
            var joined = TextLine(content: content, rect: marker.rect.union(text.rect), fontSize: text.fontSize,
                                  wraps: text.wraps)
            joined.readingRect = text.readingRect.map { $0.union(marker.rect) }
            joined.listTag = sharedListTag([marker, text])
            // The join requires one group on both sides, so both tags are nil or both are set.
            if var tag = text.structure, let markerTag = marker.structure {
                tag.order = min(tag.order, markerTag.order)
                joined.structure = tag
                joinedGroups[tag.group, default: 0] += 1
            }
            result[target] = joined
            claimed.formUnion([index, target])
            absorbed.insert(index)
        }
        var kept = result.indices.filter { !absorbed.contains($0) }.map { result[$0] }
        guard !joinedGroups.isEmpty else { return kept }
        for index in kept.indices {
            guard let group = kept[index].structure?.group, let pieces = joinedGroups[group] else { continue }
            kept[index].structure?.lineCount -= pieces
            kept[index].structure?.opensWithSplitMarker = true
        }
        return kept
    }

    /// A form's row of type with its ruled blanks (#152). The US Courts form sets fill-in sentences
    /// across the page's blanks (`The plaintiff, (name) ____, is a citizen of the`), and sets a
    /// field label on each blank of a stack (`Name ____`, `Street Address ____`). PDFKit returns the
    /// text on either side of a blank as separate lines, so each sentence came apart at every blank,
    /// and the labels, one per row, ran on into one paragraph.
    ///
    /// The blanks are the form's own evidence (`AnnotationEvidence.blanks`): a one-line field
    /// sharing a row with a line (`FormBlank.sharesRow`) is set in that row. Its row holds the
    /// nearest untagged line ending before the blank and the nearest starting after it, and the
    /// pieces and blanks of one row read left to right as one line, each blank written as
    /// `FormBlank.text`: `The plaintiff, (name) ____, is a citizen of the`, `____.`. Punctuation
    /// that follows a blank closes up to it. A row that ends in a blank is complete, as a label on
    /// its field is, so its line does not wrap onto the next (`wraps` false); a row that ends in
    /// text wraps as its last piece did, so a sentence runs on to the next row. A blank on no row
    /// of type — an answer area's closing rule, a caption's name line — joins nothing.
    static func joiningBlankRows(_ lines: [TextLine], blanks: [FormBlank]) -> [TextLine] {
        guard !blanks.isEmpty else { return lines }
        func eligible(_ line: TextLine) -> Bool {
            line.structure == nil && !line.monospaced && line.readingDirection == nil
                && !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        // Each row's pieces (line indices) and blanks (rule extents without padding), by root piece.
        var parent = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        var rowBlanks: [(piece: Int, rule: CGRect)] = []
        for blank in blanks {
            let rule = blank.rule.insetBy(dx: 2, dy: 0)
            let row = lines.indices.filter { eligible(lines[$0]) && blank.sharesRow(with: lines[$0].rect) }
            // Text standing over the rule is something else (a filled-in value): leave the row alone.
            guard !row.contains(where: { lines[$0].rect.maxX > rule.minX + 2 && lines[$0].rect.minX < rule.maxX - 2 })
            else { continue }
            let left = row.filter { lines[$0].rect.maxX <= rule.minX + 2 }.max { lines[$0].rect.maxX < lines[$1].rect.maxX }
            let right = row.filter { lines[$0].rect.minX >= rule.maxX - 2 }.min { lines[$0].rect.minX < lines[$1].rect.minX }
            guard let anchor = left ?? right else { continue }
            if let left, let right { parent[root(right)] = root(left) }
            rowBlanks.append((anchor, rule))
        }
        guard !rowBlanks.isEmpty else { return lines }
        var replaced: [Int: TextLine] = [:]
        var removed = Set<Int>()
        let rows = Dictionary(grouping: lines.indices.filter { index in
            rowBlanks.contains { root($0.piece) == root(index) }
        }, by: root)
        for (_, members) in rows {
            enum Item { case piece(Int), blank(CGRect) }
            let blanksHere = rowBlanks.filter { root($0.piece) == root(members[0]) }.map(\.rule)
            let items = (members.map { Item.piece($0) } + blanksHere.map { Item.blank($0) }).sorted { a, b in
                func x(_ item: Item) -> CGFloat {
                    switch item { case let .piece(index): lines[index].rect.midX; case let .blank(rule): rule.midX }
                }
                return x(a) < x(b)
            }
            var content = InlineText()
            var afterBlank = false
            for item in items {
                switch item {
                case let .piece(index):
                    let text = lines[index].text
                    let closesUp = afterBlank && text.first.map { ",.;:)!?".contains($0) } == true
                    if !content.elements.isEmpty, !closesUp { content.append(InlineText(" ")) }
                    content.append(lines[index].content)
                    afterBlank = false
                case .blank:
                    if !content.elements.isEmpty { content.append(InlineText(" ")) }
                    content.append(InlineText(FormBlank.text))
                    afterBlank = true
                }
            }
            let pieces = members.map { lines[$0] }
            let text = union(pieces.map(\.rect))
            let extent = union(pieces.map(\.rect) + blanksHere)
            let last = pieces.max { $0.rect.maxX < $1.rect.maxX }!
            var joined = TextLine(content: content, rect: CGRect(x: extent.minX, y: text.minY, width: extent.width, height: text.height),
                                  fontSize: pieces.map(\.fontSize).max() ?? last.fontSize,
                                  wraps: afterBlank ? false : last.wraps)
            joined.trailingSpace = !afterBlank && last.trailingSpace
            joined.listTag = sharedListTag(pieces.sorted { $0.rect.minX < $1.rect.minX })
            // The row keeps the reading position of its earliest piece in page order.
            let anchor = members.min()!
            replaced[anchor] = joined
            removed.formUnion(members.filter { $0 != anchor })
        }
        return lines.indices.compactMap { index in
            removed.contains(index) ? nil : replaced[index] ?? lines[index]
        }
    }

    /// PDFKit splits a prose row at an inline radical: `Not all numbers have a nice even square
    /// root. For example, if we found 8` and `√ on` (Wallace page 288), `process is being able to
    /// translate a problem like 180 √ into 36· 5` and `√ . There are sev-` (page 289). Each piece
    /// used to open a paragraph of its own, and a piece whose radical sign raised its rectangle
    /// sorted a line early (#95). The pieces of one row rejoin into one line before anything reads
    /// the lines.
    ///
    /// Radical signs overshoot a row's type by most of a line above and below, so rectangle
    /// overlap alone cannot tell a row from its neighbour (page 288's last two rows overlap by 14
    /// points). Two pieces can belong to one row when they are untagged, not monospaced, at the
    /// body's size, overlap vertically as `sameRow` does, and meet horizontally in one of the ways a
    /// split row does. The right piece can start where the left one ends, within one and a half
    /// font sizes, on an edge no other line starts on (as a column or table cell would); where that
    /// gap is wider than a font size a mathematical sign stands at the join (in the left piece's last
    /// two tokens or the right piece's first two, since PDFKit writes a radicand before its sign:
    /// `81 √ = 9 but 814√`, page 292) or one piece is mathematics alone (`25 √ .`, `36· 5`). A
    /// derivation's annotation beside its step has neither (page 189's `Convert 3.21 × 105 to
    /// standard notation` and `Positive exponent means…`). The radical at the join can make them
    /// overlap in step by up to four font sizes, each extending past the other by more than half a
    /// font size. Or a radicand extracted apart from its sign (`x8` inside `√ = x4, because we`,
    /// page 290) lies within the sign's piece: narrow, without words, and clear of that piece's
    /// left edge. A short line of the next row at the column's edge (`21.`, `example.`, `equal to`,
    /// pages 9, 180 and 120) lies within the tall rectangle of a full line above it and joins
    /// nothing. No preserved image may
    /// stand between the pieces.
    ///
    /// Each piece proposes the candidates it overlaps most vertically, and proposals join strongest
    /// first, only while every piece of the growing row still shares a band at least half a font
    /// size tall: the pieces of one row all hold its baseline, whereas a chain through a tall piece
    /// reaches the next row (page 198's `then combine like terms …` beneath `− 8xy + 21xy− 14y2 and`,
    /// page 212's `12x3 + 32x. …` beneath `− 3x + 8) = 8x4`). Every joined row must read as prose
    /// on its paragraph's measure (`isProseRow`), so table rows, exercise columns and a two-column
    /// page's rows stay apart, and a stray same-size digit beside a line end is left to the rules
    /// that already read it. Beyond that a row qualifies in one of two ways.
    ///
    /// It carries inline mathematics: a radical, operator or relation sign in one of its pieces
    /// (page 288's `squares" a number. For example, because 52` and `= 25 we say …`, split at the
    /// raised 2).
    ///
    /// Or its text simply runs on across the split (#148). PDFKit splits a prose row at a raised
    /// note marker (9/11 page 220's `that al-Qida was responsible” for the Cole.` and `178 In March
    /// 2001, the CIA’s brief-`) and, on a justified line, at a stretched word space (page 438's
    /// `…to conduct oversight of` and `the intel-`, 4.2 points apart). Each piece then opened a
    /// paragraph of its own, cutting the sentence and stranding the word break at the row's end.
    /// Such a row's pieces stand at most half a font size apart — narrower than any gutter, and
    /// narrower than the word spaces PDFKit itself keeps — and at each junction the left piece
    /// leaves its sentence open or the right piece opens with a raised note marker. A marker
    /// closes the line it was raised over with no space, as a detached marker does; every other
    /// junction is a word space. PDFKit reports a piece that opens with a raised marker at the
    /// marker's size, so a piece of that shape whose rectangle is the page's ordinary line at the
    /// body size is read as body type (`typeSize`).
    ///
    /// The joined line reads its pieces left to right by centre, keeps their styles, and occupies
    /// one line of its type: from the highest bottom edge among the pieces, as tall as the page's
    /// ordinary lines of that size, so the paragraph rules see the row's leading rather than the
    /// radical signs' overshoot.
    ///
    /// A joined row that opens with a mathematical minus before a number or a variable (page 321's
    /// radicand `− 1`, read ahead of `√ , and it is in the denominator…`) is not a list line, though
    /// `isList` reads `− ` as a bullet; its opening piece must not have been a list line on its own
    /// (#109). Such rows are returned in `mathMinusRows`, and the list rules pass over them. `isList`
    /// itself is unchanged: across the corpus a line opening with U+2212 is Wallace's alone, and the
    /// equation and derivation lines that open with one stay separate blocks.
    static func joiningRowPieces(_ lines: [TextLine], images: [CGRect], body: CGFloat) -> [TextLine] {
        joinedRows(lines, images: images, body: body).lines
    }

    static func joinedRows(_ lines: [TextLine], images: [CGRect], body: CGFloat)
        -> (lines: [TextLine], mathMinusRows: [TextLine]) {
        let ordinary = ordinaryLineHeight(body, in: lines)
        // A piece that opens with a raised note marker carries the marker's size, because PDFKit
        // measures the line from its first run (9/11 page 220's 7.175-point
        // `178 In March 2001, the CIA’s brief-`). Its type is the body it sets, which its
        // rectangle — an ordinary line of that body — still shows.
        func typeSize(_ line: TextLine) -> CGFloat {
            guard line.fontSize < body * 0.8, raisedNoteNumber(line.content) != nil, let ordinary,
                  abs(line.rect.height - ordinary) <= ordinary * 0.15 else { return line.fontSize }
            return body
        }
        let sized = lines.indices.filter { index in
            let line = lines[index]
            return line.structure == nil && !line.monospaced && abs(typeSize(line) - body) <= body * 0.15
                && !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard sized.count >= 2 else { return (lines, []) }
        func signed(_ text: Substring) -> Bool { text.rangeOfCharacter(from: rowMathSymbols) != nil }
        func word(_ token: Substring) -> Bool { token.filter(\.isLetter).count >= 2 }
        // An edge the page's own text shares: a column's measure, a table's column, a hanging
        // indent. A line PDFKit broke inside its measure ends on no such edge.
        func sharedEdge(_ value: CGFloat, _ edge: KeyPath<CGRect, CGFloat>,
                        besides: [TextLine], atLeast: Int = 2) -> Bool {
            var found = 0
            for other in lines where !besides.contains(other) && abs(other.rect[keyPath: edge] - value) <= 2 {
                found += 1
                if found >= atLeast { return true }
            }
            return false
        }
        // A justified line PDFKit split at its own stretched word space (#180). The IEEEtran
        // bibliography's references [1] and [7] break 1.6 and 1.3 ems wide — wider than any
        // junction the word-space reading admits — and a reference's fields all end in a period,
        // so neither the junction's width nor an open sentence can read them.
        //
        // What reads them is the space itself: PDFKit kept it at the end of the left piece
        // (`[1] M. S. Andersen, J. Dahl, and L. Vandenberghe. ` before `CVXOPT: A`), which a
        // piece it ended at a line break never carries. The geometry says the break stands inside
        // the measure: the left piece ends nowhere the page's own text ends and the right piece
        // begins nowhere it begins, while the row still reaches the right edge that every full
        // line of the paragraph reaches. A column's line ends on its column's measure and a cell
        // on its table's, so neither is one of these. Both pieces must also stand in the page's
        // ordinary line of their type, since a split line is one line of the paragraph: Wallace
        // page 189 sets `Positiveexponentmeansstandardnotation` beside `Convert 3.21 × 105 to
        // standard notation ` in a worked example's 21.8-point rows over an 11.98-point page, and
        // its right edge happens to fall on the body's measure.
        func stretchedWordSpace(_ left: TextLine, _ right: TextLine, size: CGFloat) -> Bool {
            let gap = right.rect.minX - left.rect.maxX
            guard left.trailingSpace, gap > 0, gap <= size * 2,
                  let ordinary = ordinaryLineHeight(size, in: lines),
                  [left, right].allSatisfy({ abs($0.rect.height - ordinary) <= ordinary * 0.15 }) else { return false }
            return !sharedEdge(left.rect.maxX, \.maxX, besides: [left, right])
                && !sharedEdge(right.rect.minX, \.minX, besides: [left, right])
                && sharedEdge(right.rect.maxX, \.maxX, besides: [left, right], atLeast: 3)
        }
        func candidate(_ a: TextLine, _ b: TextLine) -> Bool {
            guard sameRow(a.rect, b.rect),
                  abs(typeSize(a) - typeSize(b)) <= max(typeSize(a), typeSize(b)) * 0.1 else { return false }
            let (left, right) = a.rect.midX <= b.rect.midX ? (a, b) : (b, a)
            let size = max(typeSize(a), typeSize(b))
            let gap = right.rect.minX - left.rect.maxX
            if gap >= 0 {
                let stretched = stretchedWordSpace(left, right, size: size)
                guard gap <= size * 1.5 || stretched else { return false }
                // A column or table cell starts on an edge other lines share; a split row's piece
                // starts wherever its radical falls.
                let aligned = lines.filter { other in
                    other != left && other != right && !sameRow(other.rect, right.rect)
                        && abs(other.rect.minX - right.rect.minX) <= 2
                }
                guard aligned.count < 2 else { return false }
                if gap > size, !stretched {
                    let leftTokens = left.text.split(whereSeparator: \.isWhitespace)
                    let rightTokens = right.text.split(whereSeparator: \.isWhitespace)
                    let formulaOnly = [leftTokens, rightTokens].contains { !$0.contains(where: word) && $0.contains(where: signed) }
                    guard formulaOnly || leftTokens.suffix(2).contains(where: signed) || rightTokens.prefix(2).contains(where: signed)
                    else { return false }
                }
            } else if right.rect.minX - left.rect.minX > size * 0.5, right.rect.maxX - left.rect.maxX > size * 0.5 {
                guard -gap <= size * 4 else { return false }
            } else {
                // A radicand PDFKit extracts apart from its sign lies within the span of the piece
                // holding the sign: narrow, without words, clear of that piece's left edge, and
                // only by its own choice (`a` is the piece choosing), since a full line of the next
                // row also spans a short piece.
                guard a.rect.width < b.rect.width, a.rect.width <= size * 4,
                      !a.text.split(whereSeparator: \.isWhitespace).contains(where: word),
                      a.rect.minX >= b.rect.minX + size * 0.5, a.rect.maxX <= b.rect.maxX + 1 else { return false }
            }
            let start = min(left.rect.maxX, right.rect.minX), end = max(left.rect.maxX, right.rect.minX)
            let band = a.rect.union(b.rect)
            return !images.contains { image in
                image.minX < end && image.maxX > start && image.minY < band.maxY && image.maxY > band.minY
            }
        }
        func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat { min(a.maxY, b.maxY) - max(a.minY, b.minY) }
        var parent = Dictionary(uniqueKeysWithValues: sized.map { ($0, $0) })
        // Each row's shared band: the highest bottom and the lowest top among its pieces.
        var band = Dictionary(uniqueKeysWithValues: sized.map { ($0, (bottom: lines[$0].rect.minY, top: lines[$0].rect.maxY)) })
        func root(_ index: Int) -> Int {
            var index = index
            while let next = parent[index], next != index { index = next }
            return index
        }
        var proposals: [(piece: Int, other: Int, overlap: CGFloat)] = []
        for index in sized {
            let piece = lines[index]
            let neighbours = sized.filter { $0 != index && candidate(piece, lines[$0]) }
            guard let best = neighbours.map({ overlap(piece.rect, lines[$0].rect) }).max() else { continue }
            for other in neighbours where overlap(piece.rect, lines[other].rect) >= best - 0.01 {
                proposals.append((index, other, overlap(piece.rect, lines[other].rect)))
            }
        }
        // Strongest first; ties in page order, so the result does not depend on sorting stability.
        proposals.sort { ($0.overlap, -$0.piece, -$0.other) > ($1.overlap, -$1.piece, -$1.other) }
        for proposal in proposals {
            let a = root(proposal.piece), b = root(proposal.other)
            guard a != b, let first = band[a], let second = band[b] else { continue }
            let shared = (bottom: max(first.bottom, second.bottom), top: min(first.top, second.top))
            guard shared.top - shared.bottom >= lines[proposal.piece].fontSize * 0.5 else { continue }
            parent[b] = a
            band[a] = shared
        }
        let clusters = Dictionary(grouping: sized, by: root).values.filter { $0.count >= 2 }
        guard !clusters.isEmpty else { return (lines, []) }
        var replaced: [Int: TextLine] = [:]
        var removed = Set<Int>()
        var mathMinusRows: [TextLine] = []
        // The flush edge of each size, where the page justifies its type (#152).
        let measures = justifiedMeasures(lines)
        for cluster in clusters {
            let pieces = cluster.sorted { lines[$0].rect.midX < lines[$1].rect.midX }
            let math = pieces.contains { lines[$0].text.rangeOfCharacter(from: rowMathSymbols) != nil }
            // A junction a raised note marker made: the marker closes the line to its left with
            // no space, exactly as a marker PDFKit detached past the line's end does. A raised
            // term inside mathematics is not one; those rows meet at a space, as they always have.
            func closesWithMarker(_ right: Int) -> Bool { !math && raisedNoteNumber(lines[right].content) != nil }
            // Where this reading admits a row #95's did not — a row outside mathematics, or a
            // piece PDFKit measured at its raised marker's size — no piece of the page may stand
            // in one of its junctions (#148): NOAA page 145 sets `…0.7 W/m2`, `.` and the raised
            // `2 Since NCA4, the` as three pieces of one row, and joining the outer two would
            // carry the period past the end of the line. A row of mathematics that #95 already
            // read joins as it always has, since a radical's pieces routinely overlap the terms
            // beside them.
            let widened = !math || pieces.contains { typeSize(lines[$0]) != lines[$0].fontSize }
            let clear = zip(pieces, pieces.dropFirst()).allSatisfy { left, right in
                let (start, end) = (lines[left].rect.maxX, lines[right].rect.minX)
                return !lines.indices.contains { other in
                    !cluster.contains(other) && sameRow(lines[other].rect, lines[left].rect)
                        && lines[other].rect.maxX > start && lines[other].rect.minX < end
                }
            }
            // The row's text runs on across each junction: no junction is wider than the word
            // space a justified line's piece ends with, and the left piece leaves its sentence
            // open or the right piece opens with a raised note marker.
            // A junction PDFKit made inside a justified line's own measure runs on whatever the
            // line's punctuation reads like, since the break is the line's word space (#180).
            func runs(atSentenceSpace: Bool) -> Bool {
                zip(pieces, pieces.dropFirst()).allSatisfy { left, right in
                    let size = typeSize(lines[right])
                    if stretchedWordSpace(lines[left], lines[right], size: size) { return true }
                    let gap = lines[right].rect.minX - lines[left].rect.maxX
                    if gap <= size * 0.5, !endsSentence(lines[left].content) || closesWithMarker(right) { return true }
                    // Two word spaces after a sentence: half an em in Times, a little over in
                    // wider faces.
                    return atSentenceSpace && lines[left].trailingSpace && endsSentence(lines[left].content)
                        && gap > 0 && gap <= size * 0.75
                }
            }
            let runsOn = runs(atSentenceSpace: false)
            // A sentence can end at a junction too, where the left piece still carries the word
            // space PDFKit measured after it (#152): a piece PDFKit ended at a line break carries
            // none. The US Courts form sets two spaces after a sentence, and PDFKit cut its
            // Statement of Claim's first line there (`…statement of the claim. ` and `Do not make
            // legal arguments. …`), 5.54 points apart at 11 points. The form sets its prose ragged,
            // so the row cannot share a justified measure; it is instead the first line of the
            // paragraph beneath it: that paragraph's next line stands under it on the same left
            // edge at ordinary leading, and the row reaches nine tenths of that line's width. Only
            // where the page sets its type ragged: in a justified column a line reaches the
            // measure, and a row that stops short of it is no line of the paragraph (#180).
            let runsOnAtSentenceSpace = !math && !runsOn && runs(atSentenceSpace: true)
            func opensParagraphBeneath() -> Bool {
                guard measures[Int(typeSize(lines[pieces[0]]).rounded())] == nil else { return false }
                let row = union(pieces.map { lines[$0].rect })
                guard let beneath = lines.indices.filter({ index in
                    let other = lines[index]
                    let gap = row.minY - other.rect.maxY
                    return !cluster.contains(index) && abs(other.rect.minX - row.minX) <= 2
                        && abs(other.fontSize - body) <= body * 0.15 && gap >= -body * 0.4 && gap < body * 0.9
                }).map({ lines[$0] }).max(by: { $0.rect.maxY < $1.rect.maxY }) else { return false }
                return isWordy(beneath.text) && row.width >= beneath.rect.width * 0.9
            }
            // Outside mathematics the row must also be a full line of its justified paragraph,
            // sharing both edges with the lines around it. A short row that merely sits on a
            // paragraph's edge is something else set beside it: the FAA's heading `ATC
            // Instructions—` and `“Hold Short”`, two pieces of one row over the body text.
            guard math || runsOn || runsOnAtSentenceSpace, !widened || clear,
                  runsOnAtSentenceSpace ? opensParagraphBeneath()
                    : isProseRow(pieces: pieces.map { lines[$0] }, in: lines, body: body, fillingItsMeasure: !math)
            else { continue }
            var content = InlineText()
            for (position, index) in pieces.enumerated() {
                if position > 0, !closesWithMarker(index) { content.append(InlineText(" ")) }
                content.append(lines[index].content)
            }
            // The joined row must not turn into a list line that its opening piece was not, unless
            // what reads as a marker is a minus sign before a number or variable: page 321's
            // radicand `− 1`, read ahead of `√ , and it is in the denominator…` (#109).
            var opensWithMathMinus = false
            if let opening = pieces.min(by: { lines[$0].rect.minX < lines[$1].rect.minX }),
               isList(content.text), !isList(lines[opening].text) {
                guard opensWithMinusSign(content.text) else { continue }
                opensWithMathMinus = true
            }
            let first = lines[pieces[0]], last = lines[pieces[pieces.count - 1]]
            let bounds = union(pieces.map { lines[$0].rect })
            let bottom = pieces.map { lines[$0].rect.minY }.max() ?? bounds.minY
            let size = typeSize(first)
            let height = min(bounds.maxY - bottom, ordinaryLineHeight(size, in: lines) ?? first.rect.height)
            var joined = TextLine(content: content, rect: CGRect(x: bounds.minX, y: bottom, width: bounds.width, height: height),
                                  fontSize: size, wraps: last.wraps)
            if pieces.contains(where: { lines[$0].readingRect != nil }) {
                joined.readingRect = union(pieces.map { lines[$0].readingRect ?? lines[$0].rect })
            }
            joined.listTag = sharedListTag(pieces.map { lines[$0] }.sorted { $0.rect.minX < $1.rect.minX })
            // The row keeps the reading position of its earliest piece in page order.
            let anchor = cluster.min()!
            replaced[anchor] = joined
            removed.formUnion(cluster.filter { $0 != anchor })
            if opensWithMathMinus { mathMinusRows.append(joined) }
        }
        return (lines.indices.compactMap { index in
            removed.contains(index) ? nil : replaced[index] ?? lines[index]
        }, mathMinusRows)
    }

    /// A line that opens with a mathematical minus (U+2212) before a number or a single-letter
    /// variable (`− 1`, `− 3x`, `− x +6y`), rather than a bullet before a word (`− Your fair dealing`,
    /// the license list on Wallace page 2).
    static func opensWithMinusSign(_ text: String) -> Bool {
        text.range(of: "^−\\s+(?:[0-9]|[A-Za-z](?![A-Za-z]))", options: .regularExpression) != nil
    }

    /// The page's ordinary line height at a size: the median height of its lines of that size.
    static func ordinaryLineHeight(_ size: CGFloat, in lines: [TextLine]) -> CGFloat? {
        let heights = lines.filter { abs($0.fontSize - size) <= size * 0.1 }.map(\.rect.height).sorted()
        return heights.isEmpty ? nil : heights[heights.count / 2]
    }

    /// The page's ordinary gap between wrapped lines at a size: the lower quartile, over lines of
    /// that size and ordinary height, of the gap to the nearest such line directly beneath on the
    /// same left edge (within half a body) inside the prose window (`-0.4…0.9` body). Paragraph
    /// spacing falls inside that window too, and on Wallace page 64 it is nearly as common as the
    /// wrapped lines' own gap (9.7 against 2.4 points), so a median can land on it; wrapped lines
    /// set the smallest common gap. Nil when no line has one.
    static func ordinaryLineGap(_ size: CGFloat, in lines: [TextLine], body: CGFloat) -> CGFloat? {
        guard let height = ordinaryLineHeight(size, in: lines) else { return nil }
        let ordinary = lines.filter { abs($0.fontSize - size) <= size * 0.1 && $0.rect.height <= height + body * 0.25 }
        let gaps = ordinary.compactMap { upper -> CGFloat? in
            ordinary.compactMap { lower -> CGFloat? in
                let gap = upper.rect.minY - lower.rect.maxY
                guard lower != upper, abs(upper.rect.minX - lower.rect.minX) <= body * 0.5,
                      gap >= -body * 0.4, gap < body * 0.9, lower.rect.midY < upper.rect.midY else { return nil }
                return gap
            }.min()
        }.sorted()
        return gaps.isEmpty ? nil : gaps[gaps.count / 4]
    }

    private struct Region {
        var seed: CGRect
        var bounds: CGRect
        /// The ink a crop must keep: a thin rule's one-point stroke, otherwise the whole seed.
        var core: CGRect {
            isThinRule(seed) ? CGRect(x: seed.minX, y: seed.midY - 0.5, width: seed.width, height: 1) : seed
        }
    }

    /// A rule drawn across the page's whole measure is a boundary, not art: *Agricultural
    /// Research* rules its running foot off under every column, and furniture detection reads
    /// that rule to admit the foot (`FurnitureDetector.ruledOff`, #159). A page that keeps a
    /// source-page reference instead of its crops (#164) drops its graphics, so such a rule is
    /// kept as a separator rather than lost with them.
    static func isPageWideRule(_ rect: CGRect, bounds: CGRect) -> Bool {
        isThinRule(rect) && bounds.width > 0 && rect.width >= bounds.width * 0.6
    }

    /// `clusters` for regions: merged bounds carry the union of their seeds. Two regions that do
    /// not overlap stay apart when the box around them would take a line of the page's block text
    /// that neither of them takes (#158): the magazine's signature box and the rule under its
    /// columns come within a point and a half of each other across the foot of three columns.
    private static func merged(_ regions: [Region], text: [TextLine]) -> [Region] {
        var result: [Region] = []
        for region in regions {
            var merged = region
            var previousCount = -1
            while previousCount != result.count {
                previousCount = result.count
                result.removeAll { existing in
                    if existing.bounds.insetBy(dx: -3, dy: -3).intersects(merged.bounds) {
                        let union = merged.bounds.union(existing.bounds)
                        if !existing.bounds.intersects(merged.bounds),
                           text.contains(where: { line in
                               line.rect.intersects(union) && !line.rect.intersects(merged.bounds)
                                   && !line.rect.intersects(existing.bounds)
                           }) { return false }
                        merged.seed = merged.seed.union(existing.seed)
                        merged.bounds = union
                        return true
                    }
                    return false
                }
            }
            result.append(merged)
        }
        return result
    }

    /// A piece of a display row whose rectangle all but touches a crop that already holds the
    /// rest of that row. PDFKit breaks such a row at a raised exponent or a fraction, and the
    /// crop's edge falls in the break: Wallace page 340's leading `x²` stands 0.01 pt clear of
    /// the crop holding the rest of `x² − 3x + 9/4 = 8/4 + 9/4`, page 343's `x² +` 0.53 pt, and
    /// the answer-key entries `22)− 2,` and `29)−` 0.63 and 0.58 pt from their fraction crops
    /// (#46, #48). The gap is extraction padding, not typography: across the gated corpus every
    /// such piece stands at most 0.65 pt clear, while the nearest piece separated by a real
    /// space is 0.87 pt away, so three quarters of a point separates them.
    ///
    /// A piece carrying a word is an explanation set beside the derivation, not part of it
    /// (`Separate constant term from varaibles`, 11.6 pt clear on Wallace page 339), and a bare
    /// list marker is a separable entry number whose item happens to start at the crop's edge
    /// (NOAA's reference numbers `396.`, `402.`). Neither joins the crop.
    static func adjoinsRow(_ line: TextLine, bounds: CGRect, admitted: [CGRect]) -> Bool {
        guard !line.monospaced, line.text.count <= 40, !isMarkerPiece(line.text),
              line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) == nil else { return false }
        let gap = line.rect.midX < bounds.midX ? bounds.minX - line.rect.maxX : line.rect.minX - bounds.maxX
        guard gap >= 0, gap <= 0.75 else { return false }
        return admitted.contains { sameRow($0, line.rect) }
    }

    /// A drawing's own label, set a word space from its ink (#179). Wallace's trigonometry
    /// answers draw a right triangle for each exercise and letter its vertices: page 427 sets
    /// `C` 1.6–4.0 pt over each triangle and `B` 2.8–5.2 pt to its right, page 424's `A`
    /// 1.0–6.4 pt beside it. That is typography, not the extraction padding `adjoinsRow`
    /// measures, so those labels stood outside the crop and reflowed as one-character
    /// paragraphs around the image, while the labels that happened to touch the crop joined it.
    ///
    /// A line is such a label when it is one or two letters or digits — an exercise number
    /// carries its `)` and a word its letters — standing at most one body size clear of a crop
    /// it overlaps in the other direction, where the crop is a drawing (a painted region at
    /// least one body wide and one body tall reaches into it) that holds nothing but labels
    /// itself: at most eight lines, none over eight characters and none carrying a word.
    ///
    /// Each guard answers a measured neighbour. A fraction bar is painted a body wide and four
    /// points tall, so Wallace's worked examples are no drawings and their terms' digits keep
    /// their text (page 13's `25` and `55`, whose crop went on to swallow two explanations); the
    /// `or` between the FAA's page-265 fractions and the folio 6.2 pt under Wallace page 33's
    /// derivation are refused for the same reason, and so are the USDA magazine's folios beside
    /// its running-foot rule. The graph pages set their exercise numbers against the drawing
    /// itself — page 483's `5)` stands 0.54 pt from its graph and page 447's `3)` 2.3 pt — and
    /// the closing parenthesis is what tells them from a vertex letter. Across the gated corpus
    /// every line this admits is a vertex letter or a side length on Wallace pages 422–436, at
    /// 0.03 to 0.93 of a body from its drawing.
    static func isDiagramLabel(_ line: TextLine, bounds: CGRect, held: [TextLine], page: PageContent,
                               body: CGFloat) -> Bool {
        guard !line.monospaced,
              line.text.trimmingCharacters(in: .whitespaces)
                  .range(of: "^[A-Za-z0-9]{1,2}$", options: .regularExpression) != nil else { return false }
        let dx = max(bounds.minX - line.rect.maxX, line.rect.minX - bounds.maxX, 0)
        let dy = max(bounds.minY - line.rect.maxY, line.rect.minY - bounds.maxY, 0)
        // Beside the drawing or over it, never diagonally off a corner: an exercise number set
        // above and to the left of its triangle overlaps neither span (page 426's `30)`).
        guard (dx == 0) != (dy == 0), max(dx, dy) <= body else { return false }
        guard held.count <= 8, held.allSatisfy({ other in
            other.text.trimmingCharacters(in: .whitespaces).count <= 8
                && other.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) == nil
        }) else { return false }
        return page.graphics.contains { bounds.intersects($0) && $0.width >= body && $0.height >= body }
    }

    /// Whole-line expansion admits the lines a seed captures and the other pieces of their
    /// rows. Tightly leaded line rectangles overlap, so admitting every line that touches an
    /// admitted line would absorb a whole paragraph or column (#36). The crop is then trimmed
    /// away from lines it merely touches, because layout removes every intersecting line from
    /// prose; a line whose rectangle genuinely overlaps admitted text is admitted instead.
    /// A crop never keeps half a row: a piece its edge left just outside joins it (`adjoinsRow`).
    /// A drawing takes its own vertex and side labels with it (`isDiagramLabel`, #179).
    /// Returns nil for a thin rule that lies inside text it does not strike through.
    private static func expanded(_ region: Region, page: PageContent, body: CGFloat,
                                 text: [TextLine] = []) -> CGRect? {
        var admitted: [CGRect] = []
        while true {
            var bounds = admitted.reduce(region.seed) { $0.union($1.insetBy(dx: -2, dy: -2)) }
                .intersection(page.bounds)
            var changed = false
            for line in page.lines where !admitted.contains(line.rect) && bounds.intersects(line.rect) {
                guard captures(region.seed, line)
                    || admitted.contains(where: { sameRow($0, line.rect) }) else { continue }
                admitted.append(line.rect)
                changed = true
            }
            if changed { continue }
            for line in page.lines where !admitted.contains(line.rect) && !bounds.intersects(line.rect)
                && adjoinsRow(line, bounds: bounds, admitted: admitted) {
                admitted.append(line.rect)
                changed = true
            }
            if changed { continue }
            let held = page.lines.filter { admitted.contains($0.rect) || bounds.intersects($0.rect) }
            for line in page.lines where !admitted.contains(line.rect) && !bounds.intersects(line.rect)
                && isDiagramLabel(line, bounds: bounds, held: held, page: page, body: body) {
                admitted.append(line.rect)
                changed = true
            }
            if changed { continue }
            let kept = admitted.reduce(region.core) { $0.union($1) }
            for line in page.lines where !admitted.contains(line.rect) && bounds.intersects(line.rect) {
                let rect = line.rect
                let cuts = [
                    CGRect(x: bounds.minX, y: rect.maxY, width: bounds.width, height: bounds.maxY - rect.maxY),
                    CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: rect.minY - bounds.minY),
                    CGRect(x: rect.maxX, y: bounds.minY, width: bounds.maxX - rect.maxX, height: bounds.height),
                    CGRect(x: bounds.minX, y: bounds.minY, width: rect.minX - bounds.minX, height: bounds.height),
                // A cut rebuilt from origin and size can fall short of an edge it shares with
                // the kept ink by rounding (FAA page 195: a figure box ending exactly at the
                // crop's top); a hundredth of a point is below any drawn distinction.
                ].filter { $0.width > 0 && $0.height > 0 && $0.insetBy(dx: -0.01, dy: -0.01).contains(kept) }
                if let cut = cuts.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                    bounds = cut
                } else if admitted.isEmpty && isThinRule(region.seed) {
                    return nil
                } else if text.contains(where: { $0.rect == rect }),
                          let cut = textCut(bounds, beyond: rect, admitted: admitted, core: region.core) {
                    // A line of the page's running text is not this figure's label: rather than
                    // swallow the column it opens, the crop gives up the part of its art on that
                    // line's side, as long as it keeps most of it (#158).
                    bounds = cut
                } else {
                    admitted.append(rect)
                    changed = true
                    break
                }
            }
            if changed { continue }
            return bounds
        }
    }

    /// The largest part of `bounds` beyond `rect` that still holds every admitted line and all of
    /// `core` but its outermost point, or nil when no side does. A crop whose art ends a fraction
    /// of a point inside a column's first line (the magazine's index rules) gives up that point
    /// rather than the column; a crop that would have to cut into its figure keeps the line.
    private static func textCut(_ bounds: CGRect, beyond rect: CGRect, admitted: [CGRect], core: CGRect) -> CGRect? {
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        let ink = core.insetBy(dx: min(1, core.width / 4), dy: min(1, core.height / 4))
        guard !ink.isNull else { return nil }
        return [
            CGRect(x: bounds.minX, y: rect.maxY, width: bounds.width, height: bounds.maxY - rect.maxY),
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: rect.minY - bounds.minY),
            CGRect(x: rect.maxX, y: bounds.minY, width: bounds.maxX - rect.maxX, height: bounds.height),
            CGRect(x: bounds.minX, y: bounds.minY, width: rect.minX - bounds.minX, height: bounds.height),
        ].filter { cut in
            cut.width > 0 && cut.height > 0
                && admitted.allSatisfy { cut.insetBy(dx: -0.01, dy: -0.01).contains($0) }
                && cut.insetBy(dx: -0.01, dy: -0.01).contains(ink)
        }.max { area($0) < area($1) }
    }

    /// An algorithm float set between rules (LaTeX `algorithm`/`algorithmic`): a caption line
    /// `Algorithm N …` directly beneath a thin rule, a second rule of the same extent directly
    /// beneath the caption, and a closing rule of that extent further down. The listing between
    /// the second and closing rules is one region, because its numbered lines, keywords and
    /// inline mathematics cannot reflow as prose or code without losing lines to separate crops
    /// (#43). The caption stays text; the top rule is the caption's decoration.
    static func algorithmFloats(in page: PageContent) -> (regions: [CGRect], decorations: [CGRect]) {
        let rules = page.graphics.filter { isThinRule($0) && $0.width >= 100 }
        guard !rules.isEmpty else { return ([], []) }
        let body = max(4, bodySize(page.lines))
        func sameExtent(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) <= 3 && abs(a.maxX - b.maxX) <= 3 }
        var regions: [CGRect] = [], decorations: [CGRect] = []
        for caption in page.lines where !caption.monospaced
            && caption.text.range(of: #"^Algorithm\s+\d+\b"#, options: .regularExpression) != nil {
            let box = caption.rect
            guard let top = rules.first(where: { rule in
                      rule.minX <= box.minX + 3 && rule.maxX >= box.maxX - 3
                          && rule.minY >= box.maxY - 1 && rule.minY <= box.maxY + body
                  }),
                  let upper = rules.first(where: { rule in
                      sameExtent(rule, top) && rule.maxY <= box.minY + 1 && rule.maxY >= box.minY - body
                  }),
                  let closing = rules.filter({ sameExtent($0, top) && $0.maxY < upper.minY })
                      .max(by: { $0.maxY < $1.maxY }) else { continue }
            // The rules' ink is at their midlines (GraphicsReader pads them by two points).
            regions.append(CGRect(x: top.minX, y: closing.midY - 1, width: top.width,
                                  height: upper.midY + 1 - (closing.midY - 1)))
            decorations.append(top)
        }
        return (regions, decorations)
    }

    /// Text rotated a quarter turn extracts as a line far taller than wide. One running along
    /// at least a quarter of the outer margin of a page whose other text runs horizontally is a
    /// stamp (arXiv's identifier), not content or a heading (#43). A short rotated line beside a
    /// photograph is its credit and keeps its paragraph; on a rotated page every line is tall,
    /// so nothing is a stamp.
    static func rotatedMarginLines(_ page: PageContent) -> [TextLine] {
        let horizontal = page.lines.filter { $0.rect.width >= $0.rect.height * 2 }.reduce(0) { $0 + $1.text.count }
        let vertical = page.lines.filter { $0.rect.height >= $0.rect.width * 2 }.reduce(0) { $0 + $1.text.count }
        guard vertical > 0, horizontal > vertical * 3 else { return [] }
        let margin = page.bounds.width * 0.12
        return page.lines.filter { line in
            line.text.filter { !$0.isWhitespace }.count >= 3 && line.rect.height >= line.rect.width * 3
                && line.rect.height >= page.bounds.height * 0.25
                && (line.rect.maxX <= page.bounds.minX + margin || line.rect.minX >= page.bounds.maxX - margin)
        }
    }

    /// A section label set only modestly larger than the body (acmart's 10.9-point bold
    /// small-caps `ABSTRACT` or `1 INTRODUCTION` over 9-point prose, the 9/11 report's 12-point
    /// `1.1 INSIDE THE FOUR FLIGHTS` over 10-point prose) sits below the 25% heading threshold
    /// and would otherwise open its paragraph (#43). Size alone is not evidence (an inherited
    /// OCR layer's prose can run 20% over a small reference body), so the line must also read
    /// as a label: it starts with a capital or a digit, does not end in sentence punctuation,
    /// has clear space above it or continues a label of the same size, and is either set in
    /// capitals or shorter than the column's prose lines. Recognized and synthetic pages have
    /// no typographic sizes to trust.
    ///
    /// A title can run nearly the column's width (FAA page 43's `Crew Resource Management (CRM)
    /// and`, 95% of its prose). Its width is then no evidence, but the book's typography is: a
    /// line set in a `LabelStyle` that the book's narrower section labels establish (`styles`)
    /// is a label when it passes every other test and still fits within the column (#73).
    ///
    /// A book's smallest sub-headings can be set at body size or barely above it (FAA's 10-point
    /// Helvetica-Bold `Radius of Turn` and 11-point Times-BoldItalic `Fixed-Pitch Propeller` over
    /// 10-point Times). Size is then no evidence and only the book's repeated typography is: such a
    /// line is a label when it is set entirely in bold in a `LabelStyle` of `styles`, fits the same
    /// narrow width, has clear space above it, and a paragraph opens directly beneath it on its
    /// left edge in ordinary body text (#76). `recordingSubheadings` admits every such line
    /// without a style, for `labelEvidence(on:)` to record.
    ///
    /// The book's lowest titles can be set in its body's italic (FAA's 10-point Times-Italic
    /// `Southerly Turning Errors`, `Drugs`). Where no tag sets them apart, such a line is a label
    /// on the same evidence, with the italic in place of bold: set wholly in italic in a recurring
    /// italic `LabelStyle`, in title case, not a figure or table caption, and over ordinary
    /// body text that is not itself italic, either on its left edge or as the list it heads
    /// (`opensListBeneath`). Italic emphasis inside prose has no clear space above it or no
    /// paragraph opening beneath it (#97).
    static func sectionLabels(in lines: [TextLine], body: CGFloat, headingThreshold: CGFloat,
                              page: PageContent, styles: Set<LabelStyle> = [],
                              recordingSubheadings: Bool = false) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var labels: [TextLine] = []
        let entryEdges = hangingEntryEdges(lines, body: body, titles: styles)
        // The leading the body wraps at, for a title set under the body's own size.
        let bodyGap = ordinaryLineGap(body, in: lines, body: body)
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            let subheading = line.fontSize < body * 1.15
            // A book can set its sub-headings *below* the body's size: *Agricultural Research*
            // heads sections of its ten-and-a-half point columns with nine-point bold lines
            // (#159). Only bold qualifies there — the smaller type a magazine sets beside its
            // body is otherwise a caption or a photo credit — and the rest of the sub-heading
            // evidence, including the recurring style, still decides it.
            let smaller = line.fontSize < body * 0.95
            // A list item (an answer-key entry, a contents line) keeps its list representation; a
            // numbered title set above the body in capitals or bold is a label (#154).
            guard !line.monospaced, line.fontSize >= body * (subheading ? 0.8 : 1.15), line.fontSize < headingThreshold,
                  line.text.count >= 2, line.text.count < 200,
                  !isList(line.text) || !subheading && isNumberedTitle(line, body: body)
                    && !lines.contains(where: { other in
                        other != line && ListMarker(other.text).map { ListMarker(line.text)?.isSibling(of: $0) == true } == true
                    }),
                  // Past an opening bracket or quote: `(EMAS)` finishes FAA page 370's title.
                  let first = line.text.first(where: { !"([\u{201C}\"'".contains($0) }),
                  first.isUppercase || first.isNumber,
                  let last = line.text.last, !".,;:".contains(last),
                  // Words, or a dotted section number whose title PDFKit split off at the gap.
                  line.text.contains(where: \.isLetter)
                    || line.text.range(of: #"^\d+(?:\.\d+)+$"#, options: .regularExpression) != nil else { continue }
            let column = lines.filter { other in
                other != line && other.rect.minX < line.rect.maxX && other.rect.maxX > line.rect.minX
            }
            let above = column.filter { $0.rect.minY >= line.rect.maxY - body * 0.25 }
                .min { $0.rect.minY < $1.rect.minY }
            // A title set smaller than the body cannot be measured against the body's own size:
            // the magazine leaves 5.7 points over its nine-point subheads in columns whose lines
            // stand 1.3 points apart, which is clear space in that column although it is under
            // four fifths of a ten-and-a-half point body. Such a title is set apart when the space
            // above exceeds the column's own leading by half a body; every other candidate keeps
            // the absolute distance (#159).
            let clearance = smaller ? min(body * 0.8, (bodyGap ?? 0) + body * 0.5) : body * 0.8
            if let above, above.rect.minY - line.rect.maxY < clearance,
               subheading || !(labels.contains(above) && abs(above.fontSize - line.fontSize) <= line.fontSize * 0.05) { continue }
            let letters = line.text.filter(\.isLetter)
            let capitals = letters.allSatisfy(\.isUppercase)
            let prose = column.filter { $0.fontSize < body * 1.1 }.map(\.rect.width).max() ?? 0
            if subheading {
                let style = LabelStyle(line, body: body)
                func nearestBelow(_ title: TextLine) -> TextLine? {
                    lines.filter { other in
                        other != title && other.rect.minX < title.rect.maxX && other.rect.maxX > title.rect.minX
                            && other.rect.maxY <= title.rect.minY + body * 0.4
                    }.max(by: { $0.rect.maxY < $1.rect.maxY })
                }
                // The line opening the text a title heads past a picture set directly beneath it
                // (#186): *Agricultural Research*'s `Fighting Filth Flies` heads a sidebar over the
                // sidebar's photograph and its caption, 142 points above the sidebar's first line.
                // The picture (no thin rule) stands within four fifths of a body of the title's foot
                // and spans the title's left edge; everything in the title's measure between the
                // picture and the opening is set smaller than the body (its caption and credit); and
                // the opening stands within four bodies of the last of them, since a caption the
                // picture's crop takes is no line here (page 9's two caption lines and 31 points).
                // A caption's own label is no title of the text beneath.
                func pastFigure(_ title: TextLine) -> TextLine? {
                    guard !isCaption(title.text), let figure = page.graphics.filter({ graphic in
                              !isThinRule(graphic) && graphic.minX <= title.rect.minX + body * 0.5
                                  && graphic.maxX >= title.rect.maxX && graphic.maxY <= title.rect.minY + body * 0.4
                                  && title.rect.minY - graphic.maxY < body * 0.8
                          }).max(by: { $0.maxY < $1.maxY }) else { return nil }
                    let beneath = lines.filter { other in
                        other != title && other.rect.minX < title.rect.maxX && other.rect.maxX > title.rect.minX
                            && other.rect.maxY <= figure.minY + body * 0.4
                    }.sorted { $0.rect.maxY > $1.rect.maxY }
                    guard let opening = beneath.firstIndex(where: { $0.fontSize >= body * 0.9 }) else { return nil }
                    let foot = beneath[..<opening].map(\.rect.minY).min() ?? figure.minY
                    return foot - beneath[opening].rect.maxY < body * 4 ? beneath[opening] : nil
                }
                // Whether `title`'s paragraph opens directly beneath it (#76, #97), or past the picture
                // set beneath it (#186).
                func opens(beneath title: TextLine) -> Bool {
                    if let direct = nearestBelow(title), title.rect.minY - direct.rect.maxY < body * 0.8 {
                        if opens(title, with: direct) { return true }
                    }
                    return pastFigure(title).map { opens(title, with: $0) } ?? false
                }
                func opens(_ title: TextLine, with below: TextLine) -> Bool {
                    guard abs(below.fontSize - body) <= body * 0.1, !LabelStyle(below, body: body).bold else { return false }
                    // The paragraph can open on the column's own first-line indent instead of on
                    // the title's edge (the magazine indents ten points at a ten-and-a-half point
                    // body, #159). The page's indent pattern is the evidence, as it is for the
                    // paragraph break itself; a wider step is another block, not this title's text.
                    let indent = below.rect.minX - line.rect.minX
                    let onIndent = indent >= body * 0.5 && indent < body * 1.5
                        && firstLineIndentRun(in: lines, step: indent, size: below.fontSize)
                    // A title set under the body's size has no size evidence at all, so the
                    // opening beneath it must be a paragraph's own: the page's first-line indent.
                    // Small bold type standing flush over prose is a caption's label or a note's,
                    // and stays where it is (FAA page 165's control; #159).
                    let paragraph = (smaller ? onIndent : abs(indent) <= body * 0.5 || onIndent)
                        && below.rect.width > title.rect.width
                    // A bold title can head entries narrower than itself where the page's entries wrap
                    // into a hanging indent on the title's own edge (9/11 page 458's `Intelligence
                    // Oversight and the Joint Inquiry` over `Senator Bob Graham (D-Fla.)`; #134).
                    let entries = !smaller && abs(below.rect.minX - line.rect.minX) <= body * 0.5
                        && !isList(below.text) && hangingEntryEdge(of: below, in: entryEdges) != nil
                    // An italic title opens ordinary body text or a list, never more italic type.
                    return style.bold ? paragraph || entries
                        : !LabelStyle(below, body: body).italic
                            && (paragraph && !isList(below.text) || opensListBeneath(below, title: line, body: body))
                }
                // A title over hanging entries can wrap from a first line wider than any entry:
                // 9/11 page 461's `Preventive Detention: Use of Immigration Laws and Enemy Combatant
                // Des-` runs the page's full measure over `ignations to Combat Terrorism` (#161). Only
                // the two-line path below admits it, in the book's style over its entries.
                let wideTitle = !smaller && style.bold && styles.contains(style)
                    && hangingEntryEdge(of: line, in: entryEdges) != nil
                guard style.bold || !smaller && style.italic && !isCaption(line.text),
                      recordingSubheadings || styles.contains(style),
                      prose > 0, line.rect.width <= prose || wideTitle else { continue }
                if line.rect.width <= prose * 0.9, !style.italic || isTitleCase(line.text), opens(beneath: line) {
                    labels.append(line)
                    continue
                }
                // A sub-heading set over two lines in the book's recurring style: the second line
                // stacks under the first on its left edge at heading leading, the pair reads as
                // one title, and the paragraph opens beneath the second (FAA page 21's `The
                // Professional Air Traffic Controllers` / `Organization (PATCO) Strike`, page 404's
                // `Use of Chart Supplement U.S. (formerly Airport/` / `Facility Directory)`; #102).
                // The first line may run the column's measure, as a wrapping title does. Only a
                // style the book already repeats qualifies; pairs are no evidence of their own.
                // Where the page's entries wrap into a hanging indent on the title's edge, a title
                // wraps into it too (9/11 page 458's `Law Enforcement, Domestic Intelligence, and` /
                // `Homeland Security`, one em in; #134).
                guard styles.contains(style), let second = nearestBelow(line), LabelStyle(second, body: body) == style,
                      abs(second.fontSize - line.fontSize) <= line.fontSize * 0.1 else { continue }
                let hanging = hangingEntryEdge(of: line, in: entryEdges) != nil
                    && stacksUnderHeading(second, after: line, hangingIndent: true)
                guard hanging || abs(second.rect.minX - line.rect.minX) <= body * 0.5 && stacksUnderHeading(second, after: line),
                      second.rect.width <= prose * 0.9, !opensHeading(second.text),
                      !isList(second.text), !isContentsEntry(line.text), !isContentsEntry(second.text),
                      let end = second.text.last, !".,;:".contains(end) else { continue }
                let text = line.text + " " + second.text
                guard !style.italic || isTitleCase(text) && !isCaption(text), opens(beneath: second) else { continue }
                labels += [line, second]
                continue
            }
            if capitals || line.rect.width <= prose * 0.9 || prose == 0
                || line.rect.width <= prose && styles.contains(LabelStyle(line, body: body)) { labels.append(line) }
        }
        // Three or more labels ending in folios are a table of contents, not section labels.
        let folio = #"\s(?:\d{1,4}|[ivxlc]+(?:[–-][ivxlc]+)?)$"#
        let entries = labels.filter { $0.text.range(of: folio, options: .regularExpression) != nil }
        return entries.count >= 3 ? labels.filter { !entries.contains($0) } : labels
    }

    /// The section labels of an outline and their depth (#152): 0 for a Roman numeral, 1 for a
    /// capital letter, 2 for a number. The US Courts form numbers its sections `I.`–`V.`, their
    /// parts `A.` and `B.`, and theirs `1.`–`3.`, each tier's markers on its own tab stop half an
    /// inch right of the tier above, all at the body's size; only the Roman and lettered tiers are
    /// bold. The labels read as bold paragraphs, or as list lines (`<pre>`) where their marker is
    /// a single letter or a number, since nothing about their size set them apart.
    ///
    /// The evidence is the outline itself, on the page. A label is a line at the body's size that
    /// opens with its marker and a period, then a title: at most ten words in title case, opening
    /// with a capital and ending without punctuation, so a numbered sentence is never one. The page
    /// must set labels of at least two tiers, nested — every marker of an outer tier on an edge at
    /// least a body size left of every marker of an inner one — and at least one label must be set
    /// wholly in bold, as an outline heads its sections. A numbered list is one tier, and a list
    /// under a lettered one nests in the other direction.
    ///
    /// A single `I`, `V`, `X`, `L` or `C` reads as Roman where a Roman label of more letters shares
    /// its edge or a lettered label stands inside it; otherwise it is a letter. A lowercase tier
    /// (`a.`, `b.`) enumerates items within its section and stays a list line.
    static func outlineSectionLabels(in lines: [TextLine], body: CGFloat) -> [(line: TextLine, depth: Int)] {
        struct Candidate { var line: TextLine; var marker: Substring; var depth: Int? }
        var candidates: [Candidate] = []
        for line in lines where !line.monospaced && line.readingDirection == nil && line.structure == nil
            && abs(line.fontSize - body) <= body * 0.1 && line.text.count < 120 {
            guard let match = line.text.range(of: #"^(?:[IVXLC]{1,6}|[A-Z]|[0-9]{1,2})\.\s+"#, options: .regularExpression)
            else { continue }
            let marker = line.text[match].prefix { $0 != "." }
            let title = line.text[match.upperBound...].trimmingCharacters(in: .whitespaces)
            guard let first = title.first, first.isUppercase, let last = title.last, !".,;:".contains(last),
                  title.contains(where: \.isLetter), isTitleCase(title) else { continue }
            let depth: Int?
            if marker.allSatisfy(\.isNumber) { depth = 2 }
            else if marker.count > 1 { depth = FurnitureDetector.folioValue(marker.lowercased()) == nil ? nil : 0 }
            else { depth = "IVXLC".contains(marker) ? nil : 1 }
            // A multi-letter marker that is no Roman numeral (`VV.`) is no label.
            if depth == nil, marker.count > 1 { continue }
            candidates.append(Candidate(line: line, marker: marker, depth: depth))
        }
        // Resolve single Roman letters against the page's other labels.
        for index in candidates.indices where candidates[index].depth == nil {
            let edge = candidates[index].line.rect.minX
            let roman = candidates.contains { $0.depth == 0 && abs($0.line.rect.minX - edge) <= 2 }
                || candidates.contains { $0.depth == 1 && $0.line.rect.minX >= edge + body }
            candidates[index].depth = roman ? 0 : 1
        }
        let tiers = Dictionary(grouping: candidates, by: { $0.depth! })
        guard tiers.count >= 2, candidates.contains(where: { LabelStyle($0.line, body: body).bold }) else { return [] }
        for outer in tiers.keys {
            for inner in tiers.keys where inner > outer {
                guard let outerEdge = tiers[outer]!.map(\.line.rect.minX).max(),
                      let innerEdge = tiers[inner]!.map(\.line.rect.minX).min(),
                      outerEdge + body <= innerEdge else { return [] }
            }
        }
        return candidates.map { ($0.line, $0.depth!) }
    }

    /// A section label's typography relative to its page: its size and the body's (to the half
    /// point), whether every word is bold, and whether a line that is not bold is wholly italic.
    /// The FAA handbook sets its section titles in 12-point bold over 10-point prose, and its
    /// lowest titles in 10-point italic (#97). A bold line never carries the italic flag, so
    /// bold and bold-italic labels keep one style between them as before.
    struct LabelStyle: Hashable {
        var size: Int
        var body: Int
        var bold: Bool
        var italic: Bool

        init(_ line: TextLine, body: CGFloat) {
            size = Int((line.fontSize * 2).rounded())
            self.body = Int((body * 2).rounded())
            func wholly(_ trait: TextStyle) -> Bool {
                line.content.elements.allSatisfy { element in
                    guard case let .text(value, style) = element else { return true }
                    return style.contains(trait) || value.allSatisfy(\.isWhitespace)
                }
            }
            bold = wholly(.bold)
            italic = !bold && wholly(.italic)
        }
    }

    /// The line's first character past opening quotes and brackets is a capital letter.
    static func opensWithCapital(_ line: TextLine) -> Bool {
        line.text.first(where: { !"([\u{201C}\u{2018}\"'".contains($0) && !$0.isWhitespace })?.isUppercase == true
    }

    /// A title set in title case: at most ten words, every word of four or more letters
    /// capitalised (`Coupled Ailerons and Rudder`, `Southerly Turning Errors`). An italic phrase
    /// in prose or an italic sentence is rarely set so (#90, #97).
    static func isTitleCase(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.count <= 10 && words.allSatisfy { word in
            let letters = word.drop { !$0.isLetter }
            return letters.filter(\.isLetter).count < 4 || letters.first?.isUppercase == true
        }
    }

    /// A list line set directly beneath a title opens the list the title heads: its marker
    /// stands on the title's left edge or up to 2.5 em inside it (FAA page 48 indents its
    /// bullets 9 points under `Airport` and `Airspace`; #97).
    static func opensListBeneath(_ below: TextLine, title: TextLine, body: CGFloat) -> Bool {
        let indent = below.rect.minX - title.rect.minX
        return isList(below.text) && indent >= -body * 0.5 && indent <= body * 2.5
    }

    /// The label styles one page's narrow section labels establish, measured as `blocks` measures
    /// them but before image regions are known: lines inside a painted graphic, running heads and
    /// margin lines are no evidence. `labelStyles(from:)` keeps the styles that recur.
    static func labelEvidence(on page: PageContent) -> Set<LabelStyle> {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        let figures = page.graphics.filter { !isThinRule($0) }
        let lines = page.lines.map { line -> TextLine in
            var copy = line; copy.structure = nil; return copy
        }.filter { line in
            !figures.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) }
                && !inMargin(line, of: page) && !isHeaderLike(line, in: page, bothBands: true)
        }
        let body = max(4, bodySize(page.lines))
        let boxes = clusters(page.tints, distance: 4)
        let outside = lines.filter { line in !boxes.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }
        let reflowBody = headingBodySize(outside, pageBody: body)
        let threshold = max(body * 1.25, reflowBody * 1.1)
        return Set(sectionLabels(in: lines, body: reflowBody, headingThreshold: threshold, page: page,
                                 recordingSubheadings: true)
            .filter { !isContentsEntry($0.text) }.map { LabelStyle($0, body: reflowBody) })
    }

    /// The styles of one page's heading-size lines (at or past the page's heading threshold),
    /// measured as `labelEvidence(on:)` measures labels: lines inside a painted graphic, running
    /// heads and contents entries are no evidence, and neither is a line with fewer than two
    /// letters (a drop cap, a numeral, a folio such as `C-1`). The margin bands stay in: a chapter
    /// label sits high on its opening page. `labelStyles(from:)` keeps the styles that recur: the
    /// FAA handbook opens each chapter with a 16-point `Chapter N` over a 48-point title (#84).
    static func headingEvidence(on page: PageContent) -> Set<LabelStyle> {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        let figures = page.graphics.filter { !isThinRule($0) }
        let lines = page.lines.map { line -> TextLine in
            var copy = line; copy.structure = nil; return copy
        }.filter { line in
            !figures.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) }
                && !isHeaderLike(line, in: page, bothBands: true)
        }
        let body = max(4, bodySize(page.lines))
        let boxes = clusters(page.tints, distance: 4)
        let outside = lines.filter { line in !boxes.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }
        let reflowBody = headingBodySize(outside, pageBody: body)
        let threshold = max(body * 1.25, reflowBody * 1.1)
        return Set(lines.filter { line in
            !line.monospaced && line.fontSize >= threshold && line.text.count < 200
                && line.text.filter(\.isLetter).count >= 2 && line.rect.width >= line.rect.height
                && !isContentsEntry(line.text)
        }.map { LabelStyle($0, body: reflowBody) })
    }

    /// A style is the book's label typography once narrow labels set in it appear on at least
    /// three pages; `pages` counts the pages whose evidence names each style. The same count
    /// selects the book's recurring heading styles from `headingEvidence(on:)`.
    static func labelStyles(from pages: [LabelStyle: Int]) -> Set<LabelStyle> {
        Set(pages.filter { $0.value >= 3 }.keys)
    }

    /// The titles of tinted boxes set in the box's own text size (#100). The Fed's narrow sidebars
    /// open with an 8-point demibold title over 8-point book text (`A fresh look at the monetary
    /// policy framework`), below the page's heading size and label band, and PDFKit names both
    /// fonts `Helvetica`, so no bold run marks the title either. The box's spacing does: the title
    /// is the top line of the box's text column, set off from the text beneath by more than that
    /// text's own leading (15.6-point pitch over 12). A title set over two lines keeps its lines at
    /// no more than that leading (10-point pitch) and sets the space after its second line
    /// (`Finding data on institutions supervised by the` / `Federal Reserve`).
    ///
    /// The box's lines are read top to bottom as they stand, so the line directly beneath the title
    /// and the next one below it are the box's next two lines, whatever their edge: the text
    /// beneath continues on the title's left edge at the title's size (the leading between those
    /// two lines is measured, not assumed). A paragraph that opens on a first-line indent is no
    /// title's text: the 9/11 report's page 348 sidebar indents `The FBI interviewed…` under a
    /// two-line paragraph. The title reads as one: a capital, digit or quotation mark first, no
    /// closing `.`, `,`, `;` or `:` before any raised note marker (`…allowed to depart.30`; a
    /// question stays a title: `What does “systemically important” mean?`), no list marker or
    /// leader, and no line wider than the box's text measure (the title can outrun the ragged line
    /// directly beneath it, page 19). A box whose first paragraph ends a sentence before paragraph
    /// space (the Fed's page 63 `…den’s Riksbank was formed.`) has no title; a box title at heading
    /// size is a heading already. Recognized and synthetic pages have no trustworthy sizes.
    static func boxTitles(in lines: [TextLine], page: PageContent) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var titles: [TextLine] = []
        for hull in clusters(page.tints, distance: 4) {
            let stack = lines.filter { hull.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                .sorted { $0.rect.maxY > $1.rect.maxY }
            guard let first = stack.first else { continue }
            let size = first.fontSize
            // One line to a row: a row PDFKit split (or two columns) is no stack of lines.
            guard stack.count >= 3, !zip(stack, stack.dropFirst()).prefix(3).contains(where: { sameRow($0.rect, $1.rect) })
            else { continue }
            for count in 1...2 where stack.count >= count + 2 {
                let title = Array(stack.prefix(count))
                let below = stack[count]
                let next = stack[count + 1]
                guard (title + [below]).allSatisfy({ abs($0.rect.minX - first.rect.minX) <= size * 0.5
                          && abs($0.fontSize - size) <= size * 0.1 }),
                      abs(next.fontSize - size) <= size * 0.1 else { break }
                let leading = below.rect.minY - next.rect.maxY
                let gap = title[count - 1].rect.minY - below.rect.maxY
                let measure = stack.dropFirst(count).filter { abs($0.rect.minX - first.rect.minX) <= size * 0.5 }
                    .map(\.rect.width).max() ?? 0
                let text = title.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                guard gap >= leading + size * 0.25, gap <= size * 2.5, leading >= -size * 0.4,
                      zip(title, title.dropFirst()).allSatisfy({ $0.rect.minY - $1.rect.maxY <= leading + size * 0.1 }),
                      title.allSatisfy({ $0.rect.width <= measure + size * 0.5 }),
                      text.count < 150, text.filter(\.isLetter).count >= 2,
                      let initial = text.first(where: { !"([\u{201C}\"'".contains($0) }), initial.isUppercase || initial.isNumber,
                      let last = lastCharacterBeforeMarker(title[count - 1]), !".,;:".contains(last),
                      !title.contains(where: { isList($0.text) || isContentsEntry($0.text) || $0.text.contains("....") })
                else { continue }
                titles += title
                break
            }
        }
        return titles
    }

    /// The lines of a slide's title: the topmost text of a landscape page, standing in the band
    /// at the head of the slide, alone on its row and clear of the text beneath it (#165).
    ///
    /// A slide's title cannot be told from its type size, which is what `blocks` measures a
    /// heading by. A slide carries one title and a handful of body words, so the page's
    /// character-weighted body size is as often the title's own type as the body's (the
    /// Earthdata deck's two-line `Over time, EOSDIS archive volumes` / `increase exponentially`
    /// outweighs the one word beside the chart it heads, and `Architectural Concept` is set
    /// *smaller* than the statement under it), while a diagram slide's body runs from 14-point
    /// boxes down to an 8-point note, so the smallest of them would make the boxes headings.
    /// What a deck repeats is the place: every slide sets its title in the same band at the top.
    ///
    /// The title is the topmost line, its top within the outer eighth of the page, reading as a
    /// title (a capital or digit first, a word, no terminal punctuation, no list marker) with no
    /// other line on its row, followed by the lines that stack under it as a heading's do
    /// (`continuesHeading`), and set off from the slide's body by at least half its own height.
    /// A page whose topmost text is a running head, a folio or body prose has no slide title, and
    /// neither has a portrait page: this is the evidence `isSlide(_:)` counts to decide a deck.
    static func slideTitle(in lines: [TextLine], bounds: CGRect) -> [TextLine] {
        guard bounds.width > bounds.height, bounds.height > 0, bounds.isFinite else { return [] }
        let candidates = lines.filter { !$0.monospaced && $0.fontSize > 0 && $0.rect.isFinite
            && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = candidates.max(by: { $0.rect.maxY < $1.rect.maxY }),
              bounds.maxY - first.rect.maxY <= bounds.height * 0.125,
              first.text.count < 200, first.text.filter(\.isLetter).count >= 2,
              !isList(first.text), !isContentsEntry(first.text), !endsSentence(first.text),
              let initial = first.text.first(where: { !"([\u{201C}\"'".contains($0) && !$0.isWhitespace }),
              initial.isUppercase || initial.isNumber,
              !candidates.contains(where: { $0 != first && sameRow($0.rect, first.rect) })
        else { return [] }
        var title = [first]
        while let next = candidates.filter({ line in
            !title.contains(line) && continuesHeading(title.map(\.text).joined(separator: " "), with: line, after: title[title.count - 1])
        }).max(by: { $0.rect.maxY < $1.rect.maxY }) {
            title.append(next)
        }
        let bottom = title.map(\.rect.minY).min() ?? first.rect.minY // `title` always holds `first`
        let below = candidates.filter { line in !title.contains(line) && line.rect.maxY < bottom }
        if let highest = below.map(\.rect.maxY).max(), bottom - highest < first.rect.height * 0.5 { return [] }
        return title
    }

    /// Whether a page reads as one slide of a deck: a landscape page carrying one screenful of
    /// text (at most 600 characters, where the deck's fullest slide sets 346 and the smallest
    /// landscape book page in the corpus, NOAA's, sets thousands) under a title in its head band
    /// (`slideTitle`). The pipeline counts these pages: a document of at least three pages, every
    /// page the same landscape size, where two thirds of the pages carrying text are slides, is a
    /// deck, and its slides' titles are headings whatever their size.
    static func isSlide(_ page: PageContent) -> Bool {
        guard !page.hasSyntheticTextStyle,
              page.lines.reduce(0, { $0 + $1.text.count }) <= 600 else { return false }
        return !slideTitle(in: page.lines, bounds: page.bounds).isEmpty
    }

    /// A line's last visible character past closing quotes and brackets and past a raised
    /// reference marker (`…allowed to depart.30`), as `opensSection` reads a sentence's end.
    private static func lastCharacterBeforeMarker(_ line: TextLine) -> Character? {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        for element in line.content.elements.reversed() {
            guard case let .text(value, style) = element else { continue }
            if style.contains(.superscript), value.allSatisfy({ $0.isNumber || $0.isWhitespace }) { continue }
            if let character = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) { return character }
        }
        return nil
    }

    /// A contents entry: a dot leader of four or more dots running to the line's end, with or
    /// without its folio (PDFKit can split the folio into a same-row line). Contents pages set
    /// their chapter entries at heading size, but a leader never ends a heading (#55). The folio
    /// can be numbered within its chapter or lettered part (`Introduction To Flying.......1-1`,
    /// `Glossary.......G-1`; #97).
    static func isContentsEntry(_ text: String) -> Bool {
        text.range(of: #"(?:\.\s*){4,}(?:\d{1,4}|[ivxlcdm]{1,8}|(?:\d{1,3}|[a-z])[-–]\d{1,4})?\s*$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether `line` is the next line of the heading `previous` opens: the same size, set
    /// directly beneath it at ordinary heading leading (the rectangles include PDFKit's
    /// leading, so they touch or overlap), sharing the left edge, the centre or the right edge.
    ///
    /// With `hanging`, the line may instead start under the previous line's text past its
    /// section number: acmart indents `OVERHEAD` under `REPRESENTATION` in `6 REPRESENTATION OF
    /// REPCL AND ITS` (#83), and the 9/11 report `LAW ENFORCEMENT COMMUNITY` under `3.2
    /// ADAPTATION—AND NONADAPTATION—IN THE`. The indent is past the shared edge but no wider than
    /// the number and its space can be set: 0.6 em per character and one em for the space.
    static func stacksUnderHeading(_ line: TextLine, after previous: TextLine, hanging: Bool = false,
                                   hangingIndent: Bool = false) -> Bool {
        let size = max(previous.fontSize, line.fontSize)
        guard abs(previous.fontSize - line.fontSize) <= size * 0.1, !sameRow(previous.rect, line.rect),
              line.rect.minY < previous.rect.minY, line.rect.maxY >= previous.rect.minY - size,
              previous.rect.minY - line.rect.minY <= size * 2.2 else { return false }
        // A title wrapped into its page's hanging indent (`hangingEntryEdges`, #134).
        if hangingIndent {
            let indent = line.rect.minX - previous.rect.minX
            return indent >= size * 0.5 && indent <= size * 2.5
        }
        if abs(previous.rect.minX - line.rect.minX) <= size * 0.6
            || abs(previous.rect.midX - line.rect.midX) <= size * 0.6
            || abs(previous.rect.maxX - line.rect.maxX) <= size * 0.6 { return true }
        guard hanging, let number = previous.text.range(of: #"^\d+(?:\.\d+)*\.?(?=\s+\S)"#, options: .regularExpression)
        else { return false }
        let indent = line.rect.minX - previous.rect.minX
        let characters = CGFloat(previous.text.distance(from: number.lowerBound, to: number.upperBound))
        return indent > size * 0.6 && indent <= size * (0.6 * characters + 1)
    }

    /// A left edge whose entries wrap into a hanging indent (#134). The 9/11 report's hearings
    /// appendix (pages 458–465) lists each panel's witnesses one to an entry, flush left, and sets
    /// an entry's wrapped lines one em in (`Ken Holden, Commissioner, New York City Department of` /
    /// `Design and Construction`); a panel title that wraps does the same. Such a pair is a line on
    /// the edge that ends no sentence, with a line directly beneath it at ordinary leading, in its
    /// size, starting 0.5–2.5 ems further in and not centred under it. Prose that indents its
    /// paragraphs' first lines sets the same step under a line that ends a sentence (or a colon
    /// or semicolon), so an edge qualifies only when it has at least one wrapped-entry pair and no
    /// such opening. A wholly bold upper line is a title, and a title wrapped into the indent is no
    /// evidence for itself (FAA page 21's two-line subhead). Lists, code, centred display lines,
    /// leader entries (an index's sub-entries, FAA page 521) and a line without letters over an
    /// indented one (Loper Bright's footnote rule over `*Together with No. 22–1219, …`) are no
    /// evidence either.
    ///
    /// A page can list entries in the book's hanging style without any entry long enough to wrap
    /// (9/11 page 457, #161). Its edge qualifies by the titles over it instead (`titled`): at least
    /// two lines wholly bold in a style of `titles` (the book's recurring label styles) stand on the
    /// edge, each over an entry on it in its own size at ordinary leading; no entry of that size
    /// wraps flush onto the edge beneath it (a line opening in lowercase, or after a line-end
    /// hyphen or slash); none opens on an indent under a sentence's end; and the size has no
    /// justified measure on the page, since lines filling a measure are prose however they are
    /// headed.
    struct HangingEdge {
        var x: CGFloat
        var size: CGFloat
        /// The wrapped-entry pairs seen on the edge.
        var pairs: Int
        /// Qualified by the titles over its entries rather than by a wrapped entry.
        var titled = false
        /// No entry of the edge's size continues flush on the edge: its only wraps hang.
        var hangsOnly = false
        /// For an edge whose one-line entries stand apart by added space (`spacedEntryEdges`,
        /// #181), the least gap that sets an entry apart: an entry opens only that far below the
        /// line above it, never at the edge's own wrap.
        var spacing: CGFloat? = nil
    }

    /// The page's hanging-entry edges (see `HangingEdge`). With `body`, only lines in the body's size
    /// are evidence: a heading-size title hung under its section number is `continuesHeading`'s
    /// (Replay Clocks page 6, #83).
    static func hangingEntryEdges(_ lines: [TextLine], body: CGFloat? = nil,
                                  titles: Set<LabelStyle> = []) -> [HangingEdge] {
        var pairs: [(x: CGFloat, size: CGFloat, wraps: Bool)] = []
        for upper in lines where !upper.monospaced && !isList(upper.text) && upper.fontSize > 0
            && upper.text.contains(where: \.isLetter) && !LabelStyle(upper, body: upper.fontSize).bold
            && body.map({ abs(upper.fontSize - $0) <= $0 * 0.1 }) != false {
            let size = upper.fontSize
            guard let lower = lines.filter({ other in
                other != upper && !sameRow(other.rect, upper.rect) && abs(other.fontSize - size) <= size * 0.1
                    && other.rect.maxY <= upper.rect.minY + size * 0.4
                    && other.rect.minX < upper.rect.maxX && other.rect.maxX > upper.rect.minX
            }).max(by: { $0.rect.maxY < $1.rect.maxY }) else { continue }
            let gap = upper.rect.minY - lower.rect.maxY
            let indent = lower.rect.minX - upper.rect.minX
            guard gap >= -size * 0.4, gap < size * 0.9, indent >= size * 0.5, indent <= size * 2.5,
                  !lower.monospaced, !isList(lower.text),
                  abs((lower.rect.minX - upper.rect.minX) - (upper.rect.maxX - lower.rect.maxX)) > size * 0.5,
                  !upper.text.contains("...."), !lower.text.contains("....") else { continue }
            let ends = lastCharacterBeforeMarker(upper).map { ".!?:;".contains($0) } ?? true
            pairs.append((upper.rect.minX, size, !ends))
        }
        var edges: [HangingEdge] = []
        for pair in pairs where pair.wraps {
            func sameEdge(_ x: CGFloat, _ size: CGFloat) -> Bool {
                abs(x - pair.x) <= pair.size * 0.5 && abs(size - pair.size) <= pair.size * 0.1
            }
            guard !pairs.contains(where: { !$0.wraps && sameEdge($0.x, $0.size) }),
                  !edges.contains(where: { sameEdge($0.x, $0.size) }) else { continue }
            edges.append(HangingEdge(x: pair.x, size: pair.size,
                                     pairs: pairs.filter { $0.wraps && sameEdge($0.x, $0.size) }.count))
        }
        // The line set directly beneath `upper` at ordinary leading in its size, if any.
        func beneath(_ upper: TextLine) -> TextLine? {
            let size = upper.fontSize
            guard let lower = lines.filter({ other in
                other != upper && !sameRow(other.rect, upper.rect) && abs(other.fontSize - size) <= size * 0.1
                    && other.rect.maxY <= upper.rect.minY + size * 0.4
                    && other.rect.minX < upper.rect.maxX && other.rect.maxX > upper.rect.minX
            }).max(by: { $0.rect.maxY < $1.rect.maxY }) else { return nil }
            let gap = upper.rect.minY - lower.rect.maxY
            return gap >= -size * 0.4 && gap < size * 0.9 ? lower : nil
        }
        func entryLine(_ line: TextLine) -> Bool {
            !line.monospaced && !isList(line.text) && line.fontSize > 0 && !LabelStyle(line, body: line.fontSize).bold
        }
        func on(_ line: TextLine, _ x: CGFloat, _ size: CGFloat) -> Bool {
            abs(line.rect.minX - x) <= size * 0.5 && abs(line.fontSize - size) <= size * 0.1
        }
        // An entry of the edge's size that runs on flush beneath another on the edge.
        func runsOnFlush(_ x: CGFloat, _ size: CGFloat) -> Bool {
            lines.contains { upper in
                guard entryLine(upper), on(upper, x, size), let lower = beneath(upper), entryLine(lower),
                      on(lower, x, size) else { return false }
                return lower.text.first(where: \.isLetter)?.isLowercase == true
                    || upper.text.last.map({ "-\u{00AD}/".contains($0) }) == true
            }
        }
        // Titled edges (#161): no wrapped entry, but titles in the book's label style over entries.
        if !titles.isEmpty {
            let measures = justifiedMeasures(lines)
            var heads: [(x: CGFloat, size: CGFloat)] = []
            for title in lines where !title.monospaced && title.fontSize > 0
                && titles.contains(LabelStyle(title, body: body ?? title.fontSize)) && LabelStyle(title, body: title.fontSize).bold
                && body.map({ abs(title.fontSize - $0) <= $0 * 0.1 }) != false {
                guard let entry = beneath(title), entryLine(entry), on(entry, title.rect.minX, title.fontSize) else { continue }
                heads.append((title.rect.minX, title.fontSize))
            }
            for head in heads {
                func sameEdge(_ x: CGFloat, _ size: CGFloat) -> Bool {
                    abs(x - head.x) <= head.size * 0.5 && abs(size - head.size) <= head.size * 0.1
                }
                guard heads.filter({ sameEdge($0.x, $0.size) }).count >= 2,
                      !edges.contains(where: { sameEdge($0.x, $0.size) }),
                      !pairs.contains(where: { !$0.wraps && sameEdge($0.x, $0.size) }),
                      measures[Int(head.size.rounded())] == nil, !runsOnFlush(head.x, head.size) else { continue }
                edges.append(HangingEdge(x: head.x, size: head.size, pairs: 0, titled: true))
            }
        }
        return edges.map { edge in
            var edge = edge
            edge.hangsOnly = !runsOnFlush(edge.x, edge.size)
            return edge
        }
    }

    /// A left edge whose one-line entries stand apart by added space (#181). NOAA's chapter
    /// openers list each chapter's authors and contributors one to a line, a name and an
    /// affiliation, flush on one edge and never wrapped, so #134's hanging indent never appears:
    /// `Robert G. Byron, Montana Health Professionals for a Healthy Climate` / `Amy E. East, US
    /// Geological Survey` ran together, and nothing ends a sentence between them. The book shows
    /// how its own text wraps at that size — the recommended citation beneath runs to the measure
    /// a tenth of a point under the line above — and the entries stand 3.2 points apart (page 81)
    /// or 7.7 (page 1700), at one even leading from the first to the last.
    ///
    /// The edge's wrap (`edgeWraps`) is the least gap under a line that reaches within one size
    /// of the edge's widest line, to the nearest line directly beneath it on the edge: that line
    /// filled the measure, so the next continued it. The measure needs three lines to reach it, as
    /// #157's does, since the widest line or two may be the longest entries (page 692's). Where the
    /// edge has none (page 343 sets its citation overleaf, and page 81's reaches its measure on two
    /// lines), the book's wrap at that size stands in (`bookWrap`). A run
    /// is at least three lines on the edge, each the nearest beneath the one before it, at gaps
    /// within a tenth of a size of the first and at least a fifth of a size over the wrap, and
    /// none of the run's upper lines reaches the measure. A paragraph's wrapped lines sit at the
    /// wrap, and space between paragraphs never repeats three lines running unless each is a
    /// paragraph of its own. Lists, code, leader entries, wholly bold labels and lines out of the
    /// body's size are no evidence, as for `hangingEntryEdges`, and a page of more than
    /// `TintDetector.blockTextLineLimit` lines has none. An entry on such an edge opens only that
    /// fifth of a size over the wrap below the line above it (`HangingEdge.spacing`).
    static func spacedEntryEdges(_ lines: [TextLine], body: CGFloat, bookWrap: CGFloat? = nil) -> [HangingEdge] {
        edgeWraps(lines, body: body).compactMap { found in
            let edge = found.lines, size = found.size, beneath = found.beneath
            guard let wrap = found.wrap ?? bookWrap else { return nil }
            let spaced = wrap + size * 0.2
            let qualified = edge.indices.contains { start in
                var last = start, count = 1
                var first: CGFloat?
                while !found.fills(last), let next = beneath[last], next.gap >= spaced,
                      abs(next.gap - (first ?? next.gap)) <= size * 0.1 {
                    first = first ?? next.gap
                    last = next.line
                    count += 1
                    if count >= 3 { return true }
                }
                return false
            }
            return qualified ? HangingEdge(x: found.x, size: size, pairs: 0, spacing: spaced) : nil
        }
    }

    /// The gap at which a page's text of the body's size wraps (#181): the median over its edges
    /// (`edgeWraps`) of each edge's own wrap, nil when no line on any edge fills its measure. The
    /// book's wrap at a size is the median of its pages' (`PDFReflowLibPipeline`), which stands in
    /// for an edge of one-line entries on a page with no wrapped line of its own.
    static func wrapGap(_ lines: [TextLine], body: CGFloat) -> CGFloat? {
        let wraps = edgeWraps(lines, body: body).compactMap(\.wrap).sorted()
        return wraps.isEmpty ? nil : wraps[wraps.count / 2]
    }

    /// A page's evidence for its book's wrap (#181): its body size, to the half point, and the gap
    /// its text of that size wraps at (`wrapGap`). A recognized page or a synthetic text layer's
    /// geometry is Vision's, not the book's, and gives none.
    static func wrapEvidence(on page: PageContent) -> (size: Int, gap: CGFloat)? {
        guard !page.recognized, !page.hasSyntheticTextStyle else { return nil }
        let body = bodySize(page.lines)
        guard body > 0, let gap = wrapGap(page.lines, body: body) else { return nil }
        return (wrapKey(body), gap)
    }

    /// The book's wrap at each body size: the median of its pages' (`wrapEvidence`), where at least
    /// three pages give one.
    static func bookWraps(from evidence: [Int: [CGFloat]]) -> [Int: CGFloat] {
        evidence.compactMapValues { gaps in
            guard gaps.count >= 3 else { return nil }
            return gaps.sorted()[gaps.count / 2]
        }
    }

    /// A body size to the half point, the key of `bookWraps`.
    static func wrapKey(_ size: CGFloat) -> Int { Int((size * 2).rounded()) }

    /// The page's left edges of body-size lines that could hold entries (see `spacedEntryEdges`),
    /// each with its lines top to bottom, each line's nearest neighbour beneath it on the edge inside
    /// the prose window, whether a line reaches the edge's measure, and the edge's wrap.
    private static func edgeWraps(_ lines: [TextLine], body: CGFloat)
        -> [(x: CGFloat, size: CGFloat, lines: [TextLine], beneath: [(line: Int, gap: CGFloat)?],
             fills: (Int) -> Bool, wrap: CGFloat?)] {
        guard lines.count <= TintDetector.blockTextLineLimit else { return [] }
        let candidates = lines.filter { line in
            !line.monospaced && !isList(line.text) && line.fontSize > 0 && line.text.contains(where: \.isLetter)
                && !line.text.contains("....") && abs(line.fontSize - body) <= body * 0.1
                && !LabelStyle(line, body: line.fontSize).bold
        }.sorted { $0.rect.maxY > $1.rect.maxY }
        guard candidates.count >= 4 else { return [] }
        var result: [(x: CGFloat, size: CGFloat, lines: [TextLine], beneath: [(line: Int, gap: CGFloat)?],
                      fills: (Int) -> Bool, wrap: CGFloat?)] = []
        var assigned = Set<Int>()
        for index in candidates.indices where !assigned.contains(index) {
            let anchor = candidates[index], size = anchor.fontSize
            let onEdge = candidates.indices.filter { other in
                !assigned.contains(other) && abs(candidates[other].rect.minX - anchor.rect.minX) <= size * 0.5
                    && abs(candidates[other].fontSize - size) <= size * 0.1
            }
            assigned.formUnion(onEdge)
            let edge = onEdge.map { candidates[$0] }
            guard edge.count >= 4, let measure = edge.map(\.rect.maxX).max() else { continue }
            let beneath: [(line: Int, gap: CGFloat)?] = edge.indices.map { upper in
                guard let lower = edge.indices.filter({ other in
                    other != upper && !sameRow(edge[other].rect, edge[upper].rect)
                        && edge[other].rect.maxY <= edge[upper].rect.minY + size * 0.4
                }).max(by: { edge[$0].rect.maxY < edge[$1].rect.maxY }) else { return nil }
                let gap = edge[upper].rect.minY - edge[lower].rect.maxY
                return gap >= -size * 0.4 && gap < size * 0.9 ? (lower, gap) : nil
            }
            let fills = { (line: Int) in edge[line].rect.maxX >= measure - size }
            // A line or two at the widest is no measure: they may be the longest entries.
            let full = edge.indices.filter(fills)
            let wrap = full.count >= 3 ? full.compactMap { beneath[$0]?.gap }.min() : nil
            result.append((anchor.rect.minX, size, edge, beneath, fills, wrap))
        }
        return result
    }

    /// The hanging-entry edge (`hangingEntryEdges`) a line stands on, if any.
    static func hangingEntryEdge(of line: TextLine, in edges: [HangingEdge]) -> HangingEdge? {
        edges.first { abs(line.rect.minX - $0.x) <= $0.size * 0.5 && abs(line.fontSize - $0.size) <= $0.size * 0.1 }
    }

    /// Terminal punctuation past closing quotes and brackets; a colon ends a heading's first
    /// line (`The Federal Open Market Committee:` / `Selection and Function`), not a sentence.
    private static func endsSentence(_ text: String) -> Bool {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        guard let ending = text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) else { return false }
        return ".!?".contains(ending)
    }

    /// A line that opens a heading of its own rather than continuing the one above it: a
    /// section number or a chapter label. Two same-size headings stacked without such a mark
    /// are the lines of one title.
    private static func opensHeading(_ text: String) -> Bool {
        text.range(of: #"^(?:\d+(?:\.\d+)+\.?\s|(?:Chapter|Part|Section|Appendix|Unit|Lesson)\s+(?:\d+|[IVXLC]+)\b)"#,
                   options: .regularExpression) != nil
    }

    /// The lines of one heading set over several lines merge into one heading: the next line
    /// stacks under the previous at the same size and alignment, the heading so far does not
    /// end a sentence, and the line does not open a numbered heading of its own (#55). A line
    /// hanging under a numbered first line's text continues it too (#83).
    static func continuesHeading(_ heading: String, with line: TextLine, after previous: TextLine) -> Bool {
        stacksUnderHeading(line, after: previous, hanging: heading == previous.text)
            && !endsSentence(heading) && !opensHeading(line.text)
    }

    /// A chapter opener's pull quote is set in display type between the body and the title,
    /// over several lines, and reads as a sentence: the run ends in terminal punctuation and
    /// carries at least eight words. It is prose, not one heading per printed line (#55). A
    /// multi-line title has no terminal punctuation; a one-line heading ending in a period
    /// stays a heading. `lines` are the page's lines in reading order and `candidates` names
    /// the heading-size and label lines among them.
    static func pullQuoteLines(in lines: [TextLine], candidates: (TextLine) -> Bool) -> [TextLine] {
        var quotes: [TextLine] = []
        var run: [TextLine] = []
        func close() {
            if run.count >= 2, let last = run.last, endsSentence(last.text),
               run.reduce(0, { $0 + wordCount($1.text) }) >= 8 { quotes += run }
            run = []
        }
        for line in lines {
            guard candidates(line) else { close(); continue }
            if let previous = run.last, !stacksUnderHeading(line, after: previous) { close() }
            run.append(line)
        }
        close()
        return quotes
    }

    /// Heading sizes ranked into tiers (7% apart), largest first.
    static func headingTiers(_ sizes: [CGFloat]) -> [CGFloat] {
        var tiers: [CGFloat] = []
        for size in sizes.sorted(by: >) where !(tiers.last.map { size >= $0 * 0.93 } ?? false) {
            tiers.append(size)
        }
        return tiers
    }

    /// Levels for headings, ranked document-wide once every page is reconstructed: the largest
    /// tier keeps the existing level 2 of the flat navigation model and each smaller tier is one
    /// level deeper (to 6), so a title outranks the author names beneath it and a chapter title
    /// outranks its section labels on every page alike (#43).
    ///
    /// A tagged heading keeps its validated level (#43), but only where that level is comparable
    /// with the ranking the rest of the document uses. A source whose heading hierarchy is only
    /// partly reconstructable otherwise contradicts itself: the Fed's chapter titles sit on
    /// image-backed pages, so their `H2` never reaches this stage, and their 16-point `H3`
    /// sections would become siblings of the 24-point chapter titles above them (#67).
    ///
    /// A validated level therefore yields only to a typographic heading that is larger than every
    /// heading the document tags at that level and already ranks at that level or deeper. A
    /// larger heading inside the tagged size range is a sibling the tags did not reach, not a
    /// contradiction: Our Flag tags `H3` from 9 to 21 points, so its untagged 20-point
    /// `"The Star-Spangled Banner"` does not demote `Flag Anatomy` at 18. A level that yields
    /// ranks all its headings by size, like every other heading.
    ///
    /// A heading contributes its size to the tiers exactly when it is ranked on them, so a
    /// validated level neither adds a tier the document does not otherwise use nor removes the
    /// one its own typography provides: the Fed's tagged section titles restore the tier their
    /// untagged siblings used to supply, while a book whose validated levels all hold ranks
    /// exactly as it did before any tag applied. One pass over the blocks' sizes; no page geometry.
    ///
    /// `slideDeck` says the document is a deck (`isSlide(_:)`), where the size tiers say nothing:
    /// a slide carries one title, and a deck sets each slide's title to fit the words on it, so
    /// the Earthdata deck's 52-, 32-, 30-, 28- and 26-point titles rank into four tiers of one rank.
    /// Every ranked heading of a deck is level 2; a validated level still holds, as it does above.
    ///
    /// An outline's section labels (`outlineDepth`, #152) are set at the body's size whatever their
    /// tier, so their size says nothing of their rank. They take no part in the size tiers: the
    /// outermost tier ranks where the size scale places its size, and each inner tier one level
    /// deeper (to 6). The US Courts form's `I.` sections fall under its 20- and 13-point titles
    /// at level 4, their `A.` parts at 5 and the numbered parts at 6.
    static func rankHeadingLevels(_ blocks: inout [ReflowBlock], slideDeck: Bool = false) {
        func ranker(_ sizes: [CGFloat]) -> (CGFloat) -> Int {
            let tiers = headingTiers(sizes)
            return { value in min(6, 2 + (tiers.firstIndex { value >= $0 * 0.93 } ?? tiers.count)) }
        }
        let headings = blocks.compactMap { block -> (size: CGFloat, validated: Int?)? in
            guard let size = block.headingSize, block.outlineDepth == nil, case .heading = block.content else { return nil }
            return (size, block.taggedLevel)
        }
        var largestTagged: [Int: CGFloat] = [:]
        for heading in headings {
            if let validated = heading.validated { largestTagged[validated] = max(largestTagged[validated] ?? 0, heading.size) }
        }
        // Rank the typographic headings first, then see which validated levels that scale
        // contradicts; only those join it, and the final scale settles every ranked heading.
        let spatial = ranker(headings.filter { $0.validated == nil }.map(\.size))
        // Once a level yields, every deeper level yields with it: a validated level beneath one that
        // typography now ranks could otherwise land beside it (the Fed's 12-point `H5` beside its
        // re-ranked 14-point `H4`), so below the break the whole hierarchy is ranked by size.
        let firstYielding = largestTagged.compactMap { validated, largest -> Int? in
            headings.contains { $0.validated == nil && $0.size > largest * 1.07 && spatial($0.size) >= validated }
                ? validated : nil
        }.min()
        func yields(_ validated: Int) -> Bool { firstYielding.map { validated >= $0 } ?? false }
        let byTier = ranker(headings.filter { $0.validated.map(yields) ?? true }.map(\.size))
        let ranked: (CGFloat) -> Int = slideDeck ? { _ in 2 } : byTier
        for index in blocks.indices {
            guard let size = blocks[index].headingSize,
                  case let .heading(id, text, _) = blocks[index].content else { continue }
            var level = ranked(size)
            if let validated = blocks[index].taggedLevel, !yields(validated) { level = validated }
            if let depth = blocks[index].outlineDepth { level = min(6, level + depth) }
            blocks[index].content = .heading(id: id, text: text, level: level)
        }
    }

    private static let mathSymbols = CharacterSet(charactersIn: "∫∑∏√∂∇≈≠≤≥∞")
    /// Arithmetic set in a line, for the hanging-entry continuation (#181).
    static let arithmetic = CharacterSet(charactersIn: "+=−×÷∫∑∏√∂∇≈≠≤≥∞")
    /// Signs of inline mathematics at which PDFKit splits a prose row (`joiningRowPieces`).
    private static let rowMathSymbols = mathSymbols.union(CharacterSet(charactersIn: "=·×÷±−"))

    /// Letters-only words of at least `minimum` letters (surrounding quotes, brackets and
    /// punctuation ignored) and the number of whitespace-separated tokens.
    private static func wordShare(_ text: String, minimum: Int = 3) -> (words: Int, tokens: Int) {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let edges = CharacterSet(charactersIn: "\"'“”‘’()[]{}.,;:!?")
        let words = tokens.filter { token in
            let core = String(token).trimmingCharacters(in: edges)
            return core.count >= minimum && core.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
        }.count
        return (words, tokens.count)
    }

    /// Text that reads as words: at least two words of three or more letters, and words of two
    /// or more letters making up at least 40% of the tokens. Prose dense with inline mathematics
    /// (`is where x = 0 and y = 0. As we move`) stays above that share, single-letter variables
    /// do not count; whether a wordy row is prose is decided by its measure. A token of operator
    /// signs alone is not a term: whether a sign stands apart depends only on whether the math
    /// space beside it was read (#188: PDFKit kept it on one side of Wallace's signs and dropped it
    /// on the other, so `representing x =1, 2, 3.` was two tokens where `x = 1` is three).
    private static func isWordy(_ text: String) -> Bool {
        let share = wordShare(text, minimum: 2)
        let signs = text.split(whereSeparator: \.isWhitespace)
            .filter { $0.unicodeScalars.allSatisfy(NativeSpacingReader.mathOperators.contains) }.count
        return wordShare(text).words >= 2 && share.words * 5 >= (share.tokens - signs) * 2
    }

    private static let functionWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "for", "from", "if", "in", "is",
        "it", "not", "of", "on", "or", "our", "so", "that", "the", "then", "there", "these", "this",
        "to", "was", "we", "when", "which", "will", "with",
    ]

    /// Words set as a sentence carry function words (`the`, `we`, `is`, `of`). A stacked display
    /// set the full measure reads as terms and names alone (`sin⁻¹(opposite/hypotenuse) = θ …`,
    /// Wallace page 428), however many letters its words have.
    private static func readsAsSentence(_ text: String) -> Bool {
        let edges = CharacterSet(charactersIn: "\"'“”‘’()[]{}.,;:!?")
        return text.split(whereSeparator: \.isWhitespace).contains {
            functionWords.contains(String($0).trimmingCharacters(in: edges).lowercased())
        }
    }

    /// The pieces of a line's visual row that read with it. PDFKit splits a prose row at an
    /// inline radical or superscript (`The square root of 25 is written as` / `25 √ .`); the
    /// pieces sit beside each other with text above or below spanning the gap between them,
    /// whereas a column gutter stays blank.
    private static func rowPieces(_ line: TextLine, in lines: [TextLine], body: CGFloat) -> [TextLine] {
        let candidates = lines.filter { $0 != line && sameRow($0.rect, line.rect) }
        var row = [line]
        var changed = true
        while changed {
            changed = false
            for piece in candidates where !row.contains(piece) {
                let joins = row.contains { member in
                    let start = min(member.rect.maxX, piece.rect.maxX), end = max(member.rect.minX, piece.rect.minX)
                    guard end > start else { return true }
                    guard end - start <= body * 2 else { return false }
                    return lines.contains { other in
                        !row.contains(other) && other != piece && !sameRow(other.rect, line.rect)
                            && other.rect.minX <= start && other.rect.maxX >= end
                            && max(other.rect.minY - line.rect.maxY, line.rect.minY - other.rect.maxY) <= body * 2
                    }
                }
                if joins { row.append(piece); changed = true }
            }
        }
        return row
    }

    /// A line whose visual row is prose: the row reads as a sentence and is set on its
    /// paragraph's measure. Either it is a full line of a justified paragraph (at least three
    /// other prose lines on the page share both of its edges, or two with one adjacent at
    /// ordinary leading), or an adjacent full line shares its left or right edge (a paragraph's
    /// indented first or short last line). An inline equation in such a row (`since the maximum
    /// driven velocity Uo = eEo/mw becomes`, NBS page 7; `We can use the product rule to
    /// simplify an expression such as √36·5`, Wallace page 288) is read as text (#51, #58). A
    /// displayed derivation is set apart from the paragraph's edges and stays a formula; a
    /// repeated annotation (`Change the signs and combine`, set three times down Wallace page
    /// 207 at one indent) shares edges with its repeats but has no adjacent full line.
    static func isProseRow(_ line: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        isProseRow(pieces: rowPieces(line, in: lines, body: body), in: lines, body: body)
    }

    /// `isProseRow` for a row whose pieces are already known; the first piece stands for the row.
    /// `fillingItsMeasure` drops the weaker reading, where an adjacent full line merely shares one
    /// of the row's edges: the row itself must be a full line of its paragraph (#148).
    private static func isProseRow(pieces row: [TextLine], in lines: [TextLine], body: CGFloat,
                                   fillingItsMeasure: Bool = false) -> Bool {
        guard let line = row.first else { return false }
        let text = row.map(\.text).joined(separator: " ")
        // A row whose pieces stand at least twice their type size stacks terms (fractions,
        // radical indices) and has spatial structure to preserve unless it reads as a sentence.
        // A single-level row keeps no structure a line of text cannot carry, so a word equation
        // set in the column's measure (`True Course (180°) ± Variation (+10°) = Magnetic
        // Course`, FAA page 227) reads as the text it is.
        let stacked = row.contains { $0.rect.height >= $0.fontSize * 2 }
        guard isWordy(text), !stacked || readsAsSentence(text) else { return false }
        let bounds = union(row.map(\.rect))
        let prose = lines.filter { other in
            !other.monospaced && wordShare(other.text).words >= 4 && isWordy(other.text)
        }
        func sharesEdges(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 2 && abs(a.maxX - b.maxX) <= 2
        }
        func adjacent(_ a: CGRect, _ b: CGRect) -> Bool {
            max(a.minY - b.maxY, b.minY - a.maxY) <= body * 2
        }
        func fullLine(_ rect: CGRect, excluding: [TextLine]) -> Bool {
            let sharing = prose.filter { !excluding.contains($0) && sharesEdges($0.rect, rect) }
            return sharing.count >= 3 || (sharing.count == 2 && sharing.contains { adjacent($0.rect, rect) })
        }
        if fullLine(bounds, excluding: row) { return true }
        guard !fillingItsMeasure else { return false }
        return prose.contains { other in
            !row.contains(other) && fullLine(other.rect, excluding: [other])
                && !sameRow(other.rect, line.rect) && adjacent(other.rect, bounds)
                && min(bounds.maxX, other.rect.maxX) > max(bounds.minX, other.rect.minX)
                && (abs(other.rect.minX - bounds.minX) <= 2 || abs(other.rect.maxX - bounds.maxX) <= 2)
        }
    }

    /// A text line a formula's margin must not reach: prose, or a row of words alone above the
    /// formula, an instruction or label introducing it (`Simplify.` over the page-291 exercises).
    /// A line carrying any term, number or operator (`Find g(3)+ f(3)` closing a page-398
    /// exercise) can belong to the formula beside it, and so can words that share their row with
    /// other pieces (a derivation's `Our Solution`) or conclude it from beneath (`Infinite
    /// solutions Our Solution`, page 149).
    private static func isTextNeighbour(_ line: TextLine, above: Bool, in lines: [TextLine], body: CGFloat) -> Bool {
        let edges = CharacterSet(charactersIn: "\"'“”‘’.,;:!?")
        let tokens = line.text.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: edges) }
        // Words of two or more letters: a single letter is a variable (`y Use two variables, x
        // and y` opens a page-359 derivation row).
        if above, wordShare(line.text).words >= 1,
           tokens.allSatisfy({ $0.count >= 2 && $0.unicodeScalars.allSatisfy(CharacterSet.letters.contains) }),
           !lines.contains(where: { $0 != line && sameRow($0.rect, line.rect) }) {
            return true
        }
        return isSentenceRow(line, in: lines) || isProseRow(line, in: lines, body: body)
    }

    /// A word whose equals signs belong to a web address's query string, not an equation: an
    /// address with a query (`…/print.php3?ReportID=145).`, `www.nftc.org/…?Mode=View&…`), or
    /// the wrapped rest of one, two or more `name=value` pairs joined by `&`
    /// (`item_id=1645&content_type_id=7).`). 9/11 notes pages 571 and 581–583 lost the lines
    /// around such addresses to formula crops (#80).
    static func isURLQuery(_ word: Substring) -> Bool {
        if let query = word.firstIndex(of: "?"), let equals = word.firstIndex(of: "="), query < equals,
           word[..<query].contains(where: { $0 == "/" || $0 == "." }) { return true }
        return word.range(of: #"(?:^|[(?&])[A-Za-z_][A-Za-z0-9_.-]*=[^\s&=]*(?:&[A-Za-z_][A-Za-z0-9_.-]*=[^\s&=]*)+[).,;]*$"#,
                          options: .regularExpression) != nil
    }

    /// A title that spells out a mnemonic's letter, set wholly in bold: one capital letter, an
    /// equals sign and a capitalised word of three or more letters, then words of two or more (the FAA's
    /// PAVE checklist titles `A = Aircraft` and `V = EnVironment`, pages 47–48). It carries no
    /// term, number or operator besides the sign, so it is not a displayed equation; as a formula
    /// seed its crop took the title and the italic title beneath it out of the text (#97).
    static func isLetterMnemonic(_ line: TextLine) -> Bool {
        LabelStyle(line, body: line.fontSize).bold
            && line.text.range(of: #"^\p{Lu} = \p{Lu}\p{L}{2,}(?: [\p{L}()]{2,}){0,6}$"#, options: .regularExpression) != nil
    }

    /// A sentence set on its own row beside a formula: it opens with a capital, closes with a full
    /// stop, carries function words and no term or operator (FAA page 298's `The height of the
    /// cloud base is 3,180 feet AGL.` beneath the worked example, #112). A derivation's
    /// conclusion carries its terms (`x = 3.`) or reads as a label (`Infinite solutions`).
    private static func isSentenceRow(_ line: TextLine, in lines: [TextLine]) -> Bool {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        return text.first?.isUppercase == true && text.last == "." && wordShare(text).words >= 4 && isWordy(text)
            && readsAsSentence(text) && text.rangeOfCharacter(from: rowMathSymbols) == nil && !text.contains("=")
            && !lines.contains(where: { $0 != line && sameRow($0.rect, line.rect) })
    }

    /// A formula candidate that is the wrapped end of the sentence on the line above it: that line
    /// reads as words and leaves its sentence open, and this one continues in lower case from its
    /// left edge or hanging indent (FAA page 251's `2. Enter the moment for each item listed.
    /// Remember` / `“weight x arm = moment.”`, #112). A display starts its own row with a term.
    private static func continuesSentenceAbove(_ line: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        guard !lines.contains(where: { $0 != line && sameRow($0.rect, line.rect) }),
              !line.rect.isEmpty, line.rect.height < line.fontSize * 2, isWordy(line.text) else { return false }
        let quotes = CharacterSet(charactersIn: "\"'“‘(")
        guard let opening = line.text.split(whereSeparator: \.isWhitespace).first.map({ String($0).trimmingCharacters(in: quotes) }),
              opening.count >= 3, opening.first?.isLowercase == true,
              opening.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else { return false }
        let above = lines.filter { other in
            other != line && other.rect.minY > line.rect.midY && other.rect.minY - line.rect.maxY <= body * 0.9
                && min(other.rect.maxX, line.rect.maxX) > max(other.rect.minX, line.rect.minX)
        }
        guard above.count == 1, let previous = above.first, !previous.monospaced,
              abs(previous.fontSize - line.fontSize) <= line.fontSize * 0.1,
              wordShare(previous.text).words >= 4, isWordy(previous.text),
              let ending = previous.text.trimmingCharacters(in: .whitespaces).last, !".!?:;".contains(ending),
              previous.text.rangeOfCharacter(from: rowMathSymbols) == nil, !previous.text.contains("=") else { return false }
        return line.rect.minX >= previous.rect.minX - body * 0.5 && line.rect.minX <= previous.rect.minX + body * 2.5
            && line.rect.maxX <= previous.rect.maxX + body * 0.5
    }

    /// Art set behind a title, found from the title lines a painted cluster touches (#111, #112).
    /// `nil`: not title art. `.some(nil)`: decoration to drop. `.some(rect)`: the art's part beside
    /// the title, which stays a crop.
    ///
    /// - A drop shadow is an offset, blurred copy of its title: the titles' rectangles cover at
    ///   least 60% of it and it reaches no further than one type size beyond them (FAA's appendix
    ///   and chapter-opener titles, pages 3, 453, 461, 473 and 477; PDFKit merges page 473's title
    ///   with `Appendix C` into one line whose rectangle starts at x −18.7, 27 pt short of the
    ///   shadow's right end). It is decoration; the title reflows as a heading,
    ///   and a body line its blur touches (page 461) reflows too.
    /// - A band is a strip no taller than twice its one title, set level with the title and
    ///   touching no other text (DGA page 9's section bands under `Young Adulthood`, `Pregnant
    ///   Women` and `Lactating Women`). A band the title overhangs keeps its part beyond the title,
    ///   as the band beside `Older Adults` (0.9 pt clear of its title) always did; a band that holds
    ///   the whole title is the title's background and is dropped. With `stacked`, the per-paint
    ///   judgement in `TintDetector.withoutTitleBackdrops` (#117), the title may also be one title
    ///   wrapped onto stacked lines of one size from one left edge, measured together (DGA page 5's
    ///   `Limit Highly Processed Foods, Added Sugars,` / `& Refined Carbohydrates`); a cluster's two
    ///   title lines (the Fed's boxed figure title bars) are still not a band.
    ///
    /// Title type is at least 1.25 body (the heading threshold of `blocks`) and carries a word.
    /// Paint order is not recorded in the page model, so the evidence is the art's shape: a figure
    /// behind a title extends well beyond it or holds other text.
    static func titleArt(_ rect: CGRect, in lines: [TextLine], body: CGFloat, stacked allowStacked: Bool = false) -> CGRect?? {
        guard !isThinRule(rect), rect.width > 0, rect.height > 0 else { return nil }
        let touching = lines.filter { $0.rect.intersects(rect) }
        let titles = touching.filter { line in
            !line.monospaced && line.fontSize >= body * 1.25
                && line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
        }
        guard !titles.isEmpty else { return nil }
        let others = touching.filter { !titles.contains($0) }
        let size = titles.map(\.fontSize).max() ?? body
        let hull = union(titles.map(\.rect))
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        // Stacked title lines' rectangles overlap; count their shared part once.
        var covered = titles.reduce(CGFloat(0)) { $0 + area($1.rect.intersection(rect)) }
        for (offset, a) in titles.enumerated() {
            for b in titles.dropFirst(offset + 1) { covered -= area(a.rect.intersection(b.rect).intersection(rect)) }
        }
        // Another line may only graze the shadow's blur (page 461's first body line, 2 pt of 11.5).
        let grazed = others.allSatisfy { other in
            min(other.rect.maxY, rect.maxY) - max(other.rect.minY, rect.minY) <= other.rect.height * 0.25
        }
        if grazed, hull.insetBy(dx: -size, dy: -size).contains(rect), covered >= area(rect) * 0.6 {
            return .some(nil)
        }
        let stacked = titles.sorted { $0.rect.minY > $1.rect.minY }
        let oneTitle = zip(stacked, stacked.dropFirst()).allSatisfy { upper, lower in
            abs(upper.fontSize - lower.fontSize) <= upper.fontSize * 0.1 && abs(upper.rect.minX - lower.rect.minX) <= body
                && lower.rect.maxY >= upper.rect.minY - upper.fontSize * 0.5
        }
        guard oneTitle, allowStacked || titles.count == 1, others.isEmpty,
              rect.height <= hull.height * 2, rect.width >= rect.height * 3,
              rect.minY <= hull.minY + 2, rect.maxY >= hull.maxY - 2 else { return nil }
        let gap: CGFloat = 0.5
        var kept: CGRect?
        if hull.minX < rect.minX, hull.maxX < rect.maxX {
            kept = CGRect(x: hull.maxX + gap, y: rect.minY, width: rect.maxX - hull.maxX - gap, height: rect.height)
        } else if hull.maxX > rect.maxX, hull.minX > rect.minX {
            kept = CGRect(x: rect.minX, y: rect.minY, width: hull.minX - gap - rect.minX, height: rect.height)
        }
        guard let band = kept, band.width >= rect.height else { return .some(nil) }
        return .some(band)
    }

    /// Expand crops to whole intersecting text lines so a label cannot be cut in half.
    static func graphicsWithLabels(_ page: PageContent) -> [CGRect] {
        classifiedGraphics(page).map(\.rect)
    }

    /// What one crop seed says about the crop that holds it (#187).
    private enum SeedEvidence {
        /// A displayed formula line, a fraction, or a rule that keeps a mathematical line.
        case formula
        case table
        case listing
        /// Painted art at least a body size wide and tall: a drawing, a chart, a picture.
        case art
        /// A painted mark smaller than the type (a fraction bar under one digit, a radical sign,
        /// a bullet): it says nothing about the crop on its own, so the text beside it decides.
        case mark
    }

    /// The same crops, each with what its own seeds say it holds (#187). Alternative text has to
    /// name the content, and the only evidence the converter has about a crop is which detector
    /// seeded it: a displayed formula or a fraction, a table region the layout could not reflow,
    /// an algorithm listing between its rules, or drawn and placed art. A crop's kind is the
    /// reduction of the evidence of every seed the finished crop holds, in that precedence: a
    /// table region's claim is the strongest evidence on the page, a listing's rules next, then
    /// art, since a drawing routinely swallows one of its own labels. A crop with none of those is
    /// read from the lines it holds: an equation when they read as mathematics, text when most of
    /// them read as words (a formula seed can take a prose line with it, and an underlined link
    /// fragment in a reference list reads as a mathematical line to the formula seed), and art when
    /// it holds only marks and no text.
    static func classifiedGraphics(_ page: PageContent) -> [(rect: CGRect, kind: PreservedImageKind)] {
        let body = max(4, bodySize(page.lines))
        // Displayed formulas have spatial meaning (superscripts, fractions, aligned terms)
        // that line concatenation cannot reproduce. Preserve recognizable formulas as crops.
        // A prose row with inline mathematics is not a displayed formula, and a formula's
        // margin (raised and lowered terms, radical bars) stops short of neighbouring text.
        // A contents entry is no display either: FAA page 6 lists the PAVE checklist's `A =
        // Aircraft` and `V = EnVironment` in plain type with their leaders, and their crop took
        // the column's last four entries out of the contents (#102).
        let formulas = page.lines.filter { line in
            guard !line.monospaced, line.text.count < 160, !isContentsEntry(line.text) else { return false }
            let symbols = line.text.rangeOfCharacter(from: mathSymbols) != nil
            let words = line.text.split(whereSeparator: \.isWhitespace)
            let equation = words.count <= 12 && words.contains { $0.contains("=") && !isURLQuery($0) }
                && !isLetterMnemonic(line)
            return (symbols || equation) && !isProseRow(line, in: page.lines, body: body)
                && !continuesSentenceAbove(line, in: page.lines, body: body)
        }.map { line -> CGRect in
            var seed = line.rect.insetBy(dx: -4, dy: -8)
            for other in page.lines where other != line && seed.intersects(other.rect)
                && !sameRow(other.rect, line.rect)
                && isTextNeighbour(other, above: other.rect.midY > line.rect.midY, in: page.lines, body: body) {
                if other.rect.midY > line.rect.midY {
                    let top = max(line.rect.maxY, min(seed.maxY, other.rect.minY - 0.5))
                    seed.size.height = top - seed.minY
                } else {
                    let bottom = min(line.rect.minY, max(seed.minY, other.rect.maxY + 0.5))
                    seed.size.height = seed.maxY - bottom
                    seed.origin.y = bottom
                }
            }
            return seed
        }
        // A rule underlining one text line is that text's decoration, not a figure. Rows of
        // column-header underlines are table evidence instead (#36).
        let tables = TableRegionDetector.underlinedColumnRegions(in: page)
        let floats = algorithmFloats(in: page)
        func owner(of rect: CGRect) -> TextLine? {
            page.lines.first { line in
                rect.minX >= line.rect.minX - body && rect.maxX <= line.rect.maxX + body
                    && rect.midY >= line.rect.minY - 3 && rect.midY <= line.rect.maxY
            }
        }
        let numericTables = TableRegionDetector.regions(in: page)
        let fractions = FractionRegionDetector.regions(in: page)
        let otherSeeds = formulas + numericTables + fractions + tables + floats.regions
        // What each seed says the crop holds (#187). `drawn` adds the painted seeds' own below.
        var evidence: [(CGRect, SeedEvidence)] =
            formulas.map { ($0, .formula) } + fractions.map { ($0, .mark) }
            + numericTables.map { ($0, .table) } + tables.map { ($0, .table) }
            + floats.regions.map { ($0, .listing) }
        // A rule that keeps a mathematical line is that display's own bar, not a drawing, and a
        // mark smaller than the type is no drawing either; everything else painted is art.
        func painted(_ rect: CGRect) -> SeedEvidence { rect.width < body || rect.height < body ? .mark : .art }
        let drawn = page.graphics.compactMap { rect -> (CGRect, SeedEvidence)? in
            // A radical's bar inside a prose row decorates that row (`is written as √25.`, `if
            // we found √8 on`): the tall rectangle PDFKit gives the radical piece would otherwise
            // read as a fraction's terms around it, and a bar over one or two digits is shorter
            // than a rule (#58). Only a row that carries the radical sign qualifies; any other
            // small mark touching prose keeps its line.
            if rect.height <= 6, rect.width > rect.height, let owner = owner(of: rect),
               rowPieces(owner, in: page.lines, body: body).contains(where: { $0.text.rangeOfCharacter(from: mathSymbols) != nil }),
               isProseRow(owner, in: page.lines, body: body) {
                return nil
            }
            // What placed the graphic may already know what it holds (#187).
            switch page.graphicKinds[rect] {
            case .equation: return (rect, .formula)
            case .table: return (rect, .table)
            default: break
            }
            if let art = titleArt(rect, in: page.lines, body: body) { return art.map { ($0, painted($0)) } }
            guard isThinRule(rect) else { return (rect, painted(rect)) }
            if tables.contains(where: { $0.contains(rect) }) || floats.decorations.contains(rect) { return nil }
            // A fraction bar keeps the terms it touches, as any intersecting graphic does. Its
            // test reads only a short letter-free line over it, which NOAA's underlined DOI
            // fragments also satisfy, so it is a mark and the crop's text decides (#187).
            if isFractionBar(rect, in: page.lines, body: body) {
                return (page.lines.filter { rect.intersects($0.rect) }.reduce(rect) { $0.union($1.rect) }, .mark)
            }
            // A rule inside one line's box belongs to that line: a radical's vinculum or an
            // exercise bar keeps its short mathematical line; an underline beneath prose is
            // decoration. A rule outside every line stays an isolated graphic unless it is a
            // page's decoration rule (#66).
            guard let owner = owner(of: rect) else {
                let isolated = !page.graphics.contains { $0 != rect && $0.insetBy(dx: -4, dy: -4).intersects(rect) }
                    && !otherSeeds.contains { $0.insetBy(dx: -4, dy: -4).intersects(rect) }
                // A short rule is a mark the crop's text decides (the bar Wallace sets under
                // `+ 7/2 + 7/2` in a worked step, page 43, five bodies long); a long one may rule
                // a table or frame a drawing, and stays art as before.
                return isolated && isDecorationRule(rect, in: page.lines, bounds: page.bounds, body: body)
                    ? nil : (rect, rect.width <= body * 6 ? .mark : .art)
            }
            // Such a line is only letter-free: an underlined link fragment in a reference list
            // (`1029/2019GL082077`) qualifies as readily as a radical's vinculum, so the rule
            // is a mark whose crop the text inside decides.
            let mathematical = owner.text.count <= 40 && !owner.monospaced
                && owner.text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil
            return mathematical ? (rect.union(owner.rect), .mark) : nil
        }
        let graphics = drawn.map(\.0)
        evidence += drawn
        let seeds = graphics + otherSeeds
        // Running text keeps crops apart and stops them growing over it (#158).
        let text = TintDetector.blockText(page.lines)
        var regions = TintDetector.clustersKeepingText(clusters(seeds, distance: 3), seeds: seeds, lines: page.lines)
            .map { Region(seed: $0, bounds: $0) }
        var previous: [CGRect] = []
        while regions.map(\.bounds) != previous {
            previous = regions.map(\.bounds)
            regions = regions.compactMap { region in
                expanded(region, page: page, body: body, text: text)
                    .map { Region(seed: region.seed, bounds: $0) }
            }
            // A merged bounding rectangle can newly intersect a label that neither component
            // touched. Expand again before rasterizing, or its text is removed from prose while
            // the image clips part of it (for example, a raised exponent beside a fraction).
            regions = merged(regions, text: text)
        }
        // A seed is the crop's own when the crop holds its centre: a formula seed reaches eight
        // points past its line, so the line beside a crop would otherwise lend it its evidence.
        return regions.map { region in
            let held = evidence.filter { region.bounds.contains(CGPoint(x: $0.0.midX, y: $0.0.midY)) }.map(\.1)
            return (region.bounds, kind(of: region.bounds, evidence: held, in: page))
        }
    }

    /// A crop's kind from the evidence of the seeds it holds (`classifiedGraphics`).
    private static func kind(of crop: CGRect, evidence: [SeedEvidence], in page: PageContent) -> PreservedImageKind {
        if evidence.contains(.table) { return .table }
        if evidence.contains(.listing) { return .listing }
        if evidence.contains(.art) { return .artwork }
        let held = page.lines.filter { crop.intersects($0.rect) }
        guard !held.isEmpty else { return .artwork }
        // A displayed formula line makes the crop mathematics, whatever annotates it: Wallace's
        // worked examples set `Subtract 7 from both sides` beside each step, and its rules are
        // stated in words before the formula (`Zero Power Rule of Exponents: a0 = 1`).
        if evidence.contains(.formula) { return .equation }
        // Marks alone decide nothing, so the lines do. A line of prose reads as words over at
        // least eight tokens: a word problem's line can, a fraction's `35 Our Solution` cannot. A
        // crop at least half of whose lines are prose holds text: a word problem whose inline
        // mixed number seeded a crop (Wallace page 369), or a reference entry over the bare DOI
        // fragment whose underline reads as a fraction bar (NOAA's reference lists).
        let prose = held.filter { isWordy($0.text) && $0.text.split(whereSeparator: \.isWhitespace).count >= 8 }.count
        return prose * 2 >= held.count ? .text : .equation
    }

    struct Element {
        var rect: CGRect
        var line: TextLine?
        var image: String?
        /// Index into the page's shaded text tables.
        var table: Int?
        /// Marks the edge of a tinted box: paragraphs never join across it.
        var boundary = false
        /// A tinted box read as one float: its content is ordered on its own, and the box
        /// follows the lines beside it instead of interleaving with them.
        var box: [Element]?
    }

    // Recursive whitespace cuts: columns first, except that a single-line heading band above
    // them is cut off first (`headingBand`); a spanning heading is separated by a horizontal cut
    // before retrying columns; a gutter hidden by overhanging figures is measured over text last,
    // and content above or below the columns that crosses their gutter — a folio, a running foot's
    // rule, a spanning figure — is set aside last of all (`marginBands`, #153).
    // No page-wide y/x sort of interleaved column text.
    static func ordered(_ elements: [Element], bodySize: CGFloat, depth: Int = 0) -> [Element] {
        guard elements.count > 1, depth < 32 else { return elements }
        if let rotated = rotatedLineOrder(elements) { return rotated }
        if let entries = namedEntries(elements) { return entries }
        func gap(horizontal: Bool, measuring measured: [Element], in part: [Element]? = nil) -> CGFloat? {
            whitespaceCut(horizontal: horizontal, measuring: measured, in: part ?? elements, bodySize: bodySize)
        }
        if let x = gap(horizontal: true, measuring: elements) {
            if let y = headingBand(elements, gutter: x, bodySize: bodySize) {
                return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                    + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
            }
            if let y = stackedBlocks(elements, gutter: x, bodySize: bodySize) {
                return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                    + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
            }
            let columns = ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX > x }, bodySize: bodySize, depth: depth + 1)
            // Cells numbered along their rows read in number order, not down each column (#78).
            if let labels = rowMajorLabels(elements, bodySize: bodySize) {
                return inNumberOrder(columns, labels: labels)
            }
            return columns
        }
        if let y = gap(horizontal: false, measuring: elements) {
            // Two prose columns can break a paragraph at the same height, and when a figure across
            // their full measure closes the gutter, that aligned paragraph space is the widest
            // whitespace: FAA page 439's drug table and page 392's time-zone map read left, right,
            // left, right (#86). A band no wider than paragraph spacing gives way to the figure
            // partition (`spanningFigures`); Our Flag's state grids band their rows with 62 pt.
            let width = horizontalBands(elements).first { abs($0.y - y) < 0.01 }?.width ?? .greatestFiniteMagnitude
            if width <= bodySize * 1.5, let parts = spanningFigures(elements, bodySize: bodySize, gutter: {
                gap(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0)
            }) {
                return ordered(parts.head, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.columns, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.foot, bodySize: bodySize, depth: depth + 1)
            }
            // A heading left alone at the foot of the part above heads the part below (#103).
            if let moved = trailingHeading(elements, cut: y, bodySize: bodySize) {
                return ordered(elements.filter { $0.rect.minY > moved }, bodySize: bodySize, depth: depth + 1)
                    + ordered(elements.filter { $0.rect.maxY < moved }, bodySize: bodySize, depth: depth + 1)
            }
            // Two prose columns that both break a paragraph at the band read down each column
            // rather than across it (#153, DASC page 9).
            if width <= bodySize * 1.5, let parts = marginBands(elements, bodySize: bodySize, across: y, gutter: {
                gap(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0)
            }) {
                return ordered(parts.head, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.columns.filter { $0.rect.maxX < parts.gutter }, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.columns.filter { $0.rect.minX > parts.gutter }, bodySize: bodySize, depth: depth + 1)
                    + ordered(parts.foot, bodySize: bodySize, depth: depth + 1)
            }
            return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
        }
        // A preserved figure or table is set to its column's measure, but its rectangle can
        // overhang the prose by a few points and swallow the gutter: the FAA's pages 165, 199
        // and 262 keep 11.6–11.9 pt of whitespace between their text columns — the same measure
        // the page-91 and -511 columns are cut on — while figures at the columns' heads narrow
        // it to 6.5–7.4 pt, under the 0.75-body test, so those pages find no cut at all and
        // fall through to the reading-order sort, which interleaves them line by line (#56).
        // Measured over the text lines alone the gutter is there; it is taken only once neither
        // whitespace cut has found anything, so a page whose rows are banded horizontally — Our
        // Flag's four-to-a-page state grids, whose folio sits in the gutter 3.6 pt from the
        // flags while 62 pt of whitespace separates the rows — is still cut into its rows first.
        // The cut is kept only when every figure falls wholly on one side of it, so a figure
        // heading a column joins that column instead of bridging both.
        if let x = gap(horizontal: true, measuring: elements.filter { $0.line != nil }) {
            return ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX > x }, bodySize: bodySize, depth: depth + 1)
        }
        // A figure set across the full measure above or below two columns, its rectangle within
        // a few points of the columns' first or last lines (#86, `spanningFigures`).
        if let parts = spanningFigures(elements, bodySize: bodySize, gutter: {
            gap(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0)
        }) {
            return ordered(parts.head, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.columns, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.foot, bodySize: bodySize, depth: depth + 1)
        }
        // A heading set in a row with a figure divides the sections above and below it (#103).
        if let parts = headingRow(elements, bodySize: bodySize) {
            return ordered(parts.above, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.row, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.below, bodySize: bodySize, depth: depth + 1)
        }
        if let x = bulletColumns(elements, bodySize: bodySize) {
            return ordered(elements.filter { $0.rect.minX < x && $0.rect.maxX > x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.maxX <= x }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.minX >= x }, bodySize: bodySize, depth: depth + 1)
        }
        // Content set wholly above or below two prose columns, across their gutter (#153).
        if let parts = marginBands(elements, bodySize: bodySize, gutter: {
            gap(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0)
        }) {
            return ordered(parts.head, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.columns.filter { $0.rect.maxX < parts.gutter }, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.columns.filter { $0.rect.minX > parts.gutter }, bodySize: bodySize, depth: depth + 1)
                + ordered(parts.foot, bodySize: bodySize, depth: depth + 1)
        }
        // One numbered key stacked under another, with no band wide enough to cut between them
        // (#178). The numbering says where the upper key ends; each key is then cut on its own.
        if let y = numberedKeyBand(elements, bodySize: bodySize) {
            return ordered(elements.filter { $0.rect.minY > y }, bodySize: bodySize, depth: depth + 1)
                + ordered(elements.filter { $0.rect.maxY < y }, bodySize: bodySize, depth: depth + 1)
        }
        // Blocks set beside each other at different leadings, with no whitespace between them
        // (the CDC comic's speech balloons beside its caption boxes, #122), read block by block.
        if let blocks = interleavedBlocks(elements, bodySize: bodySize) {
            return blocks.flatMap { sortedByRows($0, bodySize: bodySize) }
        }
        return noteColumnsInNumberOrder(sortedByRows(elements, bodySize: bodySize), bodySize: bodySize)
    }

    /// The widest whitespace band in one direction, measured over `measured`. The cut is
    /// kept only when every element of `region` falls wholly on one side of it: ordering
    /// drops an element that straddles its cut, so a subset may not choose a line that the
    /// elements it leaves out would cross. Where the band's middle is straddled, the cut may
    /// move within the band to any line no element crosses (#153).
    static func whitespaceCut(horizontal: Bool, measuring measured: [Element], in region: [Element],
                              bodySize: CGFloat) -> CGFloat? {
        guard measured.count > 1 else { return nil }
        let intervals = measured.map { horizontal ? ($0.rect.minX, $0.rect.maxX) : ($0.rect.minY, $0.rect.maxY) }
            .sorted { $0.0 < $1.0 }
        var end = intervals[0].1
        var gaps: [(width: CGFloat, low: CGFloat, high: CGFloat)] = []
        for interval in intervals.dropFirst() {
            let width = interval.0 - end
            if width > bodySize * (horizontal ? 0.75 : 1.1) {
                let middle = (end + interval.0) / 2
                // A narrow gutter is evidence for prose columns only when both sides
                // contain substantial text lines. Short labels and numeric answer cells
                // need row associations; the whitespace alone must not separate them. A figure
                // or table preserved at a column's measure counts beside at least one such line:
                // DASC page 10 sets Table III under its caption beside the references (#153), while
                // Wallace's tables with notes beside them hold no line on the tables' side.
                let left = region.filter { horizontal ? $0.rect.maxX < middle : false }
                let right = region.filter { horizontal ? $0.rect.minX > middle : false }
                let proseColumns = !horizontal || width > bodySize * 1.5 || [left, right].allSatisfy { column in
                    let wide = column.filter { $0.rect.width >= bodySize * 12 }
                    let lines = wide.filter { $0.line != nil }.count
                    return lines >= 1 && lines + wide.filter { $0.image != nil || $0.table != nil }.count >= 2
                }
                if proseColumns { gaps.append((width, end, interval.0)) }
            }
            end = max(end, interval.1)
        }
        func low(_ element: Element) -> CGFloat { horizontal ? element.rect.minX : element.rect.minY }
        func high(_ element: Element) -> CGFloat { horizontal ? element.rect.maxX : element.rect.maxY }
        func clear(_ cut: CGFloat) -> Bool { region.allSatisfy { high($0) < cut || low($0) > cut } }
        // The widest band first. Measured over a subset, a figure can cross it: where prose runs
        // beside prose, the cut moves within the band to a line nothing crosses (DASC page 4's
        // figure overhangs the gutter by 4 pt; USDA page 11's by 6); otherwise it falls to the next
        // widest band (a figure over the first two of three columns leaves the second gutter,
        // USDA page 15). A formula crop beside its note is not prose beside prose (Wallace).
        for gap in gaps.sorted(by: { $0.width > $1.width }) {
            let middle = (gap.low + gap.high) / 2
            if clear(middle) { return middle }
            let edges = ([gap.low, gap.high] + region.flatMap { [low($0), high($0)] }.filter { $0 > gap.low && $0 < gap.high })
                .sorted()
            if let cut = zip(edges, edges.dropFirst()).filter({ $1 > $0 }).map({ ($0 + $1) / 2 })
                .sorted(by: { abs($0 - middle) < abs($1 - middle) })
                .first(where: { horizontal && clear($0) && proseBesideProse(region, gutter: $0, bodySize: bodySize, minimum: 2) }) {
                return cut
            }
        }
        return nil
    }

    /// Whether a part holds prose on both sides of a gutter, running beside each other: at least
    /// `minimum` text lines 12 bodies wide on each side. `prose: false` asks for the width alone —
    /// a column's contents page of dot leaders is column content, though it is not prose. Otherwise
    /// the wide lines must carry at least two thirds of that side's
    /// characters, four fifths of them letters or spaces. A table's label column, a contents page's
    /// entry numbers or a graph's axis labels set most of their text in short lines, however wide a
    /// merged row may be, and a table half's rows are figures rather than words (the Blue Book's
    /// scanned statistical tables, whose halves read row by row). Both columns are also set in the
    /// page's body type (the wide lines' median size within a quarter of it), so a scan whose lines
    /// merge a margin rule into the text beside it is no column of prose (the Blue Book's contents).
    static func proseBesideProse(_ part: [Element], gutter: CGFloat, bodySize: CGFloat, minimum: Int,
                                 prose: Bool = true) -> Bool {
        guard minimum > 0 else { return false }
        var extents: [CGRect] = []
        for side in [part.filter { $0.rect.maxX < gutter }, part.filter { $0.rect.minX > gutter }] {
            let lines = side.compactMap { element in
                element.line.map { (rect: element.rect, text: $0.text, size: $0.fontSize) }
            }
            let wide = lines.filter { $0.rect.width >= bodySize * 12 }
            let letters = wide.reduce(0) { $0 + withoutLeaders($1.text).filter { $0.isLetter || $0 == " " }.count }
            let characters = wide.reduce(0) { $0 + withoutLeaders($1.text).count }
            let sizes = wide.map(\.size).sorted()
            guard wide.count >= minimum else { return false }
            if prose {
                guard letters * 5 >= characters * 4,
                      characters * 3 >= lines.reduce(0, { $0 + $1.text.count }) * 2,
                      let median = sizes.isEmpty ? nil : sizes[sizes.count / 2],
                      median >= bodySize * 0.8, median <= bodySize * 1.25 else { return false }
            }
            extents.append(union(wide.map(\.rect)))
        }
        return min(extents[0].maxY, extents[1].maxY) > max(extents[0].minY, extents[1].minY)
    }

    /// A line's text without its leaders: a run of three or more of one character that is neither a
    /// letter nor a digit (a contents entry's dots), which carries no words but is column content.
    static func withoutLeaders(_ text: String) -> String {
        var result = ""
        var run: [Character] = []
        func flush() {
            if run.count < 3 || run[0].isLetter || run[0].isNumber { result += run }
            run = []
        }
        for character in text {
            if character == run.last { run.append(character) } else { flush(); run = [character] }
        }
        flush()
        return result
    }

    /// Whether a horizontal band falls where both columns break and each column runs on beneath it.
    /// On each side of the gutter the whitespace around the band reaches no more than 4.5 bodies,
    /// so the band is the paragraph space the two columns happen to share rather than the space
    /// under a section that ends higher in one column (DGA page 3 sets its `Consume Dairy` heading
    /// 52 pt below the right column's last bullet); and the first line of the column's measure
    /// beneath the band is body text near the column's edge (within three bodies, for an indented
    /// or centred opening), not a heading in display type that starts a section there. The Word paper's abstract and DASC
    /// page 9's appendices run on in both columns; a section heading under one column does not.
    static func breaksBothColumns(_ columns: [Element], gutter: CGFloat, band: CGFloat, bodySize: CGFloat) -> Bool {
        [columns.filter { $0.rect.maxX < gutter }, columns.filter { $0.rect.minX > gutter }].allSatisfy { side in
            guard let above = side.filter({ $0.rect.minY > band }).map(\.rect.minY).min(),
                  let below = side.filter({ $0.rect.maxY < band }).map(\.rect.maxY).max(),
                  above - below <= bodySize * 4.5 else { return false }
            let wide = side.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }
            guard let edge = wide.filter({ $0.rect.minY > band }).map(\.rect.minX).min(),
                  let opening = wide.filter({ $0.rect.maxY < band }).max(by: { $0.rect.maxY < $1.rect.maxY })
            else { return false }
            return !isHeadingType(opening, bodySize: bodySize) && abs(opening.rect.minX - edge) <= bodySize * 3
        }
    }

    /// Two prose columns with content set wholly above or below them that crosses their gutter,
    /// separated from them only by whitespace narrower than the horizontal cut's 1.1 body. A folio
    /// centred in the gutter under the columns' last lines (the Word paper's 6 pt), a running foot's
    /// rule across the page (the USDA magazine), or a figure over both columns with its caption
    /// leaves no cut at all, and the row sort interleaves the columns line by line (#153).
    ///
    /// Tries the region's whitespace bands, nearest the top and bottom first: the part above a
    /// head band and the part below a foot band are set aside, and what remains must be cut by
    /// its text gutter into prose columns running beside each other (two lines at least 12 bodies
    /// wide on each side) while the region as a whole is not. Set-aside content crosses that gutter
    /// and holds no prose beside prose. Returns the head, the columns and the foot; nil otherwise.
    ///
    /// Given `across`, a whitespace band narrower than paragraph spacing that the region would
    /// otherwise be cut at, the columns must also hold prose beside prose both above and below it:
    /// the two columns break a paragraph at the same height (DASC page 9, the Word paper's
    /// abstract), and they read down each column rather than across the band. The region itself
    /// may then be the columns.
    static func marginBands(_ elements: [Element], bodySize: CGFloat, across band: CGFloat? = nil,
                            gutter: ([Element]) -> CGFloat?)
        -> (head: [Element], columns: [Element], gutter: CGFloat, foot: [Element])? {
        let bands = horizontalBands(elements).map(\.y).filter { $0 != band }
        guard !bands.isEmpty || band != nil else { return nil }
        let limit = 8
        let heads = [CGFloat.greatestFiniteMagnitude] + bands.prefix(limit)
        let feet = [-CGFloat.greatestFiniteMagnitude] + bands.reversed().prefix(limit)
        for foot in feet {
            for head in heads where head > foot && (band != nil || head != heads[0] || foot != feet[0]) {
                let columns = elements.filter { $0.rect.maxY < head && $0.rect.minY > foot }
                guard let x = gutter(columns), proseBesideProse(columns, gutter: x, bodySize: bodySize, minimum: 2)
                else { continue }
                if let band {
                    guard band < head, band > foot,
                          proseBesideProse(columns.filter { $0.rect.minY > band }, gutter: x, bodySize: bodySize,
                                           minimum: 1, prose: false),
                          proseBesideProse(columns.filter { $0.rect.maxY < band }, gutter: x, bodySize: bodySize,
                                           minimum: 1, prose: false),
                          breaksBothColumns(columns, gutter: x, band: band, bodySize: bodySize)
                    else { continue }
                }
                let above = elements.filter { $0.rect.minY > head }, below = elements.filter { $0.rect.maxY < foot }
                let outside = above + below
                guard outside.isEmpty && band != nil || outside.contains(where: { $0.rect.minX < x && $0.rect.maxX > x }),
                      !proseBesideProse(above, gutter: x, bodySize: bodySize, minimum: 1, prose: false),
                      !proseBesideProse(below, gutter: x, bodySize: bodySize, minimum: 1, prose: false) else { continue }
                return (above, columns, x, below)
            }
        }
        return nil
    }

    /// The printed number of a note line: its first run is raised and holds one to three digits
    /// (with whitespace or control characters PDFKit reports beside them, DGA's `1 \u{07}`), and
    /// the note's text follows in the same line.
    static func raisedNoteNumber(_ line: TextLine) -> Int? { raisedNoteNumber(line.content) }
    static func raisedNoteNumber(_ text: InlineText) -> Int? {
        guard case let .text(value, style)? = text.elements.first, style.contains(.superscript),
              text.elements.count > 1 else { return nil }
        let printed = value.trimmingCharacters(in: .whitespaces.union(.controlCharacters))
        guard (1...3).contains(printed.count), printed.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(printed), number > 0 else { return nil }
        return number
    }

    /// Notes set side by side in columns and numbered down each column, in a region no whitespace
    /// cut divides, read in number order (#141). DGA page 2 sets notes 1 and 2 over each other at
    /// the left and 3 and 4 at the right, 4 pt below a rule under the signatures: the page has no
    /// band of whitespace to cut, so the row sort read 1, 3, 2, 4. The numbers decide, as for
    /// `rowMajorLabels`: a contiguous run of the sorted elements, opening with a raised-number note
    /// line, holding only lines smaller than 0.9 body, in at least two columns whose extents do not
    /// overlap, every line at or right of a marker's left edge, with at least three markers
    /// counting up by one down each column and on from one column to the next, reads column by
    /// column (a note continued at the head of the next column reads after it). Anything else
    /// keeps the row order.
    static func noteColumnsInNumberOrder(_ sorted: [Element], bodySize: CGFloat) -> [Element] {
        guard let start = sorted.firstIndex(where: { $0.line.flatMap(raisedNoteNumber) != nil }) else { return sorted }
        var end = start
        while end < sorted.count, let line = sorted[end].line, line.fontSize <= bodySize * 0.9 {
            end += 1
        }
        let run = Array(sorted[start..<end])
        let markers = run.filter { $0.line.flatMap(raisedNoteNumber) != nil }
        guard markers.count >= 3 else { return sorted }
        // Columns open at the markers' left edges; every line belongs to the nearest edge at or left of it.
        var edges: [CGFloat] = []
        for x in markers.map(\.rect.minX).sorted() where edges.last.map({ x - $0 > bodySize * 1.5 }) ?? true { edges.append(x) }
        // One column already reads down (an early exit).
        guard edges.count >= 2 else { return sorted }
        var columns = Array(repeating: [Element](), count: edges.count)
        for element in run {
            guard let column = edges.lastIndex(where: { element.rect.minX >= $0 - bodySize * 0.5 }) else { return sorted }
            columns[column].append(element)
        }
        let extents = columns.map { union($0.map(\.rect)) }
        guard zip(extents, extents.dropFirst()).allSatisfy({ $0.maxX < $1.minX }) else { return sorted }
        var numbers: [Int] = []
        var reordered: [Element] = []
        for column in columns {
            let down = column.sorted { $0.rect.maxY > $1.rect.maxY }
            numbers += down.compactMap { $0.line.flatMap(raisedNoteNumber) }
            reordered += down
        }
        guard zip(numbers, numbers.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return sorted }
        return Array(sorted[..<start]) + reordered + Array(sorted[end...])
    }

    /// Lines that all read in one rotated direction (`TextLine.readingDirection`, within 20°),
    /// in the order their text advances (#122). Whitespace cuts and the row sort measure upright
    /// geometry: CDC page 17's sideways caption runs down the page, so its lines stack from right
    /// to left, but the row sort read the three narrow rectangles from left to right, last line
    /// first. Each line's centre is projected on the direction a new line advances (the reading
    /// direction turned a quarter clockwise); lines within 0.4 of their thickness of each other
    /// share a line position and read along the text. Nil for any other region, including one
    /// that mixes rotated and upright text.
    static func rotatedLineOrder(_ elements: [Element]) -> [Element]? {
        guard let direction = elements.first?.line?.readingDirection,
              elements.allSatisfy({ element in
                  guard let other = element.line?.readingDirection, element.box == nil else { return false }
                  return direction.dx * other.dx + direction.dy * other.dy >= cos(CGFloat.pi / 9)
              }) else { return nil }
        let advance = CGVector(dx: direction.dy, dy: -direction.dx)
        func across(_ element: Element) -> CGFloat { element.rect.midX * advance.dx + element.rect.midY * advance.dy }
        func along(_ element: Element) -> CGFloat {
            [CGPoint(x: element.rect.minX, y: element.rect.minY), CGPoint(x: element.rect.maxX, y: element.rect.maxY),
             CGPoint(x: element.rect.minX, y: element.rect.maxY), CGPoint(x: element.rect.maxX, y: element.rect.minY)]
                .map { $0.x * direction.dx + $0.y * direction.dy }.min()!
        }
        return elements.sorted { a, b in
            let thickness = min(a.rect.width, a.rect.height, b.rect.width, b.rect.height)
            return abs(across(a) - across(b)) > thickness * 0.4 ? across(a) < across(b) : along(a) < along(b)
        }
    }

    /// A list of names, each set beside its description (#161). The 9/11 report's Table of Names
    /// (pages 449–456) sets each name flush left and its description on the same baseline in a
    /// second column 108 points in, and wraps both into a one-em hanging indent (`Khalid Saeed Ahmad` /
    /// `al Zahrani` beside `Saudi; candidate 9/11 hijacker`). The whitespace between the columns cut
    /// the page in two where a long name left 17–35 points of it (pages 450 and 456 read every name,
    /// then every description), and elsewhere the row sort took a wrapped name's second line between
    /// its description's lines (`Mohammed Farrah`, `Somali warlord…`, `Aidid`, `Somalia in…`).
    ///
    /// The layout is read from the region's lines in its most common size: every one stands on the
    /// names' edge (an entry's first line), in the hanging indent a name wraps into, or on the
    /// descriptions' edge or in its indent. At least four names, and two thirds of them, share their
    /// baseline with a line on the descriptions' edge (a line PDFKit read across both columns stands
    /// for its own entry), and the widest name is at most three fifths of the widest description, so
    /// two prose columns (their lines about equally wide) are never read as one. Lines in any other
    /// size (a centred section title, a folio) keep their place between the entries. Each entry
    /// reads its name's lines, then its description's, and a description continued from the
    /// previous page reads first. Nil for any other region.
    static func namedEntries(_ elements: [Element]) -> [Element]? {
        guard elements.count >= 8, elements.allSatisfy({ $0.line != nil && $0.box == nil && !$0.boundary }) else { return nil }
        var tally: [Int: Int] = [:]
        for element in elements { tally[Int((element.line!.fontSize * 2).rounded()), default: 0] += 1 }
        guard let common = tally.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return nil }
        let size = CGFloat(common) / 2
        guard size > 0 else { return nil }
        let indices = Array(elements.indices)
        let entry = indices.filter { index in
            let line = elements[index].line!
            return abs(line.fontSize - size) <= size * 0.05 && !line.monospaced && !isList(line.text)
        }
        guard entry.count >= 8, let edge = entry.map({ elements[$0].rect.minX }).min() else { return nil }
        let names = entry.filter { abs(elements[$0].rect.minX - edge) <= size * 0.5 }
        // A name is words: a column of codes beside their meanings (the Blue Book's scanned code
        // tables, page 303's `0`, `1`… beside `5 second and less`) is a table.
        guard names.allSatisfy({ elements[$0].line!.text.filter(\.isLetter).count >= 2 }) else { return nil }
        func partner(of name: Int) -> Int? {
            let rect = elements[name].rect
            return entry.first { $0 != name && abs(elements[$0].rect.minY - rect.minY) <= size * 0.2
                && elements[$0].rect.minX > rect.maxX + size * 0.5 }
        }
        let partners = names.compactMap { name in partner(of: name).map { (name: name, description: $0) } }
        guard partners.count >= 4, partners.count * 3 >= names.count * 2 else { return nil }
        let starts = partners.map { elements[$0.description].rect.minX }.sorted()
        let column = starts[starts.count / 2]
        guard starts.allSatisfy({ abs($0 - column) <= size * 0.5 }) else { return nil }
        func hangs(_ x: CGFloat, from start: CGFloat) -> Bool { x - start >= size * 0.5 && x - start <= size * 2.5 }
        var descriptions: [Int] = [], wrapped: [Int] = []
        for index in entry where !names.contains(index) {
            let rect = elements[index].rect
            if abs(rect.minX - column) <= size * 0.5 || hangs(rect.minX, from: column) {
                descriptions.append(index)
            } else if hangs(rect.minX, from: edge), rect.maxX < column - size * 0.5 {
                wrapped.append(index)
            } else {
                return nil
            }
        }
        let widestName = partners.map { elements[$0.name].rect.width }.max() ?? 0
        let widestDescription = descriptions.map { elements[$0].rect.width }.max() ?? 0
        guard widestName <= widestDescription * 0.6 else { return nil }
        // Entries and the other lines (`starters`) in reading order; every remaining line belongs
        // to the nearest starter at or above it.
        let others = indices.filter { !entry.contains($0) }
        let starters = (names + others).sorted { elements[$0].rect.maxY > elements[$1].rect.maxY }
        var owned: [Int: [Int]] = [:]
        var leading: [Int] = []
        for index in wrapped + descriptions {
            let rect = elements[index].rect
            let owner = starters.filter { elements[$0].rect.minY >= rect.minY - size * 0.2 }
                .min { elements[$0].rect.minY < elements[$1].rect.minY }
            if let owner { owned[owner, default: []].append(index) } else { leading.append(index) }
        }
        func topDown(_ group: [Int]) -> [Element] {
            group.sorted { elements[$0].rect.maxY > elements[$1].rect.maxY }.map { elements[$0] }
        }
        var result = topDown(leading)
        for starter in starters {
            let group = owned[starter] ?? []
            if names.contains(starter) {
                result += [elements[starter]] + topDown(group.filter(wrapped.contains)) + topDown(group.filter(descriptions.contains))
            } else {
                result += [elements[starter]] + topDown(group)
            }
        }
        return result
    }

    /// The reading-order sort: rows from the top, left to right within a row. A floated box reads
    /// after the lines beside it and before the lines below it.
    static func sortedByRows(_ elements: [Element], bodySize: CGFloat) -> [Element] {
        func key(_ element: Element) -> CGFloat { element.box == nil ? element.rect.midY : element.rect.minY }
        return elements.sorted {
            abs(key($0) - key($1)) > bodySize * 0.4 ? key($0) > key($1) : $0.rect.minX < $1.rect.minX
        }
    }

    /// Text blocks that interleave by baseline where no whitespace cut separates them (#122). The
    /// CDC comic sets a speech balloon beside a caption box: each is a stack of short lines at its
    /// own leading, and the inherited text layer's rectangles overhang the lettering, so the
    /// balloon's lines overlap the box's in both directions and the row sort alternates them
    /// (page 14's `Nothing but snow.` between the broadcast's lines, page 34's `works!` after it).
    ///
    /// Lines are taken from the top and each joins the block whose lowest line it sits under at
    /// ordinary leading (`-0.4…0.9` of the larger size, the prose window) and overlaps horizontally,
    /// the block with the nearest centre when several qualify; a line sharing most of the lowest
    /// line's height and set within one body beside it continues that row (page 34's
    /// `L o o k in g` + `f o r ?`). Returns the two blocks, left one first as a column cut would read
    /// them, only when the region's lines form exactly two blocks that stand apart (centres more
    /// than a quarter of the wider measure apart), are both set centred, share at most a third of
    /// the smaller block's baselines and alternate in the row sort at least three times, which
    /// they can only do beside each other. Across the fifteen English corpus books the
    /// step fires only on CDC pages 14, 23 and 34 (`measurements/fallback-blocks-and-ligatures`).
    /// Rows of a table or a name beside its description share baselines or form many blocks (9/11
    /// page 452's glossary); left-aligned columns are not centred (Project Blue Book's tables);
    /// lines of one paragraph around a formula piece share a measure (Wallace's worked examples).
    /// Nil for any region holding anything but plain lines, or a list line.
    static func interleavedBlocks(_ elements: [Element], bodySize: CGFloat) -> [[Element]]? {
        guard elements.count >= 4, elements.allSatisfy({ element in
            guard let line = element.line, element.box == nil, !element.boundary else { return false }
            return !isList(line.text)
        }) else { return nil }
        var blocks: [[Element]] = []
        for element in elements.sorted(by: { $0.rect.maxY != $1.rect.maxY ? $0.rect.maxY > $1.rect.maxY : $0.rect.minX < $1.rect.minX }) {
            let rect = element.rect, size = element.line!.fontSize
            var best: (index: Int, distance: CGFloat)?
            for (index, block) in blocks.enumerated() {
                guard let lowest = block.min(by: { $0.rect.minY < $1.rect.minY })?.rect else { continue }
                let scale = max(size, block.last!.line!.fontSize)
                let distance: CGFloat
                if min(lowest.maxY, rect.maxY) - max(lowest.minY, rect.minY) >= max(lowest.height, rect.height) * 0.5 {
                    let gap = max(lowest.minX, rect.minX) - min(lowest.maxX, rect.maxX)
                    guard gap >= 0, gap <= bodySize else { continue }
                    distance = 0
                } else {
                    let gap = lowest.minY - rect.maxY
                    guard gap > -scale * 0.4, gap < scale * 0.9, rect.minX < lowest.maxX, rect.maxX > lowest.minX else { continue }
                    distance = abs(rect.midX - lowest.midX)
                }
                if distance < (best?.distance ?? .greatestFiniteMagnitude) { best = (index, distance) }
            }
            if let best { blocks[best.index].append(element) } else { blocks.append([element]) }
        }
        // Two blocks with their centres apart by more than a quarter of the wider one's measure.
        // (Alternating three times below implies that they share part of their height and hold
        // at least two lines each.)
        guard blocks.count == 2 else { return nil }
        let (first, second) = (union(blocks[0].map(\.rect)), union(blocks[1].map(\.rect)))
        guard abs(first.midX - second.midX) > max(first.width, second.width) * 0.25 else { return nil }
        // Both blocks are set centred, as balloon and caption lettering is: their lines' centres
        // spread over less than half as much as their left edges (CDC 14's box, 21 against 116
        // points). Table columns and prose share a left edge (Project Blue Book's scanned
        // statistics tables, whose row labels sit a few points off their figures' baselines).
        func centred(_ block: [Element]) -> Bool {
            let centres = block.map(\.rect.midX), edges = block.map(\.rect.minX)
            return centres.max()! - centres.min()! < (edges.max()! - edges.min()!) * 0.5
        }
        guard blocks.allSatisfy(centred) else { return nil }
        // At most a third of the smaller block's baselines fall on the other's.
        let (small, large) = blocks[0].count <= blocks[1].count ? (blocks[0], blocks[1]) : (blocks[1], blocks[0])
        let shared = small.filter { line in large.contains { abs($0.rect.minY - line.rect.minY) <= bodySize * 0.2 } }
        guard shared.count * 3 <= small.count else { return nil }
        // The row sort alternates between them at least three times, rather than reading one first.
        let owners = sortedByRows(elements, bodySize: bodySize).map { element in
            blocks[0].contains { $0.rect == element.rect && $0.line == element.line }
        }
        guard zip(owners, owners.dropFirst()).filter({ $0 != $1 }).count >= 3 else { return nil }
        return first.minX <= second.minX ? blocks : [blocks[1], blocks[0]]
    }

    /// A line set above columns heads all of them, but it need not span the gutter that
    /// separates them. Wallace's answer keys centre `Answers - Chapter 0` and each
    /// `Answers - <topic>` label on the page while column 1 begins far to their left, so the
    /// page's widest whitespace is column 1's gutter and the title is cut away with columns 2
    /// and 3, reading after column 1's whole answer list; the section numbers `0.1` and `8.1`,
    /// set over column 1 alone, were read with that column instead of ahead of every column
    /// they number (#47).
    ///
    /// Given the gutter the whitespace test would otherwise cut, the region's horizontal
    /// whitespace divides it into bands, read here from the top. A band that is a single text
    /// line — a title, a section number, a table's label — heads the columns and is separated
    /// by a horizontal cut first. Returns that cut: the whitespace above the line when anything
    /// precedes it, otherwise the whitespace below it. Any other band is column content and is
    /// passed over. Two or more lines at ordinary leading are a paragraph, which belongs to the
    /// column it sits in even when it stands clear of the other column: the CDC comic's speech
    /// balloons are spaced exactly as labels are, and reading one ahead of the panel beside it
    /// breaks the panel order.
    ///
    /// The columns must still run beside each other beneath the band, or the search ends. A
    /// column that has ended keeps its own continuation: the FAA's glossary page 511 fills its
    /// left column below the last entry of the right one, with only the printed folio beyond
    /// the gutter, and a cut there would read the tail of the left column after the right
    /// column instead of before it. Bands are found at 0.8 body rather than the 1.1 the
    /// whitespace cut demands, because a label sits closer to the column it heads than to the
    /// label above it (Wallace page 438 sets `Answers - Integers` 10.7 pt over 12-point
    /// answers); a row of the columns themselves is never a single line, so the looser measure
    /// cannot cut one.
    static func headingBand(_ elements: [Element], gutter: CGFloat, bodySize: CGFloat) -> CGFloat? {
        let intervals = elements.map { ($0.rect.minY, $0.rect.maxY) }.sorted { $0.0 < $1.0 }
        guard let first = intervals.first else { return nil }
        var end = first.1
        var cuts: [CGFloat] = []
        for interval in intervals.dropFirst() {
            if interval.0 - end > bodySize * 0.8 { cuts.append((end + interval.0) / 2) }
            end = max(end, interval.1)
        }
        let boundaries = Array(cuts.reversed())
        for (index, lower) in boundaries.enumerated() {
            let below = elements.filter { $0.rect.maxY < lower }
            let left = below.filter { $0.rect.maxX < gutter }, right = below.filter { $0.rect.minX > gutter }
            guard !left.isEmpty, !right.isEmpty else { return nil }
            let leftRange = union(left.map(\.rect)), rightRange = union(right.map(\.rect))
            guard min(leftRange.maxY, rightRange.maxY) > max(leftRange.minY, rightRange.minY) else { return nil }
            let upper = index == 0 ? CGFloat.greatestFiniteMagnitude : boundaries[index - 1]
            let band = elements.filter { $0.rect.minY > lower && $0.rect.maxY < upper }
            if band.count == 1, band[0].line != nil { return index == 0 ? lower : upper }
        }
        return nil
    }

    /// A line set in heading type: at least the 1.25 bodies `blocks` demands of a heading, and
    /// not a list line.
    private static func isHeadingType(_ element: Element, bodySize: CGFloat) -> Bool {
        guard let line = element.line, !line.monospaced else { return false }
        return line.fontSize >= bodySize * 1.25 && !isList(line.text)
    }

    /// A horizontal cut can find as much whitespace below a heading as above it. DGA page 4 sets
    /// `Incorporate Healthy Fats` 13.89 pt under the columns before it and 13.91 pt over its own
    /// bullets, so the widest band leaves it at the foot of the part above; there the gutter cut
    /// reads it with the left column, ahead of the right column's last bullet and its sub-items
    /// (#103). Given the cut, when everything beneath the lowest band of more than 1.1 body in the
    /// part above is one or two lines in heading type, returns that band instead: the heading
    /// reads first in the part below, the content it introduces. Nil when the cut stands.
    static func trailingHeading(_ elements: [Element], cut: CGFloat, bodySize: CGFloat) -> CGFloat? {
        let upper = elements.filter { $0.rect.minY > cut }
        // Every element of the part falls on one side of each band `horizontalBands` reports.
        guard let band = horizontalBands(upper).last(where: { $0.width > bodySize * 1.1 }) else { return nil }
        let tail = upper.filter { $0.rect.maxY < band.y }
        // A section icon ordered in its heading's row (#117) stays with the heading.
        let headings = tail.filter { isHeadingType($0, bodySize: bodySize) }
        let row = union(headings.map(\.rect))
        let icons = tail.filter { $0.line == nil && $0.box == nil && $0.table == nil
            && $0.rect.minY >= row.minY - 0.5 && $0.rect.maxY <= row.maxY + 0.5 }
        guard (1...2).contains(headings.count), headings.count + icons.count == tail.count else { return nil }
        return band.y
    }

    /// Stacked sections whose rows sit closer than the whitespace cut's 1.1 body, each a heading
    /// with a decorative band across the measure over two columns, give no cut at all: the band
    /// hides the gutter and the sort interleaves the columns line by line. DGA page 9 sets
    /// `Older Adults` beside its band 8.4 pt over its columns and 10.5 pt under the section
    /// above; where the tags fall back, its one bullet read across both columns a line at a time
    /// (#103). A heading-type line and the figures in its row, with nothing else reaching into
    /// the row's height, separate what is above them from what is below: the parts are read in
    /// turn, each cut on its own. Returns nil unless there is content on both sides of the row.
    static func headingRow(_ elements: [Element], bodySize: CGFloat)
        -> (above: [Element], row: [Element], below: [Element])? {
        for heading in elements.filter({ isHeadingType($0, bodySize: bodySize) }).sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            let row = elements.filter { $0.rect.minY < heading.rect.maxY && $0.rect.maxY > heading.rect.minY }
            guard row.contains(where: { $0.line == nil && $0.box == nil }) else { continue }
            let extent = union(row.map(\.rect))
            let above = elements.filter { $0.rect.minY >= extent.maxY }
            let below = elements.filter { $0.rect.maxY <= extent.minY }
            guard !above.isEmpty, !below.isEmpty, above.count + row.count + below.count == elements.count else { continue }
            return (above, row, below)
        }
        return nil
    }

    /// Whitespace bands across a region, top to bottom: the midpoint of each band and its height.
    static func horizontalBands(_ elements: [Element]) -> [(y: CGFloat, width: CGFloat)] {
        let intervals = elements.map { ($0.rect.minY, $0.rect.maxY) }.sorted { $0.1 > $1.1 }
        guard var floor = intervals.first?.0 else { return [] }
        var bands: [(y: CGFloat, width: CGFloat)] = []
        for interval in intervals.dropFirst() {
            if interval.1 < floor { bands.append(((floor + interval.1) / 2, floor - interval.1)) }
            floor = min(floor, interval.0)
        }
        return bands
    }

    /// A figure set across both columns' full measure, above or below them, bridges their
    /// gutter, so the text-measured gutter refuses to cut it; when its rectangle comes within
    /// 1.1 body of the columns' first or last lines no horizontal band separates it either, and
    /// the page falls to the reading-order sort, which interleaves the columns line by line.
    /// FAA page 340's runway figure ends 0.7 pt above the columns' headings, and page 401's two
    /// wind-triangle figures begin 8 pt below the left column's last line with a caption under
    /// them (#86). A crop can also come nearer still: page 108's ground-effect figure rises to
    /// within a few points of both columns' last lines, and page 19's airmail map to the lines
    /// beneath it, so no whitespace band isolates the figure without taking column lines too.
    ///
    /// The figures are therefore separated by partition, not by a cut. The gutter is measured
    /// over the text lines other than captions (`Figure N`/`Table N` lines and the lines wrapped
    /// beneath them). The figures that straddle it must all lie above the columns' first line or
    /// below their last (within half a body); a figure between two blocks of columns is not
    /// moved. Every other element, captions set beside the columns included, must fall wholly on
    /// one side of a gutter that separates prose on both sides (two lines at least 12 bodies wide
    /// each): short cells keep their row associations. A caption whose lines all lie beyond the
    /// columns goes with the figures, unless it sits against a figure of the columns' own: page
    /// 194's `Figure 7-38` under its photo stays with the left column, as does page 19's photo
    /// caption, whose first line stands beside the right column's last lines. Returns the figures
    /// and captions read before the columns, the columns, and those read after them; nil when the
    /// region has no such figure. Tinted boxes are not figures.
    static func spanningFigures(_ elements: [Element], bodySize: CGFloat, gutter: ([Element]) -> CGFloat?)
        -> (head: [Element], columns: [Element], foot: [Element])? {
        guard elements.contains(where: { $0.line == nil && $0.box == nil }) else { return nil }
        // Each caption line keys its caption: a `Figure N` line and the lines wrapped beneath it on
        // its left edge at ordinary leading.
        var caption: [Int: Int] = [:]
        for index in elements.indices where elements[index].line.map({ isCaption($0.text) }) ?? false { caption[index] = index }
        var grown = true
        while grown {
            grown = false
            for index in elements.indices where caption[index] == nil {
                // The line joins the caption of the earliest member above it in reading order. The
                // members are read in that order, not the dictionary's, whose order changes from
                // process to process and made the page's columns differ between identical runs (#140).
                guard let line = elements[index].line,
                      let member = caption.keys.sorted().first(where: { member in
                          let above = elements[member].rect
                          return abs(above.minX - line.rect.minX) <= bodySize * 0.5
                              && above.minY - line.rect.maxY > -bodySize * 0.4 && above.minY - line.rect.maxY < bodySize * 0.5
                      }), let owner = caption[member] else { continue }
                caption[index] = owner; grown = true
            }
        }
        let captions = Set(caption.keys)
        let text = elements.indices.filter { elements[$0].line != nil && !captions.contains($0) }.map { elements[$0] }
        guard let measured = gutter(text) else { return nil }
        let spanning = elements.indices.filter { index in
            let element = elements[index]
            return element.line == nil && element.box == nil && element.rect.minX < measured && element.rect.maxX > measured
        }
        guard !spanning.isEmpty else { return nil }
        let body = elements.indices.filter { !spanning.contains($0) && !captions.contains($0) }
        guard let top = body.map({ elements[$0].rect.maxY }).max(), let bottom = body.map({ elements[$0].rect.minY }).min()
        else { return nil }
        let tolerance = bodySize * 0.5
        func above(_ index: Int) -> Bool { elements[index].rect.minY >= top - tolerance }
        func below(_ index: Int) -> Bool { elements[index].rect.maxY <= bottom + tolerance }
        guard spanning.allSatisfy({ above($0) || below($0) }) else { return nil }
        // A caption goes with the spanning figures only when all of its lines lie beyond the columns
        // and it does not sit against a figure of the columns' own.
        let own = elements.indices.filter { elements[$0].line == nil && !spanning.contains($0) }.map { elements[$0].rect }
        let beyond = Set(Dictionary(grouping: captions, by: { caption[$0]! }).filter { owner, lines in
            let label = elements[owner].rect
            let captionsOwnFigure = own.contains { figure in
                figure.minX < label.maxX && figure.maxX > label.minX
                    && (abs(figure.minY - label.maxY) <= bodySize * 1.5 || abs(label.minY - figure.maxY) <= bodySize * 1.5)
            }
            return !captionsOwnFigure && (lines.allSatisfy(above) || lines.allSatisfy(below))
        }.values.joined())
        let outer = Set(spanning + beyond)
        let columns = elements.indices.filter { !outer.contains($0) }.map { elements[$0] }
        guard let x = gutter(columns) else { return nil }
        let sides = [columns.filter { $0.rect.maxX < x }, columns.filter { $0.rect.minX > x }]
        guard sides.allSatisfy({ side in side.filter { $0.line != nil && $0.rect.width >= bodySize * 12 }.count >= 2 })
        else { return nil }
        let head = outer.sorted().filter { above($0) }.map { elements[$0] }
        let foot = outer.sorted().filter { !above($0) }.map { elements[$0] }
        return (head, columns, foot)
    }

    /// Stacked blocks of short answer columns that share one gutter. Wallace page 487 sets item
    /// 1's sub-answers a–i in three columns above answers 2–15 in three columns on the same
    /// edges, so the gutter runs through both blocks and cutting it read `a`–`d`, `2`–`6`,
    /// `e`–`h`… (#78). The blocks stand 38 pt apart, while no column's own rows are more than 15 pt
    /// apart.
    ///
    /// Returns the widest horizontal band of at least two bodies, at least twice the widest
    /// whitespace inside either side of the gutter above or below it, that has columns running
    /// beside each other on both sides of it. Prose columns (any line at least 12 bodies wide)
    /// are never stacked blocks: their paragraphs flow from one column's foot to the next
    /// column's head.
    static func stackedBlocks(_ elements: [Element], gutter: CGFloat, bodySize: CGFloat) -> CGFloat? {
        guard !elements.contains(where: { $0.line != nil && $0.rect.width >= bodySize * 12 }) else { return nil }
        /// The part's two sides of the gutter, when both hold content running beside each other.
        func sides(_ part: [Element]) -> [[Element]]? {
            let left = part.filter { $0.rect.maxX < gutter }, right = part.filter { $0.rect.minX > gutter }
            guard !left.isEmpty, !right.isEmpty else { return nil }
            let l = union(left.map(\.rect)), r = union(right.map(\.rect))
            return min(l.maxY, r.maxY) > max(l.minY, r.minY) ? [left, right] : nil
        }
        var best: (y: CGFloat, width: CGFloat)?
        for band in horizontalBands(elements) where band.width >= bodySize * 2 && band.width > (best?.width ?? 0) {
            guard let above = sides(elements.filter { $0.rect.minY > band.y }),
                  let below = sides(elements.filter { $0.rect.maxY < band.y }) else { continue }
            let spacing = (above + below).map { horizontalBands($0).map(\.width).max() ?? 0 }.max() ?? 0
            if band.width >= spacing * 2 { best = band }
        }
        return best?.y
    }

    /// Labelled cells numbered along their rows. Wallace page 448 sets graphs 15–22 three to a
    /// row under their labels `15)`, `16)`, `17)` / `18)`… with no whitespace between the rows
    /// (graph 20 hangs below label 21's top), so only the column gutters cut them, and they read
    /// 15, 18, 21, 16… (#78). The answer lists and exercise sets are numbered down their columns
    /// by design and must keep reading that way, so the geometry does not decide; the numbers do.
    ///
    /// Returns the region's `N)` labels when they form a grid read row-major: at least four
    /// labels in two or more rows of at least two, at least three columns, each row's labels on
    /// the first row's column edges, the numbers consecutive row by row, and nothing in the region
    /// above the first row. Otherwise nil. Wallace sets its exercises two to a row and numbers them
    /// along the rows (`1)` | `2)`), but the book reads them column by column by contract (pages 10,
    /// 26 and 424's triangles), so a two-column grid is never reordered.
    static func rowMajorLabels(_ elements: [Element], bodySize: CGFloat) -> [(rect: CGRect, number: Int)]? {
        let labels = elements.compactMap { element -> (rect: CGRect, number: Int)? in
            guard let text = element.line?.text,
                  let range = text.range(of: #"^[0-9]{1,3}(?=\))"#, options: .regularExpression),
                  let number = Int(text[range]) else { return nil }
            return (element.rect, number)
        }
        guard labels.count >= 4 else { return nil }
        var rows: [[(rect: CGRect, number: Int)]] = []
        for label in labels.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            if let anchor = rows.last?.first, anchor.rect.maxY - label.rect.maxY <= bodySize { rows[rows.count - 1].append(label) }
            else { rows.append([label]) }
        }
        rows = rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
        guard rows.count >= 2, rows.filter({ $0.count >= 2 }).count >= 2,
              let first = rows.first, first.count >= 3, rows.allSatisfy({ $0.count <= first.count }) else { return nil }
        // A grid: the i-th label of every row stands on the i-th label's left edge in the first row.
        guard rows.allSatisfy({ row in row.indices.allSatisfy { abs(row[$0].rect.minX - first[$0].rect.minX) <= bodySize } })
        else { return nil }
        let sequence = rows.flatMap { $0.map(\.number) }
        guard zip(sequence, sequence.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return nil }
        // Every cell hangs beneath its label: nothing in the region stands above the first row.
        let ceiling = first.map(\.rect.maxY).max()!
        guard elements.allSatisfy({ $0.rect.maxY <= ceiling + bodySize * 0.25 }) else { return nil }
        return labels
    }

    /// Where one numbered key ends and the next begins (#178). Wallace's answer keys set short
    /// numeric entries in two or three columns numbered down each column, one key under the next,
    /// each under its own title. The title runs across every gutter, so no vertical band of
    /// whitespace divides the page; the entries are nowhere near the twelve bodies a narrow
    /// gutter's prose test demands, and a key sits closer to the key above it than the 1.1 bodies
    /// a horizontal cut asks. Page 486's second key therefore read `1) 0`, `15) 1`, `29) 0`,
    /// `2)− 1`… across its rows and page 465's first key read `11)`, `27)`, `12)`, `28)`… across
    /// its own.
    ///
    /// The numbers decide where the cut goes, as they decide which way #78's grids read. Returns
    /// the highest whitespace band of the region — a line no element crosses — whose markers below
    /// it read down their columns (`readsDownColumns`) and open at a number no higher than any
    /// number above it. That restart is what makes them two keys: a band inside one key leaves
    /// that key's own first entry above it, so what is below opens higher and is refused, and a
    /// key the entries above continue (1–7 over 8–11) opens higher still. A grid numbered along
    /// its rows (page 448's graphs, the two-to-a-row exercise sets on pages 10, 26 and 424)
    /// interleaves its columns' numbers and is refused at every band.
    static func numberedKeyBand(_ elements: [Element], bodySize: CGFloat) -> CGFloat? {
        let markers = elements.compactMap { element -> (rect: CGRect, number: Int)? in
            guard let line = element.line, !line.monospaced,
                  let range = line.text.range(of: #"^[0-9]{1,3}(?=\))"#, options: .regularExpression),
                  let number = Int(line.text[range]), number > 0 else { return nil }
            return (element.rect, number)
        }
        guard markers.count >= 6 else { return nil }
        for band in horizontalBands(elements) {
            let below = markers.filter { $0.rect.maxY < band.y }
            let above = markers.filter { $0.rect.minY > band.y }
            guard let opening = below.map(\.number).min(),
                  let earliest = above.map(\.number).min(), opening <= earliest,
                  readsDownColumns(below, bodySize: bodySize) else { continue }
            return band.y
        }
        return nil
    }

    /// Markers set in columns at their own left edges and numbered down each column: at least two
    /// columns, each holding at least two markers on its own edge, each column counting up from
    /// its top, and each column's numbers standing wholly below the column to its left. A key
    /// numbered along its rows fails the last test, since its columns' numbers interleave.
    static func readsDownColumns(_ markers: [(rect: CGRect, number: Int)], bodySize: CGFloat) -> Bool {
        var edges: [CGFloat] = []
        for x in markers.map(\.rect.minX).sorted() where edges.last.map({ x - $0 > bodySize * 1.5 }) ?? true {
            edges.append(x)
        }
        guard edges.count >= 2 else { return false }
        var columns = Array(repeating: [(rect: CGRect, number: Int)](), count: edges.count)
        for marker in markers {
            guard let column = edges.lastIndex(where: { marker.rect.minX >= $0 - bodySize * 0.5 }) else { return false }
            columns[column].append(marker)
        }
        var previous = 0
        for column in columns {
            guard column.count >= 2 else { return false }
            let down = column.sorted { $0.rect.maxY > $1.rect.maxY }.map(\.number)
            guard down[0] > previous, zip(down, down.dropFirst()).allSatisfy({ $1 > $0 }) else { return false }
            previous = down[down.count - 1]
        }
        return true
    }

    /// Column-ordered cells regrouped by their labels' numbers: each label leads the elements that
    /// follow it in its column.
    static func inNumberOrder(_ columns: [Element], labels: [(rect: CGRect, number: Int)]) -> [Element] {
        var head: [Element] = [], cells: [(number: Int, elements: [Element])] = []
        for element in columns {
            if element.line != nil, let label = labels.first(where: { $0.rect == element.rect }) {
                cells.append((label.number, [element]))
            } else if cells.isEmpty {
                head.append(element)
            } else {
                cells[cells.count - 1].elements.append(element)
            }
        }
        return head + cells.sorted { $0.number < $1.number }.flatMap(\.elements)
    }

    /// Bulleted columns the whitespace cuts cannot separate: their items are far shorter than
    /// the prose-column measure, and a label set over both columns spans the gutter, so no
    /// vertical band of whitespace runs the height of the group (Fed page 58's "Emergency
    /// lending facilities" panel, #64). The evidence is the markers themselves: two runs of at
    /// least two list markers, each run on its own left edge, with every line at or below the
    /// first marker wholly on one side of a gutter at least as wide as the whitespace test
    /// demands. Lines above the first marker are the columns' heading and read before them.
    /// Returns the gutter's x, or nil when the markers give no such reading.
    static func bulletColumns(_ elements: [Element], bodySize: CGFloat) -> CGFloat? {
        let markers = elements.filter { element in
            guard let line = element.line, !line.monospaced else { return false }
            return isList(line.text)
        }
        guard markers.count >= 4, let top = markers.map(\.rect.maxY).max() else { return nil }
        let edges = markers.map(\.rect.minX).sorted()
        // A marker column's own lines share a left edge; the next column starts a marker's
        // width away. Indices walk the sorted edges so three columns split one gutter at a time.
        for index in 1..<edges.count where edges[index] - edges[index - 1] > bodySize * 2 {
            let split = (edges[index - 1] + edges[index]) / 2
            let leading = markers.filter { $0.rect.minX < split }
            let trailing = markers.filter { $0.rect.minX > split }
            guard leading.count >= 2, trailing.count >= 2,
                  leading.allSatisfy({ $0.rect.minX <= edges[index - 1] + bodySize * 0.5 }),
                  trailing.allSatisfy({ $0.rect.minX >= edges[index] - bodySize * 0.5 }) else { continue }
            let items = elements.filter { $0.rect.minY < top }
            let left = items.filter { $0.rect.minX < split }, right = items.filter { $0.rect.minX > split }
            guard left.count + right.count == items.count,
                  let leadingEnd = left.map(\.rect.maxX).max(), let trailingStart = right.map(\.rect.minX).min(),
                  trailingStart - leadingEnd > bodySize * 0.75 else { continue }
            let gutter = (leadingEnd + trailingStart) / 2
            // Only a heading above the columns may span the gutter; a note or a rule beneath
            // them binds the columns together and leaves the group to the reading-order sort.
            guard elements.allSatisfy({ $0.rect.minY >= top || $0.rect.maxX <= gutter || $0.rect.minX >= gutter })
            else { continue }
            return gutter
        }
        return nil
    }

    /// Tinted boxes (sidebars, shaded tables with their titles) are read as units: the elements
    /// inside each box are ordered among themselves and the box takes one place in the page
    /// order, as its image did before the box reflowed (#54).
    static func boxed(_ elements: [Element], tints: [CGRect], bodySize: CGFloat) -> [Element] {
        var remaining = elements
        var boxes: [Element] = []
        for hull in clusters(tints, distance: 4) {
            let inside = remaining.filter { hull.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            guard inside.contains(where: { $0.line != nil }) else { continue }
            remaining.removeAll { element in inside.contains { $0.rect == element.rect && $0.line == element.line && $0.image == element.image } }
            boxes.append(Element(rect: hull.union(union(inside.map(\.rect))), box: ordered(inside, bodySize: bodySize)))
        }
        return ordered(remaining + boxes, bodySize: bodySize).flatMap { element -> [Element] in
            guard let content = element.box else { return [element] }
            let edge = Element(rect: element.rect, boundary: true)
            return [edge] + content + [edge]
        }
    }

    /// The rounded size holding the most characters. Sizes that tie read as the smaller one: a
    /// dictionary's order changes from process to process, so an unbroken tie made the page's body
    /// size, and everything measured against it, differ between identical runs (#140).
    static func bodySize(_ lines: [TextLine]) -> CGFloat {
        var weights: [Int: Int] = [:]
        addBodyWeights(of: lines, to: &weights)
        return bodySize(weights: weights) ?? 12
    }

    /// Characters per rounded type size, the evidence `bodySize` weighs; accumulated over a document's
    /// native pages it gives the document's body (#186).
    static func addBodyWeights(of lines: [TextLine], to weights: inout [Int: Int]) {
        for line in lines { weights[Int(line.fontSize.rounded()), default: 0] += line.text.count }
    }

    static func bodySize(weights: [Int: Int]) -> CGFloat? {
        weights.max { ($0.value, -$0.key) < ($1.value, -$1.key) }.map { CGFloat($0.key) }
    }

    /// The justified measure of the column `line` stands in: the column's own dominant type size
    /// and the left and right edges that at least three of its lines in that size share. `column`
    /// is the lines whose horizontal span meets the line's, as `sectionLabels` reads a column. The
    /// size is the column's, not the page's, because a column can be set smaller than the body
    /// (the IEEEtran paper's bibliography, 7.97 points under a 9-point page).
    ///
    /// A two-column paper's section titles are set at body size, so size alone cannot tell them
    /// from prose; their place inside this measure can (#162).
    static func columnMeasure(of column: [TextLine]) -> (left: CGFloat, right: CGFloat, size: CGFloat)? {
        let size = bodySize(column)
        let prose = column.filter { !$0.monospaced && abs($0.fontSize - size) <= size * 0.1 }
        func shared(_ values: [CGFloat]) -> CGFloat? {
            values.first { value in values.filter { abs($0 - value) <= size * 0.25 }.count >= 3 }
        }
        guard size > 0, let left = shared(prose.map(\.rect.minX).sorted()),
              let right = shared(prose.map(\.rect.maxX).sorted(by: >)), right - left >= size * 8
        else { return nil }
        return (left, right, size)
    }

    /// Whether `line` is set centred inside `measure`: it is inset from both edges, by insets that
    /// agree within three quarters of the measure's type size. A justified prose line reaches both
    /// edges exactly, a first-line indent or a hanging indent is inset on one side only, and a
    /// ragged last line leaves all its space on the right. A two-line title's first line can run
    /// nearly the whole measure (`VII. COMPATIBILITY WITH A DISTRIBUTED SYSTEM FOR`, half a body
    /// inside each edge), so the insets are asked to be real rather than wide.
    static func isCentred(_ line: TextLine, in measure: (left: CGFloat, right: CGFloat, size: CGFloat)) -> Bool {
        let left = line.rect.minX - measure.left
        let right = measure.right - line.rect.maxX
        return left >= measure.size * 0.4 && right >= measure.size * 0.4
            && abs(left - right) <= measure.size * 0.75
    }

    /// A Roman-numeral section number opening a line (`I.`, `VII.`, `VIII.`). IEEEtran numbers its
    /// sections this way, so `I.` and `V.` also read as one-letter list markers (#162). A bare
    /// numeral with no period is a slip opinion's part label, not a numbered title (Loper Bright's
    /// `I`, `II`, `III`).
    static func opensWithRomanNumeral(_ text: String) -> Bool {
        text.range(of: "^(?:M{0,3}(?:CM|CD|D?C{0,3})(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3}))\\.\\s+\\S",
                   options: .regularExpression) != nil
            && text.first.map { "IVXLCDM".contains($0) } == true
    }

    /// The section heads a numbered paper prints without a number: its appendices and the standard
    /// end matter. They stand in the same sequence as the numbered titles and are set the same way,
    /// but carry no numeral of their own (#162).
    static func isUnnumberedSectionHead(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return false }
        return ["APPENDIX", "APPENDICES", "REFERENCES", "BIBLIOGRAPHY", "NOMENCLATURE",
                "ACKNOWLEDGMENT", "ACKNOWLEDGMENTS", "ACKNOWLEDGEMENT", "ACKNOWLEDGEMENTS"]
            .contains(String(first).trimmingCharacters(in: CharacterSet(charactersIn: ".:")).uppercased())
    }

    /// Whether `line` is the next line of the centred title `previous` opens, set in the small
    /// capitals' own size: directly beneath it at ordinary heading leading, sharing its centre.
    /// `stacksUnderHeading` cannot read such a pair, because PDFKit reports the title's size from
    /// its full-size initial (9.96 points) and the continuation line's from its small capitals
    /// (7.97), a fifth apart (#162).
    static func continuesCentredTitle(_ line: TextLine, after previous: TextLine) -> Bool {
        let size = previous.fontSize
        guard line.fontSize >= size * 0.65, line.fontSize <= size * 0.95, !sameRow(previous.rect, line.rect),
              line.rect.minY < previous.rect.minY, line.rect.maxY >= previous.rect.minY - size,
              previous.rect.minY - line.rect.minY <= size * 2.2 else { return false }
        return abs(previous.rect.midX - line.rect.midX) <= size * 0.6
    }

    /// The section and subsection titles a two-column academic paper sets at its own body size,
    /// which neither the heading-size threshold nor a recurring `LabelStyle` can reach (#162).
    /// The NTRS IEEEtran paper (`ntrs-20190030725-dasc-2019`) prints both:
    ///
    /// - a **section title** centred in its column's justified measure, wholly in capitals
    ///   (`II. PROBLEM INPUT AND OUTPUT`, `APPENDIX A`, `REFERENCES`), set off above by more than
    ///   the column's leading, over text no larger than the body. IEEEtran sets these in small
    ///   capitals, so a numeral such as `I.` or `V.` also reads as a one-letter list marker and a
    ///   title wrapped onto a second line carries only small capitals, a fifth smaller than the
    ///   line PDFKit measures from the full-size initial (`continuesCentredTitle`);
    /// - a **subsection title**, a single capital letter and period before a sentence-case title
    ///   set wholly in italic on the column's left edge (`A. Input data`, `B. Output data: the
    ///   format of a “schedule”`), set off above and below by more than the leading, with the
    ///   section's first paragraph opening beneath it on the column's own first-line indent.
    ///
    /// Both are refused on recognized and synthetic text, where sizes and styles say nothing, and
    /// on a leader entry, a caption or a line that closes a sentence. `isTitleCase` is not asked:
    /// IEEEtran sets its subsection titles in sentence case.
    static func academicSectionTitles(in lines: [TextLine], body: CGFloat, page: PageContent) -> [TextLine] {
        guard !page.hasSyntheticTextStyle, !page.recognized else { return [] }
        var titles: [TextLine] = []
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            guard !line.monospaced, line.text.count >= 3, line.text.count < 200,
                  !isContentsEntry(line.text), !isCaption(line.text), !line.text.contains("...."),
                  line.text.filter(\.isLetter).count >= 3,
                  let last = lastCharacterBeforeMarker(line), !".,;:".contains(last) else { continue }
            let column = lines.filter { other in
                other != line && other.rect.minX < line.rect.maxX && other.rect.maxX > line.rect.minX
            }
            guard let measure = columnMeasure(of: column) else { continue }
            // The nearest lines above and below the title in its column.
            let above = column.filter { $0.rect.minY >= line.rect.maxY - body * 0.25 }
                .min { $0.rect.minY < $1.rect.minY }
            let below = column.filter { $0.rect.maxY <= line.rect.minY + body * 0.25 }
                .max { $0.rect.maxY < $1.rect.maxY }
            // The rest of the title above: its next line, stacked under it on the same centre at its
            // own size, or wrapped into the small capitals' size (`continuesCentredTitle`).
            if let previous = titles.last, previous == above,
               continuesCentredTitle(line, after: previous) || stacksUnderHeading(line, after: previous),
               line.text.filter(\.isLetter).allSatisfy(\.isUppercase), !LabelStyle(line, body: body).bold,
               isCentred(line, in: measure), !opensHeading(line.text), !endsSentence(previous.text) {
                titles.append(line)
                continue
            }
            // A section title stands at the body's own size or a little over it; past the heading
            // threshold `isHeadingSize` already has it. The references head is the page's largest
            // line, since the bibliography is set smaller than the body (`REFERENCES`, 9.96 over
            // 7.97), so the band reaches a quarter above the body.
            guard line.fontSize >= body * 0.9, line.fontSize <= body * 1.25 else { continue }
            let spacedAbove = above.map { $0.rect.minY - line.rect.maxY >= body * 0.5 } ?? true
                || above.map(titles.contains) == true
            // The text a centred title heads opens on the measure's own left edge, or on the
            // column's first-line indent inside it, directly beneath the title's last line. A
            // table's or display's title is centred over its table instead, and the line beneath
            // it is centred too (FAA page 416's `NONDIRECTIONAL RADIO BEACON (NDB)` over
            // `(Usable radius distances for all altitudes)`).
            func opensText() -> Bool {
                var next = below
                for _ in 0..<4 {
                    guard let candidate = next else { return false }
                    guard isCentred(candidate, in: measure), candidate.fontSize <= line.fontSize + 0.5,
                          candidate.text.filter(\.isLetter).allSatisfy(\.isUppercase) else {
                        let inset = candidate.rect.minX - measure.left
                        return candidate.fontSize <= body * 1.1 && inset >= -measure.size * 0.5
                            && inset <= measure.size * 1.5 && candidate.rect.width >= measure.size * 4
                    }
                    next = column.filter { $0.rect.maxY <= candidate.rect.minY + body * 0.25 }
                        .max { $0.rect.maxY < $1.rect.maxY }
                }
                return false
            }
            // Small capitals are set in the text face, never bold: a bold label over its paragraph
            // is `sectionLabels`' recurring-style evidence, whatever its measure leaves beside it
            // (Our Flag page 15 centres `BENNINGTON FLAG` among five flush flag labels, #76).
            // The title opens the paper's own section sequence — a Roman numeral and a period, an
            // appendix or one of the standard unnumbered heads. A centred line of capitals with no
            // such place in the sequence is a caption block (a slip opinion's `RELENTLESS, INC., ET
            // AL., PETITIONERS` among the lines of its case caption).
            if line.text.filter(\.isLetter).allSatisfy(\.isUppercase), !LabelStyle(line, body: body).bold,
               opensWithRomanNumeral(line.text) || isUnnumberedSectionHead(line.text),
               isCentred(line, in: measure), spacedAbove, opensText() {
                titles.append(line)
                continue
            }
            // A subsection title: an italic lettered marker on the column's own left edge.
            guard line.text.range(of: "^[A-Z]\\.\\s+\\p{Lu}", options: .regularExpression) != nil,
                  abs(line.fontSize - body) <= body * 0.1, LabelStyle(line, body: body).italic,
                  abs(line.rect.minX - measure.left) <= body * 0.5,
                  line.rect.maxX <= measure.right - body, spacedAbove,
                  let below, line.rect.minY - below.rect.maxY >= body * 0.5,
                  line.rect.minY - below.rect.maxY <= body * 2,
                  abs(below.fontSize - body) <= body * 0.1, !LabelStyle(below, body: body).italic,
                  !LabelStyle(below, body: body).bold, !isList(below.text), below.rect.width >= body * 8,
                  below.rect.minX - measure.left >= -body * 0.5,
                  below.rect.minX - measure.left <= body * 1.5 else { continue }
            titles.append(line)
        }
        return titles
    }

    /// Whether the page sets a run of wrapped lines at `indent` under lines on `edge`, in `size`:
    /// at least two lines at the indent whose nearest line above is on the edge, at least one
    /// whose nearest line above is itself at the indent, and an indented line reaching the edge
    /// lines' own right margin (#162).
    ///
    /// A hanging-indent list whose entries are set with no space between them (IEEEtran's
    /// bibliography and its numbered algorithm steps) cannot be told from a first-line indent by
    /// the space above an entry, which `blocks`' opening rule asks for (#147), nor by #134's
    /// sentence test, since a reference's first line routinely ends in a full stop or a semicolon
    /// (`[4] L. Meyn. A closed-form solution to multi-point scheduling problems.`). The run is the
    /// evidence instead: a first-line indent never sets two lines in a row at the indent, because
    /// the paragraph returns to the edge beneath its opening line.
    static func hangingRun(in lines: [TextLine], edge: CGFloat, indent: CGFloat, size: CGFloat) -> Bool {
        func sized(_ line: TextLine) -> Bool {
            !line.monospaced && abs(line.fontSize - size) <= size * 0.1
        }
        func onEdge(_ line: TextLine) -> Bool { sized(line) && abs(line.rect.minX - edge) <= size * 0.5 }
        func hangs(_ line: TextLine) -> Bool { sized(line) && abs(line.rect.minX - indent) <= size * 0.5 }
        func nearestAbove(_ line: TextLine) -> TextLine? {
            lines.filter { other in
                other != line && !sameRow(other.rect, line.rect) && other.rect.minY >= line.rect.maxY - size * 0.4
                    && other.rect.minX < line.rect.maxX && other.rect.maxX > line.rect.minX
            }.min { $0.rect.minY < $1.rect.minY }
        }
        var openings = 0
        var runs = 0
        for line in lines where hangs(line) {
            guard let above = nearestAbove(line), above.rect.minY - line.rect.maxY < size * 0.9 else { continue }
            if onEdge(above) { openings += 1 } else if hangs(above) { runs += 1 }
        }
        guard openings >= 2, runs >= 1, let right = lines.filter(onEdge).map(\.rect.maxX).max() else { return false }
        return lines.contains { hangs($0) && $0.rect.maxX >= right - size * 0.5 }
    }

    /// Whether the page opens its paragraphs on a first-line indent of `step`, in `size` (#159).
    ///
    /// *Agricultural Research* indents each paragraph's first line ten points in a ten-and-a-half
    /// point column and adds two points of space, so neither the leading nor the width of the line
    /// above says where a paragraph ends: only the indent does. That indent is narrower than the
    /// one and a half bodies a column's lines are allowed to drift by, so it needs the page's own
    /// evidence before it may break a paragraph.
    ///
    /// The evidence is the mirror of `hangingRun`'s, read as steps between neighbouring lines so
    /// that every column of a page supplies it: an opening line stands `step` inside the line above
    /// it and the line beneath it returns `step` outward, and at least two such lines stand on the
    /// page. A hanging indent is ruled out by the same reading — its wrapped lines stay at the
    /// indent, so a line beneath an indented one shares its edge, which a first-line indent never
    /// does because the paragraph returns to the measure beneath its opening line.
    ///
    /// Only lines of `size` are read, so a heading or a caption between two paragraphs is neither a
    /// neighbour nor evidence, and the nearest neighbour must stand at ordinary leading: a line
    /// across a paragraph's space or a column's foot supplies nothing.
    static func firstLineIndentRun(in lines: [TextLine], step: CGFloat, size: CGFloat) -> Bool {
        func sized(_ line: TextLine) -> Bool {
            !line.monospaced && abs(line.fontSize - size) <= size * 0.1
        }
        let column = lines.filter(sized)
        func neighbour(of line: TextLine, above: Bool) -> TextLine? {
            let sharing = column.filter { other in
                other != line && !sameRow(other.rect, line.rect)
                    && other.rect.minX < line.rect.maxX && other.rect.maxX > line.rect.minX
                    && (above ? other.rect.minY >= line.rect.maxY - size * 0.4
                              : other.rect.maxY <= line.rect.minY + size * 0.4)
            }
            return above ? sharing.min { $0.rect.minY < $1.rect.minY }
                         : sharing.max { $0.rect.maxY < $1.rect.maxY }
        }
        var openings = 0
        for line in column {
            guard let above = neighbour(of: line, above: true),
                  above.rect.minY - line.rect.maxY < size * 0.9,
                  abs(line.rect.minX - above.rect.minX - step) <= size * 0.5,
                  let below = neighbour(of: line, above: false),
                  line.rect.minY - below.rect.maxY < size * 0.9 else { continue }
            if abs(below.rect.minX - line.rect.minX) <= size * 0.5 { return false }
            if abs(line.rect.minX - below.rect.minX - step) <= size * 0.5 { openings += 1 }
        }
        return openings >= 2
    }

    /// Small labels inside preserved images must not turn the surrounding prose into headings.
    /// Keep the page estimate when too little reflowable text remains to establish a body size.
    static func headingBodySize(_ lines: [TextLine], pageBody: CGFloat) -> CGFloat {
        establishedBodySize(lines).map { max(pageBody, $0) } ?? pageBody
    }

    /// The body size the lines establish: at least three lines and 200 characters in their commonest size.
    static func establishedBodySize(_ lines: [TextLine]) -> CGFloat? {
        let candidate = bodySize(lines)
        let matching = lines.filter { Int($0.fontSize.rounded()) == Int(candidate) }
        guard matching.count >= 3, matching.reduce(0, { $0 + $1.text.count }) >= 200 else { return nil }
        return candidate
    }

    /// The smallest heading size on a page whose reflowable text establishes no body of its own
    /// (#186). Such a page (a back cover, a cover) measures its display lines against type it barely
    /// sets: *Agricultural Research*'s back cover estimates an 8-point body from the subscribe box
    /// inside its crop, and its 10-point return address and 11-point web line became headings in a
    /// magazine whose columns are set at 10.5. There a heading must also clear the document's body
    /// (`documentBody`, the size most of its native text is set in) as the page threshold clears the
    /// page's: a line the document's own body would not raise heads nothing on a page too bare to say
    /// otherwise. A page that establishes its body keeps its own measure.
    static func documentHeadingFloor(_ lines: [TextLine], documentBody: CGFloat?) -> CGFloat {
        guard let documentBody, establishedBodySize(lines) == nil else { return 0 }
        return documentBody * 1.1
    }

    /// `noteChapter` is the chapter named by this page's `NOTES TO CHAPTER N` running head,
    /// retained before furniture removal; nil for pages without one. `noteLastChapter` is the
    /// second chapter a `NOTES TO CHAPTERS N-M` head names. `continuesNote` states
    /// that the previous page ended in a page-bottom footnote, so a marker-less note under
    /// this page's separator may continue it. `labelStyles` is the book's section-label
    /// typography (`labelStyles(from:)`), and `headingStyles` its recurring heading-size
    /// typography (`headingEvidence(on:)`). `continuingNoteList` is the previous page's open list
    /// inside a numbered note, which this page may resume; `noteLayout` receives this page's
    /// numbered-note layout (nil when the page is not a notes page), so the caller can pass its
    /// open list and last note to the next page. `continuingNote` is the previous page's last note,
    /// which the lines above this page's first note start may continue (#11). `slideDeck` says the
    /// document reads as a deck (`isSlide(_:)`), so this page's slide title, if it has one, is a
    /// heading and nothing set smaller than it is (#165). `documentBody` is the size most of the
    /// document's native text is set in (`documentBodySize`), for a page too bare to state its own (#186).
    static func blocks(page: PageContent, images: [(CGRect, String)], vocabulary: Set<String>,
                       warnings: inout [ConversionWarning], noteChapter: Int? = nil,
                       noteLastChapter: Int? = nil, continuingNoteList: NumberedNoteDetector.OpenList? = nil,
                       noteLayout reportNoteLayout: ((NumberedNoteDetector.Layout?) -> Void)? = nil,
                       continuingNote: NumberedNoteDetector.Layout.Note? = nil,
                       continuesNote: Bool = false,
                       labelStyles: Set<LabelStyle> = [], headingStyles: Set<LabelStyle> = [],
                       neighbouringMarkers: [PageMarker] = [],
                       slideDeck: Bool = false,
                       imageKinds: [String: PreservedImageKind] = [:],
                       imageCaptions: [String: String] = [:], bookWraps: [Int: CGFloat] = [:],
                       documentBody: CGFloat? = nil) -> [ReflowBlock] {
        let body = max(4, bodySize(page.lines))
        // A rotated stamp in the outer margin is furniture, never content or a heading.
        let stamps = rotatedMarginLines(page)
        if !stamps.isEmpty {
            warnings.append(.init(code: .furnitureRemoved, page: page.number,
                message: "Rotated margin text is omitted from the reflowed text."))
        }
        // A caption's brace set as a column of bracket glyphs is decoration (#152).
        let braces = bracketColumns(in: page.lines)
        let lines = page.lines.filter { line in
            !stamps.contains(line) && !braces.contains { $0.contains(line) } && !images.contains { $0.0.intersects(line.rect) }
        }
        let shaded = ShadedTableDetector.tables(in: page, lines: lines)
        let shadedLines = shaded.flatMap(\.ownedLines)
        let borderless = shaded + BorderlessTableDetector.tables(in: lines.filter { !shadedLines.contains($0) })
        let borderlessLines = borderless.flatMap(\.ownedLines)
        // Tables of aligned columns under a header, without rules, bands or capital headings (#150).
        let tables = borderless + BorderlessTableDetector.alignedTables(in: lines.filter { !borderlessLines.contains($0) })
        let tableLines = tables.flatMap(\.ownedLines)
        // A marker PDFKit split from its item's text rejoins it before anything reads the lines.
        // So do the pieces of a prose row PDFKit split at an inline radical (#95), and the pieces
        // of a form's row with the ruled blanks between them (#152).
        let (free, mathMinusRows) = joinedRows(joiningMarkerPieces(joiningBlankRows(lines.filter { line in !tableLines.contains(line) },
                                                                                    blanks: page.blanks)),
                                               images: images.map(\.0), body: body)
        // A list line, except a joined prose row whose apparent marker is a minus sign (#109).
        func listLine(_ line: TextLine) -> Bool { isList(line.text) && !mathMinusRows.contains(line) }
        // The flush edge of each size, for the line-end hyphens PDFKit loses (#157). Only a native
        // page has one: a recognized line's quadrilateral is the ink Vision read, which says
        // nothing about the advance a dropped hyphen would have taken, and a synthetic layer's
        // typography is not the page's either.
        let measures = page.recognized || page.hasSyntheticTextStyle ? [:] : justifiedMeasures(free)
        // Preserve existing modest-size headings, but reject candidates within 10% of the
        // supported reflowable body size. This only narrows the original page-size heuristic.
        // Small text inside reflowed boxes and tables does not lower the body estimate, so a
        // page whose sidebar outweighs its prose keeps that prose as paragraphs (#54).
        let boxes = clusters(page.tints, distance: 4)
        let outside = free.filter { line in !boxes.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }
        let reflowBody = headingBodySize(outside, pageBody: body)
        let documentFloor = documentHeadingFloor(outside, documentBody: documentBody)
        let headingThreshold = max(body * 1.25, reflowBody * 1.1, documentFloor)
        // A heading line is wider than tall unless it is one or two characters; rotated text
        // outside the margin keeps its paragraph representation.
        func isHeadingSize(_ line: TextLine) -> Bool {
            !page.hasSyntheticTextStyle && line.fontSize >= headingThreshold && line.text.count < 200
                && (line.rect.width >= line.rect.height || line.text.count <= 2)
                && (line.text.first?.isLowercase != true || stacksWithDisplay(line))
        }
        // A title opens with a capital, a digit or a mark. A heading-size line standing alone that
        // opens in lowercase is display text that heads nothing: the magazine's cover follows its
        // 40-point `From Insects` with a 15-point `pages 2, 4-14` (#186), and the 9/11 report's cover
        // sets `official government edition`. A line stacked with another of its size, above or
        // below, is part of a title or a pull quote and keeps its size's reading.
        func stacksWithDisplay(_ line: TextLine) -> Bool {
            free.contains { other in
                other != line && other.fontSize >= headingThreshold
                    && (stacksUnderHeading(line, after: other) || stacksUnderHeading(other, after: line))
            }
        }
        // Labels are measured against the supported reflowable body, as the threshold is, so
        // small table text cannot make a page's ordinary prose read as labels.
        // A line's tag is not part of its typography, and reconstruction drops tags as it goes
        // (`structuredOrder`, the paragraph-type rule below), so compare labels without one.
        func untagged(_ line: TextLine) -> TextLine {
            var copy = line; copy.structure = nil; return copy
        }
        // An outline's section labels, ranked by their tier rather than their size (#152).
        let outline = page.hasSyntheticTextStyle || page.recognized ? [] : outlineSectionLabels(in: free.map(untagged), body: reflowBody)
        func outlineDepth(_ line: TextLine) -> Int? { outline.first { $0.line == untagged(line) }?.depth }
        // On a page too bare to state its body, a label its size alone sets apart must clear the
        // document's body as a heading must (`documentHeadingFloor`, #186); a sub-heading set at or
        // under the body keeps its own evidence of style and placement.
        let labels = sectionLabels(in: free.map(untagged), body: reflowBody,
                                   headingThreshold: headingThreshold, page: page, styles: labelStyles)
            .filter { $0.fontSize >= documentFloor || $0.fontSize < reflowBody * 1.15 }
            + boxTitles(in: free.map(untagged), page: page)
            // A two-column paper's centred small-capital sections and italic lettered subsections,
            // both set at the body's own size (#162).
            + academicSectionTitles(in: free.map(untagged), body: reflowBody, page: page)
            + outline.map(\.line)
        // Edges whose entries wrap into a hanging indent (#134): a label's second line hanging on
        // one continues its title, and a line back on the edge opens the next entry.
        let entryEdges = page.hasSyntheticTextStyle || page.recognized ? []
            : hangingEntryEdges(free.map(untagged), body: reflowBody, titles: labelStyles)
        // Edges whose one-line entries stand apart by added space instead (#181): a line back on
        // one opens the next entry as on a hanging edge. They head no titles.
        let spacedEdges = page.hasSyntheticTextStyle || page.recognized ? [] : spacedEntryEdges(free.map(untagged), body: reflowBody, bookWrap: bookWraps[wrapKey(reflowBody)])
        func continuesHangingTitle(_ line: TextLine, after previous: TextLine, heading: String) -> Bool {
            labels.contains(untagged(line)) && labels.contains(untagged(previous))
                && hangingEntryEdge(of: previous, in: entryEdges) != nil
                && stacksUnderHeading(line, after: previous, hangingIndent: true)
                && !LayoutReconstructor.endsSentence(heading) && !opensHeading(line.text)
        }
        // A line on a hanging-entry edge opens a new entry after the open paragraph's last line
        // when that line is an entry's wrapped continuation (hanging in the indent under the entry's
        // first line, which this paragraph opened on the edge or in the indent where an entry runs on
        // from the previous page, page 462; a paragraph's indented first line is no continuation,
        // Loper Bright page 8), or is itself on
        // the edge and ends early: this line's first word would have fit after it, short of the
        // edge's widest line, so the break was the author's (9/11 page 458's `Senator John McCain
        // (R-Az.)` / `Senator Joseph Lieberman (D-Conn.)`). Where two or more entries wrap on the
        // edge, a line ending an em short of the widest one is enough, as the widest line need not
        // reach the measure (page 459's `Stephen McHale, …, Transportation Security Agency` over
        // `Major General O.K. Steele`). Justified prose fills its measure. A line opening in lowercase
        // or after a line-end hyphen continues its sentence, and an entry opens with a word.
        func opensHangingEntry(_ line: TextLine, after prev: TextLine, first: TextLine?) -> Bool {
            guard !line.monospaced, !prev.monospaced, !line.text.contains("...."), !prev.text.contains("...."),
                  line.text.first(where: \.isLetter)?.isLowercase == false,
                  prev.text.last.map({ "-\u{00AD}/".contains($0) }) == false,
                  let first, first.text.contains(where: \.isLetter),
                  let edge = hangingEntryEdge(of: line, in: entryEdges + spacedEdges),
                  abs(prev.fontSize - edge.size) <= edge.size * 0.1 else { return false }
            func hangs(_ other: TextLine) -> Bool {
                other.rect.minX - edge.x >= edge.size * 0.5 && other.rect.minX - edge.x <= edge.size * 2.5
            }
            let opensOnEdge = hangingEntryEdge(of: first, in: [edge]) != nil
            if hangs(prev) { return prev != first && (opensOnEdge || hangs(first)) }
            guard opensOnEdge else { return false }
            let offset = prev.rect.minX - edge.x
            // On an edge whose entries stand apart by added space (#181), the entry is set that
            // far below the line above it; a line at the edge's own wrap continues its entry.
            if let spacing = edge.spacing, prev.rect.minY - line.rect.maxY < spacing { return false }
            guard abs(offset) <= edge.size * 0.5, let word = line.text.split(whereSeparator: \.isWhitespace).first else { return false }
            let right = free.filter { hangingEntryEdge(of: $0, in: [edge]) != nil }.map(\.rect.maxX).max() ?? prev.rect.maxX
            let wordWidth = line.rect.width * CGFloat(word.count + 1) / CGFloat(max(1, line.text.count))
            if prev.rect.maxX + wordWidth + edge.size * 0.5 <= right || edge.pairs >= 2 && prev.rect.maxX <= right - edge.size {
                return true
            }
            // Where the edge's entries only ever wrap into the indent, and two or more do (or the
            // book's titles head them), a line back on the edge is the next entry however far the
            // one above it ran: 9/11 page 463's `The Honorable Louis J. Freeh, …` is its page's
            // widest line, over `The Honorable Janet Reno, …` (#161). A line filling the page's
            // justified measure is prose, and its paragraph runs on.
            let justified = measures[Int(prev.fontSize.rounded())].map { prev.rect.maxX >= $0 - body * 0.75 } ?? false
            return (edge.pairs >= 2 || edge.titled) && edge.hangsOnly && !justified
        }
        // In a deck, this slide's title (`slideTitle`) and its body. A slide's title is decided by
        // where it stands, not by a size the slide has too few body words to establish; and once
        // the title is known, everything set smaller than it on that slide is the slide's body,
        // whatever the page's own estimate makes of it. Slides 19 and 20 of the Earthdata deck
        // hold more 10-point labels than 14-point boxes, so the boxes read 40% over the estimate
        // and became `<h5>`/`<h6>` beneath the real title (#165). A slide with no title in the
        // band (its title slide, whose title is centred on the page) keeps the ordinary rules.
        let slideTitle = slideDeck ? LayoutReconstructor.slideTitle(in: free.map(untagged), bounds: page.bounds) : []
        // The page's own typography for a heading, before any tag is consulted. A contents entry
        // is never a heading; a multi-line display sentence is a pull quote (handled below).
        // Neither is a separated margin line that opens or closes with this page's number:
        // that is a running head, whatever furniture removal made of it (#62).
        func headingTypography(_ line: TextLine) -> Bool {
            if let title = slideTitle.first {
                if slideTitle.contains(untagged(line)) { return true }
                if line.fontSize < title.fontSize * 0.95 { return false }
            }
            return (isHeadingSize(line) || labels.contains(untagged(line)))
                && !isContentsEntry(line.text) && !isHeaderLike(line, in: page, bothBands: true)
        }
        // A section icon reads in its heading's row (#117). DGA pages 3–6 set a circular photo in
        // the margin beside each section title, taller than the title: it reaches into the last
        // line of the section above and the first bullets below, closes the whitespace between
        // sections, and the columns interleave. A region holding no text, set within two bodies
        // left of a heading-size line whose middle it spans and no taller than three such lines,
        // is ordered at the uppermost such line's height. The image itself is unchanged.
        func readingRect(ofRegion rect: CGRect) -> CGRect {
            guard !free.contains(where: { $0.rect.intersects(rect) }) else { return rect }
            let titles = free.filter { line in
                isHeadingSize(line) && line.rect.minX >= rect.maxX && line.rect.minX - rect.maxX <= body * 2
                    && line.rect.midY > rect.minY && line.rect.midY < rect.maxY && rect.height <= line.rect.height * 3
            }
            guard let title = titles.max(by: { $0.rect.maxY < $1.rect.maxY }) else { return rect }
            return CGRect(x: rect.minX, y: title.rect.minY, width: rect.width, height: title.rect.height)
        }
        let spatial = boxed(free.map { Element(rect: $0.readingRect ?? $0.rect, line: $0) }
            + braces.map { Element(rect: union($0.map(\.rect)), boundary: true) }
            + images.map { Element(rect: readingRect(ofRegion: $0.0), image: $0.1) }
            + tables.enumerated().map { Element(rect: $0.element.ownedLines.map(\.rect).reduce($0.element.bounds) { $0.union($1) }, table: $0.offset) },
            tints: page.tints, bodySize: body)
        // A line runs on into the line beneath it: set directly below at ordinary leading on the
        // same left edge in the same type, neither a heading, a list item nor a leader entry, and
        // filling the page's justified measure, with evidence that no paragraph ends between them.
        // Tags that split one paragraph at such a line describe the source's text frames, not the
        // author's paragraphs (FAA page 211 tags `…in the AFM/` and `POH. These airspeeds
        // include:` as two paragraphs, page 105 `…upon stability.` and `The allowable location of
        // the CG…`; #75).
        //
        // `opening` says the upper line is its block's only line so far. Such a line may be a
        // paragraph's indented first line (Our Flag tags each line of page 12's quotations as its own
        // paragraph, `“A thoughtful mind when it sees a nation's flag, sees not the` set two ems in
        // from `flag, but the nation itself.`; #147): indented by up to three bodies past the lower
        // line, opening with a capital, reading as words, reaching the right edge at least three
        // lines on the lower line's edge share, and continued by a lowercase letter or after a
        // hyphen or slash.
        func wraps(_ upper: TextLine, onto lower: TextLine, opening: Bool = false) -> Bool {
            let size = max(upper.fontSize, lower.fontSize)
            let gap = upper.rect.minY - lower.rect.maxY
            let indent = upper.rect.minX - lower.rect.minX
            if opening, indent > size * 0.5 {
                guard indent <= body * 3, opensWithCapital(upper), upper.readingRect == nil, !headingTypography(upper), isWordy(upper.text),
                      lower.text.first(where: \.isLetter)?.isLowercase == true
                        || upper.text.last.map({ "-/\u{00AD}".contains($0) }) == true else { return false }
                guard free.filter({ abs($0.rect.minX - lower.rect.minX) <= body * 0.5 && abs($0.rect.maxX - upper.rect.maxX) <= body * 0.5 })
                        .count >= 3, lower.rect.maxX <= upper.rect.maxX + body * 0.5 else { return false }
                // The pair must otherwise wrap as two lines on one edge do.
                var aligned = upper
                aligned.rect.origin.x = lower.rect.minX
                aligned.rect.size.width = upper.rect.maxX - lower.rect.minX
                return wraps(aligned, onto: lower)
            }
            guard !sameRow(upper.rect, lower.rect), abs(upper.rect.minX - lower.rect.minX) <= size * 0.5,
                  abs(upper.fontSize - lower.fontSize) <= size * 0.15, gap > -size * 0.4, gap < size * 0.4,
                  !isList(lower.text),
                  !upper.text.contains("..."), !lower.text.contains("..."),
                  LabelStyle(upper, body: body).bold == LabelStyle(lower, body: body).bold,
                  !headingTypography(upper), !headingTypography(lower), upper.rect.width >= body * 12,
                  // Both lines are set as prose: a table row spreads a few characters over the
                  // measure (FAA page 416's `Compass Locator  Under 25  15`, 0.9 em a character,
                  // where a loosely justified line of text sets about half that).
                  [upper, lower].allSatisfy({ $0.rect.width <= CGFloat($0.text.count) * size * 0.7 })
            else { return false }
            // The upper line reaches its column's right edge, and that measure is the page's
            // justified measure (three other lines set to it): a title, a ragged list entry or a
            // short report line does not run on.
            let column = free.filter { abs($0.rect.minX - upper.rect.minX) <= body * 0.5 }.map(\.rect.maxX).max() ?? upper.rect.maxX
            let measure = free.filter { $0 != upper && abs($0.rect.width - upper.rect.width) <= body * 0.75 }
            guard upper.rect.maxX >= column - body * 0.75, measure.count >= 3 else { return false }
            // Continuation evidence: the lower line's first letter is lowercase (past an opening
            // bracket: `(bottom) are examples…`), or the upper line breaks at a hyphen or a slash.
            if lower.text.first(where: \.isLetter)?.isLowercase == true
                || upper.text.last.map({ "-/\u{00AD}".contains($0) }) == true { return true }
            // Otherwise the next line continues the paragraph only where the column marks
            // paragraphs with space, so ordinary leading is itself evidence (FAA page 342: `…against
            // you.` / `Runway holding position markings consist…`). A list set at even leading (FAA's
            // acronyms, page 462) has no such space.
            let edge = free.filter { abs($0.rect.minX - upper.rect.minX) <= body * 0.5
                && abs($0.fontSize - upper.fontSize) <= upper.fontSize * 0.1 }
                .sorted { $0.rect.minY > $1.rect.minY }
            let spaced = zip(edge, edge.dropFirst()).filter { above, below in
                let gap = above.rect.minY - below.rect.maxY
                return gap >= upper.fontSize * 0.6 && gap <= upper.fontSize * 2.5
            }
            if spaced.count >= 2 { return true }
            // Or the column is justified and sets space somewhere on its edge: most of its lines end
            // at its right edge, so a line that fills the measure and a line on the same edge at
            // ordinary leading read as one block of text, whatever sentence opens the lower line,
            // in a column that shows its breaks with space (FAA page 96's `…affected portion of the
            // airfoil.` / `Manufacturers have developed…`, whose only space sets off `A Third
            // Dimension`; #89). A ragged list (the acronyms) reaches that edge only with its longest
            // entries, and a column with no space at all leaves the tags as the only evidence.
            let justified = edge.filter { $0.rect.maxX >= column - body * 0.75 }
            let sameEdge = free.filter { abs($0.rect.minX - upper.rect.minX) <= body * 0.5 }.sorted { $0.rect.minY > $1.rect.minY }
            let spacedAtAll = zip(sameEdge, sameEdge.dropFirst()).contains { above, below in
                let gap = above.rect.minY - below.rect.maxY
                return gap >= upper.fontSize * 0.6 && gap <= upper.fontSize * 2.5
            }
            return edge.count >= 6 && justified.count * 2 > edge.count && spacedAtAll
        }
        var elements = structuredOrder(spatial, page: page.number, warnings: &warnings,
                                       headingTypography: headingTypography, wraps: { wraps($0, onto: $1) })
        // A validated `P` settles grouping and reading order, not typography. Sources tag their
        // own section titles as ordinary paragraphs (the Fed's `Contents`, the FAA handbook's
        // `History of Flight`), and reading the tag literally would silently drop a navigation
        // entry that every untagged page of the same book keeps. A paragraph group set entirely
        // in heading type therefore keeps its spatial reading, but only where it introduces
        // something: the next text in its own column is ordinary text that starts no further left
        // than the group does, as a section title and the body beneath it share a column edge.
        // (The next line in reading order can belong to the other column where untagged text
        // below falls back to spatial order, as on FAA page 194.) A cover title's publication
        // label (the Fed's `PUBLIC EDUCATION & OUTREACH`) is followed by the title itself, and a
        // title page's centred imprint (Our Flag's `JOINT COMMITTEE ON PRINTING`, 61 points right
        // of the line under it) heads nothing: both stay the paragraphs they are tagged as (#67).
        // A group that reads as a multi-line display sentence is a pull quote, not a title, even
        // above the text it introduces (the Fed's chapter openers, above each chapter's contents;
        // #72): its validated paragraph stands, as the spatial pull-quote rule would read it.
        // The book's own typography is evidence too. A group set entirely in a heading or label
        // style the book repeats on three or more pages is a title wherever it stands, even
        // directly above another heading: FAA tags each chapter opener's `Chapter 4` and
        // `Principles of Flight` as paragraphs over the `Introduction` heading (#84). A title
        // page's one-off imprint (Our Flag) and a cover's publication label (the Fed) are set in
        // no recurring style, so they still need the column test.
        //
        // A heading tag is not taken literally either where the page's own tags and typography
        // contradict it: a group set no larger than the page's body text, in the type of the page's
        // paragraph-tagged text, that closes a sentence or opens lowercase is a paragraph. The NASA
        // Word paper tags eight of its page-19 references, a DOI line and a wrapped reference line
        // as `H1` (`[16] NASA Space Vehicle Design Criteria, …, November 1965.`, `doi: 10.1016/…`),
        // among references in the same 9-point type tagged `P` (#154). Our Flag's body-size bold
        // `§174. Time and occasions for display` closes no sentence and stays a heading, and a
        // heading tag with no paragraph in its type on the page keeps its identity.
        let paragraphTypes = Set(elements.compactMap { element -> LabelStyle? in
            guard let line = element.line, line.structure?.headingLevel == 0 else { return nil }
            return LabelStyle(line, body: reflowBody)
        })
        for (_, indices) in Dictionary(grouping: elements.indices.filter({ (elements[$0].line?.structure?.headingLevel ?? 0) > 0 }),
                                       by: { elements[$0].line!.structure!.group }) {
            let lines = indices.sorted().map { elements[$0].line! }
            let text = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard !page.hasSyntheticTextStyle, lines.allSatisfy({ $0.fontSize <= reflowBody * 1.05
                      && paragraphTypes.contains(LabelStyle($0, body: reflowBody)) }),
                  text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) == "." && text.count >= 40
                    || text.first(where: \.isLetter)?.isLowercase == true else { continue }
            for index in indices { elements[index].line?.structure?.headingLevel = 0 }
        }
        let bookStyles = labelStyles.union(headingStyles)
        func inBookHeadingStyle(_ line: TextLine) -> Bool {
            line.text.filter(\.isLetter).count >= 2 && bookStyles.contains(LabelStyle(line, body: reflowBody))
        }
        let introduces = Set(Dictionary(grouping: elements.indices.filter {
            elements[$0].line?.structure?.headingLevel == 0
        }, by: { elements[$0].line!.structure!.group }).compactMap { group, indices -> Int? in
            let lines = indices.sorted().map { elements[$0].line! }
            guard lines.allSatisfy(headingTypography),
                  pullQuoteLines(in: lines, candidates: { _ in true }).count < lines.count else { return nil }
            if lines.allSatisfy(inBookHeadingStyle) { return group }
            guard let last = indices.max(),
                  let left = lines.map({ $0.rect.minX }).min(), let right = lines.map({ $0.rect.maxX }).max(),
                  let next = elements[(last + 1)...].lazy.compactMap(\.line)
                    .first(where: { $0.rect.minX < right && $0.rect.maxX > left }),
                  left <= next.rect.minX + body else { return nil }
            // A page title stacked over a smaller section title on its edge introduces that section
            // (DGA page 7's `Special Populations & Considerations` over `Infancy & Early Childhood`,
            // whose band crop hid it until #111). A label over a larger title (the Fed's cover) does not.
            if headingTypography(next) {
                guard let smallest = lines.map(\.fontSize).min(), next.fontSize <= smallest * 0.9,
                      abs(next.rect.minX - left) <= body else { return nil }
            }
            return group
        })
        // A paragraph group can also be a title that the page's own label test cannot see, because
        // that test asks for body text directly beneath a body-size label: FAA page 27 stacks
        // `Pilot and Aeronautical Information` over `Notices to Airmen (NOTAMs)`, page 54 sets
        // `PAVE Checklist: Identify Hazards and Personal` / `Minimums` over two lines, and the
        // chapter openers set `Introduction` right under the chapter title. The tag already makes the
        // line its own element, so the evidence left to find is that the element is a title (#90):
        // - every line is set in bold in a heading or label style the book repeats, and the group
        //   reads as a title (a capital first, no closing punctuation, no list marker or leader); or
        // - it is one line in the body's size set wholly in italic, in title case, over a wider
        //   body-text line on its own left edge or over the list it heads (#97), with space or
        //   another title above it: the FAA's lowest title level (`Likelihood of an Event`,
        //   `Coupled Ailerons and Rudder`, page 48's `Airport` over its bullets). An italic
        //   sentence, quotation or caption fragment ends in punctuation or is not in title case.
        // Such a group is emitted as a heading in tag order, ranked by its size (see `flushTagged`).
        func readsAsTitle(_ lines: [TextLine]) -> Bool {
            let text = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard (1...3).contains(lines.count), text.count < 150, text.filter(\.isLetter).count >= 2,
                  let first = text.first(where: { !"([\u{201C}\"'".contains($0) }), first.isUppercase || first.isNumber,
                  let last = text.last, !".,;:!?".contains(last) else { return false }
            // A contents page's chapter label heads leader entries (`Introduction To Flying.....1-1`,
            // whose chapter-prefixed folio `isContentsEntry` does not read), and a table's header
            // row spreads a few words over its width (`Class  (Watts)  (Miles)`).
            guard !lines.contains(where: { $0.text.contains("....") || $0.rect.width > CGFloat($0.text.count) * $0.fontSize * 0.7 }),
                  let lowest = lines.min(by: { $0.rect.minY < $1.rect.minY }) else { return false }
            let beneath = free.filter { $0.rect.maxY <= lowest.rect.minY + body * 0.4 && $0.rect.minX < lowest.rect.maxX
                && $0.rect.maxX > lowest.rect.minX }.max { $0.rect.maxY < $1.rect.maxY }
            // The entry beneath can wrap before its leader (`Performance Data for Cessna Model 172R` /
            // `and Challenger 605.....A-1`): its whole group counts.
            if let beneath, free.contains(where: { other in
                (other == beneath || other.structure != nil && other.structure?.group == beneath.structure?.group)
                    && other.text.contains("....")
            }) { return false }
            return !lines.contains { isList($0.text) || isContentsEntry($0.text) || isHeaderLike($0, in: page, bothBands: true) }
        }
        func wholly(_ line: TextLine, _ trait: TextStyle) -> Bool {
            line.content.elements.allSatisfy { element in
                guard case let .text(value, style) = element else { return true }
                return style.contains(trait) || value.allSatisfy(\.isWhitespace)
            }
        }
        func setsItalicTitle(_ line: TextLine) -> Bool {
            guard wholly(line, .italic), abs(line.fontSize - reflowBody) <= reflowBody * 0.1, isTitleCase(line.text),
                  !isCaption(line.text) else { return false }
            let column = free.filter { $0.rect.minX < line.rect.maxX && $0.rect.maxX > line.rect.minX && !sameRow($0.rect, line.rect) }
            // Beneath it, body text on its own edge or a list it heads (FAA page 48's `Airport`; #97).
            guard let below = column.filter({ $0.rect.maxY <= line.rect.minY + body * 0.4 }).max(by: { $0.rect.maxY < $1.rect.maxY }),
                  line.rect.minY - below.rect.maxY < body * 0.8, abs(below.fontSize - reflowBody) <= reflowBody * 0.1,
                  !wholly(below, .italic), !wholly(below, .bold),
                  abs(below.rect.minX - line.rect.minX) <= body * 0.5 && below.rect.width > line.rect.width && !isList(below.text)
                    || opensListBeneath(below, title: line, body: body) else { return false }
            guard let above = column.filter({ $0.rect.minY >= line.rect.maxY - body * 0.25 }).min(by: { $0.rect.minY < $1.rect.minY })
            else { return true }
            return above.rect.minY - line.rect.maxY >= body * 0.5 || wholly(above, .bold) || headingTypography(above)
        }
        let taggedTitles = Set(Dictionary(grouping: elements.indices.filter {
            elements[$0].line?.structure?.headingLevel == 0
        }, by: { elements[$0].line!.structure!.group }).compactMap { group, indices -> Int? in
            guard !introduces.contains(group) else { return nil }
            let lines = indices.sorted().map { elements[$0].line! }
            // A section title is set flush left. A title centred over the body text of its column is a
            // table's or display's title (`NONDIRECTIONAL RADIO BEACON (NDB)` on FAA page 416, 16 points
            // in from the column edge and centred on the prose line above it).
            guard readsAsTitle(lines), !free.contains(where: { other in
                !sameRow(other.rect, lines[0].rect) && abs(other.fontSize - reflowBody) <= reflowBody * 0.1
                    && !wholly(other, .bold) && lines[0].rect.minX - other.rect.minX > body
                    && abs(lines[0].rect.midX - other.rect.midX) <= body
            }) else { return nil }
            if lines.allSatisfy({ inBookHeadingStyle($0) && wholly($0, .bold) && $0.fontSize >= reflowBody * 0.95 }) {
                return group
            }
            return lines.count == 1 && setsItalicTitle(untagged(lines[0])) ? group : nil
        })
        if !introduces.isEmpty {
            for index in elements.indices {
                if let group = elements[index].line?.structure?.group, introduces.contains(group) {
                    elements[index].line?.structure = nil
                }
            }
        }
        // Page-bottom footnotes end the page's reading order; the body is every element
        // outside the note area, whose drawn separator, when it has one, is not emitted.
        // A running foot the document is too short to repeat can follow an unruled note
        // block (#61); it stays body text, ahead of the notes as captions and folios are.
        let footnotes = FootnoteDetector.layout(in: elements, page: page, continuesNote: continuesNote)
        let bodyElements = elements.indices.filter { index in
            guard let footnotes else { return true }
            return !footnotes.range.contains(index) && index != footnotes.separator
        }
        let noteLayout = NumberedNoteDetector.layout(in: elements, page: page, chapter: noteChapter,
            lastChapter: noteLastChapter, continuing: continuingNoteList, continuedNote: continuingNote)
        reportNoteLayout?(noteLayout)
        let noteGroups = noteLayout?.paragraphs ?? [:]
        func isHeadingCandidate(_ line: TextLine) -> Bool {
            line.structure == nil && headingTypography(line)
        }
        let quotes = pullQuoteLines(in: bodyElements.compactMap { elements[$0].line }, candidates: isHeadingCandidate)
        var result: [ReflowBlock] = []
        var note: (Int, InlineText)?
        func flushNote() {
            if let (start, text) = note {
                let key = noteLayout?.notes[start].map { NoteKey(number: $0.number, scope: .chapter($0.chapter)) }
                result.append(ReflowBlock(content: .paragraph(text), note: key, page: page.number))
            }
            note = nil
        }
        var tagged: (TextStructure, InlineText, CGFloat)?
        // The groups the open tagged block holds, and its last line (see `wraps`).
        var taggedGroups: Set<Int> = []
        var taggedLast: TextLine?
        // Whether `taggedLast` is the open tagged block's only line (`wraps`' `opening`, #147).
        var taggedOpening = false
        // The open tagged block's first line: a list item's marker line (`listEvidence`).
        var taggedFirst: TextLine?
        func flushTagged() {
            guard let (tag, text, size) = tagged else { return }
            // A paragraph group that is one rejoined list item (#81) keeps the representation
            // the same item has untagged: a preserved list line, its marker intact.
            // A paragraph group that reads as a title (`taggedTitles`) is a heading with no validated
            // level: `rankHeadingLevels` ranks it by size, as it ranks untagged headings.
            let title = tag.headingLevel == 0 && taggedTitles.contains(tag.group)
            let content: ReflowBlock.Content = title
                ? .heading(id: "heading-\(page.number)-\(result.count)", text: text, level: 2)
                : tag.headingLevel == 0
                ? ((tag.opensWithSplitMarker || opensWithPlusBullet(text.text)) && isList(text.text) ? .preformatted(text) : .paragraph(text))
                : .heading(id: "heading-\(page.number)-\(result.count)", text: text, level: tag.headingLevel)
            var block = ReflowBlock(content: content, structureGroup: tag.group, page: page.number)
            if case .preformatted = content, let first = taggedFirst {
                block.listEvidence = listEvidence(first, recognized: page.recognized || page.hasSyntheticTextStyle)
            }
            block.taggedLevel = title ? nil : tag.headingLevel
            // A tagged heading keeps its validated level, but its typography still belongs in the
            // document-wide scale: see `rankHeadingLevels`.
            if tag.headingLevel > 0 || title { block.headingSize = size }
            result.append(block)
            tagged = nil
        }
        var paragraph = InlineText()
        var previous: TextLine?
        // The open paragraph's first line, where this loop opened it (`opensHangingEntry`).
        var paragraphFirst: TextLine?
        var codeOrigin: CGFloat?
        // The vertical gap the open paragraph's last line was attached at: the leading a
        // section lead-in must exceed to read as added space (#60).
        var previousGap: CGFloat?
        // The open paragraph's opening line while it is the paragraph's only line, and whether
        // something other than its own left edge set it apart from the text above (see
        // `continuesOpening`).
        var opening: (line: TextLine, evidenced: Bool)?
        func flush() {
            if !paragraph.elements.isEmpty {
                result.append(ReflowBlock(content: .paragraph(paragraph), page: page.number))
            }
            paragraph = InlineText()
            previous = nil
            previousGap = nil
            opening = nil
            paragraphFirst = nil
        }
        // A paragraph's opening line can stand further from the column's edge than the lines it
        // wraps onto, which the same-column test (within one and a half bodies) does not admit (#147):
        // - Our Flag indents each paragraph's first line two ems (18 points at a 9-point body):
        //   `Strong evidence indicates that Francis Hopkinson of New Jersey, a` / `signer of the
        //   Declaration…` (page 7). The opening line opens with a capital, was set apart from the
        //   text above by more than its indent (a short or sentence-ending line, space, a heading, a
        //   tag or the top of the text), is indented by up to three bodies, and ends where at least
        //   three lines on the lower line's edge end, the lower line reaching no further. A hanging
        //   indent's wrapped line fails: its entry's first line runs onto it at ordinary leading, and
        //   its last line is short.
        // - Our Flag also opens each section on a drop cap (#135), whose first lines are set beside
        //   the initial, up to the initial's width in from the drop-cap line's edge
        //   (`During the night…bom` / `barded Fort McHenry…`, page 5), before the text returns to
        //   that edge below the initial. The drop-cap line carries `NativeTextReader`'s evidence
        //   (`readingRect`, the body-height row beside the initial); the lines beside it lie within
        //   the initial's depth and end on the drop-cap line's right edge.
        func continuesOpening(_ line: TextLine, after prev: TextLine) -> Bool {
            // The upper line reads as words across a measure of at least twelve bodies, as `wraps`
            // asks. A table's stub column fails (Blue Book page 142's scanned `Evaluation` over
            // `0-Balloon`, `1-Astronomical`, …, whose labels happen to end together), and so does its
            // header row (page 70's `Identification 1 2 3 4 5 6 7`, which a margin mark stretches).
            // Character density is not asked: Our Flag's pledge (page 51) justifies bold capitals
            // loosely across the measure.
            // An entry's own first line can be a list of initials rather than words (a reference's
            // authors, `[7] J. L. Rios, I. S. Smith, P. Venkatesan, D. R. Smith, V. Baskaran,`), so
            // the hanging-run path below asks only for real words on it (#162).
            let hangingEntry = line.rect.minX - prev.rect.minX >= body * 1.5
                && line.rect.minX - prev.rect.minX <= body * 4
                && hangingRun(in: free, edge: prev.rect.minX, indent: line.rect.minX, size: line.fontSize)
            guard let opening, !line.monospaced, abs(line.fontSize - prev.fontSize) <= max(line.fontSize, prev.fontSize) * 0.1,
                  prev.rect.width >= body * 12,
                  isWordy(prev.text) || hangingEntry && wordShare(prev.text).words >= 3
            else { return false }
            if opening.line.readingRect != nil {
                let cap = opening.line
                // A line beside the initial: in from the drop-cap line's edge by up to the initial's
                // width (the line's full height is the initial's), within its depth. The line above
                // fills the drop-cap line's measure.
                func beside(_ other: TextLine) -> Bool {
                    let inset = other.rect.minX - cap.rect.minX
                    return inset > body * 1.5 && inset <= cap.rect.height * 1.5 && other.rect.midY > cap.rect.minY
                }
                guard abs(prev.rect.maxX - cap.rect.maxX) <= body * 0.5 else { return false }
                if prev == cap { return beside(line) }
                return beside(prev) && abs(line.rect.minX - cap.rect.minX) <= body * 0.5
            }
            // An entry's first line on the page's hanging-entry edge (`hangingEntryEdges`, #134) runs
            // on into a line in the edge's indent, however wide the indent is against a paragraph's
            // drift: NOAA's front matter lists its staff one to an entry at ordinary leading and wraps
            // an entry 1.8 ems in (`Brooke C. Stewart, Managing Editor and Lead Science Editor, North
            // Carolina` / `State University (through July 2023)`, #181). The edge's own wrapped
            // entries are the evidence, so the opening's space is not asked; three of them share a
            // measure (below), so the pair being read is never its own evidence (a lone reading-list
            // entry under a line at ordinary leading keeps #147's answer). The
            // wrapped line carries on in words: it opens with a letter, a digit or a bracket, and
            // neither line sets arithmetic, so a form's checkbox under its question (Pro Se page 3's
            // `☐ Federal question`) and a worked example's next step beneath its annotation (Wallace
            // page 19's `2+3(5)2 Exponents`) stay apart. And the entry's first line was full: the
            // wrapped line's first word would not have fitted after it, short of the widest line on
            // the edge that has a line hanging beneath it (the entries' own measure; a running foot on
            // the edge is none of theirs), as `opensHangingEntry` asks the other way round, and that
            // measure is one three of those lines reach within a size. A poem that indents alternate
            // lines breaks them where the verse does, at no shared measure (NOAA page 5's `It is a
            // forgotten pleasure, the pleasure` / `of the unexpected blue-bellied lizard`), and each
            // stays a line of its own.
            if opening.line == prev, prev.readingRect == nil, let edge = hangingEntryEdge(of: prev, in: entryEdges),
               abs(line.fontSize - edge.size) <= edge.size * 0.1,
               line.text.first.map({ $0.isLetter || $0.isNumber || $0 == "(" }) == true,
               ![prev.text, line.text].contains(where: { $0.rangeOfCharacter(from: Self.arithmetic) != nil }),
               line.rect.minX - edge.x >= max(body * 1.5, edge.size * 0.5), line.rect.minX - edge.x <= edge.size * 2.5,
               let word = line.text.split(whereSeparator: \.isWhitespace).first {
                func hangsBeneath(_ upper: TextLine) -> Bool {
                    free.contains { lower in
                        let indent = lower.rect.minX - edge.x, gap = upper.rect.minY - lower.rect.maxY
                        return indent >= edge.size * 0.5 && indent <= edge.size * 2.5 && gap >= -edge.size * 0.4
                            && gap < edge.size * 0.9 && abs(lower.fontSize - edge.size) <= edge.size * 0.1
                            && lower.rect.minX < upper.rect.maxX
                    }
                }
                let full = free.filter { hangingEntryEdge(of: $0, in: [edge]) != nil && hangsBeneath($0) }.map(\.rect.maxX)
                let right = full.max() ?? prev.rect.maxX
                let wordWidth = line.rect.width * CGFloat(word.count + 1) / CGFloat(max(1, line.text.count))
                if full.filter({ $0 >= right - edge.size }).count >= 3,
                   prev.rect.maxX + wordWidth + edge.size * 0.5 > right { return true }
            }
            guard opening.evidenced, opening.line == prev, prev.readingRect == nil else { return false }
            // At least three lines on `edge`'s left edge end where the opening line does: it fills
            // that measure.
            func fillsMeasure(onEdgeOf edge: TextLine) -> Bool {
                free.filter { abs($0.rect.minX - edge.rect.minX) <= body * 0.5 && abs($0.rect.maxX - prev.rect.maxX) <= body * 0.5 }
                    .count >= 3 && line.rect.maxX <= prev.rect.maxX + body * 0.5
            }
            let indent = prev.rect.minX - line.rect.minX
            if indent >= body * 1.5, indent <= body * 3 {
                return opensWithCapital(prev) && fillsMeasure(onEdgeOf: line)
            }
            // The converse, a hanging indent: an entry's first line on the edge and its wrapped lines
            // up to three bodies in (Our Flag's reading list, pages 53 and 54: `Manning, John R. The
            // Story of Old Glory. Phoenix, AZ: Continuing Education` / `Institute, 1971.`). The entries
            // are set apart by space, so the gap above the first line exceeds the leading beneath it
            // by at least 0.4 body; an indented paragraph or quotation under a full line has no
            // such space above that line.
            guard -indent >= body * 1.5, -indent <= body * 4, fillsMeasure(onEdgeOf: prev) else { return false }
            // A list whose entries are set with no space between them shows its hanging indent in
            // the runs of wrapped lines instead (IEEEtran's references and algorithm steps, #162).
            if hangingEntry { return true }
            guard -indent <= body * 3 else { return false }
            let leading = prev.rect.minY - line.rect.maxY
            guard let above = free.filter({ $0 != prev && !sameRow($0.rect, prev.rect) && $0.rect.minY >= prev.rect.maxY - body * 0.4
                && $0.rect.minX < prev.rect.maxX && $0.rect.maxX > prev.rect.minX }).min(by: { $0.rect.minY < $1.rect.minY })
            else { return false }
            return above.rect.minY - prev.rect.maxY >= leading + body * 0.4
        }
        // A wrapped body line can begin with an initial, a citation abbreviation or a year
        // followed by a period. It continues the open paragraph only when the previous line
        // fills its column without terminal punctuation, this line sits on the column's
        // majority left edge (or outdents from an indented opening line) with ordinary line
        // spacing, and at least three same-size lines establish the column's right edge.
        // Genuine list items follow short, terminal or separated lines, or open a block of their own.
        func continuesParagraph(_ line: TextLine, lonely: Bool) -> Bool {
            guard let prev = previous, prev.wraps != false, !paragraph.elements.isEmpty,
                  line.text.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression) != nil else { return false }
            let verticalGap = prev.rect.minY - line.rect.maxY
            guard verticalGap >= -body * 0.4, verticalGap < body * 0.9 else { return false }
            let indent = prev.rect.minX - line.rect.minX
            guard indent > -body * 0.5, indent < body * 1.5 else { return false }
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard let ending = prev.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?:;".contains(ending) else { return false }
            // The previous line reads as prose; exercise or formula lines mostly carry symbols.
            let words = prev.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count
            guard words >= 3 else { return false }
            let size = Int(line.fontSize.rounded())
            let column = lines.filter {
                !$0.monospaced && Int($0.fontSize.rounded()) == size && abs($0.rect.minX - line.rect.minX) < body * 1.5
            }
            // The candidate sits on the column's majority left edge, so an indented note or
            // hanging list marker beside dedented continuations does not qualify.
            let onEdge = column.filter { abs($0.rect.minX - line.rect.minX) < body * 0.5 }.count
            guard onEdge * 2 > column.count, column.count >= 3 else { return false }
            // A justified column: at least three lines agree on the right edge, and the previous
            // line reaches it. The edge is the one most lines share within half a body of the
            // furthest, not the furthest itself: the 9/11 report sets some lines 2.9 points past
            // its measure (pages 179, 206, 215, 229; #146). Ragged item lengths do not establish
            // a margin.
            let furthest = column.map(\.rect.maxX).max() ?? prev.rect.maxX
            let right = column.map(\.rect.maxX).filter { $0 >= furthest - body * 0.5 }.max { a, b in
                let shareA = column.filter { abs($0.rect.maxX - a) <= body * 0.25 }.count
                let shareB = column.filter { abs($0.rect.maxX - b) <= body * 0.25 }.count
                return shareA != shareB ? shareA < shareB : a < b
            } ?? furthest
            let justified = column.filter { $0.rect.maxX >= right - body * 0.25 }
            if justified.count >= 3 && prev.rect.maxX >= right - body * 0.25 { return true }
            // A marker no other marker on the page continues (`1913.` after `…the Federal Reserve
            // was established in`, Fed page 92's ragged column) is no list's item: the previous
            // line need only run most of the column's measure, as a wrapped prose line does.
            guard lonely, let measure = column.map(\.rect.width).max() else { return false }
            return prev.rect.width >= measure * 0.75
        }
        // A numbered or lettered marker that no other marker on the page continues (no neighbour
        // one or two away in the same kind, punctuation and type size) belongs to no list.
        // The previous and next pages' markers count, so a list broken by the page keeps its items.
        let pageMarkers: [(line: TextLine?, marker: PageMarker)] = free.compactMap { line in
            ListMarker(line.text).map { (line, PageMarker(marker: $0, fontSize: line.fontSize)) }
        } + neighbouringMarkers.map { (nil, $0) }
        func isLonely(_ line: TextLine) -> Bool {
            guard let marker = ListMarker(line.text) else { return false }
            return !pageMarkers.contains { other in
                other.line != line && other.marker.marker.isSibling(of: marker)
                    && abs(other.marker.fontSize - line.fontSize) <= line.fontSize * 0.1
            }
        }
        // A lonely marker line that runs on into the line directly beneath it, on its own left
        // edge, is a paragraph's opening line: a list item's text wraps past its marker. The
        // marker line leaves its sentence open and runs most of its column's measure, and the
        // line beneath, at ordinary leading in the same type, opens no list of its own (9/11 page
        // 288's `2000. They decided that if Mihdhar was in the United States, he should be` over
        // `found.`; FAA page 18's `P. E. Fansler, a Florida businessman…`; #146). A title such as
        // `3. Quantum Description` is short and does not run on.
        func runsOnFlush(_ line: TextLine) -> Bool {
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard let ending = line.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?:;".contains(ending), line.text.split(whereSeparator: { !$0.isLetter }).filter({ $0.count >= 2 }).count >= 3
            else { return false }
            let beneath = free.filter { other in
                other != line && other.rect.maxY <= line.rect.minY + body * 0.4
                    && other.rect.minX < line.rect.maxX && other.rect.maxX > line.rect.minX
            }.max { $0.rect.maxY < $1.rect.maxY }
            guard let next = beneath, !isList(next.text), !next.monospaced,
                  abs(next.rect.minX - line.rect.minX) <= body * 0.5,
                  abs(next.fontSize - line.fontSize) <= line.fontSize * 0.1 else { return false }
            let gap = line.rect.minY - next.rect.maxY
            guard gap >= -body * 0.4, gap < body * 0.9 else { return false }
            let measure = free.filter { abs($0.rect.minX - line.rect.minX) <= body * 0.5
                && abs($0.fontSize - line.fontSize) <= line.fontSize * 0.1 }.map(\.rect.width).max() ?? 0
            return line.rect.width >= measure * 0.75
        }
        // Whether a marker line reads as prose rather than a list item.
        func readsAsProse(_ line: TextLine) -> Bool {
            let lonely = isLonely(line)
            return continuesParagraph(line, lonely: lonely) || lonely && !line.monospaced && runsOnFlush(line)
        }
        // PDFKit can drop the space after a numbered marker (`10.August 2001: …` among spaced
        // items 6 to 9 on 9/11 page 374). Such a line opens a list item only when a capital
        // letter follows the period, at least two spaced numbered items share its left edge and
        // size on this page, and its number is next to one of theirs. Decimals (`3.5 percent`),
        // section numbers (`1.1 INSIDE`) and times (`10.30`) never qualify, and a note run
        // (`5.This`) has already claimed its lines (#69).
        let spacedMarkers: [(line: TextLine, number: Int)] = free.compactMap { line in
            guard !line.monospaced, let end = line.text.range(of: "^[0-9]{1,3}\\.\\s", options: .regularExpression),
                  let number = Int(line.text[end].dropLast(2)) else { return nil }
            return (line, number)
        }
        func isTightMarker(_ line: TextLine) -> Bool {
            guard !line.monospaced, let end = line.text.range(of: "^[0-9]{1,3}\\.\\p{Lu}", options: .regularExpression),
                  let number = Int(line.text[end].dropLast(2)) else { return false }
            let siblings = spacedMarkers.filter {
                abs($0.line.rect.minX - line.rect.minX) <= body * 0.5 && abs($0.line.fontSize - line.fontSize) <= line.fontSize * 0.1
            }
            return siblings.count >= 2 && siblings.contains { $0.number == number - 1 || $0.number == number + 1 }
        }
        // An inline expression makes its line's rectangle taller than the page's ordinary line of
        // that size, above the type (a radical's bar) or below it (Wallace's minus and times glyphs
        // drop the rectangle 8.5 points), so that line overlaps its neighbour by more than tight
        // leading does (#109). The extra height counts for a line set as prose on its paragraph's
        // measure (`isProseRow`); a derivation's stacked terms and annotations are not, and a
        // rectangle more than twice the ordinary height is a display, not an inline expression.
        //
        // A list item's lines are set on the item's own measure, not the paragraph's, so for them
        // `listText` also accepts a line that reads as a sentence (Wallace page 2's `− Your fair
        // dealing or fair use rights, …`, whose measure only one other line shares, #115). An
        // exercise row of terms is still not.
        func extraHeight(_ line: TextLine, listText: Bool = false) -> CGFloat {
            guard let ordinary = ordinaryLineHeight(line.fontSize, in: lines),
                  line.rect.height > ordinary + body * 0.25,
                  line.rect.height <= ordinary * 2 else { return 0 }
            let readsAsItemText = listText && isWordy(line.text) && readsAsSentence(line.text)
            guard readsAsItemText || isProseRow(line, in: free, body: body) else { return 0 }
            return line.rect.height - ordinary
        }
        // A list item's marker line opens the item; its wrapped lines are set in the hanging
        // indent under the item's text, at ordinary line spacing and no larger than the item.
        // The item closes at the next marker, a paragraph gap, a dedent to the marker's edge,
        // a heading, an image, a table or a box edge, each of which another branch takes
        // first, so this line joins the open item instead of opening a paragraph (#50, #64).
        var listGaps: [Int: CGFloat?] = [:]
        func listGap(_ size: CGFloat) -> CGFloat? {
            let key = Int((size * 10).rounded())
            if let known = listGaps[key] { return known }
            let gap = ordinaryLineGap(size, in: lines, body: body)
            listGaps[key] = gap
            return gap
        }
        // An item nested under another, marked by a dash the page repeats on its own edge. The
        // IEEEtran paper sets `– Only four types of aircraft…` under `• Parameters affecting air
        // traffic:` at 1.76 bodies, inside the width a marker occupies, while that bullet's own
        // wrapped lines stand at 2.86 (#180). `isList` reads a minus and a hyphen as markers but
        // not a dash, and the paper's dash items are paragraphs, so the evidence is the page
        // itself: another line on this edge, in this type, opening with the same dash and a space.
        func opensRepeatedDashItem(_ line: TextLine) -> Bool {
            func opensWithDash(_ text: String) -> Character? {
                guard let dash = text.first, "\u{2013}\u{2014}\u{2012}\u{2015}".contains(dash),
                      text.dropFirst().first?.isWhitespace == true else { return nil }
                return dash
            }
            guard let dash = opensWithDash(line.text) else { return false }
            return free.contains { other in
                other != line && opensWithDash(other.text) == dash
                    && abs(other.rect.minX - line.rect.minX) <= 2
                    && abs(other.fontSize - line.fontSize) <= line.fontSize * 0.1
            }
        }
        func continuesListItem(_ line: TextLine, item: (marker: TextLine, last: TextLine, indent: CGFloat?, index: Int)) -> Bool {
            // A lonely marker line that reads as prose is item text too: NOAA's reference 177 wraps
            // `S. Martinuzzi, A.D. Syphard, …` at its hanging indent (#146).
            guard !listLine(line) || isLonely(line), !opensRepeatedDashItem(line),
                  line.fontSize <= item.marker.fontSize + 0.5 else { return false }
            // Where the PDF tags its lists, the tags decide (#194): a line of the open item's `LI`
            // continues it wherever it stands, and a line of another item does not.
            if let open = item.marker.listTag, let tag = line.listTag { return tag.item == open.item }
            let verticalGap = item.last.rect.minY - line.rect.maxY
            // A tall marker line (Wallace page 2's license bullets, whose rectangles stand 17 points
            // against the page's 9.9) overlaps its wrapped line as a tall prose line does (#109, #115).
            let inflation = extraHeight(item.last, listText: true) + extraHeight(line, listText: true)
            guard verticalGap >= -(body * 0.4 + inflation), verticalGap < body * 0.9 else { return false }
            // A line set off by added space under the item is a display line of its own, not more of
            // the item: Wallace page 64 sets `Three more than a number becomes x + 3` 9.7 points under
            // `writing the second part plus the first`, where its wrapped lines stand 2.4 apart
            // (#123). The evidence is the page's ordinary gap at the line's size plus half a body,
            // and a capital opening the line; the item's own text need not end a sentence, since
            // Wallace's items carry no final period.
            if let ordinary = listGap(line.fontSize), verticalGap >= ordinary + body * 0.5,
               line.text.first(where: { !"([\u{201C}\u{2018}\"'".contains($0) && !$0.isWhitespace })?.isUppercase == true {
                return false
            }
            // The wrapped line starts past the marker, within the width a marker occupies;
            // a deeper indent is nested content and a dedent ends the item.
            let indent = line.rect.minX - item.marker.rect.minX
            guard indent > body * 0.25, indent <= body * 2.5 else { return false }
            // Once a wrapped line has established the item's hanging indent, the rest of the
            // item sits on that same edge however its sentences fall (Fed page 22's council
            // entries run to several sentences under one marker). The edge is measured from the
            // first wrapped line, so PDFKit's few points of jitter cannot accumulate.
            if let edge = item.indent { return abs(line.rect.minX - edge) <= body * 0.5 }
            // The first wrapped line continues a marker line that ran out of room mid-sentence.
            // A marker line that ends one is as likely to be the whole item, leaving the
            // indented line under it to open a paragraph (Loper Bright page 64's wrapped
            // citation, whose next paragraph opens on a first-line indent).
            // A period inside a web address ends nothing (FAA page 372's `(AIM)—www.faa.` +
            // `gov/air_traffic/…`, #79).
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            guard let ending = item.last.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
                  !".!?".contains(ending) || addressContinues(item.last.text, line.text)
                    || hangsLikeSiblings(line, marker: item.marker) else { return false }
            return true
        }
        // A bulleted item's wrapped line stands where the page's other items with that bullet on
        // that edge wrap: the hanging indent is the page's, so the line continues the item even
        // after a sentence (#194). FAA page 211's `• Green arc—the normal operating range of the
        // aircraft.` wraps to `Most flying occurs within this range.`, which read as a paragraph. A
        // numbered or lettered marker has no such evidence (Loper Bright page 64's `U. S. 134
        // (1944), …` over a paragraph's first line).
        func hangsLikeSiblings(_ line: TextLine, marker: TextLine) -> Bool {
            guard let bullet = marker.text.first, "•+*-".contains(bullet),
                  marker.text.dropFirst().first?.isWhitespace == true else { return false }
            return free.contains { sibling in
                sibling != marker && sibling.text.first == bullet && sibling.text.dropFirst().first?.isWhitespace == true
                    && abs(sibling.rect.minX - marker.rect.minX) <= body * 0.5
                    && abs(sibling.fontSize - marker.fontSize) <= marker.fontSize * 0.1
                    && free.contains { wrapped in
                        wrapped != line && abs(wrapped.rect.minX - line.rect.minX) <= body * 0.5
                            && !isList(wrapped.text)
                            && wrapped.rect.minX < sibling.rect.maxX && wrapped.rect.maxX > sibling.rect.minX
                            && (-body * 0.4..<body * 0.9).contains(sibling.rect.minY - wrapped.rect.maxY)
                    }
            }
        }
        // PDFKit can detach a body note marker that falls past a justified line's right edge
        // into its own tiny line. A one-to-three digit line below body size, starting where the
        // previous line ends and sitting raised inside that line's box, is its marker. A small
        // number on the same baseline (an OCR'd table cell) is not.
        func isDetachedMarker(_ line: TextLine, after prev: TextLine) -> Bool {
            guard !paragraph.elements.isEmpty, !page.recognized, !page.hasSyntheticTextStyle,
                  (1...3).contains(line.text.count),
                  line.text.utf8.allSatisfy({ (48...57).contains($0) }),
                  line.fontSize < body * 0.8, line.rect.minX >= prev.rect.maxX - 1,
                  line.rect.minX <= prev.rect.maxX + body * 0.5 else { return false }
            return line.rect.minY >= prev.rect.minY + prev.rect.height * 0.2
                && line.rect.maxY <= prev.rect.maxY + 1
        }
        // PDFKit can also split a row at a closing quote kerned back over the period before it,
        // leaving the quote and the marker after it as a piece of their own (9/11 page 362's
        // `to routine.` and `”12`, whose marker `NativeTextReader` re-measures as raised, #11). A
        // piece of closing punctuation and one raised one-to-three digit marker, on the previous
        // line's row and starting within half a body size of its end, closes that line.
        func isDetachedQuotedMarker(_ line: TextLine, after prev: TextLine) -> Bool {
            guard !paragraph.elements.isEmpty, !page.recognized, !page.hasSyntheticTextStyle, line.structure == nil,
                  abs(line.rect.minX - prev.rect.maxX) <= body * 0.5, sameRow(line.rect, prev.rect) else { return false }
            let visible = line.content.elements.compactMap { element -> (String, TextStyle)? in
                guard case let .text(value, style) = element else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : (trimmed, style)
            }
            let closing = Set("\u{201D}\u{2019}\"')]")
            guard visible.count == 2, !visible[0].1.contains(.superscript), visible[0].0.allSatisfy(closing.contains),
                  visible[1].1.contains(.superscript), (1...3).contains(visible[1].0.count),
                  visible[1].0.utf8.allSatisfy({ (48...57).contains($0) }) else { return false }
            return true
        }
        // A bold run-in section label opens a paragraph even where the source sets less than
        // the ordinary paragraph spacing between its sections (the USGS Mineral Commodity
        // Summaries add 0.3 pt, #60). The evidence is typographic and positional together: the
        // line opens with a bold run that closes with a colon or is set in capitals, ordinary
        // text follows that label on the same line (a run-in, not a heading), the previous line
        // ends a sentence, the label starts at the column's majority left edge at body size,
        // and the source still added space — the gap is not negative and exceeds the leading
        // the paragraph has been wrapping at. Bold emphasis inside a paragraph fails all of
        // these: it follows an unfinished line, sits mid-measure and adds no space.
        func opensSection(_ line: TextLine, after prev: TextLine, gap: CGFloat, leading: CGFloat?) -> Bool {
            guard !page.hasSyntheticTextStyle, line.structure == nil, !line.monospaced,
                  abs(line.fontSize - body) <= body * 0.1,
                  gap >= 0, gap >= leading.map({ $0 + body * 0.2 }) ?? 0,
                  case let .text(value, style)? = line.content.elements.first,
                  style.contains(.bold) else { return false }
            let label = value.trimmingCharacters(in: .whitespaces)
            let letters = label.filter(\.isLetter)
            guard letters.count >= 3, label.hasSuffix(":") || letters.allSatisfy(\.isUppercase),
                  line.content.elements.dropFirst().contains(where: { element in
                      guard case let .text(rest, restStyle) = element else { return false }
                      return !restStyle.contains(.bold) && rest.contains { !$0.isWhitespace }
                  }) else { return false }
            guard endsSentence(prev) else { return false }
            // A section opens flush with the column the paragraph above it fills, so a run-in
            // label indented inside an item or a note is not one.
            return abs(prev.rect.minX - line.rect.minX) <= body * 0.5
        }
        // The sentence's own last character, past closing quotes and brackets and past a
        // raised reference marker: USGS sections end `… copper supply.5` before the next
        // lead-in, and the marker is not the sentence's punctuation.
        func endsSentence(_ prev: TextLine) -> Bool {
            let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
            for element in prev.content.elements.reversed() {
                guard case let .text(value, style) = element else { continue }
                if style.contains(.superscript), value.allSatisfy({ $0.isNumber || $0.isWhitespace }) { continue }
                if let character = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) {
                    return ".!?".contains(character)
                }
            }
            return false
        }
        // A paragraph opens on a first-line indent narrower than the drift the same-column test
        // allows (#159). *Agricultural Research* sets its columns at a ten-and-a-half point body
        // and indents each opening line ten points — under one and a half bodies — over two points
        // of added space, so the column reads as one paragraph from its first line to its last: on
        // page 9 three source paragraphs became one, and a nine-point subhead ran into the
        // paragraph beneath it.
        //
        // The indent alone is not the evidence, since a column's lines drift and a hanging indent
        // runs the other way. The page's own pattern is (`firstLineIndentRun`): the line stands at
        // least half a body inside the previous line's edge, that edge carries the column, and the
        // page sets other lines at the same indent under it, none of them twice in a row. The line
        // must also read as an opening — the same type at ordinary leading, opening with a capital
        // and holding words, not a list marker — and the line above must end a sentence, so an
        // indented continuation inside a quotation does not break its paragraph.
        func opensIndentedParagraph(_ line: TextLine, after prev: TextLine) -> Bool {
            guard !page.hasSyntheticTextStyle, !page.recognized, !line.monospaced, !prev.monospaced,
                  !isList(line.text), line.structure == nil, prev.structure == nil,
                  line.readingRect == nil, prev.readingRect == nil,
                  abs(line.fontSize - prev.fontSize) <= max(line.fontSize, prev.fontSize) * 0.1,
                  !headingTypography(line), !headingTypography(prev) else { return false }
            let indent = line.rect.minX - prev.rect.minX
            guard indent >= body * 0.5, indent < body * 1.5, endsSentence(prev),
                  isWordy(line.text), opensWithCapital(line) else { return false }
            return firstLineIndentRun(in: free, step: indent, size: line.fontSize)
        }
        // A paragraph set off by added space alone opens a paragraph even where that space falls
        // under the ordinary threshold. The USGS Mineral Commodity Summaries leave a blank line
        // between paragraphs at 11.04-point leading, but their line rectangles are 13.76 points
        // tall, so the lines of a paragraph report a gap of -2.72 points and the blank line only
        // 7.9, under `body * 0.9` (COMEX on copper page 2, #71). The evidence is measured against
        // the paragraph's own leading: the gap exceeds the gap its last line was attached at by at
        // least half the body size, the previous line ends a sentence, and this line opens with a
        // capital (past opening quotes and brackets) on the same left edge in the same type. A
        // wrapped line inside a paragraph sits at the paragraph's leading; nothing about the right
        // edge is consulted, so ragged and justified columns are read alike.
        func opensSpacedParagraph(_ line: TextLine, after prev: TextLine, gap: CGFloat, leading: CGFloat?) -> Bool {
            guard let leading, gap >= leading + body * 0.5, !line.monospaced,
                  abs(line.fontSize - prev.fontSize) <= max(line.fontSize, prev.fontSize) * 0.1,
                  abs(prev.rect.minX - line.rect.minX) <= body * 0.5,
                  line.text.first(where: { !"([\u{201C}\u{2018}\"'".contains($0) && !$0.isWhitespace })?.isUppercase == true
            else { return false }
            return endsSentence(prev)
        }
        // The open heading's first line (the row PDFKit split) and its latest line (for the
        // line stacked beneath it).
        var headingRow: (first: TextLine, last: TextLine)?
        // The list item this page's reading order has open: its marker line, its latest line
        // and the block holding it. Every other branch closes it, as `codeOrigin` closes a
        // code block.
        var listItem: (marker: TextLine, last: TextLine, indent: CGFloat?, index: Int)?
        // Coded weather reports set over several lines read as one preformatted block each (#96).
        // A run spans consecutive text lines of the body order; an image, table, boundary or note
        // between them ends it. Each member maps to the break before it: nil opens the report.
        var codedReport: [Int: Bool?] = [:]
        do {
            var segment: [Int] = []
            func findRuns() {
                for run in codedReportRuns(segment.map { elements[$0].line! }, body: body) {
                    for (offset, member) in run.enumerated() {
                        codedReport[segment[member.index]] = .some(offset == 0 ? nil : member.lineBreak)
                    }
                }
                segment = []
            }
            for index in bodyElements {
                if elements[index].line != nil, noteGroups[index] == nil { segment.append(index) } else { findRuns() }
            }
            findRuns()
        }
        for index in bodyElements {
            let element = elements[index]
            let previousHeading = headingRow
            headingRow = nil
            let openItem = listItem
            listItem = nil
            if let group = noteGroups[index], let line = element.line {
                flushTagged()
                flush()
                codeOrigin = nil
                if note?.0 != group { flushNote() }
                if let current = note {
                    note = (group, join(current.1, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings))
                } else { note = (group, line.content) }
                continue
            }
            flushNote()
            if let path = element.image {
                flushTagged()
                flush()
                codeOrigin = nil
                result.append(imageBlock(assetID: path, page: page.number,
                                         kind: imageKinds[path] ?? .artwork,
                                         sourceCaption: imageCaptions[path] ?? ""))
                continue
            }
            if let index = element.table {
                flushTagged()
                flush()
                codeOrigin = nil
                result.append(ReflowBlock(content: .table(tableBlock(tables[index], vocabulary: vocabulary,
                    page: page.number, warnings: &warnings)), page: page.number))
                continue
            }
            if element.boundary {
                flushTagged()
                flush()
                codeOrigin = nil
                continue
            }
            guard let line = element.line else { continue }
            if let member = codedReport[index] {
                flushTagged()
                flush()
                codeOrigin = nil
                if let lineBreak = member, let last = result.indices.last, case let .preformatted(text) = result[last].content {
                    var combined = text
                    combined.append(InlineText(lineBreak ? "\n" : " "))
                    combined.append(line.content)
                    result[last].content = .preformatted(combined)
                } else {
                    result.append(ReflowBlock(content: .preformatted(line.content), page: page.number))
                }
                continue
            }
            if let tag = line.structure {
                // A paragraph group can open on the line an untagged paragraph wraps onto: FAA page
                // 127 tags `…there is maximum thrust.` with text across a figure, so its group falls
                // back, and `After liftoff, …` opens the next group at ordinary leading. The wrap
                // evidence that joins two tagged groups joins these too (#89); the group's text
                // then continues the open paragraph.
                if tag.headingLevel == 0, !tag.opensWithSplitMarker, !taggedTitles.contains(tag.group), tagged == nil, !line.monospaced,
                   let prev = previous, prev.wraps != false, !paragraph.elements.isEmpty,
                   wraps(prev, onto: line, opening: opening?.line == prev && opening?.evidenced == true) {
                    tagged = (tag, join(paragraph, line.content, vocabulary: vocabulary, page: page.number,
                        warnings: &warnings), max(prev.fontSize, line.fontSize))
                    taggedGroups = [tag.group]
                    taggedLast = line
                    taggedOpening = false
                    paragraph = InlineText()
                    previous = nil
                    previousGap = nil
                    opening = nil
                    codeOrigin = nil
                    continue
                }
                flush()
                codeOrigin = nil
                if let current = tagged, !taggedGroups.contains(tag.group) {
                    // Two paragraph groups split at a wrapped line read as one paragraph.
                    if current.0.headingLevel == 0, !current.0.opensWithSplitMarker, tag.headingLevel == 0,
                       !tag.opensWithSplitMarker, !taggedTitles.contains(current.0.group), !taggedTitles.contains(tag.group),
                       let last = taggedLast, wraps(last, onto: line, opening: taggedOpening) {
                        taggedGroups.insert(tag.group)
                    } else { flushTagged() }
                }
                taggedLast = line
                taggedOpening = tagged == nil
                if tagged == nil { taggedGroups = [tag.group] }
                if let current = tagged {
                    tagged = (current.0, join(current.1, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings), max(current.2, line.fontSize))
                } else {
                    tagged = (tag, line.content, line.fontSize)
                    taggedFirst = line
                }
                continue
            }
            // The converse: an untagged line a paragraph group's last line wraps onto continues that
            // paragraph (FAA page 360's `…[Figure 14-44]` / `In addition to basic radar service, …`,
            // whose group crosses the figure beside it and falls back). The open group's text becomes
            // the spatial paragraph, and the ordinary rules below attach the line to it.
            if let current = tagged, current.0.headingLevel == 0, !current.0.opensWithSplitMarker,
               !taggedTitles.contains(current.0.group),
               let last = taggedLast, !line.monospaced, wraps(last, onto: line, opening: taggedOpening) {
                tagged = nil
                paragraph = current.1
                previous = last
                previousGap = nil
                // A group's only line opened the paragraph, and its tag set it apart.
                opening = taggedOpening ? (last, true) : nil
                paragraphFirst = nil
            }
            flushTagged()
            if !line.monospaced { codeOrigin = nil }
            if isHeadingCandidate(line), !quotes.contains(line) {
                // PDFKit splits a heading row at a wide gap (a section number and its title);
                // the pieces form one heading, as do the lines of a title set over several
                // lines (#55). The pieces of one row sit within a few ems of each other; two
                // columns' titles on one row are two headings (FAA page 340, #76).
                // An outline's label opens a section of its own (#152).
                if let row = previousHeading, let last = result.indices.last, outlineDepth(line) == nil,
                   case let .heading(id, text, level) = result[last].content,
                   sameRow(row.first.rect, line.rect) && abs(row.first.fontSize - line.fontSize) <= line.fontSize * 0.1
                    && line.rect.minX - row.last.rect.maxX <= line.fontSize * 3
                    || continuesHeading(text.text, with: line, after: row.last)
                    || continuesHangingTitle(line, after: row.last, heading: text.text)
                    // A centred title's second line, set wholly in its small capitals (#162).
                    || labels.contains(untagged(line)) && labels.contains(untagged(row.last))
                        && continuesCentredTitle(line, after: row.last)
                        && !LayoutReconstructor.endsSentence(text.text) && !opensHeading(line.text) {
                    result[last].content = .heading(id: id, text: join(text, line.content, vocabulary: vocabulary,
                        page: page.number, warnings: &warnings), level: level)
                    headingRow = (row.first, line)
                    continue
                }
                flush()
                // Level 2 until the document-wide ranking runs (`rankHeadingLevels`).
                var heading = ReflowBlock(content: .heading(id: "heading-\(page.number)-\(result.count)", text: line.content),
                    page: page.number)
                heading.headingSize = line.fontSize
                heading.outlineDepth = outlineDepth(line)
                result.append(heading)
                headingRow = (line, line)
            } else if !page.hasSyntheticTextStyle && line.monospaced {
                flush()
                if let origin = codeOrigin, let last = result.last, case let .preformatted(previousText) = last.content {
                    let indent = min(80, max(0, Int(((line.rect.minX - origin) / (line.fontSize * 0.6)).rounded())))
                    var combined = previousText
                    combined.append(InlineText("\n" + String(repeating: " ", count: indent)))
                    combined.append(line.content)
                    result[result.count - 1].content = .preformatted(combined)
                } else {
                    codeOrigin = line.rect.minX
                    result.append(ReflowBlock(content: .preformatted(line.content), page: page.number))
                }
            } else if listLine(line) || isTightMarker(line), !readsAsProse(line) {
                flush()
                // Preserve significant breaks and native styles; do not rewrite list markers or code.
                // `ListBuilder` reads the marker line's evidence once the document is complete.
                var block = ReflowBlock(content: .preformatted(line.content), page: page.number)
                block.listEvidence = listEvidence(line, recognized: page.recognized || page.hasSyntheticTextStyle)
                result.append(block)
                listItem = (marker: line, last: line, indent: nil, index: result.count - 1)
            } else if let item = openItem, continuesListItem(line, item: item),
                      case let .preformatted(text) = result[item.index].content {
                result[item.index].content = .preformatted(join(text, line.content, vocabulary: vocabulary,
                    page: page.number, warnings: &warnings))
                listItem = (marker: item.marker, last: line, indent: item.indent ?? line.rect.minX, index: item.index)
            } else {
                if let prev = previous, isDetachedMarker(line, after: prev) {
                    paragraph.append(InlineText(line.text, style: .superscript))
                    continue
                }
                if let prev = previous, isDetachedQuotedMarker(line, after: prev) {
                    paragraph.append(line.content)
                    continue
                }
                // The leading this line was attached at, for the next line's section test.
                var attachedGap: CGFloat?
                // Whether this line, should it open a paragraph, is set apart by more than its edge.
                var evidencedOpening = true
                if let prev = previous {
                    // A drop-cap line's row is its reading rectangle, not the initial's depth (#147).
                    let verticalGap = (prev.readingRect ?? prev.rect).minY - line.rect.maxY
                    // The overlap allowed grows by either line's extra height (`extraHeight`, #109).
                    // The paragraph gap above is still measured on the rectangles, and such a gap
                    // is not the paragraph's leading.
                    let inflation = extraHeight(prev) + extraHeight(line)
                    let ordinaryLeading = verticalGap >= -(body * 0.4 + inflation) && verticalGap < body * 0.9
                    evidencedOpening = !ordinaryLeading || prev.wraps == false
                        || prev.rect.maxX < line.rect.maxX - body || endsSentence(prev)
                    let sameColumn = ordinaryLeading
                        && (abs(prev.rect.minX - line.rect.minX) < body * 1.5 || continuesOpening(line, after: prev))
                    let shortEnding = prev.rect.width < line.rect.width * 0.65
                        && prev.text.last.map { ".!?".contains($0) } == true
                    // A figure caption ends where clearly larger type begins at body size or
                    // above: that line is a section title, not more caption (#63). A caption's
                    // own lines differ by less: FAA opens each with an 8-point bold label and
                    // wraps its 9-point text, and a figure-heavy page can measure a 9-point body.
                    // A line only slightly larger ends it too when it leaves the caption's
                    // alignment, sharing neither its left edge nor its centre: FAA page 159's
                    // 9-point `Figure 5-16.` caption, indented 3.5 points, over 10-point body text
                    // flush with the column (#82). Wrapped caption lines keep the caption's edge.
                    let leavesCaption = line.fontSize >= prev.fontSize * 1.05
                        && abs(line.rect.minX - prev.rect.minX) > body * 0.25
                        && abs(line.rect.midX - prev.rect.midX) > body * 0.25
                    let endsCaption = (line.fontSize >= prev.fontSize * 1.15 || leavesCaption)
                        && line.fontSize >= reflowBody * 0.95 && isCaption(paragraph.text)
                    // Notes the footnote reader did not take (DGA page 2's two columns of notes,
                    // #141) still open one paragraph each at their raised numbers.
                    let nextNote = raisedNoteNumber(line) != nil && raisedNoteNumber(paragraph) != nil
                    if prev.wraps == false || !sameColumn || shortEnding || endsCaption || nextNote
                        || opensIndentedParagraph(line, after: prev)
                        || opensSection(line, after: prev, gap: verticalGap, leading: previousGap)
                        || opensSpacedParagraph(line, after: prev, gap: verticalGap, leading: previousGap)
                        || opensHangingEntry(line, after: prev, first: paragraphFirst) {
                        flush()
                    } else { attachedGap = inflation > 0 ? previousGap : verticalGap }
                }
                if paragraph.elements.isEmpty {
                    paragraph = line.content
                    opening = (line, evidencedOpening)
                    paragraphFirst = line
                } else {
                    // A line-end hyphen the extractor never saw closes up with no space (#157).
                    if let prev = previous, lostLineEndHyphen(prev, line, measures: measures,
                                                              vocabulary: vocabulary) {
                        paragraph.append(line.content)
                    } else {
                        paragraph = join(paragraph, line.content, vocabulary: vocabulary,
                            page: page.number, warnings: &warnings)
                    }
                    // The drop-cap line stays the opening while the lines beside its initial follow.
                    if opening?.line.readingRect == nil { opening = nil }
                }
                previous = line
                previousGap = attachedGap
            }
        }
        flushNote()
        flushTagged()
        flush()
        joinWrappedCaptionLines(&result, page: page, body: body, vocabulary: vocabulary, warnings: &warnings)
        joinColumnContinuations(&result, page: page, images: images.map(\.0) + clusters(page.tints, distance: 4),
                                vocabulary: vocabulary, warnings: &warnings)
        joinWordBreaks(&result, page: page, body: body, vocabulary: vocabulary, warnings: &warnings)
        attachEdgeCredits(&result, page: page, images: images, body: body)
        for note in footnotes?.notes ?? [] {
            var text = FootnoteDetector.normalizedMarker(elements[note.range.lowerBound].line!.content)
            for index in note.range.dropFirst() {
                text = join(text, elements[index].line!.content, vocabulary: vocabulary,
                    page: page.number, warnings: &warnings)
            }
            // Only a numbered note has an identity a reference can cite; a lettered table
            // note (`eEstimated.`) is cited from the table, which is preserved as an image.
            var key: NoteKey?
            if case let .number(number)? = note.marker { key = NoteKey(number: number, scope: .page(page.number)) }
            result.append(ReflowBlock(content: .footnote(text), note: key, page: page.number))
        }
        return result
    }

    /// A page's first note that opens without a marker continues the previous page's last
    /// note. The note keeps its position and the page's standalone boundary moves inside it,
    /// as it does for a continued paragraph, so the page's body follows the completed note.
    /// When `appendPage` has already joined the body across the page, the boundary sits in
    /// that paragraph and the note simply absorbs the continuation.
    static func joinContinuedFootnote(_ blocks: inout [ReflowBlock], page: Int,
                                      vocabulary: Set<String>, warnings: inout [ConversionWarning]) {
        guard let index = blocks.firstIndex(where: { $0.isFootnote && $0.page == page }),
              case let .footnote(rest) = blocks[index].content, FootnoteDetector.noteMarker(of: rest) == nil,
              let start = blocks[..<index].lastIndex(where: \.isFootnote),
              case let .footnote(left) = blocks[start].content,
              blocks[start].page == page - 1 || blocks[start].sourcePages.contains(page - 1) else { return }
        let marker = blocks[start..<index].firstIndex { $0.content == .sourcePage(page) }
        blocks[start].content = .footnote(join(left, rest, vocabulary: vocabulary, page: page,
            sourceBoundary: marker == nil ? nil : page, warnings: &warnings))
        blocks.remove(at: index)
        if let marker { blocks.remove(at: marker) }
    }

    /// Tags may reorder only complete groups inside an uninterrupted run of tagged text.
    /// Images and unassociated text are barriers, including content removed into image crops.
    /// `headingTypography` is the page's own heading typography, before tags, and `wraps` whether
    /// one line runs on into the line beneath it (see `blocks`).
    static func structuredOrder(_ spatial: [Element], page: Int,
                                warnings: inout [ConversionWarning], depth: Int = 0,
                                headingTypography: (TextLine) -> Bool = { _ in false },
                                wraps: (TextLine, TextLine) -> Bool = { _, _ in false }) -> [Element] {
        var elements = spatial
        guard depth < 32 else {
            for index in elements.indices { elements[index].line?.structure = nil }
            return elements
        }
        if depth == 0 {
            let groups = Dictionary(grouping: elements.compactMap(\.line).filter { $0.structure != nil },
                by: { $0.structure!.group })
            var unsafe = Set(groups.compactMap { group, lines -> Int? in
                // Caption ownership and lists are outside this phase. A paragraph tag alone
                // must not detach a figure label or collapse significant item breaks. One
                // exception: a paragraph group that opens with a marker PDFKit split from its
                // text, and holds no other list line, is exactly that one item, so it has no
                // item break to collapse (#81). An unsplit bullet inside a group still falls back.
                let listLines = lines.filter { isList($0.text) }
                // The item opens the group: first by tag order, and first in spatial order among
                // lines sharing that order (one marked section can hold several lines).
                let opening = lines.min { $0.structure!.order < $1.structure!.order }
                // A group opening with a `+` bullet is one item too (#194): the dietary guidelines tag
                // each `+` item as a paragraph, which held no list line before `+` was a bullet.
                let singleSplitItem = listLines.count == 1 && lines.first!.structure!.headingLevel == 0
                    && (listLines[0].structure!.opensWithSplitMarker || opensWithPlusBullet(listLines[0].text))
                    && opening == listLines[0]
                let captionOrList = (!listLines.isEmpty && !singleSplitItem) || lines.contains { $0.text.range(
                    of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil }
                let oversizedHeading = lines.first!.structure!.headingLevel > 0
                    && lines.reduce(0, { $0 + $1.text.count + 1 }) >= 200
                return captionOrList || oversizedHeading ? group : nil
            })
            // A source can tag a wrapped line as a paragraph of its own: FAA page 227 tags
            // `Figure 8-34. Utilization of a compass rose aids compensation for` and `deviation
            // errors.` as two groups. A paragraph group whose first line continues the last line of
            // a group that falls back falls back with it, so the spatial caption and list rules read
            // the whole item, as they do where the page has no tags (#75).
            var grown = true
            while grown {
                grown = false
                for (group, lines) in groups where !unsafe.contains(group) && lines.first!.structure!.headingLevel == 0 {
                    if unsafe.contains(where: { groups[$0].map { wraps($0.last!, lines.first!) } ?? false }) {
                        unsafe.insert(group); grown = true
                    }
                }
            }
            // A paragraph tag over a title and the body set beneath it is not one paragraph, and
            // its order is no evidence either: FAA page 203 tags `Introduction`, its paragraph,
            // `Pitot-Static Flight Instruments` and its paragraph as one `P`, ahead of the
            // chapter title (#84). Such a group keeps its spatial reading. A drop cap or numeral
            // (fewer than two letters) is not a title.
            let titled = Set(groups.compactMap { group, lines -> Int? in
                guard lines.first!.structure!.headingLevel == 0, !unsafe.contains(group) else { return nil }
                return lines.indices.contains { index in
                    lines[index].text.filter(\.isLetter).count >= 2 && headingTypography(lines[index])
                        && lines[(index + 1)...].contains { !headingTypography($0) }
                } ? group : nil
            })
            if !titled.isEmpty {
                for index in elements.indices {
                    if let group = elements[index].line?.structure?.group, titled.contains(group) {
                        elements[index].line?.structure = nil
                    }
                }
                warnings.append(.init(code: .structureFallback, page: page,
                    message: "A paragraph tag spanning a heading and the text beneath it requires broader semantic validation; spatial reconstruction is retained."))
            }
            if !unsafe.isEmpty {
                for index in elements.indices {
                    if let group = elements[index].line?.structure?.group, unsafe.contains(group) {
                        elements[index].line?.structure = nil
                    }
                }
                warnings.append(.init(code: .structureFallback, page: page,
                    message: "Caption, list or oversized heading tags require broader semantic validation; spatial reconstruction is retained."))
            }
        }
        var runs: [Int: Set<Int>] = [:]
        var counts: [Int: Int] = [:]
        var run = 0
        for element in elements {
            if let tag = element.line?.structure {
                runs[tag.group, default: []].insert(run)
                counts[tag.group, default: 0] += 1
            } else { run += 1 }
        }
        var rejected = false
        for index in elements.indices {
            if let tag = elements[index].line?.structure,
               runs[tag.group]?.count != 1 || counts[tag.group] != tag.lineCount {
                elements[index].line?.structure = nil
                rejected = true
            }
        }
        // Rejecting a group introduces another barrier. Repeat until groups cannot cross it.
        if rejected {
            if !warnings.contains(where: { $0.code == .structureFallback && $0.page == page }) {
                warnings.append(.init(code: .structureFallback, page: page,
                    message: "Tagged groups intersect preserved regions or unassociated text; their spatial layout is retained."))
            }
            return structuredOrder(elements, page: page, warnings: &warnings, depth: depth + 1)
        }
        var start = 0
        while start < elements.count {
            guard elements[start].line?.structure != nil else { start += 1; continue }
            var end = start + 1
            while end < elements.count && elements[end].line?.structure != nil { end += 1 }
            elements.replaceSubrange(start..<end, with: elements[start..<end].enumerated().sorted {
                let left = $0.element.line!.structure!, right = $1.element.line!.structure!
                return left.order == right.order ? $0.offset < $1.offset : left.order < right.order
            }.map(\.element))
            start = end
        }
        return elements
    }

    /// Cell lines join like paragraph lines (spaces, hyphen repair); a section row is one cell.
    static func tableBlock(_ table: ShadedTableDetector.Table, vocabulary: Set<String>, page: Int,
                           warnings: inout [ConversionWarning]) -> ReflowBlock.Table {
        let rows = table.rows.map { row in
            ReflowBlock.Table.Row(cells: row.cells.map { cell in
                ReflowBlock.Table.Cell(text: cell.lines.dropFirst().reduce(cell.lines.first?.content ?? InlineText()) {
                    join($0, $1.content, vocabulary: vocabulary, page: page, warnings: &warnings)
                }, span: cell.span, header: cell.header)
            }, header: row.header)
        }
        // The title and the description are separate caption paragraphs, joined like prose.
        let caption = [table.title, table.description].filter { !$0.isEmpty }.map { lines in
            lines.dropFirst().reduce(lines[0].content) { join($0, $1.content, vocabulary: vocabulary, page: page, warnings: &warnings) }
        }
        return ReflowBlock.Table(columns: table.columns, rows: rows, caption: caption)
    }

    /// A preserved image with alternative text that says what it holds and provenance kept out of
    /// it (#187). `sourceCaption` is the caption the page itself prints for this figure, which
    /// describes it better than any kind can; it is empty for every crop the converter cannot
    /// pair with one, and it stays in the reading text as its own block either way.
    static func imageBlock(assetID: String, page: Int, kind: PreservedImageKind = .artwork,
                           sourceCaption: String = "") -> ReflowBlock {
        let provenance = switch kind {
        case .sourcePage, .page: "Source page \(page)"
        default: "Preserved region from page \(page)"
        }
        let alternative = sourceCaption.isEmpty ? kind.alternativeText : sourceCaption
        return ReflowBlock(content: .image(.init(assetID: assetID, alternativeText: alternative,
                                                 provenance: provenance)), page: page)
    }

    /// Preserve the source boundary inside a continuing paragraph, without a format-specific marker.
    ///
    /// The join anchors are the last and first body paragraphs in reading order, past preserved
    /// images, figure captions and bare folios that furniture removal kept (#45). Those blocks
    /// stay on their page, ahead of the joined paragraph. Structure groups, geometry and the
    /// preserved regions of both pages supply the evidence; see `continuation`. `continuesNote`
    /// states that the numbered-note detector read this page's first line as the wrapped text of
    /// the previous page's last note (`NumberedNoteDetector.Layout.continuesParagraph`).
    static func appendPage(_ pageBlocks: [ReflowBlock], page: PageContent, images: [CGRect] = [],
                           previousPage: PageContent?, previousImages: [CGRect] = [],
                           skippedPages: [(page: PageContent, images: [CGRect])] = [],
                           to blocks: inout [ReflowBlock], vocabulary: Set<String>,
                           continuesNote: Bool = false,
                           warnings: inout [ConversionWarning]) {
        var remaining = pageBlocks
        // Text inside a tinted box (a sidebar, a figure's title band) competes with a join anchor
        // only when it is body-sized, exactly as text inside a preserved image does (#54).
        let images = images + clusters(page.tints, distance: 4)
        let previousImages = previousImages + clusters(previousPage?.tints ?? [], distance: 4)
        if let previousPage,
           let anchors = continuation(from: blocks, previousPage: previousPage, previousImages: previousImages,
                                      skippedPages: skippedPages, to: remaining, page: page,
                                      vocabulary: vocabulary, images: images, continuesNote: continuesNote),
           let left = joinableText(blocks[anchors.previous].content),
           case .paragraph(var right) = remaining[anchors.next].content {
            // Pages holding only figures between the halves open at the text boundary as well,
            // ahead of this page; their figures follow the paragraph, as this page's leading
            // figures do.
            let skipped = skippedPages.map(\.page.number)
            if !skipped.isEmpty {
                right.elements.insert(contentsOf: (skipped.dropFirst() + [page.number]).map { .sourcePage($0) }, at: 0)
            }
            var joined = blocks[anchors.previous]
            let text = join(left, right, vocabulary: vocabulary, page: page.number,
                sourceBoundary: skipped.first ?? page.number, warnings: &warnings)
            // A continued list item keeps its representation; only its text grows.
            if case .preformatted = joined.content { joined.content = .preformatted(text) }
            else { joined.content = .paragraph(text) }
            // Images, captions and folios keep their place ahead of the joined paragraph. A
            // page-bottom footnote follows it instead: its reference is inside that paragraph,
            // and note text must not precede its marker (#40). It then sits past the inline
            // boundary, so page navigation reaches it from the next page. Headings directly above
            // the paragraph move with it: the section they open starts with that paragraph, and
            // a figure the page set beside or below the section must not come between them (FAA
            // page 33's `Selecting a Flight School`, #63).
            var start = anchors.previous
            while start > 0, case .heading = blocks[start - 1].content { start -= 1 }
            let headings = Array(blocks[start..<anchors.previous])
            let after = blocks[(anchors.previous + 1)...]
            // A figure and its caption on a page the paragraph already runs into belong after it,
            // as a skipped page's figures do: that page's marker is inside the joined text, and
            // keeping them ahead would place them before it, inside the page before (#153, the
            // Word paper's Figure 16 on page 10, read inside page 9). A folio keeps its place.
            let opened = blocks[anchors.previous].page
            func crossed(_ block: ReflowBlock) -> Bool {
                guard block.page > opened, !skipped.contains(block.page) else { return false }
                if case .image = block.content { return true }
                return isCaption(block.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let trailing = after.filter { !skipped.contains($0.page) && !crossed($0) }
            let later = after.filter(crossed)
            let skippedBlocks = after.filter {
                guard skipped.contains($0.page) else { return false }
                if case .sourcePage = $0.content { return false }
                return true
            }
            blocks.replaceSubrange(start..., with: trailing.filter { !$0.isFootnote } + headings + [joined]
                + trailing.filter(\.isFootnote) + later + skippedBlocks)
            remaining.remove(at: anchors.next)
        } else {
            blocks.append(ReflowBlock(content: .sourcePage(page.number), page: page.number))
        }
        blocks += remaining
    }

    /// The previous page's last body paragraph continues in the next page's first body paragraph
    /// only when: neither block carries a different validated paragraph identity; the next text
    /// starts lowercase and the previous text lacks terminal punctuation (past closing quotes and
    /// superscript note markers); the previous paragraph's last line fills its column and reads
    /// as prose; the next paragraph's first line is not a retained running header; and no other
    /// prose lies below or right of that last line, or above or left of that first line. Text
    /// inside a preserved region counts as prose when it is body-sized and wide, so a figure that
    /// swallowed the real neighbour blocks the join instead of corrupting the text.
    ///
    /// On a notes page whose first line the numbered-note detector read as the previous page's
    /// last note wrapping (`continuesNote`: the dedented wrap edge, above the chapter's next note
    /// start), that reading replaces the text evidence: the continuation may open with a capital,
    /// a digit or a quote, after any punctuation. The previous block must still be a paragraph,
    /// its last line must fill its column (page 583's last bullet ends short, and page 584's
    /// flush-left `The proposed National Counterterrorism Center…` opens a paragraph of its own),
    /// and no prose may lie below that line or above the first.
    private static func continuation(from blocks: [ReflowBlock], previousPage: PageContent, previousImages: [CGRect],
                                     skippedPages: [(page: PageContent, images: [CGRect])] = [],
                                     to pageBlocks: [ReflowBlock], page: PageContent, vocabulary: Set<String>,
                                     images: [CGRect], continuesNote: Bool = false) -> (previous: Int, next: Int)? {
        var previous = blocks.count - 1
        // Pages between that hold only figures, captions and folios, with their page markers.
        let skipped = Set(skippedPages.map(\.page.number))
        if !skipped.isEmpty && continuesNote { return nil }
        while previous >= 0, skipped.contains(blocks[previous].page) { previous -= 1 }
        // A footnote continued onto the previous page starts on an earlier one, and a join
        // moves an earlier page's footnotes behind the paragraph that continued.
        while previous >= 0, blocks[previous].page == previousPage.number
                || blocks[previous].sourcePages.contains(previousPage.number)
                || (blocks[previous].isFootnote && blocks[previous].page < previousPage.number),
              isSkippable(blocks[previous], page: previousPage) { previous -= 1 }
        guard previous >= 0, let left = joinableText(blocks[previous].content),
              blocks[previous].page == previousPage.number
                || blocks[previous].sourcePages.contains(previousPage.number) else { return nil }
        var next = 0
        while next < pageBlocks.count, isSkippable(pageBlocks[next], page: page) { next += 1 }
        guard next < pageBlocks.count, case let .paragraph(right) = pageBlocks[next].content else { return nil }
        // Two validated identities are the author's evidence of separation, but only when one of
        // them is something other than a plain paragraph: a heading, a list item, a caption. Where
        // both are paragraphs the identities say nothing, because a source may tag each page's
        // fragment of one continuing paragraph as its own `P` — the Fed does that for six of its
        // paragraphs while 22 of its groups do span a page (#67). Those fall through to the
        // geometric rule below, which already refuses every other role. One untagged side, or a
        // side whose role no group vouches for, keeps the heuristic as before.
        if let leftGroup = blocks[previous].structureGroup, let rightGroup = pageBlocks[next].structureGroup,
           leftGroup != rightGroup,
           blocks[previous].taggedLevel != 0 || pageBlocks[next].taggedLevel != 0 { return nil }
        let previousCaptions = captionTexts(blocks, page: previousPage.number)
        let nextCaptions = captionTexts(pageBlocks, page: page.number)
        if continuesNote {
            guard case .paragraph = blocks[previous].content, pageBlocks[next].note == nil,
                  let last = lastLine(of: left.text, in: previousPage.lines),
                  let first = firstLine(of: right.text, in: page.lines),
                  fillsColumn(last, in: previousPage.lines, body: max(4, bodySize(previousPage.lines))),
                  endsColumn(last, in: previousPage, images: previousImages, captions: previousCaptions),
                  opensColumn(first, in: page, images: images, captions: nextCaptions) else { return nil }
            return (previous, next)
        }
        guard !endsSentence(left), let last = lastLine(of: left.text, in: previousPage.lines),
              continuesSentence(left, into: right,
                                sameTag: sameParagraphTag(last, firstLine(of: right.text, in: page.lines))),
              // A skipped page holds no prose, even inside its regions.
              !skippedPages.contains(where: { skippedPage in
                  let captions = captionTexts(blocks, page: skippedPage.page.number)
                  return skippedPage.page.lines.contains {
                      isProse($0, beside: last, share: 0.5, page: skippedPage.page, images: skippedPage.images,
                              captions: captions)
                  }
              }),
              let first = firstLine(of: right.text, in: page.lines),
              !isHeaderLike(first, in: page), wordCount(first.text) >= 2,
              // A word the page break cut in half is evidence of its own, whatever else the line
              // carries: Loper Bright page 11's citations leave `…it author-` under half letters.
              readsAsProse(last.text) || continuesWordBreak(last.text, first.text, vocabulary: vocabulary),
              readsAsProse(first.text),
              fillsColumn(last, in: previousPage.lines, body: max(4, bodySize(previousPage.lines)))
                || right.text.first?.isLowercase == true && endsOnAComma(last, body: max(4, bodySize(previousPage.lines))),
              endsColumn(last, in: previousPage, images: previousImages, captions: previousCaptions),
              opensColumn(first, in: page, images: images, captions: nextCaptions),
              // A capital, digit or quote continues only in the anchor's type and on a full line:
              // 9/11 page 302's credit `The World Trade Center Radio Repeater System` under the
              // rendering, and page 246's run-in title `Atta’s Alleged Trip to Prague`, are short.
              right.text.first?.isLowercase == true
                || Int(first.fontSize.rounded()) == Int(last.fontSize.rounded())
                && opensOnAFullLine(first, in: page.lines, body: max(4, bodySize(page.lines))) else { return nil }
        // A code block is preformatted because its breaks are significant; a list item is
        // preformatted because its marker is. Only the item continues as running text.
        if case .preformatted = blocks[previous].content, last.monospaced { return nil }
        return (previous, next)
    }

    /// A paragraph that ends one column's foot continues at the next column's head on the same
    /// page (DGA page 9, `Older Adults`: `…dairy, meats, seafood,` / `eggs, legumes…`, #111).
    /// Tags join a tagged page's columns; untagged text had no such join. The evidence is the
    /// cross-page rule's (#45): the paragraphs are adjacent in reading order apart from figures,
    /// captions and folios; neither carries a different validated identity; the next text starts
    /// lowercase and the previous one leaves its sentence open; both anchor lines read as prose
    /// and the last fills its column. Geometry replaces the page ends: the next paragraph's first
    /// line sits in a column to the right whose head is higher than the last line; no prose lies
    /// below the last line in its span, between the two columns, or above the first line in its
    /// span. Stacked sections above do not compete: the search stops at the lowest line, figure
    /// or box above the first line that crosses the gutter (DGA's section band), so the columns
    /// of earlier sections are not this section's text.
    private static func joinColumnContinuations(_ blocks: inout [ReflowBlock], page: PageContent, images: [CGRect],
                                                vocabulary: Set<String>, warnings: inout [ConversionWarning]) {
        let body = max(4, bodySize(page.lines))
        var index = 0
        while index < blocks.count {
            defer { index += 1 }
            guard let left = joinableText(blocks[index].content) else { continue }
            var next = index + 1
            while next < blocks.count, isSkippable(blocks[next], page: page) { next += 1 }
            guard next < blocks.count, case let .paragraph(right) = blocks[next].content,
                  continuesColumn(left, blocks[index], into: right, blocks[next], page: page, images: images,
                                  captions: captionTexts(blocks, page: page.number), body: body)
            else { continue }
            let text = join(left, right, vocabulary: vocabulary, page: page.number, warnings: &warnings)
            if case .preformatted = blocks[index].content { blocks[index].content = .preformatted(text) }
            else { blocks[index].content = .paragraph(text) }
            // Figures and captions between the column's foot and the next column's head follow
            // the sentence rather than interrupt it.
            let between = Array(blocks[(index + 1)..<next])
            blocks.replaceSubrange((index + 1)...next, with: between)
            index -= 1
        }
    }

    /// A block whose text ends in a word-break hyphen continues in the next block when that block
    /// opens lowercase (#131). The halves of one word cannot stand in two paragraphs, so the break
    /// itself is the evidence, whatever split the lines: a line whose detached note marker set it
    /// in note type (9/11 page 220, `178 In March 2001, the CIA’s brief-` + `ing slides…`), a row
    /// piece PDFKit split off (page 438, `the intel-` + `ligence establishment…`), or a wrapped
    /// line the paragraph rules set apart (Fed page 20's `maximum em-` + `ployment`, Loper Bright
    /// page 4's `trig-` + `gered`). Two letters precede the hyphen, as a word break leaves at least
    /// two (never the Blue Book's OCR debris `/9, Z-` + `r.,mbel`). The left block is a paragraph or
    /// a list item, the right one a paragraph that opens no note of its own, neither with a
    /// validated role other than a paragraph. The hyphen policy decides the join, as it does inside
    /// a paragraph, but the blocks stay apart where it has no evidence (`uncertainHyphen`): reading
    /// order can place a broken fragment beside the wrong neighbour (NOAA's `acidifica-` before
    /// `oceans, animal…`).
    ///
    /// The halves are usually adjacent in reading order. Where a tinted box or a figure cuts the
    /// paragraph they are not: the Fed sets a sidebar into its measure, and its title and text are
    /// read between the two halves (page 22's `…stress tests of banking insti-`, `More on Federal
    /// Reserve Advisory Councils`, the box's paragraph, then `tutions. Stress tests are required…`;
    /// also pages 28, 56, 57 and 80). Then the geometry must say the two lines are one paragraph's
    /// (#148): the continuation's first line is the next line of the anchor's own column
    /// (`nextLineInColumn` — directly beneath it, on its edge, in its type, with no line between),
    /// and both blocks are this page's. The box keeps its place and follows the joined paragraph,
    /// as a figure between a column's foot and the next column's head does.
    private static func joinWordBreaks(_ blocks: inout [ReflowBlock], page: PageContent, body: CGFloat,
                                       vocabulary: Set<String>, warnings: inout [ConversionWarning]) {
        var index = 0
        while index + 1 < blocks.count {
            let leftBlock = blocks[index]
            guard let left = joinableText(leftBlock.content), (leftBlock.taggedLevel ?? 0) == 0,
                  left.text.hasSuffix("-"), left.text.dropLast().suffix(2).filter(\.isLetter).count == 2 else {
                index += 1
                continue
            }
            // The blocks' separation stands unless the book vouches for the word or the compound.
            var anchor: TextLine??
            func continues(_ candidate: Int) -> Bool {
                guard case let .paragraph(right) = blocks[candidate].content, blocks[candidate].note == nil,
                      (blocks[candidate].taggedLevel ?? 0) == 0,
                      continuesWordBreak(left.text, right.text, vocabulary: vocabulary) else { return false }
                if candidate == index + 1 { return true }
                if anchor == nil {
                    anchor = leftBlock.page == page.number ? lastLine(of: left.text, in: page.lines) : .some(nil)
                }
                guard blocks[candidate].page == page.number, let last = anchor ?? nil,
                      let first = firstLine(of: right.text, in: page.lines) else { return false }
                return nextLineInColumn(last, first, page: page, body: body)
            }
            guard let next = ((index + 1)..<blocks.count).first(where: continues),
                  case let .paragraph(right) = blocks[next].content else {
                index += 1
                continue
            }
            let text = join(left, right, vocabulary: vocabulary, page: page.number, warnings: &warnings)
            if case .preformatted = leftBlock.content { blocks[index].content = .preformatted(text) }
            else { blocks[index].content = .paragraph(text) }
            // A box read between the halves keeps its place and follows the joined paragraph.
            blocks.remove(at: next)
        }
    }

    /// A figure or table caption keeps the line it wraps onto when reading order read that line
    /// apart from it (#145). The row sort interleaves a caption at a column's foot with the prose
    /// beside it, so the caption's second line became a paragraph of its own: FAA page 391's
    /// `Figure 16-4. Meridians and parallels—the basis of measuring time,` / `distance, and
    /// direction.` beside `…an hour is lost when`, and page 341's `…marking located` / `on Taxiway
    /// Kilo.` and `…takeoff end of Runway` / `14 with collocated Taxiway Alpha location sign.`,
    /// with figure 14-7's caption read between. The evidence is the paragraph rule's: the caption
    /// leaves its sentence open; a later paragraph on the page opens on the line directly beneath
    /// the caption's last line, on its left edge or centre, at ordinary leading (-0.4…0.9 of the
    /// larger size), no more than 15% larger, set smaller than the page's body (NASA's paper sets
    /// `…is illustrated in` / `Figure 14. These peak values…` in body type, a sentence that opens with
    /// a figure reference, not a caption), and no line lies between them. Something else must
    /// have been read between the two blocks: where the paragraph rule saw the lines in sequence
    /// and still set them apart, that decision stands (the Fed's 8-point description beneath each
    /// 10-point bold `Figure N.` title, page 13's `…paid to the U.S. Treasury` / `The Federal
    /// Reserve transfers its net earnings to the U.S. Treasury.`).
    private static func joinWrappedCaptionLines(_ blocks: inout [ReflowBlock], page: PageContent, body: CGFloat,
                                                vocabulary: Set<String>, warnings: inout [ConversionWarning]) {
        var index = 0
        while index < blocks.count {
            defer { index += 1 }
            guard blocks[index].page == page.number, case let .paragraph(caption) = blocks[index].content,
                  isCaption(caption.text), !endsSentence(caption),
                  let last = lastLine(of: caption.text, in: page.lines) else { continue }
            let beneath = page.lines.filter { $0.fontSize < body * 0.95 && wrapsCaption(last, onto: $0, page: page, body: body) }
            guard !beneath.isEmpty, let wrapped = blocks.indices.dropFirst(index + 2).first(where: { candidate in
                guard blocks[candidate].page == page.number, case let .paragraph(text) = blocks[candidate].content,
                      !isCaption(text.text), let first = firstLine(of: text.text, in: page.lines) else { return false }
                return beneath.contains(first)
            }), case let .paragraph(text) = blocks[wrapped].content else { continue }
            blocks[index].content = .paragraph(join(caption, text, vocabulary: vocabulary, page: page.number,
                                                    warnings: &warnings))
            blocks.remove(at: wrapped)
            index -= 1
        }
    }

    /// `first` is the line a caption's `last` line wraps onto (`joinWrappedCaptionLines`).
    static func wrapsCaption(_ last: TextLine, onto first: TextLine, page: PageContent, body: CGFloat) -> Bool {
        let size = max(last.fontSize, first.fontSize)
        let gap = last.rect.minY - first.rect.maxY
        guard first.fontSize < last.fontSize * 1.15, gap > -size * 0.4, gap < size * 0.9,
              abs(first.rect.minX - last.rect.minX) <= body * 0.5 || abs(first.rect.midX - last.rect.midX) <= body * 0.5,
              first != last else { return false }
        return !page.lines.contains { other in
            other != last && other != first && other.rect.midY < last.rect.midY && other.rect.midY > first.rect.midY
                && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX
                && other.rect.maxX > last.rect.minX && other.rect.minX < last.rect.maxX
        }
    }

    private static func continuesColumn(_ left: InlineText, _ leftBlock: ReflowBlock, into right: InlineText,
                                        _ rightBlock: ReflowBlock, page: PageContent, images: [CGRect],
                                        captions: [String], body: CGFloat) -> Bool {
        if let leftGroup = leftBlock.structureGroup, let rightGroup = rightBlock.structureGroup,
           leftGroup != rightGroup { return false }
        guard !endsSentence(left), let last = lastLine(of: left.text, in: page.lines),
              let first = firstLine(of: right.text, in: page.lines),
              continuesSentence(left, into: right, sameTag: sameParagraphTag(last, first)),
              wordCount(first.text) >= 2, readsAsProse(last.text), readsAsProse(first.text),
              fillsColumn(last, in: page.lines, body: body)
                || right.text.first?.isLowercase == true && endsOnAComma(last, body: body) else { return false }
        // Evidence weaker than a lowercase opening needs the continuation in the anchor's type (FAA
        // page 341's `…the threshold for` does not continue in the wrapped caption line `14 with
        // collocated Taxiway Alpha location sign.` beneath figure 14-9) and on a full line.
        let sameSize = Int(first.fontSize.rounded()) == Int(last.fontSize.rounded())
        guard right.text.first?.isLowercase == true || sameSize && opensOnAFullLine(first, in: page.lines, body: body)
        else { return false }
        if case .preformatted = leftBlock.content, last.monospaced { return false }
        // A figure or caption set beside the paragraph was read between two of its lines (FAA
        // page 230's `…twisted` / `into a helix`, beside figure 8-39): the next line lies directly
        // below, on the column's edge, at the paragraph's own line pitch.
        if nextLineInColumn(last, first, page: page, body: body) { return true }
        // The next column's head is higher than the foot, or lower only beneath a figure that
        // heads that column and reaches above the foot (FAA page 411: `…by means of the` over
        // figure 16-29, `course select knob` under figure 16-30).
        let headedByFigure = images.contains {
            $0.minX < first.rect.maxX && $0.maxX > first.rect.minX
                && $0.minY >= first.rect.maxY - body * 0.5 && $0.maxY > last.rect.midY
        }
        guard first.rect.minX >= last.rect.maxX - body * 0.5,
              first.rect.midY > last.rect.midY || headedByFigure && sameSize else { return false }
        // The lowest element over the first line that crosses the gutter bounds the section. Body
        // prose a crossing region swallowed still competes: the bound is that element's top, and
        // only the element itself is set aside (FAA page 19's fixture, whose full-width crop took
        // the right column's first lines, #118).
        let gutter = (start: last.rect.maxX, end: first.rect.minX)
        let lowest = (page.lines.map(\.rect) + images)
            .filter { $0.minX < gutter.start && $0.maxX > gutter.end && $0.midY > first.rect.maxY }
            .min { $0.minY < $1.minY }
        let ceiling = lowest?.maxY ?? .infinity
        let separator = page.lines.filter { FootnoteDetector.isSeparator($0) && $0.rect.midY < last.rect.minY }
            .map(\.rect.minY).max()
        return !page.lines.contains { other in
            guard other != last, other != first, other.rect.midY < ceiling, other.rect != lowest else { return false }
            if let separator, other.rect.midY < separator, other.fontSize <= last.fontSize * 0.9 { return false }
            let below = other.rect.midY < last.rect.minY && other.rect.maxX > last.rect.minX && other.rect.minX < last.rect.maxX
            let between = other.rect.minX >= last.rect.maxX && other.rect.maxX <= first.rect.minX
            let above = other.rect.midY > first.rect.maxY && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX
            return below && isProse(other, beside: last, share: 0.5, page: page, images: images, captions: captions)
                || between && isProse(other, beside: last, share: 0.9, page: page, images: images, captions: captions)
                || above && isProse(other, beside: first, share: 0.5, page: page, images: images, captions: captions)
        }
    }

    /// `first` is the line after `last` in one column: the same size, on the same left edge (half
    /// a body), directly below at a pitch of at most one and a half line heights, with no line
    /// between them.
    static func nextLineInColumn(_ last: TextLine, _ first: TextLine, page: PageContent, body: CGFloat) -> Bool {
        let pitch = last.rect.midY - first.rect.midY
        guard Int(first.fontSize.rounded()) == Int(last.fontSize.rounded()),
              abs(first.rect.minX - last.rect.minX) <= body * 0.5,
              first.rect.maxY <= last.rect.minY + last.rect.height * 0.25,
              pitch <= max(last.rect.height, first.rect.height) * 1.5 else { return false }
        return !page.lines.contains { other in
            other != last && other != first && other.rect.midY < last.rect.midY && other.rect.midY > first.rect.midY
                && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX
        }
    }

    /// The previous text leaves its sentence open and the next text carries it on: it opens
    /// lowercase or, after a word that cannot end a sentence (an article, preposition,
    /// conjunction, auxiliary, determiner or possessive), with a capital, a digit or an opening
    /// quote (FAA `…further increasing the` / `AOA.`, `…about 2 °Celsius (C) every` / `1,000 feet`).
    /// Two more kinds of evidence admit those openings after any word (#145): the last sentence
    /// leaves a parenthesis open (FAA page 169's `…Fahrenheit degrees (70 x 100/180 = 38.89` /
    /// `Celsius degrees)`), or `sameTag`, the source's structure tree puts the anchor's last line
    /// and the continuation's first line in one paragraph (FAA page 24's `…education. The FAA` /
    /// `Safety Team (FAASTeam) exemplifies this commitment.`, both in one `P` interrupted by a figure).
    static func continuesSentence(_ left: InlineText, into right: InlineText, sameTag: Bool = false) -> Bool {
        guard !endsSentence(left), let opening = right.text.first else { return false }
        if opening.isLowercase { return true }
        guard opening.isUppercase || opening.isNumber || opening == "\u{201C}" || opening == "\"",
              let last = left.text.split(whereSeparator: \.isWhitespace).last else { return false }
        if sameTag || leavesParenthesisOpen(left.text) { return true }
        let word = String(last)
        for suffix in ["\u{2019}s", "'s"] where word.hasSuffix(suffix) {
            let stem = word.dropLast(2)
            return stem.count >= 2 && stem.allSatisfy(\.isLetter)
        }
        return openWords.contains(word.lowercased())
    }

    /// The text after its last sentence end (terminal punctuation, closing quotes or brackets, then a
    /// space) opens more parentheses than it closes.
    static func leavesParenthesisOpen(_ text: String) -> Bool {
        guard text.contains("(") else { return false }
        let whole = NSRange(text.startIndex..., in: text)
        let start = sentenceEnd.matches(in: text, range: whole).last
            .flatMap { Range($0.range, in: text)?.upperBound } ?? text.startIndex
        let sentence = text[start...]
        return sentence.filter { $0 == "(" }.count > sentence.filter { $0 == ")" }.count
    }

    private static let sentenceEnd = try! NSRegularExpression(pattern: "[.!?][\u{201D}\u{2019}\"')\\]]*\\s")

    /// Both lines carry one validated paragraph identity from the source's structure tree.
    static func sameParagraphTag(_ last: TextLine?, _ first: TextLine?) -> Bool {
        guard let left = last?.structure, let right = first?.structure else { return false }
        return left.group == right.group && left.headingLevel == 0 && right.headingLevel == 0
    }

    /// A column's last line that ends on a comma after a word of prose, in the page's body size, at
    /// least three words and twelve bodies wide. The comma leaves the sentence open, so the line need
    /// not reach the column's edge: FAA page 221 ends its right column `compass. Errors in the magnetic
    /// compass are numerous,` at x 535.7 against the column's 562.3, and page 438 `list, states have
    /// taken steps to allow the possession, sale,` at 510.5 against 522.1, each the last line of its
    /// text frame, set short in print (the shows' measured advances agree with PDFKit's rectangles,
    /// #145). NBS page 1's 3-point footnote `…references al the end of thi s paper,`, whose period
    /// OCR read as a comma, is not body type. Used only before a lowercase opening.
    private static func endsOnAComma(_ last: TextLine, body: CGFloat) -> Bool {
        let text = last.text.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix(","), text.dropLast().last?.isLetter == true else { return false }
        return wordCount(text) >= 3 && last.rect.width >= body * 12 && Int(last.fontSize.rounded()) == Int(body)
    }

    /// The continuation's first line fills its column, or ends short because it closes the sentence
    /// (FAA page 127's `87 percent, depending on how much the propeller “slips.”`). A short title or
    /// credit line (9/11 page 302's `The World Trade Center Radio Repeater System`) does neither.
    private static func opensOnAFullLine(_ first: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        fillsColumn(first, in: lines, body: body) || endsSentence(InlineText(first.text))
    }

    private static let openWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "from", "with", "into", "onto", "upon",
        "about", "between", "over", "under", "through", "per", "via", "and", "or", "nor", "but", "than",
        "as", "is", "are", "was", "were", "be", "been", "being", "can", "may", "must", "should", "will",
        "would", "could", "every", "each", "its", "their", "his", "her", "our", "your", "this", "these",
        "those", "whose",
    ]

    /// The text of the figure and table captions among a page's blocks.
    private static func captionTexts(_ blocks: [ReflowBlock], page: Int) -> [String] {
        blocks.compactMap {
            guard $0.page == page, case .paragraph = $0.content else { return nil }
            let text = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return isCaption(text) ? text : nil
        }
    }

    /// A reflowed page whose blocks are only preserved images, figure captions and margin folios,
    /// at least one of them an image. A cross-page join may step over it when it also holds no
    /// prose line (FAA page 46, a full-page risk assessment form between `…health, fatigue,
    /// weather,` and `capabilities, etc.`).
    static func holdsOnlyFigures(_ pageBlocks: [ReflowBlock], page: PageContent) -> Bool {
        pageBlocks.contains { if case .image = $0.content { true } else { false } }
            && pageBlocks.allSatisfy { !$0.isFootnote && isSkippable($0, page: page) }
    }

    /// The text a page-crossing join may continue: a body paragraph, or the wrapped line of a
    /// list item whose marker opened it on the previous page and whose text runs on (Fed's
    /// advisory-council list, pages 21 to 22). A block holding a preserved line break keeps it.
    private static func joinableText(_ content: ReflowBlock.Content) -> InlineText? {
        switch content {
        case let .paragraph(text): return text
        case let .preformatted(text): return isList(text.text) && !text.text.contains("\n") ? text : nil
        default: return nil
        }
    }

    /// Preserved images, page-bottom footnotes, figure captions and bare folios in the margin
    /// do not carry body text.
    private static func isSkippable(_ block: ReflowBlock, page: PageContent) -> Bool {
        switch block.content {
        case .image, .footnote: return true
        case .paragraph: break
        case .heading, .preformatted, .listItem, .table, .sourcePage: return false
        }
        let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCaption(text) { return true }
        return isFolio(text) && page.lines.contains {
            $0.text.trimmingCharacters(in: .whitespaces) == text && inMargin($0, of: page)
        }
    }

    private static func isCaption(_ text: String) -> Bool {
        text.range(of: "^(?:Figure|Table)\\s+[0-9]", options: .regularExpression) != nil
    }

    /// The label a printed caption opens with (`Figure 3.2`, `Fig. 1`, `TABLE I`, `Algorithm 2`),
    /// or nil where the line opens no caption (#187). Wider than `isCaption`, which decides what
    /// carries body text and must stay tight: this only chooses alternative text, and the corpus
    /// prints its captions in all of these forms.
    static func captionLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = "^(?:figure|fig\\.|table|plate|chart|exhibit|map|algorithm|listing|box)"
            + "\\s+(?:[A-Z]?[0-9]+(?:[-\u{2013}.][0-9]+)*|[IVXLCDM]{1,6})(?![A-Za-z0-9])"
        guard let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(trimmed[range])
    }

    /// A printed caption shortened for alternative text (#187): whole up to 200 characters,
    /// otherwise its sentences that fit (the FAA's `Figure 11-3. Field elevation versus pressure.`
    /// before three sentences of worked example), or its words that fit and an ellipsis.
    static func alternativeText(caption: String) -> String {
        let limit = 200
        guard caption.count > limit else { return caption }
        let head = String(caption.prefix(limit))
        let label = captionLabel(caption)?.count ?? 0
        if let end = head.ranges(of: /[.!?](?=\s)/).last?.upperBound,
           head.distance(from: head.startIndex, to: end) > label + 1 {
            return String(head[..<end])
        }
        let words = head.split(separator: " ", omittingEmptySubsequences: true).dropLast()
        return words.joined(separator: " ") + "\u{2026}"
    }

    /// The caption a page prints for each crop, where the page leaves no doubt which crop it
    /// names (#187): exactly one caption stands directly against the crop and that caption stands
    /// directly against no other crop. Keyed by the crop's rectangle.
    ///
    /// A caption is the line opening with a printed label, outside every crop, within one and a
    /// half body sizes above or below the crop and overlapping its measure, together with the
    /// lines set directly beneath it in its own type (the rest of the caption's sentence). Where
    /// two crops or two captions compete the page says nothing reliable, so the crop keeps its
    /// kind: #27 records that adjacency proves pairing survived, never that a pairing is right,
    /// and the magazine sets one caption above its photograph and another beside a second.
    static func sourceCaptions(for regions: [CGRect], in page: PageContent) -> [CGRect: String] {
        guard !regions.isEmpty else { return [:] }
        let body = max(4, bodySize(page.lines))
        let candidates = page.lines.filter { line in
            captionLabel(line.text) != nil && !regions.contains { region in region.intersects(line.rect) }
        }
        guard !candidates.isEmpty else { return [:] }
        func against(_ line: TextLine, _ region: CGRect) -> Bool {
            let overlap = min(line.rect.maxX, region.maxX) - max(line.rect.minX, region.minX)
            guard overlap > 0 else { return false }
            let below = region.minY - line.rect.maxY
            let above = line.rect.minY - region.maxY
            return (below >= -1 && below <= body * 1.5) || (above >= -1 && above <= body * 1.5)
        }
        var pairs: [CGRect: TextLine] = [:]
        for region in regions {
            let touching = candidates.filter { against($0, region) }
            guard touching.count == 1, let caption = touching.first,
                  regions.filter({ against(caption, $0) }).count == 1 else { continue }
            pairs[region] = caption
        }
        return pairs.mapValues { caption in
            var text = caption.text.trimmingCharacters(in: .whitespaces)
            // The caption's own wrapped lines: set directly beneath it at the caption's own tight
            // leading, in its type, within its measure. A section title or the body text after a
            // caption stands further off (the Word paper's `Data Acquisition`, 6.1 points under
            // Figure 1's second line where its lines stand 0.5 apart) and ends the caption, as
            // does a smaller credit line (TechPort's 8.2-point description under the 9-point lines
            // of `Figure 1: essential signal chain of the MPG technology`). PDFKit sizes a line by
            // its first run, so a caption whose bold label is set a point smaller reads a point
            // under its own wrapped lines (the FAA's 8-point `Figure 12-5. …` over 9-point `the
            // Earth.`): a wrapped line may stand a point from the caption's first line, and no
            // more than half a point under the line before it.
            let beneath = page.lines.filter { line in
                abs(line.fontSize - caption.fontSize) <= 1 && line.rect.maxY < caption.rect.minY + line.rect.height * 0.5
                    && line.rect.minX >= caption.rect.minX - body && line.rect.minX < caption.rect.maxX
                    && captionLabel(line.text) == nil && !regions.contains { $0.intersects(line.rect) }
            }.sorted { $0.rect.maxY > $1.rect.maxY }
            var floor = caption.rect.minY, size = caption.fontSize
            for line in beneath {
                guard floor - line.rect.maxY <= caption.fontSize * 0.4, line.fontSize >= size - 0.5 else { break }
                text += " " + line.text.trimmingCharacters(in: .whitespaces)
                floor = line.rect.minY
                size = line.fontSize
            }
            return alternativeText(caption: text.trimmingCharacters(in: .whitespaces))
        }
    }

    /// An Arabic page number (optionally prefixed by its chapter's number or its part's letter,
    /// `5-17` or `C-2`) or a Roman numeral.
    private static func isFolio(_ text: String) -> Bool {
        !text.isEmpty && text.range(of: "^(?:(?:[0-9]+-|[A-Za-z]-)?[0-9]+|m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3}))$",
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func inMargin(_ line: TextLine, of page: PageContent) -> Bool {
        guard page.bounds.height > 0 else { return false }
        let position = (line.rect.midY - page.bounds.minY) / page.bounds.height
        return position <= 0.1 || position >= 0.9
    }

    /// Terminal punctuation, looking past closing quotes or brackets and superscript note markers.
    private static func endsSentence(_ text: InlineText) -> Bool {
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        for element in text.elements.reversed() {
            // A linked marker is a superscript too, though linking follows every join.
            guard case let .text(value, style) = element, !style.contains(.superscript),
                  let ending = value.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) else { continue }
            return ".!?:".contains(ending)
        }
        return true
    }

    /// A photo credit set against a preserved image's edge reads beside that image (#159).
    ///
    /// *Agricultural Research* prints each photograph's credit in six-point capitals a point or
    /// two outside the picture, at one corner, above it as often as below. Read where it stands,
    /// such a line takes the place the page's reading order gives it, which on pages 13 and 17 is
    /// the top of the page while the picture it names is the last block: the credit and its
    /// picture come apart, and nothing afterwards says they belong together.
    ///
    /// The line is recognized by its setting, never by its words: it is a paragraph of its own
    /// holding one source line, set in the smallest type the page uses and smaller than the body,
    /// standing within half a body of a preserved region's top or bottom edge, wholly inside that
    /// region's width, outside every region, with no other line between it and that edge. A
    /// caption is set larger and, where it wraps, holds more than one line; a label inside the
    /// picture is inside the region; a running foot spans the page rather than one picture.
    ///
    /// The block moves to the near side of its region's image — after it for a credit set below
    /// the picture, before it for one set above — so a credit already beside its picture stays
    /// where it is. Only a region this page emitted as an image can take one, and a region with
    /// two such lines (the magazine sets one under each of page 6's photographs) keeps both in
    /// their own order.
    static func attachEdgeCredits(_ blocks: inout [ReflowBlock], page: PageContent,
                                  images: [(CGRect, String)], body: CGFloat) {
        guard !page.hasSyntheticTextStyle, !page.recognized, !images.isEmpty, body > 0 else { return }
        let sizes = page.lines.map(\.fontSize).filter { $0 > 0 && $0.isFinite }
        guard let smallest = sizes.min(), smallest < body * 0.9 else { return }
        let regions = images.map(\.0)
        /// The region `line` is credited to, and whether the line stands below it.
        func credited(_ line: TextLine) -> (asset: String, below: Bool)? {
            guard abs(line.fontSize - smallest) <= 0.01, line.rect.isFinite, line.rect.width > 0,
                  raisedNoteNumber(line) == nil,
                  !regions.contains(where: { $0.intersects(line.rect) }) else { return nil }
            for (region, asset) in images {
                // A credit tags one corner of its picture; a note or a caption set under a figure
                // runs the measure. Half the picture's width separates them (#141's DGA notes).
                // A thin rule is a page's decoration, not a picture anything is credited to: the
                // magazine's foot rule runs under every page, a point above the credit beneath the
                // photograph, and is preserved as an image of its own.
                guard !isThinRule(region),
                      line.rect.minX >= region.minX - body * 0.25, line.rect.maxX <= region.maxX + body * 0.25,
                      line.rect.width <= region.width * 0.5 else { continue }
                let below = line.rect.maxY <= region.minY
                let gap = below ? region.minY - line.rect.maxY : line.rect.minY - region.maxY
                guard gap >= 0, gap <= body * 0.5 else { continue }
                // The credit stands against that edge alone: no other line of the page reaches
                // the band between the picture and the credit's far side, anywhere across the
                // picture. Our Flag's page 11 sets `Courtesy U.S. Naval Academy Museum` on the
                // same row as the caption `“Old Ironsides” in the War of 1812.` beneath one
                // engraving, and the row reads left to right where it stands; a credit that
                // shares its edge with other text is part of such a row, not a tag on the corner.
                let band = below ? (line.rect.minY, region.minY) : (region.maxY, line.rect.maxY)
                let crowded = page.lines.contains { other in
                    other != line && other.rect.maxY > band.0 && other.rect.minY < band.1
                        && other.rect.maxX > region.minX - body * 0.25
                        && other.rect.minX < region.maxX + body * 0.25
                }
                if !crowded { return (asset, below) }
            }
            return nil
        }
        var moved = 0
        var index = 0
        while index < blocks.count {
            guard blocks[index].page == page.number, case let .paragraph(text) = blocks[index].content,
                  let line = firstLine(of: text.text, in: page.lines),
                  line.text.trimmingCharacters(in: .whitespaces) == text.text.trimmingCharacters(in: .whitespaces),
                  let credit = credited(line),
                  let image = blocks.firstIndex(where: { block in
                      guard block.page == page.number, case let .image(image) = block.content else { return false }
                      return image.assetID == credit.asset
                  }) else {
                index += 1
                continue
            }
            let target = credit.below ? image + 1 : image
            guard target != index, target != index + 1, moved < page.lines.count else {
                index += 1
                continue
            }
            let block = blocks.remove(at: index)
            blocks.insert(block, at: target > index ? target - 1 : target)
            moved += 1
            if target <= index { index += 1 }
        }
    }


    /// Every join appends the right-hand line verbatim, so a paragraph's last line is a suffix of
    /// its text; its first line may have lost a line-ending hyphen to the join that followed.
    private static func lastLine(of text: String, in lines: [TextLine]) -> TextLine? {
        var best: (line: TextLine, length: Int)?
        for line in lines {
            let candidate = line.text.trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty, text.hasSuffix(candidate) else { continue }
            if let current = best, current.length > candidate.count
                || (current.length == candidate.count && current.line.rect.minY <= line.rect.minY) { continue }
            best = (line, candidate.count)
        }
        return best?.line
    }

    private static func firstLine(of text: String, in lines: [TextLine]) -> TextLine? {
        var best: (line: TextLine, length: Int)?
        for line in lines {
            var candidate = line.text.trimmingCharacters(in: .whitespaces)
            if let hyphen = candidate.last, hyphen == "-" || hyphen == "\u{00ad}", !text.hasPrefix(candidate) {
                candidate.removeLast()
            }
            guard !candidate.isEmpty, text.hasPrefix(candidate) else { continue }
            if let current = best, current.length > candidate.count
                || (current.length == candidate.count && current.line.rect.maxY >= line.rect.maxY) { continue }
            best = (line, candidate.count)
        }
        return best?.line
    }

    /// A short line in a margin band that opens or closes with a page number and is separated
    /// from the text beside it is a running head that furniture removal kept
    /// (`xiv COMMISSION STAFF`, `554 NOTES TO CHAPTERS 9-10`). A paragraph's short final line at
    /// the head of a page carries no folio. `bothBands` also reads the foot of the page, which
    /// the cross-page join rule has no reason to consult: it only ever asks about a page's first
    /// line. Whatever this accepts is margin furniture and never a heading (#62).
    static func isHeaderLike(_ line: TextLine, in page: PageContent, bothBands: Bool = false) -> Bool {
        let words = line.text.split(whereSeparator: \.isWhitespace)
        guard page.bounds.height > 0 else { return false }
        let position = (line.rect.midY - page.bounds.minY) / page.bounds.height
        let top = position >= 0.9
        guard top || (bothBands && position <= 0.1), line.text.count < 100,
              let first = words.first, let last = words.last,
              isFolio(String(first)) || isFolio(String(last)) else { return false }
        let inward = page.lines.filter {
            top ? $0.rect.midY < line.rect.midY - line.rect.height * 0.4
                : $0.rect.midY > line.rect.midY + line.rect.height * 0.4
        }
        let gaps = inward.map { top ? line.rect.minY - $0.rect.maxY : $0.rect.minY - line.rect.maxY }
        guard let gap = gaps.min() else { return true }
        return gap >= max(line.rect.height, page.bounds.height * 0.012)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count
    }

    /// Letters make up at least half of a prose line's ink; inherited OCR of a scanned table
    /// row (`0 6 lip&,, tJ.() w. a,g`) does not qualify as a join anchor.
    private static func readsAsProse(_ text: String) -> Bool {
        let ink = text.filter { !$0.isWhitespace }
        return !ink.isEmpty && ink.filter(\.isLetter).count * 2 >= ink.count
    }

    /// The flush right edge of each type size on a page: the line end most of that size's lines
    /// share, which is the measure a justified column is set to. It is the commonest end, not the
    /// furthest: a line ending in the book's own hyphen overhangs the measure (the 9/11 report's
    /// `=` is two-thirds of an em wide, half again what its longest line otherwise reaches), and a
    /// measure taken from such a line would read every ordinary line as ending short. At least
    /// three lines and a quarter of the size's lines must share the edge, so a ragged column, a
    /// size set on too few lines, and a page of mixed columns have no measure of their own.
    static func justifiedMeasures(_ lines: [TextLine]) -> [Int: CGFloat] {
        var edges: [Int: [CGFloat]] = [:]
        for line in lines where !line.monospaced && line.fontSize > 0 {
            edges[Int(line.fontSize.rounded()), default: []].append(line.rect.maxX)
        }
        return edges.compactMapValues { values in
            let sorted = values.sorted()
            var best: (edge: CGFloat, count: Int)?
            var start = 0
            for index in sorted.indices {
                while sorted[index] - sorted[start] > 1 { start += 1 }
                let count = index - start + 1
                if best.map({ (count, sorted[index]) > ($0.count, $0.edge) }) ?? true {
                    best = (sorted[index], count)
                }
            }
            guard let best, best.count >= 3, best.count * 4 >= sorted.count else { return nil }
            return best.edge
        }
    }

    /// A line the extraction lost a line-end hyphen from (#157). PDFKit drops the hyphen glyph
    /// from some of Our Flag's justified lines, and the line's rectangle loses the glyph's advance
    /// with it, so the break reads as a word space (`…the British fleet bom` over `barded Fort
    /// McHenry…`, page 5; also `fab` + `rics`, `sym` + `bolize`, `mean` + `ing`, `PEO` + `PLE`).
    /// The line's own position is what says a glyph is missing: its column is justified, and this
    /// line ends in a letter short of the measure by between a fifth and a half of its type size —
    /// where a hyphen's advance falls (0.33 em in the book's Times) and no character else does.
    static func endsShortOfMeasure(_ line: TextLine, measures: [Int: CGFloat]) -> Bool {
        guard !line.monospaced, line.fontSize > 0,
              line.text.trimmingCharacters(in: .whitespaces).last?.isLetter == true,
              let measure = measures[Int(line.fontSize.rounded())] else { return false }
        let shortfall = measure - line.rect.maxX
        return shortfall >= line.fontSize * 0.2 && shortfall <= line.fontSize * 0.5
    }

    /// Two lines one lost hyphen broke a word across (#157): `last` ends short of its column's
    /// measure by a hyphen's width, `next` opens in the same type, and the book's words decide the
    /// break as they decide a hyphen the source did print. Only a break the policy resolves to
    /// `removeHyphen` closes up, so the halves must join into a word the book prints (or an
    /// inflected form of one, #115) while the compound is not one. A line that merely ends short
    /// keeps its word space, because no word comes of joining it.
    static func lostLineEndHyphen(_ last: TextLine, _ next: TextLine, measures: [Int: CGFloat],
                                  vocabulary: Set<String>) -> Bool {
        guard endsShortOfMeasure(last, measures: measures), !next.monospaced,
              next.text.first?.isLetter == true,
              abs(next.fontSize - last.fontSize) <= last.fontSize * 0.1 else { return false }
        var uncertain: [ConversionWarning] = []
        let text = last.text.trimmingCharacters(in: .whitespaces)
        let operation = joinOperation(text + "-", next.text, vocabulary: vocabulary, page: 0, lexicon: false,
                                      warnings: &uncertain)
        guard uncertain.isEmpty, case .removeHyphen = operation else { return false }
        return true
    }

    /// One word broken across `left` and `right`, with the book's evidence for the join (#148).
    /// `left` ends in a hyphen after two letters, `right` opens lowercase, and the hyphen policy
    /// decides the break without warning `uncertainHyphen`, so the book prints the joined word
    /// (or the compound) and the halves are not being guessed at. This is the evidence
    /// `joinWordBreaks` already requires of two blocks; a break is the same evidence wherever the
    /// halves ended up, and it stands where a line's other ink would not read as prose (Loper
    /// Bright page 11 ends `§§1854(d)(2)(B), 1862(b)(2)(E). And in general, it author-` over
    /// page 12's `izes the Secretary…`).
    static func continuesWordBreak(_ left: String, _ right: String, vocabulary: Set<String>) -> Bool {
        guard left.hasSuffix("-"), left.dropLast().suffix(2).filter(\.isLetter).count == 2,
              right.first?.isLowercase == true else { return false }
        var uncertain: [ConversionWarning] = []
        _ = joinOperation(left, right, vocabulary: vocabulary, page: 0, warnings: &uncertain)
        return uncertain.isEmpty
    }

    /// A paragraph cut by the page ends on a full prose line. The column is the same-size lines
    /// sharing the line's left edge (widening to indented neighbours, then the page, until three
    /// lines are found). A justified column, where most lines share the right edge, demands that
    /// edge; a ragged column accepts three quarters of its measure. A line-ending hyphen is
    /// continuation evidence on its own.
    private static func fillsColumn(_ last: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        let text = last.text.trimmingCharacters(in: .whitespaces)
        if let ending = text.last, ending == "-" || ending == "\u{00ad}" { return true }
        guard wordCount(text) >= 3, last.rect.width >= body * 12 else { return false }
        let size = Int(last.fontSize.rounded())
        let sized = lines.filter { Int($0.fontSize.rounded()) == size }
        guard let edges = [0.5, 1.5, CGFloat.infinity].lazy.map({ tolerance in
            sized.filter { abs($0.rect.minX - last.rect.minX) < body * tolerance }.map(\.rect.maxX).sorted(by: >)
        }).first(where: { $0.count >= 3 }) else { return false }
        let reaching = edges.filter { $0 >= edges[0] - body * 0.5 }.count
        if reaching * 5 >= edges.count * 3 { return last.rect.maxX >= edges[0] - body * 0.5 }
        return last.rect.width >= (edges[2] - last.rect.minX) * 0.75
    }

    /// Text that competes with a join anchor: a line at least `share` of the anchor's width,
    /// except captions and margin folios; inside a preserved region it must also be the
    /// anchor's size, so figure labels do not count but swallowed body text does.
    private static func isProse(_ other: TextLine, beside line: TextLine, share: CGFloat,
                                page: PageContent, images: [CGRect], captions: [String] = []) -> Bool {
        let text = other.text.trimmingCharacters(in: .whitespaces)
        guard other != line, !text.isEmpty, other.rect.width >= line.rect.width * share,
              !isCaption(text), !(isFolio(text) && inMargin(other, of: page)) else { return false }
        // A caption's wrapped lines, set smaller than the anchor, belong to the caption (FAA page
        // 21's `Richard “Pete” Quesada, 1959–1961.` under `Figure 1-10.`).
        if other.fontSize < line.fontSize * 0.95 {
            var wrapped = text
            if wrapped.last == "-" || wrapped.last == "\u{00ad}" { wrapped.removeLast() }
            if wrapped.count >= 3, captions.contains(where: { $0.contains(wrapped) }) { return false }
        }
        guard images.contains(where: { $0.intersects(other.rect) }) else { return true }
        return Int(other.fontSize.rounded()) == Int(line.fontSize.rounded())
    }

    /// Prose below the last line, even a short swallowed line, means the paragraph did not end
    /// the page; a column of prose to its right (lines as wide as the anchor, so a name column
    /// beside a hanging-indent entry does not count) means the anchor is not the last column.
    private static func endsColumn(_ last: TextLine, in page: PageContent, images: [CGRect], captions: [String]) -> Bool {
        // Page-bottom footnotes (smaller type under a dash separator) are not the body's continuation.
        let separator = page.lines.filter { FootnoteDetector.isSeparator($0) && $0.rect.midY < last.rect.minY }
            .map(\.rect.minY).max()
        return !page.lines.contains { other in
            if let separator, other.rect.midY < separator, other.fontSize <= last.fontSize * 0.9 { return false }
            let below = other.rect.midY < last.rect.minY && other.rect.maxX > last.rect.minX && other.rect.minX < last.rect.maxX
            let beside = other.rect.minX >= last.rect.maxX
            return below && isProse(other, beside: last, share: 0.5, page: page, images: images, captions: captions)
                || beside && isProse(other, beside: last, share: 0.9, page: page, images: images, captions: captions)
        }
    }

    private static func opensColumn(_ first: TextLine, in page: PageContent, images: [CGRect], captions: [String]) -> Bool {
        !page.lines.contains { other in
            let above = other.rect.midY > first.rect.maxY && other.rect.maxX > first.rect.minX && other.rect.minX < first.rect.maxX
            let beside = other.rect.maxX <= first.rect.minX
            return above && isProse(other, beside: first, share: 0.5, page: page, images: images, captions: captions)
                || beside && isProse(other, beside: first, share: 0.9, page: page, images: images, captions: captions)
        }
    }

    /// The groups of the aviation weather report formats (METAR/SPECI, TAF, PIREP; FAA-H-8083-25C
    /// chapter 13) a line carries, or nil when the line cannot belong to a coded report because a
    /// token holds a lowercase letter or a character the formats never use. Groups are a
    /// date-time group (`161753Z`), wind (`14021G26KT`), visibility (`3/4SM`, `P6SM`), sky
    /// condition (`OVC012CB`), temperature and dew point (`18/17`), altimeter (`A2970`), a valid
    /// period (`1112/1212`), a change group (`FM1500`, `TEMPO`, `PROB30`), the report types and
    /// modifiers (`METAR`, `AUTO`, `RMK`), coded weather (`+TSRA`, `BR`) and PIREP fields
    /// (`UA/OV`, `C182/SK`).
    static func codedReportGroupCount(_ text: String) -> Int? {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty, tokens.allSatisfy({ token in
            token.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || "/+-".contains($0)) }
        }) else { return nil }
        return tokens.indices.reduce(0) { count, index in
            let word = String(tokens[index])
            let fields = word.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
                .filter { codedReportFields.contains(String($0)) }.count
            if fields > 0 { return count + fields + (word.hasPrefix("UA/") || word.hasPrefix("UUA/") ? 1 : 0) }
            // A station identifier is four letters or digits only before the report's date-time group.
            let station = word.range(of: "^[A-Z][A-Z0-9]{3}$", options: .regularExpression) != nil
                && index + 1 < tokens.count && tokens[index + 1].range(of: "^[0-9]{6}Z$", options: .regularExpression) != nil
            return count + (station || word.range(of: codedReportGroup, options: .regularExpression) != nil ? 1 : 0)
        }
    }

    private static let codedReportFields: Set<String> = ["OV", "TM", "FL", "TP", "SK", "WX", "TA", "WV", "TB", "IC", "RM"]

    private static let codedReportGroup = "^(?:[0-9]{6}Z|(?:[0-9]{3}|VRB)[0-9]{2,3}(?:G[0-9]{2,3})?KT|P?[0-9]{1,2}SM|M?[0-9]/[0-9]SM"
        + "|(?:FEW|SCT|BKN|OVC|VV)[0-9]{3}(?:CB|TCU)?|SKC|CLR|M?[0-9]{2}/M?[0-9]{2}|A[0-9]{4}|[0-9]{4}/[0-9]{4}"
        + "|FM[0-9]{4,6}|TEMPO|BECMG|PROB[0-9]{2}|METAR|SPECI|TAF|AUTO|COR|AMD|RMK"
        + "|[+-]?(?:VC)?(?:MI|PR|BC|DR|BL|SH|TS|FZ)?(?:DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)+)$"

    /// A line that is only a report type (`TAF` above `KPIR 111130Z 1112/1212`, FAA page 319).
    static func isCodedReportType(_ text: String) -> Bool {
        text.range(of: "^(?:METAR|SPECI|TAF)(?: AMD| COR)?$", options: .regularExpression) != nil
    }

    /// The runs of lines, in reading order, that set one coded weather report over several lines
    /// (#96). The source sets each report line as a paragraph of its own, so no layout evidence
    /// joins a METAR's wrapped `…A2970 RMK` / `PRESFR` while keeping a TAF's change groups apart;
    /// the report's own format does. A run opens on a line of at least three report groups, or on
    /// a lone report type directly above such a line. It continues through lines in the same
    /// column at ordinary leading and size that hold only report characters, carry a report group
    /// (or follow `RMK`, whose remarks are free text in capitals) and do not open another report.
    /// Each member records whether the source's break before it is significant: after a lone
    /// report type and before a TAF change group (`FM1500`, `TEMPO`, `BECMG`, `PROB30`) it is; a
    /// report wrapped at the column's edge is not.
    static func codedReportRuns(_ lines: [TextLine], body: CGFloat) -> [[(index: Int, lineBreak: Bool)]] {
        var runs: [[(index: Int, lineBreak: Bool)]] = []
        var current: [(index: Int, lineBreak: Bool)] = []
        var remarks = false
        func close() {
            if current.count >= 2 { runs.append(current) }
            current = []
            remarks = false
        }
        func holdsRemarks(_ text: String) -> Bool { text.split(whereSeparator: \.isWhitespace).contains("RMK") }
        for (index, line) in lines.enumerated() {
            let count = line.monospaced ? nil : codedReportGroupCount(line.text)
            if let last = current.last.map({ lines[$0.index] }), let count {
                let gap = last.rect.minY - line.rect.maxY
                let opensReport = line.text.range(of: "^(?:METAR|SPECI|TAF|UUA|UA)(?:\\s|/|$)", options: .regularExpression) != nil
                if abs(last.rect.minX - line.rect.minX) <= body * 0.5, abs(last.fontSize - line.fontSize) <= 0.5,
                   gap >= -body * 0.4, gap < body * 0.9, !opensReport, count >= 1 || remarks {
                    let changeGroup = line.text.range(of: "^(?:FM[0-9]{4,6}|TEMPO|BECMG|PROB[0-9]{2})(?:\\s|$)",
                                                      options: .regularExpression) != nil
                    current.append((index, isCodedReportType(last.text) || changeGroup))
                    remarks = remarks || holdsRemarks(line.text)
                    continue
                }
            }
            close()
            guard let count else { continue }
            let next = index + 1 < lines.count ? codedReportGroupCount(lines[index + 1].text) ?? 0 : 0
            if count >= 3 || isCodedReportType(line.text) && next >= 3 {
                current = [(index, false)]
                remarks = holdsRemarks(line.text)
            }
        }
        close()
        return runs
    }

    /// A numeric parenthesis marker set tight against a minus sign (`1)− 2`, as the algebra
    /// answer keys extract) is also a list item; the period form stays space-delimited so
    /// dedented note continuations such as `5.This` keep their existing handling. A plus sign is a
    /// bullet too (#194) when words follow it: the dietary guidelines set their top-level items with
    /// `+` and the items beneath them with `-`, so without it the parents were paragraphs and the
    /// children list items. The item opens on a word (or a percentage, `+ 100% fruit or vegetable
    /// juice`) and reads as words; a row of a derivation that opens with a plus (`+ 21 + 21 Add 21 to
    /// both sides`, Wallace page 40) stays what it was.
    static func isList(_ text: String) -> Bool {
        if text.hasPrefix("+"), text.dropFirst().first?.isWhitespace == true {
            return text.range(of: "^\\+\\s+(?:\\p{L}{2}|[0-9]+%)", options: .regularExpression) != nil
                && isWordy(String(text.dropFirst(2)))
        }
        return text.range(of: "^(?:(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s|[0-9]+\\)−)", options: .regularExpression) != nil
    }

    /// A line opening with the `+` bullet (#194), which a paragraph group holding it as its only
    /// list line keeps as one item.
    static func opensWithPlusBullet(_ text: String) -> Bool {
        text.hasPrefix("+") && isList(text)
    }

    /// The tagged list item of pieces joined into one line (#194): the leftmost piece's, which
    /// carries the label, when no piece names another item.
    static func sharedListTag(_ pieces: [TextLine]) -> ListTag? {
        let tags = pieces.compactMap(\.listTag)
        guard let first = pieces.first?.listTag ?? tags.first, tags.allSatisfy({ $0.item == first.item }) else { return nil }
        return first
    }

    /// The evidence a list-marker line leaves for `ListBuilder` (#194).
    static func listEvidence(_ line: TextLine, recognized: Bool) -> ReflowBlock.ListEvidence {
        ReflowBlock.ListEvidence(edge: line.rect.minX, fontSize: line.fontSize, recognized: recognized, tag: line.listTag)
    }

    /// A numbered or lettered marker opening a line (`12.`, `b)`, `P.`) before a space: its kind
    /// (0 digits, 1 a lowercase letter, 2 a capital), punctuation and value. Bullets, the tight
    /// `1)−` answer form and unmarked text carry none.
    struct ListMarker: Equatable {
        var kind: Int
        var punctuation: Character
        var value: Int

        init?(_ text: String) {
            guard let range = text.range(of: "^(?:[0-9]{1,9}|[A-Za-z])[.)](?=\\s)", options: .regularExpression),
                  let punctuation = text[range].last else { return nil }
            let token = text[range].dropLast()
            if let number = Int(token) {
                (kind, value) = (0, number)
            } else if let letter = token.first, let ascii = letter.asciiValue {
                (kind, value) = (letter.isUppercase ? 2 : 1, Int(ascii))
            } else { return nil }
            self.punctuation = punctuation
        }

        /// The next or previous marker of this list, or the one after that: Wallace's answer keys
        /// print the odd exercises only (`11) 4`, `13) 3`).
        func isSibling(of other: ListMarker) -> Bool {
            kind == other.kind && punctuation == other.punctuation && (1...2).contains(abs(value - other.value))
        }
    }

    /// The numbered and lettered markers opening this page's lines, with their type size, which
    /// the pipeline records during extraction so the neighbouring pages' blocks can read a list
    /// that continues across the page boundary (9/11 pages 146–147's items `1.` to `3.`, #146).
    static func listMarkers(on page: PageContent) -> [PageMarker] {
        page.lines.compactMap { line in
            guard !line.monospaced, let marker = ListMarker(line.text) else { return nil }
            return PageMarker(marker: marker, fontSize: line.fontSize)
        }
    }

    struct PageMarker: Equatable {
        var marker: ListMarker
        var fontSize: CGFloat
    }

    /// A numbered section title set as a label: a one- or two-digit number and period before a
    /// title wholly in capitals or wholly bold (the NASA Word paper's 12-point bold `2. TEST
    /// DESCRIPTION` over 10-point prose, #154). An answer-key entry (`1) 6p− 42`) or a list item
    /// in text type is neither, nor is a contents entry ending in its folio (`1. “WE HAVE SOME PLANES”
    /// 1`), and `sectionLabels` also refuses a number another line on the page
    /// continues: the 9/11 report's contents set `11. FORESIGHT—AND HINDSIGHT` over `12. WHAT TO
    /// DO?`, each folio on a line of its own.
    static func isNumberedTitle(_ line: TextLine, body: CGFloat) -> Bool {
        guard let range = line.text.range(of: "^[0-9]{1,2}\\.\\s+", options: .regularExpression),
              line.text.range(of: "\\s[0-9]+$", options: .regularExpression) == nil else { return false }
        let letters = line.text[range.upperBound...].filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        return letters.allSatisfy(\.isUppercase) || LabelStyle(line, body: body).bold
    }

    private enum JoinOperation { case space, concatenate, removeHyphen }

    private static let addressCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&()*+,;=%")

    private static func isASCIIAlphanumeric(_ character: Character?) -> Bool {
        character.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
    }

    /// The web address `text` ends inside: the run of URL characters that ends it, after any
    /// whitespace, dash or quote (`(NACO)—www.faa.` on FAA page 372) and without leading opening
    /// punctuation, when that run has a scheme (`https://`), starts with `www.`, or opens with a
    /// domain and a slash (`ffiec.gov/`).
    static func trailingAddress(_ text: String) -> Substring? {
        let start = text.lastIndex(where: { !addressCharacters.contains($0) }).map { text.index(after: $0) } ?? text.startIndex
        let word = text[start...].drop { "([<:;,".contains($0) }
        guard word.count >= 2, word.contains("."),
              word.range(of: "^(?:[A-Za-z][A-Za-z0-9+.-]*://|www\\.|[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}/)",
                         options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return word
    }

    /// A line broken inside a web address continues it with no space (#79). The break is inside
    /// the address when the address ends in a character that cannot end one after a letter or
    /// digit (`bst_` + `openmarketops.htm`, `?content_` + `item_id=…`), in a dot after a letter or
    /// digit before a lowercase continuation (`https://www.` + `federalreserve.gov`) or a
    /// continuation that is not a bare number (`10.1080/14693062.` + `2022.2061405`, never `2004`),
    /// in a hyphen before a digit or capital (`Spec/02-` + `2004/Article…`), or when the next line
    /// opens with such a character (`www.federalreserve.gov` + `/monetarypolicy/…`). A hyphen
    /// before a lowercase letter is decided by `addressHyphenOperation`: the Fed's typesetter
    /// hyphenates inside addresses (`communi-` + `cations.htm`) as well as breaking at real ones. A period
    /// after a closing parenthesis, or before a capital, ends the sentence.
    private static func addressContinues(_ left: String, _ right: String) -> Bool {
        guard let next = right.first, let address = trailingAddress(left), let last = address.last else { return false }
        // A percent escape encodes a character the address continues past (`Lithium%20` +
        // `Batteries%200621_0.pdf`).
        if address.range(of: "%[0-9A-Fa-f]{0,2}$", options: .regularExpression) != nil {
            return isASCIIAlphanumeric(next) || next == "%"
        }
        let before = address.dropLast().last
        switch last {
        case "_", "=", "&", "?", "#", "%", "~":
            return isASCIIAlphanumeric(before) && isASCIIAlphanumeric(next)
        case ".":
            guard isASCIIAlphanumeric(before), next.isASCII else { return false }
            if next.isLowercase { return true }
            let word = right.prefix { !$0.isWhitespace }.reversed().drop { ".,;:)]".contains($0) }
            return next.isNumber && word.contains { !$0.isNumber }
        case "-":
            return next.isASCII && (next.isNumber || next.isUppercase)
        default:
            return isASCIIAlphanumeric(last) && "/._?#=&%~".contains(next) && isASCIIAlphanumeric(right.dropFirst().first)
        }
    }

    /// A line broken at a hyphen inside an alphanumeric code before a digit or capital continues
    /// the code with its hyphen and no space (#127): FBI serials (`265A-NY-` + `280350-HQ`,
    /// `315N-NY-280350-` + `BS`), report numbers (`CTC 2002-` + `30060CH`) and designations (`C-` +
    /// `130H`, `MI-` + `5`, `PA-` + `23`). The code is the run of
    /// ASCII letters, digits and hyphens ending the line (not after an address character) and the
    /// run opening the next, which must end at a space or closing punctuation. Every
    /// hyphen-separated segment is capitals and digits (`NY`, `280350`, `130H`) or digits with a
    /// short lowercase suffix (`7e`). One segment must mix digits and letters, or the line must end
    /// in a segment of capitals before a digit. Prose compounds, number ranges, citation ranges
    /// running into the next citation (`601-` + `CE 1318`) and hyphenated words before a folio
    /// (`pres-` + `62`) are no codes; `compoundOperation` decides them (#131).
    static func codeContinues(_ left: String, _ right: String) -> Bool {
        guard left.hasSuffix("-"), let next = right.first, next.isASCII, next.isNumber || next.isUppercase else { return false }
        let isCodeCharacter: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let leftRun = left.reversed().prefix(while: isCodeCharacter).reversed()
        if let before = left.dropLast(leftRun.count).last, "/._@:#?&=%~+\\".contains(before) { return false }
        let leftCode = String(leftRun.drop { $0 == "-" })
        let rightCode = String(right.prefix(while: isCodeCharacter))
        if let after = right.dropFirst(rightCode.count).first, !after.isWhitespace, !".,;:)]”’\"'".contains(after) {
            return false
        }
        let segments = (leftCode + rightCode).split(separator: "-", omittingEmptySubsequences: false)
        guard leftCode.count > 1, !rightCode.hasSuffix("-"), segments.count >= 2,
              !segments.contains(where: \.isEmpty) else { return false }
        func isUppercaseCode(_ segment: Substring) -> Bool { segment.allSatisfy { $0.isUppercase || $0.isNumber } }
        func isSuffixedNumber(_ segment: Substring) -> Bool {
            let digits = segment.prefix(while: \.isNumber)
            return !digits.isEmpty && (1...2).contains(segment.count - digits.count)
                && segment.dropFirst(digits.count).allSatisfy(\.isLowercase)
        }
        guard segments.allSatisfy({ isUppercaseCode($0) || isSuffixedNumber($0) }) else { return false }
        let mixed = segments.contains { $0.contains(where: \.isNumber) && $0.contains(where: \.isLetter) }
        let lastLeft = leftCode.dropLast().split(separator: "-").last ?? ""
        let capitals = lastLeft.count >= 2 && lastLeft.allSatisfy(\.isUppercase) && next.isNumber
        return mixed || capitals
    }

    /// A line-end hyphen before a capital or a digit, outside addresses and alphanumeric codes
    /// (#131). Nil leaves the join to the rules after it.
    ///
    /// - A word before a capital is a compound whose second half is a name or an acronym (`non-` +
    ///   `Muslims`, `Israeli-` + `Palestinian`, `Single-` + `Pilot`, `pre-` + `APA`): the hyphen
    ///   stays with no space. When the book prints the halves as one word and never the compound,
    ///   the hyphen goes (`CENT-` + `COM` where the notes print `CENTCOM`, `Harper-` + `Collins`).
    /// - A word of two or more letters before a digit keeps its hyphen only where the book sets
    ///   that word before a number inside a line (`mid-` + `1990s` beside `mid-1980s`, `pre-` +
    ///   `9/11`). Other words keep the space: a hyphen set for a dash (`Airplanes-` + `14 CFR`) or
    ///   a word broken before a folio (`pres-` + `62`).
    /// - A number before a number continues a number code or range (`CTC 96-` + `30015`, `SD
    ///   108-` + `00`, Warren's `pp. 105-` + `106`): both runs are digits and hyphens, standing
    ///   apart from other words, and one number has at least two digits (not the Blue Book's OCR
    ///   column labels `6-` + `7.`). A number before a capital is a citation running into the next
    ///   (`601-` + `CE 1318`) and keeps the space.
    private static func compoundOperation(_ left: String, _ right: String, vocabulary: Set<String>) -> JoinOperation? {
        guard left.hasSuffix("-"), let next = right.first, next.isUppercase || next.isNumber,
              let before = left.dropLast().last else { return nil }
        if before.isASCII, before.isNumber {
            guard next.isASCII, next.isNumber else { return nil }
            let isNumberCharacter: (Character) -> Bool = { $0.isASCII && ($0.isNumber || $0 == "-") }
            let leftRun = left.reversed().prefix(while: isNumberCharacter)
            if let outside = left.dropLast(leftRun.count).last, !outside.isWhitespace, !"([".contains(outside) { return nil }
            let rightRun = right.prefix(while: isNumberCharacter)
            if let after = right.dropFirst(rightRun.count).first, !after.isWhitespace, !".,;:)]”’\"'".contains(after) {
                return nil
            }
            let segments = (String(leftRun.reversed()) + rightRun).split(separator: "-", omittingEmptySubsequences: false)
            return segments.contains(where: \.isEmpty) || !segments.contains(where: { $0.count >= 2 }) ? nil : .concatenate
        }
        guard before.isLetter else { return nil }
        let prefix = String(left.dropLast().reversed().prefix(while: \.isLetter).reversed()).lowercased()
        if next.isNumber {
            return prefix.count >= 2 && vocabulary.contains(numberPrefixKey + prefix) ? .concatenate : nil
        }
        let suffix = right.prefix(while: \.isLetter).lowercased()
        if vocabulary.contains(prefix + suffix), !vocabulary.contains(prefix + "-" + suffix) { return .removeHyphen }
        return .concatenate
    }

    private static let addressDelimiters = Set("/.?#&=:")
    private static let addressPrefixKey = "\u{1}address:"
    private static let addressSegmentKey = "\u{1}segment:"
    private static let numberPrefixKey = "\u{1}number-prefix:"
    private static let dashKey = "\u{1}dash:"

    /// An address without its scheme or `www.`, lowercased: the form address evidence compares.
    static func normalizedAddress(_ address: Substring) -> String {
        var text = address.lowercased()
        if let scheme = text.range(of: "^[a-z][a-z0-9+.-]*://", options: .regularExpression) { text.removeSubrange(scheme) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return text
    }

    private static func uncertainHyphen(page: Int, warnings: inout [ConversionWarning]) {
        guard !warnings.contains(where: { $0.code == .uncertainHyphen && $0.page == page }) else { return }
        warnings.append(.init(code: .uncertainHyphen, page: page,
            message: "An ambiguous line-ending hyphen is retained. Review source word joins."))
    }

    /// A line-end hyphen inside a web address before a lowercase letter (#88). The Fed's
    /// typesetter hyphenates inside addresses (`federalreserve.gov/monetary-` + `policy/…`) and
    /// also breaks at real hyphens (`publications/page1-` + `econ/…`), and prose compounds say
    /// nothing about either, so the book's own addresses decide. The address through the broken
    /// segment, as seen unbroken elsewhere (`federalreserve.gov/monetarypolicy`), decides first;
    /// then the broken segment seen in any address (`dfa-stress-tests`). One form must be seen
    /// and the other not. Failing both, a break inside a word removes the hyphen: the letters on
    /// either side, with no digit beside them (never `page1-` + `econ`), join into a book word
    /// and are not both book words themselves (`communi-` + `cations.htm`; `cations` is a
    /// line-start fragment of prose hyphenation, `communi` is not a word). Otherwise the hyphen
    /// stays and the page warns.
    private static func addressHyphenOperation(_ address: Substring, _ right: String, vocabulary: Set<String>, page: Int,
                                               warnings: inout [ConversionWarning]) -> JoinOperation {
        let rest = right.prefix { addressCharacters.contains($0) && !addressDelimiters.contains($0) }
        let removed = normalizedAddress(Substring(address.dropLast() + rest))
        let kept = normalizedAddress(Substring(address + rest))
        func segment(_ text: String) -> Substring {
            text.lastIndex(where: { addressDelimiters.contains($0) }).map { text[text.index(after: $0)...] } ?? Substring(text)
        }
        for (removedKey, keptKey) in [(addressPrefixKey + removed, addressPrefixKey + kept),
                                      (addressSegmentKey + segment(removed), addressSegmentKey + segment(kept))] {
            switch (vocabulary.contains(removedKey), vocabulary.contains(keptKey)) {
            case (true, false): return .removeHyphen
            case (false, true): return .concatenate
            default: continue
            }
        }
        let prefix = address.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()
        let suffix = right.prefix(while: { $0.isLetter })
        let whole = !(address.dropLast().dropLast(prefix.count).last?.isNumber ?? false)
            && !(right.dropFirst(suffix.count).first?.isNumber ?? false)
        if whole, !prefix.isEmpty, !suffix.isEmpty, vocabulary.contains((String(prefix) + suffix).lowercased()),
           !vocabulary.contains(String(prefix).lowercased()) || !vocabulary.contains(suffix.lowercased()) {
            return .removeHyphen
        }
        uncertainHyphen(page: page, warnings: &warnings)
        return .concatenate
    }

    private static func joinOperation(_ left: String, _ right: String, vocabulary: Set<String>, page: Int,
                                      lexicon: Bool = true, warnings: inout [ConversionWarning]) -> JoinOperation {
        if left.hasSuffix("\u{00ad}") { return .removeHyphen }
        // A line broken after a slash inside a compound or an address (`runway/` + `taxiway`,
        // `and/` + `or`, `www.faa.gov/` + `pilots/`, `https://` + `www.`) continues it with no
        // space: a letter, digit or slash sits before the slash and a letter or digit follows
        // the break. A slash the source sets apart (`China /` + `East Asia`) keeps the space, as
        // does one after other punctuation, which in the corpus is only damaged OCR (#70).
        if left.hasSuffix("/"), let before = left.dropLast().last, before.isLetter || before.isNumber || before == "/",
           let next = right.first, next.isLetter || next.isNumber { return .concatenate }
        if addressContinues(left, right) { return .concatenate }
        if codeContinues(left, right) { return .concatenate }
        if let operation = compoundOperation(left, right, vocabulary: vocabulary) { return operation }
        guard left.hasSuffix("-"), right.first?.isLowercase == true else { return .space }
        if let address = trailingAddress(left) {
            return addressHyphenOperation(address, right, vocabulary: vocabulary, page: page, warnings: &warnings)
        }
        // A hyphen after a number joins a compound (`45-` + `degree-increment`, #155): no word breaks
        // inside a number, and the letters after it alone would otherwise read as the joined word.
        if let before = left.dropLast().last, before.isASCII, before.isNumber { return .concatenate }
        let prefix = left.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()
        let suffix = right.prefix(while: { $0.isLetter })
        let joined = (String(prefix) + suffix).lowercased()
        let compound = (String(prefix) + "-" + suffix).lowercased()
        if vocabulary.contains(joined), !vocabulary.contains(compound) { return .removeHyphen }
        if vocabulary.contains(compound) { return .concatenate }
        if inflectionVouches(prefix: String(prefix).lowercased(), suffix: suffix.lowercased(), vocabulary: vocabulary) {
            return .removeHyphen
        }
        if lexicon, lexiconVouches(prefix: String(prefix).lowercased(), suffix: suffix.lowercased(), vocabulary: vocabulary) {
            return .removeHyphen
        }
        uncertainHyphen(page: page, warnings: &warnings)
        return .concatenate
    }

    /// Marks the vocabulary of a document declared English, whose word breaks the system's English
    /// lexicon may decide (`lexiconVouches`, #186).
    static let englishLexiconKey = "\u{1}lexicon:en"

    /// A line-end hyphen the book's own words cannot decide, in an English document (#186). A
    /// 24-page magazine prints `com-` + `panies`, `infec-` + `tions` and `compli-` + `ance` and never
    /// the words whole or in another inflection, so #115's evidence is missing although the words are
    /// ordinary. The system's English lexicon (`TextLayerPlausibility.lexiconContains`, the list the
    /// text-layer judgement reads) vouches for the join when it holds the joined word and the halves
    /// are not both words, of the lexicon or the book, with #115's lengths: two letters a side and six
    /// in all. The compound was already refused: the book prints neither it nor an inflection of it.
    /// A compound whose halves are both words (`on-` + `going`, `sharp-` + `edged`) keeps its hyphen
    /// and warns, as before. Only a hyphen the page printed consults the lexicon; a hyphen PDFKit lost
    /// (#157) needs the book's own evidence.
    static func lexiconVouches(prefix: String, suffix: String, vocabulary: Set<String>) -> Bool {
        guard vocabulary.contains(englishLexiconKey), prefix.count >= 2, suffix.count >= 2, prefix.count + suffix.count >= 6,
              TextLayerPlausibility.lexiconContains(prefix + suffix) == true else { return false }
        func word(_ text: String) -> Bool { vocabulary.contains(text) || TextLayerPlausibility.lexiconContains(text) == true }
        return !(word(prefix) && word(suffix))
    }

    private static let inflections = ["s", "es", "d", "ed", "ing", "ly"]

    /// The forms a word shares its stem with: the word, and the word without one inflectional
    /// ending, with a dropped final `e` restored (`separates` → `separate`, `distributing` →
    /// `distribut`, `distribute`), each with every ending added back.
    static func inflectedForms(_ word: String) -> Set<String> {
        var stems: Set<String> = [word]
        for ending in inflections where word.hasSuffix(ending) && word.count - ending.count >= 4 {
            let stem = String(word.dropLast(ending.count))
            stems.insert(stem)
            if !stem.hasSuffix("e") { stems.insert(stem + "e") }
        }
        var forms = stems
        for stem in stems {
            for ending in inflections {
                forms.insert(stem + ending)
                if stem.hasSuffix("e"), ending.first.map({ "ei".contains($0) }) == true { forms.insert(stem.dropLast() + ending) }
            }
        }
        return forms
    }

    /// A line-end hyphen neither the joined word nor the compound decides (#115). The book vouches
    /// for the join when it uses another inflected form of the joined word (`sep-` + `arates`, where
    /// Wallace prints `separate`, `separated` and `separately` but never `separates`), no inflected
    /// form of the compound, and the halves are not both words of their own, as a compound's halves
    /// are (`sharp-` + `edged`). Short stems are not evidence.
    static func inflectionVouches(prefix: String, suffix: String, vocabulary: Set<String>) -> Bool {
        guard prefix.count >= 2, suffix.count >= 2, prefix.count + suffix.count >= 6,
              !(vocabulary.contains(prefix) && vocabulary.contains(suffix)) else { return false }
        let joined = prefix + suffix
        let compounds = inflectedForms(joined).compactMap { form -> String? in
            guard form.hasPrefix(prefix), form.count > prefix.count else { return nil }
            return prefix + "-" + form.dropFirst(prefix.count)
        }
        guard !compounds.contains(where: vocabulary.contains) else { return false }
        return inflectedForms(joined).contains { $0 != joined && vocabulary.contains($0) }
    }

    static func join(_ left: String, _ right: String, vocabulary: Set<String>, page: Int,
                     warnings: inout [ConversionWarning]) -> String {
        switch joinOperation(left, right, vocabulary: vocabulary, page: page, warnings: &warnings) {
        case .space: left + " " + right
        case .concatenate: left + right
        case .removeHyphen: String(left.dropLast()) + right
        }
    }

    static func join(_ left: InlineText, _ right: InlineText, vocabulary: Set<String>, page: Int,
                     sourceBoundary: Int? = nil, warnings: inout [ConversionWarning]) -> InlineText {
        var result = left
        switch joinOperation(left.text, right.text, vocabulary: vocabulary, page: page, warnings: &warnings) {
        case .space: result.append(InlineText(" "))
        case .concatenate: break
        case .removeHyphen: result.removeLastCharacter()
        }
        if let sourceBoundary { result.elements.append(.sourcePage(sourceBoundary)) }
        result.append(right)
        return result
    }
}
