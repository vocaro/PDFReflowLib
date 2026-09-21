import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreflow-locked-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// `prose.pdf` written again behind a password, by PDFKit's own writer.
private func lockedProse(in directory: URL, user: String = "test-reader") throws -> URL {
    let document = try #require(PDFDocument(url: fixtureURL("prose.pdf")))
    let locked = directory.appendingPathComponent("locked.pdf")
    #expect(document.write(to: locked, withOptions: [.ownerPasswordOption: "test-owner",
                                                     .userPasswordOption: user]))
    return locked
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/252"))
func aLockedDocumentConvertsWithThePasswordTheCallerAlreadyHas() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    var options = ConversionOptions()
    options.password = ConversionOptions.Password("test-reader")
    let output = dir.appendingPathComponent("book.epub")
    let report = try await PDFConverter().convert(from: try lockedProse(in: dir), to: output, options: options)
    #expect(report.pageCount == 3)
    let html = try Archive(url: output, accessMode: .read).chapter()
    #expect(html.contains("ordinary hard-wrapped lines that belong together"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/252"))
func aDocumentThatDoesNotUnlockIsStillRefusedAndLeavesNothingBehind() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = try lockedProse(in: dir)
    for password in [nil, ConversionOptions.Password("not the password")] {
        var options = ConversionOptions()
        options.password = password
        do {
            _ = try await PDFConverter().convert(from: source, to: dir.appendingPathComponent("book.epub"),
                                                 options: options)
            Issue.record("A document that does not unlock must not convert")
        } catch ConversionError.encryptedPDF {
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["locked.pdf"])
        }
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/252"))
func theStandardSecurityHandlerAnOlderBookUsesUnlocksAsWell() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    // The committed fixture is 40-bit RC4 at revision 2, which is what PDF 1.4 documents carry;
    // PDFKit's own writer, used above, produces a modern handler instead.
    var options = ConversionOptions()
    options.password = ConversionOptions.Password("reflow")
    let output = dir.appendingPathComponent("book.epub")
    _ = try await PDFConverter().convert(from: fixtureURL("encrypted.pdf"), to: output, options: options)
    let html = try Archive(url: output, accessMode: .read).chapter()
    #expect(html.contains("A locked page reflows once its password unlocks it."))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/252"))
func everyPathThatOpensTheDocumentAgainAppliesThePassword() throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = try lockedProse(in: dir)
    let password = ConversionOptions.Password("test-reader")
    // The page window reopens the file as it moves; without the password the reopen reads nothing.
    let pages = try PDFPageSource(url: source, password: password)
    pages.releaseCachedPages()
    #expect(throws: Never.self) { _ = try pages.page(at: 0) }
    // Core Graphics opens the document itself for the structure tree, and refuses it locked.
    #expect(SourceDocument.openCore(source, password: password) != nil)
    #expect(SourceDocument.openCore(source, password: nil) == nil)
    #expect(SourceDocument.openCore(source, password: ConversionOptions.Password("wrong")) == nil)
    // The outline read opens its own document too.
    #expect(throws: Never.self) { _ = try ChapterBoundaryReader.read(source, password: password) }
    #expect(try StructureTreeReader.read(source, password: password).rejected == false)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/252"))
func aPasswordIsRedactedWhereverOptionsAreDescribed() async throws {
    let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
    let secret = "correct-horse-battery-staple"
    var options = ConversionOptions()
    options.password = ConversionOptions.Password(secret)
    #expect(String(describing: options.password!) == "<redacted>")
    #expect(!String(describing: options).contains(secret))
    #expect(!String(reflecting: options).contains(secret))
    var dumped = ""
    dump(options, to: &dumped)
    #expect(!dumped.contains(secret))

    // Nor does it reach anything the conversion hands back.
    options.password = ConversionOptions.Password("test-reader")
    let output = dir.appendingPathComponent("book.epub")
    let report = try await PDFConverter().convert(from: try lockedProse(in: dir), to: output, options: options)
    let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
    #expect(!encoded.contains("test-reader"))
    #expect(!report.warnings.contains { $0.message.contains("test-reader") })
}
