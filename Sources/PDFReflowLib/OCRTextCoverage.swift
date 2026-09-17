import Accelerate
import CoreGraphics

/// Checks a recognized page for text Vision silently left out (#116).
///
/// A compile of Vision's document models can drop whole paragraphs while reporting success
/// (`measurements/ocr-text-loss/record.md`). The check reuses the raster Vision just read, so it
/// needs no second recognition. It finds rows of glyph-sized ink (connected components of similar
/// height side by side, the shape of printed or typed text) and measures how much of that ink
/// lies outside every recognized line box. Artwork, rules, fills and speckle rarely form such rows,
/// so sparse or illustrated pages keep a low uncovered share when recognition is complete.
enum OCRTextCoverage {
    struct Measurement: Equatable, Sendable {
        /// Rows of glyph-sized ink found on the page, outside excluded regions.
        var textRows = 0
        /// Rows whose ink lies mostly outside the recognized line boxes.
        var uncoveredRows = 0
        /// Dark pixels in text rows, and those outside the recognized line boxes.
        var textInk = 0
        var uncoveredInk = 0
        /// Pixel boxes (top-left origin) of uncovered rows, collected only when requested.
        var uncoveredRowBoxes: [CGRect] = []

        var uncoveredFraction: Double { textInk == 0 ? 0 : Double(uncoveredInk) / Double(textInk) }

        /// Whether the recognized lines miss enough text-shaped ink to suggest dropped text.
        var indicatesLoss: Bool {
            uncoveredRows >= OCRTextCoverage.minimumUncoveredRows
                && uncoveredFraction >= OCRTextCoverage.minimumUncoveredFraction
        }
    }

    static let minimumUncoveredRows = 8
    static let minimumUncoveredFraction = 0.2

    /// - Parameters:
    ///   - image: the raster that was recognized.
    ///   - lines: recognized line boxes, normalized with a lower-left origin (Vision's convention).
    ///   - excluded: normalized regions whose ink is not counted (table regions that become images).
    ///   - pixelsPerPoint: raster pixels per PDF point.
    static func measure(image: CGImage, lines: [CGRect], excluded: [CGRect] = [],
                        pixelsPerPoint: Double) -> Measurement {
        guard let gray = GrayRaster(image) else { return Measurement() }
        return measure(gray, lines: lines, excluded: excluded, pixelsPerPoint: pixelsPerPoint)
    }

    static func measure(_ raster: GrayRaster, lines: [CGRect], excluded: [CGRect],
                        pixelsPerPoint: Double, collectBoxes: Bool = false,
                        minimumGlyphs: Int = 5) -> Measurement {
        let width = raster.width, height = raster.height
        guard width > 0, height > 0, pixelsPerPoint > 0 else { return Measurement() }
        let threshold = raster.inkThreshold()
        let components = raster.components(darkerThan: threshold)

        // Glyph-sized: 2.5–40 pt tall (a lowercase letter of 5 pt text to a large title), not a
        // long rule or a filled block, and not a hairline frame.
        let minimumHeight = max(4, Int((2.5 * pixelsPerPoint).rounded()))
        let maximumHeight = Int((40 * pixelsPerPoint).rounded())
        func pixelRect(_ normalized: CGRect) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            (Int((normalized.minX * Double(width)).rounded(.down)),
             Int(((1 - normalized.maxY) * Double(height)).rounded(.down)),
             Int((normalized.maxX * Double(width)).rounded(.up)),
             Int(((1 - normalized.minY) * Double(height)).rounded(.up)))
        }
        let excludedRects = excluded.map(pixelRect)
        let glyphs = components.filter { c in
            let w = c.maxX - c.minX + 1, h = c.maxY - c.minY + 1
            guard h >= minimumHeight, h <= maximumHeight, w <= h * 12 else { return false }
            let density = Double(c.pixels) / Double(w * h)
            guard density >= 0.08, density <= 0.9 else { return false }
            let cx = (c.minX + c.maxX) / 2, cy = (c.minY + c.maxY) / 2
            return !excludedRects.contains { cx >= $0.minX && cx <= $0.maxX && cy >= $0.minY && cy <= $0.maxY }
        }
        guard !glyphs.isEmpty else { return Measurement() }

