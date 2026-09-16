import Foundation
import PDFKit
import CoreText
import AppKit

// Scratch measurement tool: dump PDFKit text, per-run font names and CG font-dictionary
// evidence for every page. usage: dump-pages <pdf> <output.json> [firstPage lastPage]
struct FontInfo: Codable {
    var resourceName: String
    var baseFont: String
    var subtype: String
    var encoding: String          // name, "dict", or ""
    var baseEncoding: String
    var differencesCount: Int
    var differencesSample: [String]
    var hasToUnicode: Bool
    var fontFile: String          // FontFile/FontFile2/FontFile3:<Subtype>/none
    var descendantHasToUnicode: Bool
}

func name(_ d: CGPDFDictionaryRef, _ key: String) -> String? {
    var p: UnsafePointer<Int8>? = nil
    guard CGPDFDictionaryGetName(d, key, &p), let p else { return nil }
    return String(cString: p)
}

func fontInfo(_ font: CGPDFDictionaryRef, resourceName: String) -> FontInfo {
    var info = FontInfo(resourceName: resourceName, baseFont: name(font, "BaseFont") ?? "", subtype: name(font, "Subtype") ?? "",
        encoding: "", baseEncoding: "", differencesCount: 0, differencesSample: [], hasToUnicode: false, fontFile: "none",
        descendantHasToUnicode: false)
    if let enc = name(font, "Encoding") { info.encoding = enc }
    var encDict: CGPDFDictionaryRef? = nil
    if CGPDFDictionaryGetDictionary(font, "Encoding", &encDict), let encDict {
        info.encoding = "dict"
        info.baseEncoding = name(encDict, "BaseEncoding") ?? ""
        var diffs: CGPDFArrayRef? = nil
        if CGPDFDictionaryGetArray(encDict, "Differences", &diffs), let diffs {
            let n = CGPDFArrayGetCount(diffs)
            var names: [String] = []
            for i in 0..<n {
                var p: UnsafePointer<Int8>? = nil
                if CGPDFArrayGetName(diffs, i, &p), let p { names.append(String(cString: p)) }
            }
            info.differencesCount = names.count
            info.differencesSample = Array(names.prefix(12))
        }
    }
    var stream: CGPDFStreamRef? = nil
    info.hasToUnicode = CGPDFDictionaryGetStream(font, "ToUnicode", &stream)
    var desc: CGPDFDictionaryRef? = nil
    if CGPDFDictionaryGetDictionary(font, "FontDescriptor", &desc), let desc {
        var s: CGPDFStreamRef? = nil
        if CGPDFDictionaryGetStream(desc, "FontFile", &s) { info.fontFile = "FontFile" }
        else if CGPDFDictionaryGetStream(desc, "FontFile2", &s) { info.fontFile = "FontFile2" }
        else if CGPDFDictionaryGetStream(desc, "FontFile3", &s), let s, let sd = CGPDFStreamGetDictionary(s) {
            info.fontFile = "FontFile3:" + (name(sd, "Subtype") ?? "?")
        }
    }
    var descendants: CGPDFArrayRef? = nil
    if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants, CGPDFArrayGetCount(descendants) > 0 {
        var d: CGPDFDictionaryRef? = nil
        if CGPDFArrayGetDictionary(descendants, 0, &d), let d {
            var s: CGPDFStreamRef? = nil
            info.descendantHasToUnicode = CGPDFDictionaryGetStream(d, "ToUnicode", &s)
            var dd: CGPDFDictionaryRef? = nil
            if CGPDFDictionaryGetDictionary(d, "FontDescriptor", &dd), let dd {
                var ss: CGPDFStreamRef? = nil
                if CGPDFDictionaryGetStream(dd, "FontFile", &ss) { info.fontFile = "FontFile" }
                else if CGPDFDictionaryGetStream(dd, "FontFile2", &ss) { info.fontFile = "FontFile2" }
                else if CGPDFDictionaryGetStream(dd, "FontFile3", &ss), let ss, let sd = CGPDFStreamGetDictionary(ss) {
                    info.fontFile = "FontFile3:" + (name(sd, "Subtype") ?? "?")
                }
            }
        }
    }
    return info
}

