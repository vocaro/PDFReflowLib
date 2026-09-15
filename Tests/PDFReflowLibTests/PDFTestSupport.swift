import Foundation

// Original in-memory fixtures exercise PDF operators without a corpus download.
func testPDFStream(_ content: String, extra: String = "") -> String {
    "<< /Length \(content.utf8.count) \(extra) >>\nstream\n\(content)\nendstream"
}

func testPDF(objects: [String]) -> Data {
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
    data.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
}

func testPDFDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-regression-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
