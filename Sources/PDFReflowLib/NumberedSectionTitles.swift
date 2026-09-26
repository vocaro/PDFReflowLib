import CoreGraphics
import Foundation

/// Section titles a book numbers, where its type alone does not say they are headings (#297).
///
/// The Census report sets its section titles (`2 Data Files`) in 12-point bold over a 10.08-point
/// body, a fifth larger, which is under the quarter a line must clear to be title-sized, and its
/// subsection titles (`2.1 Domingo-Ferrer and Mateo-Sanz`) in bold at the body's own size. Neither
/// weight reaches the library: PDFKit names every embedded Type 1 font `Helvetica` with no bold
/// trait (#250), and the report's font descriptors state none either (`/Flags 4`, `/StemV 0`), so
/// the recurring-label rule (#218) has no style to recur. What the book does state is its
/// numbering. A line that opens with a section number and a capitalised title, stands apart from
/// the lines above and below it, and belongs to a sequence the book keeps across its pages is a
/// section title, whatever its weight.
///
/// The evidence is document-wide and taken from native pages only:
///
/// - **Sections.** Numbered titles of one level set larger than the page's body, at one size, at
///   least three of them, starting from `1`, each number once and rising in reading order by at
///   most three: the Census report's native pages give `1`, `2`, `4` and `7`, its sections `3`,
///   `5` and `6` falling on pages the library had to recognize. A running head that repeats its
///   section's number on every page is not an outline, and nor is a magazine's contents, whose
///   display titles open with the page they start on: *Agricultural Research* lists `4`, `18`,
///   `20` and `21`.
/// - **Subsections.** Two-level titles set at the body's own size, at least two, rising in reading
///   order, each standing between the book's section titles as its number says: `2.1` and `2.2`
///   after section `2` and before `4`, `4.1` and `4.2` after `4` and before `7`.
///
/// A candidate opens with one or two levels of number, each of one or two digits and with no
/// point after the last (`1.` opens a list item), then a capital and at least three letters. It
/// stands apart from the lines above and below it (`titleLines`) and ends no sentence. A numbered
/// paragraph wraps onto a line one leading below, a list's items stand one leading apart, and a
/// run-in title carries on as its paragraph: none of them stands apart. The level the numbering
/// states is not written: untagged headings are flat, as every other rule reads them.
///
/// Reading order within a page is taken top to bottom. A two-column page whose titles sort out of
/// their order that way states no outline and changes nothing, which is the safe way to be wrong.
enum NumberedSectionTitles {
    /// One numbered title a native page sets apart, in the order the book reads.
    struct Candidate: Equatable, Sendable {
        var page: Int
        var number: [Int]
        /// The line's size and its page's body, to the half point (`LayoutReconstructor.sizeKey`).
        var size: Int
        var body: Int
    }

    /// The titles the book's own numbering vouches for.
    struct Outline: Equatable, Sendable {
        struct Title: Hashable, Sendable {
            var page: Int
            var number: [Int]
            var size: Int
        }
        private(set) var titles: Set<Title> = []

        /// An outline with no opinion: what a book that numbers no sections has.
        init() {}

        init(titles: Set<Title>) { self.titles = titles }

        func contains(page: Int, number: [Int], size: Int) -> Bool {
            titles.contains(Title(page: page, number: number, size: size))
        }
    }

    /// Numbered titles of one level at one size before the book is said to number its sections.
    static let minimumSections = 3
    /// Subsection titles before the book is said to number its subsections.
    static let minimumSubsections = 2
    /// The furthest one section title's number may stand from the one before it: sections the
    /// library had to recognize leave gaps (the Census report reads `4` and then `7`), a page
    /// number does not count like this.
    static let maximumSectionStep = 3
    /// The longest title read, over one line or two.
    static let maximumLength = 120

