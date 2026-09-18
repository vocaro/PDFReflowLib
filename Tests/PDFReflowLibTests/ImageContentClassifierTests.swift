import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// #193: the automatic default classifies each image and permits lossy only where it is safe.

/// An RGBA8 raster built exactly as `PageRasterizer.image` builds one (premultipliedLast over an
/// opaque fill), so the classifier reads its bytes directly.
private func raster(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let row = context.bytesPerRow
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = pixel(x, y)
            // CGBitmapContext memory is top row first.
            let offset = y * row + x * 4
            bytes[offset] = r; bytes[offset + 1] = g; bytes[offset + 2] = b; bytes[offset + 3] = 255
        }
    }
    return try #require(context.makeImage())
}

private struct Noise {
    var seed: UInt32
    mutating func next(_ range: Int) -> Int {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Int(seed >> 16) % range
    }
}

private func clamp(_ value: Int) -> UInt8 { UInt8(max(0, min(255, value))) }

@Test func defaultEncodingIsAutomaticAtNinetyForPagesAndRegions() {
    let options = ConversionOptions()
    #expect(options.fullPageImageEncoding == .automatic(jpegQuality: 0.9))
    #expect(options.regionImageEncoding == .automatic(jpegQuality: 0.9))
    #expect(ConversionOptions.ImageEncoding.automaticJPEGQuality == 0.9)
}

/// Hand-computed on a 4×4 raster: two rows of white over a 2×2 red and a 2×2 black square. The
/// survey prototype (`measurements/image-encoding/classifier.py`) gives the same numbers.
@Test func featuresMatchTheSurveyPrototypeOnAHandComputedRaster() throws {
    let image = try raster(width: 4, height: 4) { x, y in
        y < 2 ? (255, 255, 255) : x < 2 ? (255, 0, 0) : (0, 0, 0)
    }
    let f = ImageContentClassifier.features(of: image)
    #expect(f.background == (255, 255, 255))
    #expect(f.backgroundShare == 0.5)
    #expect(f.chromaShare == 0.25)          // the red square alone differs in hue from white
    #expect(f.bilevelShare == 1)            // only ever paper or ink
    #expect(f.distinctColours == 3)
    #expect(f.flatShare == 6.0 / 16)        // the top row and the two outer bottom corners
    #expect(f.hardEdgeShare == 10.0 / 16)
    #expect(f.softEdgeShare == 0)
    // The modal colour is exact, not a coarse bin: all three colours here share one 4-bit bin, and
    // only exact counts inside it find the ground (13, 14, 15) rather than (0, 0, 0).
    let ground = try raster(width: 10, height: 1) { x, _ in x < 4 ? (13, 14, 15) : x < 7 ? (0, 0, 0) : (1, 1, 1) }
    #expect(ImageContentClassifier.features(of: ground).background == (13, 14, 15))
}

@Test func featuresReadTheSamePixelsFromAnyRasterLayout() throws {
    var noise = Noise(seed: 3)
    let image = try raster(width: 64, height: 48) { x, y in
        (clamp(x * 3 + noise.next(20)), clamp(y * 4), clamp(128 + noise.next(40)))
    }
    // The same bytes described as 24-bit RGB take the redraw path.
    let packed = try #require(image.dataProvider?.data)
    var rgb = [UInt8]()
    let pointer = try #require(CFDataGetBytePtr(packed))
    for y in 0..<image.height {
        for x in 0..<image.width {
            let offset = y * image.bytesPerRow + x * 4
            rgb += [pointer[offset], pointer[offset + 1], pointer[offset + 2]]
        }
    }
    let provider = try #require(CGDataProvider(data: Data(rgb) as CFData))
    let other = try #require(CGImage(width: 64, height: 48, bitsPerComponent: 8, bitsPerPixel: 24,
        bytesPerRow: 64 * 3, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    #expect(ImageContentClassifier.features(of: other) == ImageContentClassifier.features(of: image))
}

