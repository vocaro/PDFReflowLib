import CoreGraphics
import Foundation

/// Associates native lines with MCIDs using explicitly positioned text-show origins. This is
/// deliberately not a second font decoder: unknown cursor advancement or Form text falls back.
enum CensusReader {
    nonisolated(unsafe) static var pageReason: String? = nil
    nonisolated(unsafe) static var groupReasons: [Int: Set<String>] = [:]
    nonisolated(unsafe) static var anchorBytes: [[UInt8]] = []
    nonisolated(unsafe) static var samples: [String] = []
    private struct Anchor { var point: CGPoint; var id: Int? }
    /// The open marked-content section. `artifact` is inherited, so a span nested inside an
    /// artifact is still page furniture; an explicit MCID always names its own content.
    private struct Mark { var id: Int?; var artifact: Bool }
    private final class State {
        var matrix = CGAffineTransform.identity
        var lineMatrix = CGAffineTransform.identity
        var saved: [(CGAffineTransform, CGFloat, CGFloat)] = []
        var leading: CGFloat = 0
        var rise: CGFloat = 0
        var positioned = false
        var inText = false
        var marks: [Mark] = []
        var anchors: [Anchor] = []
        var identifiers: Set<Int> = []
        /// Identifiers whose text was shown from an origin this reader cannot derive.
        var unknownOrigins: Set<Int> = []
        var invalid = false
        func fail(_ why: String) { if !invalid { CensusReader.pageReason = why }; invalid = true }
        var operations = 0
        var resources: CGPDFDictionaryRef?
        /// Form XObjects already inspected on this page, by stream identity: true when textless.
        var textlessForms: [UInt: Bool] = [:]
        /// Operators scanned inside forms on this page; see `FormScan`.
        var formOperations = 0

