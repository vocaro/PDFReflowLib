import Foundation
import PDFKit

// Diagnostic only, for #182. For every page of every named PDF it reports two things:
//
//  * what the pipeline does today — the crops `graphicsWithLabels` forms and the lines those
//    crops take out of the reflowed text;
//  * what each placed image's own alpha says — its placement box, the sub-rectangle of that box
//    its soft mask actually paints, and which lines the box takes that the painted part does not.
//
// The second is the defect #182 names: a producer's placement box is routinely larger than the
// drawing in it, and a crop grown from the box can take a word the drawing never reaches. The
// first is what decides whether that ever costs the book a word, since a page whose paints
// cluster into one page-sized region has no per-figure crop for the margin to grow.
//
// No converter output, no rasters. The reading of the mask here is deliberately the same narrow
// one the candidate change made in `GraphicsReader`: a plain `/SMask`, eight bits a sample, no
// `/Decode` and no `/Matte`, decoded by Core Graphics to raw samples.
//
//     survey-image-alpha /tmp/survey.json corpus/cache/20180003024.pdf corpus/cache/DGA.pdf …

/// An alpha sample at or below this paints nothing a reader can see.
let transparentAlpha: UInt8 = 2

/// The part of an image XObject's unit square its own alpha paints, or nil where the mask is not
/// in the plain form this reads. `.zero` means the image is transparent everywhere.
func paintedUnitBounds(_ dictionary: CGPDFDictionaryRef) -> CGRect? {
    var mask: CGPDFStreamRef?
    guard CGPDFDictionaryGetStream(dictionary, "SMask", &mask), let mask,
          let maskDictionary = CGPDFStreamGetDictionary(mask) else { return nil }
    var width: CGPDFInteger = 0, height: CGPDFInteger = 0, bits: CGPDFInteger = 0
    guard CGPDFDictionaryGetInteger(maskDictionary, "Width", &width),
          CGPDFDictionaryGetInteger(maskDictionary, "Height", &height),
          CGPDFDictionaryGetInteger(maskDictionary, "BitsPerComponent", &bits),
          bits == 8, width > 0, height > 0 else { return nil }
    var ignored: CGPDFObjectRef?
    guard !CGPDFDictionaryGetObject(maskDictionary, "Decode", &ignored),
          !CGPDFDictionaryGetObject(maskDictionary, "Matte", &ignored) else { return nil }
    var format = CGPDFDataFormat.raw
    guard let data = CGPDFStreamCopyData(mask, &format) as Data?, format == .raw,
          data.count >= width * height else { return nil }
    var minimumRow = height, maximumRow = -1, minimumColumn = width, maximumColumn = -1
    data.withUnsafeBytes { raw in
        let samples = raw.bindMemory(to: UInt8.self)
        for row in 0..<height {
            let offset = row * width
            var column = 0
            while column < width, samples[offset + column] <= transparentAlpha { column += 1 }
            guard column < width else { continue }
            if row < minimumRow { minimumRow = row }
            maximumRow = row
            if column < minimumColumn { minimumColumn = column }
            var last = width - 1
            while last > column, samples[offset + last] <= transparentAlpha { last -= 1 }
            if last > maximumColumn { maximumColumn = last }
        }
    }
    guard maximumRow >= 0 else { return .zero }
    // Image space runs top row first; the unit square runs bottom up.
    let w = CGFloat(width), h = CGFloat(height)
    return CGRect(x: CGFloat(minimumColumn) / w, y: CGFloat(height - maximumRow - 1) / h,
                  width: CGFloat(maximumColumn - minimumColumn + 1) / w,
                  height: CGFloat(maximumRow - minimumRow + 1) / h)
}

@main struct SurveyImageAlpha {
    static func main() throws {
        let output = CommandLine.arguments[1]
        var books: [String: Any] = [:]
        for path in CommandLine.arguments.dropFirst(2) {
            guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
                fatalError("no document " + path)
            }
            var pages: [[String: Any]] = []
            var images = 0, softMasks = 0, readable = 0, trimmed = 0, trimmedATenth = 0
            var wordsBehindPadding: [String] = []
            for index in 0..<document.pageCount {
                try autoreleasepool {
                    let page = document.page(at: index)!
                    let reference = page.pageRef!
                    let lines = try NativeTextReader.lines(on: page, limit: 200_000)
                    let graphics = GraphicsReader.read(reference)
                    let content = PageContent(number: index + 1, bounds: page.bounds(for: .cropBox),
                                              lines: lines, graphics: graphics.regions,
                                              pictures: graphics.images)
                    let crops = LayoutReconstructor.graphicsWithLabels(content, language: "en")
                    let taken = lines.enumerated().filter { line in
                        crops.contains { LayoutReconstructor.takes($0, line.element) }
                    }.map { "\($0.offset):\($0.element.text.prefix(40))" }
                    // What each placed image's alpha says about its own box.
                    var behind: [String] = []
                    for placement in EmbeddedImageReader.placements(reference) {
                        images += 1
                        guard let dictionary = CGPDFStreamGetDictionary(placement.stream) else { continue }
                        var mask: CGPDFObjectRef?
                        if CGPDFDictionaryGetObject(dictionary, "SMask", &mask) { softMasks += 1 }
                        guard let unit = paintedUnitBounds(dictionary) else { continue }
                        readable += 1
                        if unit.width < 0.98 || unit.height < 0.98 { trimmed += 1 }
                        if unit.width < 0.9 || unit.height < 0.9 { trimmedATenth += 1 }
                        let box = placement.rect
                        let ink = CGRect(x: box.minX + unit.minX * box.width,
                                         y: box.minY + unit.minY * box.height,
                                         width: unit.width * box.width, height: unit.height * box.height)
                        for line in lines where LayoutReconstructor.takes(box, line)
                            && !LayoutReconstructor.takes(ink, line) {
                            behind.append("p\(index + 1):\(line.text.prefix(40))")
                        }
                    }
                    wordsBehindPadding += behind
                    pages.append(["page": index + 1, "crops": crops.count, "taken": taken,
                                  "linesOnlyInPadding": behind,
                                  "cropArea": (crops.reduce(0.0) { $0 + Double($1.width * $1.height) } * 100).rounded() / 100])
                }
            }
            books[URL(fileURLWithPath: path).lastPathComponent] = [
                "pages": pages, "images": images, "softMasks": softMasks, "readable": readable,
                "trimmedOverTwoPercent": trimmed, "trimmedOverATenth": trimmedATenth,
                "linesOnlyInPadding": wordsBehindPadding,
            ]
        }
        try JSONSerialization.data(withJSONObject: books, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: output))
    }
}
