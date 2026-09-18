// Measurement-only re-encoder. Reads the PNG assets a conversion wrote and encodes each one as
// JPEG at the requested qualities with the same ImageIO call PageRasterizer.write makes, so the
// byte counts are the converter's own encoder, not Pillow's. Nothing here is library code and
// nothing here is imported by the library; it exists to produce numbers.
//
//   swiftc -O reencode.swift -o reencode
//   ./reencode <input-dir> <output-dir> 0.95,0.90,0.85 > sizes.json
//
// For every `*.png` in the input directory it writes `<name>.q95.jpg` and so on into the output
// directory, and prints one JSON object mapping the asset name to its pixel dimensions and to
// the encoded byte count at each quality.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("reencode: " + message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else { fail("usage: reencode INPUT_DIR OUTPUT_DIR QUALITY[,QUALITY...]") }
let inputDirectory = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])
let qualities = arguments[3].split(separator: ",").map { part -> Double in
    guard let quality = Double(part), quality.isFinite, (0...1).contains(quality) else {
        fail("JPEG quality must be in 0...1")
    }
    return quality
}
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func label(_ quality: Double) -> String { "q" + String(Int((quality * 100).rounded())) }

func encode(_ image: CGImage, to url: URL, quality: Double?) -> Int {
    let type = (quality == nil ? UTType.png : UTType.jpeg).identifier as CFString
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
        fail("cannot write \(url.path)")
    }
    let properties = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(url.path)") }
    return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
}

let names = ((try? FileManager.default.contentsOfDirectory(atPath: inputDirectory.path)) ?? [])
    .filter { $0.lowercased().hasSuffix(".png") }.sorted()
var results: [String: [String: Int]] = [:]
for name in names {
    let source = inputDirectory.appendingPathComponent(name)
    guard let provider = CGDataProvider(url: source as CFURL),
          let png = CGImageSourceCreateWithDataProvider(provider, nil),
          let image = CGImageSourceCreateImageAtIndex(png, 0, nil) else {
        fail("cannot decode \(name)")
    }
    let stem = String(name.dropLast(4))
    var row: [String: Int] = ["width": image.width, "height": image.height,
                              "png": (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0]
    for quality in qualities {
        let target = outputDirectory.appendingPathComponent("\(stem).\(label(quality)).jpg")
        row[label(quality)] = encode(image, to: target, quality: quality)
    }
    results[stem] = row
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
