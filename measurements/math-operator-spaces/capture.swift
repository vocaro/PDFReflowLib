// Captures source pages as a text-operator fixture for #188's tests.
//
//   swiftc -O -parse-as-library measurements/math-operator-spaces/capture.swift -o <scratch>/capture
//   <scratch>/capture wallace-algebra-2010 corpus/cache/Beginning_and_Intermediate_Algebra.pdf 7 8 \
//     > Tests/PDFReflowLibTests/fixtures/algebra-7-8-text-operators.json
//   <scratch>/capture arxiv-replay-clocks-2023 corpus/cache/2311.07842v1.pdf 7 \
//     > Tests/PDFReflowLibTests/fixtures/replay-7-text-operators.json
//
// For each page it writes the font resources (Subtype, BaseFont, FirstChar, Widths, the decoded
// ToUnicode stream, and `/Encoding` as a name or as a dictionary of its BaseEncoding and
// Differences), the ExtGState entries, the decoded content stream and PDFKit's native lines with
// their bounds. Font programs are not copied. In the content stream, bytes outside printable ASCII
// inside string literals are written as octal escapes (Ghostscript's CMSY minus is code 0), and each
// XObject draw (`/Name Do`, Replay's plots) is removed: the spacing reader treats both an image and
// a form as opaque. The tool refuses a font it cannot describe and any other non-ASCII byte.
import CryptoKit
import Foundation
import PDFKit

struct Font: Encodable {
    var resourceName: String
    var subtype: String
    var baseFont: String?
    var firstChar: Int?
    var widths: [Double]?
    var toUnicode: String?
    var encoding: String?
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
    var caseID: String
    var sourceTitle: String
    var sourceURL: String
    var rightsBasis: String
    var provenance: String
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

/// The content stream as ASCII: string-literal bytes outside 0x20–0x7E as octal escapes, and
/// every `/Name Do` removed.
func ascii(_ bytes: Data) -> String {
    var out = "", depth = 0, escaped = false
    for byte in bytes {
        if depth > 0 {
            if escaped { escaped = false; out.append(Character(UnicodeScalar(byte))); continue }
            switch byte {
            case 0x5C: escaped = true; out += "\\"
            case 0x28: depth += 1; out += "("
            case 0x29: depth -= 1; out += ")"
            case 0x20...0x7E: out.append(Character(UnicodeScalar(byte)))
            default: out += String(format: "\\%03o", byte)
            }
            continue
        }
        precondition(byte < 0x80, "non-ASCII byte outside a string")
        if byte == 0x28 { depth = 1 }
        out.append(Character(UnicodeScalar(byte)))
    }
    return out.replacingOccurrences(of: #"/[^\s/\[\]()<>{}%]+\s+Do\b"#, with: "", options: .regularExpression)
}

@main
struct Capture {
    static func main() throws {
        let caseID = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let numbers = CommandLine.arguments.dropFirst(3).compactMap { Int($0) }
        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(url: url), let cg = CGPDFDocument(url as CFURL) else { fatalError("unreadable") }
        var pages: [Page] = []
        for number in numbers {
            let pdfPage = document.page(at: number - 1)!
            let page = cg.page(at: number)!
            var resources: CGPDFDictionaryRef?, fontsDict: CGPDFDictionaryRef?, states: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "Font", &fontsDict), let fontsDict else { fatalError("no fonts") }
            var fonts: [Font] = []
            CGPDFDictionaryApplyBlock(fontsDict, { key, value, _ in
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(value, .dictionary, &dict), let dict else { return true }
                var font = Font(resourceName: String(cString: key), subtype: name(dict, "Subtype") ?? "", baseFont: name(dict, "BaseFont"))
                var first: CGPDFInteger = 0, widths: CGPDFArrayRef?, encoding: CGPDFDictionaryRef?, differences: CGPDFArrayRef?
                if CGPDFDictionaryGetInteger(dict, "FirstChar", &first) { font.firstChar = first }
                if CGPDFDictionaryGetArray(dict, "Widths", &widths), let widths {
                    font.widths = (0..<CGPDFArrayGetCount(widths)).map { index in
                        var value: CGPDFReal = 0
                        CGPDFArrayGetNumber(widths, index, &value)
                        return Double(value)
                    }
                }
                if let named = name(dict, "Encoding") {
                    font.encoding = "/" + named
                } else if CGPDFDictionaryGetDictionary(dict, "Encoding", &encoding), let encoding {
                    var parts = ["/Type /Encoding"]
                    if let base = name(encoding, "BaseEncoding") { parts.append("/BaseEncoding /" + base) }
                    if CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences {
                        parts.append("/Differences [" + (0..<CGPDFArrayGetCount(differences)).map { index -> String in
                            var item: CGPDFObjectRef?
                            CGPDFArrayGetObject(differences, index, &item)
                            return object(item!)
                        }.joined(separator: " ") + "]")
                    }
                    font.encoding = "<< " + parts.joined(separator: " ") + " >>"
                }
                var stream: CGPDFStreamRef?, format = CGPDFDataFormat.raw
                if CGPDFDictionaryGetStream(dict, "ToUnicode", &stream), let stream {
                    guard let map = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw,
                          let text = String(data: map, encoding: .ascii) else { fatalError("ToUnicode") }
                    font.toUnicode = text
                }
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
            let selection = pdfPage.selection(for: pdfPage.bounds(for: .cropBox))!
            let lines = selection.selectionsByLine().compactMap { line -> Line? in
                guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let rect = line.bounds(for: pdfPage)
                return Line(text: text, rect: [rect.minX, rect.minY, rect.width, rect.height].map { (Double($0) * 10_000).rounded() / 10_000 })
            }
            pages.append(Page(page: number, fonts: fonts.sorted { $0.resourceName < $1.resourceName }, extGStates: extGStates,
                              operators: ascii(bytes), lines: lines))
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sources: [String: (String, String, String)] = [
            "wallace-algebra-2010": ("Beginning and Intermediate Algebra", "http://wallace.ccfaculty.org/book/book.html",
                                     "Page 2 states Copyright 2010 Tyler Wallace and Creative Commons Attribution 3.0 Unported. The PDF remains an external local corpus source; it is not bundled or relicensed under MIT."),
            "arxiv-replay-clocks-2023": ("Replay Clocks", "https://arxiv.org/abs/2311.07842v1",
                                         "Replay Clocks by Ishaan Lagwankar and Sandeep S Kulkarni, arXiv:2311.07842v1 (2023), CC BY 4.0; development corpus only, not relicensed under MIT."),
        ]
        guard let (title, source, rights) = sources[caseID] else { fatalError("unknown case") }
        let provenance = "Unmodified page font dictionaries (Subtype, BaseFont, FirstChar, Widths, decoded ToUnicode streams, "
            + "Encoding names or BaseEncoding and Differences), ExtGState entries and the complete decoded page content streams, "
            + "read with CoreGraphics from the checksum-pinned original by measurements/math-operator-spaces/capture.swift. "
            + "String bytes outside printable ASCII are octal escapes and XObject draws are removed; font programs are excluded. "
            + "Native lines are PDFKit selectionsByLine strings and bounds on macOS 27.0."
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(Fixture(caseID: caseID, sourceTitle: title, sourceURL: source, rightsBasis: rights,
                                                                   provenance: provenance, sourceSHA256: digest, pages: pages)))
    }
}