    /// The section number a line opens with, where the rest of the line opens a title: one or two
    /// levels of one or two digits, no point after the last, then a capital.
    static func number(of text: String) -> [Int]? {
        guard text.count <= maximumLength,
              let space = text.firstIndex(where: \.isWhitespace) else { return nil }
        let token = text[..<space]
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 1 }) else { return nil }
        let title = text[space...].drop(while: \.isWhitespace)
        guard let first = title.first, first.isUppercase, title.filter(\.isLetter).count >= 3 else { return nil }
        return numbers
    }

    /// The line or two lines of a numbered title the page sets apart from its neighbours, opening
    /// with `line`; nil where `line` opens none.
    ///
    /// A title stands at least four fifths of a body below the line above it in its column, and
    /// at least two fifths above the line beneath, which must exist: its section's text. A title
    /// too long for its measure wraps onto one more line at its own size and within its own
    /// leading, and that line then stands apart from the text beneath: Replay Clocks sets
    /// `6 REPRESENTATION OF REPCL AND ITS` over `OVERHEAD`. Either way the title ends no sentence.
    static func titleLines(of line: TextLine, in lines: [TextLine], body: CGFloat) -> [TextLine]? {
        guard eligible(line, body: body), number(of: line.text) != nil,
              !LayoutReconstructor.isList(line.text) else { return nil }
        if let above = neighbour(of: line, in: lines, body: body, above: true),
           above.rect.minY - line.rect.maxY < body * 0.8 { return nil }
        guard let below = neighbour(of: line, in: lines, body: body, above: false) else { return nil }
        if line.rect.minY - below.rect.maxY >= body * 0.4 {
            return endsTitle(line.text) ? [line] : nil
        }
        let gap = line.rect.minY - below.rect.maxY
        guard eligible(below, body: body), below.hasSize(line.fontSize), number(of: below.text) == nil,
              gap >= -line.fontSize, gap <= line.fontSize * 0.8,
              line.text.count + 1 + below.text.count <= maximumLength, endsTitle(below.text),
              let beneath = neighbour(of: below, in: lines, body: body, above: false),
              below.rect.minY - beneath.rect.maxY >= body * 0.4 else { return nil }
        return [line, below]
    }

    private static func eligible(_ line: TextLine, body: CGFloat) -> Bool {
        line.turn == .upright && !line.monospaced && line.structure == nil && line.fontSize >= body * 0.95
    }

    private static func endsTitle(_ text: String) -> Bool {
        text.last.map { !".,;:".contains($0) } ?? false
    }

    /// The nearest line of `line`'s column above or below it, pieces of its own row aside.
    private static func neighbour(of line: TextLine, in lines: [TextLine], body: CGFloat, above: Bool) -> TextLine? {
        let column = lines.filter { line.sharesColumn(with: $0) && !line.sharesRow(with: $0) }
        return above
            ? column.filter { $0.rect.minY >= line.rect.maxY - body * 0.25 }.min { $0.rect.minY < $1.rect.minY }
            : column.filter { $0.rect.maxY <= line.rect.minY + body * 0.25 }.max { $0.rect.maxY < $1.rect.maxY }
    }

    /// One native page's numbered titles, top to bottom.
    static func candidates(on page: PageContent) -> [Candidate] {
        guard !page.recognized, !page.hasSyntheticTextStyle, !page.requiresPageImage else { return [] }
        let body = PageTypography(page: page).body
        return page.lines.compactMap { line -> (TextLine, [Int])? in
            guard let number = number(of: line.text), titleLines(of: line, in: page.lines, body: body) != nil
            else { return nil }
            return (line, number)
        }
        .sorted { $0.0.rect.maxY > $1.0.rect.maxY }
        .map { Candidate(page: page.number, number: $0.1, size: LayoutReconstructor.sizeKey($0.0.fontSize),
                         body: LayoutReconstructor.sizeKey(body)) }
    }

    /// The titles the book's numbering vouches for, from every native page's candidates in
    /// reading order.
    static func outline(from candidates: [Candidate]) -> Outline {
        // Sections: one level, set larger than the body, grouped by size.
        let sectionCandidates = candidates.enumerated().filter { _, candidate in
            candidate.number.count == 1 && Double(candidate.size) >= Double(candidate.body) * 1.1
        }
        var sections: [(order: Int, candidate: Candidate)] = []
        for (_, group) in Dictionary(grouping: sectionCandidates, by: { $0.element.size }) {
            let numbers = group.map { $0.element.number[0] }
            guard numbers.count >= minimumSections, numbers.first == 1,
                  zip(numbers, numbers.dropFirst()).allSatisfy({ $0 < $1 && $1 - $0 <= maximumSectionStep })
            else { continue }
            sections += group.map { (order: $0.offset, candidate: $0.element) }
        }
        guard !sections.isEmpty else { return Outline() }
        sections.sort { $0.order < $1.order }
        // Subsections: two levels, set at the body's own size, each between the sections its
        // number places it between.
        let subsections = candidates.enumerated().filter { order, candidate in
            guard candidate.number.count == 2, abs(candidate.size - candidate.body) <= 1 else { return false }
            let before = sections.last { $0.order < order }?.candidate.number[0]
            let after = sections.first { $0.order > order }?.candidate.number[0]
            let section = candidate.number[0]
            return (before.map { $0 <= section } ?? true) && (after.map { section < $0 } ?? true)
        }.map(\.element)
        let rising = zip(subsections, subsections.dropFirst()).allSatisfy { $0.number.lexicographicallyPrecedes($1.number) }
        var titles = Set(sections.map { Outline.Title(page: $0.candidate.page, number: $0.candidate.number,
                                                      size: $0.candidate.size) })
        if subsections.count >= minimumSubsections, rising {
            titles.formUnion(subsections.map { Outline.Title(page: $0.page, number: $0.number, size: $0.size) })
        }
        return Outline(titles: titles)
    }

    /// One page's lines with each title the book's outline vouches for as a single line, and those
    /// titles. A title the page wraps onto a second line becomes one line over both, as a stacked
    /// label does (`StackedSectionLabels`): two headings would be two navigation entries, and a
    /// break between two Latin words says nothing to the assembler about one title.
    static func coalescing(_ lines: [TextLine], page: PageContent, body: CGFloat,
                           outline: Outline) -> (lines: [TextLine], titles: [TextLine]) {
        guard !outline.titles.isEmpty, !page.recognized, !page.hasSyntheticTextStyle else { return (lines, []) }
        var result = lines
        var titles: [TextLine] = []
        for line in lines {
            guard let number = number(of: line.text),
                  outline.contains(page: page.number, number: number, size: LayoutReconstructor.sizeKey(line.fontSize)),
                  let title = titleLines(of: line, in: lines, body: body),
                  let first = result.firstIndex(of: line) else { continue }
            guard title.count == 2, let second = result.firstIndex(of: title[1]) else {
                titles.append(line)
                continue
            }
            var content = line.content
            content.append(InlineText(" "))
            content.append(title[1].content)
            let merged = TextLine(content: content, rect: line.rect.union(title[1].rect), fontSize: line.fontSize,
                                  monospaced: line.monospaced, turn: line.turn)
            result[first] = merged
            result.remove(at: second)
            titles.append(merged)
        }
        return (result, titles)
    }
}
