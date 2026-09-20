import CoreGraphics

/// Decides, per emitted image, whether lossy encoding may be used (#193).
///
/// A port of the survey's prototype (`measurements/image-encoding/classifier.py`). The damage
/// ImageIO's JPEG does below quality 1.00 is chroma subsampling, identical at 0.95 and 0.90, so
/// what the classifier looks for is fine detail *in color*: colored labels, chart keys, seal
/// lettering. An image with no chroma to lose takes JPEG safely whatever it depicts; tonal
/// content (photographs, painted art, photographs of a page) hides the subsampling in its own
/// gradients; drawn colored matter is kept lossless. The classifier only says whether lossy is
/// *permitted*: `.smallest` still keeps whichever encoding is smaller, so a permitted image may
/// end up PNG.
enum ImageContentClassifier {
    /// What the image is for. A supplementary page reference is a picture of a page whose text is
    /// reflowed beside it; a region crop is often the only copy of a figure, and a required
    /// full-page fallback is the only copy of its page, so the converter judges it as `.region`
    /// (the survey measured fallbacks as preserved regions too).
    enum Role: Sendable, Equatable { case page, region }

    enum ContentClass: String, Sendable, Equatable, CaseIterable {
        case photograph = "photograph"
        case continuousTone = "continuous-tone art"
        case lineArt = "line art or chart"
        case bilevelScan = "text page (bilevel scan)"
        case tonalScan = "text page (tonal scan)"
        case bornDigitalText = "text page (born-digital)"
        case mixed = "mixed"
    }

    /// Raster-only features, named as in the prototype.
    struct Features: Sendable, Equatable {
        var width = 0, height = 0
        /// The modal color: the image's ground.
        var background: (red: Int, green: Int, blue: Int) = (255, 255, 255)
        /// Share within 10 levels of the ground in every channel.
        var backgroundShare = 0.0
        /// Share whose hue (R−G, G−B) differs from the ground's by 24 levels or more.
        var chromaShare = 0.0
        /// Share that is only ever ground (within 32 levels) or ink (110 levels darker).
        var bilevelShare = 0.0
        var distinctColours = 0
        /// Share with no neighbor differing at all, a step edge (≥ 64 levels) or a ramp (6–63).
        var flatShare = 0.0, hardEdgeShare = 0.0, softEdgeShare = 0.0

        var hardRatio: Double {
            hardEdgeShare + softEdgeShare > 0 ? hardEdgeShare / (hardEdgeShare + softEdgeShare) : 0
        }

        static func == (a: Features, b: Features) -> Bool {
            a.width == b.width && a.height == b.height && a.background == b.background
                && a.backgroundShare == b.backgroundShare && a.chromaShare == b.chromaShare
                && a.bilevelShare == b.bilevelShare && a.distinctColours == b.distinctColours
                && a.flatShare == b.flatShare && a.hardEdgeShare == b.hardEdgeShare
                && a.softEdgeShare == b.softEdgeShare
        }
    }

    struct Verdict: Sendable, Equatable {
        var contentClass: ContentClass
        var lossyPermitted: Bool
        var features: Features
    }

    /// The encoding to hand `PageRasterizer.encode`: the requested one, unless it is
    /// `.automatic`, which becomes `.smallest` where lossy is permitted and `.png` elsewhere.
    /// `features` is evaluated only for `.automatic`; the pipeline passes what it measured on the
    /// raster's own buffer while drawing it (`PageRasterizer.image(inspect:)`).
    static func resolve(_ requested: ConversionOptions.ImageEncoding, role: Role, pageDrawnFromImage: Bool,
                        features measured: @autoclosure () -> Features) -> ConversionOptions.ImageEncoding {
        guard case .automatic(let quality) = requested else { return requested }
        return judge(measured(), role: role, pageDrawnFromImage: pageDrawnFromImage).lossyPermitted
            ? .smallest(jpegQuality: quality) : .png
    }

