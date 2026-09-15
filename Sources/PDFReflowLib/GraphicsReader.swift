import CoreGraphics
import Foundation

/// Finds painted regions, not just raw image resources. Cropping the original rendering preserves
/// masks, clipping, vector paths and labels without reimplementing their PDF compositing semantics.
enum GraphicsReader {
    struct Result { var regions: [CGRect]; var unsupported: Bool }
    private final class State {
        var matrix = CGAffineTransform.identity
        var saved: [(CGAffineTransform, Bool, CGRect)] = []
        // Conservative page-space bounds, not a replacement for Core Graphics clipping.
        var clip = CGRect.zero
        var pendingClip = false
        var white = false
        var path = CGRect.null
        var regions: [CGRect] = []
        var unsupported = false
        var depth = 0
        var operations = 0
        var table: CGPDFOperatorTableRef?
        var resources: CGPDFDictionaryRef?
        var pageBounds = CGRect.zero

        func accept() -> Bool {
            operations += 1
            if operations > 100_000 { unsupported = true; return false }
            return true
        }
        func finishPath() {
            if pendingClip {
                if !path.isNull && !path.isFinite { unsupported = true }
                else { clip = clip.intersection(path) }
            }
            pendingClip = false
            path = .null
        }
        func paint() {
            defer { finishPath() }
            guard accept(), !path.isNull else { return }
            if regions.count < 10_000 { regions.append(path.insetBy(dx: -2, dy: -2)) }
            else { unsupported = true }
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for i in (0..<count).reversed() {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return nil }
            values[i] = value
        }
        return values
    }

