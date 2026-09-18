import CoreGraphics
import Foundation

/// Value-only page/MCID associations. No PDF objects escape the parsing pool.
enum StructureTreeReader {
    struct Index {
        var pages: [Int: [Int: TextStructure]] = [:]
        // Paths through root K (-1 means dictionary K; nonnegative means array index).
        var owners: [Int: [Int: [Int]]] = [:]
        /// Marked content inside a tagged list item (`L`, `LI`, `Lbl`, `LBody`, #194), by page and
        /// MCID, with the owners that validate it. List roles form no paragraph group, so this
        /// content is still reconstructed spatially (and still reported as a structure
        /// fallback); the tags annotate its lines with the list, item, depth and label.
        var listTags: [Int: [Int: ListTag]] = [:]
        var listOwners: [Int: [Int: [Int]]] = [:]
        var present = false
        var rejected = false
    }

    static func read(_ url: URL) throws -> Index {
        try autoreleasepool {
            guard let document = CGPDFDocument(url as CFURL), let catalog = document.catalog,
                  let root = dictionary(catalog, "StructTreeRoot") else { return Index() }
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
        var listCounter = 0
        /// The `L` elements enclosing the walk, outermost first.
        var listDepth: [Int] = []
        /// Lists implied by `LI` elements set directly in another element, by that element.
        var parentLists: [UInt: Int] = [:]
        var itemCounter = 0
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
                if let key = integer(dict, "StructParents") {
                    guard key >= 0, neededParentKeys.insert(key).inserted else { throw Invalid.tree }
                    parentKeys[i] = key
                }
            }
            if let kids = object(root, "K") {
                try walk(kids, parent: root, page: nil, group: nil, list: nil, allowed: true, depth: 0, path: [], parentPath: [])
            }
            for page in result.pages.keys {
                result.pages[page] = result.pages[page]?.filter { !rejectedGroups.contains($0.value.group) }
                result.owners[page] = result.owners[page]?.filter { result.pages[page]?[$0.key] != nil }
            }
            return result
        }
        func role(_ dict: CGPDFDictionaryRef) throws -> String {
            guard var role = name(dict, "S") else { throw Invalid.tree }
            let standard: Set<String> = ["Document", "Part", "Art", "Sect", "Div", "P", "H", "H1", "H2", "H3", "H4", "H5", "H6", "Span", "Link", "BlockQuote", "Caption", "TOC", "TOCI", "Index", "NonStruct", "Private", "L", "LI", "Lbl", "LBody", "Table", "TR", "TH", "TD", "THead", "TBody", "TFoot", "Quote", "Note", "Reference", "BibEntry", "Code", "Annot", "Ruby", "RB", "RT", "RP", "Warichu", "WT", "WP", "Figure", "Formula", "Form"]
            var visited: Set<String> = []
            while !standard.contains(role), let map = dictionary(root, "RoleMap"), let next = name(map, role) {
                guard visited.insert(role).inserted, visited.count <= 16 else { throw Invalid.tree }
                role = next
            }
            return role
        }
        func walk(_ value: CGPDFObjectRef, parent: CGPDFDictionaryRef, page: Int?, group: TextStructure?,
                  list: ListTag?, allowed: Bool, depth: Int, path: [Int], parentPath: [Int]) throws {
            try step(depth)
            switch CGPDFObjectGetType(value) {
            case .integer:
                var id: CGPDFInteger = 0
                guard CGPDFObjectGetValue(value, .integer, &id) else { throw Invalid.tree }
                try reference(id, page: page, group: group, list: list, ownerPath: parentPath)
            case .array:
                var kids: CGPDFArrayRef?
                guard CGPDFObjectGetValue(value, .array, &kids), let kids,
                      CGPDFArrayGetCount(kids) <= 100_000 else { throw Invalid.tree }
                for i in 0..<CGPDFArrayGetCount(kids) {
                    var child: CGPDFObjectRef?
                    guard CGPDFArrayGetObject(kids, i, &child), let child else { throw Invalid.tree }
                    try walk(child, parent: parent, page: page, group: group, list: list, allowed: allowed, depth: depth + 1, path: path + [i], parentPath: parentPath)
                }
            case .dictionary:
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(value, .dictionary, &dict), let dict,
                      seen.insert(UInt(bitPattern: dict.rawValue)).inserted else { throw Invalid.tree }
                let localPage: Int?
                if let pg = dictionary(dict, "Pg") {
                    guard let number = pages[UInt(bitPattern: pg.rawValue)] else { throw Invalid.tree }
                    localPage = number
                } else { localPage = page }
                if name(dict, "Type") == "MCR" {
                    // Form streams have their own MCID namespace. Do not confuse it with a page.
                    guard object(dict, "Stm") == nil, let id = integer(dict, "MCID") else {
                        reject(group); return
                    }
                    try reference(id, page: localPage, group: group, list: list, ownerPath: parentPath)
                    return
                }
                if name(dict, "Type") == "OBJR" { reject(group); return }
                guard dictionary(dict, "P") == parent else { throw Invalid.tree }
                let role = try role(dict)
                var next = group
                let containers: Set<String> = ["Document", "Part", "Art", "Sect", "Div"]
                let inline: Set<String> = ["Span", "Link"]
                let level = role == "P" ? 0 : (["H1", "H2", "H3", "H4", "H5", "H6"].contains(role) ? Int(role.dropFirst()) : nil)
                var childAllowed = allowed
                if allowed, let level, (0...6).contains(level) {
                    guard group == nil else { reject(group); return }
                    groupCounter += 1
                    next = TextStructure(group: groupCounter, order: 0, headingLevel: level)
                } else if !(group == nil ? containers.contains(role) : inline.contains(role)) {
                    reject(group); next = nil; childAllowed = false
                }
                // A list's roles still form no group, but they name the list, item, depth and label
                // of the content beneath them. `list` is nil until an `LI`: an `L`'s own content
                // outside any item belongs to no item.
                var nextList = list
                switch role {
                case "L":
                    listCounter += 1
                    listDepth.append(listCounter)
                case "LI":
                    // An `LI` outside any `L` (Our Flag tags its folding steps as `Sect` > `LI`) is an
                    // item of the list its parent element holds.
                    itemCounter += 1
                    let owner: Int
                    if let open = listDepth.last { owner = open } else if let known = parentLists[UInt(bitPattern: parent.rawValue)] {
                        owner = known
                    } else {
                        listCounter += 1
                        owner = listCounter
                        parentLists[UInt(bitPattern: parent.rawValue)] = owner
                    }
                    nextList = ListTag(list: owner, item: itemCounter, depth: max(0, listDepth.count - 1), label: false)
                case "Lbl": nextList?.label = true
                case "LBody": nextList?.label = false
                default: break
                }
                if let kids = object(dict, "K") {
                    try walk(kids, parent: dict, page: localPage, group: next, list: nextList, allowed: childAllowed, depth: depth + 1, path: path + [-1], parentPath: path)
                }
                if role == "L" { listDepth.removeLast() }
            case .null: break
            default: throw Invalid.tree
            }
        }
        func reject(_ group: TextStructure?) {
            result.rejected = true
            if let group { rejectedGroups.insert(group.group) }
        }
        func reference(_ id: Int, page: Int?, group: TextStructure?, list: ListTag?, ownerPath: [Int]) throws {
            guard let page, id >= 0, id < 100_000,
                  references.insert("\(page):\(id)").inserted else { throw Invalid.tree }
            guard parentKeys[page] != nil else { throw Invalid.tree }
            order += 1
            if var tag = group {
                tag.order = order
                result.pages[page, default: [:]][id] = tag
                result.owners[page, default: [:]][id] = ownerPath
            }
            if let list {
                result.listTags[page, default: [:]][id] = list
                result.listOwners[page, default: [:]][id] = ownerPath
            }
        }
    }

    /// Validate only this page's sparse ParentTree array in the caller's bounded page window.
    /// Resolving all such arrays in one CGPDFDocument can retain a quadratic number of null slots.
    static func validates<Tag>(_ tags: [Int: Tag], owners: [Int: [Int]], page: CGPDFPage) -> Bool {
        guard let pageDictionary = page.dictionary, let key = integer(pageDictionary, "StructParents"),
              let catalog = page.document?.catalog, let root = dictionary(catalog, "StructTreeRoot"),
              let parentTree = dictionary(root, "ParentTree"), let rootKids = object(root, "K") else { return false }
        var visited: Set<UInt> = []
        var operations = 0
        func entries(_ node: CGPDFDictionaryRef, depth: Int) -> CGPDFArrayRef? {
            operations += 1
            guard depth < 64, operations < 100_000, !Task.isCancelled,
                  visited.insert(UInt(bitPattern: node.rawValue)).inserted else { return nil }
            if let limits = array(node, "Limits"), CGPDFArrayGetCount(limits) == 2 {
                var low: CGPDFInteger = 0, high: CGPDFInteger = 0
                guard CGPDFArrayGetInteger(limits, 0, &low), CGPDFArrayGetInteger(limits, 1, &high),
                      low <= key, key <= high else { return nil }
            }
            if let nums = array(node, "Nums") {
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
            if let kids = array(node, "Kids"), CGPDFArrayGetCount(kids) <= 100_000 {
                for i in 0..<CGPDFArrayGetCount(kids) {
                    var child: CGPDFDictionaryRef?
                    guard CGPDFArrayGetDictionary(kids, i, &child), let child else { return nil }
                    if let result = entries(child, depth: depth + 1) { return result }
                }
            }
            return nil
        }
        guard let entries = entries(parentTree, depth: 0) else { return false }
        for id in tags.keys {
            guard !Task.isCancelled, let path = owners[id], id >= 0, id < CGPDFArrayGetCount(entries), path.count < 128 else { return false }
            var expected = rootKids
            for component in path {
                if component == -1 {
                    var dict: CGPDFDictionaryRef?
                    guard CGPDFObjectGetValue(expected, .dictionary, &dict), let dict,
                          let next = object(dict, "K") else { return false }
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

    static func object(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
        var value: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dict, key, &value) ? value : nil
    }
    static func dictionary(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dict, key, &value) ? value : nil
    }
    static func array(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
        var value: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(dict, key, &value) ? value : nil
    }
    static func integer(_ dict: CGPDFDictionaryRef, _ key: String) -> Int? {
        var value: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dict, key, &value) ? value : nil
    }
    static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &value), let value else { return nil }
        return String(cString: value)
    }
}
