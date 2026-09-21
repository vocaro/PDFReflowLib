import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-labels-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// A five-page PDF whose catalog states `labels` as its `/PageLabels` number tree.
private func labeledPDF(_ labels: String) -> Data {
    let pages = (0..<5).map { "\($0 * 2 + 4) 0 R" }.joined(separator: " ")
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [\(labels)] >> >>",
        "<< /Type /Pages /Kids [\(pages)] /Count 5 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    for page in 1...5 {
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] "
            + "/Resources << /Font << /F1 3 0 R >> >> /Contents \(objects.count + 2) 0 R >>")
        objects.append(testPDFStream("BT /F1 12 Tf 20 100 Td (Sheet number \(page) of the book.) Tj ET"))
    }
    return testPDF(objects: objects)
}

private func convert(_ labels: String, in directory: URL, name: String = "book") async throws -> Archive {
    let source = directory.appendingPathComponent(name + ".pdf")
    try labeledPDF(labels).write(to: source)
    let output = directory.appendingPathComponent(name + ".epub")
    _ = try await PDFConverter().convert(from: source, to: output)
    return try Archive(url: output, accessMode: .read)
}

/// Every `id`/`aria-label` pair among the spine documents, in order.
private func markers(_ archive: Archive) throws -> [(String, String)] {
    var found: [(String, String)] = []
    for number in 1... {
        guard archive["EPUB/chapter-\(number).xhtml"] != nil else { break }
        for match in try archive.chapter(number).matches(of: /id="(page-\d+)" aria-label="([^"]*)"/) {
            found.append((String(match.1), String(match.2)))
        }
    }
    return found
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/248"))
func aLabelIsWhatAReaderCouldSeePrintedOnThePage() {
    #expect(SourceMetadata.pageLabel("xii") == "xii")
    #expect(SourceMetadata.pageLabel("cover-108") == "cover-108")
    #expect(SourceMetadata.pageLabel(" A-5 ") == "A-5")
    #expect(SourceMetadata.pageLabel(nil) == nil)
    #expect(SourceMetadata.pageLabel("") == nil)
    #expect(SourceMetadata.pageLabel("   ") == nil)
    // A producer that writes prose into a page label is not stating a page number.
    #expect(SourceMetadata.pageLabel(String(repeating: "x", count: SourceMetadata.maximumLabelCharacters)) != nil)
    #expect(SourceMetadata.pageLabel(String(repeating: "x", count: SourceMetadata.maximumLabelCharacters + 1)) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/248"))
func thePageListCarriesThePrintedNumberWhileFragmentsStayPhysical() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // Front matter in roman numerals, then a body that restarts at 1: the shape of every book
    // whose page-list used to match nothing a reader can see.
    let archive = try await convert("0 << /S /r >> 3 << /S /D /St 1 >>", in: dir)
    let nav = try archive.entryText("EPUB/nav.xhtml")
    let list = try #require(nav.split(separator: "page-list").last)
    let entries = list.matches(of: /href="[^"]*#(page-\d+)">([^<]*)</).map { (String($0.1), String($0.2)) }
    #expect(entries.map(\.0) == ["page-1", "page-2", "page-3", "page-4", "page-5"])
    #expect(entries.map(\.1) == ["i", "ii", "iii", "1", "2"])
    #expect(try markers(archive).map(\.1) == ["i", "ii", "iii", "1", "2"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/248"))
func twoPagesMayPrintTheSameNumberAndStillHaveDistinctAnchors() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // A cover sheet and the first body page both printed `1`, as the dietary guidelines do.
    let archive = try await convert("0 << /S /D /St 1 >> 1 << /S /D /St 1 >>", in: dir)
    let found = try markers(archive)
    #expect(found.map(\.0) == ["page-1", "page-2", "page-3", "page-4", "page-5"])
    #expect(found.map(\.1) == ["1", "1", "2", "3", "4"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/248"))
func anUnusableLabelLeavesThePhysicalNumberToSpeakForThePage() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // A label longer than a reader could have seen, and one that is only a space.
    let prefix = String(repeating: "long ", count: 12)
    let archive = try await convert("0 << /S /D /P (\(prefix)) >> 3 << /P ( ) >>", in: dir)
    #expect(try markers(archive).map(\.1) == ["1", "2", "3", "4", "5"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/248"))
func aDocumentThatDeclaresNoLabelsIsUnchanged() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("plain.pdf")
    // The same five pages, with the /PageLabels entry removed from the catalog.
    let data = String(decoding: labeledPDF("0 << /S /D >>"), as: UTF8.self)
        .replacingOccurrences(of: " /PageLabels << /Nums [0 << /S /D >>] >>", with: "")
    try Data(data.utf8).write(to: source)
    let output = dir.appendingPathComponent("plain.epub")
    let report = try await PDFConverter().convert(from: source, to: output)
    let archive = try Archive(url: output, accessMode: .read)
    #expect(try markers(archive).map(\.1) == ["1", "2", "3", "4", "5"])
    // Report counts and warning pages are physical, so a developer can find the page in the file.
    #expect(report.pageCount == 5)
    #expect(report.warnings.allSatisfy { (1...5).contains($0.page) })
}
