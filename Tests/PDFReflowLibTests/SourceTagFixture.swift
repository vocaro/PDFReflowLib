import CoreGraphics
import Foundation
@testable import PDFReflowLib

struct UnreadableFixture: Error {}

/// One corpus page's tag evidence, captured from the source PDF with qpdf by
/// `tools/capture_tag_fixture.py`: its decoded content stream, its font resources (subtype,
/// encoding and decoded `ToUnicode` map), its XObject subtypes and the structure subtree its
/// `ParentTree` entry names, with every ancestor. `pdf()` replays that evidence as a one-page
/// document, so a reader test reads the source's own bytes rather than a paraphrase of them.
struct SourceTagFixture: Decodable {
    struct Element: Decodable {
        /// A child is either an MCID or another captured element.
        enum Kid: Decodable {
            case mcid(Int)
            case element(Int)
            init(from decoder: Decoder) throws {
                let values = try decoder.singleValueContainer()
                if let id = try? values.decode(Int.self) { self = .mcid(id); return }
                struct Reference: Decodable { var element: Int }
                self = .element(try values.decode(Reference.self).element)
            }
        }
        var object: Int
        var role: String?
        var parent: Int?
        var page: Bool
        var kids: [Kid]
    }
    struct Font: Decodable {
        var name: String
        var subtype: String?
        var encoding: String?
        var toUnicode: String?
    }
    /// An XObject the page draws. An image places no text, so the replay carries a one-pixel
    /// stand-in for its artwork; a Form can show text, so it carries the source's own content
    /// stream, box, matrix, fonts and nested XObjects instead (#241).
    struct XObject: Decodable {
        var name: String
        var subtype: String?
        var bbox: [Double]?
        var matrix: [Double]?
        var contentStream: String?
        var fonts: [Font]?
        var properties: [String: Property]?
        var xobjects: [XObject]?
    }
    /// A `/Properties` entry a `BDC` names. A tag reader reads one key from it, `/MCID`.
    struct Property: Decodable { var mcid: Int? }
    var sourceSHA256: String
    var page: Int
    var mediaBox: [Double]
    var structParents: Int
    var roleMap: [String: String]
    var rootKids: [Int]
    var parentTree: [String: Int]
    var elements: [Element]
    var fonts: [Font]
    var xobjects: [XObject]
    var properties: [String: Property]?
    var contentStream: String
    var provenance: String

