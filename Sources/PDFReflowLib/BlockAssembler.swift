import CoreGraphics
import Foundation

/// What one spatial line becomes in the logical document.
enum LineRole: Equatable, Sendable {
    /// A heading-size line, or a recurring bold sub-heading label.
    case heading
    /// Monospaced code, which keeps its line breaks and indentation.
    case code
    /// A line opening with a bullet, which keeps its break.
    case listItem
    /// A line opening with a number or a single letter and a point. It opens a list item, or it
    /// is a wrapped line whose first word is an initial, a citation or a year (`W. Bush`,
    /// `U. S. 760`, `2016.`) and belongs to the paragraph above it (#39, #238). Only the
    /// assembler knows what the previous line did, and only the page knows the column this line
    /// sits in, so the page's half of the evidence travels with the role.
    case markedLine(MarkerColumn)
    /// One printed row of a table the page set without rules, which keeps its break. The pieces
    /// the extractor left standing side by side on that row rejoin into it, and so does a cell
    /// that wrapped onto the next line, which the block's own left edge tells apart from the row
    /// beneath it (#137, #210).
    case tableRow(continuation: Bool)
    /// Ordinary prose, joined into paragraphs.
    case prose
}

/// The kind of list marker a line opens with: whether the page numbered or lettered it, and the
/// point or bracket that closes it. Two items belong to one list when their markers agree on
/// both, which is what lets an item whose marker stands alone on its line be vouched for by an
/// item that carries its own text (#172).
struct MarkerKind: Equatable, Sendable {
    let numbered: Bool
    let terminator: Character
}

/// Where a marker-leading line sits in the column of same-size lines around it: the page-level
/// evidence that separates the opening of a list item from a wrapped continuation (#39).
struct MarkerColumn: Equatable, Sendable {
    /// Whether the line stands on the left edge most of its column shares. A hanging list marker
    /// beside dedented continuation lines does not.
    let onMajorityEdge: Bool
    /// The right edge at least three same-size lines of the column reach, when the column is
    /// justified; nil when ragged item lengths establish no margin to fill.
    let justifiedRight: CGFloat?
    /// Whether the page may be setting a list on this line's own edge. A list marks its items, so
    /// a page that stands a run of lines on one edge and marks fewer than a quarter of them has
    /// set no list there, and the point after the first token is a name's initial, a page
    /// reference or a citation instead (#171). Below the run the reading stays as it was: a list
    /// of one item, or a marker among three lines, states too little to be read either way.
    let setsAList: Bool

    /// How many lines a page must stand on one edge before the share of them it marks says
    /// anything. Eight is a column of prose or a stack of entries; fewer is a list of one item,
    /// an introduced pair, or a page too bare to read either way.
    static let shortestUnmarkedRun = 8
}

extension LayoutReconstructor {
    /// Whether a line reads as a heading by its size: at or above the heading threshold, under
    /// 200 characters, opening with a capital, a digit or a mark unless it stacks with another
    /// display-size line (#186), and, on a recognized page in an English book, reading as words
    /// (#7).
    static func isTitleSized(_ line: TextLine, in lines: [TextLine], typography: PageTypography,
                             judgesTitleWords: Bool) -> Bool {
        guard line.fontSize >= typography.headingThreshold, line.text.count < 200,
              line.text.first?.isLowercase != true || stacksWithDisplay(line, in: lines, typography: typography),
              !judgesTitleWords || EnglishText.readsAsWords(line.text) else { return false }
        if judgesTitleWords {
            // Vision's box height is an estimate of type size. On Warren 501 a body sentence's
            // tall box overlaps three pieces of its own printed row; on Warren 566 a form value
            // stands beside its labels; Blue Book 150 repeats word column heads across a row.
            // None heads the row next to it. A genuine title may share a height with text in a
            // distant second column, so only a nearby piece vetoes it (#216).
            let own = line.uprightRect
            let near = max(typography.body * 3, line.fontSize * 1.5)
            if lines.contains(where: { other in
                guard other != line, line.sharesRow(with: other) else { return false }
                let next = other.uprightRect
                let gap = max(0, max(own.minX - next.maxX, next.minX - own.maxX))
                return gap <= near
            }) { return false }
        }
        return true
    }

    /// A heading-size line standing alone that opens in lowercase is display text that heads
    /// nothing: a magazine cover's title line "From Insects" can be followed by a lowercase
    /// cross-reference line "pages 2, 4-14" set at the same size, which is not itself a title
    /// (#186). A line stacked with another of its size, above or below, is part of a title or a
    /// pull quote and keeps its size's reading.
    static func stacksWithDisplay(_ line: TextLine, in lines: [TextLine], typography: PageTypography) -> Bool {
        lines.contains { other in
            other != line && other.fontSize >= typography.headingThreshold
                && (stacksUnderHeading(line, after: other) || stacksUnderHeading(other, after: line))
        }
    }

    /// Whether a line is the page's own number standing in its outer margin, which is furniture
    /// a title cannot be.
    ///
    /// *Our Flag* prints its folio in 8.93-point type on picture pages whose body is 7.00, so the
    /// number clears the heading threshold; the page's navigation is built from its headings,
    /// because the document states no table of contents of its own, and fifteen of that book's
    /// fifty-four navigation entries were page numbers — `9`, `26`, `27`, `28` — among its
    /// chapter titles (#290).
    ///
    /// The folio is furniture that survives: it stands at 0.081 of the sheet where the footer
    /// candidate band reaches 0.07, and that band is narrow on purpose, because widening it
    /// disturbs the reading order of this same book's illustrated rows. Refusing to call the
    /// number a *title* moves nothing in the reading order, so it does not touch what that
    /// narrowness protects; the line still reflows, as text.
    ///
    /// The outer tenth, and a bare number only. The 9/11 report sets its chapter numbers above
    /// their titles — `1` over `“WE HAVE`, `2` over `THE FOUNDATION OF` — at the head of a
    /// chapter-opening page and well inside the type area, and those are titles of a kind; so are
    /// IRS Publication 596's numbered sections. A number in the margin is the page's own.
    static func isFolioInTheMargin(_ line: TextLine, on page: PageContent) -> Bool {
        let height = page.bounds.height
        guard height > 0, page.bounds.isFinite,
              line.text.count(where: { !$0.isWhitespace }) <= 4,
              line.text.contains(where: \.isNumber),
              !line.text.contains(where: { $0.isLetter }) else { return false }
        let position = (line.rect.midY - page.bounds.minY) / height
        return position <= 0.10 || position >= 0.90
    }

    /// The role of an untagged line outside any note group. A synthetic-style page (invisible
    /// text over a scan) supplies no typography, so its lines are prose or list items only;
    /// `labels` are the page's recurring bold sub-headings, already empty on such pages.
    static func role(of line: TextLine, on page: PageContent, in lines: [TextLine], typography: PageTypography,
                     labels: [TextLine], judgesTitleWords: Bool, rightToLeft: Bool = false) -> LineRole {
        // A bulleted line is an item of a list, whatever size its text is set in: a page that
        // draws a bullet has said the line belongs to a list, which a heading does not (#254).
        // This is what lets the line's size be read from its text in both directions; a numbered
        // or lettered marker is not evidence of the same kind, because a heading can be numbered.
        // The rest of such an item carries no marker of its own — the marker is on the line above
        // it — so the page states the relationship instead, in the indent it hangs under (#256).
        // A glyph the page keys its own material to marks a note in the same way (#259).
        if !page.hasSyntheticTextStyle, !opensWithMarker(line, keyedIn: page.lines),
           isTitleSized(line, in: lines, typography: typography, judgesTitleWords: judgesTitleWords)
            || labels.contains(line),
           !hangsUnderBullet(line, in: lines, keyedIn: page.lines),
           !isFolioInTheMargin(line, on: page) {
            return .heading
        }
        if !page.hasSyntheticTextStyle && line.monospaced { return .code }
        if isMarked(line.text) { return .markedLine(markerColumn(of: line, in: lines, body: typography.body)) }
        // A marker is a marker because the page set it at the start of a printed line. A piece
        // the extractor cut out of the middle of a row began no line, so what opens it is
        // whatever the page was printing there — an operator, not a list marker (#203).
        if isList(line.text),
           !continuesPrintedRow(line, in: lines, body: typography.body, rightToLeft: rightToLeft) { return .listItem }
        // A marker the extractor left alone on its line is still a marker, where the page says
        // so (#172).
        if opensAloneAsMarker(line, in: lines, body: typography.body) {
            return .markedLine(markerColumn(of: line, in: lines, body: typography.body))
        }
        // So is a bullet the extractor left alone on its line, where the page set the item it
        // marks beside it (#261).
        if opensAloneAsBullet(line, in: lines, body: typography.body, rightToLeft: rightToLeft) {
            return .listItem
        }
        return .prose
    }

    /// Whether `line` is a list marker the extractor left with none of its item's text: the whole
    /// of the line is a number or a single letter with a point or a bracket.
    ///
    /// Both marker tests require whitespace after that point or bracket, because the item's own
    /// text follows it. PDFKit ends a line wherever the page leaves a gap, so an item whose marker
    /// the page hangs a little further out comes back as two lines and the first matches neither
    /// test: Wallace's page 101 returns `17)` and `(− 16,− 14), (11,− 14)` where every other
    /// exercise on the page is one line, and exercise 17 was read as prose and emitted as a `<p>`
    /// paragraph in a page of `<pre>` items (#172; the same page's `9)` and `10)` once their line
    /// is split, [#14](https://github.com/vocaro/PDFReflowLib/issues/14)).
    ///
    /// A marker standing alone carries no text of its own to vouch for it, and a number with a
    /// point is also how a citation ends, so the page must vouch for it twice over:
    ///
    /// - **its row is a row of items, not a row of cells.** Everything the page set to its right
    ///   on that row must be either within the three quarters of a body a column's gutter needs —
    ///   the item's own text, which `continuesRow` then joins to it — or a marker of the same list
    ///   again, which is the next column of a grid of items. Wallace sets exercises 17 and 18 on
    ///   one row, four points and a column apart; NOAA hangs a reference's number a column from
    ///   its entry, and the Blue Book's tables set a figure beside a number, and those entries and
    ///   figures are neither. A row of cells belongs to the table readers
    ///   ([#210](https://github.com/vocaro/PDFReflowLib/issues/210)). A piece to the *left* of it
    ///   within that gutter means the extractor cut this line out of the middle of a row, so what
    ///   opens it is whatever the page printed there and not a marker at all (#203);
    /// - **the page states the list.** Another line of its size, on its own left edge, opens an
    ///   item of the same list — the same marker kind, numbered or lettered and closed the same
    ///   way — and carries that item's own text after it. The 9/11 report's notes leave a
    ///   citation's year on a line of its own (`2001.`) in a column whose note numbers are set in
    ///   from it, so nothing on that edge vouches for it and it stays the prose it is.
    static func opensAloneAsMarker(_ line: TextLine, in lines: [TextLine], body: CGFloat) -> Bool {
        guard let kind = markerKind(of: line.text, whole: true),
              !continuesPrintedRow(line, in: lines, body: body) else { return false }
        let gutter = body * 0.75
        // A deck may hang every marker away from its words. Require a second marker of the
        // same kind on the same edge, with each marker paired to one nearby row of words.
        // Earthdata slide 7 prints 1–3 and a–b this way; a lone citation year cannot pass.
        let pairedMarkers = lines.filter { candidate in
            guard markerKind(of: candidate.text, whole: true) == kind,
                  candidate.hasSize(line.fontSize),
                  abs(candidate.rect.minX - line.rect.minX) < body * 0.5,
                  let item = pieceBeside(candidate, in: lines) else { return false }
            let gap = item.rect.minX - candidate.rect.maxX
            return gap >= gutter && gap < body
                && markerKind(of: item.text, whole: true) == nil
        }
        func ordinal(_ marker: TextLine) -> Int? {
            let token = marker.text.dropLast()
            if token.count <= 3, let number = Int(token) { return number }
            guard token.count == 1, let scalar = token.first?.lowercased().unicodeScalars.first else { return nil }
            return Int(scalar.value - 96)
        }
        let sequence = pairedMarkers.sorted { $0.rect.minY > $1.rect.minY }
        if zip(sequence, sequence.dropFirst()).contains(where: { before, after in
            (before == line || after == line) && ordinal(before).map { $0 + 1 == ordinal(after) } == true
        }) { return true }
        for other in lines where other != line && other.sharesRow(with: line)
            && other.rect.minX >= line.rect.maxX {
            guard other.rect.minX - line.rect.maxX < gutter
                || markerKind(of: other.text, whole: true) == kind
                || markerKind(of: other.text, whole: false) == kind else { return false }
        }
        return lines.contains { other in
            other != line && other.hasSize(line.fontSize)
                && abs(other.rect.minX - line.rect.minX) < body * 0.5
                && markerKind(of: other.text, whole: false) == kind
        }
    }

