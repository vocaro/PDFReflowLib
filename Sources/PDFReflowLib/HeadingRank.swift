import CoreGraphics
import Foundation

/// The display sizes a book's own tags rank as headings, gathered over every native page in the
/// extraction pass and consulted where one page's tags contradict them (#294).
///
/// A page whose tags name a heading is believed over its visible typography, role for role,
/// because a producer that states `H` roles knew how to state one (#67). The per-page exception
/// in `contradictedHeadingGroups` reads a paragraph-tagged display line as a heading where the
/// same page's tags call that exact size a heading: the Fed's page 21 states its own ranking,
/// twice. IRS Publication 596's cover does not. It tags `目录` a paragraph beside an `H1` set two
/// points larger, and no other line on the page is set like it. What the book does state, over
/// its other thirty-five pages, is that seventeen- and eighteen-point lines are its `H1` and
/// fourteen-point lines its `H2`; a fifteen-point line stands inside that range, and a paragraph
/// role on it contradicts the book rather than the page.
///
/// So the rank is the book's tagged heading sizes, largest first, each with the level the tags
/// give it most often, and it speaks only about a line set at or above its smallest size, giving
/// it the level of the largest tier not above it. Below that floor it has no opinion and the tag
/// is believed as before, which is what keeps *Our Flag*'s nine- and twelve-point title-page
/// imprint a paragraph under that book's eighteen-point floor. A tier needs its size tagged a
/// heading on at least three pages, as a recurring label style does (#218), so one page's odd `H`
/// cannot rank the book; and only a tagged heading that reads as a heading on its own page
/// counts, so a body-size `H` on a sparse page states no display size — *Our Flag* tags
/// nine-point lines `H` on two pages, and its imprint is set in nine. A style is a size and,
/// where PDFKit reports one, a weight: the rank speaks to a line of the weight it ranked. Of the
/// corpus's seven tagged books only *Loper Bright*'s bold `H3` reports one; the IRS book's fonts
/// all reach PDFKit as plain `Helvetica`.
///
/// The rank ranks styles; it never demotes. A line the page's own typography reads as prose is
/// never touched, and a page whose tags name no heading is decided by the rule above it.
struct HeadingRank: Equatable, Sendable {
    /// One display size the book's tags call a heading, with the level they give it.
    struct Tier: Equatable, Sendable {
        /// The size to the half point, `LayoutReconstructor.sizeKey`'s grain.
        var size: Int
        /// Whether the lines of this tier read wholly bold.
        var bold: Bool
        var level: Int
    }

    /// Largest first.
    private(set) var tiers: [Tier] = []

    /// How many pages must tag a size a heading before it ranks: three, as `labelStyles(from:)`
    /// asks of a label style.
    static let pagesToRank = 3

    /// A rank with no opinion: what a book whose tags name no heading has.
    init() {}

    init(tiers: [Tier]) {
        self.tiers = tiers.sorted { $0.size > $1.size }
    }

    /// What one extraction pass gathers: for each style, the pages on which a heading-sized
    /// line the tags call a heading appears, and the levels they give it.
    struct Tally: Equatable, Sendable {
        private struct Style: Hashable, Sendable {
            var size: Int
            var bold: Bool
        }
        private var pages: [Style: Set<Int>] = [:]
        private var levels: [Style: [Int: Int]] = [:]

        init() {}

        /// Folds one native page in: every line the tags call a heading that the page's own
        /// typography also reads as heading-sized.
        mutating func record(_ page: PageContent, pageIndex: Int) {
            let typography = PageTypography(page: page)
            for line in page.lines {
                guard let tag = line.structure, tag.headingLevel > 0,
                      LayoutReconstructor.isTitleSized(line, in: page.lines, typography: typography,
                                                       judgesTitleWords: false) else { continue }
                let style = Style(size: LayoutReconstructor.sizeKey(line.fontSize),
                                  bold: LayoutReconstructor.readsWhollyBold(line))
                pages[style, default: []].insert(pageIndex)
                levels[style, default: [:]][tag.headingLevel, default: 0] += 1
            }
        }

        /// The styles tagged a heading on enough pages, each at the level the tags give it most
        /// often; between levels given equally often, the shallower.
        fileprivate var ranked: [Tier] {
            pages.compactMap { style, pages -> Tier? in
                guard pages.count >= HeadingRank.pagesToRank, let counts = levels[style],
                      let commonest = counts.max(by: { a, b in
                          a.value < b.value || (a.value == b.value && a.key > b.key)
                      }) else { return nil }
                return Tier(size: style.size, bold: style.bold, level: commonest.key)
            }.sorted { $0.size > $1.size }
        }
    }

    init(_ tally: Tally) {
        tiers = tally.ranked
    }

    /// The level the book's tags give a line of this size and weight: that of the largest tier
    /// not above it. Nil where the rank has no opinion — below its floor, or of a weight it never
    /// ranked — and the line's own tag is believed.
    func level(of line: TextLine) -> Int? {
        let size = LayoutReconstructor.sizeKey(line.fontSize)
        let bold = LayoutReconstructor.readsWhollyBold(line)
        return tiers.first { $0.bold == bold && $0.size <= size }?.level
    }
}
