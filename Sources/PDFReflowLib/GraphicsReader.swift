import CoreGraphics
import Foundation

/// Finds painted regions, not just raw image resources. Cropping the original rendering preserves
/// masks, clipping, vector paths and labels without reimplementing their PDF compositing semantics.
enum GraphicsReader {
    /// Unclustered paint, so a flat ground can be separated from the art it surrounds (#182).
    struct Paint: Equatable, Codable {
        var rect: CGRect
        var image = false
        var filled = false
        var rectangular = false
        var vertices: [CGPoint] = []
    }
    struct Result { var regions: [CGRect]; var unsupported: Bool; var hasOnlyInvisibleText = false
                    /// Placed raster image XObjects specifically, a subset of `regions` (#176):
                    /// a photograph's internal texture is not writing the page drew, even where it
                    /// forms rows the ink test would otherwise count.
                    var images: [CGRect] = []
                    /// A text-showing operator painted visibly. A page with none of these, no
                    /// painted region and no annotation draws nothing at all (#224); extracted
                    /// text alone cannot say so, since glyphs PDFKit cannot map extract as
                    /// nothing.
                    var visibleText = false
                    var hasInvisibleText = false
                    var paints: [Paint] = []
                    /// Exact rectangles filled by the page, before region clustering (#215).
                    var filledCells: [CGRect] = [] }
    private final class State {
        var matrix = CGAffineTransform.identity
        var saved: [(CGAffineTransform, Bool, CGRect?, Int, Bool)] = []
        var textRenderingMode = 0
        var invisibleText = false
        var visibleText = false
        /// Conservative page-space bounds of the clipping region in force, or nil when nothing
        /// clips. A clip path contributes its bounding box, so this over-approximates the real
        /// region and no visible mark is ever outside it. It is not a replacement for Core
        /// Graphics clipping.
        var clip: CGRect?
        var pendingClip = false
        var white = false
        var flatFill = true
        var path = CGRect.null
        var vertices: [CGPoint]? = []
        var subpaths = 0
        var paints: [Paint] = []
        var imageIndex = 0
        var imageBounds: ((Int, CGPDFDictionaryRef) -> CGRect?)?
        var regions: [CGRect] = []
        var images: [CGRect] = []
        var filledCells: [CGRect] = []
        var pathRectangles: [CGRect] = []
        var onlyRectangles = true
        var unsupported = false
        var depth = 0
        var operations = 0
        var table: CGPDFOperatorTableRef?
        var resources: CGPDFDictionaryRef?
        var pageBounds = CGRect.zero

        /// Charged once per operator that moves the reader's state. The budget bounds the work
        /// one page can ask for; a page that exhausts it is preserved whole rather than half
        /// read. 250,000 operations cost about 60 ms and leave the paint, saved-state and form
        /// depth caps to bound everything else (#13).
        static let operationBudget = 250_000

        func accept() -> Bool {
            operations += 1
            if operations > Self.operationBudget || Task.isCancelled { unsupported = true; return false }
            return true
        }
        func finishPath() {
            if pendingClip, !path.isNull {
                // A clip path that never reached a coordinate (`W n` with nothing constructed)
                // leaves the clip alone rather than emptying it: over-approximating costs a
                // crop that is too wide, under-approximating erases the artwork below.
                if !path.isFinite { unsupported = true }
                else { clip = clip.map { $0.intersection(path) } ?? path }
            }
            pendingClip = false
            path = .null
            vertices = []
            subpaths = 0
            pathRectangles = []
            onlyRectangles = true
        }
        func recordFilledRectangles() {
            guard onlyRectangles, !Task.isCancelled else { return }
            for rect in pathRectangles {
                guard filledCells.count < 10_000 else { return }
                if let shown = visible(rect), !shown.isEmpty { filledCells.append(shown) }
            }
        }
        /// The part of a footprint the clip in force lets show, or nil when none of it can.
        ///
        /// A path's or image's extent is not its ink: illustrations draw streamlines, arrows and
        /// photographs far past the frame that clips them, into the neighboring column, and a
        /// bleed rectangle can lie wholly outside its clip (#52, #98). The tracked clip
        /// over-approximates the real clipping region, so nothing visible is dropped here.
        ///
        /// `tolerance` widens the clip by the same padding the footprint carries. A painted
        /// footprint is padded for stroke width and antialiasing, and a frame drawn exactly on
        /// the clip that bounds it would otherwise lose that padding on the clipped edges —
        /// moving a crop the clip does not really cut.
        func visible(_ rect: CGRect, tolerance: CGFloat = 0) -> CGRect? {
            guard let clip else { return rect }
            let shown = rect.intersection(clip.insetBy(dx: -tolerance, dy: -tolerance))
            return shown.isNull || shown.isEmpty ? nil : shown
        }
        func paint(filled: Bool = false) {
            defer { finishPath() }
            // The footprint is padded before it is clipped: a horizontal rule is a path of no
            // height, and an unpadded rectangle of no area intersects nothing at all.
            guard accept(), !path.isNull,
                  let shown = visible(path.insetBy(dx: -2, dy: -2), tolerance: 2) else { return }
            if regions.count < 10_000 {
                regions.append(shown)
                var points = vertices ?? []
                if points.count > 2, points.first == points.last { points.removeLast() }
                let rectangular = points.count == 4 && Set(points.map(\.x)).count == 2
                    && Set(points.map(\.y)).count == 2
                    && points.allSatisfy { ($0.x == path.minX || $0.x == path.maxX)
                        && ($0.y == path.minY || $0.y == path.maxY) }
                paints.append(Paint(rect: shown, filled: filled, rectangular: rectangular, vertices: points))
            } else { unsupported = true }
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }

