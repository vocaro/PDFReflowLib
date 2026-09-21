// Standalone Vision text-recognition probe. Apple SDKs only: PDFKit rasterizes one page, Vision
// reads it, and the probe prints the transcription's digest beside the binary's own identity.
//
//   xcrun swiftc -O probe.swift -o vision-probe
//   ./vision-probe input.pdf <page> [dpi]
//
// Two properties are meant to hold and are what this probe checks: the same binary reading the
// same page twice gives the same text, and two binaries built from this same source give the
// same text as each other, wherever either of them is run from.
import CryptoKit
import Foundation
import PDFKit
import Vision

let arguments = Array(CommandLine.arguments.dropFirst())
guard (2...3).contains(arguments.count), let pageNumber = Int(arguments[1]) else {
    fputs("Usage: vision-probe input.pdf <page, 1-based> [dpi, default 180]\n", stderr)
    exit(2)
}
let dpi = arguments.count == 3 ? (Double(arguments[2]) ?? 180) : 180
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[0])),
      pageNumber >= 1, pageNumber <= document.pageCount,
      let page = document.page(at: pageNumber - 1) else {
    fputs("Cannot open that page\n", stderr); exit(2)
}

let bounds = page.bounds(for: .cropBox)
let scale = dpi / 72
let width = Int((bounds.width * scale).rounded()), height = Int((bounds.height * scale).rounded())
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.scaleBy(x: scale, y: scale)
context.translateBy(x: -bounds.minX, y: -bounds.minY)
page.draw(with: .cropBox, to: context)
guard let image = context.makeImage() else { exit(1) }

func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// The rasterization is held constant, so a difference in the reading is not a difference in the
// pixels handed to Vision.
let pixels = Data(bytes: context.data!, count: context.bytesPerRow * height)

var request = RecognizeDocumentsRequest()
request.textRecognitionOptions.useLanguageCorrection = false
let observations = try await request.perform(on: image, orientation: nil)
let lines = observations.first?.document.text.lines.compactMap { $0.topCandidates(1).first?.string } ?? []
let text = lines.joined(separator: "\n")

let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
print("binary        \(binary.path)")
print("binary sha256 \(digest((try? Data(contentsOf: binary)) ?? Data()))")
print("image sha256  \(digest(pixels))  (\(width)x\(height) at \(Int(dpi)) dpi)")
print("text sha256   \(digest(Data(text.utf8)))")
print("lines         \(lines.count)")
for line in lines { print("| \(line)") }