    static func read(_ page: CGPDFPage) -> Result {
        guard let table = CGPDFOperatorTableCreate() else {
            return Result(regions: [], unsupported: true)
        }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let s = Self.state(info)
            guard s.accept(), s.saved.count < 128 else { s.unsupported = true; return }
            s.saved.append((s.matrix, s.white, s.clip))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = Self.state(info)
            if let saved = s.saved.popLast() { (s.matrix, s.white, s.clip) = saved }
            else { s.unsupported = true }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = Self.numbers(scanner, 6) else { s.unsupported = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
                .concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
            let s = Self.state(info)
            s.white = Self.numbers(scanner, 3)?.allSatisfy { $0 >= 0.999 } ?? false
        }
        CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
            Self.state(info).white = (Self.numbers(scanner, 1)?.first ?? 0) >= 0.999
        }
        for op in ["k", "sc", "scn"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).white = false }
        }
        for op in ["m", "l"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                guard s.accept(), let n = Self.numbers(scanner, 2) else { s.unsupported = true; return }
                let point = CGPoint(x: n[0], y: n[1]).applying(s.matrix)
                s.path = s.path.union(CGRect(origin: point, size: .zero))
            }
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = Self.numbers(scanner, 6) else { s.unsupported = true; return }
            for i in stride(from: 0, to: 6, by: 2) {
                s.path = s.path.union(CGRect(origin: CGPoint(x: n[i], y: n[i + 1])
                    .applying(s.matrix), size: .zero))
            }
        }
        for op in ["v", "y"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                guard s.accept(), let n = Self.numbers(scanner, 4) else { s.unsupported = true; return }
                for i in stride(from: 0, to: 4, by: 2) {
                    s.path = s.path.union(CGRect(origin: CGPoint(x: n[i], y: n[i + 1])
                        .applying(s.matrix), size: .zero))
                }
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = Self.numbers(scanner, 4) else { s.unsupported = true; return }
            s.path = s.path.union(CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
                .applying(s.matrix))
        }
        for op in ["S", "s", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).paint() }
        }
        for op in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info)
                if s.white { s.finishPath() } else { s.paint() }
            }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in Self.state(info).finishPath() }
        for op in ["W", "W*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).pendingClip = true }
        }
        CGPDFOperatorTableSetCallback(table, "sh") { scanner, info in
            Self.shading(scanner, state: Self.state(info))
        }
        // Unsupported placement/compositing must remain visible, never silently disappear.
        for op in ["EI"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).unsupported = true }
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            var name: UnsafePointer<CChar>?
            let parent = CGPDFScannerGetContentStream(scanner)
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let resource = CGPDFContentStreamGetResource(parent, "XObject", name) else {
                s.unsupported = true; return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(resource, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else {
                s.unsupported = true; return
            }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else {
                s.unsupported = true; return
            }
            switch String(cString: subtype) {
            case "Image":
                if s.regions.count < 10_000 {
                    s.regions.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.matrix))
                } else { s.unsupported = true }
            case "Form":
                let startCount = s.regions.count
                Self.descend(stream, dictionary: dictionary, parent: parent, state: s)
                // A bounded form can be one composite illustration with detached labels. Keep
                // those labels with it. Whole-page form wrappers are not treated as figures.
                var box: CGPDFArrayRef?
                if s.regions.count > startCount,
                   CGPDFDictionaryGetArray(dictionary, "BBox", &box), let box,
                   CGPDFArrayGetCount(box) == 4 {
                    var n = [CGPDFReal](repeating: 0, count: 4)
                    if (0..<4).allSatisfy({ CGPDFArrayGetNumber(box, $0, &n[$0]) && n[$0].isFinite }) {
                        // The form's own matrix is applied separately from the caller CTM.
                        var transform = CGAffineTransform.identity
                        var matrixArray: CGPDFArrayRef?
                        if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrixArray), let matrixArray,
                           CGPDFArrayGetCount(matrixArray) == 6 {
                            var m = [CGPDFReal](repeating: 0, count: 6)
                            if (0..<6).allSatisfy({ CGPDFArrayGetNumber(matrixArray, $0, &m[$0]) && m[$0].isFinite }) {
                                transform = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
                            }
                        }
                        let rect = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1])
                            .applying(transform.concatenating(s.matrix))
                        if rect.isFinite, rect.width * rect.height < s.pageBounds.width * s.pageBounds.height * 0.7 {
                            s.regions.append(rect)
                        }
                    }
                }
            default: s.unsupported = true
            }
        }
        let s = State()
        s.table = table
        s.pageBounds = page.getBoxRect(.cropBox)
        s.clip = s.pageBounds
        if let dictionary = page.dictionary {
            CGPDFDictionaryGetDictionary(dictionary, "Resources", &s.resources)
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        scan(stream, state: s)
        let bounds = page.getBoxRect(.cropBox)
        return Result(regions: clusters(s.regions.map { $0.intersection(bounds) }, distance: 4),
                      unsupported: s.unsupported)
    }

    private static func rectangle(_ dictionary: CGPDFDictionaryRef, key: String) -> CGRect? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &array), let array,
              CGPDFArrayGetCount(array) == 4 else { return nil }
        var n = [CGPDFReal](repeating: 0, count: 4)
        guard (0..<4).allSatisfy({ CGPDFArrayGetNumber(array, $0, &n[$0]) && n[$0].isFinite }) else { return nil }
        // PDF rectangles can name either pair of opposite corners (InDesign uses both orders).
        let rect = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1]).standardized
        return rect.isFinite ? rect : nil
    }

    // The sh operator paints within the active clip and optional shading BBox. Do not infer
    // extents from axial/radial Coords: extension and mesh/function shadings can paint beyond
    // them. Core Graphics renders the original region, including masks, colors and labels.
    private static func shading(_ scanner: CGPDFScannerRef, state s: State) {
        guard s.accept() else { return }
        var name: UnsafePointer<CChar>?
        let parent = CGPDFScannerGetContentStream(scanner)
        guard CGPDFScannerPopName(scanner, &name), let name,
              let resource = CGPDFContentStreamGetResource(parent, "Shading", name) else {
            s.unsupported = true; return
        }
        var dictionary: CGPDFDictionaryRef?
        var stream: CGPDFStreamRef?
        if !CGPDFObjectGetValue(resource, .dictionary, &dictionary),
           CGPDFObjectGetValue(resource, .stream, &stream), let stream {
            dictionary = CGPDFStreamGetDictionary(stream)
        }
        var type: CGPDFInteger = 0
        guard let dictionary, CGPDFDictionaryGetInteger(dictionary, "ShadingType", &type),
              (1...7).contains(type) else { s.unsupported = true; return }
        var region = s.clip
        var boxObject: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dictionary, "BBox", &boxObject) {
            guard let box = rectangle(dictionary, key: "BBox") else { s.unsupported = true; return }
            let transformed = box.applying(s.matrix)
            guard transformed.isFinite else { s.unsupported = true; return }
            region = region.intersection(transformed)
        }
        if region.isNull || region.isEmpty { return }
        guard region.isFinite, s.regions.count < 10_000 else { s.unsupported = true; return }
        // Without a tighter bound, preserve the page rather than inventing a small crop.
        guard region.width * region.height < s.pageBounds.width * s.pageBounds.height * 0.75 else {
            s.unsupported = true; return
        }
        s.regions.append(region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds))
    }

    private static func scan(_ stream: CGPDFContentStreamRef, state s: State) {
        let scanner = CGPDFScannerCreate(stream, s.table!, Unmanaged.passUnretained(s).toOpaque())
        if !CGPDFScannerScan(scanner) { s.unsupported = true }
        CGPDFScannerRelease(scanner)
    }

    private static func descend(_ form: CGPDFStreamRef, dictionary: CGPDFDictionaryRef,
                                parent: CGPDFContentStreamRef, state s: State) {
        guard s.depth < 12 else { s.unsupported = true; return }
        let oldMatrix = s.matrix, oldPath = s.path, oldSaved = s.saved, oldWhite = s.white
        let oldResources = s.resources
        let oldClip = s.clip, oldPendingClip = s.pendingClip
        defer {
            s.matrix = oldMatrix; s.path = oldPath; s.saved = oldSaved; s.white = oldWhite
            s.resources = oldResources; s.clip = oldClip; s.pendingClip = oldPendingClip; s.depth -= 1
        }
        s.depth += 1
        s.saved = []
        s.path = .null
        s.pendingClip = false
        var array: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array {
            guard CGPDFArrayGetCount(array) == 6 else { s.unsupported = true; return }
            var n = [CGFloat](repeating: 0, count: 6)
            for i in 0..<6 {
                var value: CGPDFReal = 0
                guard CGPDFArrayGetNumber(array, i, &value), value.isFinite else {
                    s.unsupported = true; return
                }
                n[i] = value
            }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
                .concatenating(s.matrix)
        }
        guard let box = rectangle(dictionary, key: "BBox") else { s.unsupported = true; return }
        let transformed = box.applying(s.matrix)
        guard transformed.isFinite else { s.unsupported = true; return }
        s.clip = s.clip.intersection(transformed)
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
        guard let resources = resources ?? s.resources else { s.unsupported = true; return }
        s.resources = resources
        let content = CGPDFContentStreamCreateWithStream(form, resources, parent)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, state: s)
    }
}
