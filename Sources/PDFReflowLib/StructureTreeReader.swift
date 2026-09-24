import CoreGraphics
import Foundation

/// Value-only page/MCID associations. No PDF objects escape the parsing pool.
enum StructureTreeReader {
    struct Index {
        var pages: [Int: [Int: TextStructure]] = [:]
        /// A Figure with one page MCID and author supplied Alt text. Artwork association is
        /// checked separately against the page's marked image draw.
        var figures: [Int: [Int: String]] = [:]
        /// Direct TH MCIDs inside Table/TR, validated against the page ParentTree before use.
        var tableHeaders: [Int: Set<Int>] = [:]
        // Paths through root K (-1 means dictionary K; nonnegative means array index).
        var owners: [Int: [Int: [Int]]] = [:]
        var figureOwners: [Int: [Int: [Int]]] = [:]
        var tableHeaderOwners: [Int: [Int: [Int]]] = [:]
        var present = false
        var rejected = false
    }

    static func read(_ url: URL, password: ConversionOptions.Password? = nil) throws -> Index {
        try autoreleasepool {
            guard let document = SourceDocument.openCore(url, password: password), let catalog = document.catalog,
                  let root = CGPDFObjects.dictionary(catalog, "StructTreeRoot") else { return Index() }
            let reader = Reader(document: document, root: root)
            do { return try reader.read() }
            catch is CancellationError { throw CancellationError() }
            catch { return Index(present: true, rejected: true) }
        }
    }

    private enum Invalid: Error { case tree }
    private final class Reader {
        let document: CGPDFDocument
        let root: CGPDFDictionaryRef
        var pages: [UInt: Int] = [:]
        var parentKeys: [Int: Int] = [:]
        var neededParentKeys: Set<Int> = []
        var seen: Set<UInt> = []
        var references: Set<String> = []
        var rejectedGroups: Set<Int> = []
        var result = Index(present: true)
        var operations = 0
        var groupCounter = 0
        var order = 0

