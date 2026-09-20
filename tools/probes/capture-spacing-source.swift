import Foundation
import CryptoKit
import CoreGraphics

// Run from the repository root. Captures one source page's text-placement evidence for the
// spacing tests: the page's own content stream and the font resources the spacing reader reads
// from it (subtype, font matrix, widths, encoding, `ToUnicode`), plus the names of the other
// resources the stream mentions, so a test can rebuild a page that places text exactly as the
// source does. No font program is captured: only the metadata a reader consults. This is source
// evidence, never converter output.

func capture() throws {
    guard CommandLine.arguments.count == 4, let pageNumber = Int(CommandLine.arguments[2]), pageNumber > 0 else {
        fatalError("usage: capture-spacing-source <corpus-case-id> <physical-page> <output.json>")
    }
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
    let cases = manifest["documents"] as! [[String: Any]]
    guard let item = cases.first(where: { $0["id"] as? String == CommandLine.arguments[1] }),
          let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
        fatalError("Unknown corpus case")
    }
    let source = URL(fileURLWithPath: "corpus/cache/" + file)
    let data = try Data(contentsOf: source)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == expected else { fatalError("Source identity mismatch") }
    guard let provider = CGDataProvider(url: source as CFURL), let document = CGPDFDocument(provider),
          let page = document.page(at: pageNumber) else { throw CocoaError(.fileReadCorruptFile) }

    let payload: [String: Any] = [
        "caseID": item["id"]!, "sourceSHA256": digest, "page": pageNumber,
        "sourceURL": item["downloadURL"] ?? item["url"] ?? "", "sourceTitle": item["title"]!,
        "rightsBasis": item["rightsBasis"] ?? "See corpus manifest and third-party notices.",
        "mediaBox": box(page, .mediaBox), "cropBox": box(page, .cropBox),
        "rotation": Int(page.rotationAngle),
        "content": latin1(contents(of: page)),
        "fonts": fonts(of: page), "extGStates": names(of: page, "ExtGState"), "xObjects": xObjects(of: page),
    ]
    try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
}

func box(_ page: CGPDFPage, _ which: CGPDFBox) -> [Double] {
    let rect = page.getBoxRect(which)
    return [rect.minX, rect.minY, rect.maxX, rect.maxY]
}

/// Every byte the page's content stream decodes to; an array of streams joins with newlines.
func contents(of page: CGPDFPage) -> Data {
    guard let dictionary = page.dictionary else { return Data() }
    var stream: CGPDFStreamRef?
    var format = CGPDFDataFormat.raw
    if CGPDFDictionaryGetStream(dictionary, "Contents", &stream), let stream,
       let data = CGPDFStreamCopyData(stream, &format) {
        return data as Data
    }
    var array: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(dictionary, "Contents", &array), let array else { return Data() }
    var result = Data()
    for index in 0..<CGPDFArrayGetCount(array) {
        var part: CGPDFStreamRef?
        guard CGPDFArrayGetStream(array, index, &part), let part,
              let data = CGPDFStreamCopyData(part, &format) else { continue }
        result.append(data as Data)
        result.append(0x0A)
    }
    return result
}

/// Bytes as one Latin-1 string, which JSON round-trips without losing any of them.
func latin1(_ data: Data) -> String {
    String(data: data, encoding: .isoLatin1) ?? ""
}

func resources(of page: CGPDFPage) -> CGPDFDictionaryRef? {
    var node = page.dictionary
    for _ in 0..<64 {
        guard let current = node else { return nil }
        var found: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(current, "Resources", &found) { return found }
        var parent: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(current, "Parent", &parent) else { return nil }
        node = parent
    }
    return nil
}

func names(of page: CGPDFPage, _ key: String) -> [String] {
    guard let resources = resources(of: page) else { return [] }
    var entries: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, key, &entries), let entries else { return [] }
    final class Box { var names: [String] = [] }
    let box = Box()
    CGPDFDictionaryApplyBlock(entries, { name, _, info in
        Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().names.append(String(cString: name))
        return true
    }, Unmanaged.passUnretained(box).toOpaque())
    return box.names.sorted()
}

func xObjects(of page: CGPDFPage) -> [String: String] {
    guard let resources = resources(of: page) else { return [:] }
    var entries: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "XObject", &entries), let entries else { return [:] }
    final class Box { var kinds: [String: String] = [:] }
    let box = Box()
    CGPDFDictionaryApplyBlock(entries, { name, object, info in
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream) else { return true }
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return true }
        Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().kinds[String(cString: name)] = String(cString: subtype)
        return true
    }, Unmanaged.passUnretained(box).toOpaque())
    return box.kinds
}

func fonts(of page: CGPDFPage) -> [String: Any] {
    guard let resources = resources(of: page) else { return [:] }
    var entries: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "Font", &entries), let entries else { return [:] }
    final class Box { var fonts: [String: Any] = [:] }
    let box = Box()
    CGPDFDictionaryApplyBlock(entries, { name, object, info in
        var dictionary: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return true }
        Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().fonts[String(cString: name)] = font(dictionary)
        return true
    }, Unmanaged.passUnretained(box).toOpaque())
    return box.fonts
}

func font(_ dictionary: CGPDFDictionaryRef) -> [String: Any] {
    var result: [String: Any] = [:]
    var subtype: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype {
        result["subtype"] = String(cString: subtype)
    }
    var baseFont: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(dictionary, "BaseFont", &baseFont), let baseFont {
        result["baseFont"] = String(cString: baseFont)
    }
    var matrix: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(dictionary, "FontMatrix", &matrix), let matrix {
        result["fontMatrix"] = numbers(matrix)
    }
    var first: CGPDFInteger = 0
    if CGPDFDictionaryGetInteger(dictionary, "FirstChar", &first) { result["firstChar"] = first }
    var widths: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(dictionary, "Widths", &widths), let widths { result["widths"] = numbers(widths) }
    var encodingName: UnsafePointer<CChar>?
    var encoding: CGPDFDictionaryRef?
    if CGPDFDictionaryGetName(dictionary, "Encoding", &encodingName), let encodingName {
        result["encoding"] = String(cString: encodingName)
    } else if CGPDFDictionaryGetDictionary(dictionary, "Encoding", &encoding), let encoding {
        var value: [String: Any] = [:]
        var base: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(encoding, "BaseEncoding", &base), let base {
            value["baseEncoding"] = String(cString: base)
        }
        var differences: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences {
            var items: [Any] = []
            for index in 0..<CGPDFArrayGetCount(differences) {
                var code: CGPDFInteger = 0
                var glyph: UnsafePointer<CChar>?
                if CGPDFArrayGetInteger(differences, index, &code) { items.append(code) }
                else if CGPDFArrayGetName(differences, index, &glyph), let glyph { items.append("/" + String(cString: glyph)) }
            }
            value["differences"] = items
        }
        result["encoding"] = value
    }
    var stream: CGPDFStreamRef?
    var format = CGPDFDataFormat.raw
    if CGPDFDictionaryGetStream(dictionary, "ToUnicode", &stream), let stream,
       let data = CGPDFStreamCopyData(stream, &format), format == .raw {
        result["toUnicode"] = latin1(data as Data)
    }
    return result
}

func numbers(_ array: CGPDFArrayRef) -> [Double] {
    var result: [Double] = []
    for index in 0..<CGPDFArrayGetCount(array) {
        var value: CGPDFReal = 0
        result.append(CGPDFArrayGetNumber(array, index, &value) ? value : 0)
    }
    return result
}

try capture()