    /// What kind of list marker a text opens with: whether the page numbered or lettered it, and
    /// the point or bracket that closes it. `whole` demands that the marker be the entire text;
    /// otherwise the item's own words must follow it after a space, as `isMarked` requires.
    /// Numbers are ASCII digits and letters single ASCII letters, exactly as those tests read them.
    static func markerKind(of text: String, whole: Bool) -> MarkerKind? {
        var index = text.startIndex
        var digits = 0
        while index < text.endIndex, text[index].isASCII, text[index].isNumber {
            digits += 1
            index = text.index(after: index)
        }
        if digits == 0 {
            guard index < text.endIndex, text[index].isASCII, text[index].isLetter else { return nil }
            index = text.index(after: index)
        }
        guard index < text.endIndex else { return nil }
        let terminator = text[index]
        guard terminator == "." || terminator == ")" else { return nil }
        index = text.index(after: index)
        if whole {
            guard index == text.endIndex else { return nil }
        } else {
            guard index < text.endIndex, text[index].isWhitespace else { return nil }
        }
        return MarkerKind(numbered: digits > 0, terminator: terminator)
    }

    /// Whether the extractor cut `line` out of the middle of a printed row: another line stands
    /// on its row, ends at or before its left edge, and is nearer than the gutter a column needs
    /// (`LayoutReconstructor.ordered`'s three quarters of a body, the bound `continuesRow` already
    /// uses to rejoin such pieces). Wallace breaks a row after a raised exponent, so `8x²` is one
    /// line and `− 2x − 15` the next, and the minus the page printed between two terms read as a
    /// bullet: the second piece became an item of a list, in a `<pre>` block of its own, in the
    /// middle of the derivation it belongs to (#203).
    ///
    /// A table's cells and a page's columns stand further apart than that and are unaffected, and
    /// a piece that opens its row has nothing to its left, so a genuine marker still opens an item.
    static func continuesPrintedRow(_ line: TextLine, in lines: [TextLine], body: CGFloat,
                                    rightToLeft: Bool = false) -> Bool {
        lines.contains { other in
            // The piece that opened the row stands to the right where the writing runs that way.
            let gap = rightToLeft ? other.rect.minX - line.rect.maxX : line.rect.minX - other.rect.maxX
            return gap >= 0 && gap < body * 0.75 && other.sharesRow(with: line)
        }
    }

    /// A line a page opens with a bullet glyph and a space. The alphanumeric markers `isList`
    /// also accepts are deliberately not here: `1. Introduction` is a heading in many books.
    static func opensWithBullet(_ text: String) -> Bool {
        text.range(of: "^[•*−–—-]\\s", options: .regularExpression) != nil
    }

    /// The glyphs a page draws as a bullet — the set `opensWithBullet` reads at the start of a
    /// line, written out so that a line holding one of them and nothing else can be recognized
    /// as the marker it is (#261). `aBulletAloneOnItsLineIsTheMarkerItsPageDrew` holds the two
    /// readings to the same glyphs.
    static let bulletGlyphs: Set<Character> = ["•", "*", "−", "–", "—", "-"]

    /// Whether the whole of a line is one bullet glyph: the marker, with none of its item.
    static func isBulletGlyph(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 1 && bulletGlyphs.contains(trimmed[trimmed.startIndex])
    }

    /// How far past a column's gutter the page may hang a bullet from the item it marks and the
    /// two still be one item: two bodies, an indent rather than a column.
    ///
    /// The bound is where the corpus leaves a gap. Over the twenty pinned sources 897 lines hold
    /// a bullet glyph and nothing else. Forty have nothing beside them on their row and 57 have a
    /// piece within the gutter to their left; of the 800 that remain, 204 stand within the gutter
    /// — already one block by the row rule — and 556 within two bodies, the widest at 1.89. The
    /// next widest is 2.09 bodies, and every one of the 40 beyond it is a column of the page or a
    /// cell of a row: the Blue Book sets one 12.2 bodies from its marker and one 50.4, the Warren
    /// Commission 5.2 and 8.1. Nothing the corpus prints falls between.
    static let hangingIndentBound: CGFloat = 2

    /// Whether `line` is a bullet the extractor left with none of its item's text, standing on
    /// the row of the item it marks.
    ///
    /// PDFKit ends a line wherever the page leaves a gap, so a page that hangs its bullets well
    /// clear of their items returns the marker and the item as two lines on one baseline. The FAA
    /// handbook hangs every bullet of its 499 items 18 points from the item's own edge on a ten
    /// point body, so page 29 comes back as
    ///
    /// ```
    /// [ 45.00 193.67   3.50 11.47] | •
    /// [ 63.00 193.67 210.01 11.47] | IFR Charts—Enroute High Altitude Conterminous U.S.,
    /// ```
    ///
    /// and the marker reached the reader as a block of its own — `<p>•</p>`, 54 times — or glued
    /// to the sentence that introduces the list, while the item it marks was read as prose (#261).
    ///
    /// Two pieces of one printed row are one block within the three quarters of a body a column's
    /// gutter needs (#57), which is the right bound for two pieces of *prose*, because a wider gap
    /// there could be two columns. **A bullet is never a column of its own**, so a piece the page
    /// set beyond that gutter on its row is still the item it marks, up to the `hangingIndentBound`
    /// an indent reaches. Beyond that the page has set a column or a row of cells, which belong to
    /// the column and table readers (#210).
    ///
    /// Two things the page must still state, both of them rules this library already keeps:
    ///
    /// - **the page set the item on the marker's row.** A bullet with nothing beside it marks
    ///   something the reader cannot reflow — a key in a legend, an item that is a picture — and
    ///   stays the block it was; nothing beneath it is ever swallowed, because only a piece of the
    ///   marker's own printed row can join it;
    /// - **the marker opens that row.** A piece to its left within the gutter means the extractor
    ///   cut this line out of the middle of a row, so what stands there is whatever the page was
    ///   printing — the minus between two terms of Wallace's derivations, not a marker (#203).
    ///
    /// Within the gutter nothing changes: the two pieces are already one block by the row rule
    /// above, and a glyph a hair from the piece beside it is as often a fraction bar or a mark in
    /// a scan as a marker. Wallace stacks `−` over `3` a quarter of a body apart on page 269, the
    /// rule of a fraction and not a bullet at all; it stays the prose the library already reads.
    static func opensAloneAsBullet(_ line: TextLine, in lines: [TextLine], body: CGFloat,
                                   rightToLeft: Bool = false) -> Bool {
        guard isBulletGlyph(line.text),
              !continuesPrintedRow(line, in: lines, body: body, rightToLeft: rightToLeft),
              let item = pieceBeside(line, in: lines, rightToLeft: rightToLeft) else { return false }
        let indent = rightToLeft ? line.rect.minX - item.rect.maxX : item.rect.minX - line.rect.maxX
        return indent >= body * 0.75 && indent < body * hangingIndentBound
    }

    /// The piece the page set next to `line` on its own printed row: the nearest line to its
    /// right, or to its left where the writing runs that way (#41). Nil where the page set
    /// nothing beside it.
    static func pieceBeside(_ line: TextLine, in lines: [TextLine], rightToLeft: Bool = false) -> TextLine? {
        lines.filter { other in
            other != line && other.sharesRow(with: line)
                && (rightToLeft ? other.rect.maxX <= line.rect.minX : other.rect.minX >= line.rect.maxX)
        }.min { rightToLeft ? $0.rect.maxX > $1.rect.maxX : $0.rect.minX < $1.rect.minX }
    }

    /// A line the page has marked as an item or a note, and so is not a heading of any size
    /// (#254, #259): either it opens with a bullet, or it opens with a glyph the page itself
    /// keys material to. `pageLines` is everything the page printed, not the lines that still
    /// reflow, because the material a note is keyed to may be inside a crop.
    static func opensWithMarker(_ line: TextLine, keyedIn pageLines: [TextLine]) -> Bool {
        opensWithBullet(line.text) || opensWithKeyedMark(line, keyedIn: pageLines)
    }

    /// The glyph a line opens as a mark: one character that is no letter and no digit, a space,
    /// and text after it. `NativeTextReader.sizeAfterListMarker` already reads exactly this shape
    /// when it refuses to let an opening glyph state the line's size, so a page that draws such a
    /// glyph has already been read as drawing a marker; nil where the line opens with prose.
    static func openingMark(_ text: String) -> Character? {
        var characters = text[...]
        guard let mark = characters.popFirst(), !mark.isLetter, !mark.isNumber, !mark.isWhitespace,
              characters.popFirst()?.isWhitespace == true,
              characters.contains(where: { !$0.isWhitespace })
        else { return nil }
        return mark
    }

