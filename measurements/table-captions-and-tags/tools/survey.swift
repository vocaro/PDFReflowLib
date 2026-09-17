import Foundation
import PDFKit

// Survey of tagged tables: for every Table structure element, its rows (TR, possibly under
// THead/TBody/TFoot), cells (TH/TD) with ColSpan/RowSpan attributes, and the native lines
// each cell's marked content anchors to. Prints one JSON object per table.

struct Element {
    var role: String
    var page: Int?
    var mcids: [(page: Int, id: Int)] = []   // direct content only
    var children: [Int] = []                  // element indices
    var attributes: [String: Int] = [:]
    var parent: Int?
}

@main struct Survey {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: path)
        guard let document = CGPDFDocument(url as CFURL), let catalog = document.catalog,
              let root = StructureTreeReader.dictionary(catalog, "StructTreeRoot") else { print("{\"error\":\"no tree\"}"); return }
        var pages: [UInt: Int] = [:]
        for i in 1...document.numberOfPages { pages[UInt(bitPattern: document.page(at: i)!.dictionary!.rawValue)] = i }
        let roleMap = StructureTreeReader.dictionary(root, "RoleMap")
        let standard: Set<String> = ["Document", "Part", "Art", "Sect", "Div", "P", "H", "H1", "H2", "H3", "H4", "H5", "H6", "Span", "Link", "BlockQuote", "Caption", "TOC", "TOCI", "Index", "NonStruct", "Private", "L", "LI", "Lbl", "LBody", "Table", "TR", "TH", "TD", "THead", "TBody", "TFoot", "Quote", "Note", "Reference", "BibEntry", "Code", "Annot", "Ruby", "RB", "RT", "RP", "Warichu", "WT", "WP", "Figure", "Formula", "Form"]
        func mapped(_ r: String) -> String {
            var role = r; var n = 0
            while !standard.contains(role), let map = roleMap, let next = StructureTreeReader.name(map, role), n < 16 { role = next; n += 1 }
            return role
        }
        var elements: [Element] = []
        var seen: Set<UInt> = []
        func attributes(_ dict: CGPDFDictionaryRef) -> [String: Int] {
            var result: [String: Int] = [:]
            func read(_ a: CGPDFDictionaryRef) {
                for key in ["ColSpan", "RowSpan"] { if let v = StructureTreeReader.integer(a, key) { result[key] = v } }
                if let scope = StructureTreeReader.name(a, "Scope") { result["Scope:" + scope] = 1 }
            }
            guard let object = StructureTreeReader.object(dict, "A") else { return result }
            var d: CGPDFDictionaryRef?, arr: CGPDFArrayRef?
            if CGPDFObjectGetValue(object, .dictionary, &d), let d { read(d) }
            else if CGPDFObjectGetValue(object, .array, &arr), let arr {
                for i in 0..<CGPDFArrayGetCount(arr) { var x: CGPDFDictionaryRef?; if CGPDFArrayGetDictionary(arr, i, &x), let x { read(x) } }
            }
            return result
        }
        func walk(_ value: CGPDFObjectRef, owner: Int?, page: Int?, depth: Int) {
            guard depth < 100 else { return }
            switch CGPDFObjectGetType(value) {
            case .integer:
                var id: CGPDFInteger = 0
                if CGPDFObjectGetValue(value, .integer, &id), let owner, let page { elements[owner].mcids.append((page, id)) }
            case .array:
                var kids: CGPDFArrayRef?
                guard CGPDFObjectGetValue(value, .array, &kids), let kids else { return }
                for i in 0..<CGPDFArrayGetCount(kids) {
                    var child: CGPDFObjectRef?
                    if CGPDFArrayGetObject(kids, i, &child), let child { walk(child, owner: owner, page: page, depth: depth + 1) }
                }
            case .dictionary:
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(value, .dictionary, &dict), let dict, seen.insert(UInt(bitPattern: dict.rawValue)).inserted else { return }
                var local = page
                if let pg = StructureTreeReader.dictionary(dict, "Pg") { local = pages[UInt(bitPattern: pg.rawValue)] }
                if StructureTreeReader.name(dict, "Type") == "MCR" {
                    if let id = StructureTreeReader.integer(dict, "MCID"), let owner, let local { elements[owner].mcids.append((local, id)) }
                    return
                }
                if StructureTreeReader.name(dict, "Type") == "OBJR" { return }
                guard let s = StructureTreeReader.name(dict, "S") else { return }
                let index = elements.count
                elements.append(Element(role: mapped(s), page: local, attributes: attributes(dict), parent: owner))
                if let owner { elements[owner].children.append(index) }
                if let kids = StructureTreeReader.object(dict, "K") { walk(kids, owner: index, page: local, depth: depth + 1) }
            default: break
            }
        }
        if let kids = StructureTreeReader.object(root, "K") { walk(kids, owner: nil, page: nil, depth: 0) }

        func allMCIDs(_ i: Int) -> [(page: Int, id: Int)] { elements[i].mcids + elements[i].children.flatMap(allMCIDs) }
        func descendants(_ i: Int, role: Set<String>, through: Set<String>) -> [Int] {
            elements[i].children.flatMap { c -> [Int] in
                if role.contains(elements[c].role) { return [c] }
                if through.contains(elements[c].role) { return descendants(c, role: role, through: through) }
                return []
            }
        }
        // Lines and anchors per page, computed lazily.
        guard let pdf = PDFDocument(url: url) else { return }
        var pageLines: [Int: [TextLine]] = [:]
        var anchorsByID: [Int: [Int: [Int]]] = [:]     // page -> mcid -> line indices
        var unplaced: [Int: [Int: Int]] = [:]          // page -> mcid -> anchors with no single line
        var unknown: [Int: Set<Int>] = [:]
        var invalid: [Int: Bool] = [:]
        func load(_ number: Int) {
            guard pageLines[number] == nil, let page = pdf.page(at: number - 1), let ref = page.pageRef else { return }
            let graphics = GraphicsReader.read(ref)
            var lines = (try? NativeTextReader.lines(on: page, limit: 1_000_000, columnJoints: GraphicsReader.columnJoints(graphics.paints.map(\.rect)))) ?? []
            _ = MarkedAnchors.apply([:], page: ref, lines: &lines)
            pageLines[number] = lines
            unknown[number] = MarkedAnchors.lastUnknown
            invalid[number] = MarkedAnchors.lastInvalid
            for (point, id) in MarkedAnchors.lastAnchors {
                guard let id else { continue }
                var candidates = lines.indices.filter { lines[$0].rect.insetBy(dx: -0.75, dy: -0.75).contains(point) }
                if candidates.count > 1 {
                    let starting = candidates.filter { abs(lines[$0].rect.minX - point.x) <= 0.75 }
                    if starting.count == 1 { candidates = starting }
                }
                if candidates.count == 1 { anchorsByID[number, default: [:]][id, default: []].append(candidates[0]) }
                else { unplaced[number, default: [:]][id, default: 0] += 1 }
            }
        }
        func r(_ rect: CGRect) -> [Int] { [Int(rect.minX.rounded()), Int(rect.minY.rounded()), Int(rect.maxX.rounded()), Int(rect.maxY.rounded())] }
        var output: [[String: Any]] = []
        for (t, table) in elements.enumerated() where table.role == "Table" {
            let ids = allMCIDs(t)
            let tablePages = Array(Set(ids.map(\.page))).sorted()
            tablePages.forEach(load)
            // Every line owned by some cell: shared lines are those owned by more than one cell.
            let rows = descendants(t, role: ["TR"], through: ["THead", "TBody", "TFoot"])
            var owner: [String: Set<Int>] = [:]
            var cellsOut: [[[String: Any]]] = []
            var cellIndex = 0
            for row in rows {
                var rowOut: [[String: Any]] = []
                for cell in elements[row].children {
                    cellIndex += 1
                    let mc = allMCIDs(cell)
                    var lineKeys: [(Int, Int)] = []
                    var unplacedCount = 0, unknownCount = 0
                    for (page, id) in mc {
                        for l in anchorsByID[page]?[id] ?? [] where !lineKeys.contains(where: { $0 == (page, l) }) { lineKeys.append((page, l)) }
                        unplacedCount += unplaced[page]?[id] ?? 0
                        if unknown[page]?.contains(id) == true { unknownCount += 1 }
                    }
                    for (page, l) in lineKeys { owner["\(page):\(l)", default: []].insert(cellIndex) }
                    let lines = lineKeys.map { pageLines[$0.0]![$0.1] }
                    let bounds = lines.map(\.rect).reduce(CGRect.null) { $0.union($1) }
                    var entry: [String: Any] = ["role": elements[cell].role, "mcids": mc.count, "lines": lines.map(\.text),
                        "id": cellIndex, "unplaced": unplacedCount, "unknownOrigin": unknownCount]
                    if !bounds.isNull { entry["bbox"] = r(bounds) }
                    if !elements[cell].attributes.isEmpty { entry["attrs"] = elements[cell].attributes }
                    let kidRoles = elements[cell].children.map { elements[$0].role }
                    if !kidRoles.isEmpty { entry["kids"] = kidRoles }
                    rowOut.append(entry)
                }
                cellsOut.append(rowOut)
            }
            let shared = owner.filter { $0.value.count > 1 }.map { key, cells -> String in
                let parts = key.split(separator: ":").map { Int($0)! }
                return "\(pageLines[parts[0]]![parts[1]].text) <- cells \(cells.sorted())"
            }.sorted()
            let parent = table.parent.map { elements[$0].role } ?? "root"
            let siblings: [String] = table.parent.map { parentIndex -> [String] in
                let kids = elements[parentIndex].children
                let at = kids.firstIndex(of: t) ?? 0
                return kids[max(0, at - 3)...min(kids.count - 1, at + 2)].map { k -> String in
                    let text = allMCIDs(k).flatMap { m -> [String] in tablePages.contains(m.page) ? (anchorsByID[m.page]?[m.id] ?? []).map { pageLines[m.page]![$0].text } : [] }
                    var unique: [String] = []; for x in text where !unique.contains(x) { unique.append(x) }
                    return (k == t ? "*TABLE* " : "") + elements[k].role + ": " + String(unique.joined(separator: " / ").prefix(90))
                }
            } ?? []
            let captions = descendants(t, role: ["Caption"], through: []).map { c -> String in
                allMCIDs(c).flatMap { m in (anchorsByID[m.page]?[m.id] ?? []).map { pageLines[m.page]![$0].text } }.joined(separator: " | ")
            }
            var others = elements[t].children.map { elements[$0].role }.filter { !["TR", "THead", "TBody", "TFoot"].contains($0) }
            if others.isEmpty { others = [] }
            output.append(["tableElement": t, "pages": tablePages, "parent": parent, "parentChildren": siblings,
                           "otherChildren": others, "captions": captions, "rows": cellsOut, "sharedLines": shared,
                           "invalidPages": tablePages.filter { invalid[$0] == true }, "directMCIDs": table.mcids.count])
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        FileHandle.standardOutput.write(data)
        print("")
        FileHandle.standardError.write("tables: \(output.count)\n".data(using: .utf8)!)
    }
}
