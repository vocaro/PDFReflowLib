import Foundation
import Testing
@testable import PDFReflowLib

private struct CaptionColumnCapture: Decodable { var nativeLines: [TextLine] }
private func captionColumnKey(_ text: String) -> String { text.lowercased().filter(\.isLetter) }

@Test(arguments: [8, 10, 13, 15])
func wideSourceCaptionsDoNotInvalidateCompleteBodyColumns(number: Int) throws {
    let name = "usda-caption-columns-\(number)"
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761")
    var page = fixture.content()
    page.lines = try JSONDecoder().decode(CaptionColumnCapture.self,
        from: Data(contentsOf: fixtureURL("\(name)-layout.json"))).nativeLines
    page.lines.removeAll { $0.rect.maxY < 40 }
    page = TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
    // Apply the production structural preparation: the source's page-sized photograph on
    // page 13 is retained as a page reference, freeing the printed native columns below it.
    let backed = page.graphics.contains { PageDiagnosis.coversPage($0, bounds: page.bounds) }
    PageDiagnosis.prepareExtracted(&page, evidence: .init(requiresPageImage: false, hasText: true,
        characters: page.lines.reduce(0) { $0 + $1.text.count }, replacementCharacters: 0,
        imageBackedText: backed, damagedEncoding: false, implausibleLayer: nil, drawnText: false))
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element,"image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10.5)
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return captionColumnKey(block.text) }; return nil
    }
    let passage: String
    let caption: String
    switch number {
    case 8:
        passage = "Another team member, entomologist Sandra Allan in the Insect Behavior and Biocontrol Research Unit at CMAVE, is using toxic sugar-based baits to lure and kill mosquitoes."
        caption = "Cups containing mosquitoes and sugar water mixed with different doses of pesticides. Technician Faith Umoh"
    case 10:
        passage = "The greatest potential for pyriproxyfen may be via autodissemination, a process in which adult flies are treated with pyriproxyfen that they later transport to egg-laying sites, he says."
        caption = "Entomologist Jerry Hogsette sets out stable fly traps and targets for a field study. Stable flies"
    case 13:
        passage = "Spatial repellents are used in field conditions to significantly reduce the number of mosquitoes and other biting insects in a specific area over a certain period of time, he says."
        caption = "In Marigat, Kenya, Kenneth Linthicum, the director of ARS’s Center for Medical, Agricultural, and Veterinary Entomology"
    default:
        passage = "Applying pesticides is no simple task. With dozens of manufacturers producing dozens of different types of spray technology—each with its own nozzle type, flow rate, and pressure setting range—the equipment can get pretty complicated."
        caption = "Two new apps developed by ARS scientists in College Station, Texas"
    }
    #expect(paragraphs.contains { $0.contains(captionColumnKey(passage)) })
    #expect(paragraphs.filter { $0.contains(captionColumnKey(caption)) }.count == 1)
    #expect(!paragraphs.contains { $0.contains(captionColumnKey(caption)) && $0.contains(captionColumnKey(passage)) })
    let assets = blocks.compactMap { block -> String? in
        if case .image(let image) = block.content { return image.assetID }; return nil
    }
    #expect(assets.count == crops.count)
    #expect(Set(assets) == Set(crops.indices.map { "image-\($0)" }))
}
