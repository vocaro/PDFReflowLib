import CoreGraphics
import Foundation

// Structure roles behind the book-wide `structureFallback` warning (#124): every structure element's
// role (after RoleMap), counted by whether `StructureTreeReader` accepts it where it stands. The
// reader accepts containers (Document, Part, Art, Sect, Div) outside paragraph groups, P and H1–H6
// as groups, and Span/Link inside a group; anything else, a heading or paragraph nested in a
// group, an OBJR or a form-stream MCR sets the document's `rejected` flag.
//
// usage: role-survey <pdf>

guard CommandLine.arguments.count == 2,
      let document = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL),
      let catalog = document.catalog else { fatalError("usage: role-survey <pdf>") }
func dictionary(_ d: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
    var value: CGPDFDictionaryRef?; return CGPDFDictionaryGetDictionary(d, key, &value) ? value : nil
}
func name(_ d: CGPDFDictionaryRef, _ key: String) -> String? {
    var value: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(d, key, &value), let value else { return nil }
    return String(cString: value)
}
guard let root = dictionary(catalog, "StructTreeRoot") else { print("no structure tree"); exit(0) }
let standard: Set<String> = ["Document", "Part", "Art", "Sect", "Div", "P", "H", "H1", "H2", "H3", "H4", "H5", "H6", "Span", "Link", "BlockQuote", "Caption", "TOC", "TOCI", "Index", "NonStruct", "Private", "L", "LI", "Lbl", "LBody", "Table", "TR", "TH", "TD", "THead", "TBody", "TFoot", "Quote", "Note", "Reference", "BibEntry", "Code", "Annot", "Ruby", "RB", "RT", "RP", "Warichu", "WT", "WP", "Figure", "Formula", "Form"]
func role(_ d: CGPDFDictionaryRef) -> String {
    var role = name(d, "S") ?? "?"
    var visited: Set<String> = []
    while !standard.contains(role), let map = dictionary(root, "RoleMap"), let next = name(map, role), visited.insert(role).inserted {
        role = next
    }
    return role
}
var accepted: [String: Int] = [:], rejected: [String: Int] = [:]
var seen: Set<UInt> = []
let containers: Set<String> = ["Document", "Part", "Art", "Sect", "Div"]
func walk(_ value: CGPDFObjectRef, inGroup: Bool, allowed: Bool) {
    switch CGPDFObjectGetType(value) {
    case .array:
        var kids: CGPDFArrayRef?
        guard CGPDFObjectGetValue(value, .array, &kids), let kids else { return }
        for i in 0..<CGPDFArrayGetCount(kids) {
            var child: CGPDFObjectRef?
            if CGPDFArrayGetObject(kids, i, &child), let child { walk(child, inGroup: inGroup, allowed: allowed) }
        }
    case .dictionary:
        var d: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(value, .dictionary, &d), let d, seen.insert(UInt(bitPattern: d.rawValue)).inserted else { return }
        if let type = name(d, "Type"), type == "MCR" || type == "OBJR" {
            var stream: CGPDFObjectRef?
            if type == "OBJR" || CGPDFDictionaryGetObject(d, "Stm", &stream) { rejected[type, default: 0] += 1 }
            return
        }
        let r = role(d)
        let heading = r == "P" || ["H1", "H2", "H3", "H4", "H5", "H6"].contains(r)
        var group = inGroup, childAllowed = allowed
        if allowed && heading && !inGroup {
            accepted[r, default: 0] += 1; group = true
        } else if (!inGroup && containers.contains(r)) || (inGroup && (r == "Span" || r == "Link")) {
            accepted[r, default: 0] += 1
        } else {
            rejected[r, default: 0] += 1; group = false; childAllowed = false
        }
        var kids: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(d, "K", &kids), let kids { walk(kids, inGroup: group, allowed: childAllowed) }
    default: return
    }
}
var kids: CGPDFObjectRef?
if CGPDFDictionaryGetObject(root, "K", &kids), let kids { walk(kids, inGroup: false, allowed: true) }
func show(_ counts: [String: Int]) -> String { counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") }
print("accepted: \(show(accepted))")
print("rejected: \(show(rejected))")
