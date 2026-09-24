import CoreGraphics
import Foundation

/// Locates a direct page Image XObject owned by one marked-content identifier. A Figure tag
/// alone does not establish which preserved crop contains its artwork: vector figures and
/// multi-part figures deliberately return no association.
enum MarkedImageReader {
    private final class Visitor: ContentStreamVisitor {
        let resources: CGPDFDictionaryRef?
        var marks: [Int?] = []
        var images: [Int: [CGRect]] = [:]
        var seen: Set<Int> = []

        init(page: CGPDFPage) { resources = page.dictionary.flatMap { CGPDFObjects.dictionary($0, "Resources") } }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            switch op {
            case "BDC":
                guard marks.count < 128 else { walk.invalid = true; return }
                var property: CGPDFObjectRef?
                guard CGPDFScannerPopObject(scanner, &property), let property,
                      let label = ContentStreamWalk.popName(scanner) else { walk.invalid = true; return }
                var dict: CGPDFDictionaryRef?
                if CGPDFObjectGetType(property) == .dictionary {
                    _ = CGPDFObjectGetValue(property, .dictionary, &dict)
                } else if CGPDFObjectGetType(property) == .name {
                    var key: UnsafePointer<CChar>?
                    if CGPDFObjectGetValue(property, .name, &key), let key,
                       let properties = resources.flatMap({ CGPDFObjects.dictionary($0, "Properties") }) {
                        dict = CGPDFObjects.dictionary(properties, String(cString: key))
                    }
                }
                guard let dict else { walk.invalid = true; return }
                let id = CGPDFObjects.integer(dict, "MCID")
                if CGPDFObjects.object(dict, "MCID") != nil && id == nil { walk.invalid = true; return }
                if let id, (id < 0 || !seen.insert(id).inserted) { walk.invalid = true; return }
                marks.append(label == "Artifact" ? nil : (id ?? marks.last ?? nil))
            case "BMC":
                guard marks.count < 128, let label = ContentStreamWalk.popName(scanner) else { walk.invalid = true; return }
                marks.append(label == "Artifact" ? nil : (marks.last ?? nil))
            case "EMC":
                guard !marks.isEmpty else { walk.invalid = true; return }
                marks.removeLast()
            case "Do":
                guard let key = ContentStreamWalk.popName(scanner),
                      let objects = resources.flatMap({ CGPDFObjects.dictionary($0, "XObject") }),
                      let stream = CGPDFObjects.stream(objects, key),
                      let dictionary = CGPDFStreamGetDictionary(stream),
                      let subtype = CGPDFObjects.name(dictionary, "Subtype") else { walk.invalid = true; return }
                guard let id = marks.last ?? nil else { return }
                // A Form has a separate marking namespace; it cannot prove ownership here.
                guard subtype == "Image" else { images[id, default: []].append(.null); return }
                let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(walk.matrix).standardized
                guard rect.isFinite, rect.width > 0, rect.height > 0 else { walk.invalid = true; return }
                images[id, default: []].append(rect)
            default: walk.invalid = true
            }
        }
    }

    static func read(_ page: CGPDFPage, ids: Set<Int>) -> [Int: CGRect] {
        guard !ids.isEmpty else { return [:] }
        let visitor = Visitor(page: page)
        var options = ContentStreamWalk.Options()
        options.operators = ["BDC", "BMC", "EMC", "Do"]
        guard ContentStreamWalk.scan(page, options: options, visitor: visitor), visitor.marks.isEmpty else { return [:] }
        return visitor.images.compactMapValues { $0.count == 1 && !$0[0].isNull ? $0[0] : nil }
            .filter { ids.contains($0.key) }
    }
}
