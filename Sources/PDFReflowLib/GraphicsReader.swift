import CoreGraphics
import Foundation

/// Finds painted regions, not just raw image resources. Cropping the original rendering preserves
/// masks, clipping, vector paths and labels without reimplementing their PDF compositing semantics.
enum GraphicsReader {
    /// One painted footprint. `frame` marks a path made only of `re` rectangles (filled or
    /// stroked) painted outside any `/Figure` marked content: a sidebar box, a tint band or a
    /// table cell background rather than figure ink. Whether it is decoration is decided later
    /// against the page's text (`TintDetector`); this reader records only what was painted.
    /// Where a ruled grid's columns meet: InDesign draws each row rule as one segment per column,
    /// so collinear thin segments that abut (the reader pads each by two points, so neighbours
    /// overlap by up to six) mark a column boundary. A boundary recurring at the same x in at
    /// least three rule rows is a column joint, spanning those rows vertically (Fed page 46,
    /// Table 3.1: joints at x ≈ 215.4 and 360 over seven rows). A lone underline, a dashed rule
    /// in one row or two rules that happen to touch are not a grid (#65).
    static func columnJoints(_ rects: [CGRect]) -> [ColumnJoint] {
        var rows: [(y: CGFloat, segments: [CGRect])] = []
        for rect in rects where rect.isFinite && !rect.isNull && rect.height <= 6 && rect.width >= 24 {
            if let index = rows.firstIndex(where: { abs($0.y - rect.midY) <= 1.5 }) {
                rows[index].segments.append(rect)
            } else { rows.append((rect.midY, [rect])) }
        }
        var joints: [(x: CGFloat, ys: [CGFloat])] = []
        for row in rows {
            let segments = row.segments.sorted { $0.minX < $1.minX }
            var seen: [CGFloat] = []
            for (a, b) in zip(segments, segments.dropFirst())
            where b.minX <= a.maxX + 1 && b.minX >= a.maxX - 6 && b.maxX > a.maxX {
                let x = (a.maxX + b.minX) / 2
                guard !seen.contains(where: { abs($0 - x) <= 3 }) else { continue }
                seen.append(x)
                if let index = joints.firstIndex(where: { abs($0.x - x) <= 3 }) {
                    joints[index].ys.append(row.y)
                } else { joints.append((x, [row.y])) }
            }
        }
        return joints.filter { $0.ys.count >= 3 }
            .map { ColumnJoint(x: $0.x, minY: $0.ys.min()!, maxY: $0.ys.max()!) }
            .sorted { $0.x < $1.x }
    }

