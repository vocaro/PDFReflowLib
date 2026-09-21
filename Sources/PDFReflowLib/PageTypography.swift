import CoreGraphics
import Foundation

/// The type-size evidence one page supplies for its heading decisions and the leading its own
/// text states, computed once per page. `pageLines` are every line on the page;
/// `reflowableLines` exclude text preserved inside images, because small labels inside a figure
/// must not turn the surrounding prose into headings, and a figure's stacked labels say nothing
/// about the leading the prose is set on.
struct PageTypography: Equatable {
    /// The page's body: the character-weighted commonest size over every line, at least 4 pt.
    let body: CGFloat
    /// The body the reflowable text establishes (at least three lines and 200 characters in
    /// their commonest size), or nil when the page is too sparse to state one.
    let establishedBody: CGFloat?
    /// The body heading candidates are measured against: the page body, unless the reflowable
    /// text establishes a larger one.
    let headingBody: CGFloat
    /// On a page too sparse to establish a body of its own, a heading must also clear 110% of
    /// the document's body (#186); zero otherwise.
    let documentFloor: CGFloat
    /// The size at or above which a line reads as a heading: a quarter over the page body, a
    /// tenth over the heading body, and the document floor.
    let headingThreshold: CGFloat
    /// The leading the page's reflowable text states, or nil where it states none (#123).
    let leading: CGFloat?

    init(pageLines: [TextLine], reflowableLines: [TextLine], documentBody: CGFloat?) {
        let body = max(4, LayoutReconstructor.bodySize(pageLines))
        let established = LayoutReconstructor.establishedBodySize(reflowableLines)
        let headingBody = established.map { max(body, $0) } ?? body
        let documentFloor = documentBody.map { established == nil ? $0 * 1.1 : 0 } ?? 0
        self.body = body
        establishedBody = established
        self.headingBody = headingBody
        self.documentFloor = documentFloor
        headingThreshold = max(body * 1.25, headingBody * 1.1, documentFloor)
        leading = LayoutReconstructor.statedLeading(reflowableLines)
    }

    /// The typography of a whole page's lines, with no document floor: what the label survey and
    /// the region detectors read.
    init(page: PageContent) {
        self.init(pageLines: page.lines, reflowableLines: page.lines, documentBody: nil)
    }
}
