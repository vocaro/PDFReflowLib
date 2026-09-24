import Foundation
import PDFReflowLib

@main
struct PDFReflowLibCommand {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let usage = """
        Usage: pdf-reflow input.pdf output.epub [options]
          --ocr automatic|image-backed|keep-image-backed|always|never
          --no-ocr  (alias for --ocr never)
          --reviewed-panel-pages 13,24          (one-based physical pages shown as images; no OCR/reflow)
          --ocr-language-correction on|off       (recognizer corrects words to its language model; default off)
          --reference-images automatic|always|never
          --repeated-headers-and-footers remove|keep
          --full-page-image-encoding automatic[:QUALITY]|png|jpeg:QUALITY|smallest:QUALITY
          --region-image-encoding automatic[:QUALITY]|png|jpeg:QUALITY|smallest:QUALITY
          --maximum-output-bytes BYTES|unlimited  (uncompressed entry budget)
          --maximum-epub-bytes BYTES|unlimited    (final ZIP file cap)
          --language TAG                          (BCP 47; dc:language and OCR; default en)
          --password-file PATH                    (password for a locked PDF; - reads stdin)
          --package-identifier ID                 (dc:identifier; default random urn:uuid)
          --modification-date ISO8601             (e.g. 2026-01-01T00:00:00Z; default now)
          --raster-dpi DPI                        (72...600; default 180)
          --maximum-raster-pixels PIXELS          (1...48000000 per raster; default 12000000)
        JPEG QUALITY must be in 0...1. Defaults: automatic references, repeated headers and
        footers removed, automatic:0.9 image encoding, 512 MiB entry budget, no separate final
        ZIP cap. Required image-only fallback pages are retained. automatic classifies each
        image: photographs, painted art, tonal scans, mixed full pages and uncolored images
        keep the smaller of PNG and JPEG; colored line art, charts, drawn illustration and
        mixed crops, and colored text pages stay PNG. png, jpeg:QUALITY and smallest:QUALITY
        apply exactly as named.
        Set both --package-identifier and --modification-date for byte-reproducible packaging.
        Language correction is for scans of plain prose only: it reads prose a little better
        and codes, dates and names worse, and a corrected mistake reads as a real word; every
        ocrUsed warning of a conversion that used it says so.
        A locked PDF needs --password-file: the password is read from a file or standard input,
        never from an argument, so it stays out of the shell history and the process list. One
        trailing newline is the file's and is removed; anything else is the password.
        """
        if args == ["--help"] {
            print(usage); return
        }
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data((usage + "\n").utf8)); exit(2)
        }
        var options = ConversionOptions()
        do {
            func encoding(_ value: String) throws -> ConversionOptions.ImageEncoding {
                if value == "png" { return .png }
                if value == "automatic" { return .automatic(jpegQuality: ConversionOptions.ImageEncoding.automaticJPEGQuality) }
                let parts = value.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count == 2, let quality = Double(parts[1]), quality.isFinite,
                   (0...1).contains(quality) {
                    if parts[0] == "jpeg" { return .jpeg(quality: quality) }
                    if parts[0] == "smallest" { return .smallest(jpegQuality: quality) }
                    if parts[0] == "automatic" { return .automatic(jpegQuality: quality) }
                }
                throw ConversionError.invalidOptions("expected automatic, automatic:QUALITY, png, jpeg:QUALITY or smallest:QUALITY")
            }
            func byteLimit(_ value: String) throws -> Int64? {
                if value == "unlimited" { return nil }
                guard let limit = Int64(value), limit > 0 else {
                    throw ConversionError.invalidOptions("byte limit must be a positive integer or unlimited")
                }
                return limit
            }
            var index = 2
            while index < args.count {
                let flag = args[index]; index += 1
                if flag == "--no-ocr" { options.ocr = .never; continue }
                guard index < args.count else { throw ConversionError.invalidOptions("missing value for \(flag)") }
                let value = args[index]; index += 1
                switch flag {
                case "--ocr":
                    switch value {
                    case "automatic": options.ocr = .automatic
                    case "image-backed": options.ocr = .automaticIncludingImageBackedText
                    case "keep-image-backed": options.ocr = .automaticKeepingImageBackedText
                    case "always": options.ocr = .always
                    case "never": options.ocr = .never
                    default: throw ConversionError.invalidOptions("unknown OCR policy: \(value)")
                    }
                case "--reviewed-panel-pages":
                    let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                    guard !parts.isEmpty, parts.count <= options.maximumPages,
                          parts.allSatisfy({ Int($0).map { (1...options.maximumPages).contains($0) } == true }) else {
                        throw ConversionError.invalidOptions("reviewed panel pages must be comma-separated positive physical page numbers")
                    }
                    options.reviewedPanelImagePages = Set(parts.compactMap { Int($0) })
                case "--ocr-language-correction":
                    // An opt-in with a measured cost to codes, dates and names (#108), so it
                    // takes an explicit value rather than standing as a bare switch.
                    switch value {
                    case "on": options.ocrLanguageCorrection = true
                    case "off": options.ocrLanguageCorrection = false
                    default: throw ConversionError.invalidOptions(
                        "unknown OCR language-correction setting: \(value) (expected on or off)")
                    }
                case "--reference-images":
                    switch value {
                    case "automatic": options.referenceImages = .automatic
                    case "always": options.referenceImages = .always
                    case "never": options.referenceImages = .never
                    default: throw ConversionError.invalidOptions("unknown reference-image policy: \(value)")
                    }
                case "--repeated-headers-and-footers":
                    switch value {
                    case "remove": options.removeRepeatedHeadersAndFooters = true
                    case "keep": options.removeRepeatedHeadersAndFooters = false
                    default: throw ConversionError.invalidOptions(
                        "unknown repeated header/footer policy: \(value) (expected remove or keep)")
                    }
                case "--full-page-image-encoding": options.fullPageImageEncoding = try encoding(value)
                case "--region-image-encoding": options.regionImageEncoding = try encoding(value)
                case "--maximum-output-bytes": options.maximumOutputBytes = try byteLimit(value) ?? .max
                case "--maximum-epub-bytes": options.maximumEPUBBytes = try byteLimit(value)
                case "--raster-dpi":
                    guard let dpi = Double(value), dpi.isFinite, (72...600).contains(dpi) else {
                        throw ConversionError.invalidOptions("raster DPI must be a number in 72...600")
                    }
                    options.rasterDPI = dpi
                case "--maximum-raster-pixels":
                    guard let pixels = Int(value), (1...48_000_000).contains(pixels) else {
                        throw ConversionError.invalidOptions("maximum raster pixels must be an integer in 1...48000000")
                    }
                    options.maximumRasterPixels = pixels
                case "--language":
                    // The tag decides dc:language, the recognizer's language where it supports
                    // one, and the rules that only hold for a declared language — English word
                    // breaks, the Cyrillic look-alike repair, East Asian spacing (#108).
                    let tag = value.trimmingCharacters(in: .whitespaces)
                    guard !tag.isEmpty, tag.count <= 35,
                          tag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                          tag.first?.isLetter == true, !tag.hasSuffix("-"), !tag.contains("--") else {
                        throw ConversionError.invalidOptions("language must be a BCP 47 tag, e.g. en, zh-Hans or ar")
                    }
                    options.language = tag
                case "--password-file":
                    // Read from a file or standard input so that the secret is never an argument
                    // another user of the machine can read from the process list (#252).
                    let data: Data
                    if value == "-" {
                        data = FileHandle.standardInput.readDataToEndOfFile()
                    } else if let contents = FileManager.default.contents(atPath: value) {
                        data = contents
                    } else {
                        throw ConversionError.invalidOptions("cannot read the password file")
                    }
                    guard data.count <= 4_096 else {
                        throw ConversionError.invalidOptions("the password file is larger than 4096 bytes")
                    }
                    guard var password = String(data: data, encoding: .utf8) else {
                        throw ConversionError.invalidOptions("the password file is not UTF-8 text")
                    }
                    // One trailing newline belongs to the file, not to the password, which may
                    // itself contain spaces and is otherwise taken exactly as written.
                    if password.hasSuffix("\r\n") { password.removeLast(2) }
                    else if password.hasSuffix("\n") { password.removeLast() }
                    guard !password.isEmpty else {
                        throw ConversionError.invalidOptions("the password file states no password")
                    }
                    options.password = ConversionOptions.Password(password)
                case "--package-identifier": options.packageIdentifier = value
                case "--modification-date":
                    guard let date = ISO8601DateFormatter().date(from: value) else {
                        throw ConversionError.invalidOptions("modification date must be ISO 8601, e.g. 2026-01-01T00:00:00Z")
                    }
                    options.modificationDate = date
                default: throw ConversionError.invalidOptions("unknown option: \(flag)")
                }
            }
            let report = try await PDFConverter().convert(from: URL(fileURLWithPath: args[0]),
                to: URL(fileURLWithPath: args[1]), options: options) { event in
                    let line = "\(Int(event.fractionCompleted * 100))% \(event.stage.rawValue)"
                        + (event.page.map { " page \($0)/\(event.totalPages)" } ?? "") + "\n"
                    FileHandle.standardError.write(Data(line.utf8))
                }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