    struct Paint: Equatable, Sendable { var rect: CGRect; var frame: Bool }
    /// Where one text-showing operator placed its text, for deciding whether it can be seen
    /// (#74, #85). In horizontal writing every glyph of a show sits on `baseline`; `left` is a
    /// lower bound on its first glyph's x (glyph advances are never negative, but kerning and
    /// negative spacing can move left), `-infinity` when unknown. `origin` is the exact start
    /// when a positioning operator preceded the show. `clip` over-approximates the clip region
    /// in force when the text was painted; `sequence` orders it among `covers`.
    struct TextShow: Equatable, Sendable {
        var baseline: CGFloat
        var left: CGFloat
        var origin: CGPoint?
        /// The known origin of the show that opened this run of shows on the same line (the
        /// show's own origin when it has one): its glyphs continue from there along `baseline`.
        var chainStart: CGPoint?
        var clip: CGRect
        var sequence: Int
    }
    /// An opaque image or rectangle fill under-approximated to what it certainly paints: its
    /// axis-aligned bounds inside exact rectangular clips, painted with full alpha, the Normal
    /// blend mode, no soft mask, no overprint, outside optional content and transparency groups.
    struct Cover: Equatable, Sendable { var rect: CGRect; var sequence: Int }
    /// Text not set on a horizontal baseline: its glyphs lie within `halfWidth` of the ray from
    /// `origin` along the unit `direction` (of the whole line through it unless `bounded`).
    struct SlantedShow: Equatable, Sendable {
        var origin: CGPoint
        var direction: CGVector
        var halfWidth: CGFloat
        var bounded: Bool
        var clip: CGRect
        var sequence: Int
    }
    struct Result {
        var regions: [CGRect]
        var paints: [Paint] = []
        var unsupported: Bool
        var hasOnlyInvisibleText = false
        /// Some text-showing operator ran in invisible rendering mode 3 (an inherited OCR layer).
        var hasInvisibleText = false
        var textShows: [TextShow] = []
        var covers: [Cover] = []
        var slantedShows: [SlantedShow] = []
        /// Some text could not be placed on a horizontal baseline (rotated or vertical writing,
        /// clip-only rendering, unreadable operands): its visibility cannot be judged.
        var textPlacementUnsupported = false
    }
    /// Text state parameters; like the CTM they belong to the graphics state (`q`/`Q`).
    private struct TextParameters {
        var size: CGFloat = 0
        var characterSpacing: CGFloat = 0
        var wordSpacing: CGFloat = 0
        var horizontalScale: CGFloat = 1
        var leading: CGFloat = 0
        var rise: CGFloat = 0
        /// Type 3 glyph widths are arbitrary, so no lower bound follows a show in such a font.
        var unboundedAdvance = false
        var vertical = false
    }
    /// Whether a fill or image paints opaquely, from `gs` and the fill colour space.
    private struct Appearance {
        var fillAlpha: CGFloat = 1
        var normalBlend = true
        var noSoftMask = true
        var overprint = false
        var pattern = false
        var opaque: Bool { fillAlpha >= 1 && normalBlend && noSoftMask && !overprint }
    }
    private struct Saved {
        var matrix: CGAffineTransform, white: Bool, clip: CGRect, mode: Int
        var textClip: CGRect, coverClip: CGRect, text: TextParameters, appearance: Appearance
    }
    private final class State {
        var matrix = CGAffineTransform.identity
        var saved: [Saved] = []
        var textRenderingMode = 0
        var invisibleText = false
        var visibleText = false
        // Conservative page-space bounds, not a replacement for Core Graphics clipping.
        var clip = CGRect.zero
        var pendingClip = false
        var white = false
        var path = CGRect.null
        var pathIsRectangles = true
        // Marked-content nesting: true for a `/Figure` sequence, false for artifacts and
        // structural marks. Unbalanced marks are tolerated; they carry no paint of their own.
        var marks: [Bool] = []
        var figureDepth = 0
        var paints: [Paint] = []
        var unsupported = false
        var depth = 0
        var operations = 0
        var table: CGPDFOperatorTableRef?
        var resources: CGPDFDictionaryRef?
        var pageBounds = CGRect.zero

        // Text visibility evidence (#74, #85). `textClip` over-approximates the clip like
        // `clip`, but an empty clipping path leaves it unchanged, so it never invents hiding.
        // `coverClip` under-approximates it: only single axis-aligned rectangles stay exact.
        var textClip = CGRect.zero
        var coverClip = CGRect.zero
        var pathRectangles = 0
        var pathAxisAligned = true
        var text = TextParameters()
        var appearance = Appearance()
        var inText = false
        var lineMatrix = CGAffineTransform.identity
        /// Lower bound on the current point's x offset along the line, in unscaled text space.
        var textOffset: CGFloat = 0
        var positioned = false
        var chainStart: CGPoint?
        var clipsWithText = false
        var optionalContent: [Bool] = []
        var optionalDepth = 0
        var groupDepth = 0
        var sequence = 0
        var shows: [TextShow] = []
        var covers: [Cover] = []
        var slantedShows: [SlantedShow] = []
        var textPlacementUnsupported = false

