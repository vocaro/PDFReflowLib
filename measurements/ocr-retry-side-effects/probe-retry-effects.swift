import Accelerate
import Darwin
import Foundation
import PDFKit
import Vision

// OCR retry side effects (#129). Uses the library's own recognition code on each page's converter
// raster (library defaults, 180 DPI). Name the executable after the converter it is compared with
// (for example `pdf-reflow-i129` in another directory) so both share one compiled model set (#94).
// Build with the library's sources (no library change):
//   xcrun swiftc -parse-as-library -O Sources/PDFReflowLib/OCRReader.swift \
//     Sources/PDFReflowLib/OCRTextCoverage.swift Sources/PDFReflowLib/PageRasterizer.swift \
//     Sources/PDFReflowLib/ConversionTypes.swift Sources/PDFReflowLib/DocumentModel.swift \
//     Sources/PDFReflowLib/ReflowDocument.swift Sources/PDFReflowLib/PDFPageSource.swift \
//     measurements/ocr-retry-side-effects/probe-retry-effects.swift -o <dir>/<converter name>
// Usage:
//   <probe> dump <pdf> <page>...
//       One JSON object per page: the first recognition and, when the coverage check flags the
//       page, the merged band recognition (lines with text and normalized lower-left boxes, tables),
//       each pass's line-only uncovered ink, and whether `OCRReader.read` keeps the retry.
//   [VMMAP=1] <probe> memory <variant> <pdf> <page>...
//       Variants are listed at `memory` below. One JSON line per page with seconds, the process's
//       peak RSS and current physical footprint, then a summary line; VMMAP=1 appends
//       `vmmap --summary` of the process at the end.
@main struct ProbeRetryEffects {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else { fatalError("usage: probe-retry-effects dump|memory ...") }
        switch args[1] {
        case "dump": try await dump(pdf: args[2], pages: args.dropFirst(3).compactMap { Int($0) })
        case "memory": try await memory(variant: args[2], pdf: args[3], pages: args.dropFirst(4).compactMap { Int($0) })
        default: fatalError("unknown mode \(args[1])")
        }
    }

    static func document(_ path: String) -> PDFDocument {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { fatalError("unreadable \(path)") }
        return document
    }

    static func dump(pdf: String, pages: [Int]) async throws {
        let document = document(pdf)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let request = OCRReader.recognitionRequest(language: "en")
        for number in pages {
            guard let page = document.page(at: number - 1) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let image = try PageRasterizer.image(page: page, rect: bounds, options: ConversionOptions())
            let scale = Double(image.width) / bounds.width
            let first = try await OCRReader.recognize(image, request: request)
            let flagged = OCRTextCoverage.measure(image: image, lines: first.lines.map(\.box), excluded: first.tables,
                                                  pixelsPerPoint: scale)
            var record = Record(page: number, width: bounds.width, height: bounds.height, first: Pass(first),
                                firstUncoveredInk: OCRTextCoverage.measure(image: image, lines: first.lines.map(\.box),
                                                                           pixelsPerPoint: scale).uncoveredInk,
                                flagged: flagged.indicatesLoss)
            if flagged.indicatesLoss {
                var bands: [(recognition: OCRReader.Recognition, bottom: Double, height: Double)] = []
                for band in OCRReader.retryBands {
                    let top = Int((1 - band.upperBound) * Double(image.height))
                    let bottom = Int((1 - band.lowerBound) * Double(image.height))
                    let tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top))!
                    bands.append((try await OCRReader.recognize(tile, request: request),
                                  1 - Double(bottom) / Double(image.height), Double(bottom - top) / Double(image.height)))
                }
                let merged = OCRReader.mergeBands(bands)
                record.retry = Pass(merged)
                record.retryUncoveredInk = OCRTextCoverage.measure(image: image, lines: merged.lines.map(\.box),
                                                                   pixelsPerPoint: scale).uncoveredInk
                record.retryKept = record.retryUncoveredInk! < record.firstUncoveredInk
            }
            print(String(decoding: try encoder.encode(record), as: UTF8.self))
        }
    }

    /// Variants, each on the converter's raster with pages opened as the converter opens them:
    ///   none        recognize once, no coverage check (before #116)
    ///   first       recognize once, coverage check by direct byte read
    ///   first-draw  recognize once, then draw the raster into a gray bitmap (the first #116 check)
    ///   first-draw-proxy  the same draw of a CGImage made on the raster's data provider
    ///   first-draw-pool   the same draw inside an autorelease pool
    ///   first-vimage      recognize once, then vImageBuffer_InitWithCGImage into 8-bit gray
    ///   bgra        recognize a BGRA copy, then the library check (its converting path)
    ///   bgra-draw   recognize a BGRA copy, then draw it into a gray bitmap
    ///               (the BGRA copy is itself drawn, so both bgra variants include one draw each)
    ///   bands       recognize once, then always recognize both bands (`cropping(to:)`), no check
    ///   bands-copy  the same with each band copied into a bitmap of its own
    ///   sizes       print raster and band heights only (after one recognition)
    ///   read        `OCRReader.read` (check, retry only on flagged pages)
    static func memory(variant: String, pdf: String, pages: [Int]) async throws {
        let document = try PDFPageSource(url: URL(fileURLWithPath: pdf))
        let request = OCRReader.recognitionRequest(language: "en")
        let start = Date()
        var retried = 0, maximumFootprint = 0
        for number in pages {
            let page = try document.page(at: number - 1)
            let pageStart = Date()
            if variant == "read" {
                let result = try await OCRReader.read(page: page, options: ConversionOptions())
                if result.retriedInBands { retried += 1 }
            } else {
                let bounds = page.bounds(for: .cropBox)
                var image = try PageRasterizer.image(page: page, rect: bounds, options: ConversionOptions())
                if variant.hasPrefix("bgra") {
                    // A layout the direct byte read does not take, so the check converts it.
                    let context = autoreleasepool {
                        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                        return context
                    }
                    image = context.makeImage()!
                }
                let first = try await OCRReader.recognize(image, request: request)
                switch variant {
                case "bgra":
                    _ = OCRTextCoverage.measure(image: image, lines: first.lines.map(\.box), excluded: first.tables,
                                                pixelsPerPoint: Double(image.width) / bounds.width)
                case "bgra-draw":
                    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                case "first":
                    _ = OCRTextCoverage.measure(image: image, lines: first.lines.map(\.box), excluded: first.tables,
                                                pixelsPerPoint: Double(image.width) / bounds.width)
                case "first-draw":
                    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                case "first-vimage":
                    var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8,
                        colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceGray()),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), version: 0,
                        decode: nil, renderingIntent: .defaultIntent)
                    var buffer = vImage_Buffer()
                    _ = vImageBuffer_InitWithCGImage(&buffer, &format, nil, image, vImage_Flags(kvImageNoFlags))
                    free(buffer.data)
                    format.colorSpace.release()
                case "first-draw-pool":
                    autoreleasepool {
                        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    }
                case "first-draw-proxy":
                    let proxy = CGImage(width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
                        bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow, space: image.colorSpace!,
                        bitmapInfo: image.bitmapInfo, provider: image.dataProvider!, decode: nil,
                        shouldInterpolate: false, intent: .defaultIntent)!
                    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                    context.draw(proxy, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                case "sizes":
                    print("{\"page\":\(number),\"width\":\(image.width),\"height\":\(image.height),\"bands\":"
                        + "\(OCRReader.retryBands.map { Int((1 - $0.lowerBound) * Double(image.height)) - Int((1 - $0.upperBound) * Double(image.height)) })}")
                case "bands", "bands-copy", "bands-same":
                    for band in OCRReader.retryBands {
                        var top = Int((1 - band.upperBound) * Double(image.height))
                        var bottom = Int((1 - band.lowerBound) * Double(image.height))
                        if variant == "bands-same" {
                            // Both bands exactly the same pixel height.
                            let height = Int((0.6 * Double(image.height)).rounded())
                            if band.upperBound == 1 { top = 0; bottom = height } else { top = image.height - height; bottom = image.height }
                        }
                        let tile: CGImage
                        if variant == "bands" {
                            tile = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top))!
                        } else {
                            // The band's rows copied into a bitmap of its own.
                            let data = image.dataProvider!.data!
                            let rows = Data(bytes: CFDataGetBytePtr(data)! + top * image.bytesPerRow,
                                            count: (bottom - top) * image.bytesPerRow)
                            tile = CGImage(width: image.width, height: bottom - top, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: image.bytesPerRow, space: image.colorSpace!, bitmapInfo: image.bitmapInfo,
                                provider: CGDataProvider(data: rows as CFData)!, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent)!
                        }
                        _ = try await OCRReader.recognize(tile, request: request)
                    }
                    retried += 1
                default: break
                }
            }
            maximumFootprint = max(maximumFootprint, footprint())
            print("{\"page\":\(number),\"seconds\":\(Date().timeIntervalSince(pageStart)),"
                + "\"peakRSSMiB\":\(peakRSS() / 1_048_576),\"footprintMiB\":\(footprint() / 1_048_576)}")
        }
        print("{\"variant\":\"\(variant)\",\"pages\":\(pages.count),\"retried\":\(retried),"
            + "\"seconds\":\(Date().timeIntervalSince(start)),\"peakRSSMiB\":\(peakRSS() / 1_048_576),"
            + "\"maximumSampledFootprintMiB\":\(maximumFootprint / 1_048_576)}")
        if ProcessInfo.processInfo.environment["VMMAP"] != nil {
            let vmmap = Process()
            vmmap.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
            vmmap.arguments = ["--summary", String(getpid())]
            try vmmap.run()
            vmmap.waitUntilExit()
        }
    }

    static func peakRSS() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss)
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

struct Line: Codable { var text: String; var box: [Double] }
struct Pass: Codable {
    var lines: [Line], tables: [[Double]]
    init(_ recognition: OCRReader.Recognition) {
        func box(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height].map { (Double($0) * 10_000).rounded() / 10_000 } }
        lines = recognition.lines.map { Line(text: $0.text, box: box($0.box)) }
        tables = recognition.tables.map(box)
    }
}
struct Record: Codable {
    var page: Int, width: Double, height: Double
    var first: Pass, firstUncoveredInk: Int, flagged: Bool
    var retry: Pass?, retryUncoveredInk: Int?, retryKept: Bool?
}