    static func read(_ page: CGPDFPage,
                     imageBounds: ((Int, CGPDFDictionaryRef) -> CGRect?)? = nil) -> Result {
        guard let table = CGPDFOperatorTableCreate() else {
            return Result(regions: [], unsupported: true)
        }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let s = Self.state(info)
            guard s.accept(), s.saved.count < 128 else { s.unsupported = true; return }
            s.saved.append((s.matrix, s.white, s.clip, s.textRenderingMode, s.flatFill))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = Self.state(info)
            if let saved = s.saved.popLast() { (s.matrix, s.white, s.clip, s.textRenderingMode, s.flatFill) = saved }
            else { s.unsupported = true }
        }
        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, info in
            let s = Self.state(info)
            var mode: CGPDFInteger = 0
            guard s.accept(), CGPDFScannerPopInteger(scanner, &mode), (0...7).contains(mode) else {
                s.unsupported = true; return
            }
            s.textRenderingMode = mode
        }
        for op in ["Tj", "TJ", "'", "\""] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info)
                guard s.accept() else { return }
                if s.textRenderingMode == 3 { s.invisibleText = true }
                else { s.visibleText = true }
            }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = ContentStreamWalk.numbers(scanner, 6) else { s.unsupported = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
                .concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
            let s = Self.state(info)
            s.white = ContentStreamWalk.numbers(scanner, 3)?.allSatisfy { $0 >= 0.999 } ?? false
            s.flatFill = true
        }
        CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
            let s = Self.state(info)
            s.white = (ContentStreamWalk.numbers(scanner, 1)?.first ?? 0) >= 0.999
            s.flatFill = true
        }
        for op in ["k", "sc"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info); s.white = false; s.flatFill = true
            }
        }
        CGPDFOperatorTableSetCallback(table, "scn") { _, info in
            let s = Self.state(info); s.white = false; s.flatFill = false
        }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = ContentStreamWalk.numbers(scanner, 2) else { s.unsupported = true; return }
            s.onlyRectangles = false
            let point = CGPoint(x: n[0], y: n[1]).applying(s.matrix)
            s.path = s.path.union(CGRect(origin: point, size: .zero))
            s.subpaths += 1
            if s.subpaths > 1 { s.vertices = nil }
            else { s.vertices?.append(point) }
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = ContentStreamWalk.numbers(scanner, 2) else { s.unsupported = true; return }
            s.onlyRectangles = false
            let point = CGPoint(x: n[0], y: n[1]).applying(s.matrix)
            s.path = s.path.union(CGRect(origin: point, size: .zero))
            if (s.vertices?.count ?? 0) >= 8 { s.vertices = nil }
            else { s.vertices?.append(point) }
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = ContentStreamWalk.numbers(scanner, 6) else { s.unsupported = true; return }
            s.onlyRectangles = false
            s.vertices = nil
            for i in stride(from: 0, to: 6, by: 2) {
                s.path = s.path.union(CGRect(origin: CGPoint(x: n[i], y: n[i + 1])
                    .applying(s.matrix), size: .zero))
            }
        }
        for op in ["v", "y"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                guard s.accept(), let n = ContentStreamWalk.numbers(scanner, 4) else { s.unsupported = true; return }
                s.onlyRectangles = false
                s.vertices = nil
                for i in stride(from: 0, to: 4, by: 2) {
                    s.path = s.path.union(CGRect(origin: CGPoint(x: n[i], y: n[i + 1])
                        .applying(s.matrix), size: .zero))
                }
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = ContentStreamWalk.numbers(scanner, 4) else { s.unsupported = true; return }
            let rect = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
            if s.path.isNull {
                s.vertices = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                              CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
                    .map { $0.applying(s.matrix) }
                s.subpaths = 1
            } else { s.vertices = nil }
            s.path = s.path.union(rect.applying(s.matrix))
            if abs(s.matrix.b) < 0.0001, abs(s.matrix.c) < 0.0001,
               s.pathRectangles.count < 10_000 { s.pathRectangles.append(rect.standardized.applying(s.matrix)) }
            else { s.onlyRectangles = false }
        }
        for op in ["S", "s"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).paint() }
        }
        for op in ["B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info)
                s.recordFilledRectangles()
                s.paint()
            }
        }
        for op in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info)
                s.recordFilledRectangles()
                if s.white { s.finishPath() } else { s.paint(filled: s.flatFill) }
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
                let index = s.imageIndex
                s.imageIndex += 1
                if s.regions.count < 10_000 {
                    // Only the part the clip lets show: FAA page 19 places a 338 by 400 pt map
                    // under a 207 by 129 pt clip, and the rest of it reached into the left
                    // column (#52).
                    let unit = s.imageBounds?(index, dictionary) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                    if !unit.isEmpty, let rect = s.visible(unit.applying(s.matrix)) {
                        s.regions.append(rect)
                        s.images.append(rect)
                        s.paints.append(Paint(rect: rect, image: true))
                    }
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
                        let box = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1])
                            .applying(transform.concatenating(s.matrix))
                        // The form paints nothing the clip in force hides, so its declared box
                        // is not its footprint either (#52).
                        if box.isFinite, let rect = s.visible(box),
                           rect.width * rect.height < s.pageBounds.width * s.pageBounds.height * 0.7 {
                            s.regions.append(rect)
                            s.paints.append(Paint(rect: rect))
                        }
                    }
                }
            default: s.unsupported = true
            }
        }
        let s = State()
        s.table = table
        s.imageBounds = imageBounds
        s.pageBounds = page.getBoxRect(.cropBox)
        // Nothing paints outside the crop box, so it is the opening clip — unless the page
        // reports no usable box, where an unclipped start keeps every mark.
        s.clip = s.pageBounds.isFinite && !s.pageBounds.isEmpty ? s.pageBounds : nil
        if let dictionary = page.dictionary {
            CGPDFDictionaryGetDictionary(dictionary, "Resources", &s.resources)
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        scan(stream, state: s)
        let bounds = page.getBoxRect(.cropBox)
        return Result(regions: clusters(s.regions.map { $0.intersection(bounds) }, distance: 4),
                      unsupported: s.unsupported, hasOnlyInvisibleText: !s.unsupported && s.invisibleText && !s.visibleText,
                      images: clusters(s.images.map { $0.intersection(bounds) }, distance: 4),
                      visibleText: s.visibleText, hasInvisibleText: s.invisibleText,
                      paints: s.paints.map { paint in
                          var result = paint; result.rect = paint.rect.intersection(bounds); return result
                      }, filledCells: s.filledCells)
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
        var region = s.clip ?? s.pageBounds
        var boxObject: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dictionary, "BBox", &boxObject) {
            guard let box = CGPDFObjects.rectangle(dictionary, "BBox") else { s.unsupported = true; return }
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
        let rect = region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds)
        s.regions.append(rect)
        s.paints.append(Paint(rect: rect))
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
        let oldVertices = s.vertices, oldSubpaths = s.subpaths, oldFlatFill = s.flatFill
        let oldRectangles = s.pathRectangles, oldOnlyRectangles = s.onlyRectangles
        let oldResources = s.resources
        let oldTextRenderingMode = s.textRenderingMode
        let oldClip = s.clip, oldPendingClip = s.pendingClip
        defer {
            s.matrix = oldMatrix; s.path = oldPath; s.saved = oldSaved; s.white = oldWhite
            s.vertices = oldVertices; s.subpaths = oldSubpaths; s.flatFill = oldFlatFill
            s.pathRectangles = oldRectangles; s.onlyRectangles = oldOnlyRectangles
            s.textRenderingMode = oldTextRenderingMode
            s.resources = oldResources; s.clip = oldClip; s.pendingClip = oldPendingClip; s.depth -= 1
        }
        s.depth += 1
        s.saved = []
        s.path = .null
        s.vertices = []; s.subpaths = 0
        s.pathRectangles = []; s.onlyRectangles = true
        s.pendingClip = false
        if CGPDFObjects.array(dictionary, "Matrix") != nil {
            guard let matrix = CGPDFObjects.matrix(dictionary, "Matrix") else { s.unsupported = true; return }
            s.matrix = matrix.concatenating(s.matrix)
        }
        guard let box = CGPDFObjects.rectangle(dictionary, "BBox") else { s.unsupported = true; return }
        let transformed = box.applying(s.matrix)
        guard transformed.isFinite else { s.unsupported = true; return }
        // The form's own box clips its content, under whatever clip was already in force. A box
        // that transforms to no area at all is left out of the clip rather than emptying it:
        // producers do emit degenerate boxes, and a form's artwork must not vanish for one.
        if !transformed.isEmpty { s.clip = s.clip.map { $0.intersection(transformed) } ?? transformed }
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
        guard let resources = resources ?? s.resources else { s.unsupported = true; return }
        s.resources = resources
        let content = CGPDFContentStreamCreateWithStream(form, resources, parent)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, state: s)
    }
}
