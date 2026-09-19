import CoreGraphics
import Foundation

/// Associates native lines with MCIDs using explicitly positioned text-show origins. This is
/// deliberately not a second font decoder: unknown cursor advancement or Form text falls back.
enum MarkedTextReader {
    struct Anchor: Equatable { var point: CGPoint; var id: Int? }

    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.operators = ["Ts", "Tr", "BDC", "BMC", "EMC", "Do"]
        options.moveAndShow = .show
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        var rise: CGFloat = 0
        var saved: [CGFloat] = []
        var marks: [Int?] = []
        var anchors: [Anchor] = []
        var identifiers: Set<Int> = []
        let resources: CGPDFDictionaryRef?

        init(resources: CGPDFDictionaryRef?) { self.resources = resources }

        func saveState() { saved.append(rise) }
        func restoreState() { rise = saved.removeLast() }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard walk.inText, walk.positioned else { walk.invalid = true; return }
            // An initial TJ adjustment moves the first glyph away from the known origin.
            if case .adjustment(let number)? = arguments.first, number != 0 { walk.invalid = true; return }
            let point = CGPoint(x: 0, y: rise).applying(walk.lineMatrix).applying(walk.matrix)
            guard point.x.isFinite, point.y.isFinite, anchors.count < 100_000 else { walk.invalid = true; return }
            anchors.append(Anchor(point: point, id: marks.last ?? nil))
        }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            switch op {
            case "Ts":
                guard let n = ContentStreamWalk.numbers(scanner, 1) else { walk.invalid = true; return }
                rise = n[0]
            case "Tr":
                guard let n = ContentStreamWalk.numbers(scanner, 1), (0...2).contains(n[0]) else { walk.invalid = true; return }
            case "BDC":
                guard marks.count < 128 else { walk.invalid = true; return }
                var property: CGPDFObjectRef?
                var label: UnsafePointer<CChar>?
                guard CGPDFScannerPopObject(scanner, &property), let property,
                      CGPDFScannerPopName(scanner, &label) else { walk.invalid = true; return }
                var dict: CGPDFDictionaryRef?
                if CGPDFObjectGetType(property) == .dictionary {
                    _ = CGPDFObjectGetValue(property, .dictionary, &dict)
                } else if CGPDFObjectGetType(property) == .name {
                    var key: UnsafePointer<CChar>?
                    if CGPDFObjectGetValue(property, .name, &key), let key,
                       let resources, let properties = CGPDFObjects.dictionary(resources, "Properties") {
                        dict = CGPDFObjects.dictionary(properties, String(cString: key))
                    }
                }
                guard let dict else { walk.invalid = true; return }
                // A nested non-MCID span inherits ownership, except explicit artifacts.
                let artifact = label.map { String(cString: $0) == "Artifact" } ?? false
                let id = CGPDFObjects.integer(dict, "MCID")
                if CGPDFObjects.object(dict, "MCID") != nil && id == nil { walk.invalid = true; return }
                if let id, id < 0 || !identifiers.insert(id).inserted { walk.invalid = true; return }
                marks.append(artifact ? nil : (id ?? (marks.last ?? nil)))
            case "BMC":
                guard marks.count < 128, let label = ContentStreamWalk.popName(scanner) else { walk.invalid = true; return }
                marks.append(label == "Artifact" ? nil : (marks.last ?? nil))
            case "EMC":
                guard !marks.isEmpty else { walk.invalid = true; return }
                marks.removeLast()
            case "Do":
                guard let key = ContentStreamWalk.popName(scanner),
                      let resources, let objects = CGPDFObjects.dictionary(resources, "XObject"),
                      let stream = CGPDFObjects.stream(objects, key),
                      let dictionary = CGPDFStreamGetDictionary(stream),
                      CGPDFObjects.name(dictionary, "Subtype") == "Image" else { walk.invalid = true; return }
            default:
                walk.invalid = true
            }
        }
    }

    /// The page's explicitly positioned text-show origins with the MCID each lies in, or nil
    /// when the content stream holds anything this reader cannot follow.
    static func anchors(on page: CGPDFPage) -> [Anchor]? {
        let visitor = Visitor(resources: CGPDFObjects.inheritedResources(of: page))
        guard ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor), visitor.marks.isEmpty else { return nil }
        return visitor.anchors
    }

    /// Returns false if any supported group could not be used. Unmapped lines remain untouched.
    static func apply(_ tags: [Int: TextStructure], page: CGPDFPage,
                      lines: inout [TextLine]) -> Bool {
        guard !tags.isEmpty else { return true }
        guard let anchors = anchors(on: page) else { return false }
        return associate(anchors, tags: tags, lines: &lines)
    }

    /// Gives each line the tag of the one anchor that lies in it and in no other line. A group
    /// is rejected, and none of its lines tagged, when any of its anchors is ambiguous, any of
    /// its MCIDs never appears, or a line collects anchors from more than one group.
    static func associate(_ anchors: [Anchor], tags: [Int: TextStructure], lines: inout [TextLine]) -> Bool {
        guard lines.count <= AnchorMatcher.maximumAnchors, anchors.count <= AnchorMatcher.maximumAnchors,
              lines.count * anchors.count <= AnchorMatcher.maximumComparisons else { return false }
        var assignments: [Int: [TextStructure?]] = [:]
        var found: Set<Int> = []
        var rejected: Set<Int> = []
        for anchor in anchors {
            let tag = anchor.id.flatMap { tags[$0] }
            if let id = anchor.id { found.insert(id) }
            let candidates = lines.indices.filter { AnchorMatcher.contains(lines[$0].rect, anchor.point) }
            guard candidates.count == 1, let index = candidates.first else {
                if let tag { rejected.insert(tag.group) }
                for index in candidates { assignments[index, default: []].append(nil) }
                continue
            }
            assignments[index, default: []].append(tag)
        }
        for (id, tag) in tags where !found.contains(id) { rejected.insert(tag.group) }
        for values in assignments.values {
            let groups = Set(values.compactMap { $0?.group })
            if groups.count != 1 || values.contains(where: { $0 == nil }) { rejected.formUnion(groups) }
        }
        for (index, values) in assignments {
            if let tag = values.compactMap({ $0 }).min(by: { $0.order < $1.order }), !rejected.contains(tag.group) {
                lines[index].structure = tag
            }
        }
        let counts = Dictionary(grouping: lines.compactMap(\.structure), by: \.group).mapValues(\.count)
        for index in lines.indices {
            if let group = lines[index].structure?.group { lines[index].structure?.lineCount = counts[group] ?? 0 }
        }
        return rejected.isEmpty
    }
}
