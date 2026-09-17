import PDFKit
// usage: excerpt <source.pdf> <output.pdf> <first> <last>
let args = CommandLine.arguments
let source = PDFDocument(url: URL(fileURLWithPath: args[1]))!
let output = PDFDocument()
for (i, n) in (Int(args[3])!...Int(args[4])!).enumerated() {
    output.insert(source.page(at: n - 1)!.copy() as! PDFPage, at: i)
}
precondition(output.write(to: URL(fileURLWithPath: args[2])))
print(output.pageCount)
