import Foundation
import PDFKit
import CoreGraphics

// Survey every annotation's raw dictionary: subtype, flags, border, appearance, field values.
func name(_ d: CGPDFDictionaryRef, _ k: String) -> String? {
    var p: UnsafePointer<CChar>? = nil
    return CGPDFDictionaryGetName(d, k, &p) ? String(cString: p!) : nil
}
func str(_ d: CGPDFDictionaryRef, _ k: String) -> String? {
    var s: CGPDFStringRef? = nil
    if CGPDFDictionaryGetString(d, k, &s), let s, let c = CGPDFStringCopyTextString(s) { return c as String }
    return name(d, k).map { "/" + $0 }
}
func int(_ d: CGPDFDictionaryRef, _ k: String) -> Int? {
    var i: CGPDFInteger = 0
    return CGPDFDictionaryGetInteger(d, k, &i) ? Int(i) : nil
}
func arr(_ d: CGPDFDictionaryRef, _ k: String) -> [Double]? {
    var a: CGPDFArrayRef? = nil
    guard CGPDFDictionaryGetArray(d, k, &a), let a else { return nil }
    var out: [Double] = []
    for i in 0..<CGPDFArrayGetCount(a) { var r: CGPDFReal = 0; if CGPDFArrayGetNumber(a, i, &r) { out.append(Double(r)) } }
    return out
}
func inherited(_ d: CGPDFDictionaryRef, _ k: String, _ f: (CGPDFDictionaryRef, String) -> String?) -> String? {
    var cur: CGPDFDictionaryRef? = d
    var n = 0
    while let c = cur, n < 20 {
        if let v = f(c, k) { return v }
        var p: CGPDFDictionaryRef? = nil
        cur = CGPDFDictionaryGetDictionary(c, "Parent", &p) ? p : nil
        n += 1
    }
    return nil
}
func apInfo(_ d: CGPDFDictionaryRef, state: String?) -> String {
    var ap: CGPDFDictionaryRef? = nil
    guard CGPDFDictionaryGetDictionary(d, "AP", &ap), let ap else { return "noAP" }
    var parts: [String] = []
    for key in ["N", "D", "R"] {
        var s: CGPDFStreamRef? = nil
        if CGPDFDictionaryGetStream(ap, key, &s), let s {
            var fmt = CGPDFDataFormat.raw
            let data = CGPDFStreamCopyData(s, &fmt) as Data?
            parts.append("\(key)=stream(\(data?.count ?? -1))")
            if key == "N", let data, data.count < 400 { parts.append("N:\(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "))") }
        } else {
            var sd: CGPDFDictionaryRef? = nil
            if CGPDFDictionaryGetDictionary(ap, key, &sd), let sd {
                var keys: [String] = []
                CGPDFDictionaryApplyBlock(sd, { k, obj, _ in
                    var st: CGPDFStreamRef? = nil
                    var len = -1
                    if CGPDFObjectGetValue(obj, .stream, &st), let st {
                        var fmt = CGPDFDataFormat.raw
                        len = (CGPDFStreamCopyData(st, &fmt) as Data?)?.count ?? -1
                    }
                    keys.append("\(String(cString: k)):\(len)"); return true }, nil)
                parts.append("\(key)={\(keys.joined(separator: ","))}")
            }
        }
    }
    return parts.joined(separator: " ")
}

let path = CommandLine.arguments[1]
let verbose = CommandLine.arguments.count > 2
guard let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL) else { print("unreadable"); exit(1) }
var summary: [String: Int] = [:]
var pagesWith = 0
for pn in 1...doc.numberOfPages {
    guard let page = doc.page(at: pn), let pd = page.dictionary else { continue }
    var annots: CGPDFArrayRef? = nil
    guard CGPDFDictionaryGetArray(pd, "Annots", &annots), let annots, CGPDFArrayGetCount(annots) > 0 else { continue }
    pagesWith += 1
    var line: [String: Int] = [:]
    for i in 0..<CGPDFArrayGetCount(annots) {
        var a: CGPDFDictionaryRef? = nil
        guard CGPDFArrayGetDictionary(annots, i, &a), let a else { continue }
        let sub = name(a, "Subtype") ?? "?"
        let flags = int(a, "F") ?? 0
        var bsW: String = "-"
        var bs: CGPDFDictionaryRef? = nil
        if CGPDFDictionaryGetDictionary(a, "BS", &bs), let bs { var r: CGPDFReal = 0; if CGPDFDictionaryGetNumber(bs, "W", &r) { bsW = "\(r)" } }
        let border = arr(a, "Border").map { "\($0)" } ?? "-"
        let ft = inherited(a, "FT", name) ?? ""
        let v = inherited(a, "V", str) ?? ""
        let asState = name(a, "AS")
        let ff = inherited(a, "Ff", { d, k in int(d, k).map(String.init) }) ?? ""
        var mk = ""
        var mkd: CGPDFDictionaryRef? = nil
        if CGPDFDictionaryGetDictionary(a, "MK", &mkd), let mkd { mk = "MK(bc=\(arr(mkd, "BC") ?? []),bg=\(arr(mkd, "BG") ?? []),ca=\(str(mkd, "CA") ?? ""))" }
        let key = "\(sub) \(ft) F=\(flags) BS.W=\(bsW) Border=\(border)"
        line[key, default: 0] += 1
        summary[sub + (ft.isEmpty ? "" : "/" + ft), default: 0] += 1
        if verbose {
            print("p\(pn) #\(i) \(sub) C=\(arr(a, "C") ?? [-1]) H=\(name(a, "H") ?? "") FT=\(ft) Ff=\(ff) F=\(flags) BS.W=\(bsW) Border=\(border) V=\(v.prefix(40)) AS=\(asState ?? "") \(mk) \(apInfo(a, state: asState)) Rect=\(arr(a, "Rect") ?? [])")
        }
    }
    if !verbose { print("p\(pn): " + line.map { "\($0.value)x[\($0.key)]" }.sorted().joined(separator: "; ")) }
}
print("pagesWithAnnots=\(pagesWith) of \(doc.numberOfPages); \(summary)")