    /// Whether the page keys its own material to the glyph this line opens with — the evidence
    /// that the line is a note about that material and not a heading that happens to begin with a
    /// symbol (#259).
    ///
    /// IRS Publication 596 sets a legend in the footnote band under ten pages of its EIC table:
    /// `★ 如果您的报税身份是已婚分别申报，…请使用此栏。`, 8 points over a table whose body is
    /// 5.69, so it clears the page's heading threshold on size alone. #254's bullet class is
    /// enumerated and holds no U+2605, and #256 reads the line a marker is *not* on, while this
    /// legend is the first line of its own note. Enumerating one more glyph would say nothing
    /// about why it is a marker, so the page is asked instead.
    ///
    /// Three things the page states, together:
    ///
    /// - **a glyph standing alone before a measure of text.** `openingMark` reads the shape the
    ///   size correction already reads — one non-alphanumeric character, a space, then text;
    /// - **the same glyph printed by itself, higher on the page.** Each of those pages sets `★`
    ///   as a line of its own twice, at 6.5 points, in the two column headers of the table the
    ///   legend explains. A mark a note is keyed to is a mark the page has already made, so a
    ///   heading opening `§` or `★` on a page that keys nothing to it stays a heading;
    /// - **a line that filled its measure**, at least twelve of its own sizes wide, the width
    ///   `hangsUnderBullet` asks of a line that wrapped. A note keyed to a mark runs on; a
    ///   decorated heading is short, and `★ Contents` beneath a bare star keeps its reading.
    ///
    /// The search is over everything the page printed, not over the lines that still reflow: the
    /// EIC table is a preserved region on all ten pages, so the two header stars are inside a
    /// crop, while the legend that explains them is beneath it. What the page keyed its note to
    /// is what the page drew, whether or not the converter kept it as text.
    static func opensWithKeyedMark(_ line: TextLine, keyedIn pageLines: [TextLine]) -> Bool {
        guard let mark = openingMark(line.text) else { return false }
        guard line.rect.width >= max(line.fontSize, 4) * 12 else { return false }
        return pageLines.contains { other in
            other.rect.minY > line.rect.minY && other.text.count == 1 && other.text.first == mark
        }
    }

    /// Whether the page hung this line under a marked line: it is the rest of that item or note,
    /// and neither is a heading whatever size its text is set in (#254, #256, #259). The marker
    /// that says so is on the line above, so the page states the relationship in its indent
    /// instead, and a line that opens a mark of its own is an item, not a continuation. IRS
    /// Publication 596 sets the starred footnotes under its EIC table at 8 points over a table
    /// whose body is 5.69, and the footnote that wraps reaches the page's heading threshold on
    /// size alone.
    ///
    /// The evidence is the hanging indent the marker leaves, and it is the page's own: a line
    /// carrying no marker itself, at the marked line's size, directly beneath it within the
    /// leading `continuesBrokenItem` already reads, standing between 0.8 and 3 of its size in
    /// from that line's left edge — the window `NumberedNoteDetector` reads for the same
    /// relationship in a numbered note. The marked line must also fill a measure, at least twelve
    /// of its own sizes wide, because a line that wrapped is a line that ran out of room: a short
    /// bulleted item above an indented one is two items, not one wrapped over two lines.
    static func hangsUnderBullet(_ line: TextLine, in lines: [TextLine],
                                 keyedIn pageLines: [TextLine] = []) -> Bool {
        guard !isList(line.text), !opensWithKeyedMark(line, keyedIn: pageLines) else { return false }
        let size = max(line.fontSize, 4)
        // The geometry is asked first: it settles all but a handful of the page's lines before
        // the marker test reads the page again for a keyed mark.
        return lines.contains { above in
            guard above.hasSize(line.fontSize), above.wraps != false, above.rect.width >= size * 12
            else { return false }
            let indent = line.rect.minX - above.rect.minX
            guard indent >= size * 0.8, indent <= size * 3 else { return false }
            let gap = above.rect.minY - line.rect.maxY
            guard gap >= -size * 0.6, gap <= size * 0.8 else { return false }
            return opensWithMarker(above, keyedIn: pageLines)
        }
    }

    static func isList(_ text: String) -> Bool {
        text.range(of: "^(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s", options: .regularExpression) != nil
    }

    /// The list markers a wrapped line of prose can also begin with: a number or a single letter
    /// followed by a point or a bracket. A bullet, a minus or a hyphen never opens a sentence's
    /// continuation, so those keep the plain `listItem` reading.
    static func isMarked(_ text: String) -> Bool {
        text.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression) != nil
    }

    /// The value a line's opening marker would carry in a list: the number it prints, or the
    /// place of its letter in the alphabet, with the kind kept apart so that a lettered list and
    /// a numbered one are never read as one sequence (#171). Nil for a bullet and for a line that
    /// opens no marker at all.
    static func markerValue(_ text: String) -> (digits: Bool, value: Int)? {
        guard let range = text.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression)
        else { return nil }
        let token = text[range].dropLast(2)
        if let number = Int(token) { return (true, number) }
        guard let letter = token.first?.lowercased().unicodeScalars.first else { return nil }
        return (false, Int(letter.value))
    }

    /// Where `line` sits among the same-size, proportional lines within one and a half body sizes
    /// of its left edge: whether it is on that column's majority left edge, the right edge at
    /// least three of those lines reach, and whether the page sets a list on its own edge. Two
    /// lines agreeing on a right edge are not a justified margin, and ragged item lengths
    /// establish none at all.
    static func markerColumn(of line: TextLine, in lines: [TextLine], body: CGFloat) -> MarkerColumn {
        let size = Int(line.fontSize.rounded())
        // A marker's column is a column of the writing: where the page set every line of this
        // group at one quarter turn, the edge its markers stand on and the margin its column
        // justifies to run along that writing and not down the page (#276, #263).
        let frame = LayoutReconstructor.ownFrame(of: lines)
        let column = lines.filter {
            !$0.monospaced && Int($0.fontSize.rounded()) == size
                && abs(frame($0).minX - frame(line).minX) < body * 1.5
        }
        let edge = column.filter { abs(frame($0).minX - frame(line).minX) < body * 0.5 }
        // A list marks its items and its markers advance, so a run of lines on one edge with
        // fewer than a quarter of them marked, whose markers do not run on down the page, is no
        // list. Eight is the shortest run that says anything: the 9/11 report's staff pages stand
        // twenty-five names on one edge and open four of them with the initials `T.`, `L.`, `C.`
        // and `R.`, which run in no order at all, while the Fed book sets four numbered duties
        // among twenty lines of prose on one edge and numbers them 1, 2, 3, 4 (#171).
        let marked = edge.count { isList($0.text) }
        let digits = markerValue(line.text)?.digits
        let sequence = edge.sorted { frame($0).minY > frame($1).minY }
            .compactMap(\.text).compactMap(markerValue).filter { $0.digits == digits }.map(\.value)
        let advancing = zip(sequence, sequence.dropFirst()).count { $1 > $0 }
        let setsAList = edge.count < MarkerColumn.shortestUnmarkedRun || marked * 4 > edge.count
            || (sequence.count >= 2 && advancing * 2 > sequence.count - 1)
        guard let right = column.map({ frame($0).maxX }).max() else {
            return MarkerColumn(onMajorityEdge: false, justifiedRight: nil, setsAList: setsAList)
        }
        let justified = column.count { frame($0).maxX >= right - body * 0.25 }
        return MarkerColumn(onMajorityEdge: edge.count * 2 > column.count,
                            justifiedRight: justified >= 3 ? right : nil, setsAList: setsAList)
    }
}

/// Builds one page's logical blocks from its ordered elements: paragraphs from prose lines,
/// preformatted blocks from code and list lines, headings, images, and the tagged and numbered
/// note groups that arrive already grouped. It owns the paragraph in progress and the code
/// block's origin; every `append` decides what the previous block was and flushes it.
///
/// There is one paragraph in progress, whether the structure tree named it or the page's
/// geometry did. A page whose tags apply only in part (#67) hands the assembler tagged and
/// untagged lines of one printed paragraph in turn, so a second, parallel slot for tagged text
/// would break that paragraph at every crossing — and strand `previous` and the open paragraph
/// that `continuesWrapped` reads (#238).
struct BlockAssembler {
    let page: Int
    let body: CGFloat
    /// The leading this page's own text states, or nil where it states none (#123).
    let leading: CGFloat?
    private let additionalLeading: [Int: CGFloat]
    let hyphens: HyphenContext
    private(set) var blocks: [ReflowBlock] = []
    /// Uncertain-hyphen warnings the joins raised, one per page.
    private(set) var warnings: [ConversionWarning] = []
    private var note: (group: Int, text: InlineText)?
    private var paragraph = InlineText()
    /// The structure group the open paragraph belongs to, when the tags named one. A tagged and
    /// an untagged line of the same printed paragraph arrive at one assembler — a page whose
    /// tags partly apply interleaves them (#67) — so the open paragraph is one slot, and the tag
    /// travels with it rather than holding a second, parallel one (#238).
    private var paragraphTag: TextStructure?
    /// A resumed paragraph keeps its original position before the intervening figure (#160).
    private var paragraphTarget: Int?
    private var previous: TextLine?
    /// The printed row `previous` closes, where the extractor split that row into pieces standing
    /// side by side: the line the page set, of which `previous` is only the last piece (#41,
    /// #272). It is nil wherever `previous` is a whole row, and it is cleared beside every
    /// assignment to `previous` that is not one.
    private var previousRow: TextLine?
    /// The line of the heading block last appended, for a heading the page breaks over two lines
    /// with no space at the break (#42).
    private var headingLine: TextLine?
    /// The line of the last preformatted block appended, for an item whose last word the page
    /// broke over the block boundary (#245). A bullet opens that block through `.listItem` and a
    /// number or a letter through `.markedLine` on an edge the page sets a list on; an item is an
    /// item either way, so both branches record it (#266).
    private var itemLine: TextLine?
    private var codeOrigin: CGFloat?
    /// The table row the last block holds, while more pieces of that printed row can still join
    /// it (#137, #210). Anything else the page hands over closes the row.
    private var rowInProgress: TextLine?
    /// The list item the last block holds, while the rest of that item's own printed row can
    /// still join it (#172). PDFKit ends a line at the gap a page leaves after a hanging marker,
    /// so an item can arrive as its marker and then its text.
    private var itemRowInProgress: TextLine?
    /// The left edge of a paragraph a marker-leading line opened because the page set no list at
    /// that edge, while that line is still the whole of it (#171).
    private var initialOpening: CGFloat?

