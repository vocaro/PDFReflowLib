import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

/// A content stream of `count` charged operators, ending in one painted rectangle. The filler is
/// the text-rendering-mode operator, which the reader charges but which neither nests the
/// graphics state nor adds to the path, so the painted footprint stays the rectangle whatever
/// the length.
private func operations(_ count: Int) -> String {
    String(repeating: "0 Tr ", count: max(0, count - 2)) + "100 500 40 30 re f"
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/13"))
func aDenseButOrdinaryDrawingIsReadRatherThanRasterized() throws {
    // FAA pages 226, 286, 288 and 302 carry 101,000 to 183,000 operations of ordinary vector
    // drawing. Under the old 100,000 budget their prose never reflowed.
    let result = GraphicsReader.read(try operatorPage(operations(150_000)))
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 98, y: 498, width: 44, height: 34)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/13"))
func aPageOverTheBudgetIsStillPreservedWhole() throws {
    // The budget still bounds adversarial content: FAA page 448's 1.95 million operations stay
    // over it, and a page that exhausts it is preserved rather than half read.
    let result = GraphicsReader.read(try operatorPage(operations(260_000)))
    #expect(result.unsupported)
}

@Test func theBudgetIsSpentOnOperatorsInsideFormsToo() throws {
    // A page can hide its work in an XObject; the budget follows the reader into it.
    let result = GraphicsReader.read(try operatorPage("q 1 0 0 1 0 0 cm /Fm Do Q",
                                                      formContent: operations(260_000),
                                                      formBox: "[0 0 600 700]"))
    #expect(result.unsupported)
}

@Test func anOrdinaryPageSpendsAlmostNoneOfTheBudget() throws {
    let result = GraphicsReader.read(try operatorPage(operations(500)))
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 98, y: 498, width: 44, height: 34)])
}
