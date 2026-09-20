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
    /// An XObject the page draws, by name and subtype. Only the subtype matters to a tag
    /// reader, which refuses anything that is not a placed image, so the replay carries a
    /// one-pixel stand-in rather than the source's artwork.
    struct XObject: Decodable {
        var name: String
        var subtype: String?
    }
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

    /// The captured page as a one-page PDF: the same content stream, the same fonts, the same
    /// structure graph, renumbered. Nothing here is invented; a `nil` role or absent `Pg` is
    /// reproduced as the source has it.
    func pdf() -> Data {
        let catalog = 1, pages = 2, root = 3, page = 4, parentTreeObject = 5, contents = 6, roles = 7
        var objects = [String](repeating: "<< >>", count: 7)
        var numbers: [Int: Int] = [:]
        // Fonts first, each followed by its `ToUnicode` stream, then the structure elements.
        var next = objects.count + 1
        var resources: [String] = []
        for font in fonts {
            var entries = ["/Type /Font"]
            if let subtype = font.subtype { entries.append("/Subtype /\(subtype)") }
            if let encoding = font.encoding { entries.append("/Encoding /\(encoding)") }
            if let map = font.toUnicode {
                entries.append("/ToUnicode \(next + 1) 0 R")
                objects.append("<< \(entries.joined(separator: " ")) >>")
                objects.append(testPDFStream(map))
                resources.append("/\(font.name) \(next) 0 R")
                next += 2
            } else {
                objects.append("<< \(entries.joined(separator: " ")) >>")
                resources.append("/\(font.name) \(next) 0 R")
                next += 1
            }
        }
        var drawn: [String] = []
        for object in xobjects {
            objects.append(testPDFStream("x", extra: "/Type /XObject /Subtype /\(object.subtype ?? "Form")"
                + (object.subtype == "Image" ? " /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8" : " /BBox [0 0 1 1]")))
            drawn.append("/\(object.name) \(next) 0 R")
            next += 1
        }
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