        func accept() -> Bool {
            operations += 1
            if operations > 100_000 { unsupported = true; return false }
            return true
        }
        func finishPath() {
            if pendingClip {
                if !path.isNull && !path.isFinite { unsupported = true }
                else { clip = clip.intersection(path) }
                if !path.isNull && path.isFinite {
                    textClip = textClip.intersection(path)
                    coverClip = pathRectangles == 1 && pathIsRectangles && pathAxisAligned
                        ? coverClip.intersection(path) : .null
                }
            }
            pendingClip = false
            path = .null
            pathIsRectangles = true
            pathRectangles = 0
            pathAxisAligned = true
        }
        func save() -> Saved {
            Saved(matrix: matrix, white: white, clip: clip, mode: textRenderingMode, textClip: textClip,
                  coverClip: coverClip, text: text, appearance: appearance)
        }
        func restore(_ saved: Saved) {
            matrix = saved.matrix; white = saved.white; clip = saved.clip; textRenderingMode = saved.mode
            textClip = saved.textClip; coverClip = saved.coverClip; text = saved.text; appearance = saved.appearance
        }
        /// Records an opaque paint over `rect` (already in page space), if nothing can make it
        /// translucent or conditional.
        func cover(_ rect: CGRect) {
            guard appearance.opaque, optionalDepth == 0, groupDepth == 0, !coverClip.isNull,
                  rect.isFinite, !rect.isNull else { return }
            let painted = rect.intersection(coverClip)
            guard !painted.isNull, painted.width > 0, painted.height > 0 else { return }
            sequence += 1
            if covers.count < 10_000 { covers.append(Cover(rect: painted, sequence: sequence)) }
            else { textPlacementUnsupported = true }
        }
        /// Records one show's placement and advances the lower bound on the current point.
        /// `bytes` and `spaces` count the string's bytes and 0x20 bytes; `adjustment` is the sum
        /// of TJ numbers between them, in thousandths of text space.
        func show(bytes: Int, spaces: Int, adjustment: CGFloat) {
            guard inText else { textPlacementUnsupported = true; return }
            if textRenderingMode == 7 { textPlacementUnsupported = true }
            if textRenderingMode >= 4 { clipsWithText = true }
            let m = lineMatrix.concatenating(matrix)
            let scale = max(abs(m.a), abs(m.b), abs(m.c), abs(m.d))
            let forward = text.size * text.horizontalScale > 0
            sequence += 1
            if m.a > 0, m.d > 0, abs(m.b) <= scale * 1e-6, abs(m.c) <= scale * 1e-6, forward,
               text.size > 0, !text.vertical {
                let baseline = text.rise * m.d + m.ty
                let left = textOffset.isFinite ? textOffset * m.a + m.tx : -.infinity
                guard baseline.isFinite, !left.isNaN else { textPlacementUnsupported = true; return }
                let origin = positioned && left.isFinite ? CGPoint(x: left, y: baseline) : nil
                if let origin { chainStart = origin }
                if shows.count < 50_000 {
                    shows.append(TextShow(baseline: baseline, left: left, origin: origin,
                                          chainStart: chainStart, clip: textClip, sequence: sequence))
                } else { textPlacementUnsupported = true }
            } else {
                chainStart = nil
                // Rotated, mirrored or vertical text: a thick ray from the origin along the
                // writing direction (a whole line when the start is unknown). It never
                // anchors a hidden line; it only keeps every line it could touch.
                let origin = CGPoint(x: textOffset.isFinite ? textOffset : 0, y: text.rise).applying(m)
                var direction = text.vertical ? CGVector(dx: -m.c, dy: -m.d) : CGVector(dx: m.a, dy: m.b)
                if !text.vertical && text.horizontalScale < 0 { direction = CGVector(dx: -direction.dx, dy: -direction.dy) }
                let length = (direction.dx * direction.dx + direction.dy * direction.dy).squareRoot()
                let up = text.vertical ? (m.a * m.a + m.b * m.b).squareRoot() : (m.c * m.c + m.d * m.d).squareRoot()
                let halfWidth = 1.5 * abs(text.size) * max(up, 1e-9) + 1
                guard origin.x.isFinite, origin.y.isFinite, length > 0, halfWidth.isFinite, scale.isFinite else {
                    textPlacementUnsupported = true; return
                }
                if slantedShows.count < 10_000 {
                    slantedShows.append(SlantedShow(origin: origin,
                        direction: CGVector(dx: direction.dx / length, dy: direction.dy / length),
                        halfWidth: halfWidth, bounded: textOffset.isFinite && forward && !text.vertical,
                        clip: textClip, sequence: sequence))
                } else { textPlacementUnsupported = true }
            }
            positioned = false
            if text.unboundedAdvance || !forward || text.vertical { textOffset = -.infinity; return }
            // tx = ((w0 − Tj/1000) × Tfs + Tc + Tw) × Th with w0 ≥ 0 for every glyph.
            textOffset += (-adjustment / 1000 * text.size + min(0, text.characterSpacing) * CGFloat(bytes)
                + min(0, text.wordSpacing) * CGFloat(spaces)) * text.horizontalScale
        }
        func noteShow() {
            if textRenderingMode == 3 { invisibleText = true } else { visibleText = true }
        }
        /// A fill of exactly one axis-aligned rectangle in a solid colour covers that rectangle.
        func coverFill() {
            guard pathRectangles == 1, pathIsRectangles, pathAxisAligned, !appearance.pattern,
                  !path.isNull else { return }
            cover(path)
        }
        func moveLine(_ x: CGFloat, _ y: CGFloat) {
            guard inText else { textPlacementUnsupported = true; return }
            lineMatrix = CGAffineTransform(translationX: x, y: y).concatenating(lineMatrix)
            textOffset = 0
            positioned = true; chainStart = nil
        }
        func paint() {
            defer { finishPath() }
            guard accept(), !path.isNull else { return }
            guard let shown = visible(path.insetBy(dx: -2, dy: -2)) else { return }
            add(shown, frame: pathIsRectangles && figureDepth == 0)
        }
        /// The part of a footprint the clip in force lets show, or nil when none of it can. A
        /// path's or image's extent is not its ink: FAA illustrations draw streamlines, arrows and
        /// photographs far beyond the frame that clips them, into the neighbouring column (#98,
        /// #52), and a bleed rectangle can lie wholly outside its clip (page 361). The clip
        /// over-approximates the real clipping region, so no visible mark is lost.
        func visible(_ rect: CGRect) -> CGRect? {
            let shown = rect.intersection(clip)
            return shown.isNull || shown.isEmpty ? nil : shown
        }
        func add(_ rect: CGRect, frame: Bool = false) {
            if paints.count < 10_000 { paints.append(Paint(rect: rect, frame: frame)) }
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
            s.saved.append(s.save())
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = Self.state(info)
            if let saved = s.saved.popLast() { s.restore(saved) }
            else { s.unsupported = true }
        }
        Self.textCallbacks(table)
        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, info in
            let s = Self.state(info)
            var mode: CGPDFInteger = 0
            guard s.accept(), CGPDFScannerPopInteger(scanner, &mode), (0...7).contains(mode) else {
                s.unsupported = true; return
            }
            s.textRenderingMode = mode
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = Self.numbers(scanner, 6) else { s.unsupported = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
                .concatenating(s.matrix)
            s.chainStart = nil
        }
        CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
            let s = Self.state(info)
            s.white = Self.numbers(scanner, 3)?.allSatisfy { $0 >= 0.999 } ?? false
            s.appearance.pattern = false
        }
        CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
            let s = Self.state(info)
            s.white = (Self.numbers(scanner, 1)?.first ?? 0) >= 0.999
            s.appearance.pattern = false
        }
        CGPDFOperatorTableSetCallback(table, "k") { _, info in
            let s = Self.state(info)
            s.white = false; s.appearance.pattern = false
        }
        CGPDFOperatorTableSetCallback(table, "sc") { _, info in Self.state(info).white = false }
        CGPDFOperatorTableSetCallback(table, "scn") { scanner, info in
            let s = Self.state(info)
            s.white = false
            // A pattern fill names its pattern last; its cells can be transparent.
            var name: UnsafePointer<CChar>?
            if CGPDFScannerPopName(scanner, &name) { s.appearance.pattern = true }
        }
        CGPDFOperatorTableSetCallback(table, "cs") { scanner, info in
            Self.fillColorSpace(scanner, state: Self.state(info))
        }
        for op in ["m", "l"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                guard s.accept(), let n = Self.numbers(scanner, 2) else { s.unsupported = true; return }
                let point = CGPoint(x: n[0], y: n[1]).applying(s.matrix)
                s.pathIsRectangles = false
                s.path = s.path.union(CGRect(origin: point, size: .zero))
            }
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            let s = Self.state(info)
            guard s.accept(), let n = Self.numbers(scanner, 6) else { s.unsupported = true; return }
            s.pathIsRectangles = false
            for i in stride(from: 0, to: 6, by: 2) {
                s.path = s.path.union(CGRect(origin: CGPoint(x: n[i], y: n[i + 1])
                    .applying(s.matrix), size: .zero))
            }
        }
        for op in ["v", "y"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                guard s.accept(), let n = Self.numbers(scanner, 4) else { s.unsupported = true; return }
                s.pathIsRectangles = false
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
            s.pathRectangles += 1
            if !Self.axisAligned(s.matrix) { s.pathAxisAligned = false }
        }
        for op in ["S", "s", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).paint() }
        }
        for op in ["B", "B*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info)
                s.coverFill()
                s.paint()
            }
        }
        for op in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = Self.state(info)
                s.coverFill()
                if s.white { s.finishPath() } else { s.paint() }
            }
        }
        CGPDFOperatorTableSetCallback(table, "gs") { scanner, info in
            Self.graphicsState(scanner, state: Self.state(info))
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in Self.state(info).finishPath() }
        for op in ["W", "W*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).pendingClip = true }
        }
        // Marked content only classifies paint; it never changes what is preserved on its own.
        CGPDFOperatorTableSetCallback(table, "BDC") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            var property: CGPDFObjectRef?
            var label: UnsafePointer<CChar>?
            _ = CGPDFScannerPopObject(scanner, &property)
            let popped = CGPDFScannerPopName(scanner, &label)
            let figure = popped && label.map { String(cString: $0) == "Figure" } == true
            // Optional content may be hidden in the rendering; paint inside it hides nothing.
            let optional = !popped || label.map { String(cString: $0) == "OC" } == true
            if s.marks.count < 128 {
                s.marks.append(figure)
                s.optionalContent.append(optional)
                if optional { s.optionalDepth += 1 }
            } else { s.textPlacementUnsupported = true }
            if figure { s.figureDepth += 1 }
        }
        CGPDFOperatorTableSetCallback(table, "BMC") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            var label: UnsafePointer<CChar>?
            let figure = CGPDFScannerPopName(scanner, &label) && label.map { String(cString: $0) == "Figure" } == true
            if s.marks.count < 128 { s.marks.append(figure); s.optionalContent.append(false) }
            else { s.textPlacementUnsupported = true }
            if figure { s.figureDepth += 1 }
        }
        CGPDFOperatorTableSetCallback(table, "EMC") { _, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            if let optional = s.optionalContent.popLast(), optional { s.optionalDepth = max(0, s.optionalDepth - 1) }
            if let figure = s.marks.popLast(), figure { s.figureDepth = max(0, s.figureDepth - 1) }
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
                if let shown = s.visible(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.matrix)) { s.add(shown) }
                // Masked, soft-masked, stencil and optional images can leave what is beneath visible.
                var flag: CGPDFBoolean = 0
                var object: CGPDFObjectRef?
                if Self.axisAligned(s.matrix),
                   !CGPDFDictionaryGetObject(dictionary, "SMask", &object),
                   !CGPDFDictionaryGetObject(dictionary, "Mask", &object),
                   !CGPDFDictionaryGetObject(dictionary, "OC", &object),
                   !CGPDFDictionaryGetObject(dictionary, "SMaskInData", &object),
                   !(CGPDFDictionaryGetBoolean(dictionary, "ImageMask", &flag) && flag != 0) {
                    s.cover(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.matrix))
                }
            case "Form":
                let startCount = s.paints.count
                var object: CGPDFObjectRef?
                // A transparency group composites as a whole (knockout, isolation, its own
                // soft mask); nothing inside it is taken as an opaque cover.
                let group = CGPDFDictionaryGetObject(dictionary, "Group", &object)
                let optional = CGPDFDictionaryGetObject(dictionary, "OC", &object)
                if group { s.groupDepth += 1 }
                if optional { s.optionalDepth += 1 }
                Self.descend(stream, dictionary: dictionary, parent: parent, state: s)
                if group { s.groupDepth -= 1 }
                if optional { s.optionalDepth -= 1 }
                // A bounded form can be one composite illustration with detached labels. Keep
                // those labels with it. Whole-page form wrappers are not treated as figures.
                var box: CGPDFArrayRef?
                if s.paints.count > startCount,
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
                        // Only the part of the box inside the clip in force can show: a figure
                        // group whose box overhangs its rounded frame into the prose above it
                        // (FAA page 227) must not claim that prose (#77). The clip is a
                        // conservative bounding rectangle, so no visible mark is excluded.
                        var rect = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1])
                            .applying(transform.concatenating(s.matrix))
                        let visible = rect.intersection(s.clip)
                        if !visible.isNull, !visible.isEmpty { rect = visible }
                        if rect.isFinite, rect.width * rect.height < s.pageBounds.width * s.pageBounds.height * 0.7 {
                            s.add(rect)
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
        s.textClip = s.pageBounds
        s.coverClip = s.pageBounds
        if let dictionary = page.dictionary {
            CGPDFDictionaryGetDictionary(dictionary, "Resources", &s.resources)
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        scan(stream, state: s)
        let bounds = page.getBoxRect(.cropBox)
        // A mark wholly off the page (FAA pages 474–475 place a two-page illustration across
        // both, #99) shows nothing; its intersection is the infinite null rectangle, not a paint.
        let paints = s.paints.compactMap { paint -> Paint? in
            let visible = paint.rect.intersection(bounds)
            return visible.isNull ? nil : Paint(rect: visible, frame: paint.frame)
        }
        return Result(regions: clusters(paints.map(\.rect), distance: 4), paints: paints,
                      unsupported: s.unsupported, hasOnlyInvisibleText: !s.unsupported && s.invisibleText && !s.visibleText,
                      hasInvisibleText: s.invisibleText, textShows: s.shows, covers: s.covers, slantedShows: s.slantedShows,
                      textPlacementUnsupported: s.textPlacementUnsupported || s.inText)
    }

    static func axisAligned(_ m: CGAffineTransform) -> Bool {
        let scale = max(abs(m.a), abs(m.b), abs(m.c), abs(m.d))
        return scale > 0 && ((abs(m.b) <= scale * 1e-6 && abs(m.c) <= scale * 1e-6)
            || (abs(m.a) <= scale * 1e-6 && abs(m.d) <= scale * 1e-6))
    }

    /// Text positioning and showing: enough to place every show on its baseline (#74, #85).
    /// Glyph widths are never decoded; only lower bounds on the current point are kept.
    private static func textCallbacks(_ table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            let s = Self.state(info)
            if s.inText { s.textPlacementUnsupported = true }
            s.inText = true; s.lineMatrix = .identity; s.textOffset = 0; s.positioned = true; s.chainStart = nil
        }
        CGPDFOperatorTableSetCallback(table, "ET") { _, info in
            let s = Self.state(info)
            if !s.inText { s.textPlacementUnsupported = true }
            s.inText = false; s.positioned = false
            // Clipping render modes add glyph outlines to the clip: no longer one rectangle.
            if s.clipsWithText { s.coverClip = .null; s.clipsWithText = false }
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let s = Self.state(info)
            guard s.inText, let n = Self.numbers(scanner, 6) else { s.textPlacementUnsupported = true; return }
            s.lineMatrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            s.textOffset = 0; s.positioned = true; s.chainStart = nil
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 2) else { s.textPlacementUnsupported = true; return }
            s.moveLine(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 2) else { s.textPlacementUnsupported = true; return }
            s.text.leading = -n[1]; s.moveLine(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            let s = Self.state(info)
            s.moveLine(0, -s.text.leading)
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 1) else { s.textPlacementUnsupported = true; return }
            s.text.leading = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 1) else { s.textPlacementUnsupported = true; return }
            s.text.characterSpacing = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tw") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 1) else { s.textPlacementUnsupported = true; return }
            s.text.wordSpacing = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 1) else { s.textPlacementUnsupported = true; return }
            s.text.rise = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            let s = Self.state(info)
            guard let n = Self.numbers(scanner, 1) else { s.textPlacementUnsupported = true; return }
            s.text.horizontalScale = n[0] / 100
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?
            guard let n = Self.numbers(scanner, 1), CGPDFScannerPopName(scanner, &name), let name else {
                s.textPlacementUnsupported = true; return
            }
            s.text.size = n[0]
            s.text.unboundedAdvance = true
            s.text.vertical = false
            var dictionary: CGPDFDictionaryRef?
            guard let font = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name),
                  CGPDFObjectGetValue(font, .dictionary, &dictionary), let dictionary else { return }
            var subtype: UnsafePointer<CChar>?
            let type = CGPDFDictionaryGetName(dictionary, "Subtype", &subtype) ? subtype.map { String(cString: $0) } : nil
            s.text.unboundedAdvance = type == nil || type == "Type3"
            // Vertical writing advances down the page: a composite font with a vertical CMap.
            var encoding: UnsafePointer<CChar>?
            var cmap: CGPDFStreamRef?
            if CGPDFDictionaryGetName(dictionary, "Encoding", &encoding), let encoding {
                s.text.vertical = String(cString: encoding).hasSuffix("-V")
            } else if CGPDFDictionaryGetStream(dictionary, "Encoding", &cmap), let cmap,
                      let cmapDictionary = CGPDFStreamGetDictionary(cmap) {
                var mode: CGPDFInteger = 0
                s.text.vertical = CGPDFDictionaryGetInteger(cmapDictionary, "WMode", &mode) && mode != 0
            }
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            s.noteShow()
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { s.textPlacementUnsupported = true; return }
            let (bytes, spaces) = Self.count(string)
            s.show(bytes: bytes, spaces: spaces, adjustment: 0)
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            s.noteShow()
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { s.textPlacementUnsupported = true; return }
            s.moveLine(0, -s.text.leading)
            let (bytes, spaces) = Self.count(string)
            s.show(bytes: bytes, spaces: spaces, adjustment: 0)
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            s.noteShow()
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string, let n = Self.numbers(scanner, 2) else {
                s.textPlacementUnsupported = true; return
            }
            s.text.wordSpacing = n[0]; s.text.characterSpacing = n[1]
            s.moveLine(0, -s.text.leading)
            let (bytes, spaces) = Self.count(string)
            s.show(bytes: bytes, spaces: spaces, adjustment: 0)
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            let s = Self.state(info)
            guard s.accept() else { return }
            s.noteShow()
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { s.textPlacementUnsupported = true; return }
            var bytes = 0, spaces = 0
            var adjustment: CGFloat = 0
            var leading: CGFloat = 0
            for index in 0..<CGPDFArrayGetCount(array) {
                var number: CGPDFReal = 0
                var string: CGPDFStringRef?
                if CGPDFArrayGetNumber(array, index, &number), number.isFinite {
                    // A number before the first string moves the first glyph off the origin.
                    if bytes == 0 { leading += number } else { adjustment += number }
                } else if CGPDFArrayGetString(array, index, &string), let string {
                    let counted = Self.count(string)
                    bytes += counted.0; spaces += counted.1
                } else { s.textPlacementUnsupported = true; return }
            }
            // A number before any glyph is an exact displacement, so a known start stays known.
            if leading != 0 { s.textOffset += -leading / 1000 * s.text.size * s.text.horizontalScale }
            s.show(bytes: bytes, spaces: spaces, adjustment: adjustment)
        }
    }

    private static func count(_ string: CGPDFStringRef) -> (Int, Int) {
        let length = CGPDFStringGetLength(string)
        guard let pointer = CGPDFStringGetBytePtr(string) else { return (length, 0) }
        var spaces = 0
        for i in 0..<length where pointer[i] == 0x20 { spaces += 1 }
        return (length, spaces)
    }

    /// `gs`: the entries that decide whether a later fill or image hides what is beneath it.
    private static func graphicsState(_ scanner: CGPDFScannerRef, state s: State) {
        var name: UnsafePointer<CChar>?
        var dictionary: CGPDFDictionaryRef?
        guard CGPDFScannerPopName(scanner, &name), let name,
              let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ExtGState", name),
              CGPDFObjectGetValue(resource, .dictionary, &dictionary), let dictionary else {
            // An unreadable state could make anything translucent.
            s.appearance.fillAlpha = 0; return
        }
        var object: CGPDFObjectRef?
        var number: CGPDFReal = 0
        if CGPDFDictionaryGetObject(dictionary, "ca", &object) {
            s.appearance.fillAlpha = CGPDFDictionaryGetNumber(dictionary, "ca", &number) && number.isFinite ? number : 0
        }
        if CGPDFDictionaryGetObject(dictionary, "BM", &object) {
            var blend: UnsafePointer<CChar>?
            var modes: CGPDFArrayRef?
            if CGPDFDictionaryGetName(dictionary, "BM", &blend), let blend {
                s.appearance.normalBlend = ["Normal", "Compatible"].contains(String(cString: blend))
            } else if CGPDFDictionaryGetArray(dictionary, "BM", &modes), let modes,
                      CGPDFArrayGetName(modes, 0, &blend), let blend {
                s.appearance.normalBlend = ["Normal", "Compatible"].contains(String(cString: blend))
            } else { s.appearance.normalBlend = false }
        }
        if CGPDFDictionaryGetObject(dictionary, "SMask", &object) {
            var mask: UnsafePointer<CChar>?
            s.appearance.noSoftMask = CGPDFDictionaryGetName(dictionary, "SMask", &mask)
                && mask.map { String(cString: $0) == "None" } == true
        }
        var flag: CGPDFBoolean = 0
        if CGPDFDictionaryGetObject(dictionary, "op", &object) {
            s.appearance.overprint = !CGPDFDictionaryGetBoolean(dictionary, "op", &flag) || flag != 0
        } else if CGPDFDictionaryGetObject(dictionary, "OP", &object) {
            // `OP` also sets fill overprint when `op` is absent.
            s.appearance.overprint = !CGPDFDictionaryGetBoolean(dictionary, "OP", &flag) || flag != 0
        }
        // A font set through the graphics state is not followed; its shows cannot be placed.
        if CGPDFDictionaryGetObject(dictionary, "Font", &object) { s.textPlacementUnsupported = true }
    }

    /// `cs`: a pattern colour space makes later fills unable to cover anything.
    private static func fillColorSpace(_ scanner: CGPDFScannerRef, state s: State) {
        var name: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &name), let name else { s.appearance.pattern = true; return }
        let space = String(cString: name)
        if ["DeviceGray", "DeviceRGB", "DeviceCMYK"].contains(space) { s.appearance.pattern = false; return }
        if space == "Pattern" { s.appearance.pattern = true; return }
        var array: CGPDFArrayRef?
        var family: UnsafePointer<CChar>?
        guard let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ColorSpace", name) else {
            s.appearance.pattern = true; return
        }
        if CGPDFObjectGetValue(resource, .array, &array), let array,
           CGPDFArrayGetName(array, 0, &family), let family {
            s.appearance.pattern = String(cString: family) == "Pattern"
        } else if CGPDFObjectGetValue(resource, .name, &family), let family {
            s.appearance.pattern = String(cString: family) == "Pattern"
        } else {
            s.appearance.pattern = true
        }
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
        guard region.isFinite, s.paints.count < 10_000 else { s.unsupported = true; return }
        // Without a tighter bound, preserve the page rather than inventing a small crop.
        guard region.width * region.height < s.pageBounds.width * s.pageBounds.height * 0.75 else {
            s.unsupported = true; return
        }
        s.add(region.insetBy(dx: -2, dy: -2).intersection(s.pageBounds))
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
        let oldTextRenderingMode = s.textRenderingMode
        let oldClip = s.clip, oldPendingClip = s.pendingClip
        let oldMarks = s.marks, oldFigureDepth = s.figureDepth, oldRectangles = s.pathIsRectangles
        let oldGraphics = s.save(), oldPathRectangles = s.pathRectangles, oldAxisAligned = s.pathAxisAligned
        let oldOptional = s.optionalContent, oldOptionalDepth = s.optionalDepth
        let oldInText = s.inText, oldLineMatrix = s.lineMatrix, oldOffset = s.textOffset
        let oldPositioned = s.positioned, oldClipsWithText = s.clipsWithText, oldChainStart = s.chainStart
        defer {
            s.matrix = oldMatrix; s.path = oldPath; s.saved = oldSaved; s.white = oldWhite
            s.textRenderingMode = oldTextRenderingMode
            s.resources = oldResources; s.clip = oldClip; s.pendingClip = oldPendingClip; s.depth -= 1
            // A form's marks are its own; the caller's figure nesting still applies inside it.
            s.marks = oldMarks; s.figureDepth = oldFigureDepth; s.pathIsRectangles = oldRectangles
            // A form's graphics and text state never leak into its caller.
            if s.inText { s.textPlacementUnsupported = true }
            s.restore(oldGraphics); s.pathRectangles = oldPathRectangles; s.pathAxisAligned = oldAxisAligned
            s.optionalContent = oldOptional; s.optionalDepth = oldOptionalDepth
            s.inText = oldInText; s.lineMatrix = oldLineMatrix; s.textOffset = oldOffset
            s.positioned = oldPositioned; s.clipsWithText = oldClipsWithText; s.chainStart = oldChainStart
        }
        s.depth += 1
        s.saved = []
        s.path = .null
        s.pathIsRectangles = true
        s.pathRectangles = 0
        s.pathAxisAligned = true
        s.marks = []
        s.optionalContent = []
        s.inText = false
        s.clipsWithText = false
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
            s.chainStart = nil
        }
        guard let box = rectangle(dictionary, key: "BBox") else { s.unsupported = true; return }
        let transformed = box.applying(s.matrix)
        guard transformed.isFinite else { s.unsupported = true; return }
        s.clip = s.clip.intersection(transformed)
        s.textClip = s.textClip.intersection(transformed)
        s.coverClip = Self.axisAligned(s.matrix) ? s.coverClip.intersection(transformed) : .null
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
        guard let resources = resources ?? s.resources else { s.unsupported = true; return }
        s.resources = resources
        let content = CGPDFContentStreamCreateWithStream(form, resources, parent)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, state: s)
    }
}
