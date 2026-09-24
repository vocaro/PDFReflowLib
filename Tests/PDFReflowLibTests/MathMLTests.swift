import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/206"))
func mathExpressionPackagesWithADeclaredFallback() async throws {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let crop = directory.appendingPathComponent("row.png")
    try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl8Vx8AAAAASUVORK5CYII=")!.write(to: crop)
    let expression = MathExpression(label: "1)", node: .squareRoot(.fraction(
        .number("1"), .subscript(.identifier("x"), .number("2")))), fallbackAssetID: "row")
    let image = ReflowBlock.Image(assetID: "row", alternativeText: "formula", caption: "", link: nil,
                                  math: [expression])
    let book = ReflowDocument(metadata: .init(title: "Math", language: "en"),
                              blocks: [.init(content: .image(image), page: 1)],
                              assets: [.init(id: "row", fileURL: crop)])
    try book.validate()
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: directory,
                                   progress: { _ in })
    let chapter = try String(contentsOf: directory.appendingPathComponent("EPUB/chapter-1.xhtml"), encoding: .utf8)
    let package = try String(contentsOf: directory.appendingPathComponent("EPUB/package.opf"), encoding: .utf8)
    #expect(chapter.contains("<msqrt><mfrac><mn>1</mn><msub><mi>x</mi><mn>2</mn></msub></mfrac></msqrt>"))
    #expect(chapter.contains("altimg=\"images/image-1.png\""))
    #expect(chapter.contains("alttext=\"√(1/(x_2))\""))
    #expect(package.contains("href=\"chapter-1.xhtml\" media-type=\"application/xhtml+xml\" properties=\"mathml\""))
}
