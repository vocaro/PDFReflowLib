import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func decode(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
    return image
}
func pixels(_ image: CGImage) throws -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try data.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileReadCorruptFile) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}
@main struct EncodeExperiment {
    static func main() throws {
        let args = CommandLine.arguments
        let directory = URL(fileURLWithPath: args[1])
        let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("images.json")))
        for (index, path) in paths.enumerated() {
            try autoreleasepool {
                let original = try decode(directory.appendingPathComponent(path))
                let before = try pixels(original)
                var variants: [[String: Any]] = []
                for quality in [90, 95] {
                    let url = directory.appendingPathComponent("q\(quality)/" + URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent + ".jpg")
                    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
                    CGImageDestinationAddImage(destination, original, [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                    let decoded = try decode(url)
                    guard original.width == decoded.width && original.height == decoded.height else { throw CocoaError(.fileReadCorruptFile) }
                    let after = try pixels(decoded)
                    var squared: Double = 0, worst = 0, largeErrors = 0
                    for i in stride(from: 0, to: before.count, by: 4) {
                        for c in 0..<3 {
                            let delta = abs(Int(before[i+c]) - Int(after[i+c]))
                            squared += Double(delta * delta); worst = max(worst, delta)
                            if delta > 16 { largeErrors += 1 }
                        }
                    }
                    let samples = Double(original.width * original.height * 3)
                    let mse = squared / samples
                    variants.append(["quality": quality, "bytes": try url.resourceValues(forKeys: [.fileSizeKey]).fileSize!,
                        "rgbMSE": mse, "rgbPSNRdB": mse > 0 ? 10 * log10(65025 / mse) : 100,
                        "maximumChannelError": worst, "fractionChannelsErrorOver16": Double(largeErrors)/samples])
                }
                let record: [String: Any] = ["image": path, "width": original.width, "height": original.height,
                    "pngBytes": try directory.appendingPathComponent(path).resourceValues(forKeys: [.fileSizeKey]).fileSize!, "variants": variants]
                let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            }
            FileHandle.standardError.write(Data("\(index+1)/\(paths.count) encoded\n".utf8))
        }
    }
}