    static func load(_ name: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: fixtureURL("\(name)-tags.json")))
    }

    /// The MCIDs the source marks with each role, for a test to state what it expects.
    func identifiers(role: String) -> [Int] {
        let byObject = Dictionary(uniqueKeysWithValues: elements.map { ($0.object, $0) })
        return parentTree.compactMap { key, owner in
            byObject[owner]?.role == role ? Int(key) : nil
        }.sorted()
    }

    /// A resource dictionary's `/Properties` entry, or nil when the stream names none.
    private static func propertyEntries(_ properties: [String: Property]?) -> String? {
        guard let properties, !properties.isEmpty else { return nil }
        let entries = properties.sorted { $0.key < $1.key }.map { name, property in
            "/\(name) << \(property.mcid.map { "/MCID \($0)" } ?? "") >>"
        }
        return "/Properties << \(entries.joined(separator: " ")) >>"
    }

    /// The captured page as a one-page PDF: the same content stream, the same fonts, the same
    /// structure graph, renumbered. Nothing here is invented; a `nil` role or absent `Pg` is
    /// reproduced as the source has it.
    func pdf() -> Data {
        let catalog = 1, pages = 2, root = 3, page = 4, parentTreeObject = 5, contents = 6, roles = 7
        var objects = [String](repeating: "<< >>", count: 7)
        var numbers: [Int: Int] = [:]
        // Fonts first, each followed by its `ToUnicode` stream, then the structure elements.
        var next = objects.count + 1
        /// Writes one font and its `ToUnicode` stream, answering the resource entry for it.
        func emit(_ font: Font) -> String {
            var entries = ["/Type /Font"]
            if let subtype = font.subtype { entries.append("/Subtype /\(subtype)") }
            if let encoding = font.encoding { entries.append("/Encoding /\(encoding)") }
            if let map = font.toUnicode {
                entries.append("/ToUnicode \(next + 1) 0 R")
                objects.append("<< \(entries.joined(separator: " ")) >>")
                objects.append(testPDFStream(map))
                defer { next += 2 }
                return "/\(font.name) \(next) 0 R"
            }
            objects.append("<< \(entries.joined(separator: " ")) >>")
            defer { next += 1 }
            return "/\(font.name) \(next) 0 R"
        }
        /// Writes one XObject and everything it names, answering its resource entry. An image is
        /// a one-pixel stand-in; a captured Form is replayed with the source's own bytes, and a
        /// Form captured before #241 (no content) keeps the empty stand-in it always had.
        func emit(_ object: XObject) -> String {
            guard object.subtype != "Image" else {
                objects.append(testPDFStream("x", extra: "/Type /XObject /Subtype /Image"
                    + " /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8"))
                defer { next += 1 }
                return "/\(object.name) \(next) 0 R"
            }
            let inner = (object.fonts ?? []).map { emit($0) }
            let nested = (object.xobjects ?? []).map { emit($0) }
            var resources: [String] = []
            if !inner.isEmpty { resources.append("/Font << \(inner.joined(separator: " ")) >>") }
            if !nested.isEmpty { resources.append("/XObject << \(nested.joined(separator: " ")) >>") }
            if let entries = Self.propertyEntries(object.properties) { resources.append(entries) }
            func array(_ values: [Double]) -> String {
                "[" + values.map { String($0) }.joined(separator: " ") + "]"
            }
            var extra = "/Type /XObject /Subtype /\(object.subtype ?? "Form")"
                + " /BBox \(object.bbox.map(array) ?? "[0 0 1 1]")"
            if let matrix = object.matrix { extra += " /Matrix \(array(matrix))" }
            extra += " /Resources << \(resources.joined(separator: " ")) >>"
            objects.append(testPDFStream(object.contentStream ?? "x", extra: extra))
            defer { next += 1 }
            return "/\(object.name) \(next) 0 R"
        }
        let resources = fonts.map { emit($0) }
        let drawn = xobjects.map { emit($0) }
        for element in elements {
            numbers[element.object] = next
            next += 1
        }
        for element in elements {
            var entries = ["/Type /StructElem"]
            if let role = element.role { entries.append("/S /\(role)") }
            entries.append("/P \(element.parent.flatMap { numbers[$0] } ?? root) 0 R")
            if element.page { entries.append("/Pg \(page) 0 R") }
            let kids = element.kids.map { kid -> String in
                switch kid {
                case .mcid(let id): "\(id)"
                case .element(let object): "\(numbers[object] ?? root) 0 R"
                }
            }
            if !kids.isEmpty { entries.append("/K [\(kids.joined(separator: " "))]") }
            objects.append("<< \(entries.joined(separator: " ")) >>")
        }
        let owners = (0...(parentTree.keys.compactMap(Int.init).max() ?? 0)).map { mcid in
            parentTree["\(mcid)"].flatMap { numbers[$0] }.map { "\($0) 0 R" } ?? "null"
        }
        objects[catalog - 1] = "<< /Type /Catalog /Pages \(pages) 0 R /StructTreeRoot \(root) 0 R /MarkInfo << /Marked true >> >>"
        objects[pages - 1] = "<< /Type /Pages /Kids [\(page) 0 R] /Count 1 >>"
        objects[roles - 1] = "<< \(roleMap.sorted { $0.key < $1.key }.map { "/\($0.key) /\($0.value)" }.joined(separator: " ")) >>"
        objects[root - 1] = "<< /Type /StructTreeRoot /RoleMap \(roles) 0 R /K [\(rootKids.compactMap { numbers[$0] }.map { "\($0) 0 R" }.joined(separator: " "))] /ParentTree \(parentTreeObject) 0 R >>"
        objects[page - 1] = "<< /Type /Page /Parent \(pages) 0 R /MediaBox [\(mediaBox.map { "\($0)" }.joined(separator: " "))]"
            + " /Resources << /Font << \(resources.joined(separator: " ")) >>"
            + (drawn.isEmpty ? "" : " /XObject << \(drawn.joined(separator: " ")) >>")
            + (Self.propertyEntries(properties).map { " " + $0 } ?? "")
            + " >> /Contents \(contents) 0 R /StructParents 0 >>"
        objects[parentTreeObject - 1] = "<< /Nums [0 [\(owners.joined(separator: " "))]] >>"
        objects[contents - 1] = testPDFStream(contentStream)
        return testPDF(objects: objects)
    }

    /// Runs `body` with the replayed page. The document is written to a temporary directory
    /// because `StructureTreeReader` reads the tree from its own `CGPDFDocument`.
    func withPage<T>(_ body: (URL, CGPDFPage) throws -> T) throws -> T {
        let directory = try testPDFDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("page.pdf")
        try pdf().write(to: url)
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else {
            throw UnreadableFixture()
        }
        return try body(url, page)
    }
}
