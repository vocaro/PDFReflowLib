import CoreGraphics
import Foundation
import Testing

/// An original one-page PDF built from a content stream, so a graphics rule can be exercised one
/// operator at a time without a downloaded corpus or a PDF authoring dependency. The page carries
/// a one-pixel image and a form XObject under `/Im` and `/Fm`.
func operatorPDF(_ content: String, formContent: String = "0 0 60 40 re f",
                 formBox: String = "[0 0 60 40]", formMatrix: String = "[1 0 0 1 0 0]",
                 mediaBox: String = "[0 0 612 792]") -> Data {
    func stream(_ s: String, extra: String = "") -> String {
        "<< /Length \(s.utf8.count) \(extra) >>\nstream\n\(s)\nendstream"
    }
    let image = "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray"
        + " /BitsPerComponent 8 /Length 1 >>\nstream\n\u{00}\nendstream"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox \(mediaBox) /Resources << /XObject << /Im 5 0 R /Fm 6 0 R >> >> /Contents 4 0 R >>",
        stream(content),
        image,
        stream(formContent, extra: "/Type /XObject /Subtype /Form /BBox \(formBox) /Matrix \(formMatrix)"),
    ]
    var bytes = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (i, object) in objects.enumerated() {
        offsets.append(bytes.count)
        bytes.append(Data("\(i + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = bytes.count
    bytes.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() { bytes.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    bytes.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return bytes
}

/// The first page of an `operatorPDF`, as Core Graphics reads it.
func operatorPage(_ content: String, formContent: String = "0 0 60 40 re f",
                  formBox: String = "[0 0 60 40]", formMatrix: String = "[1 0 0 1 0 0]",
                  mediaBox: String = "[0 0 612 792]") throws -> CGPDFPage {
    let data = operatorPDF(content, formContent: formContent, formBox: formBox,
                           formMatrix: formMatrix, mediaBox: mediaBox)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    return try #require(document.page(at: 1))
}
