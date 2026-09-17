import Foundation
import PDFKit

// usage: spacing-census <pdf> <lines-out> <repairs-out>
// stdout: one TSV row per page with at least one simple font (Type1/TrueType/MMType1) carrying both
// ToUnicode and Widths in the page's own resources, the only fonts NativeSpacingReader measures.
// Columns: page, styled (the pipeline's includeStyle gate), simple fonts, maps the strict parser
// (`unicodeMap`, as on 9884ed6) rejects, of those the ones a one-byte reading of an Adobe
// `<0000> <FFFF>` codespace accepts, other rejections by reason, evidence shows, decoded shows,
// measured shows, and the first reason the instrumented reader copy (CensusSpacingReader, generated
// from the compiled tree) disqualified the page. Both parses come from the same binary; the evidence
// columns depend on the tree and generator options the binary was built with.
// <lines-out>: page, line index, line text from NativeTextReader exactly as the pipeline requests it
// (the product reader), for diffing a baseline build's lines against a candidate's.
// <repairs-out>: every line CensusSpacingReader.apply changes, mirroring NativeTextReader's loop:
// page, before, after, and the matched shows (decoded text, origin x, measured end, size, font id).
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let doc = PDFDocument(url: url)!
func output(_ path: String) -> FileHandle {
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)!
}
let linesOut = output(CommandLine.arguments[2]), repairsOut = output(CommandLine.arguments[3])
func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
}

func adobeOneByte(_ data: Data) -> Data? {
    guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
    return text.replacingOccurrences(of: #"begincodespacerange\s*<0000>\s*<[fF]{4}>\s*endcodespacerange"#,
        with: "begincodespacerange <00> <FF> endcodespacerange", options: .regularExpression).data(using: .isoLatin1)
}
func reason(_ data: Data) -> String {
    guard let text = String(data: data, encoding: .isoLatin1) else { return "encoding" }
    if text.contains("usecmap") { return "usecmap" }
    if data.count > 65_536 { return "size" }
    guard let range = text.range(of: #"begincodespacerange[\s\S]*?endcodespacerange"#, options: .regularExpression) else { return "noCodespace" }
    let space = text[range].replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    var result = "codespace(\(space.dropFirst(20).dropLast(18)))"
    // A source code of four hex digits at the start of a mapping line (bfchar or bfrange).
    if let entry = text[range.upperBound...].range(of: #"(?m)^[ \t]*<[0-9a-fA-F]{4}>[ \t]*<[0-9a-fA-F]+>"#, options: .regularExpression) {
        let sample = text[entry].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"[\s,=]+"#, with: " ", options: .regularExpression)
        result += "+twoByteEntry(\(sample))"
    }
    return result
}

final class Box { var rows: [(String, CGPDFDictionaryRef)] = [] }
func pageFonts(_ page: CGPDFPage) -> [(String, CGPDFDictionaryRef)] {
    var node: CGPDFDictionaryRef? = page.dictionary
    for _ in 0..<64 {
        guard let current = node else { return [] }
        var resources: CGPDFDictionaryRef?, fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
            guard CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return [] }
            let box = Box()
            CGPDFDictionaryApplyFunction(fonts, { key, object, info in
                var dict: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return }
                Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue().rows.append((String(cString: key), dict))
            }, Unmanaged.passUnretained(box).toOpaque())
            return box.rows
        }
        var parent: CGPDFDictionaryRef?
        _ = CGPDFDictionaryGetDictionary(current, "Parent", &parent)
        node = parent
    }
    return []
}

print("page\tstyled\tsimpleFonts\tstrictRejected\toneByteAccepted\totherRejected\tshows\tdecoded\tmeasured\tinvalid")
for n in 1...doc.pageCount {
    autoreleasepool {
        guard let page = doc.page(at: n - 1), let ref = page.pageRef else { return }
        let bounds = page.bounds(for: .cropBox)
        let g = GraphicsReader.read(ref)
        let requires = g.unsupported || page.rotation % 360 != 0
        let synthetic = g.hasOnlyInvisibleText && g.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 }
        let styled = !requires && !synthetic
        let lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: styled)) ?? []
        var buffer = ""
        for (index, line) in lines.enumerated() { buffer += "\(n)\t\(index)\t\(escaped(line.text))\n" }
        linesOut.write(buffer.data(using: .utf8)!)

        let evidence = styled ? CensusSpacingReader.read(ref) : []
        let reader = CensusSpacingReader.lastReason
        if !evidence.isEmpty, let selection = page.selection(for: bounds) {
            let selections = selection.selectionsByLine()
            let boundsByLine = selections.map { $0.bounds(for: page) }
            var repairs = ""
            for line in selections {
                guard let raw = line.string,
                      !raw.replacingOccurrences(of: "\u{FFFC}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let lineBounds = line.bounds(for: page)
                guard lineBounds.isFinite, !lineBounds.isNull, lineBounds.width > 0, lineBounds.height > 0,
                      let attributed = line.attributedString, attributed.string == raw else { continue }
                let repaired = CensusSpacingReader.apply(evidence, to: attributed, bounds: lineBounds, allBounds: boundsByLine)
                guard repaired.string != raw else { continue }
                let shows = evidence.filter { lineBounds.insetBy(dx: -0.75, dy: -0.75).contains($0.origin) }
                    .sorted { $0.origin.x < $1.origin.x }
                    .map { "\(escaped($0.unicode ?? "?"))@\(String(format: "%.2f", $0.origin.x))-\($0.end.map { String(format: "%.2f", $0) } ?? "?")/\(String(format: "%.2f", $0.size))/f\($0.font % 100_000)" }
                repairs += "\(n)\t\(escaped(raw))\t\(escaped(repaired.string))\t\(shows.joined(separator: " | "))\n"
            }
            repairsOut.write(repairs.data(using: .utf8)!)
        }

        var simple = 0, strictRejected = 0, oneByte = 0
        var other: [String: Int] = [:]
        for (_, font) in pageFonts(ref) {
            var subtype: UnsafePointer<CChar>?, stream: CGPDFStreamRef?, widths: CGPDFArrayRef?
            guard CGPDFDictionaryGetName(font, "Subtype", &subtype), let subtype,
                  ["Type1", "TrueType", "MMType1"].contains(String(cString: subtype)),
                  CGPDFDictionaryGetStream(font, "ToUnicode", &stream), let stream,
                  CGPDFDictionaryGetArray(font, "Widths", &widths) else { continue }
            simple += 1
            var format = CGPDFDataFormat.raw
            guard let cf = CGPDFStreamCopyData(stream, &format), format == .raw else { other["streamFormat", default: 0] += 1; strictRejected += 1; continue }
            let data = cf as Data
            if NativeSpacingReader.unicodeMap(data) != nil { continue }
            strictRejected += 1
            if data.count <= 65_536, let normalized = adobeOneByte(data), NativeSpacingReader.unicodeMap(normalized) != nil {
                oneByte += 1
            } else {
                other[reason(data), default: 0] += 1
            }
        }
        guard simple > 0 else { return }
        let otherText = other.isEmpty ? "-" : other.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        print("\(n)\t\(styled)\t\(simple)\t\(strictRejected)\t\(oneByte)\t\(otherText)\t\(evidence.count)\t\(evidence.filter { $0.unicode != nil }.count)\t\(evidence.filter { $0.end != nil }.count)\t\(reader ?? "-")")
    }
}
