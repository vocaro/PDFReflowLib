// Captures Census report pages as a text-operator fixture for #143's tests.
//
//   swiftc -O -parse-as-library measurements/glyph-index-decoding/capture.swift -o <scratch>/capture
//   <scratch>/capture corpus/cache/rrs2002-01.pdf 3 12 17 20 > Tests/PDFReflowLibTests/fixtures/census-text-operators.json
//
// For each page it writes the font resources (subtype, BaseFont, FirstChar, Widths and the
// `Differences` array as PDF syntax; no font programs, no ToUnicode exists), the ExtGState entries,
// the decoded content stream and PDFKit's native lines with their bounds. Type3 fonts are written
// as Type1 fonts with the same encoding: their glyph procedures are not copied. The content streams
// must hold ASCII only and no XObject; the tool refuses otherwise.
import Foundation
import PDFKit
import CryptoKit

struct Font: Encodable {
    var resourceName: String
    var subtype: String
    var baseFont: String?
    var firstChar: Int?
    var widths: [Double]?
    var differences: String
}
struct Line: Encodable { var text: String; var rect: [Double] }
struct Page: Encodable {
    var page: Int
    var fonts: [Font]
    var extGStates: [String: String]
    var operators: String
    var lines: [Line]
}
struct Fixture: Encodable {
    var source = "census-rrs2002-01 (corpus/cache/rrs2002-01.pdf), U.S. Census Bureau Research Report Series RRS2002/01"
    var sourceSHA256: String
    var pages: [Page]
}

func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
    var value: UnsafePointer<CChar>?
    return CGPDFDictionaryGetName(dict, key, &value) ? value.map { String(cString: $0) } : nil
}

func object(_ object: CGPDFObjectRef) -> String {
    var integer: CGPDFInteger = 0, real: CGPDFReal = 0, pointer: UnsafePointer<CChar>?, boolean: CGPDFBoolean = 0
    switch CGPDFObjectGetType(object) {
    case .integer: CGPDFObjectGetValue(object, .integer, &integer); return String(integer)
    case .real: CGPDFObjectGetValue(object, .real, &real); return String(format: "%g", real)
    case .name: CGPDFObjectGetValue(object, .name, &pointer); return "/" + String(cString: pointer!)
    case .boolean: CGPDFObjectGetValue(object, .boolean, &boolean); return boolean != 0 ? "true" : "false"
    default: fatalError("unsupported object in a captured dictionary")
    }
}

@main
struct Capture {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let numbers = CommandLine.arguments.dropFirst(2).compactMap { Int($0) }
        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(url: url), let cg = CGPDFDocument(url as CFURL) else { fatalError("unreadable") }
        var pages: [Page] = []
        for number in numbers {
            let pdfPage = document.page(at: number - 1)!
            let page = cg.page(at: number)!
            var resources: CGPDFDictionaryRef?, fontsDict: CGPDFDictionaryRef?, states: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "Font", &fontsDict), let fontsDict else { fatalError("no fonts") }
            var xobjects: CGPDFDictionaryRef?
            precondition(!CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), "page \(number) draws XObjects")
            var fonts: [Font] = []
            CGPDFDictionaryApplyBlock(fontsDict, { key, value, _ in
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(value, .dictionary, &dict), let dict else { return true }
                var font = Font(resourceName: String(cString: key), subtype: name(dict, "Subtype") ?? "", baseFont: name(dict, "BaseFont"),
                                differences: "")
                var first: CGPDFInteger = 0, widths: CGPDFArrayRef?, encoding: CGPDFDictionaryRef?, differences: CGPDFArrayRef?
                if CGPDFDictionaryGetInteger(dict, "FirstChar", &first) { font.firstChar = first }
                if CGPDFDictionaryGetArray(dict, "Widths", &widths), let widths {
                    font.widths = (0..<CGPDFArrayGetCount(widths)).map { index in
                        var value: CGPDFReal = 0
                        CGPDFArrayGetNumber(widths, index, &value)
                        return Double(value)
                    }
                }
                if CGPDFDictionaryGetDictionary(dict, "Encoding", &encoding), let encoding,
                   CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences {
                    font.differences = "[" + (0..<CGPDFArrayGetCount(differences)).map { index -> String in
                        var item: CGPDFObjectRef?
                        CGPDFArrayGetObject(differences, index, &item)
                        return object(item!)
                    }.joined(separator: " ") + "]"
                }
                var stream: CGPDFStreamRef?
                precondition(!CGPDFDictionaryGetStream(dict, "ToUnicode", &stream), "a ToUnicode map")
                fonts.append(font)
                return true
            }, nil)
            var extGStates: [String: String] = [:]
            if CGPDFDictionaryGetDictionary(resources, "ExtGState", &states), let states {
                CGPDFDictionaryApplyBlock(states, { key, value, _ in
                    var dict: CGPDFDictionaryRef?
                    guard CGPDFObjectGetValue(value, .dictionary, &dict), let dict else { return true }
                    var entries: [String] = []
                    CGPDFDictionaryApplyBlock(dict, { entry, item, _ in
                        entries.append("/\(String(cString: entry)) \(object(item))"); return true
                    }, nil)
                    extGStates[String(cString: key)] = "<< " + entries.sorted().joined(separator: " ") + " >>"
                    return true
                }, nil)
            }
            // A Contents array is written as its streams joined by line breaks.
            var contents: CGPDFStreamRef?, parts: CGPDFArrayRef?, streams: [CGPDFStreamRef] = []
            if CGPDFDictionaryGetStream(page.dictionary!, "Contents", &contents), let contents {
                streams = [contents]
            } else if CGPDFDictionaryGetArray(page.dictionary!, "Contents", &parts), let parts {
                streams = (0..<CGPDFArrayGetCount(parts)).compactMap { index in
                    var stream: CGPDFStreamRef?
                    return CGPDFArrayGetStream(parts, index, &stream) ? stream : nil
                }
            }
            var bytes = Data()
            for stream in streams {
                var format = CGPDFDataFormat.raw
                guard let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw else { fatalError("contents") }
                if !bytes.isEmpty { bytes.append(0x0A) }
                bytes.append(data)
            }
            precondition(!bytes.isEmpty, "contents")
            precondition(bytes.allSatisfy { $0 < 128 }, "non-ASCII content")
            let selection = pdfPage.selection(for: pdfPage.bounds(for: .cropBox))!
            let lines = selection.selectionsByLine().compactMap { line -> Line? in
                guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let rect = line.bounds(for: pdfPage)
                return Line(text: text, rect: [rect.minX, rect.minY, rect.width, rect.height].map { (Double($0) * 10_000).rounded() / 10_000 })
            }
            pages.append(Page(page: number, fonts: fonts.sorted { $0.resourceName < $1.resourceName }, extGStates: extGStates,
                              operators: String(decoding: bytes, as: UTF8.self), lines: lines))
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(Fixture(sourceSHA256: digest, pages: pages)))
    }
}