        init(document: CGPDFDocument, root: CGPDFDictionaryRef) {
            self.document = document; self.root = root
        }
        func step(_ depth: Int) throws {
            operations += 1
            guard depth < 64, operations <= 200_000 else { throw Invalid.tree }
            if operations % 256 == 0 { try Task.checkCancellation() }
        }
        func read() throws -> Index {
            try Task.checkCancellation()
            guard document.numberOfPages > 0 else { throw Invalid.tree }
            for i in 1...document.numberOfPages {
                try step(0)
                guard let page = document.page(at: i) else { throw Invalid.tree }
                guard let dict = page.dictionary else { throw Invalid.tree }
                pages[UInt(bitPattern: dict.rawValue)] = i
                if let key = CGPDFObjects.integer(dict, "StructParents") {
                    guard key >= 0, neededParentKeys.insert(key).inserted else { throw Invalid.tree }
                    parentKeys[i] = key
                }
            }
            if let kids = CGPDFObjects.object(root, "K") {
                try walk(kids, parent: root, page: nil, group: nil, allowed: true, inTable: false, inRow: false,
                         depth: 0, path: [], parentPath: [])
            }
            for page in result.pages.keys {
                result.pages[page] = result.pages[page]?.filter { !rejectedGroups.contains($0.value.group) }
                result.owners[page] = result.owners[page]?.filter { result.pages[page]?[$0.key] != nil }
            }
            for page in result.figures.keys {
                result.figureOwners[page] = result.figureOwners[page]?.filter { result.figures[page]?[$0.key] != nil }
            }
            return result
        }
        func role(_ dict: CGPDFDictionaryRef) throws -> String {
            guard var role = CGPDFObjects.name(dict, "S") else { throw Invalid.tree }
            let standard: Set<String> = ["Document", "Part", "Art", "Sect", "Div", "P", "H", "H1", "H2", "H3", "H4", "H5", "H6", "Span", "Link", "BlockQuote", "Caption", "TOC", "TOCI", "Index", "NonStruct", "Private", "L", "LI", "Lbl", "LBody", "Table", "TR", "TH", "TD", "THead", "TBody", "TFoot", "Quote", "Note", "Reference", "BibEntry", "Code", "Annot", "Ruby", "RB", "RT", "RP", "Warichu", "WT", "WP", "Figure", "Formula", "Form"]
            var visited: Set<String> = []
            while !standard.contains(role), let map = CGPDFObjects.dictionary(root, "RoleMap"), let next = CGPDFObjects.name(map, role) {
                guard visited.insert(role).inserted, visited.count <= 16 else { throw Invalid.tree }
                role = next
            }
            return role
        }
        func walk(_ value: CGPDFObjectRef, parent: CGPDFDictionaryRef, page: Int?, group: TextStructure?,
                  allowed: Bool, inTable: Bool, inRow: Bool, depth: Int, path: [Int], parentPath: [Int]) throws {
            try step(depth)
            switch CGPDFObjectGetType(value) {
            case .integer:
                var id: CGPDFInteger = 0
                guard CGPDFObjectGetValue(value, .integer, &id) else { throw Invalid.tree }
                try reference(id, page: page, group: group, ownerPath: parentPath)
            case .array:
                var kids: CGPDFArrayRef?
                guard CGPDFObjectGetValue(value, .array, &kids), let kids,
                      CGPDFArrayGetCount(kids) <= 100_000 else { throw Invalid.tree }
                for i in 0..<CGPDFArrayGetCount(kids) {
                    var child: CGPDFObjectRef?
                    guard CGPDFArrayGetObject(kids, i, &child), let child else { throw Invalid.tree }
                    try walk(child, parent: parent, page: page, group: group, allowed: allowed,
                             inTable: inTable, inRow: inRow, depth: depth + 1, path: path + [i], parentPath: parentPath)
                }
            case .dictionary:
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(value, .dictionary, &dict), let dict,
                      seen.insert(UInt(bitPattern: dict.rawValue)).inserted else { throw Invalid.tree }
                let localPage: Int?
                if let pg = CGPDFObjects.dictionary(dict, "Pg") {
                    guard let number = pages[UInt(bitPattern: pg.rawValue)] else { throw Invalid.tree }
                    localPage = number
                } else { localPage = page }
                if CGPDFObjects.name(dict, "Type") == "MCR" {
                    // Form streams have their own MCID namespace. Do not confuse it with a page.
                    guard CGPDFObjects.object(dict, "Stm") == nil, let id = CGPDFObjects.integer(dict, "MCID") else {
                        reject(group); return
                    }
                    try reference(id, page: localPage, group: group, ownerPath: parentPath)
                    return
                }
                if CGPDFObjects.name(dict, "Type") == "OBJR" { reject(group); return }
                guard CGPDFObjects.dictionary(dict, "P") == parent else { throw Invalid.tree }
                let role = try role(dict)
                var next = group
                let containers: Set<String> = ["Document", "Part", "Art", "Sect", "Div"]
                let inline: Set<String> = ["Span", "Link"]
                let level = role == "P" ? 0 : (["H1", "H2", "H3", "H4", "H5", "H6"].contains(role) ? Int(role.dropFirst()) : nil)
                var childAllowed = allowed
                if allowed, group == nil, inRow, role == "TH",
                   let kids = CGPDFObjects.object(dict, "K"), CGPDFObjectGetType(kids) == .integer {
                    var id: CGPDFInteger = 0
                    guard CGPDFObjectGetValue(kids, .integer, &id) else { throw Invalid.tree }
                    try reference(id, page: localPage, group: nil, ownerPath: path, tableHeader: true)
                    return
                }
                if allowed, group == nil, role == "Figure",
                   let alt = CGPDFObjects.text(dict, "Alt")?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !alt.isEmpty, alt.count <= 2_000,
                   let kids = CGPDFObjects.object(dict, "K"), CGPDFObjectGetType(kids) == .integer {
                    var id: CGPDFInteger = 0
                    guard CGPDFObjectGetValue(kids, .integer, &id) else { throw Invalid.tree }
                    try reference(id, page: localPage, group: nil, ownerPath: path, figure: alt)
                    return
                }
                if allowed, let level, (0...6).contains(level) {
                    guard group == nil else { reject(group); return }
                    groupCounter += 1
                    next = TextStructure(group: groupCounter, order: 0, headingLevel: level)
                } else if !(group == nil
                            ? (containers.contains(role) || (role == "Table" && !inTable)
                               || (role == "TR" && inTable) || (role == "TD" && inRow))
                            : inline.contains(role)) {
                    reject(group); next = nil; childAllowed = false
                }
                if let kids = CGPDFObjects.object(dict, "K") {
                    try walk(kids, parent: dict, page: localPage, group: next, allowed: childAllowed,
                             inTable: childAllowed && (role == "Table" || inTable),
                             inRow: childAllowed && role == "TR", depth: depth + 1,
                             path: path + [-1], parentPath: path)
                }
            case .null: break
            default: throw Invalid.tree
            }
        }
        func reject(_ group: TextStructure?) {
            result.rejected = true
            if let group { rejectedGroups.insert(group.group) }
        }
        func reference(_ id: Int, page: Int?, group: TextStructure?, ownerPath: [Int], figure: String? = nil,
                       tableHeader: Bool = false) throws {
            guard let page, id >= 0, id < 100_000,
                  references.insert("\(page):\(id)").inserted else { throw Invalid.tree }
            guard parentKeys[page] != nil else { throw Invalid.tree }
            order += 1
            if var tag = group {
                tag.order = order
                result.pages[page, default: [:]][id] = tag
                result.owners[page, default: [:]][id] = ownerPath
            } else if let figure {
                result.figures[page, default: [:]][id] = figure
                result.figureOwners[page, default: [:]][id] = ownerPath
            } else if tableHeader {
                result.tableHeaders[page, default: []].insert(id)
                result.tableHeaderOwners[page, default: [:]][id] = ownerPath
            }
        }
    }