    static func resolve(_ requested: ConversionOptions.ImageEncoding, image: CGImage, role: Role,
                        pageDrawnFromImage: Bool) -> ConversionOptions.ImageEncoding {
        resolve(requested, role: role, pageDrawnFromImage: pageDrawnFromImage, features: features(of: image))
    }

    static func judge(_ image: CGImage, role: Role, pageDrawnFromImage: Bool) -> Verdict {
        judge(features(of: image), role: role, pageDrawnFromImage: pageDrawnFromImage)
    }

    static func judge(_ measured: Features, role: Role, pageDrawnFromImage: Bool) -> Verdict {
        let contentClass = classify(measured, role: role, pageDrawnFromImage: pageDrawnFromImage)
        return Verdict(contentClass: contentClass,
                       lossyPermitted: lossyIsSafe(contentClass, measured, role: role), features: measured)
    }

    /// `classifier.classify`. `pageDrawnFromImage` stands for the prototype's page evidence: a
    /// page whose type arrives inside an image (the image-backed-page signal) or that has no text
    /// layer at all is a scan; one drawing its own text is born-digital. The prototype's second
    /// photograph test (ramp-dominated over a JPEG XObject) is omitted: every image it admits
    /// already satisfies the continuous-tone test that follows it, and both classes permit lossy.
    static func classify(_ f: Features, role: Role, pageDrawnFromImage: Bool) -> ContentClass {
        let flat = f.flatShare, hard = f.hardEdgeShare, soft = f.softEdgeShare
        let ratio = f.hardRatio, color = f.chromaShare, ground = f.backgroundShare
        // Two-tone enough that a lossless coder has almost nothing to carry.
        let drawn = f.bilevelShare >= 0.95 && f.distinctColours <= 4_096

        // 1. Mostly one ground color, one hue, carrying step edges and almost no ramps: type.
        if ground >= 0.20 && color < 0.10 && soft < 0.15 && ratio >= 0.40 && hard >= 0.01 {
            guard role == .page else { return .lineArt }
            if pageDrawnFromImage { return drawn ? .bilevelScan : .tonalScan }
            return .bornDigitalText
        }
        // 2. Few enough colors, on a flat enough ground, to be drawn rather than captured.
        if f.distinctColours <= 4_096 && flat >= 0.30 { return .lineArt }
        // 3. Captured tone: almost nothing flat, ramps everywhere, no ground to speak of.
        if flat <= 0.12 && soft >= 0.30 && ground <= 0.15 { return .photograph }
        // 4. Drawn tone: gradients and washes, but flat fields and hard outlines survive.
        if soft >= 0.20 && ground <= 0.55 && flat <= 0.55 { return .continuousTone }
        // 5. Drawn: hard edges dominate what edge there is, on a flat ground.
        if ratio >= 0.40 && flat >= 0.45 { return .lineArt }
        return .mixed
    }

    /// `classifier.lossy_is_safe`: neutral images (chroma share under 2%), tonal content and
    /// full-page `mixed` references permit lossy; colored line art, charts, `mixed` crops, and
    /// colored bilevel or born-digital text pages do not.
    ///
    /// One tightening over the prototype: a continuous-tone *crop* that is at least 30% perfectly
    /// flat is drawn illustration, not captured tone (no corpus photograph reaches that share),
    /// and its saturated fills and labels meet at hard colored edges that subsampling smears.
    /// The survey's worst case, the FAA attitude indicator, is one; so are the FAA's magnetic
    /// pole map and a NOAA crop at 55.7 levels. Such crops stay PNG
    /// (measurements/image-encoding-default/record.md).
    static func lossyIsSafe(_ contentClass: ContentClass, _ f: Features, role: Role) -> Bool {
        if f.chromaShare < 0.02 { return true }
        switch contentClass {
        case .photograph, .tonalScan: return true
        case .continuousTone: return role == .page || f.flatShare < drawnIllustrationFlatShare
        case .mixed: return role == .page
        case .lineArt, .bilevelScan, .bornDigitalText: return false
        }
    }