func collectFonts(_ resources: CGPDFDictionaryRef, depth: Int, into out: inout [FontInfo], seen: inout Set<String>) {
    var fonts: CGPDFDictionaryRef? = nil
    if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
        CGPDFDictionaryApplyBlock(fonts, { key, value, _ in
            var d: CGPDFDictionaryRef? = nil
            if CGPDFObjectGetValue(value, .dictionary, &d), let d {
                let info = fontInfo(d, resourceName: String(cString: key))
                let id = info.baseFont + "|" + info.subtype + "|" + info.resourceName
                if !seen.contains(id) { seen.insert(id); out.append(info) }
            }
            return true
        }, nil)
    }
    guard depth < 4 else { return }
    var xobjects: CGPDFDictionaryRef? = nil
    if CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects {
        CGPDFDictionaryApplyBlock(xobjects, { _, value, _ in
            var s: CGPDFStreamRef? = nil
            if CGPDFObjectGetValue(value, .stream, &s), let s, let sd = CGPDFStreamGetDictionary(s),
               name(sd, "Subtype") == "Form" {
                var res: CGPDFDictionaryRef? = nil
                if CGPDFDictionaryGetDictionary(sd, "Resources", &res), let res {
                    collectFonts(res, depth: depth + 1, into: &out, seen: &seen)
                }
            }
            return true
        }, nil)
    }
}

struct RunInfo: Codable { var text: String; var font: String }
struct LineInfo: Codable { var text: String; var runs: [RunInfo] }
struct PageInfo: Codable { var number: Int; var text: String; var lines: [LineInfo]; var fonts: [FontInfo]; var graphicsCount: Int; var pageArea: Double; var largestGraphicFraction: Double }
struct DocInfo: Codable { var file: String; var pages: [PageInfo] }

@main struct DumpPages {
static func main() throws {
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
guard let doc = PDFDocument(url: url) else { fatalError("cannot open") }
let first = args.count > 4 ? Int(args[3])! : 1
let last = args.count > 4 ? Int(args[4])! : doc.pageCount
var pages: [PageInfo] = []
for i in (first - 1)..<last {
    autoreleasepool {
        guard let page = doc.page(at: i), let ref = page.pageRef else { return }
        var fonts: [FontInfo] = []; var seen: Set<String> = []
        if let dict = ref.dictionary {
            var res: CGPDFDictionaryRef? = nil
            if CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res { collectFonts(res, depth: 0, into: &fonts, seen: &seen) }
        }
        var lines: [LineInfo] = []
        for sel in page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [] {
            guard let raw = sel.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var runs: [RunInfo] = []
            if let a = sel.attributedString {
                a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { attrs, range, _ in
                    let f = attrs[.font] as? NSFont
                    runs.append(RunInfo(text: (a.string as NSString).substring(with: range), font: f?.fontName ?? ""))
                }
            }
            lines.append(LineInfo(text: raw, runs: runs))
        }
        let bounds = page.bounds(for: .cropBox)
        let graphics = GraphicsReader.read(ref)
        let largest = graphics.regions.map { $0.width * $0.height / (bounds.width * bounds.height) }.max() ?? 0
        pages.append(PageInfo(number: i + 1, text: page.string ?? "", lines: lines, fonts: fonts, graphicsCount: graphics.regions.count,
            pageArea: Double(bounds.width * bounds.height), largestGraphicFraction: Double(largest)))
    }
}
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try enc.encode(DocInfo(file: url.lastPathComponent, pages: pages)).write(to: URL(fileURLWithPath: args[2]))
print("wrote \(pages.count) pages")
}
}
