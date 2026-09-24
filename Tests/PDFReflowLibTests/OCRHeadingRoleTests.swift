import CoreGraphics
import Testing
@testable import PDFReflowLib

// Vision's boxes are not measured type. A prose fragment or a table's word-column head can
// exceed the page's estimated heading size while standing beside other text in its printed row.
private func recognizedPage(_ fixture: String) throws -> PageContent {
    let capture = try SourceRecognitionFixture.load(fixture)
    func rect(_ values: [Double]) -> CGRect {
        CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    return PageContent(number: capture.page, bounds: rect(capture.bounds), lines: capture.reading().lines,
                       graphics: capture.graphics.map(rect), recognized: true)
}

private func recognizedRole(_ text: String, on page: PageContent) throws -> LineRole {
    let line = try #require(page.lines.first { $0.text == text })
    return LayoutReconstructor.role(of: line, on: page, in: page.lines,
                                    typography: PageTypography(page: page), labels: [], judgesTitleWords: true)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/216"))
func recognizedProseFragmentsAndWordColumnsDoNotBecomeHeadings() throws {
    let warren501 = try recognizedPage("warren-501")
    #expect(try recognizedRole("That (a) for the purposes corission in-", on: warren501) == .prose)
    #expect(try recognizedRole("APPENDIX III", on: warren501) == .heading)

    let warren566 = try recognizedPage("warren-566")
    #expect(try recognizedRole("LCOL PIERE A. FINCR, NC,USA (04 043 322)", on: warren566) == .prose)
    #expect(try recognizedRole("Autopsy Report and Supplemental Report", on: warren566) == .heading)

    let blueBook150 = try recognizedPage("blue-150")
    #expect(try recognizedRole("Certain Doubtful | Total", on: blueBook150) == .prose)
    #expect(try recognizedRole("TABLE A63", on: blueBook150) == .heading)
    #expect(try recognizedRole("METALLIC", on: blueBook150) == .prose)

    // The current Vision reading of page 50 gives this chart-axis month a tall box, but the
    // caption establishes a still larger type size. It remains a negative control for #216.
    let blueBook50 = try recognizedPage("blue-50")
    #expect(try recognizedRole("September", on: blueBook50) == .prose)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/216"))
func distantSecondColumnDoesNotVetoARecognizedHeading() {
    func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size), fontSize: size)
    }
    let body = (0..<5).map { row in
        line("A recognized body paragraph keeps enough words to establish its ordinary size across the page.",
             x: 40, y: 460 - CGFloat(row) * 13, width: 330, size: 10)
    }
    let title = line("Methods of Evaluation", x: 40, y: 500, width: 150, size: 16)
    let far = line("Other column", x: 260, y: 500, width: 100, size: 10)
    let near = line("Table value", x: 198, y: 500, width: 100, size: 10)
    func role(with companion: TextLine) -> LineRole {
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 600),
                               lines: body + [title, companion], graphics: [], recognized: true)
        return LayoutReconstructor.role(of: title, on: page, in: page.lines,
                                        typography: PageTypography(page: page), labels: [], judgesTitleWords: true)
    }
    #expect(role(with: far) == .heading)
    #expect(role(with: near) == .prose)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/216"))
func recognizedContinuationAndFormValuesDoNotBecomeHeadings() {
    // Fresh Vision output from Warren 501/566 produced these false h2 elements even though
    // the pinned captures above used different readings. Keep their printed text shapes as
    // controls against OCR's run-to-run segmentation changes.
    let rejected = [
        "appointed by the President by Executive Order 11130, dated November sassination of",
        "Prevkdent John P. Keunedy to compel the uttendance and testimony of wit-",
        "(c) in case of rontumacy or refusal to obey a subpena issued to ans",
        "It. - 170 pounds",
        "Rair - Reddish brown",
    ]
    func role(_ reading: String) -> LineRole {
        let body = (0..<5).map { row in
            TextLine(text: "The report records testimony and supporting evidence from the commission.",
                     rect: CGRect(x: 40, y: 440 - CGFloat(row) * 15, width: 450, height: 10), fontSize: 10)
        }
        let candidate = TextLine(text: reading,
                                 rect: CGRect(x: 40, y: 500, width: 450, height: 17), fontSize: 17)
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 700),
                               lines: body + [candidate], graphics: [], recognized: true)
        return LayoutReconstructor.role(of: candidate, on: page, in: page.lines,
                                        typography: PageTypography(page: page), labels: [], judgesTitleWords: true)
    }
    for reading in rejected { #expect(role(reading) == .prose, "\(reading)") }
    #expect(role("APPENDIX III") == .heading)
    #expect(role("Autopsy Report and Supplemental Report") == .heading)
    #expect(role("TABLE A63") == .heading)
    #expect(role("Methods - Overview") == .heading)
    #expect(role("Part - Overview") == .heading)
}
