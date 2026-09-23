import CoreGraphics
import Foundation

/// The nontransparent extent of a plain soft mask. Callers read it in an isolated Core
/// Graphics document: CGPDFStreamCopyData keeps its decoded bytes for the document's lifetime.
/// Releasing that document after each image bounds retention by one mask, independent of the
/// number or placement order of a page's images (#182).
enum ImageAlphaBounds {
    static let maximumSamples = 64_000_000

    static func mask(in dictionary: CGPDFDictionaryRef) -> (CGPDFStreamRef, Int, Int)? {
        guard let stream = CGPDFObjects.stream(dictionary, "SMask"),
              let mask = CGPDFStreamGetDictionary(stream),
              let width = CGPDFObjects.integer(mask, "Width"),
              let height = CGPDFObjects.integer(mask, "Height"),
              CGPDFObjects.integer(mask, "BitsPerComponent") == 8,
              CGPDFObjects.name(mask, "ColorSpace") == "DeviceGray",
              width > 0, height > 0, width <= maximumSamples / height,
              CGPDFObjects.object(mask, "Decode") == nil,
              CGPDFObjects.object(mask, "Matte") == nil else { return nil }
        return (stream, width, height)
    }

    static func read(_ dictionary: CGPDFDictionaryRef) -> CGRect? {
        guard let (stream, width, height) = mask(in: dictionary) else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?,
              format == .raw, data.count >= width * height else { return nil }
        var left = width, right = -1, top = height, bottom = -1
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: UInt8.self)
            for row in 0..<height {
                let start = row * width
                var first = 0
                while first < width, samples[start + first] == 0 { first += 1 }
                guard first < width else { continue }
                var last = width - 1
                while last > first, samples[start + last] == 0 { last -= 1 }
                left = min(left, first); right = max(right, last)
                top = min(top, row); bottom = row
            }
        }
        guard bottom >= 0 else { return .zero }
        return CGRect(x: Double(left) / Double(width), y: Double(height - bottom - 1) / Double(height),
                      width: Double(right - left + 1) / Double(width), height: Double(bottom - top + 1) / Double(height))
    }
}