    /// The flat share at which a continuous-tone crop counts as drawn illustration: the same
    /// constant as the line-art test's "flat fields".
    static let drawnIllustrationFlatShare = 0.30

    // MARK: - Features

    /// Features of any `CGImage`. Reading a `CGImage`'s pixels copies them (`CGDataProvider.data`
    /// duplicates even a bitmap context's image, 23 MiB for a 6-megapixel raster), so the
    /// converter measures the context's buffer before making the image instead; this entry point
    /// serves `PageRasterizer.encode` called without that measurement, and tests.
    static func features(of image: CGImage) -> Features {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return Features() }
        if let data = directBytes(image), let pointer = CFDataGetBytePtr(data) {
            return features(UnsafeBufferPointer(start: pointer, count: CFDataGetLength(data)),
                            width: width, height: height, bytesPerRow: image.bytesPerRow)
        }
        // Any other layout: draw into RGBA8 over white, as the rasterizer does.
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 255, count: bytesPerRow * height)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return Features() }
        return buffer.withUnsafeBufferPointer {
            features($0, width: width, height: height, bytesPerRow: bytesPerRow)
        }
    }

    /// The raster's own bytes when they are 8-bit RGB(A/X) in memory order with opaque alpha,
    /// which is what `PageRasterizer.image` makes.
    private static func directBytes(_ image: CGImage) -> CFData? {
        let alpha = image.alphaInfo
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.bitmapInfo.intersection(.byteOrderMask).rawValue == 0,
              alpha == .premultipliedLast || alpha == .noneSkipLast || alpha == .last,
              image.colorSpace?.model == .rgb else { return nil }
        return image.dataProvider?.data
    }

    /// RGBA8 (or RGBX8) rows, alpha ignored. One pass for the gradient shares, the distinct
    /// colors and a coarse histogram; one pass per batch of 16 coarse (4-bit) bins, most
    /// populated first, counting exact colors until no unexamined bin could hold more than the
    /// best found, which makes the modal color exact against the prototype; one pass for the
    /// shares measured against that ground. Transient memory is a 2 MiB distinct-color bitset,
    /// three rows of gray and 512 KiB of exact counts, whatever the raster's size.
    static func features(_ bytes: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                         bytesPerRow: Int) -> Features {
        let count = width * height
        precondition(bytes.count >= (height - 1) * bytesPerRow + width * 4)
        @inline(__always) func gray(_ offset: Int) -> Float {
            // numpy: float64 arithmetic, then cast to float32.
            Float(0.299 * Double(bytes[offset]) + 0.587 * Double(bytes[offset + 1])
                  + 0.114 * Double(bytes[offset + 2]))
        }
        @inline(__always) func packed(_ offset: Int) -> Int {
            Int(bytes[offset]) << 16 | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
        }
        @inline(__always) func coarse(_ color: Int) -> Int {
            (color >> 12 & 0xF00) | (color >> 8 & 0xF0) | (color >> 4 & 0xF)
        }
        @inline(__always) func fine(_ color: Int) -> Int {
            (color >> 8 & 0xF00) | (color >> 4 & 0xF0) | (color & 0xF)
        }

        // Pass 1: distinct colors, coarse histogram, and the neighbor-gradient shares.
        var seen = [UInt64](repeating: 0, count: 1 << 18)
        var coarseCounts = [Int](repeating: 0, count: 4_096)
        var flat = 0, hard = 0, soft = 0
        var above = [Float](repeating: 0, count: width)
        var row = [Float](repeating: 0, count: width)
        var below = [Float](repeating: 0, count: width)
        for x in 0..<width { row[x] = gray(x * 4) }
        seen.withUnsafeMutableBufferPointer { seen in
            coarseCounts.withUnsafeMutableBufferPointer { coarseCounts in
                for y in 0..<height {
                    let base = y * bytesPerRow
                    if y + 1 < height {
                        let next = base + bytesPerRow
                        for x in 0..<width { below[x] = gray(next + x * 4) }
                    }
                    for x in 0..<width {
                        let color = packed(base + x * 4)
                        seen[color >> 6] |= 1 << UInt64(color & 63)
                        coarseCounts[coarse(color)] += 1
                        let g = row[x]
                        var gradient: Float = 0
                        if x + 1 < width { gradient = max(gradient, abs(row[x + 1] - g)) }
                        if x > 0 { gradient = max(gradient, abs(g - row[x - 1])) }
                        if y + 1 < height { gradient = max(gradient, abs(below[x] - g)) }
                        if y > 0 { gradient = max(gradient, abs(g - above[x])) }
                        if gradient == 0 { flat += 1 } else if gradient >= 64 { hard += 1 } else if gradient >= 6 { soft += 1 }
                    }
                    swap(&above, &row)
                    swap(&row, &below)
                }
            }
        }
        let distinct = seen.reduce(0) { $0 + $1.nonzeroBitCount }

        // Pass 2+: the exact modal color. Ties go to the lowest packed value, as np.unique's
        // sorted order and argmax give.
        let order = (0..<4_096).filter { coarseCounts[$0] > 0 }
            .sorted { coarseCounts[$0] != coarseCounts[$1] ? coarseCounts[$0] > coarseCounts[$1] : $0 < $1 }
        var modal = 0, modalCount = 0, next = 0
        let batch = 16
        while next < order.count, coarseCounts[order[next]] >= max(modalCount, 1) {
            let bins = Array(order[next..<min(order.count, next + batch)])
            var slot = [Int](repeating: -1, count: 4_096)
            for (index, bin) in bins.enumerated() { slot[bin] = index }
            var counts = [Int](repeating: 0, count: bins.count * 4_096)
            for y in 0..<height {
                let base = y * bytesPerRow
                for x in 0..<width {
                    let color = packed(base + x * 4)
                    let s = slot[coarse(color)]
                    if s >= 0 { counts[s * 4_096 + fine(color)] += 1 }
                }
            }
            for (index, bin) in bins.enumerated() {
                for low in 0..<4_096 where counts[index * 4_096 + low] > 0 {
                    let color = (bin & 0xF00) << 12 | (low & 0xF00) << 8 | (bin & 0xF0) << 8
                        | (low & 0xF0) << 4 | (bin & 0xF) << 4 | (low & 0xF)
                    let n = counts[index * 4_096 + low]
                    if n > modalCount || (n == modalCount && color < modal) { modal = color; modalCount = n }
                }
            }
            next += bins.count
        }
        let groundRed = modal >> 16 & 255, groundGreen = modal >> 8 & 255, groundBlue = modal & 255
        let groundGray = 0.299 * Double(groundRed) + 0.587 * Double(groundGreen) + 0.114 * Double(groundBlue)
        let groundHue = (groundRed - groundGreen, groundGreen - groundBlue)

        // Last pass: shares measured against the ground.
        var background = 0, chroma = 0, nearGround = 0, ink = 0
        for y in 0..<height {
            let base = y * bytesPerRow
            for x in 0..<width {
                let offset = base + x * 4
                let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                let distance = max(abs(r - groundRed), abs(g - groundGreen), abs(b - groundBlue))
                if distance <= 10 { background += 1 }
                if distance <= 32 { nearGround += 1 }
                if max(abs(r - g - groundHue.0), abs(g - b - groundHue.1)) >= 24 { chroma += 1 }
                if Double(gray(offset)) < groundGray - 110 { ink += 1 }
            }
        }
        let total = Double(count)
        return Features(width: width, height: height, background: (groundRed, groundGreen, groundBlue),
                        backgroundShare: Double(background) / total, chromaShare: Double(chroma) / total,
                        bilevelShare: min(1, Double(nearGround) / total + Double(ink) / total),
                        distinctColours: distinct, flatShare: Double(flat) / total,
                        hardEdgeShare: Double(hard) / total, softEdgeShare: Double(soft) / total)
    }
}
