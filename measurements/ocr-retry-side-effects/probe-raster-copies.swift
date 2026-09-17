import Accelerate
import Darwin
import Foundation
import PDFKit

// Which raster reads leave memory behind (#129 item 3)? No Vision. Rasterizes pages as the
// converter does and applies one operation to each raster; rasters are released after each page
// unless HOLD=1 (as recognition would keep them). Reports physical-footprint growth and, with
// VMMAP=1, vmmap's region summary at the end (retained copies show as live `Malloc Large`).
// Build:
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/OCRTextCoverage.swift \
//     Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
//     Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
//     Sources/PDFReflowLib/PDFPageSource.swift \
//     measurements/ocr-retry-side-effects/probe-raster-copies.swift -o <name>
// Usage: [HOLD=1] [VMMAP=1] <probe> <operation> <pdf> <first page> <count>
//   none          rasterize only
//   gray          OCRTextCoverage.GrayRaster(raster): the direct byte read of the converter's RGBA layout
//   draw          draw the raster into an 8-bit gray bitmap context (the check's first #116 form)
//   draw-proxy    draw a CGImage made on the raster's data provider instead
//   draw-buffer   the check's removed fallback: draw into a gray context over a caller-owned buffer
//   bgra-draw-buffer  the same on the byte-swapped BGRA copy
//   vimage        vImageBuffer_InitWithCGImage into 8-bit gray
//   bgra-gray     GrayRaster of a byte-swapped BGRA copy (built without drawing): its converting path
//   bgra-draw     draw that BGRA copy into a gray bitmap context
@main struct ProbeRasterCopies {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5, let first = Int(args[3]), let count = Int(args[4]) else {
            fatalError("usage: probe-raster-copies <operation> <pdf> <first page> <count>")
        }
        let document = try PDFPageSource(url: URL(fileURLWithPath: args[2]))
        let operation = args[1]
        let hold = ProcessInfo.processInfo.environment["HOLD"] == "1"
        var held: [CGImage] = []
        let base = footprint()
        for number in first..<(first + count) {
            try autoreleasepool {
                let page = try document.page(at: number - 1)
                var image = try PageRasterizer.image(page: page, rect: page.bounds(for: .cropBox), options: ConversionOptions())
                if operation.hasPrefix("bgra") { image = bgra(image) }
                if hold { held.append(image) }
                switch operation {
                case "gray", "bgra-gray": _ = OCRTextCoverage.GrayRaster(image)
                case "draw", "bgra-draw": draw(image)
                case "draw-buffer", "bgra-draw-buffer":
                    // The removed fallback: a gray context over a caller-owned buffer, filled white first.
                    var pixels = [UInt8](repeating: 255, count: image.width * image.height)
                    pixels.withUnsafeMutableBytes { bytes in
                        let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                        context.setFillColor(gray: 1, alpha: 1)
                        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    }
                case "draw-proxy": draw(proxy(image))
                case "vimage":
                    var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8,
                        colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceGray()),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), version: 0,
                        decode: nil, renderingIntent: .defaultIntent)
                    var buffer = vImage_Buffer()
                    _ = vImageBuffer_InitWithCGImage(&buffer, &format, nil, image, vImage_Flags(kvImageNoFlags))
                    free(buffer.data)
                    format.colorSpace.release()
                default: break
                }
            }
        }
        let grown = footprint() - base
        print("{\"operation\":\"\(operation)\",\"hold\":\(hold),\"pages\":\(count),"
            + "\"footprintGrowthMiB\":\(grown / 1_048_576),\"perPageMiB\":\(Double(grown) / Double(count) / 1_048_576)}")
        if ProcessInfo.processInfo.environment["VMMAP"] != nil {
            let vmmap = Process()
            vmmap.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
            vmmap.arguments = ["--summary", String(getpid())]
            try vmmap.run()
            vmmap.waitUntilExit()
        }
        withExtendedLifetime(held) {}
    }

    static func draw(_ image: CGImage) {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    static func proxy(_ image: CGImage) -> CGImage {
        CGImage(width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
                bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow, space: image.colorSpace!,
                bitmapInfo: image.bitmapInfo, provider: image.dataProvider!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The RGBA raster's bytes reordered to BGRA (alpha first, little-endian), without drawing.
    static func bgra(_ image: CGImage) -> CGImage {
        let data = image.dataProvider!.data!
        let source = CFDataGetBytePtr(data)!
        var bytes = Data(count: image.bytesPerRow * image.height)
        bytes.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let p = y * image.bytesPerRow + x * 4
                    out[p] = source[p + 2]; out[p + 1] = source[p + 1]; out[p + 2] = source[p]; out[p + 3] = source[p + 3]
                }
            }
        }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.bytesPerRow, space: image.colorSpace!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : -1
    }
}