        // Join glyphs into rows: vertically overlapping, similar height, horizontally close.
        var parent = Array(glyphs.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let cell = max(8, maximumHeight / 2)
        var buckets: [Int: [Int]] = [:]
        for (index, g) in glyphs.enumerated() {
            let h = g.maxY - g.minY + 1
            let reach = h * 3 / 2
            for bx in max(0, g.minX - reach) / cell...(g.maxX + reach) / cell {
                for by in g.minY / cell...g.maxY / cell {
                    buckets[bx << 20 | by, default: []].append(index)
                }
            }
        }
        for members in buckets.values where members.count > 1 {
            for a in 0..<members.count {
                let i = members[a], p = glyphs[i]
                let ph = p.maxY - p.minY + 1
                for b in (a + 1)..<members.count {
                    let j = members[b], q = glyphs[j]
                    let qh = q.maxY - q.minY + 1
                    let overlap = min(p.maxY, q.maxY) - max(p.minY, q.minY) + 1
                    guard overlap * 2 >= min(ph, qh), max(ph, qh) * 2 <= min(ph, qh) * 5 else { continue }
                    let gap = max(p.minX, q.minX) - min(p.maxX, q.maxX)
                    guard gap <= max(ph, qh) * 3 / 2 else { continue }
                    let ri = find(i), rj = find(j)
                    if ri != rj { parent[ri] = rj }
                }
            }
        }

        // Recognized line boxes, grown slightly: Vision's boxes can clip ascenders and descenders.
        var covered = [Bool](repeating: false, count: width * height / 16 + width / 4 + height / 4 + 2)
        let coverWidth = width / 4 + 1
        for line in lines {
            let r = pixelRect(line)
            let lineHeight = max(1, r.maxY - r.minY)
            let dx = lineHeight / 2, dy = lineHeight / 3
            let x0 = max(0, r.minX - dx) / 4, x1 = min(width - 1, r.maxX + dx) / 4
            let y0 = max(0, r.minY - dy) / 4, y1 = min(height - 1, r.maxY + dy) / 4
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { covered[y * coverWidth + x] = true } }
        }

