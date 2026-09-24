import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private let noaaColumnOrder: [Int: [String]] = [
    50: ["Figure 1.7. Billion-dollar weather", "Adapted from NCEI 2023.",
         "The impacts and risks of climate change unfold", "The risk of two or more extreme events",
         "Compound events often have cascading impacts"],
    60: ["hurricanes will strain wastewater", "Forward-looking designs of infrastructure",
         "Figure 22.17", "Climate change is already harming human health",
         "Mental and spiritual health stressors", "The Hooskanaden Landslide"],
    63: ["Together with other stressors", "Figure A4.12", "Changes in ocean conditions",
         "Increased risks to ecosystems", "While adaptation options", "Coastal ghost forests result"],
    64: ["Climate change slows economic growth", "Mitigation and adaptation actions present economic",
         "Many regional economies and livelihoods", "Climate change is projected to reduce US economic output",
         "As fish stocks in the Northeast", "While the Southeast and US Caribbean",
         "Agricultural losses in the Midwest", "In the Northern Great Plains"],
    78: ["Actions taken now to accelerate", "Accelerating the deployment", "Transitioning to a carbon-free",
         "Reducing emissions of short-lived", "Green infrastructure and nature-based solutions",
         "Strategic planning and investment", "Improving cropland management",
         "Climate actions that incorporate inclusive", "Transformative climate actions",
         "Fossil fuel–based energy systems", "A “just transition”"]
]

private let noaaColumnParagraphs: [Int: [String]] = [
    50: ["Figure 1.7. Billion-dollar weather and climate disasters are events where damages/costs reach or exceed $1 billion, including adjustments for inflation.",
         "These interactions and interdependencies can lead to cascading impacts and sudden failures."],
    60: ["Climate change is already harming human health across the US, and impacts are expected to worsen with continued warming. Climate change harms individuals and communities by exposing them to a range of compounding health hazards, including the following:",
         "Forward-looking designs of infrastructure and services can help build resilience to climate change, offset costs from future damage to transportation and electrical systems"],
    63: ["Changes in ocean conditions and extreme events are already transforming coastal, aquatic, and marine ecosystems. Coral reefs are being lost due to warming and ocean acidification, harming important fisheries;",
         "Together with other stressors, climate change is harming the health and resilience of ecosystems, leading to reductions in biodiversity and ecosystem services."],
    64: ["Climate change is projected to reduce US economic output and labor productivity across many sectors, with effects differing based on local climate and the industries unique to each region.",
         "With every additional increment of global warming, costly damages are expected to accelerate. For example, 2°F of warming is projected to cause more than twice the economic harm induced by 1°F of warming."],
    78: ["expanding renewable energy, and improving building efficiency can have significant near-term social and economic benefits like reducing energy costs and creating jobs.",
         "the economic impacts of climate change, including costs to households and businesses, risks to markets and supply chains, and potential negative impacts on employment and income, while also providing opportunities for economic gain."]
]

@Test(arguments: [50, 60, 63, 64, 78])
func nativeNOAAColumnsStayWholeAcrossPreservedBackdrops(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("noaa-columns-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    #expect(fixture.page == number)
    var original = fixture.content()
    original.lines = original.lines.map { line in
        guard let attributed = fixture.attributedLines.first(where: { $0.text == line.text }) else { return line }
        return TextLine(content: NativeTextReader.inlineText(from: attributed.attributedString()), rect: line.rect,
                        fontSize: line.fontSize, monospaced: line.monospaced)
    }
    let page = TextBackdrop.compose(original, graphics: .init(regions: original.graphics,
        unsupported: false, images: original.pictures, paints: fixture.paints))
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    func canonical(_ value: String) -> String { value.lowercased().filter(\.isLetter) }
    let text = canonical(blocks.map(\.text).joined(separator: " "))
    let positions = try noaaColumnOrder[number]!.map { phrase in
        try #require(text.range(of: canonical(phrase))?.lowerBound, "Missing source phrase: \(phrase)")
    }
    #expect(positions == positions.sorted())
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return canonical(block.text) }
        return nil
    }
    for expected in noaaColumnParagraphs[number]! {
        #expect(paragraphs.contains { $0.contains(canonical(expected)) }, "Broken source paragraph: \(expected)")
    }
    let assets = blocks.compactMap { block -> String? in
        if case .image(let image) = block.content { return image.assetID }
        return nil
    }
    #expect(Set(assets) == Set(crops.indices.map { "image-\($0)" }))
    #expect(assets.count == crops.count)
}

@Test func aSpanningFigureNeedsProvedNativeBackdropOwnershipToFollowColumns() throws {
    typealias Element = LayoutReconstructor.Element
    let lines = [30.0, 250.0].flatMap { x in
        (0..<8).map { row in
            let line = TextLine(text: "This column has a full line of ordinary prose.",
                rect: CGRect(x: x, y: 400 - Double(row) * 14, width: 180, height: 12), fontSize: 10)
            return Element(rect: line.rect, line: line)
        }
    }
    let figure = Element(rect: CGRect(x: 100, y: 340, width: 240, height: 90), image: "chart")
    #expect(PrintedColumns.plan(lines + [figure], body: 10) == nil)
    var backdrop = figure
    backdrop.proseBackdrop = true
    let plan = try #require(PrintedColumns.plan(lines + [backdrop], body: 10))
    #expect(plan.columns.map(\.count) == [8, 8])
    #expect(plan.after[1]?.map(\.image) == ["chart"])
    var table = backdrop
    table.image = nil
    table.table = PageTable(rect: table.rect, rows: [[.init(content: InlineText("table"), rect: table.rect)]])
    #expect(PrintedColumns.plan(lines + [table], body: 10) == nil)
}
