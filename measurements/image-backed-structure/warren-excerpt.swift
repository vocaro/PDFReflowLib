import PDFKit
// usage: excerpt <source.pdf> <output.pdf>: Warren pages 1, 7, 21, 30, 50, 100, 890, 910, 920
let args = CommandLine.arguments
let source = PDFDocument(url: URL(fileURLWithPath: args[1]))!
let output = PDFDocument()
for (i, n) in [1, 7, 21, 30, 50, 100, 890, 910, 920].enumerated() {
    output.insert(source.page(at: n - 1)!.copy() as! PDFPage, at: i)
}
precondition(output.write(to: URL(fileURLWithPath: args[2])))
print(output.pageCount)
