// Prints the library classifier's features and verdict for PNG files, one JSON object per line.
//
//   swiftc -O -o features Sources/PDFReflowLib/ImageContentClassifier.swift \
//       Sources/PDFReflowLib/ConversionTypes.swift measurements/image-encoding-default/features.swift
//   ./features ROLE DRAWN_FROM_IMAGE file.png ...     (ROLE page|region, DRAWN 0|1)
//
// Compiles the library's own source file, so the numbers are the converter's. The PNG's bytes
// are handed to the classifier as stored, with no colour management, as the prototype reads them.
import CoreGraphics
import Foundation
import ImageIO

@main
struct Features {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let role: ImageContentClassifier.Role = arguments[0] == "page" ? .page : .region
        let drawn = arguments[1] == "1"
        for path in arguments.dropFirst(2) {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data),
                  image.bitsPerComponent == 8 else {
                print("{\"file\":\"\(path)\",\"error\":\"unreadable\"}"); continue
            }
            let width = image.width, height = image.height, channels = image.bitsPerPixel / 8
            var rgba = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let from = y * image.bytesPerRow + x * channels, to = (y * width + x) * 4
                    if channels >= 3 {
                        rgba[to] = pointer[from]; rgba[to + 1] = pointer[from + 1]; rgba[to + 2] = pointer[from + 2]
                    } else {
                        rgba[to] = pointer[from]; rgba[to + 1] = pointer[from]; rgba[to + 2] = pointer[from]
                    }
                }
            }
            let started = DispatchTime.now().uptimeNanoseconds
            let f = rgba.withUnsafeBufferPointer {
                ImageContentClassifier.features($0, width: width, height: height, bytesPerRow: width * 4)
            }
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
            let klass = ImageContentClassifier.classify(f, role: role, pageDrawnFromImage: drawn)
            let safe = ImageContentClassifier.lossyIsSafe(klass, f, role: role)
            let row: [String: Any] = [
                "file": path, "class": klass.rawValue, "lossy": safe, "seconds": seconds,
                "backgroundColour": [f.background.red, f.background.green, f.background.blue],
                "backgroundShare": f.backgroundShare, "chromaShare": f.chromaShare,
                "bilevelShare": f.bilevelShare, "distinctColours": f.distinctColours,
                "flatShare": f.flatShare, "hardEdgeShare": f.hardEdgeShare, "softEdgeShare": f.softEdgeShare,
            ]
            let json = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            print(String(decoding: json, as: UTF8.self))
        }
    }
}