    /// Assets the page's own links cover, by asset path (#247).
    private let imageLinks: [String: LinkTarget]
    /// What an asset holds, by asset path, where the conversion has measured it and the generic
    /// description would say nothing: a table recognition located and did not transcribe (#31).
    private let imageDescriptions: [String: String]
    /// The wrapped second line of each entry the page hangs, by the entry it carries on (#160).
    private let hangingEntries: [CGRect: CGRect]
    /// Numbered short answers whose wrapped values repeatedly share one hanging edge (#212).
    private let numberedAnswerWraps: [CGRect: CGRect]
    /// The lines that open an entry of a list the page hangs under an outdented marker column,
    /// and the edge it sets those entries' text on (`LayoutReconstructor.hangingMarkerList`,
    /// #282). Empty where the page sets no such list.
    private let markerEntries: Set<CGRect>
    private let markerEntryEdge: CGFloat?
    /// Dotted citation numbers and their text edge, established by a repeated bibliography.
    private let numberedBibliography: Bool
    /// Entry starts and hanging continuations established by a repeated author column (#157).
    private let bibliographyOpenings: Set<CGRect>
    private let bibliographyWraps: Set<CGRect>
    /// Value lines following the page's recurring short labels (#215).
    private let labelValueStarts: Set<CGRect>
    /// Where this page left the same seam between two pieces of a row on three or more rows: a
    /// column it set, rather than a space inside a printed line (`LayoutReconstructor.columnSeams`,
    /// #272).
    private let columnSeams: [CGFloat]
    /// The height of an ordinary line of each type size the page sets, by rounded size
    /// (`LayoutReconstructor.ordinaryLineHeights`, #230).
    private let ordinaryHeights: [Int: CGFloat]
    /// Whether the page is written right to left, read from its own lines
    /// (`ArabicText.readsRightToLeft`). A line then begins at its right edge and the next piece
    /// of its printed row stands to its left (#41).
    private let rightToLeft: Bool
    /// Whether the page's text transcribes a scan — recognized, or an inherited invisible text
    /// layer — which a list-marker line records for `ListBuilder` (#292).
    private let recognized: Bool
    /// Whether the document heads this page as a chapter's notes (`NumberedNoteDetector`). Its
    /// numbered lines are the entries of that apparatus, which `ListBuilder` never lists (#292):
    /// a marker line on such a page records no list evidence at all.
    private let notesPage: Bool

    init(page: Int, body: CGFloat, leading: CGFloat? = nil, additionalLeading: [Int: CGFloat] = [:], hyphens: HyphenContext,
         imageLinks: [String: LinkTarget] = [:], imageDescriptions: [String: String] = [:],
         hangingEntries: [CGRect: CGRect] = [:], numberedAnswerWraps: [CGRect: CGRect] = [:],
         columnSeams: [CGFloat] = [],
         ordinaryHeights: [Int: CGFloat] = [:],
         markerEntries: Set<CGRect> = [], markerEntryEdge: CGFloat? = nil,
         numberedBibliography: Bool = false,
         bibliographyOpenings: Set<CGRect> = [], bibliographyWraps: Set<CGRect> = [],
         labelValueStarts: Set<CGRect> = [],
         rightToLeft: Bool = false, recognized: Bool = false, notesPage: Bool = false) {
        self.page = page
        self.body = body
        self.leading = leading
        self.additionalLeading = additionalLeading
        self.hyphens = hyphens
        self.imageLinks = imageLinks
        self.imageDescriptions = imageDescriptions
        self.hangingEntries = hangingEntries
        self.numberedAnswerWraps = numberedAnswerWraps
        self.markerEntries = markerEntries
        self.markerEntryEdge = markerEntryEdge
        self.numberedBibliography = numberedBibliography
        self.bibliographyOpenings = bibliographyOpenings
        self.bibliographyWraps = bibliographyWraps
        self.labelValueStarts = labelValueStarts
        self.columnSeams = columnSeams
        self.ordinaryHeights = ordinaryHeights
        self.rightToLeft = rightToLeft
        self.recognized = recognized
        self.notesPage = notesPage
    }

    /// Where a line's own text begins: its right edge in right-to-left writing, its left edge
    /// otherwise. It is what the column test that joins a paragraph's lines compares, because a
    /// paragraph's lines stand on the edge the writing starts at and end ragged at the other
    /// (#41). USCIS M-618-A page 21 sets ten wrapped lines of one paragraph whose right edges
    /// stand within a point of 543 and whose left edges are spread over 92.
    /// It is read in the frame the line's own writing runs in, so that a line the page lettered
    /// sideways starts where its writing starts rather than at the left of the box around it
    /// (#263).
    private func startEdge(_ line: TextLine) -> CGFloat {
        rightToLeft ? line.uprightRect.maxX : line.uprightRect.minX
    }

    private func headingID() -> String { "heading-\(page)-\(blocks.count)" }

    /// The preformatted block a list-marker line opens, carrying the evidence `ListBuilder`
    /// reads (#292): that a marker opened it, and whether its text transcribes a scan. On a page
    /// the document heads as a chapter's notes it carries none, because the numbered entries
    /// there are the notes apparatus, which is not a list whatever its numbering (#219).
    private func markerOpenedBlock(_ line: TextLine) -> ReflowBlock {
        var block = ReflowBlock(content: .preformatted(line.content), page: page)
        if !notesPage {
            block.listEvidence = .init(recognized: recognized, edge: startEdge(line), fontSize: line.fontSize)
        }
        return block
    }

    private mutating func join(_ left: InlineText, _ right: InlineText) -> InlineText {
        LayoutReconstructor.join(left, right, hyphens: hyphens, page: page, warnings: &warnings)
    }

    private mutating func flushNote() {
        if let note { blocks.append(ReflowBlock(content: .paragraph(note.text), page: page)) }
        note = nil
    }

    /// The heading level the tags gave the open paragraph; zero for an untagged one and for a
    /// tagged paragraph, which is what `TextStructure` already means by zero.
    private var paragraphHeadingLevel: Int { paragraphTag?.headingLevel ?? 0 }

    private mutating func flushParagraph() {
        if !paragraph.elements.isEmpty {
            let level = paragraphHeadingLevel
            let content: ReflowBlock.Content = level == 0 ? .paragraph(paragraph)
                : .heading(id: headingID(), text: paragraph, level: level)
            if let target = paragraphTarget {
                blocks[target].content = content
            } else {
                blocks.append(ReflowBlock(content: content, structureGroup: paragraphTag?.group, page: page))
            }
        }
        paragraphTarget = nil
        paragraph = InlineText()
        paragraphTag = nil
        previous = nil
        previousRow = nil
    }

    /// Retain the paragraph handle while its figure and caption are emitted in their own
    /// blocks. Only a source-geometry continuation plan can ask to resume this handle.
    mutating func suspendProse() -> Int? {
        guard !paragraph.elements.isEmpty, paragraphHeadingLevel == 0 else { return nil }
        let target = paragraphTarget ?? blocks.count
        flushParagraph()
        return target
    }

    mutating func resumeProse(_ target: Int, with line: TextLine) -> Bool {
        flushNote()
        flushParagraph()
        guard blocks.indices.contains(target), case let .paragraph(text) = blocks[target].content else { return false }
        paragraph = join(text, line.content)
        paragraphTarget = target
        paragraphTag = line.structure
        previous = line
        previousRow = nil
        initialOpening = nil
        headingLine = nil
        itemLine = nil
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        return true
    }

    /// Close the ordinary paragraph before recording a separately proved source container.
    mutating func beginClosedUnit() -> Int {
        flushNote(); flushParagraph()
        initialOpening = nil; headingLine = nil; itemLine = nil
        codeOrigin = nil; rowInProgress = nil; itemRowInProgress = nil
        return blocks.count
    }

    mutating func endClosedUnit(start: Int) {
        flushNote(); flushParagraph()
        initialOpening = nil; headingLine = nil; itemLine = nil
        codeOrigin = nil; rowInProgress = nil; itemRowInProgress = nil
        let count = blocks.count - start
        guard count > 0, count <= 4_096 else { return }
        // A painted background can belong to an ordinary body paragraph that continues
        // onto the next page. One prose block alone does not prove an independent unit.
        if count == 1, case .paragraph = blocks[start].content { return }
        for index in start..<blocks.count {
            blocks[index].closedUnit = .init(id: start, position: index - start, count: count)
        }
    }

    /// A line of a numbered note; consecutive lines of one `group` join into one paragraph.
    mutating func appendNote(group: Int, _ line: TextLine) {
        initialOpening = nil
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        if note?.group != group { flushNote() }
        if let current = note {
            note = (group, join(current.text, line.content))
        } else {
            note = (group, line.content)
        }
    }

    /// A displayed opener summary reads as one aside and cannot merge with adjacent prose.
    mutating func appendAside(_ lines: [TextLine]) {
        initialOpening = nil
        flushNote()
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        guard let first = lines.first else { return }
        var text = first.content
        for line in lines.dropFirst() { text = join(text, line.content) }
        blocks.append(ReflowBlock(content: .aside(text), page: page))
        previous = nil
        previousRow = nil
    }

    /// Source display rows carry one semantic block and cannot join nearby body text.
    mutating func appendTextPanel(_ content: [ReflowBlock]) {
        initialOpening = nil
        flushNote(); flushParagraph()
        codeOrigin = nil; rowInProgress = nil; itemRowInProgress = nil
        for var block in content {
            // Panel reconstruction used a fresh assembler. Allocate its headings in this
            // page's sequence so their EPUB anchors cannot collide with surrounding headings.
            if case let .heading(_, text, level) = block.content {
                block.content = .heading(id: headingID(), text: text, level: level)
            }
            blocks.append(block)
        }
        previous = nil; previousRow = nil
    }

    mutating func appendQuotation(_ lines: [TextLine]) {
        initialOpening = nil
        flushNote()
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        guard let first = lines.first else { return }
        var text = first.content
        for line in lines.dropFirst() { text = join(text, line.content) }
        blocks.append(ReflowBlock(content: .quotation(text), page: page))
        previous = nil
        previousRow = nil
    }

    mutating func appendCaption(_ lines: [TextLine]) {
        initialOpening = nil
        flushNote()
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        guard let first = lines.first else { return }
        var text = first.content
        for line in lines.dropFirst() { text = join(text, line.content) }
        blocks.append(ReflowBlock(content: .paragraph(text), page: page))
        previous = nil
        previousRow = nil
    }

    /// A table the page draws, read as cells (#210), closes any open paragraph.
    mutating func appendTable(_ table: PageTable) {
        initialOpening = nil
        flushNote()
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        blocks.append(ReflowBlock(content: .table(.init(
            rows: table.rows.map { $0.map { .init(text: $0.content, columns: $0.columns) } },
            headerRows: table.headerRows)), page: page))
    }

    mutating func appendImage(_ assetID: String) {
        initialOpening = nil
        flushNote()
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        blocks.append(LayoutReconstructor.imageBlock(assetID: assetID, page: page,
                                                     link: imageLinks[assetID],
                                                     describing: imageDescriptions[assetID]))
    }

    /// A line the structure tree tagged; consecutive lines of one group join into one block. A
    /// group the tags name is a paragraph boundary the source states, so it always opens its own
    /// block: an untagged paragraph left open before it is flushed, whatever the geometry says.
    mutating func appendTagged(_ tag: TextStructure, _ line: TextLine) {
        initialOpening = nil
        flushNote()
        codeOrigin = nil
        rowInProgress = nil
        itemRowInProgress = nil
        if paragraphTag?.group != tag.group { flushParagraph() }
        if paragraph.elements.isEmpty {
            paragraph = line.content
            paragraphTag = tag
        } else {
            paragraph = join(paragraph, line.content)
        }
        previous = line
        previousRow = nil
    }