        struct Row { var count = 0, ink = 0, uncoveredInk = 0
                     var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min }
        var rows: [Int: Row] = [:]
        for (index, g) in glyphs.enumerated() {
            let cx = (g.minX + g.maxX) / 2, cy = (g.minY + g.maxY) / 2
            let isCovered = covered[(cy / 4) * coverWidth + cx / 4]
            let root = find(index)
            var row = rows[root] ?? Row()
            row.count += 1
            row.minX = min(row.minX, g.minX); row.maxX = max(row.maxX, g.maxX)
            row.minY = min(row.minY, g.minY); row.maxY = max(row.maxY, g.maxY)
            row.ink += g.pixels
            if !isCovered { row.uncoveredInk += g.pixels }
            rows[root] = row
        }
        var result = Measurement()
        // A row is at least three glyph-sized pieces; a lone blob is not evidence of text. Printed
        // text stands on clear paper: when the row's box holds much more dark ink than its glyphs
        // (window grids in a photograph, crowd texture, hatching), it is not counted.
        var scanned = 0
        raster.pixels.withUnsafeBufferPointer { buffer in
            for row in rows.values.sorted(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) where row.count >= minimumGlyphs {
                let area = (row.maxX - row.minX + 1) * (row.maxY - row.minY + 1)
                scanned += area
                // A bound on work for pathological pages: rows past twice the page's area are skipped.
                guard scanned <= width * height * 2 else { break }
                var dark = 0
                for y in row.minY...row.maxY {
                    let offset = y * width
                    for x in row.minX...row.maxX where buffer[offset + x] < threshold { dark += 1 }
                }
                guard dark * 2 <= row.ink * 3 else { continue }
                result.textRows += 1
                result.textInk += row.ink
                result.uncoveredInk += row.uncoveredInk
                if row.uncoveredInk * 2 > row.ink {
                    result.uncoveredRows += 1
                    if collectBoxes {
                        result.uncoveredRowBoxes.append(CGRect(x: row.minX, y: row.minY,
                            width: row.maxX - row.minX + 1, height: row.maxY - row.minY + 1))
                    }
                }
            }
        }
        return result
    }

    /// An 8-bit luminance copy of a raster, top row first.
    struct GrayRaster {
        let width: Int, height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int, pixels: [UInt8]) {
            self.width = width; self.height = height; self.pixels = pixels
        }

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            self.width = width; self.height = height
            guard width > 0, height > 0 else { return nil }
            var buffer = [UInt8](repeating: 255, count: width * height)
            // The converter's rasters are 8-bit RGBA (alpha last, opaque): read the bytes directly.
            // Drawing into a gray context instead leaves Core Graphics a converted copy attached
            // to the image, which lives as long as recognition keeps the image.
            if image.bitsPerComponent == 8, image.bitsPerPixel == 32,
               image.alphaInfo == .premultipliedLast || image.alphaInfo == .noneSkipLast || image.alphaInfo == .last,
               image.byteOrderInfo == .orderDefault || image.byteOrderInfo == .order32Big,
               image.colorSpace?.model == .rgb, let data = image.dataProvider?.data,
               CFDataGetLength(data) >= image.bytesPerRow * (height - 1) + width * 4 {
                let bytesPerRow = image.bytesPerRow
                let source = CFDataGetBytePtr(data)!
                buffer.withUnsafeMutableBufferPointer { gray in
                    for y in 0..<height {
                        let row = y * bytesPerRow
                        for x in 0..<width {
                            let p = row + x * 4
                            // Rec. 601 luma over white (premultiplied or opaque pixels).
                            let alpha = Int(source[p + 3])
                            let luma = (Int(source[p]) * 299 + Int(source[p + 1]) * 587 + Int(source[p + 2]) * 114) / 1000
                            gray[y * width + x] = UInt8(min(255, luma + (255 - alpha)))
                        }
                    }
                }
                pixels = buffer
                return
            }
            // Other layouts are converted by vImage, never drawn: drawing an image into a gray bitmap
            // context, even over our own buffer, through a proxy image or in an autorelease pool,
            // leaves up to 32 buffers held by Core Graphics (Blue Book pages 121–175 during
            // recognition: +190 MB peak RSS). vImage leaves none (#129).
            let colorSpace = CGColorSpaceCreateDeviceGray()
            var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8,
                colorSpace: Unmanaged.passUnretained(colorSpace),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), version: 0,
                decode: nil, renderingIntent: .defaultIntent)
            let converted = buffer.withUnsafeMutableBytes { bytes -> Bool in
                var destination = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(height),
                                                width: vImagePixelCount(width), rowBytes: width)
                let white: [CGFloat] = [1]
                return withExtendedLifetime(colorSpace) {
                    vImageBuffer_InitWithCGImage(&destination, &format, white, image,
                                                 vImage_Flags(kvImageNoAllocate)) == kvImageNoError
                }
            }
            guard converted else { return nil }
            pixels = buffer
        }

        /// Otsu's threshold over the luminance histogram, kept between 96 and 170 so a page that
        /// is almost all paper, or almost all dark fill, still separates ink from paper sensibly.
        func inkThreshold() -> UInt8 {
            var histogram = [Int](repeating: 0, count: 256)
            for value in pixels { histogram[Int(value)] += 1 }
            let total = Double(pixels.count)
            var sum = 0.0
            for (value, count) in histogram.enumerated() { sum += Double(value * count) }
            var background = 0.0, weightedBackground = 0.0, best = 0.0, threshold = 128
            for value in 0..<256 {
                background += Double(histogram[value])
                guard background > 0 else { continue }
                let foreground = total - background
                guard foreground > 0 else { break }
                weightedBackground += Double(value * histogram[value])
                let meanBackground = weightedBackground / background
                let meanForeground = (sum - weightedBackground) / foreground
                let between = background * foreground * (meanBackground - meanForeground) * (meanBackground - meanForeground)
                if between > best { best = between; threshold = value }
            }
            return UInt8(min(170, max(96, threshold)))
        }

        struct Component { var minX: Int, minY: Int, maxX: Int, maxY: Int, pixels: Int }

        /// Eight-connected components of pixels darker than `threshold`, by run-length labeling.
        func components(darkerThan threshold: UInt8) -> [Component] {
            var parent: [Int32] = []
            var boxes: [Component] = []
            func find(_ i: Int32) -> Int32 {
                var i = i
                while parent[Int(i)] != i { parent[Int(i)] = parent[Int(parent[Int(i)])]; i = parent[Int(i)] }
                return i
            }
            var previous: [(start: Int, end: Int, label: Int32)] = []
            var current: [(start: Int, end: Int, label: Int32)] = []
            pixels.withUnsafeBufferPointer { buffer in
                for y in 0..<height {
                    current.removeAll(keepingCapacity: true)
                    let row = y * width
                    var x = 0
                    var p = 0
                    while x < width {
                        guard buffer[row + x] < threshold else { x += 1; continue }
                        let start = x
                        while x < width && buffer[row + x] < threshold { x += 1 }
                        let end = x - 1
                        var label: Int32 = -1
                        // Previous-row runs touching [start-1, end+1] (eight-connected).
                        while p < previous.count && previous[p].end < start - 1 { p += 1 }
                        var q = p
                        while q < previous.count && previous[q].start <= end + 1 {
                            let root = find(previous[q].label)
                            if label < 0 { label = root } else if root != label {
                                let (keep, drop) = label < root ? (label, root) : (root, label)
                                parent[Int(drop)] = keep
                                let a = boxes[Int(keep)], b = boxes[Int(drop)]
                                boxes[Int(keep)] = Component(minX: min(a.minX, b.minX), minY: min(a.minY, b.minY),
                                    maxX: max(a.maxX, b.maxX), maxY: max(a.maxY, b.maxY), pixels: a.pixels + b.pixels)
                                label = keep
                            }
                            q += 1
                        }
                        if label < 0 {
                            label = Int32(parent.count)
                            parent.append(label)
                            boxes.append(Component(minX: start, minY: y, maxX: end, maxY: y, pixels: 0))
                        }
                        var box = boxes[Int(label)]
                        box.minX = min(box.minX, start); box.maxX = max(box.maxX, end)
                        box.maxY = y; box.pixels += end - start + 1
                        boxes[Int(label)] = box
                        current.append((start, end, label))
                    }
                    swap(&previous, &current)
                }
            }
            return parent.indices.compactMap { parent[$0] == Int32($0) ? boxes[$0] : nil }
        }
    }
}