        func accept(_ scanner: CGPDFScannerRef) -> Bool {
            operations += 1
            if operations > 100_000 || Task.isCancelled { fail("accept@L34") }
            if invalid { CGPDFScannerStop(scanner) }
            return !invalid
        }
        func move(_ x: CGFloat, _ y: CGFloat) {
            guard inText else { fail("move@L39"); return }
            lineMatrix = lineMatrix.translatedBy(x: x, y: y)
            positioned = true
        }
        func show(_ scanner: CGPDFScannerRef, array: Bool = false) {
            guard accept(scanner), inText else { fail("show@L44"); return }
            // The origin is known only when a positioning operator precedes the show. Pop the
            // operand either way, so an unknown origin can be scoped instead of stopping the scan.
            var known = positioned
            positioned = false
            var bytes: [UInt8] = []
            func append(_ string: CGPDFStringRef) {
                if let p = CGPDFStringGetBytePtr(string) { bytes += UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(string)) }
            }
            if array {
                var values: CGPDFArrayRef?
                guard CGPDFScannerPopArray(scanner, &values), let values else { fail("show@L51"); return }
                // An initial TJ adjustment moves the first glyph away from the known origin.
                if CGPDFArrayGetCount(values) > 0 {
                    var number: CGPDFReal = 0
                    if CGPDFArrayGetNumber(values, 0, &number), number != 0 { known = false }
                }
                for i in 0..<CGPDFArrayGetCount(values) {
                    var string: CGPDFStringRef?
                    if CGPDFArrayGetString(values, i, &string), let string { append(string) }
                }
            } else {
                var value: CGPDFStringRef?
                guard CGPDFScannerPopString(scanner, &value) else { fail("show@L59"); return }
                if let value { append(value) }
            }
            guard known else { unknownOrigin(); return }
            let point = CGPoint(x: 0, y: rise).applying(lineMatrix).applying(matrix)
            guard point.x.isFinite, point.y.isFinite, anchors.count < 100_000 else { fail("show@L63"); return }
            anchors.append(Anchor(point: point, id: marks.last?.id))
            CensusReader.anchorBytes.append(bytes)
        }
        /// An unplaceable show costs exactly what it can affect. Inside an artifact it costs
        /// nothing, because artifacts carry no structure. Inside a marked section it costs that
        /// section's identifier, and only that identifier's group falls back. Unmarked text could
        /// sit on any line, so it still invalidates the page, as the unknown-cursor rule did.
        func unknownOrigin() {
            guard let mark = marks.last else { fail("unknownOrigin@L71"); return }
            if let id = mark.id { unknownOrigins.insert(id) }
            else if !mark.artifact { fail("unknownOrigin@L73") }
        }
    }
    private static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }
    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var result = [CGFloat](repeating: 0, count: count)
        for i in result.indices.reversed() {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return nil }
            result[i] = value
        }
        return result
    }

    /// Whether a Form XObject, and every form it draws, shows no text.
    /// Forms draw figures, so their operators have a budget of their own per page (they create no
    /// anchors); nesting is bounded as `GraphicsReader` bounds it. Anything this scan cannot
    /// resolve, or a budget it exhausts, counts as text.
    private final class FormScan {
        var textless = true
        var nested: [(CGPDFStreamRef, CGPDFDictionaryRef, CGPDFContentStreamRef)] = []
        let state: State
        init(state: State) { self.state = state }
        func count(_ scanner: CGPDFScannerRef) {
            state.formOperations += 1
            if state.formOperations > 2_000_000 || (state.formOperations & 0xFFF == 0 && Task.isCancelled) {
                textless = false; CGPDFScannerStop(scanner)
            }
        }
    }
    /// Every content operator a textless form may use; each is counted.
    private static let graphicsOperators = ["b", "B", "b*", "B*", "BI", "BX", "c", "cm", "CS", "cs", "d", "d0",
        "d1", "DP", "EI", "EX", "f", "F", "f*", "G", "g", "gs", "h", "i", "ID", "j", "J", "K", "k", "l", "m",
        "M", "MP", "n", "q", "Q", "re", "RG", "rg", "ri", "s", "S", "SC", "sc", "SCN", "scn", "sh", "v", "w",
        "W", "W*", "y", "BT", "ET", "Tc", "Td", "TD", "Tf", "TL", "Tm", "Tr", "Ts", "Tw", "Tz", "T*",
        "BDC", "BMC", "EMC"]
    private static func isTextless(_ form: CGPDFStreamRef, dictionary: CGPDFDictionaryRef,
                                   parent: CGPDFContentStreamRef, resources inherited: CGPDFDictionaryRef,
                                   state s: State, depth: Int) -> Bool {
        guard depth < 12, !s.invalid, let table = CGPDFOperatorTableCreate() else { return false }
        defer { CGPDFOperatorTableRelease(table) }
        for op in graphicsOperators {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                Unmanaged<FormScan>.fromOpaque(info!).takeUnretainedValue().count(scanner)
            }
        }
        // A text show is exactly what association would have to follow. Marked content without
        // one owns no line, so it is counted like any other operator.
        for op in ["Tj", "TJ", "'", "\""] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                Unmanaged<FormScan>.fromOpaque(info!).takeUnretainedValue().textless = false
                CGPDFScannerStop(scanner)
            }
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let scan = Unmanaged<FormScan>.fromOpaque(info!).takeUnretainedValue()
            scan.count(scanner)
            var name: UnsafePointer<CChar>?
            let content = CGPDFScannerGetContentStream(scanner)
            var stream: CGPDFStreamRef?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let resource = CGPDFContentStreamGetResource(content, "XObject", name),
                  CGPDFObjectGetValue(resource, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else {
                scan.textless = false; CGPDFScannerStop(scanner); return
            }
            switch StructureTreeReader.name(dictionary, "Subtype") {
            case "Image": break
            case "Form": scan.nested.append((stream, dictionary, content))
            default: scan.textless = false; CGPDFScannerStop(scanner)
            }
        }
        let resources = StructureTreeReader.dictionary(dictionary, "Resources") ?? inherited
        let content = CGPDFContentStreamCreateWithStream(form, resources, parent)
        defer { CGPDFContentStreamRelease(content) }
        let scan = FormScan(state: s)
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(scan).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        guard CGPDFScannerScan(scanner), scan.textless else { return false }
        for (stream, dictionary, parent) in scan.nested {
            let identity = UInt(bitPattern: stream.rawValue)
            if s.textlessForms[identity] == nil {
                s.textlessForms[identity] = isTextless(stream, dictionary: dictionary, parent: parent,
                    resources: resources, state: s, depth: depth + 1)
            }
            guard s.textlessForms[identity] == true else { return false }
        }
        return true
    }

    /// Returns false if any supported group could not be used. Unmapped lines remain untouched.
    static func apply(_ tags: [Int: TextStructure], page: CGPDFPage,
                      lines: inout [TextLine]) -> Bool {
        guard !tags.isEmpty else { return true }
        guard let table = CGPDFOperatorTableCreate() else { return false }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.saved.count < 128 else { s.fail("q@L173"); return }
            s.saved.append((s.matrix, s.leading, s.rise))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let saved = s.saved.popLast() else { s.fail("Q@L178"); return }
            (s.matrix, s.leading, s.rise) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 6) else { s.fail("cm@L183"); return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText else { s.fail("BT@L188"); return }
            s.inText = true; s.lineMatrix = .identity; s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "ET") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText else { s.fail("ET@L193"); return }
            s.inText = false; s.positioned = false
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 6) else { s.fail("Tm@L198"); return }
            s.lineMatrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 2) else { s.fail("Td@L204"); return }
            s.move(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 2) else { s.fail("TD@L209"); return }
            s.leading = -n[1]; s.move(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "T*") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner) else { return }
            s.move(0, -s.leading)
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.fail("TL@L219"); return }
            s.leading = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.fail("Ts@L224"); return }
            s.rise = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1), (0...2).contains(n[0]) else {
                s.fail("Tr@L230"); return
            }
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in Self.state(info).show(scanner) }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in Self.state(info).show(scanner, array: true) }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            let s = Self.state(info); s.move(0, -s.leading); s.show(scanner)
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            // Word/character spacing precede the string; they do not change the first origin.
            let s = Self.state(info); s.move(0, -s.leading); s.show(scanner)
            if Self.numbers(scanner, 2) == nil { s.fail("quote@L241") }
        }
        CGPDFOperatorTableSetCallback(table, "BDC") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.marks.count < 128 else { s.fail("BDC@L245"); return }
            var property: CGPDFObjectRef?
            var label: UnsafePointer<CChar>?
            guard CGPDFScannerPopObject(scanner, &property), let property,
                  CGPDFScannerPopName(scanner, &label) else { s.fail("BDC@L249"); return }
            var dict: CGPDFDictionaryRef?
            if CGPDFObjectGetType(property) == .dictionary {
                _ = CGPDFObjectGetValue(property, .dictionary, &dict)
            } else if CGPDFObjectGetType(property) == .name {
                var key: UnsafePointer<CChar>?
                if CGPDFObjectGetValue(property, .name, &key), let key,
                   let resources = s.resources, let properties = StructureTreeReader.dictionary(resources, "Properties") {
                    dict = StructureTreeReader.dictionary(properties, String(cString: key))
                }
            }
            guard let dict else { s.fail("BDC@L260"); return }
            // A nested non-MCID span inherits ownership, except explicit artifacts.
            let artifact = label.map { String(cString: $0) == "Artifact" } ?? false
            let id = StructureTreeReader.integer(dict, "MCID")
            if StructureTreeReader.object(dict, "MCID") != nil && id == nil { s.fail("BDC@L264"); return }
            if let id, id < 0 || !s.identifiers.insert(id).inserted { s.fail("BDC@L265"); return }
            let inherited = s.marks.last ?? Mark(id: nil, artifact: false)
            s.marks.append(artifact ? Mark(id: nil, artifact: true)
                : (id.map { Mark(id: $0, artifact: false) } ?? inherited))
        }
        CGPDFOperatorTableSetCallback(table, "BMC") { scanner, info in
            let s = Self.state(info)
            var label: UnsafePointer<CChar>?
            guard s.accept(scanner), s.marks.count < 128, CGPDFScannerPopName(scanner, &label), let label else {
                s.fail("BMC@L274"); return
            }
            let inherited = s.marks.last ?? Mark(id: nil, artifact: false)
            s.marks.append(String(cString: label) == "Artifact" ? Mark(id: nil, artifact: true) : inherited)
        }
        CGPDFOperatorTableSetCallback(table, "EMC") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.marks.isEmpty else { s.fail("EMC@L281"); return }
            s.marks.removeLast()
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            var key: UnsafePointer<CChar>?
            guard s.accept(scanner), CGPDFScannerPopName(scanner, &key), let key,
                  let resources = s.resources, let objects = StructureTreeReader.dictionary(resources, "XObject") else {
                s.fail("Do@L289"); return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFDictionaryGetStream(objects, key, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else {
                s.fail("Do@L294"); return
            }
            switch StructureTreeReader.name(dictionary, "Subtype") {
            case "Image": return
            // A form that shows no text cannot place or own a line:
            // a vector figure, a rule or a background drawn through a form (#75). Any other form
            // could show text this reader cannot follow, so the page still falls back.
            case "Form":
                let identity = UInt(bitPattern: stream.rawValue)
                if s.textlessForms[identity] == nil {
                    s.textlessForms[identity] = Self.isTextless(stream, dictionary: dictionary,
                        parent: CGPDFScannerGetContentStream(scanner), resources: resources, state: s, depth: 0)
                }
                if s.textlessForms[identity] != true { s.fail("Do@L307") }
            default: s.fail("Do@L308")
            }
        }
        let s = State()
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        // Resources are inheritable through the page tree.
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<64 {
            guard let current = node else { break }
            if let resources = StructureTreeReader.dictionary(current, "Resources") { s.resources = resources; break }
            node = StructureTreeReader.dictionary(current, "Parent")
        }
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(s).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        let scanned = CGPDFScannerScan(scanner)
        guard scanned, !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else {
            if CensusReader.pageReason == nil { CensusReader.pageReason = !scanned ? "scanFailed" : !s.marks.isEmpty ? "unbalancedMarks" : !s.saved.isEmpty ? "unbalancedQ" : "unclosedBT" }
            return false
        }

        guard lines.count <= 10_000, s.anchors.count <= 10_000,
              lines.count * s.anchors.count <= 2_000_000 else { CensusReader.pageReason = "limits"; return false }
        var assignments: [Int: [TextStructure?]] = [:]
        var found: Set<Int> = []
        // A group that shows text from an unplaceable origin cannot be associated, so only that
        // group falls back. Identifiers outside the supported roles name no group and cost nothing.
        var rejected = Set(s.unknownOrigins.compactMap { tags[$0]?.group })
        for id in s.unknownOrigins { if let g = tags[id]?.group { CensusReader.groupReasons[g, default: []].insert("unknownOrigin") } }
        for (anchorIndex, anchor) in s.anchors.enumerated() {
            let tag = anchor.id.flatMap { tags[$0] }
            if let id = anchor.id { found.insert(id) }
            var candidates = lines.indices.filter { lines[$0].rect.insetBy(dx: -0.75, dy: -0.75).contains(anchor.point) }
            // A display initial makes its line's box tall enough to cover the next line's origin
            // as well. A show starts where its own line starts, so when exactly one candidate
            // begins at the origin it owns the show; anything else stays ambiguous.
            if candidates.count > 1 {
                let starting = candidates.filter { abs(lines[$0].rect.minX - anchor.point.x) <= 0.75 }
                if starting.count == 1 { candidates = starting }
            }
            guard candidates.count == 1, let index = candidates.first else {
                if let tag { rejected.insert(tag.group); CensusReader.groupReasons[tag.group, default: []].insert(candidates.isEmpty ? "noLineAtOrigin" : "ambiguousOrigin")
                    let bytes = CensusReader.anchorBytes[anchorIndex]
                    let ascii = String(bytes.prefix(24).map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : "." })
                    let hex = bytes.prefix(8).map { String(format: "%02x", $0) }.joined()
                    let nearest = lines.min { a, b in
                        hypot(a.rect.midX - anchor.point.x, a.rect.midY - anchor.point.y) < hypot(b.rect.midX - anchor.point.x, b.rect.midY - anchor.point.y) }
                    let near = nearest.map { String(format: "(%.1f,%.1f %.1fx%.1f) %@", $0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height, String($0.text.prefix(30))) } ?? "-"
                    CensusReader.samples.append("\(candidates.isEmpty ? "noLine" : "ambiguous(\(candidates.count))")\t\(String(format: "%.1f,%.1f", anchor.point.x, anchor.point.y))\tlen\(bytes.count)\t\(hex)\t\(ascii)\tnearest \(near)")
                }
                for index in candidates { assignments[index, default: []].append(nil) }
                continue
            }
            assignments[index, default: []].append(tag)
        }
        for (id, tag) in tags where !found.contains(id) { rejected.insert(tag.group); CensusReader.groupReasons[tag.group, default: []].insert(
            s.unknownOrigins.contains(id) ? "mcidShownOnlyFromUnknownOrigin" : s.identifiers.contains(id) ? "mcidMarkedWithoutPlaceableText" : "mcidAbsentFromContentStream") }
        for values in assignments.values {
            let groups = Set(values.compactMap { $0?.group })
            if groups.count != 1 || values.contains(where: { $0 == nil }) { rejected.formUnion(groups); for g in groups { CensusReader.groupReasons[g, default: []].insert(groups.count != 1 ? "lineSharedByGroups" : "lineSharedWithUntaggedOrAmbiguousShow") } }
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
