import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-outline-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// One entry of a fixture outline: a title, the one-based page it aims at (nil aims at nothing),
/// and the entries under it.
private struct Item {
    var title: String
    var page: Int?
    var children: [Item] = []
}

/// A PDF of `pages` pages, each drawing `body` repeated `lines` times, whose catalog states
/// `outline`. Object numbers: 1 catalog, 2 page tree, 3 font, 4 outline root, then one object
/// per outline entry in document order, then each page and its content stream.
private func outlinePDF(pages: Int, outline: [Item], lines: Int = 1) -> Data {
    var flat: [(item: Item, parent: Int, depth: Int)] = []
    func flatten(_ items: [Item], parent: Int) {
        var numbers: [Int] = []
        for item in items {
            numbers.append(5 + flat.count)
            flat.append((item, parent, 0))
            flatten(item.children, parent: numbers[numbers.count - 1])
        }
    }
    flatten(outline, parent: 4)
    let firstPageObject = 5 + flat.count
    func pageObject(_ page: Int) -> Int { firstPageObject + (page - 1) * 2 }
    /// The object numbers of the entries whose parent is `parent`, in order.
    func siblings(of parent: Int) -> [Int] {
        flat.indices.filter { flat[$0].parent == parent }.map { 5 + $0 }
    }
    var objects: [String] = []
    let kids = (1...pages).map { "\(pageObject($0)) 0 R" }.joined(separator: " ")
    objects.append("<< /Type /Catalog /Pages 2 0 R /Outlines 4 0 R >>")
    objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages) >>")
    objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    let roots = siblings(of: 4)
    objects.append("<< /Type /Outlines /First \(roots[0]) 0 R /Last \(roots[roots.count - 1]) 0 R /Count \(roots.count) >>")
    for (index, entry) in flat.enumerated() {
        let number = 5 + index
        let order = siblings(of: entry.parent)
        let position = order.firstIndex(of: number)!
        var dictionary = "/Title (\(entry.item.title)) /Parent \(entry.parent) 0 R"
        if position > 0 { dictionary += " /Prev \(order[position - 1]) 0 R" }
        if position + 1 < order.count { dictionary += " /Next \(order[position + 1]) 0 R" }
        let children = siblings(of: number)
        if !children.isEmpty {
            dictionary += " /First \(children[0]) 0 R /Last \(children[children.count - 1]) 0 R /Count \(children.count)"
        }
        if let page = entry.item.page {
            dictionary += " /Dest [\(pageObject(page)) 0 R /XYZ null null null]"
        }
        objects.append("<< \(dictionary) >>")
    }
    for page in 1...pages {
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 700] "
            + "/Resources << /Font << /F1 3 0 R >> >> /Contents \(pageObject(page) + 1) 0 R >>")
        let text = (0..<lines).map {
            "BT /F1 5 Tf 20 \(680 - Double($0) * 7.5) Td (Page \(page) line \($0 + 1): a book that keeps running on and "
                + "on, long enough that its body reaches the writer's size target and a new spine document opens.) Tj ET"
        }.joined(separator: " ")
        objects.append(testPDFStream(text))
    }
    return testPDF(objects: objects)
}

private func convert(_ data: Data, in directory: URL, name: String = "book") async throws -> Archive {
    let source = directory.appendingPathComponent(name + ".pdf")
    try data.write(to: source)
    let output = directory.appendingPathComponent(name + ".epub")
    _ = try await PDFConverter().convert(from: source, to: output)
    return try Archive(url: output, accessMode: .read)
}

