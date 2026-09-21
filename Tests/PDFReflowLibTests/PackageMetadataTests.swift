import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-metadata-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// A one-page PDF whose information dictionary is exactly `info`.
private func statingPDF(_ info: String) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("BT /F1 12 Tf 20 100 Td (The document states its own metadata.) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ], info: info)
}

/// The package document of a conversion of that PDF.
private func package(_ info: String, options: ConversionOptions = ConversionOptions(),
                     in directory: URL, name: String = "book") async throws -> String {
    let source = directory.appendingPathComponent(name + ".pdf")
    try statingPDF(info).write(to: source)
    let output = directory.appendingPathComponent(name + ".epub")
    _ = try await PDFConverter().convert(from: source, to: output, options: options)
    return String(decoding: try Archive(url: output, accessMode: .read).entryData("EPUB/package.opf"), as: UTF8.self)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/253")) func aStatedValueIsNormalizedOnceOnItsWayIntoXML() {
    #expect(SourceMetadata.stated("Tyler Wallace") == "Tyler Wallace")
    // A producer wraps an abstract; the package document wants one line of it.
    #expect(SourceMetadata.stated("A review\nis   presented\tof the mechanism.") == "A review is presented of the mechanism.")
    // Terse is still stated: the IRS publication's author is an internal routing code.
    #expect(SourceMetadata.stated("W:CAR:MP:FP") == "W:CAR:MP:FP")
    #expect(SourceMetadata.stated("\u{0008}Bell\u{000C}rung") == "Bellrung")
    #expect(SourceMetadata.stated("") == nil)
    #expect(SourceMetadata.stated("   \n ") == nil)
    #expect(SourceMetadata.stated("--") == nil)
    #expect(SourceMetadata.stated("Unknown") == nil)
    #expect(SourceMetadata.stated("  n/a ") == nil)
    #expect(SourceMetadata.stated(42) == nil)
    #expect(SourceMetadata.stated(nil) == nil)
    let longest = String(repeating: "a", count: SourceMetadata.maximumCharacters)
    #expect(SourceMetadata.stated(longest) == longest)
    #expect(SourceMetadata.stated(longest + "a") == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/253")) func keywordsArriveAsAnArrayOrAStringAndBecomeOneSubjectEach() {
    // PDFKit splits what it recognizes and hands the rest back whole.
    #expect(SourceMetadata.keywords(["additive noise", "mixtures", "rank swapping"])
        == ["additive noise", "mixtures", "rank swapping"])
    #expect(SourceMetadata.keywords("algebra; geometry ; trigonometry") == ["algebra", "geometry", "trigonometry"])
    #expect(SourceMetadata.keywords(["taxes, credits"]) == ["taxes", "credits"])
    #expect(SourceMetadata.keywords("Flight, flight ,, unknown, ") == ["Flight"])
    #expect(SourceMetadata.keywords(nil).isEmpty)
    let many = (1...SourceMetadata.maximumKeywords + 10).map { "topic \($0)" }
    #expect(SourceMetadata.keywords(many).count == SourceMetadata.maximumKeywords)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/253")) func thePackageCarriesWhatTheDocumentStatesAboutItself() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let opf = try await package("""
        /Title (Disclosure Risk Assessment) /Author (William E. Yancey) \
        /Subject (A review is presented of the basic mechanism.) \
        /Keywords (additive noise, rank swapping) /CreationDate (D:20020131132519Z)
        """, in: dir)
    #expect(opf.contains("<dc:title>Disclosure Risk Assessment</dc:title>"))
    #expect(opf.contains("<dc:creator>William E. Yancey</dc:creator>"))
    #expect(opf.contains("<dc:description>A review is presented of the basic mechanism.</dc:description>"))
    #expect(opf.contains("<dc:subject>additive noise</dc:subject><dc:subject>rank swapping</dc:subject>"))
    // The file's creation date, which is not a claim about publication.
    #expect(opf.contains("<meta property=\"dcterms:created\">2002-01-31T13:25:19Z</meta>"))
    #expect(!opf.contains("<dc:date>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/253")) func aClientValueWinsOverTheDocumentAndADocumentThatStatesNothingAddsNothing() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    var options = ConversionOptions()
    options.title = "The Client's Title"
    options.author = "The Client's Author"
    let overridden = try await package("/Title (Stated Title) /Author (Stated Author)", options: options, in: dir)
    #expect(overridden.contains("<dc:title>The Client&apos;s Title</dc:title>"))
    #expect(overridden.contains("<dc:creator>The Client&apos;s Author</dc:creator>"))
    #expect(!overridden.contains("Stated Author"))

    // A producer's placeholder is not a statement, and neither is an absent key.
    let silent = try await package("/Author (Unknown) /Subject ( ) /Keywords ()", in: dir, name: "silent")
    #expect(!silent.contains("<dc:creator>"))
    #expect(!silent.contains("<dc:description>"))
    #expect(!silent.contains("<dc:subject>"))
    #expect(!silent.contains("dcterms:created"))
    // With nothing stated and no client title, the file name names the book.
    #expect(silent.contains("<dc:title>silent</dc:title>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/253")) func statedTextIsUntrustedAndIsEscapedAndFilteredIntoTheDocument() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // UTF-16BE, as a producer writing anything but PDFDocEncoding must: 低收入家庭福利优惠.
    let opf = try await package("""
        /Author (Marks & Co </metadata><script>) \
        /Subject <FEFF4F4E653651655BB65EAD798F52294F1860E0002000280045004900430029> /CreationDate (D:20260306181349+05'00')
        """, in: dir)
    #expect(opf.contains("<dc:creator>Marks &amp; Co &lt;/metadata&gt;&lt;script&gt;</dc:creator>"))
    #expect(opf.contains("<dc:description>低收入家庭福利优惠 (EIC)</dc:description>"))
    #expect(opf.contains("<meta property=\"dcterms:created\">2026-03-06T13:13:49Z</meta>"))
}
