import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

/// #151: only annotations that change what a reader sees earn a source-page reference image.
/// Borderless links (NASA Word paper page 1, the USDA magazine, the Fed, FAA, 9/11), unfilled form
/// fields and form buttons (US Courts Pro Se 1) lose only their interaction, which a warning names.
/// Controls keep the reference: a bordered link (9/11 pages 570, 571 and 575), a filled text field,
/// a checked box and a stamp. Checkbox widgets over printed box glyphs rewrite those glyphs as ☐/☒.
private struct AnnotatedPages {
    /// Each page: extra content drawn after the page's prose, and its /Annots entries.
    var pages: [(content: String, annotations: String)]

    var data: Data {
        // 1 catalog, 2 pages, 3 font, 4 red, 5 text and 6 white appearances, then page + contents pairs.
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [\(pages.indices.map { "\(7 + 2 * $0) 0 R" }.joined(separator: " "))] /Count \(pages.count) >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            testPDFStream("1 0 0 rg 0 0 100 16 re f", extra: "/Type /XObject /Subtype /Form /BBox [0 0 100 16]"),
            testPDFStream("BT /F1 10 Tf 2 4 Td (Jane Q. Public) Tj ET",
                          extra: "/Type /XObject /Subtype /Form /BBox [0 0 200 16] /Resources << /Font << /F1 3 0 R >> >>"),
            testPDFStream("1 g 0 0 100 16 re f", extra: "/Type /XObject /Subtype /Form /BBox [0 0 100 16]"),
        ]
        for (index, page) in pages.enumerated() {
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> "
                + "/Contents \(8 + 2 * index) 0 R /Annots [\(page.annotations)] >>")
            objects.append(testPDFStream(prose + "\n" + page.content))
        }
        return testPDF(objects: objects)
    }
}

private let prose = """
BT /F1 12 Tf 1 0 0 1 72 700 Tm (The page opens with an ordinary paragraph of prose.) Tj ET
BT /F1 12 Tf 1 0 0 1 72 684 Tm (It continues on a second line before the page ends.) Tj ET
"""

private let borderlessLink = "<< /Type /Annot /Subtype /Link /Rect [72 696 300 712] /Border [0 0 0] /A << /S /URI /URI (https://example.gov/) >> >>"
private let borderedLink = "<< /Type /Annot /Subtype /Link /Rect [72 696 300 712] /Border [0 0 1] /C [0 0 1] /A << /S /URI /URI (https://example.gov/) >> >>"
private let emptyField = "<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /F 4 /Rect [72 400 300 416] >>"
private let pushButton = "<< /Type /Annot /Subtype /Widget /FT /Btn /Ff 65536 /T (print) /F 4 /Rect [72 40 172 56] /MK << /CA (Print) >> /AP << /N 4 0 R >> >>"
private let filledField = "<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /F 4 /V (Jane Q. Public) /Rect [72 400 272 416] /AP << /N 5 0 R >> >>"
private let stamp = "<< /Type /Annot /Subtype /Stamp /F 4 /Rect [400 40 500 56] /AP << /N 4 0 R >> >>"
/// White paint over white paper inks its own bitmap but changes nothing on the page (FAA page 362's
/// white highlight).
private let whiteStamp = "<< /Type /Annot /Subtype /Stamp /F 4 /Rect [400 40 500 56] /AP << /N 6 0 R >> >>"
private let hiddenStamp = "<< /Type /Annot /Subtype /Stamp /F 2 /Rect [400 40 500 56] /AP << /N 4 0 R >> >>"

/// A `Jury Trial:` row with two box glyphs (`’`, as the form's WP-IconicSymbolsA ToUnicode map
/// reads them) and a checkbox widget over each; `state` is each widget's appearance state.
private func juryRow(_ first: String, _ second: String) -> (content: String, annotations: String) {
    func box(_ x: Int, _ state: String) -> String {
        "<< /Type /Annot /Subtype /Widget /FT /Btn /T (box\(x)) /F 4 /Rect [\(x - 4) 596 \(x + 8) 610] /V /\(state) /AS /\(state) "
            + "/MK << /CA (4) >> /AP << /N << /Yes 4 0 R >> >> >>"
    }
    let content = """
    BT /F1 12 Tf 1 0 0 1 72 600 Tm (Jury Trial:) Tj ET
    BT /F1 12 Tf 1 0 0 1 150 600 Tm (\\222) Tj ET
    BT /F1 12 Tf 1 0 0 1 162 600 Tm (Yes) Tj ET
    BT /F1 12 Tf 1 0 0 1 200 600 Tm (\\222) Tj ET
    BT /F1 12 Tf 1 0 0 1 212 600 Tm (No) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 560 Tm (The Clerk\\222s Office fills in the case number.) Tj ET
    """
    return (content, box(150, first) + " " + box(200, second))
}

private func reconstruct(_ pages: AnnotatedPages, references: ConversionOptions.ReferenceImagePolicy = .automatic)
    async throws -> PDFReflowLibPipeline.Result {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("annotated.pdf")
    try pages.data.write(to: source)
    var options = ConversionOptions(); options.ocr = .never; options.referenceImages = references
    return try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
}

private func references(on page: Int, _ result: PDFReflowLibPipeline.Result) -> Int {
    result.document.blocks.filter {
        if case let .image(image) = $0.content { $0.page == page && image.provenance == "Source page \(page)"
            && image.alternativeText == PreservedImageKind.sourcePage.alternativeText } else { false }
    }.count
}

private func annotationMessages(on page: Int, _ result: PDFReflowLibPipeline.Result) -> [String] {
    result.warnings.filter { $0.page == page && $0.code == .annotationsNotConverted }.map(\.message)
}

