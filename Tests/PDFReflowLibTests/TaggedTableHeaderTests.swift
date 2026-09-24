import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/17"))
func fedTableSourceTHCellsBecomeRowHeadersOnlyWherePrintedCellsAgree() throws {
    let source = URL(fileURLWithPath: "corpus/cache/the-fed-explained.pdf")
    let digest = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
    #expect(digest == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    let tree = try StructureTreeReader.read(source)
    let document = try #require(CGPDFDocument(source as CFURL))
    let page = try #require(document.page(at: 77))
    let ids = try #require(tree.tableHeaders[77])
    #expect(ids == [5, 6, 7, 8, 9, 13, 46])
    #expect(StructureTreeReader.validates(ids: ids,
        owners: try #require(tree.tableHeaderOwners[77]), page: page))
    let sourcePage = try PDFPageSource(url: source)
    let content = try PageReader.read(pageIndex: 76, from: sourcePage, limit: 100_000,
                                      options: ConversionOptions(), structure: tree).content
    let table = try #require(content.tables.first)
    #expect(table.rows[0].map(\.text) == ["Rating system", "CAMELS", "RFI/C(D)", "LFI"])
    #expect(table.rows[1][0].text == "Applicability")
    #expect(table.rows[1][0].isRowHeader == true)
    #expect(table.rows[1].dropFirst().allSatisfy { $0.isRowHeader != true })
    #expect(table.rows[2][0].text == "Components")
    #expect(table.rows[2][0].isRowHeader == true)
    #expect(table.rows[2].dropFirst().allSatisfy { $0.isRowHeader != true })
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: content, images: [], vocabulary: [], warnings: &warnings)
    let output = try #require(blocks.compactMap { block -> ReflowBlock.Table? in
        if case let .table(table) = block.content { return table }
        return nil
    }.first)
    #expect(output.rows[1][0].isRowHeader)
    #expect(output.rows[1][1].isRowHeader == false)
    let xhtml = EPUBTextEncoder.table(output, labels: [:])
    #expect(xhtml.contains("<th scope=\"row\">Applicability</th>"))
    #expect(xhtml.contains("<td>Depository institutions"))

    // A malformed ownership path cannot grant table semantics even if the MCID is printed
    // inside the same cell. This is the ParentTree negative control.
    var wrong = tree
    wrong.tableHeaderOwners[77]?[9] = []
    #expect(!StructureTreeReader.validates(ids: ids,
        owners: try #require(wrong.tableHeaderOwners[77]), page: page))
    let fallback = try PageReader.read(pageIndex: 76, from: sourcePage, limit: 100_000,
                                       options: ConversionOptions(), structure: wrong).content
    #expect(fallback.tables.allSatisfy { $0.rows.allSatisfy { $0.allSatisfy { $0.isRowHeader != true } } })
}
