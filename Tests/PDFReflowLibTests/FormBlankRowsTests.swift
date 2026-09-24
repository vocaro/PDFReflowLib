import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private struct FormPageEvidence: Decodable {
    struct Blank: Decodable {
        var rule: [Double]
        var field: [Double]
        func value() -> FormBlank {
            func rect(_ a: [Double]) -> CGRect { CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) }
            return FormBlank(rule: rect(rule), field: rect(field))
        }
    }
    var sourceSHA256: String
    var blanks: [Blank]
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func proSePrintedRowsKeepEachLabelWithItsBlank() throws {
    let evidence = try JSONDecoder().decode(FormPageEvidence.self,
        from: Data(contentsOf: fixtureURL("uscourts-1-layout.json")))
    #expect(evidence.sourceSHA256 == "9fe218570d311b0deab9413e39efda41210e60f2a5221eb360d43912ce05a118")
    let source = try SourceLayoutFixture.load("uscourts-1").content()
    let joined = FormBlankRows.joined(source.lines, blanks: evidence.blanks.map { $0.value() })
    for label in ["Name", "Street Address", "City and County", "State and Zip Code", "Telephone Number", "E-mail Address"] {
        #expect(joined.contains { $0.text == "\(label) ____" && $0.wraps == false }, "\(label)")
    }
    #expect(joined.contains { $0.text == "Case No. ____" })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func printedWritingRulesNeedAReadableRowAndNoCrossingArt() throws {
    let label = TextLine(text: "Applicant name", rect: CGRect(x: 80, y: 617, width: 74, height: 12), fontSize: 11)
    let rule = CGRect(x: 160, y: 614, width: 180, height: 4)
    let blank = FormBlank.printed(paints: [rule], lines: [label])
    #expect(blank.count == 1)
    #expect(FormBlankRows.joined([label], blanks: blank).map(\.text) == ["Applicant name ____"])
    let crossing = CGRect(x: 338, y: 612, width: 4, height: 10)
    #expect(FormBlank.printed(paints: [rule, crossing], lines: [label]).isEmpty)
    let value = TextLine(text: "Jane", rect: CGRect(x: 180, y: 618, width: 30, height: 10), fontSize: 11)
    #expect(FormBlank.printed(paints: [rule], lines: [label, value]).isEmpty)
    #expect(FormBlank.printed(paints: [rule], lines: []).isEmpty)
    let noaa = try SourceLayoutFixture.load("noaa-701")
    #expect(FormBlank.printed(paints: noaa.paints.map(\.rect), lines: noaa.content().lines).isEmpty)
}