    /// Validate only this page's sparse ParentTree array in the caller's bounded page window.
    /// Resolving all such arrays in one CGPDFDocument can retain a quadratic number of null slots.
    static func validates(_ tags: [Int: TextStructure], owners: [Int: [Int]], page: CGPDFPage) -> Bool {
        validates(ids: Set(tags.keys), owners: owners, page: page)
    }

    static func validates(ids: Set<Int>, owners: [Int: [Int]], page: CGPDFPage) -> Bool {
        guard let pageDictionary = page.dictionary, let key = CGPDFObjects.integer(pageDictionary, "StructParents"),
              let catalog = page.document?.catalog, let root = CGPDFObjects.dictionary(catalog, "StructTreeRoot"),
              let parentTree = CGPDFObjects.dictionary(root, "ParentTree"), let rootKids = CGPDFObjects.object(root, "K") else { return false }
        var visited: Set<UInt> = []
        var operations = 0
        func entries(_ node: CGPDFDictionaryRef, depth: Int) -> CGPDFArrayRef? {
            operations += 1
            guard depth < 64, operations < 100_000, !Task.isCancelled,
                  visited.insert(UInt(bitPattern: node.rawValue)).inserted else { return nil }
            if let limits = CGPDFObjects.array(node, "Limits"), CGPDFArrayGetCount(limits) == 2 {
                var low: CGPDFInteger = 0, high: CGPDFInteger = 0
                guard CGPDFArrayGetInteger(limits, 0, &low), CGPDFArrayGetInteger(limits, 1, &high),
                      low <= key, key <= high else { return nil }
            }
            if let nums = CGPDFObjects.array(node, "Nums") {
                let count = CGPDFArrayGetCount(nums)
                guard count % 2 == 0, count <= 200_000 else { return nil }
                for i in stride(from: 0, to: count, by: 2) {
                    var candidate: CGPDFInteger = 0
                    guard CGPDFArrayGetInteger(nums, i, &candidate) else { return nil }
                    if candidate == key {
                        var value: CGPDFArrayRef?
                        return CGPDFArrayGetArray(nums, i + 1, &value) ? value : nil
                    }
                }
            }
            if let kids = CGPDFObjects.array(node, "Kids"), CGPDFArrayGetCount(kids) <= 100_000 {
                for i in 0..<CGPDFArrayGetCount(kids) {
                    var child: CGPDFDictionaryRef?
                    guard CGPDFArrayGetDictionary(kids, i, &child), let child else { return nil }
                    if let result = entries(child, depth: depth + 1) { return result }
                }
            }
            return nil
        }
        guard let entries = entries(parentTree, depth: 0) else { return false }
        for id in ids {
            guard !Task.isCancelled, let path = owners[id], id >= 0, id < CGPDFArrayGetCount(entries), path.count < 128 else { return false }
            var expected = rootKids
            for component in path {
                if component == -1 {
                    var dict: CGPDFDictionaryRef?
                    guard CGPDFObjectGetValue(expected, .dictionary, &dict), let dict,
                          let next = CGPDFObjects.object(dict, "K") else { return false }
                    expected = next
                } else {
                    var array: CGPDFArrayRef?, next: CGPDFObjectRef?
                    guard component >= 0, CGPDFObjectGetValue(expected, .array, &array), let array,
                          component < CGPDFArrayGetCount(array), CGPDFArrayGetObject(array, component, &next), let next else { return false }
                    expected = next
                }
            }
            var expectedOwner: CGPDFDictionaryRef?, actualOwner: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(expected, .dictionary, &expectedOwner),
                  CGPDFArrayGetDictionary(entries, id, &actualOwner), expectedOwner == actualOwner else { return false }
        }
        return true
    }
}