/// Positive and negative controls for every verdict the default can reach.
@Test func lossyIsPermittedForToneAndNeutralImagesAndRefusedForColouredDrawnMatter() throws {
    // A photograph: colour ramps under sensor noise, nothing flat.
    var noise = Noise(seed: 11)
    let photograph = try raster(width: 200, height: 150) { x, y in
        let grain = noise.next(40)
        return (clamp(30 + x + grain), clamp(60 + y + grain), clamp(20 + (x + y) / 2 + grain))
    }
    // A neutral scan: grey paper and grey ink with noise, no hue at all.
    let scan = try raster(width: 200, height: 150) { x, y in
        let v = (x / 6 + y / 9) % 5 == 0 ? 40 : 225
        let g = clamp(v + noise.next(14))
        return (g, g, g)
    }
    // A coloured chart: white ground, flat red and blue bars, a green rule.
    let chart = try raster(width: 200, height: 150) { x, y in
        if y == 140 { return (0, 160, 0) }
        if x > 20 && x < 60 && y > 40 && y < 140 { return (220, 30, 30) }
        if x > 90 && x < 130 && y > 70 && y < 140 { return (30, 60, 200) }
        return (255, 255, 255)
    }
    // Drawn illustration in the attitude indicator's manner: a flat saturated sky over a shaded
    // bezel. And its negative control: the same shading with a sky too small to be drawn fill.
    func illustration(skyRows: Int) throws -> CGImage {
        var noise = Noise(seed: 5)
        return try raster(width: 200, height: 200) { x, y in
            if y < skyRows { return (0, 110, 200) }
            let grain = noise.next(40)
            return (clamp(60 + x / 2 + grain), clamp(40 + y / 4 + grain), clamp(20 + grain))
        }
    }
    func judge(_ image: CGImage, _ role: ImageContentClassifier.Role) -> ImageContentClassifier.Verdict {
        ImageContentClassifier.judge(image, role: role, pageDrawnFromImage: false)
    }

    let photo = judge(photograph, .region)
    #expect(photo.contentClass == .photograph && photo.lossyPermitted)
    let neutral = judge(scan, .region)
    #expect(neutral.features.chromaShare < 0.02 && neutral.lossyPermitted)
    let lineArt = judge(chart, .region)
    #expect(lineArt.contentClass == .lineArt && !lineArt.lossyPermitted)
    #expect(!judge(chart, .page).lossyPermitted)

    let drawn = judge(try illustration(skyRows: 80), .region)
    #expect(drawn.contentClass == .continuousTone)
    #expect(drawn.features.flatShare >= 0.30 && !drawn.lossyPermitted)
    // A page reference of the same picture keeps the prototype's verdict.
    #expect(judge(try illustration(skyRows: 80), .page).lossyPermitted)
    let shaded = judge(try illustration(skyRows: 30), .region)
    #expect(shaded.contentClass == .continuousTone)
    #expect(shaded.features.flatShare < 0.30 && shaded.lossyPermitted)
}

@Test func textPagesSplitByPageEvidenceAndOnlyTonalScansPermitColour() {
    // Typeset: mostly ground, little colour, step edges and no ramps.
    var f = ImageContentClassifier.Features()
    f.backgroundShare = 0.8; f.chromaShare = 0.05; f.softEdgeShare = 0.05; f.hardEdgeShare = 0.1
    f.flatShare = 0.7; f.distinctColours = 20_000; f.bilevelShare = 0.9
    typealias C = ImageContentClassifier
    #expect(C.classify(f, role: .page, pageDrawnFromImage: true) == .tonalScan)
    #expect(C.classify(f, role: .page, pageDrawnFromImage: false) == .bornDigitalText)
    #expect(C.classify(f, role: .region, pageDrawnFromImage: true) == .lineArt)
    #expect(C.lossyIsSafe(.tonalScan, f, role: .page))
    #expect(!C.lossyIsSafe(.bornDigitalText, f, role: .page))
    var bilevel = f; bilevel.bilevelShare = 0.97; bilevel.distinctColours = 300
    #expect(C.classify(bilevel, role: .page, pageDrawnFromImage: true) == .bilevelScan)
    #expect(!C.lossyIsSafe(.bilevelScan, bilevel, role: .page))
    // Neutral wins over every class: no chroma, nothing for subsampling to damage.
    var neutral = bilevel; neutral.chromaShare = 0.01
    for contentClass in C.ContentClass.allCases {
        #expect(C.lossyIsSafe(contentClass, neutral, role: .region))
    }
    // Mixed: a page reference permits lossy, a crop does not.
    #expect(C.lossyIsSafe(.mixed, f, role: .page))
    #expect(!C.lossyIsSafe(.mixed, f, role: .region))
}

@Test func explicitEncodingsBypassTheClassifier() throws {
    let chart = try raster(width: 40, height: 40) { x, _ in x < 20 ? (220, 30, 30) : (255, 255, 255) }
    typealias E = ConversionOptions.ImageEncoding
    for requested: E in [.png, .jpeg(quality: 0.5), .smallest(jpegQuality: 0.7)] {
        for role: ImageContentClassifier.Role in [.page, .region] {
            #expect(ImageContentClassifier.resolve(requested, image: chart, role: role, pageDrawnFromImage: true) == requested)
        }
    }
    #expect(ImageContentClassifier.resolve(.automatic(jpegQuality: 0.8), image: chart, role: .region,
                                           pageDrawnFromImage: false) == .png)
    var noise = Noise(seed: 2)
    let photograph = try raster(width: 64, height: 64) { x, y in
        (clamp(60 + x + noise.next(12)), clamp(90 + y + noise.next(12)), clamp(40 + noise.next(12)))
    }
    #expect(ImageContentClassifier.resolve(.automatic(jpegQuality: 0.8), image: photograph, role: .region,
                                           pageDrawnFromImage: false) == .smallest(jpegQuality: 0.8))
}

