import CoreGraphics
import Foundation

/// Associates native lines with MCIDs using explicitly positioned text-show origins. This is
/// deliberately not a second font decoder: unknown cursor advancement or Form text falls back.
enum MarkedTextReader {
    struct Anchor: Equatable { var point: CGPoint; var id: Int? }

    /// The open marked-content section. `artifact` is inherited, so a span nested inside an
    /// artifact is still page furniture; an explicit MCID always names its own content.
    private struct Mark: Equatable { var id: Int?; var artifact: Bool }

    /// Everything one page's content stream showed, as far as this reader can account for it.
    /// A show it cannot place costs only what that show could have described: nothing inside an
    /// artifact, its own identifier inside a marked section, the whole page outside marked
    /// content, where the text could have belonged to any line (#67).
    struct Scan {
        var anchors: [Anchor] = []
        /// Identifiers whose text was shown from an origin this reader cannot derive (#67).
        var unknownOrigins: Set<Int> = []
        /// Identifiers whose marked content showed only space glyphs. Such a show draws nothing
        /// and so anchors no line, but its identifier was shown (#91).
        var blankIdentifiers: Set<Int> = []
        /// Measurement only: the shows the two rules above absorbed, which once refused the page.
        var artifactUnknownOrigins = 0
        var invisibleArtifactShows = 0
        var blankShows = 0
    }

    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.operators = ["Ts", "Tr", "BDC", "BMC", "EMC", "Do"]
        options.moveAndShow = .show
        options.selectsFonts = true
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        var rise: CGFloat = 0
        /// The current font's codes whose glyph is a space; empty when the font cannot say.
        var spaces: Set<UInt8> = []
        /// The text render mode; 3 draws nothing (invisible text).
        var renderMode: CGFloat = 0
        var saved: [(CGFloat, Set<UInt8>, CGFloat)] = []
        var marks: [Mark] = []
        var identifiers: Set<Int> = []
        var scan = Scan()
        /// Space codes per font dictionary on this page, by identity.
        var fontSpaces: [UInt: Set<UInt8>] = [:]
        let resources: CGPDFDictionaryRef?

        init(resources: CGPDFDictionaryRef?) { self.resources = resources }

