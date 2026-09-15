import CoreGraphics
import Foundation

/// Associates native lines with MCIDs using explicitly positioned text-show origins. This is
/// deliberately not a second font decoder: unknown cursor advancement or Form text falls back.
enum MarkedTextReader {
    private struct Anchor { var point: CGPoint; var id: Int? }
    private final class State {
        var matrix = CGAffineTransform.identity
        var lineMatrix = CGAffineTransform.identity
        var saved: [(CGAffineTransform, CGFloat, CGFloat)] = []
        var leading: CGFloat = 0
        var rise: CGFloat = 0
        var positioned = false
        var inText = false
        var marks: [Int?] = []
        var anchors: [Anchor] = []
        var identifiers: Set<Int> = []
        var invalid = false
        var operations = 0
        var resources: CGPDFDictionaryRef?

        func accept(_ scanner: CGPDFScannerRef) -> Bool {
            operations += 1
            if operations > 100_000 || Task.isCancelled { invalid = true }
            if invalid { CGPDFScannerStop(scanner) }
            return !invalid
        }
        func move(_ x: CGFloat, _ y: CGFloat) {
            guard inText else { invalid = true; return }
            lineMatrix = lineMatrix.translatedBy(x: x, y: y)
            positioned = true
        }
        func show(_ scanner: CGPDFScannerRef, array: Bool = false) {
            guard accept(scanner), inText, positioned else { invalid = true; return }
            if array {
                var values: CGPDFArrayRef?
                guard CGPDFScannerPopArray(scanner, &values), let values else { invalid = true; return }
                // An initial TJ adjustment moves the first glyph away from the known origin.
                if CGPDFArrayGetCount(values) > 0 {
                    var number: CGPDFReal = 0
                    if CGPDFArrayGetNumber(values, 0, &number), number != 0 { invalid = true; return }
                }
            } else {
                var value: CGPDFStringRef?
                guard CGPDFScannerPopString(scanner, &value) else { invalid = true; return }
            }
            let point = CGPoint(x: 0, y: rise).applying(lineMatrix).applying(matrix)
            guard point.x.isFinite, point.y.isFinite, anchors.count < 100_000 else { invalid = true; return }
            anchors.append(Anchor(point: point, id: marks.last ?? nil))
            positioned = false
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

    /// Returns false if any supported group could not be used. Unmapped lines remain untouched.
    static func apply(_ tags: [Int: TextStructure], page: CGPDFPage,
                      lines: inout [TextLine]) -> Bool {
        guard !tags.isEmpty else { return true }
        guard let table = CGPDFOperatorTableCreate() else { return false }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.saved.count < 128 else { s.invalid = true; return }
            s.saved.append((s.matrix, s.leading, s.rise))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let saved = s.saved.popLast() else { s.invalid = true; return }
            (s.matrix, s.leading, s.rise) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText else { s.invalid = true; return }
            s.inText = true; s.lineMatrix = .identity; s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "ET") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText else { s.invalid = true; return }
            s.inText = false; s.positioned = false
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.lineMatrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.move(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.leading = -n[1]; s.move(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "T*") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner) else { return }
            s.move(0, -s.leading)
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.invalid = true; return }
            s.leading = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.invalid = true; return }
            s.rise = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1), (0...2).contains(n[0]) else {
                s.invalid = true; return
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
            if Self.numbers(scanner, 2) == nil { s.invalid = true }
        }
        CGPDFOperatorTableSetCallback(table, "BDC") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.marks.count < 128 else { s.invalid = true; return }
            var property: CGPDFObjectRef?
            var label: UnsafePointer<CChar>?
            guard CGPDFScannerPopObject(scanner, &property), let property,
                  CGPDFScannerPopName(scanner, &label) else { s.invalid = true; return }
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
            guard let dict else { s.invalid = true; return }
            // A nested non-MCID span inherits ownership, except explicit artifacts.
            let artifact = label.map { String(cString: $0) == "Artifact" } ?? false
            let id = StructureTreeReader.integer(dict, "MCID")
            if StructureTreeReader.object(dict, "MCID") != nil && id == nil { s.invalid = true; return }
            if let id, id < 0 || !s.identifiers.insert(id).inserted { s.invalid = true; return }
            s.marks.append(artifact ? nil : (id ?? (s.marks.last ?? nil)))
        }
        CGPDFOperatorTableSetCallback(table, "BMC") { scanner, info in
            let s = Self.state(info)
            var label: UnsafePointer<CChar>?
            guard s.accept(scanner), s.marks.count < 128, CGPDFScannerPopName(scanner, &label), let label else {
                s.invalid = true; return
            }
            s.marks.append(String(cString: label) == "Artifact" ? nil : (s.marks.last ?? nil))
        }
        CGPDFOperatorTableSetCallback(table, "EMC") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.marks.isEmpty else { s.invalid = true; return }
            s.marks.removeLast()
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            var key: UnsafePointer<CChar>?
            guard s.accept(scanner), CGPDFScannerPopName(scanner, &key), let key,
                  let resources = s.resources, let objects = StructureTreeReader.dictionary(resources, "XObject") else {
                s.invalid = true; return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFDictionaryGetStream(objects, key, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream),
                  StructureTreeReader.name(dictionary, "Subtype") == "Image" else {
                s.invalid = true; return
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
        guard CGPDFScannerScan(scanner), !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else { return false }

        guard lines.count <= 10_000, s.anchors.count <= 10_000,
              lines.count * s.anchors.count <= 2_000_000 else { return false }
        var assignments: [Int: [TextStructure?]] = [:]
        var found: Set<Int> = []
        var rejected: Set<Int> = []
        for anchor in s.anchors {
            let tag = anchor.id.flatMap { tags[$0] }
            if let id = anchor.id { found.insert(id) }
            let candidates = lines.indices.filter { lines[$0].rect.insetBy(dx: -0.75, dy: -0.75).contains(anchor.point) }
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
