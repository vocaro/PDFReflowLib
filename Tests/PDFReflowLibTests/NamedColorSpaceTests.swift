import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private func namedColorPage(_ content: String, profile: String = "/N 3", form: String = "/G cs 0 scn 0 0 8 8 re f") throws -> CGPDFPage {
    func stream(_ text: String, _ attributes: String = "") -> String {
        "<< /Length \(text.utf8.count) \(attributes) >>\nstream\n\(text)\nendstream"
    }
    let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /ColorSpace << /CS0 [/ICCBased 5 0 R] /G /DeviceGray >> /XObject << /Fm 6 0 R >> >> /Contents 4 0 R >>",
        stream(content), stream("", profile),
        stream(form, "/Type /XObject /Subtype /Form /BBox [0 0 8 8] /Resources << /ColorSpace << /G /DeviceGray >> >>")]
    var data = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (index, object) in objects.enumerated() {
        offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    data.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider)?.page(at: 1))
}

@Test func namedICCWhiteAndFlatColorSurviveGraphicsStateScopes() throws {
    let source = "/G cs q /CS0 cs 1 0 0 scn 20 20 20 20 re f Q 1 scn 60 20 20 20 re f "
        + "/CS0 cs 1 1 1 scn 100 20 20 20 re f /Fm Do 0 0 1 scn 140 20 20 20 re f"
    let result = GraphicsReader.read(try namedColorPage(source))
    #expect(!result.unsupported)
    #expect(result.paints.filter { $0.rect.contains(CGPoint(x: 30,y:30)) }.allSatisfy { $0.filled })
    #expect(result.paints.contains { $0.rect.contains(CGPoint(x:30,y:30)) })
    #expect(!result.paints.contains { $0.rect.contains(CGPoint(x:70,y:30)) || $0.rect.contains(CGPoint(x:110,y:30)) })
    #expect(result.paints.contains { $0.filled && $0.rect.contains(CGPoint(x:150,y:30)) })
}

@Test func patternsUnknownColorsAndNonstandardICCWhiteStayVisible() throws {
    for source in ["/Pattern cs /P scn", "/Missing cs 1 1 1 scn", "/CS0 cs 1 1 scn"] {
        let result = GraphicsReader.read(try namedColorPage(source + " 20 20 100 100 re f"))
        #expect(result.paints.count == 1)
        #expect(result.paints.first?.filled == false)
    }
    let custom = GraphicsReader.read(try namedColorPage("/CS0 cs 1 1 1 scn 20 20 100 100 re f", profile: "/N 3 /Range [-1 1 -1 1 -1 1]"))
    #expect(custom.paints.count == 1)
    #expect(custom.paints.first?.filled == true)
}
