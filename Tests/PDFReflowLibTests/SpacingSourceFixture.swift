import CoreGraphics
import Foundation

/// One source page's text-placement evidence, captured by `tools/probes/capture-spacing-source.swift`
/// from the checksum-pinned corpus: the page's own content stream, and the font metadata the
/// spacing reader reads from it (subtype, font matrix, first code, widths, encoding, `ToUnicode`).
/// `document()` rebuilds a page that places text exactly as the source does. No font program is
/// captured or rebuilt, so the page draws nothing; it is text placement, which is all the reader
/// measures. This is source evidence, never converter output.
struct SpacingSourceFixture: Decodable {
    struct Font: Decodable {
        enum Difference: Decodable {
            case code(Int)
            case glyph(String)

            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let code = try? value.decode(Int.self) { self = .code(code) }
                else { self = .glyph(try value.decode(String.self)) }
            }

            var pdf: String {
                switch self {
                case .code(let code): "\(code)"
                case .glyph(let name): name
                }
            }
        }

        enum Encoding: Decodable {
            case name(String)
            case table(base: String?, differences: [Difference])

            private enum Keys: String, CodingKey { case baseEncoding, differences }

            init(from decoder: Decoder) throws {
                if let name = try? decoder.singleValueContainer().decode(String.self) {
                    self = .name(name)
                    return
                }
                let values = try decoder.container(keyedBy: Keys.self)
                self = .table(base: try values.decodeIfPresent(String.self, forKey: .baseEncoding),
                              differences: try values.decodeIfPresent([Difference].self, forKey: .differences) ?? [])
            }

            func pdf(_ reference: (String) -> String) -> String {
                switch self {
                case .name(let name): "/" + name
                case .table(let base, let differences):
                    "<< /Type /Encoding"
                        + (base.map { " /BaseEncoding /\($0)" } ?? "")
                        + (differences.isEmpty ? "" : " /Differences [\(differences.map(\.pdf).joined(separator: " "))]")
                        + " >>"
                }
            }
        }

        var subtype: String?
        var baseFont: String?
        var fontMatrix: [Double]?
        var firstChar: Int?
        var widths: [Double]?
        var encoding: Encoding?
        var toUnicode: String?
    }

    var sourceSHA256: String
    var page: Int
    var mediaBox: [Double]
    var cropBox: [Double]
    var rotation: Int
    var content: String
    var fonts: [String: Font]
    var extGStates: [String]
    var xObjects: [String: String]

    static func load(_ name: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: fixtureURL("\(name)-spacing.json")))
    }

    /// The rebuilt page, as one PDF document.
    func document() throws -> CGPDFDocument {
        var builder = PDFBytes()
        var fontEntries: [String] = []
        for (name, font) in fonts.sorted(by: { $0.key < $1.key }) {
            var entries = ["/Type /Font"]
            if let subtype = font.subtype { entries.append("/Subtype /\(subtype)") }
            if let baseFont = font.baseFont { entries.append("/BaseFont /\(baseFont)") }
            if let matrix = font.fontMatrix { entries.append("/FontMatrix [\(matrix.map(PDFBytes.number).joined(separator: " "))]") }
            if let first = font.firstChar { entries.append("/FirstChar \(first)") }
            if let widths = font.widths {
                entries.append("/LastChar \((font.firstChar ?? 0) + widths.count - 1)")
                entries.append("/Widths [\(widths.map(PDFBytes.number).joined(separator: " "))]")
            }
            if let encoding = font.encoding { entries.append("/Encoding " + encoding.pdf { $0 }) }
            if let map = font.toUnicode { entries.append("/ToUnicode " + builder.addStream(map)) }
            fontEntries.append("/\(name) " + builder.add("<< " + entries.joined(separator: " ") + " >>"))
        }
        var xObjectEntries: [String] = []
        for (name, subtype) in xObjects.sorted(by: { $0.key < $1.key }) {
            let extra = subtype == "Form" ? " /Type /XObject /Subtype /Form /BBox [0 0 1 1]" : " /Type /XObject /Subtype /\(subtype)"
            xObjectEntries.append("/\(name) " + builder.addStream("", extra: extra))
        }
        let contents = builder.addStream(content)
        var resources = ["/Font << \(fontEntries.joined(separator: " ")) >>"]
        if !extGStates.isEmpty {
            resources.append("/ExtGState << \(extGStates.map { "/\($0) << >>" }.joined(separator: " ")) >>")
        }
        if !xObjectEntries.isEmpty { resources.append("/XObject << \(xObjectEntries.joined(separator: " ")) >>") }
        let parent = builder.reserve()
        let page = builder.add("""
            << /Type /Page /Parent \(parent) /MediaBox [\(mediaBox.map(PDFBytes.number).joined(separator: " "))] \
            /CropBox [\(cropBox.map(PDFBytes.number).joined(separator: " "))] /Rotate \(rotation) \
            /Resources << \(resources.joined(separator: " ")) >> /Contents \(contents) >>
            """)
        builder.fill(parent, "<< /Type /Pages /Kids [\(page)] /Count 1 >>")
        let catalog = builder.add("<< /Type /Catalog /Pages \(parent) >>")
        guard let provider = CGDataProvider(data: builder.data(root: catalog) as CFData),
              let document = CGPDFDocument(provider) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }
}

/// A byte-exact PDF writer. The captured content stream and `ToUnicode` maps hold bytes outside
/// ASCII (glyph codes, CMap text), so every object is written through Latin-1, which round-trips
/// each byte; `testPDF`'s UTF-8 writer would re-encode them and change the codes a show draws.
struct PDFBytes {
    private var objects: [Data?] = []

    static func latin1(_ text: String) -> Data { text.data(using: .isoLatin1) ?? Data(text.utf8) }

    /// A PDF number: integral values without the `.0` a `Double` would print.
    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    mutating func add(_ object: String) -> String {
        objects.append(Self.latin1(object))
        return "\(objects.count) 0 R"
    }

    mutating func addStream(_ body: String, extra: String = "") -> String {
        let payload = Self.latin1(body)
        var data = Self.latin1("<< /Length \(payload.count)\(extra) >>\nstream\n")
        data.append(payload)
        data.append(Self.latin1("\nendstream"))
        objects.append(data)
        return "\(objects.count) 0 R"
    }

    /// An object number to fill in later, for a reference cycle (a page and its `Parent`).
    mutating func reserve() -> String {
        objects.append(nil)
        return "\(objects.count) 0 R"
    }

    mutating func fill(_ reference: String, _ object: String) {
        objects[Int(reference.split(separator: " ")[0])! - 1] = Self.latin1(object)
    }

    func data(root: String) -> Data {
        var data = Self.latin1("%PDF-1.7\n")
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Self.latin1("\(index + 1) 0 obj\n"))
            data.append(object ?? Self.latin1("null"))
            data.append(Self.latin1("\nendobj\n"))
        }
        let xref = data.count
        data.append(Self.latin1("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n"))
        for offset in offsets { data.append(Self.latin1(String(format: "%010d 00000 n \n", offset))) }
        data.append(Self.latin1("trailer\n<< /Size \(offsets.count + 1) /Root \(root) >>\nstartxref\n\(xref)\n%%EOF\n"))
        return data
    }
}