    /// Whether a heading line carries on from the one above it: East Asian writing that sets no
    /// space at the break, at the same size, on the page's own leading (#42). Latin headings are
    /// untouched, because a break between two Latin words is a space and says nothing about
    /// whether the lines are one title or two.
    private func continuesHeading(_ above: TextLine, _ line: TextLine) -> Bool {
        // In the frame the two lines' own writing runs in, where the page set them at one turn:
        // the next line of a sideways title stands beside it on the page (#276, #263).
        let (top, next) = above.turn == line.turn
            ? (above.uprightRect, line.uprightRect) : (above.rect, line.rect)
        guard CJKText.setsNoSpace(between: above.text, and: line.text),
              above.hasSize(line.fontSize), next.maxY < top.maxY else { return false }
        // A display line's PDFKit box carries enough leading that two stacked lines of a title
        // overlap: the cover's two 31-point lines overlap by 12.9 points. The bound is the size
        // itself, which still separates a stack from a heading a measure further down the page.
        let gap = top.minY - next.maxY
        return gap >= -line.fontSize && gap <= line.fontSize * 0.8
    }

    /// Whether a prose line finishes a word the item above it broke: the item ends in a hyphen or
    /// a soft hyphen, the line opens in lowercase, and it sits directly beneath the item on the
    /// page's own leading. The hyphen goes with the join, as `HyphenRepair` removes one it can
    /// decide; here the page's own break is the evidence and the item's own words are the rest of
    /// it (#245).
    private func continuesBrokenItem(_ above: TextLine, _ line: TextLine, text: InlineText) -> Bool {
        let broken = text.text.hasSuffix("-") || text.text.hasSuffix("\u{00ad}")
            || hyphens.lineEndSubstitute.map { text.text.last == $0 } == true
        guard broken,
              line.text.first?.isLowercase == true, above.hasSize(line.fontSize) else { return false }
        // Along the writing, where the page set both lines at one turn (#276, #263).
        let (top, next) = above.turn == line.turn
            ? (above.uprightRect, line.uprightRect) : (above.rect, line.rect)
        let gap = top.minY - next.maxY
        let size = max(line.fontSize, 4)
        return gap >= -size * 0.6 && gap <= size * 0.8
    }

    mutating func append(_ line: TextLine, as role: LineRole) {
        // A numbered bibliography sets its marker in a separate column and every line of the
        // citation on one text edge. Keep that whole entry together even when an author's
        // initial would otherwise read as a fresh lettered item (#219 item 1).
        if numberedBibliography, let edge = markerEntryEdge,
           !markerEntries.contains(line.rect), abs(line.rect.minX - edge) <= body * 0.25,
           let above = itemLine ?? previous, above.hasSize(line.fontSize),
           (above.sharesRow(with: line)
               || (above.rect.minY > line.rect.minY && above.rect.minY - line.rect.minY <= body * 1.5)) {
            if !paragraph.elements.isEmpty {
                paragraph = join(paragraph, line.content)
                previous = line
                previousRow = nil
                return
            }
            if let last = blocks.last, last.page == page, case let .preformatted(text) = last.content {
                blocks[blocks.count - 1].content = .preformatted(join(text, line.content))
                itemLine = line
                itemRowInProgress = line
                return
            }
        }
        let openedByInitial = initialOpening
        initialOpening = nil
        flushNote()
        if case .heading = role {} else { headingLine = nil }
        if case .listItem = role {} else if case .prose = role {} else { itemLine = nil }
        // An untagged line never extends a tagged heading: the tags said where that heading ends,
        // and prose set beneath it at the column's leading is the text it heads, not more of the
        // heading. The roles below that open a block of their own flush the paragraph themselves.
        if paragraphHeadingLevel > 0 { flushParagraph() }
        if !line.monospaced { codeOrigin = nil }
        if case .tableRow = role {} else { rowInProgress = nil }
        // The rest of an item's own printed row is the only thing that can still join it, and it
        // reaches the assembler as prose (#172).
        let openItemRow = itemRowInProgress
        itemRowInProgress = nil
        switch role {
        case .heading:
            flushParagraph()
            // East Asian writing breaks a heading between two characters of one word, so the
            // second line is the rest of the first: IRS Publication 596's cover sets
            // `低收入家庭福利优` and `惠 (EIC)` as two lines of one title. The page's own leading
            // and the absence of a space at the break are the evidence (#42).
            if let above = headingLine, let last = blocks.last, last.page == page,
               case let .heading(id, text, level) = last.content, continuesHeading(above, line) {
                var combined = text
                combined.append(line.content)
                blocks[blocks.count - 1].content = .heading(id: id, text: combined, level: level)
            } else {
                blocks.append(ReflowBlock(content: .heading(id: headingID(), text: line.content), page: page))
            }
            headingLine = line
            return
        case .code:
            flushParagraph()
            if let origin = codeOrigin, let last = blocks.last, case let .preformatted(previousText) = last.content {
                let indent = min(80, max(0, Int(((line.rect.minX - origin) / (line.fontSize * 0.6)).rounded())))
                var combined = previousText
                combined.append(InlineText("\n" + String(repeating: " ", count: indent)))
                combined.append(line.content)
                blocks[blocks.count - 1].content = .preformatted(combined)
            } else {
                codeOrigin = line.rect.minX
                blocks.append(ReflowBlock(content: .preformatted(line.content), page: page))
            }
        case .listItem:
            flushParagraph()
            // Preserve significant breaks and native styles; do not rewrite list markers or code.
            // `ListBuilder` reads the marker line's evidence once the run it belongs to is whole.
            blocks.append(markerOpenedBlock(line))
            itemLine = line
            itemRowInProgress = line
            return
        case .markedLine(let column):
            // A wrapped line whose first word is an initial, a citation or a year belongs to the
            // paragraph above it; anything else opens an item and keeps its own block (#39).
            if let prev = previous, !paragraph.elements.isEmpty,
               continuesWrapped(prev, line, column) || marksEntry(prev, line) {
                paragraph = join(paragraph, line.content)
                previous = line
                previousRow = nil
            } else if column.setsAList {
                flushParagraph()
                blocks.append(markerOpenedBlock(line))
                // The page numbered or lettered this item rather than bulleting it, and it is an
                // item either way: the block it opened is the one the rest of a word broken over
                // its end belongs to. Our Flag's folding instructions are numbered, and the page
                // breaks the first of them at a printed hyphen — `1. …hold the flag waist high
                // and horizon-` above `tally between them.` (#245, #266).
                itemLine = line
                itemRowInProgress = line
            } else {
                // The page set no list on this edge, so the opening token is an initial, a page
                // reference or a citation — `T. Graham Giusti`, `P. E. Fansler, a Florida
                // businessman…`, `R. Singh, M. van Aalst,…` — and the line opens a paragraph
                // rather than an item. It opens one of its own rather than joining the one above,
                // because whether it belongs there is what `continuesWrapped` has just refused;
                // the lines the page wraps under it are prose and join it as any wrap does (#171).
                flushParagraph()
                paragraph = line.content
                previous = line
                previousRow = nil
                initialOpening = line.uprightRect.minX
            }
        case let .tableRow(continuation):
            // One block per printed row. A row the extractor split at its column gap arrives as
            // two lines on one baseline, and the second joins the first rather than opening a row
            // of its own: `H 50–1999` and its note-marked `*50` are one row of the FAA's beacon
            // table, not two. A cell that wrapped joins its row the way any wrapped line joins
            // its paragraph, so the 9/11 report's `10:03:11 Flight 93 crashes in field in` keeps
            // `Shanksville, PA` and the FAA's conterminous-states row keeps its altitudes.
            // A row's pieces stand the other way round where the writing runs right to left (#41).
            // The rest of a printed row stands along the writing, which on a page set at one
            // quarter turn is not along the page (#276, #263).
            let piece = rowInProgress.map { row in
                let (open, next) = row.turn == line.turn
                    ? (row.uprightRect, line.uprightRect) : (row.rect, line.rect)
                return row.sharesRow(with: line)
                    && (rightToLeft ? next.maxX <= open.minX : next.minX >= open.maxX)
            } ?? false
            if rowInProgress != nil, piece || continuation,
               let last = blocks.last, case let .preformatted(text) = last.content {
                blocks[blocks.count - 1].content = .preformatted(piece ? {
                    var combined = text
                    // The left-hand piece of a right-to-left row carries the stop that ends the
                    // sentence before it, and the space the page set after that stop (#41).
                    if !ArabicText.setsNoSpace(between: text.text, and: line.content.text) {
                        combined.append(InlineText(" "))
                    }
                    combined.append(line.content)
                    return combined
                }() : join(text, line.content))
            } else {
                flushParagraph()
                blocks.append(ReflowBlock(content: .preformatted(line.content), page: page))
            }
            rowInProgress = line
        case .prose:
            // Two pieces of one printed row are one block, whichever kind of block the first
            // piece opened: the rest of an item's row is that item's own text, not a paragraph
            // standing beside it. PDFKit ends a line at the gap a page leaves after a hanging
            // marker, so Wallace's page 101 hands over `17)` and then `(− 16,− 14), (11,− 14)`,
            // which the page set four points to its right (#172, the `continuesRow` bound of
            // #57).
            if let above = openItemRow, let last = blocks.last, last.page == page,
               case let .preformatted(text) = last.content, paragraph.elements.isEmpty,
               continuesRow(above, line) || marksItem(above, line, text: text) {
                var combined = text
                combined.append(InlineText(" "))
                combined.append(line.content)
                blocks[blocks.count - 1].content = .preformatted(combined)
                itemRowInProgress = line
                return
            }
            // An item the page broke mid-word keeps the rest of its word. The 9/11 report sets
            // its recommendations as items and breaks one over the block boundary, so
            // `• …supervise the planning and direc-` was followed by `tion of the operation;` as
            // a paragraph of its own, with the word split between them (#245).
            //
            // What becomes of the hyphen is `HyphenRepair`'s to say, on the same evidence it
            // reads inside a paragraph: the book's own words, and the English lexicon where the
            // document is English. The page's break says the line belongs to the item; it does
            // not say the character was a break rather than a printed compound, and the 9/11
            // report's endnotes put both on one edge — `Febru-` carries on `ary` and loses its
            // hyphen, `explosives-` carries on `laden` and keeps it (#245, #266).
            if let above = itemLine, let last = blocks.last, last.page == page,
               case let .preformatted(text) = last.content, paragraph.elements.isEmpty,
               continuesBrokenItem(above, line, text: text) {
                blocks[blocks.count - 1].content = .preformatted(join(text, line.content))
                itemLine = line
                return
            }
            // A numbered answer can set its second value on an indented line. Repeated pairs
            // prove the hanging edge (Wallace page 456).
            if let above = itemLine, let last = blocks.last, last.page == page,
               case let .preformatted(text) = last.content, paragraph.elements.isEmpty,
               continuesNumberedAnswer(above, line) {
                blocks[blocks.count - 1].content = .preformatted(join(text, line.content))
                itemLine = line
                return
            }
            // Such a paragraph takes only the wraps the page sets on its opening line's own
            // edge: a line the page steps in from it opens the next paragraph, which a first-line
            // indent of one body is. Loper Bright's page 64 opens `U. S. 134 (1944), the Court
            // returned to its time-worn path.` on the measure and then indents `Echoing themes`,
            // two paragraphs the ordinary column test, which allows one and a half bodies, would
            // run together (#171).
            let stepped = openedByInitial.map { abs($0 - line.uprightRect.minX) >= body * 0.5 } ?? false
            // A row the extractor cut into three pieces is still one row: the piece arriving now
            // is measured against what has been read of it so far, not against the last piece
            // alone (#41).
            let joinsRow = (previousRow ?? previous).map { continuesRow($0, line) } ?? false
            if stepped || labelValueStarts.contains(line.rect)
                || previous.map({ !continuesParagraph($0, line) }) == true { flushParagraph() }
            if paragraph.elements.isEmpty { paragraph = line.content }
            else { paragraph = join(paragraph, line.content) }
            // A printed row the extractor split is one line as far as the next line is concerned:
            // the paragraph's own edge is the row's, not the edge of whichever piece closed it.
            // USCIS M-618-A page 21 ends four rows with a left-hand piece 200 points short of the
            // measure, and the line beneath each of them opened a paragraph of its own (#41, #57).
            //
            // A left-to-right row reads the same way, and #41 held the rule to right-to-left
            // writing only because it had measured nothing on this side. The 9/11 report's page
            // 259 prints `ning for what later became the 9/11 attack. At the time of their travel
            // through` as one row and hands it back in two pieces at x 44.70…151.77 and
            // x 156.89…356.71; the column test measured 156.89 against the 44.70 of `Iran, the
            // al Qaeda operatives themselves were probably not aware…` and broke the paragraph
            // the page prints in the middle of its own sentence (#272).
            if joinsRow, let prev = previousRow ?? previous, readsAsOneLine(prev, line) {
                previousRow = printedRow(prev, line)
            } else {
                previousRow = nil
            }
            previous = line
        }
    }

