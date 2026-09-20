import Foundation
import Testing
@testable import PDFReflowLib

// East Asian writing sets no space between the characters of a word, and justification stretches
// the gaps between characters rather than between words (#42).

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/42")) func aLineBreakInsideChineseIsNotAWordBreak() {
    var warnings: [ConversionWarning] = []
    // The join that added a space inside 您通常不|能是其他纳税人的合条件子女 on IRS 596 page 16.
    #expect(LayoutReconstructor.join("您通常不", "能是其他纳税人的合条件子女", vocabulary: [], page: 16, warnings: &warnings)
            == "您通常不能是其他纳税人的合条件子女")
    // A line ending in Chinese punctuation runs on the same way.
    #expect(LayoutReconstructor.join("联合报税表。", "如果您已婚", vocabulary: [], page: 16, warnings: &warnings)
            == "联合报税表。如果您已婚")
    #expect(warnings.isEmpty)
    // Latin text is untouched, and so is a boundary between the two scripts.
    #expect(LayoutReconstructor.join("the first", "line", vocabulary: [], page: 1, warnings: &warnings)
            == "the first line")
    #expect(LayoutReconstructor.join("提交表格", "1040", vocabulary: [], page: 1, warnings: &warnings)
            == "提交表格 1040")
    #expect(LayoutReconstructor.join("EIC", "吗？", vocabulary: [], page: 1, warnings: &warnings)
            == "EIC 吗？")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/42")) func aStretchedGapBetweenIdeographsIsNotAMissingWordSpace() {
    // The same gap that means a word space between two Latin letters means justification here.
    #expect(NativeSpacingReader.sameFontWordSpace(before: nil, left: "件", right: "子", gap: 1) == false)
    #expect(NativeSpacingReader.sameFontWordSpace(before: nil, left: "安", right: "全", gap: 0.5) == false)
    // Controls: Latin keeps the rule, and so does a boundary with Latin on one side.
    #expect(NativeSpacingReader.sameFontWordSpace(before: nil, left: "d", right: "t", gap: 1))
    #expect(NativeSpacingReader.sameFontWordSpace(before: nil, left: "件", right: "A", gap: 1))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/42")) func spacesBetweenIdeographsAreRemovedFromTheTextLayer() {
    func joined(_ text: String) -> String {
        CJKText.joinIdeographs(NSAttributedString(string: text)).string
    }
    // A letter-spaced heading read one character at a time (IRS 596: 社会安全卡注明).
    #expect(joined("社 会 安 全 卡 注 明") == "社会安全卡注明")
    #expect(joined("合条件 子女") == "合条件子女")
    // A space the source really sets after Chinese punctuation is not between two ideographs.
    #expect(joined("联合报税表。 如果您已婚") == "联合报税表。 如果您已婚")
    // Every boundary with Latin keeps the source's own spacing, in both directions.
    #expect(joined("提交表格 1040 或 1040-SR 的特定") == "提交表格 1040 或 1040-SR 的特定")
    #expect(joined("仅经 INS 授 权才适用于就业") == "仅经 INS 授权才适用于就业")
    #expect(joined("the quick brown fox") == "the quick brown fox")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/42")) func removingASpaceKeepsTheAttributesEitherSideOfIt() {
    let styled = NSMutableAttributedString(string: "社 会")
    let marker = NSAttributedString.Key("test.marker")
    styled.addAttribute(marker, value: "left", range: NSRange(location: 0, length: 1))
    styled.addAttribute(marker, value: "right", range: NSRange(location: 2, length: 1))
    let joined = CJKText.joinIdeographs(styled)
    #expect(joined.string == "社会")
    #expect(joined.attribute(marker, at: 0, effectiveRange: nil) as? String == "left")
    #expect(joined.attribute(marker, at: 1, effectiveRange: nil) as? String == "right")
}
