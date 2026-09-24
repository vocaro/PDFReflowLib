import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

@Test(arguments: [4, 16])
func chineseIRSUnderlinesDoNotBecomeAColumnSpanningTable(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("irs-joined-rules-\(number)")
    #expect(fixture.sourceSHA256 == "7d1cff45bc567f1257ea1aa1e2ce67945aafb12708b2e22901ce6392436590c2")
    #expect(fixture.page == number)
    let original = fixture.content()
    let page = TextBackdrop.compose(original, graphics: .init(regions: original.graphics,
        unsupported: false, images: original.pictures, paints: fixture.paints))
    let crops = LayoutReconstructor.graphicsWithLabels(page, language: "zh-Hans")
    // The source's linked phrases paint one underline in several adjacent glyph pieces.
    // Treating those pieces as separate table rules manufactures a crop across both columns.
    #expect(!crops.contains { $0.width > page.bounds.width * 0.8 && $0.height > 100 })
    var warnings: [ConversionWarning] = []
    let context = LayoutReconstructor.DocumentContext(language: "zh-Hans", documentBody: 10)
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") }, context: context, warnings: &warnings)
    func compact(_ value: String) -> String { String(value.filter { !$0.isWhitespace }) }
    let text = compact(blocks.map(\.text).joined(separator: " "))
    let expected = number == 4 ? [
        "Ave.NW, IR-6526, Washington, DC 20224",
        "尽管我们无法对收到的每条意见进行单独回复",
        "非常感谢您的反馈，并会在我们修改税务表格、说明和刊物时考虑您的意见和建议"
    ] : [
        "即使您父母不能申请或不申报 EIC",
        "示例 1——不需要提交报税表。",
        "示例 3——提交报税表是为了享受 EIC。",
        "驻扎在美国境外的军人。",
        "您必须再满足一条规则才能申报 EIC。",
        "61,555 美元（已婚联合报税为 68,675 美元）",
        "57,310 美元（已婚联合报税为 64,430 美元）",
        "50,434 美元（已婚联合报税为 57,554 美元）",
        "19,104 美元（已婚联合报税为 26,214 美元）"
    ]
    let positions = try expected.map { phrase in try #require(text.range(of: compact(phrase))?.lowerBound) }
    #expect(positions == positions.sorted())
    if number == 16 {
        #expect(text.contains(compact("请在（表格 1040 或 1040-SR）第 27b 行勾选“Clergy filing Schedule SE”")))
    }
}
