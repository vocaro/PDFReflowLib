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
    /// text establishes a larger one. On a sparse page, the document body and the page's
    /// smallest reflowable type cap an estimate dominated by display text (#296).
    let headingBody: CGFloat
    /// On a page too sparse to establish a body of its own, a heading must also clear 110% of
    /// the document's body (#186); zero otherwise.
    let documentFloor: CGFloat
    /// The size at or above which a line reads as a heading: a quarter over the page's heading
    /// estimate, a tenth over the established heading body, and the document floor.
    let headingThreshold: CGFloat
    /// The leading the page's reflowable text states, or nil where it states none (#123).
    let leading: CGFloat?
    /// A corroborated secondary body's own leading. Smaller table text must not set the
    /// paragraph spacing of the larger prose, nor borrow that prose's looser spacing itself:
    /// a smaller size that sets wrapped prose of its own keeps its own leading too, where it
    /// differs from the page's (#314).
    let additionalLeading: [Int: CGFloat]

    init(pageLines: [TextLine], reflowableLines: [TextLine], documentBody: CGFloat?,
         nativeSizeEvidence: Bool = true) {
        let body = max(4, LayoutReconstructor.bodySize(pageLines))
        let established = LayoutReconstructor.establishedBodySize(reflowableLines)
        // A lone long title can outweigh its running head and become the page's commonest
        // size. With no established prose, that size cannot disqualify the title itself.
        // Keep the page body for geometry; only heading classification takes this fallback.
        // Preserve the page's own size contrast as well: a chapter's small running head is
        // not a title merely because it is larger than the document's ordinary prose.
        let smallestSize = reflowableLines.map(\.fontSize).min() ?? body
        let sparseBody = documentBody.map { max($0, smallestSize, 4) } ?? body
        // Several short lines at one size can be a set of labels, not a title. The lack of
        // 200 prose characters does not make DGA's six food-label lines sparse display type.
        let dominantLines = reflowableLines.filter { Int($0.fontSize.rounded()) == Int(body) }
        let largestSize = reflowableLines.map(\.fontSize).max() ?? body
        // The fallback rescues a dominant title, not smaller bylines below an already larger
        // title. OCR box heights and synthetic font sizes are not native type-size evidence.
        // A lone mixed letter/digit token may be a publication identifier; it cannot
        // establish this additional title evidence on its own.
        let identifier = dominantLines.count == 1 && dominantLines[0].text.contains(where: \.isLetter)
            && dominantLines[0].text.contains(where: \.isNumber)
            && !dominantLines[0].text.contains(where: \.isWhitespace)
        let sparseTitle = nativeSizeEvidence && established == nil && dominantLines.count <= 2
            && Int(largestSize.rounded()) <= Int(body) && !identifier
        let headingPageBody = sparseTitle ? min(body, sparseBody) : body
        // Small footnotes or table cells can outnumber the ordinary prose. A sustained
        // paragraph still states its own body size; recovering those smaller lines must
        // not turn each row of the paragraph into a heading.
        // The document must corroborate that larger size. A page can also contain a larger
        // display summary above its ordinary body and headings; that summary must not raise
        // the threshold for everything beneath it (NOAA's focus pages).
        // Even when that prose equals the modal size, smaller notes may dominate the
        // line-spacing evidence. A corroborated run supplies its own leading in that case.
        var proseSizes: [CGFloat] = []
        if nativeSizeEvidence, let documentBody, documentBody >= body {
            proseSizes = Self.wrappedProseRuns(reflowableLines, ceiling: documentBody * 1.05).compactMap { $0.first?.fontSize }
        }
        let proseBody = proseSizes.max()
        let headingBody = max(established.map { max(body, $0) } ?? headingPageBody, proseBody ?? 0)
        let documentFloor = documentBody.map { established == nil ? $0 * 1.1 : 0 } ?? 0
        self.body = body
        establishedBody = established
        self.headingBody = headingBody
        self.documentFloor = documentFloor
        headingThreshold = max(headingPageBody * 1.25, headingBody * 1.1, documentFloor)
        leading = LayoutReconstructor.statedLeading(reflowableLines)
        var secondary: [Int: CGFloat] = [:]
        func ownLeading(_ size: Int) -> CGFloat? {
            LayoutReconstructor.statedLeading(reflowableLines.filter { Int($0.fontSize.rounded()) == size })
        }
        if let proseBody, let own = ownLeading(Int(proseBody.rounded())) {
            secondary[Int(proseBody.rounded())] = own
        }
        // A smaller size that sets wrapped prose of its own keeps its own spacing where it
        // differs from the page's, rather than borrow the page's looser leading: Hebrew
        // Shakespeare page 87 sets its notes on 9 points under a letter on 13, and once the
        // letter's wrapped run is whole the notes would otherwise be measured against 13 (#314).
        for size in Set(proseSizes.map { Int($0.rounded()) }).sorted() where secondary[size] == nil {
            if let own = ownLeading(size), own != leading { secondary[size] = own }
        }
        if nativeSizeEvidence, let documentBody, documentBody >= body,
                  let ownLeading = Self.shortParagraphLeading(reflowableLines, size: documentBody) {
            secondary[Int(documentBody.rounded())] = ownLeading
        }
        additionalLeading = secondary
    }

    /// A second body size needs stronger evidence than the modal estimate: four wrapped rows,
    /// 200 characters, a stable left edge and leading, and lowercase continuations. Display
    /// quotations, captions, bold headings and tagged headings cannot supply this evidence.
    static func wrappedProseRuns(_ lines: [TextLine], ceiling: CGFloat) -> [[TextLine]] {
        nativeWrappedRuns(lines).filter { run in
            guard run.count >= 4, run.reduce(0, { $0 + $1.text.count }) >= 200,
                  let first = run.first, first.fontSize <= ceiling, let opening = first.text.first,
                  !"\"“‘«".contains(opening), !LayoutReconstructor.isCaption(first.text),
                  run.allSatisfy({ ($0.structure?.headingLevel ?? 0) == 0
                      && !LayoutReconstructor.readsWhollyBold($0) }),
                  run.dropFirst().filter({ $0.text.first?.isLowercase == true }).count >= 3
            else { return false }
            let measure = run.map(\.rect.width).max() ?? 0
            guard measure >= first.fontSize * 16,
                  run.dropLast().allSatisfy({ $0.rect.width >= measure * 0.75 }),
                  run.filter({ LayoutReconstructor.readsAsSentence($0) }).count >= 3
            else { return false }
            return true
        }
    }

    /// The same geometric runs also supply spacing when a page has two short body paragraphs.
    /// This weaker count can establish only leading, never a larger heading/body threshold.
    /// Separate paragraphs must corroborate one another at the document's own body size.
    private static func shortParagraphLeading(_ lines: [TextLine], size: CGFloat) -> CGFloat? {
        let runs = nativeWrappedRuns(lines).filter { run in
            guard run.count >= 2, let first = run.first,
                  abs(first.fontSize - size) <= size * 0.05,
                  run.reduce(0, { $0 + $1.text.count }) >= 100,
                  first.text.first.map({ !"\"“‘«".contains($0) }) == true,
                  !LayoutReconstructor.isCaption(first.text),
                  run.allSatisfy({ ($0.structure?.headingLevel ?? 0) == 0
                      && !LayoutReconstructor.readsWhollyBold($0)
                      && !LayoutReconstructor.isList($0.text)
                      && LayoutReconstructor.readsAsSentence($0) }) else { return false }
            let measure = run.map(\.rect.width).max() ?? 0
            return measure >= size * 16 && run.dropLast().allSatisfy { $0.rect.width >= measure * 0.75 }
        }
        guard runs.count >= 2, runs.reduce(0, { $0 + $1.count }) >= 5,
              runs.flatMap({ $0 }).reduce(0, { $0 + $1.text.count }) >= 300,
              let first = runs.first?.first else { return nil }
        let measure = runs[0].map(\.rect.width).max() ?? 0
        guard runs.allSatisfy({ run in
            abs(run[0].rect.minX - first.rect.minX) <= size * 0.5
                && abs((run.map(\.rect.width).max() ?? 0) - measure) <= measure * 0.2
        }) else { return nil }
        let drops = runs.flatMap { run in zip(run, run.dropFirst()).map { $0.rect.maxY - $1.rect.maxY } }
        guard drops.count >= 3, let leading = drops.first,
              drops.allSatisfy({ abs($0 - leading) <= max(1, leading * 0.1) }) else { return nil }
        return (leading * 2).rounded() / 2
    }

    private static func nativeWrappedRuns(_ lines: [TextLine]) -> [[TextLine]] {
        guard lines.count <= 2_000 else { return [] }
        var runs: [[TextLine]] = []
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY }) {
            guard !line.monospaced, line.turn == .upright else { continue }
            if let index = runs.indices.last(where: { index in
                let run = runs[index], last = run.last!, size = max(last.fontSize, line.fontSize)
                let drop = last.rect.maxY - line.rect.maxY
                let leading = run.count > 1 ? run[0].rect.maxY - run[1].rect.maxY : drop
                return abs(last.fontSize - line.fontSize) <= size * 0.05
                    && abs(last.rect.minX - line.rect.minX) <= size * 0.25
                    && drop >= size * 0.8 && drop <= size * 2.2
                    && abs(drop - leading) <= max(1, leading * 0.2)
            }) { runs[index].append(line) }
            else { runs.append([line]) }
        }
        return runs
    }

    /// The typography of a whole page's lines, with no document floor: what the label survey and
    /// the region detectors read.
    init(page: PageContent) {
        self.init(pageLines: page.lines, reflowableLines: page.lines, documentBody: nil,
                  nativeSizeEvidence: !page.recognized && !page.hasSyntheticTextStyle)
    }
}
