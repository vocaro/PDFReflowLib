import Foundation

// Original in-memory fixtures exercise PDF operators without a corpus download.
func testPDFStream(_ content: String, extra: String = "") -> String {
    "<< /Length \(content.utf8.count) \(extra) >>\nstream\n\(content)\nendstream"
}

/// A PDF of these objects, optionally carrying an information dictionary the trailer names.
/// `info` is the dictionary's body, written as one more object, e.g. `/Title (A Book)`.
func testPDF(objects: [String], info: String? = nil) -> Data {
    let objects = info.map { objects + ["<< \($0) >>"] } ?? objects
    var data = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (index, object) in objects.enumerated() {
        offsets.append(data.count)
        data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
        data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    let trailerInfo = info == nil ? "" : " /Info \(objects.count) 0 R"
    data.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R\(trailerInfo) >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
}

func testPDFDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-regression-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