@Test func onlyAnnotationsThatShowEarnASourcePageReference() async throws {
    let row = juryRow("Off", "Off")
    let pages = AnnotatedPages(pages: [
        ("", borderlessLink),                              // 1: NASA/USDA/Fed/FAA links
        ("", emptyField + " " + pushButton),               // 2: US Courts empty field and Print button
        (row.content, row.annotations),                    // 3: unchecked boxes over printed glyphs
        ("", hiddenStamp),                                 // 4: a hidden annotation is not drawn
        ("", borderedLink),                                // 5: 9/11 pages 570, 571, 575
        ("", filledField),                                 // 6: a value the page does not print
        (juryRow("Yes", "Off").content, juryRow("Yes", "Off").annotations), // 7: a checked box
        ("", stamp),                                       // 8: a stamp
    ])
    let result = try await reconstruct(pages)
    for page in 1...4 {
        #expect(references(on: page, result) == 0, "page \(page)")
        #expect(!result.warnings.contains { $0.page == page && ($0.code == .imageRegion || $0.code == .referenceImageOmitted) },
                "page \(page)")
    }
    #expect(annotationMessages(on: 1, result) == [
        "Links on this page are not interactive in the EPUB. They show nothing beyond the printed page, so no source-page image is added."])
    for page in [2, 3] {
        #expect(annotationMessages(on: page, result) == [
            "Form fields on this page are not interactive in the EPUB. They show nothing beyond the printed page, so no source-page image is added."],
                "page \(page)")
    }
    #expect(annotationMessages(on: 4, result).isEmpty)
    for page in 5...8 {
        #expect(references(on: page, result) == 1, "page \(page)")
        #expect(annotationMessages(on: page, result) == [
            "A page image preserves visible annotations. Link and form interactions are not reconstructed."], "page \(page)")
    }
    // Every page's prose still reflows.
    #expect(result.document.blocks.filter { $0.text.contains("The page opens with an ordinary paragraph") }.count == 8)
    try result.document.validate()

    // Under `.never` only the pages whose annotations show report an omitted reference.
    let never = try await reconstruct(pages, references: .never)
    #expect(Set(never.warnings.filter { $0.code == .referenceImageOmitted }.map(\.page)) == [5, 6, 7, 8])
    #expect(never.document.assets.isEmpty)
}

@Test func checkboxWidgetsRewriteTheBoxGlyphsTheySitOn() async throws {
    let unchecked = juryRow("Off", "Off"), checked = juryRow("Off", "Yes")
    let result = try await reconstruct(AnnotatedPages(pages: [unchecked, checked]))
    let text = result.document.blocks.map(\.text)
    #expect(text.filter { $0.contains("Jury Trial:") } == ["Jury Trial: ☐ Yes ☐ No", "Jury Trial: ☐ Yes ☒ No"])
    // The apostrophe in a line without a checkbox is untouched.
    #expect(text.filter { $0.contains("The Clerk’s Office fills in the case number.") }.count == 2)
    #expect(!text.joined().contains("Clerk☐s"))

    // A line where the glyph also occurs outside a box keeps every occurrence as extracted.
    var lines = [TextLine(text: "Clerk’s box ’ Yes", rect: CGRect(x: 72, y: 598, width: 200, height: 12), fontSize: 12)]
    AnnotationEvidence.markBoxes([.init(bounds: CGRect(x: 146, y: 596, width: 12, height: 14), on: false, glyph: "’")], in: &lines)
    #expect(lines[0].text == "Clerk’s box ’ Yes")
    lines = [TextLine(text: "box ’ Yes", rect: CGRect(x: 72, y: 598, width: 200, height: 12), fontSize: 12)]
    AnnotationEvidence.markBoxes([.init(bounds: CGRect(x: 146, y: 596, width: 12, height: 14), on: false, glyph: "’")], in: &lines)
    #expect(lines[0].text == "box ☐ Yes")
}

@Test func annotationJudgmentReadsFieldsAndDrawings() throws {
    let row = juryRow("Off", "Yes")
    let data = AnnotatedPages(pages: [
        ("", borderlessLink + " " + emptyField + " " + pushButton + " " + whiteStamp),
        (row.content, row.annotations),
        ("", borderedLink + " " + filledField + " " + stamp + " " + hiddenStamp),
        // The printed value under a pre-filled field: the form's `__________ Division`.
        ("BT /F1 10 Tf 1 0 0 1 76 404 Tm (Jane Q. Public) Tj ET", filledField),
    ]).data
    let document = try #require(PDFDocument(data: data))
    func judge(_ index: Int) throws -> AnnotationEvidence.Judgment {
        let page = try #require(document.page(at: index))
        return try AnnotationEvidence.judge(page, bounds: page.bounds(for: .cropBox))
    }
    let first = try judge(0)
    #expect((first.visible, first.links, first.formFields, first.invisible) == (0, 1, 2, 1))
    #expect(AnnotationEvidence.interactionMessage(first) == "Links and form fields on this page are not interactive in the EPUB. "
        + "They show nothing beyond the printed page, so no source-page image is added. Annotations that draw nothing are omitted.")
    let second = try judge(1)
    #expect((second.visible, second.formFields) == (1, 1))
    #expect(second.boxes.map(\.on) == [false, true] && second.boxes.allSatisfy { $0.glyph == "’" })
    let third = try judge(2)
    #expect((third.visible, third.links, third.formFields, third.invisible) == (3, 0, 0, 0))
    let fourth = try judge(3)
    #expect((fourth.visible, fourth.formFields) == (0, 1))
}