/// One born-digital page holding a paragraph over three figures, top to bottom: a noisy colour
/// photograph, a drawn illustration (a flat saturated sky over shading, the attitude indicator's
/// make-up) and a flat coloured chart.
private func figuresPDF() throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdfKitGated {
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let lines = ["The photograph below is captured tone and may be stored as JPEG.",
                     "The illustration and the chart beneath it are drawn in colour and stay lossless.",
                     "All three are preserved as images; this paragraph reflows as text."]
        for (index, text) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font]))
            pdf.textPosition = CGPoint(x: 72, y: 750 - CGFloat(index) * 14)
            CTLineDraw(line, pdf)
        }
    }
    var noise = Noise(seed: 29)
    let photograph = try raster(width: 360, height: 240) { x, y in
        let grain = noise.next(40)
        return (clamp(30 + x / 2 + grain), clamp(60 + y / 2 + grain), clamp(20 + (x + y) / 4 + grain))
    }
    pdf.draw(photograph, in: CGRect(x: 186, y: 520, width: 240, height: 160))
    let illustration = try raster(width: 200, height: 200) { x, y in
        if y < 80 { return (0, 110, 200) }
        let grain = noise.next(40)
        return (clamp(60 + x / 2 + grain), clamp(40 + y / 4 + grain), clamp(20 + grain))
    }
    pdf.draw(illustration, in: CGRect(x: 216, y: 300, width: 180, height: 180))
    let bars: [(CGFloat, CGColor)] = [(120, CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)),
                                      (80, CGColor(red: 0.1, green: 0.25, blue: 0.8, alpha: 1)),
                                      (150, CGColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1))]
    for (index, (height, colour)) in bars.enumerated() {
        pdf.setFillColor(colour)
        pdf.fill(CGRect(x: 200 + CGFloat(index) * 80, y: 70, width: 50, height: height))
    }
    pdf.setStrokeColor(CGColor(red: 0.9, green: 0.5, blue: 0, alpha: 1))
    pdf.setLineWidth(2)
    pdf.stroke(CGRect(x: 180, y: 60, width: 250, height: 180))
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

/// The converter measures the context's buffer while rasterizing, to avoid the copy reading a
/// `CGImage` makes; that must be the same picture the encoder is handed.
@Test func rasterizerInspectionSeesTheImageItReturns() throws {
    let document = try #require(PDFDocument(data: try figuresPDF()))
    let page = try #require(document.page(at: 0))
    for (rect, rotate) in [(page.bounds(for: .cropBox), true), (CGRect(x: 186, y: 520, width: 240, height: 160), false)] {
        var inspected: ImageContentClassifier.Features?
        let image = try PageRasterizer.image(page: page, rect: rect, options: ConversionOptions(), applyRotation: rotate) {
            inspected = ImageContentClassifier.features($0, width: $1, height: $2, bytesPerRow: $3)
        }
        #expect(inspected == ImageContentClassifier.features(of: image))
        #expect(inspected?.width == image.width && inspected?.height == image.height)
    }
}

@Test func automaticDefaultSendsOnlyThePhotographToJPEGAndExplicitChoicesAreExact() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let input = dir.appendingPathComponent("page.pdf")
    try figuresPDF().write(to: input)
    typealias E = ConversionOptions.ImageEncoding
    var formats: [String: [ReflowDocument.Asset.Format]] = [:]
    for (label, encoding) in [("default", E?.none), ("png", .png), ("jpeg", .jpeg(quality: 0.9)),
                              ("smallest", .smallest(jpegQuality: 0.9))] {
        var options = ConversionOptions(); options.referenceImages = .never
        if let encoding { options.regionImageEncoding = encoding }
        let result = try await PDFReflowLibPipeline.reconstruct(from: input, options: options,
            workspace: dir.appendingPathComponent(label), progress: { _ in })
        formats[label] = result.document.assets.map(\.format)
    }
    // Three crops, top to bottom. The default keeps the illustration lossless where bare
    // `smallest` takes its smaller JPEG: that difference is the classifier's.
    #expect(formats["default"] == [.jpeg, .png, .png])
    #expect(formats["smallest"] == [.jpeg, .jpeg, .png])
    #expect(formats["png"] == [.png, .png, .png])
    #expect(formats["jpeg"] == [.jpeg, .jpeg, .jpeg])
}