        func saveState() { saved.append((rise, spaces, renderMode)) }
        func restoreState() { (rise, spaces, renderMode) = saved.removeLast() }

        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            // A font this reader cannot resolve has no space codes; its shows keep every other rule.
            spaces = []
            var font: CGPDFDictionaryRef?
            guard let resource, CGPDFObjectGetValue(resource, .dictionary, &font), let font else { return }
            let identity = UInt(bitPattern: font.rawValue)
            if let known = fontSpaces[identity] { spaces = known; return }
            // Each new font costs one map parse; a page naming more than this many says nothing.
            guard fontSpaces.count < 256 else { return }
            let codes = MarkedTextReader.spaceCodes(font)
            fontSpaces[identity] = codes
            spaces = codes
        }

        /// True when the show draws at least one glyph and every glyph it draws is a space.
        private func blank(_ arguments: [ContentStreamWalk.ShowArgument]) -> Bool {
            guard !spaces.isEmpty else { return false }
            var drew = false
            for argument in arguments {
                // An array element that is neither a string nor a number could be anything.
                if case .other = argument { return false }
                guard case .string(let string) = argument else { continue }
                let count = CGPDFStringGetLength(string)
                guard count > 0 else { continue }
                guard let bytes = CGPDFStringGetBytePtr(string) else { return false }
                for index in 0..<count where !spaces.contains(bytes[index]) { return false }
                drew = true
            }
            return drew
        }

        /// A show this reader cannot place costs exactly what it could have described. Inside an
        /// artifact it costs nothing, because artifacts carry no structure. Inside a marked
        /// section it costs that section's identifier, and only that identifier's group falls
        /// back. Unmarked text could sit on any line, so it still refuses the page (#67).
        private func unplaceable(_ walk: ContentStreamWalk) {
            guard let mark = marks.last else { walk.invalid = true; return }
            if let id = mark.id { scan.unknownOrigins.insert(id) }
            else if mark.artifact { scan.artifactUnknownOrigins += 1 }
            else { walk.invalid = true }
        }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard walk.inText else { walk.invalid = true; return }
            // The origin is known only when a positioning operator precedes the show, and an
            // initial TJ adjustment moves the first glyph away from it.
            var known = walk.positioned
            if case .adjustment(let number)? = arguments.first, number != 0 { known = false }
            // Invisible text is inherited transcription (an OCR layer over a scan), not the text
            // the tags describe. Inside an artifact it carries no structure and costs nothing;
            // anywhere else the page's tags cannot be trusted (#91).
            if renderMode == 3 {
                guard marks.last?.artifact == true else { walk.invalid = true; return }
                scan.invisibleArtifactShows += 1
                return
            }
            // A show of only spaces draws nothing, and PDFKit trims trailing spaces from its line
            // boxes, so its origin often lies past every line. It owns no line, so it neither
            // places nor costs a group, but its identifier still counts as shown (#91).
            if blank(arguments) {
                scan.blankShows += 1
                if let id = marks.last?.id { scan.blankIdentifiers.insert(id) }
                return
            }
            guard known else { unplaceable(walk); return }
            let point = CGPoint(x: 0, y: rise).applying(walk.lineMatrix).applying(walk.matrix)
            guard point.x.isFinite, point.y.isFinite, scan.anchors.count < 100_000 else { walk.invalid = true; return }
            scan.anchors.append(Anchor(point: point, id: marks.last?.id))
        }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            switch op {
            case "Ts":
                guard let n = ContentStreamWalk.numbers(scanner, 1) else { walk.invalid = true; return }
                rise = n[0]
            case "Tr":
                // Mode 3 is judged where text is shown, by its mark; clipping modes still refuse.
                guard let n = ContentStreamWalk.numbers(scanner, 1), (0...3).contains(n[0]) else { walk.invalid = true; return }
                renderMode = n[0]
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
                let inherited = marks.last ?? Mark(id: nil, artifact: false)
                marks.append(artifact ? Mark(id: nil, artifact: true)
                    : (id.map { Mark(id: $0, artifact: false) } ?? inherited))
            case "BMC":
                guard marks.count < 128, let label = ContentStreamWalk.popName(scanner) else { walk.invalid = true; return }
                let inherited = marks.last ?? Mark(id: nil, artifact: false)
                marks.append(label == "Artifact" ? Mark(id: nil, artifact: true) : inherited)
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

    private static let bfcharBlocks = try! NSRegularExpression(pattern: #"beginbfchar([\s\S]*?)endbfchar"#)
    /// A one-byte `bfchar` source whose destination is exactly U+0020. A four-digit source token
    /// cannot match, so a two-byte map contributes nothing, and a destination that only begins
    /// with `0020` (`<0020002E>`) cannot match either.
    private static let spaceEntry = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{2})>\s*<0020>"#)

    /// The one-byte codes a simple font draws as a space (U+0020). Its `ToUnicode` map decides,
    /// since that map states what each code shows: only a `bfchar` entry naming a one-byte code
    /// and exactly U+0020 counts, so ranges, multi-character destinations and maps this reader
    /// cannot read leave the font with no space codes rather than a guess. Without a map, code 32
    /// is the space of the standard named encodings. Type3 glyphs are procedures and composite
    /// fonts use multi-byte codes: neither gets space codes here (#91).
    static func spaceCodes(_ font: CGPDFDictionaryRef) -> Set<UInt8> {
        guard let subtype = CGPDFObjects.name(font, "Subtype"),
              ["Type1", "TrueType", "MMType1"].contains(subtype) else { return [] }
        guard CGPDFObjects.stream(font, "ToUnicode") != nil else {
            guard let encoding = CGPDFObjects.name(font, "Encoding"),
                  ["WinAnsiEncoding", "MacRomanEncoding", "StandardEncoding"].contains(encoding) else { return [] }
            return [0x20]
        }
        guard let data = CGPDFObjects.rawData(font, "ToUnicode"), data.count <= 65_536,
              let raw = String(data: data, encoding: .isoLatin1) else { return [] }
        let text = raw.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        // An inherited map could name codes this reader never sees in the stream it reads.
        guard !text.contains("usecmap") else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        let blocks = bfcharBlocks.matches(in: text, range: whole)
        guard blocks.count <= 256 else { return [] }
        var codes: Set<UInt8> = []
        for block in blocks {
            for entry in spaceEntry.matches(in: text, range: block.range(at: 1)) {
                guard let range = Range(entry.range(at: 1), in: text),
                      let code = UInt8(text[range], radix: 16) else { continue }
                codes.insert(code)
            }
        }
        return codes
    }

    /// The page's text-show evidence, or nil when the content stream holds something this reader
    /// cannot follow at all.
    static func scan(_ page: CGPDFPage) -> Scan? {
        let visitor = Visitor(resources: CGPDFObjects.inheritedResources(of: page))
        guard ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor), visitor.marks.isEmpty else { return nil }
        return visitor.scan
    }

    /// Returns false if any supported group could not be used. Unmapped lines remain untouched.
    static func apply(_ tags: [Int: TextStructure], page: CGPDFPage,
                      lines: inout [TextLine]) -> Bool {
        guard !tags.isEmpty else { return true }
        guard let scan = scan(page) else { return false }
        return associate(scan, tags: tags, lines: &lines)
    }

    static func associate(_ anchors: [Anchor], tags: [Int: TextStructure], lines: inout [TextLine]) -> Bool {
        associate(Scan(anchors: anchors), tags: tags, lines: &lines)
    }

    /// Gives each line the tag of the one anchor that lies in it and in no other line. A group
    /// is rejected, and none of its lines tagged, when any of its anchors is ambiguous, any of
    /// its MCIDs never appears, a show it owns could not be placed, or a line collects anchors
    /// from more than one group.
    static func associate(_ scan: Scan, tags: [Int: TextStructure], lines: inout [TextLine]) -> Bool {
        guard lines.count <= AnchorMatcher.maximumAnchors, scan.anchors.count <= AnchorMatcher.maximumAnchors,
              lines.count * scan.anchors.count <= AnchorMatcher.maximumComparisons else { return false }
        var assignments: [Int: [TextStructure?]] = [:]
        // A show whose origin this reader cannot derive could have drawn anywhere, so its group
        // cannot be associated. Identifiers outside the supported roles name no group.
        var rejected = Set(scan.unknownOrigins.compactMap { tags[$0]?.group })
        // A space-only show draws nothing, so its identifier appears without anchoring a line.
        var found = scan.blankIdentifiers
        for anchor in scan.anchors {
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