    private func continuesNumberedAnswer(_ above: TextLine, _ line: TextLine) -> Bool {
        guard above.text.range(of: #"^[0-9]{1,3}\)"#, options: .regularExpression) != nil,
              !LayoutReconstructor.isList(line.text), above.hasSize(line.fontSize),
              line.rect.midY < above.rect.midY else { return false }
        let indent = line.rect.minX - above.rect.minX
        guard indent >= body * 0.75 && indent <= body * 4,
              line.rect.minX < above.rect.maxX + body * 0.5 else { return false }
        let gap = gapBeneath(above, line.rect)
        guard gap >= -body * 0.6 && gap <= body * 0.9 else { return false }
        return numberedAnswerWraps[line.rect] == above.rect
    }

    /// Whether the two pieces the extractor split one printed row into stand for that line when
    /// the next line's own edge is measured against it.
    ///
    /// PDFKit ends a line wherever the page leaves a gap, and a gap of at least a quarter of a
    /// body is a space the page set between two words: the pieces on either side of it are
    /// consecutive words of one printed line. The 9/11 report's page 259 leaves 5.11 points on a
    /// ten-point body between `ning for what later became` and `the 9/11 attack. At the time of
    /// their travel through`, and the replay-clocks paper leaves 3.60 on nine.
    ///
    /// A narrower gap is no space at all. It is the seam between two runs the page set beside
    /// each other on one row, and what the page began that row with says nothing about the line
    /// beneath it: USGS MCS 2025 page 2 closes a line of prose with a 6.5-point superscript note
    /// marker six hundredths of a point past it, the FAA handbook sets `ATC Instructions—` and
    /// `“Hold Short”` touching at x 374.17, and *Beginning and Intermediate Algebra* cuts each of
    /// its equations at the two points between `72x2` and `− 2 GCF is 2`. Each of those rows is
    /// still one row, and its pieces still join into one block; only its start is withheld.
    ///
    /// Writing the reading reorders is the one place a seam is a line's own. PDFKit splits those
    /// rows at the boundary between two bidirectional runs rather than at a gap, which leaves the
    /// pieces touching: USCIS M-618-A page 21 hands back `…الولايات المتحدة` and
    /// `. ويطلق بعض الأشخاص` with x 343.03 as the end of one and the start of the other (#41, #272).
    ///
    /// A space the page repeats in the same place on row after row is a column it set rather than
    /// a space inside a line, whichever way the writing runs, and `LayoutReconstructor.columnSeams`
    /// reads where a page did that.
    ///
    /// And the piece that closes the row must read as writing. A page whose own sizes say nothing
    /// states its columns neither by a recurring seam nor by a gutter: Project Blue Book's
    /// statistical appendix is handwriting-quality OCR that reads every printed row differently,
    /// so its eight-column rows break in a different place on every one of them and each break is
    /// a space's width. Five of those rows took the row beneath them, because the row's own start
    /// is the first cell's and the next row begins on that same column (#285).
    ///
    /// What separates those rows from the lines this rule exists for is not where they stand but
    /// what they say. The reading takes a split row's text and its wrap from the piece that closed
    /// it, so that piece is what has to read as a line of writing for the row to stand for one:
    /// `the 9/11 attack. At the time of their travel through`, `occurred far later than`,
    /// `Than One Hundred Miles per Hour .` — against `~ 2(./ /.l,O .2/.I` and `✓.:-`, which are
    /// cells of figures. Nothing under three marks is asked: the Blue Book's own speed legend
    /// closes `Meteor-Ii ke` with the rule `-` the page draws for "not stated", and one character
    /// says nothing either way.
    private func readsAsOneLine(_ prev: TextLine, _ line: TextLine) -> Bool {
        let seam = rightToLeft ? line.uprightRect.maxX : line.uprightRect.minX
        guard !columnSeams.contains(where: { abs($0 - seam) <= body * 0.25 }) else { return false }
        guard !rightToLeft else { return true }
        guard line.uprightRect.minX - prev.uprightRect.maxX >= body * 0.25 else { return false }
        return BlockAssembler.readsAsWriting(line.text)
    }

    /// Whether a piece of a printed row reads as writing rather than as a cell of figures: half
    /// its marks are letters, in any script, or it holds fewer than three marks and says nothing.
    ///
    /// Half is well clear of both populations this has to separate. Every piece that closes a row
    /// the rule exists for is prose carrying at most a date or a figure — the 9/11 report's
    /// `the 9/11 attack. At the time of their travel through` is 89% letters, the replay-clocks
    /// paper's `occurred far later than` and the census's `Lambert, D.: … Journal of Official
    /// Statistics,` are higher — and every cell the Blue Book's appendix closes a row with is
    /// under a third: `~ 2(./ /.l,O .2/.I` is three letters in fourteen marks and
    /// `26 JJ' S'I- ff.I /9.!i 5i.t. If j'_,` twelve in twenty-eight (#285).
    ///
    /// Any script, not Latin: this asks whether the page wrote something there, and the Chinese
    /// and Arabic books in the corpus write it in their own.
    static func readsAsWriting(_ text: String) -> Bool {
        let marks = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard marks.count >= 3 else { return true }
        return marks.count { $0.properties.isAlphabetic } * 2 >= marks.count
    }

    /// The one printed row the extractor split into `prev` and `line`, as the line the page set.
    ///
    /// The row covers both rectangles, so a row split near its end no longer reads as a line that
    /// stopped short of the measure. It ends where the piece that closed it ends, so its text and
    /// its wrap are that piece's: that is what the writing actually did. And it is set in the
    /// size the page set most of it in, which is the wider piece's — USGS MCS 2025 page 2 closes
    /// `…an estimated 3.5 billion tons of copper.` with a 6.5-point superscript `8` a twentieth
    /// of a point past the prose, and a row that took its measure from that marker would not be
    /// compared with the 10.1-point line beneath it at all, because `onStatedLeading` only
    /// compares lines of one size, so the 22.36 points of baseline the page opens between
    /// `World Resources:` and `Substitutes:` would say nothing (#272).
    private func printedRow(_ prev: TextLine, _ line: TextLine) -> TextLine {
        var row = line
        row.rect = prev.rect.union(line.rect)
        if prev.rect.width > line.rect.width { row.fontSize = prev.fontSize }
        return row
    }

    /// Whether `line` is the entry the page set beside the marker `prev`, on the marker's own
    /// printed row (#282).
    private func marksEntry(_ prev: TextLine, _ line: TextLine) -> Bool {
        guard let edge = markerEntryEdge, markerEntries.contains(prev.rect),
              !markerEntries.contains(line.rect), prev.sharesRow(with: line) else { return false }
        return abs(line.uprightRect.minX - edge) <= body * 0.25
    }

    /// Whether `line` is a line the page hung under an entry of its marker column: it stands on
    /// that column's text edge, it opens no entry of its own, and what it carries on is either
    /// the entry's opening line or another line already hung on that edge (#282).
    ///
    /// The ordinary column test does not reach these. A justified reference list wraps to the
    /// same right margin its entry line reaches, so #160's hung-entry rule refuses them too; what
    /// vouches for them here is the marker column, which says where every entry begins and so
    /// says that these lines begin none.
    private func hangsUnderMarkerEntry(_ prev: TextLine, _ line: TextLine) -> Bool {
        guard let edge = markerEntryEdge, !markerEntries.contains(line.rect),
              abs(line.uprightRect.minX - edge) <= body * 0.25 else { return false }
        return markerEntries.contains(prev.rect) || abs(prev.uprightRect.minX - edge) <= body * 0.25
    }

    /// Whether `line` continues the paragraph `previous` is part of: the previous line wraps, the
    /// two are stacked at ordinary leading, are two pieces of one printed row, or are an entry and
    /// the wrap the page hangs under it, and the previous line is not a short line the page has
    /// already closed.
    ///
    /// Every measure below is taken in the frame the two lines' own writing runs in (#263): for
    /// upright lines that is the page, to the bit, and for a caption the page lettered sideways
    /// it is the page turned, where the line beneath is the next line of the caption rather than
    /// the one beside it.
    private func continuesParagraph(_ prev: TextLine, _ line: TextLine) -> Bool {
        guard prev.wraps != false else { return false }
        if bibliographyOpenings.contains(line.rect) { return false }
        if bibliographyWraps.contains(line.rect), prev.hasSize(line.fontSize),
           prev.rect.minY > line.rect.minY,
           prev.rect.minY - line.rect.minY <= body * 1.5 { return true }
        // A scanned book can place a footnote call at the end of one paragraph and indent
        // the next paragraph's opening line by one body. Warren 100 and 122 have inherited
        // OCR that reads those raised calls as `^^` or `^^^`; the preceding line often fills
        // the measure, so the usual short-line test cannot see the break (#209). A genuine
        // hanging wrap does not follow a note call and is left to the ordinary column test.
        if recognized, let last = prev.text.last, last == "^",
           line.text.first?.isUppercase == true,
           abs(prev.uprightRect.midY - line.uprightRect.midY) > body * 0.5 {
            let indent = startEdge(line) - startEdge(prev)
            if indent >= body * 0.75 && indent <= body * 1.75 { return false }
        }
        // A line the page outdented a marker onto opens an entry of its own, whatever stands
        // above it: that is what the page set the marker column to say (#282).
        guard !markerEntries.contains(line.rect) else { return false }
        // And the entry beside such a marker is that marker's own text. The page hangs it
        // further from the marker than the gutter two pieces of one row are joined within — 12
        // points in the Replay Clocks paper, 21 in the Census paper — for the same reason a
        // bullet hangs clear of its item (#261): a marker is never a column of its own.
        if marksEntry(prev, line) { return true }
        // What the line above measures — how far it ran, where it started, how far down the page
        // it reached, what size it is set in — is the printed row's, which is `prev`'s own unless
        // the extractor split that row and `prev` is the piece that closed it (#41, #272).
        let row = previousRow ?? prev
        let (prevRect, lineRect) = (row.uprightRect, line.uprightRect)
        // A short line ending a sentence closes its paragraph however the two lines stand. Where
        // the writing stopped, and the text it stopped on, stay the closing piece's.
        // On a page that hangs a marker column, two pieces of one printed row are one line, and
        // the row is read before anything is decided from how far the piece before it ran. The
        // Replay Clocks paper breaks a reference after `…with physical clocks.` and sets `In
        // Proceedings of the 23rd International Conference on` 5.4 points further along that same
        // row: a sentence that ends where the extractor cut the row has not ended the page's
        // line, let alone the entry the page's own markers say it is inside (#57, #272, #282).
        //
        // Only on such a page. Asked of every page, the same reading moves seven of the
        // twenty-two cached books and takes characters out of two of them, because a short line
        // ending a sentence beside a piece of its own row is an ordinary shape the paragraph rule
        // has been measured around; what makes it safe here is that the page has said where its
        // entries begin and end.
        if markerEntryEdge != nil, continuesRow(row, line) { return true }
        let short = prevRect.width < lineRect.width * 0.65
        guard !(short && prev.text.last.map { ".!?".contains($0) } == true) else { return false }
        if continuesRow(row, line) { return true }
        let verticalGap = gapBeneath(row, lineRect)
        // A list the page hangs sets its wraps further in than one column's lines ever stand
        // apart; `LayoutReconstructor.hangingEntries` reads which ones the page hung (#160). It
        // keys on the line the page hung the wrap under, which is the piece and not the row.
        let hangs = hangingEntries[line.rect] == prev.rect || hangsUnderMarkerEntry(prev, line)
        // A split row has two starts — the row's and the piece's — and which of them the
        // paragraph stands on is what the split took away. So either will do, and the reading
        // gains a paragraph's lines rather than losing them. The census's 2002-01 page 17 hands
        // back `[ 12]` at x 134.81 and `Lambert, D.: …` at x 157.25 as one row and hangs
        // `9, (1993) 313–331.` under the entry at x 156.17, two and a half bodies in from the
        // row's own start: the row is the line the page printed, and the edge its wrap stands on
        // is the marker's item, not the marker (#272).
        //
        // The row's own start stands for the paragraph only where the line beneath does not
        // begin further out than it. A wrap stands on its paragraph's edge or in from it; a line
        // the page sets further out began something the row above it did not. Wallace's page 232
        // hands back `72x2` and `− 2 GCF is 2` as one row from x 176.28 and sets the next step of
        // the same worked example, `2(36x2`, at x 161.28 — fifteen points, a body and a quarter,
        // further out (#272).
        let outdent = rightToLeft ? startEdge(line) - startEdge(row) : startEdge(row) - startEdge(line)
        let starts = previousRow == nil || outdent > body * 0.5
            ? [startEdge(prev)] : [startEdge(row), startEdge(prev)]
        // A right-aligned label may wrap further in than prose's left-edge tolerance (#172).
        // Its conjunction states a continuation; alignment alone also describes separate steps
        // of a worked equation and must not join those. Require words, no numbers or operators.
        let rightLabel = line.text.hasPrefix("& ") && row.hasSize(line.fontSize)
            && abs(prevRect.maxX - lineRect.maxX) <= body * 0.25
            && [row.text, line.text].allSatisfy { text in
                text.contains(where: \.isLetter) && text.allSatisfy {
                    $0.isLetter || $0.isWhitespace || ",&'-".contains($0)
                }
            }
        guard verticalGap >= -body * 0.4, verticalGap < body * 0.9, onStatedLeading(row, line),
              starts.contains(where: { abs($0 - startEdge(line)) < body * 1.5 }) || centered(row, line) || hangs || rightLabel
        else { return false }
        // Prose fills its measure, so a line that used under half of the one beneath it ended
        // something, and a line the page then sets further in begins the next thing. #39 already
        // reads a marker set in past the line above it as the opening of an item rather than a
        // wrap; this is the same step under a stub of prose, and it never contradicts #39, whose
        // own test refuses exactly the lines this one closes.
        //
        // The Blue Book's observer questionnaire is the case it answers (#130). Page 273 sets the
        // spaced answer row `Yes or No` under question 7 and the instruction `IF you answered
        // YES, then complete the following questions:` a body further in beneath it. The row ends
        // no sentence, so its punctuation says nothing about it; the step the page takes does.
        //
        // Half is where the same book's contents stand: page 5 hangs each entry's wrapped line
        // six points in under an opening that fills three fifths of it, and an entry that runs
        // over is one paragraph. Two thirds — what the sentence-ending rule above asks — would
        // break those; a stub under half the measure is not a line that ran out of room.
        return !(prevRect.width < lineRect.width * 0.5 && lineRect.minX - prevRect.minX >= body * 0.5)
    }

    /// Whether the two lines are stacked on one center: a balloon, a box or a caption the page
    /// set centered, whose lines share no left edge to be read as a column (#130). The CDC graphic
    /// novel letters every speech balloon this way, so page 34's `I'VE BEEN` / `THINKING... WE` /
    /// `SHOULD REALLY` / `MAKE AN` / `EMERGENCY KIT` stand on five left edges spread over 18
    /// points and on one center, within 1.7 points of each other on a ten-point page.
    ///
    /// A shared left edge is a column the page itself sets, and stands as evidence on its own. A
    /// shared center does not: a title, its author and its date are centered on one axis and are
    /// three separate lines. Vision's wrap evidence admits ordinary centered stacks. Native text
    /// has no such flag, but a large display sentence can state its continuation with two long,
    /// same-size lines at one center and an unfinished first line. Earthdata slide 10 sets its
    /// 28-point statement that way, 50 points from one line top to the next (#175). The size and
    /// length bounds keep ordinary titles, bylines and centered captions out of this reading.
    private func centered(_ prev: TextLine, _ line: TextLine) -> Bool {
        guard abs(prev.uprightRect.midX - line.uprightRect.midX) <= body * 0.6 else { return false }
        if prev.wraps == true { return true }
        guard prev.wraps == nil, line.wraps == nil, body >= 24,
              prev.fontSize >= 24, prev.hasSize(line.fontSize),
              prev.uprightRect.width >= body * 10, line.uprightRect.width >= body * 7,
              let last = prev.text.last, !".!?".contains(last) else { return false }
        return true
    }

    /// The white the page left under a line, measured from the line's own depth rather than from
    /// the rectangle PDFKit reported for it.
    ///
    /// PDFKit gives a line the height of the tallest glyph on it, so a line of running prose
    /// carrying one inline radical reaches into the line beneath it and the two rectangles
    /// overlap although the page printed them one leading apart. Wallace's page 290 sets
    /// `72 = 36 · 2, but often the time it takes to discover the larger perfect square is more`
    /// 20.46 points high where every other line of its paragraph is 11.98, so it overlaps
    /// `than it would take to simplify in several steps.` by 5.82 points and the paragraph broke
    /// in the middle of its own sentence (#230, the same measurement #213 records from the
    /// cropping side).
    ///
    /// Only where the two rectangles overlap, and only as far as the page's own ordinary line at
    /// that size reaches: the adjustment can bring a negative gap back towards nothing and can
    /// never open one, so no pair of lines the page already reads as one paragraph is separated
    /// by it. Where the page states no ordinary height for the size, or the rectangle is not
    /// taller than one, the rectangle is the line.
    private func gapBeneath(_ prev: TextLine, _ line: CGRect) -> CGFloat {
        let rect = prev.uprightRect
        let gap = rect.minY - line.maxY
        guard gap < 0, let ordinary = ordinaryHeights[Int(prev.fontSize.rounded())],
              rect.height > ordinary + body * 0.25 else { return gap }
        return max(gap, rect.maxY - ordinary - line.maxY)
    }

    /// Whether the page set `line` on the leading its own text states, rather than a further part
    /// of a line down: a line the page pushed down is a line the page set apart (#123).
    ///
    /// Wallace page 64 hangs `writing the second part plus the first` under a bulleted item and
    /// then sets its example, `Three more than a number becomes x + 3`, 21.72 points below it,
    /// where the page's own leading — every wrapped line of prose on it — is 14.40. Measured as
    /// white between the rectangles that is 9.74 points, under the 10.76 this rule already
    /// allowed, so the example was appended to the item's own sentence and the page's separation
    /// of the two was lost. The item below it loses its example the same way, and so do the
    /// paragraph breaks this book sets with a further half-line on 22 of its other pages.
    ///
    /// Two fifths of a line is the slack. A page whose leading varies by a point between
    /// paragraphs still reads as one measure; a page that opens half a line of white has said
    /// something, and here it said 1.51 times its own leading. A page that states no leading
    /// (`statedLeading`) is judged by the gap alone, as before, and so is a pair of lines set at
    /// different sizes, whose tops are not one ascent above their baselines and so cannot be
    /// compared this way.
    private func onStatedLeading(_ prev: TextLine, _ line: TextLine) -> Bool {
        let ownLeading = additionalLeading[Int(prev.fontSize.rounded())] ?? leading
        guard let leading = ownLeading, prev.hasSize(line.fontSize) else { return true }
        return prev.uprightRect.maxY - line.uprightRect.maxY <= leading * BlockAssembler.paragraphLeadingSlack
    }

    /// How far past the page's own leading two lines may stand and still be one paragraph.
    static let paragraphLeadingSlack: CGFloat = 1.4

    /// Whether a line opening with a number or a single letter and a point is a wrapped
    /// continuation of the open paragraph rather than the opening of a list item (#39, #238).
    /// It must first continue the paragraph the way any prose line would, and then:
    ///
    /// - not be indented past the previous line's text start, because a marker set in from the
    ///   text above it hangs a new item, while a marker to the left of it is the ordinary
    ///   outdent of a wrap under an indented opening line;
    /// - stand on the majority left edge of its column, in a column justified to a right edge
    ///   at least three of its lines reach, which the previous line also reaches: a line that
    ///   stops short of the margin ended its own thought, and a list's ragged items fill nothing;
    /// - follow a line that does not end a sentence, ignoring closing quotes and brackets;
    /// - follow a line that reads as prose rather than symbols, which an exercise or a formula
    ///   above a numbered answer does not.
    private func continuesWrapped(_ prev: TextLine, _ line: TextLine, _ column: MarkerColumn) -> Bool {
        guard continuesParagraph(prev, line), prev.uprightRect.minX - line.uprightRect.minX > -body * 0.5,
              column.onMajorityEdge, let right = column.justifiedRight,
              // The column's own right edge is read off the page, so the line is measured against
              // it on the page, while the two lines are compared in their own frame above (#263).
              prev.rect.maxX >= right - body * 0.25 else { return false }
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        guard let ending = prev.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
              !".!?:;".contains(ending) else { return false }
        return prev.text.split(whereSeparator: { !$0.isLetter }).count { $0.count >= 2 } >= 3
    }

    /// Whether `line` is the rest of the printed line `prev` begins. PDFKit splits a row at a
    /// wide gap, and on the 9/11 report's page 254 it splits the page's last line a word from
    /// its end, leaving `told` a line, a paragraph and — as the page's last block — the anchor a
    /// cross-page join would have to read (#57). Two pieces of one row are one paragraph.
    ///
    /// The pieces must stand side by side, `line` to the right of `prev`, closer than the gutter
    /// a column needs (`LayoutReconstructor.ordered`'s three quarters of a body). A table's cells,
    /// and a running header and the folio at the other end of its row, stand further apart than
    /// that and stay separate blocks, as does anything on another row.
    ///
    /// The row is the one the page printed, so it is read in the frame the two lines' own writing
    /// runs in: two lines of a caption the page lettered down the side of a panel overlap across
    /// the page without standing on one row of it, and are two lines rather than two pieces of
    /// one (#263).
    private func continuesRow(_ prev: TextLine, _ line: TextLine) -> Bool {
        let (prevRect, lineRect) = (prev.uprightRect, line.uprightRect)
        guard TextLine.sameRow(prevRect, lineRect) else { return false }
        // The rest of a printed row stands to the left of the piece that opened it where the
        // writing runs right to left: USCIS M-618-A page 21 hands back `…الولايات المتحدة` at
        // x 343…543 and `. ويطلق بعض الأشخاص…` at x 184…342 on one baseline (#41).
        let gap = rightToLeft ? prevRect.minX - lineRect.maxX : lineRect.minX - prevRect.maxX
        return gap >= 0 && gap < body * 0.75
    }

    /// Whether `line` is the item a bullet standing alone marks: the open item is that bullet and
    /// nothing else, the two are one printed row, and the page hung the item within the indent a
    /// bullet reaches (#261).
    ///
    /// The bound is the marker's, not the row's. A marker is never a column of its own, so the
    /// piece the page set beside it is its item however wide the indent; the block it opens is an
    /// item like any other, and whatever the page set further along that row stands a column away
    /// from it and is judged by `continuesRow` as before. The FAA handbook's page 29 sets two
    /// columns of items, and the second column's text stands 1.2 bodies past the first column's
    /// items: it is a column, and it stays one.
    private func marksItem(_ above: TextLine, _ line: TextLine, text: InlineText) -> Bool {
        let bullet = LayoutReconstructor.isBulletGlyph(text.text)
        guard bullet || LayoutReconstructor.markerKind(of: text.text, whole: true) != nil else { return false }
        let (aboveRect, lineRect) = (above.uprightRect, line.uprightRect)
        guard TextLine.sameRow(aboveRect, lineRect) else { return false }
        let indent = rightToLeft ? aboveRect.minX - lineRect.maxX : lineRect.minX - aboveRect.maxX
        return indent >= 0 && indent < body * (bullet ? LayoutReconstructor.hangingIndentBound : 1)
    }

    mutating func finish() -> [ReflowBlock] {
        flushNote()
        flushParagraph()
        carryBrokenItems()
        carrySourceSoftHyphenParagraphs()
        carryStrandedStops()
        return blocks
    }

    /// A drop cap can make PDFKit's first selection cover two printed rows. The next row then
    /// becomes a separate paragraph even though the font's ToUnicode map explicitly ended the
    /// first one in a discretionary break. Carry only adjacent prose on the same page.
    private mutating func carrySourceSoftHyphenParagraphs() {
        var index = 0
        while index + 1 < blocks.count {
            guard case let .paragraph(left) = blocks[index].content,
                  left.text.hasSuffix("\u{00AD}"),
                  case let .paragraph(right) = blocks[index + 1].content,
                  right.text.first?.isLowercase == true,
                  blocks[index].page == blocks[index + 1].page,
                  blocks[index].closedUnit == nil, blocks[index + 1].closedUnit == nil,
                  blocks[index].structureGroup == nil, blocks[index + 1].structureGroup == nil
            else { index += 1; continue }
            blocks[index].content = .paragraph(join(left, right))
            blocks.remove(at: index + 1)
        }
    }

    /// A sentence's own full stop is not a block.
    ///
    /// The USCIS Arabic guide sets its writing right to left, so the mark that ends a sentence
    /// sits at the far left of the last line and PDFKit hands it back as a line of its own,
    /// standing clear of the rest. #41 puts such a stop back against its sentence where the
    /// extractor split one printed row, with the page's own space; a stop that is a whole line is
    /// no piece of a row, so nothing reached it and it became a block — four of them in that
    /// book, and one of those a heading, where the same page sets the same kind of heading with
    /// its stop attached (#291).
    ///
    /// One mark and one only: `.`, `?` or `!`, or the full stop Arabic and Urdu draw. An ellipsis
    /// is an elision the book prints — the 9/11 report sets three inside quotations — a rule of
    /// dashes is a footnote's rule, `* * *` is a section break, and `=`, `·` and `−` are the
    /// operators of a worked example. Each of those is a block the page meant, and none is one
    /// mark.
    ///
    /// It joins the block directly above it, and only where that block is text the sentence could
    /// have come from and does not already end in a stop of its own. A picture between them is
    /// reason to leave it: the guide's page 86 sets its stop between two preserved regions, and
    /// which sentence it closes is not something this rule can see.
    private mutating func carryStrandedStops() {
        let stops: Set<Character> = [".", "?", "!", "\u{06D4}"]
        var index = blocks.count - 1
        while index > 0 {
            defer { index -= 1 }
            let text = blocks[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count == 1, let stop = text.first, stops.contains(stop) else { continue }
            guard blocks[index].page == blocks[index - 1].page else { continue }
            let above = blocks[index - 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let last = above.last, !stops.contains(last), above.contains(where: \.isLetter)
            else { continue }
            // The stop keeps the run style the page drew it in, as the rest of its sentence does.
            let mark: InlineText
            switch blocks[index].content {
            case let .paragraph(text): mark = text
            case let .heading(_, text, _): mark = text
            default: continue
            }
            switch blocks[index - 1].content {
            case let .paragraph(carried):
                var joined = carried
                joined.append(mark)
                blocks[index - 1].content = .paragraph(joined)
            case let .heading(id, carried, level):
                var joined = carried
                joined.append(mark)
                blocks[index - 1].content = .heading(id: id, text: joined, level: level)
            default:
                continue
            }
            blocks.remove(at: index)
        }
    }

    /// An item the page broke mid-word keeps the rest of its word, wherever the break falls.
    ///
    /// #266 gives it the line beneath, and takes one printed line, and only where that line opens
    /// in lowercase. Three shapes are left over, and #280 names them: the 9/11 report's note 81
    /// breaks a case-file number, `…serial 1928; 265A-NY-` over `280350-302, serial 16379;`, so
    /// the line opens on a digit; *The Fed Explained* breaks `…operating the Fed-` over `Wire and
    /// automated clearinghouse (ACH) systems,`, so it opens on a capital; and where the rest of
    /// the word is a wrapped paragraph of more than one printed line, taking one line leaves the
    /// others standing alone.
    ///
    /// So the repair is made over the page's blocks rather than its lines, after everything else
    /// has decided what they are. A block that ends where the page broke a word takes the whole of
    /// the block beneath it when that block opens the rest of that word — the whole of it, so
    /// nothing is orphaned — and keeps its own kind, because an item that was holding half a word
    /// is still an item. What becomes of the hyphen is `HyphenRepair`'s to say, on the book's own
    /// words, exactly as inside a paragraph (#245, #266, #288).
    private mutating func carryBrokenItems() {
        var index = 0
        while index + 1 < blocks.count {
            guard case let .preformatted(text) = blocks[index].content, endsBroken(text.text),
                  case let .paragraph(next) = blocks[index + 1].content,
                  blocks[index].page == blocks[index + 1].page,
                  opensRestOfWord(text.text, next.text) else { index += 1; continue }
            blocks[index].content = .preformatted(join(text, next))
            blocks.remove(at: index + 1)
        }
    }

    /// Whether a block ends where the page broke a word: a hyphen, a soft hyphen, or the character
    /// this book's text font draws a line-end hyphen as (#233), standing after a letter or a digit.
    ///
    /// A word is what is broken, so something has to be in front of the break. Project Blue Book's
    /// inherited OCR reads the rules its pages are ruled with as runs of dashes, and blocks whose
    /// whole text is `-`, `- -` or `f. Other ------` end in one without a word anywhere near it
    /// (#280).
    private func endsBroken(_ text: String) -> Bool {
        let broken = text.hasSuffix("-") || text.hasSuffix("\u{00ad}")
            || hyphens.lineEndSubstitute.map { text.last == $0 } == true
        return broken && text.dropLast().last.map { $0.isLetter || $0.isNumber } == true
    }

    /// Whether what follows a break opens the rest of the word the page broke, rather than
    /// something of its own.
    ///
    /// A lowercase letter is what a broken word carries on with, which is all #266 asked for.
    /// **A line that opens with no letter at all opens no sentence**, so a serial, a citation or a
    /// measure crosses a break the way a word does; one that opens with a marker of its own is
    /// excluded whatever it holds, because that marker opens an item. **A capital opens a sentence
    /// unless the two halves make a word the book itself writes** — the same evidence
    /// `HyphenRepair` reads to decide the hyphen, and the reason *The Fed Explained* may carry
    /// `Fed-` over `Wire`: it writes `Fedwire` whole twenty times. `…and square-` followed by
    /// `Two persons hold the folded flag` makes no word anywhere, so a new sentence stays one
    /// (#266's contract, #280).
    private func opensRestOfWord(_ text: String, _ line: String) -> Bool {
        guard let first = line.first(where: { !$0.isWhitespace }) else { return false }
        if first.isLowercase { return true }
        guard !LayoutReconstructor.isList(line) else { return false }
        if !first.isLetter { return true }
        let prefix = LayoutReconstructor.vocabularyWord(
            String(text.dropLast().reversed().prefix(while: \.isLetter).reversed()))
        let suffix = LayoutReconstructor.vocabularyWord(String(line.prefix(while: \.isLetter)))
        guard prefix.count >= 2, suffix.count >= 2 else { return false }
        return hyphens.vocabulary.contains(prefix + suffix)
            && !hyphens.vocabulary.contains(prefix + "-" + suffix)
    }
}