/// The `toc` navigation of a converted book, as emitted.
private func toc(_ archive: Archive) throws -> String {
    let nav = try archive.entryText("EPUB/nav.xhtml")
    return String(nav.split(separator: "<nav epub:type=\"page-list\"")[0])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/249"))
func onlyAnOutlineShapedLikeAContentsBecomesNavigation() {
    // Every corpus document that states an outline, by the shape it states (measured on `main`).
    let accepted: [(String, OutlineReader.Shape, Int)] = [
        ("arxiv-replay-clocks-2023", .init(entries: 20, distinctTitles: 20, depth: 1), 12),
        ("gpo-911-2004", .init(entries: 93, distinctTitles: 93, depth: 1), 585),
        ("uscis-m618-arabic-2015", .init(entries: 49, distinctTitles: 49, depth: 1), 116),
        ("usda-ars-agresearch-2012-11", .init(entries: 11, distinctTitles: 11, depth: 0), 24),
        ("nbs-jres-geltman-1977", .init(entries: 8, distinctTitles: 8, depth: 0), 7),
        ("noaa-nca5-2023", .init(entries: 303, distinctTitles: 211, depth: 1), 1_834),
        ("irs-p596-zhs-2025", .init(entries: 56, distinctTitles: 55, depth: 2), 36),
        ("fed-explained-2021", .init(entries: 40, distinctTitles: 36, depth: 1), 135),
    ]
    for (name, shape, pages) in accepted {
        #expect(OutlineReader.isNavigation(shape, pageCount: pages), "\(name) states a contents")
    }
    // The four that state a machine's index of the file instead.
    let rejected: [(String, OutlineReader.Shape, Int)] = [
        ("faa-phak-8083-25c: a structure tree, 11 deep, 7,689 entries for 522 pages",
         .init(entries: 7_689, distinctTitles: 6_442, depth: 11), 522),
        ("cia-blue-book-14-1955: 313 entries all labeled Figure",
         .init(entries: 313, distinctTitles: 2, depth: 1), 312),
        ("gpo-warren-1964: one entry labeled Test", .init(entries: 1, distinctTitles: 1, depth: 0), 920),
        ("usgs-mcs2025-copper: one entry", .init(entries: 1, distinctTitles: 1, depth: 0), 2),
    ]
    for (name, shape, pages) in rejected {
        #expect(!OutlineReader.isNavigation(shape, pageCount: pages), "\(name) is not a contents")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/249"))
func anOutlineTitleIsBoundedAndCollapsedLikeAnyStatedValue() {
    #expect(OutlineReader.title("1 Introduction") == "1 Introduction")
    // The USCIS guide wraps one title over two lines.
    #expect(OutlineReader.title("Welcome to the United States\nA Guide for New Immigrants")
        == "Welcome to the United States A Guide for New Immigrants")
    #expect(OutlineReader.title(nil) == nil)
    #expect(OutlineReader.title("   ") == nil)
    #expect(OutlineReader.title("···") == nil)
    let longest = String(repeating: "a", count: OutlineReader.maximumTitleCharacters)
    #expect(OutlineReader.title(longest) == longest)
    #expect(OutlineReader.title(longest + "a") == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/249"))
func theAuthorsContentsBecomesNestedNavigationAcrossSpineDocuments() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // Long enough that the body target closes a document before the last page, so a contents
    // entry names a page whose spine document did not exist when the entry was read.
    let archive = try await convert(outlinePDF(pages: 14, outline: [
        Item(title: "Front matter", page: 1),
        Item(title: "Part One", page: 2, children: [
            Item(title: "A first section", page: 3),
            Item(title: "A second section", page: 8),
        ]),
        Item(title: "Part Two", page: 13),
    ], lines: 88), in: dir)
    let contents = try toc(archive)
    #expect(contents.contains("<li><a href=\"chapter-1.xhtml#page-1\">Front matter</a></li>"))
    #expect(contents.contains("<li><a href=\"chapter-1.xhtml#page-2\">Part One</a><ol>"))
    #expect(contents.contains("<a href=\"chapter-1.xhtml#page-3\">A first section</a>"))
    // The proof that resolution is deferred: a later page's document is a later file.
    let later = try #require(contents.firstMatch(of: /<a href="(chapter-\d+)\.xhtml#page-13">Part Two<\/a>/)?.1)
    #expect(later != "chapter-1")
    #expect(archive["EPUB/\(later).xhtml"] != nil)
    #expect(contents.contains("</ol></li>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/249"))
func anEntryThatAimsAtNothingGroupsItsChildrenOrIsLeftOut() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let archive = try await convert(outlinePDF(pages: 3, outline: [
        Item(title: "A group that aims at nothing", page: nil, children: [
            Item(title: "But this one aims at a page", page: 2),
        ]),
        Item(title: "A leaf that aims at nothing", page: nil),
        Item(title: "An ordinary entry", page: 3),
    ]), in: dir)
    let contents = try toc(archive)
    #expect(contents.contains("<li><span>A group that aims at nothing</span><ol>"))
    #expect(contents.contains("<a href=\"chapter-1.xhtml#page-2\">But this one aims at a page</a>"))
    #expect(!contents.contains("A leaf that aims at nothing"))
    #expect(contents.contains("An ordinary entry"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/249"))
func aDocumentWithoutAUsableOutlineKeepsTheHeadingsItDetected() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // One entry repeated is the CIA report's shape, and is refused; the detected headings stand.
    let archive = try await convert(outlinePDF(pages: 3, outline: (1...3).map {
        Item(title: "Figure", page: $0)
    }), in: dir, name: "repeated")
    #expect(!(try toc(archive)).contains("Figure"))
    let plain = try await convert(try Data(contentsOf: fixtureURL("prose.pdf")), in: dir, name: "prose")
    let contents = try toc(plain)
    #expect(contents.contains("Second Section"))
    #expect(contents.contains("Third Section"))
}
