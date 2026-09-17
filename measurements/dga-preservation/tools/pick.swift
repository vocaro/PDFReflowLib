import PDFKit
// usage: pick <source.pdf> <output.pdf> <page>...
let args = CommandLine.arguments
let source = PDFDocument(url: URL(fileURLWithPath: args[1]))!
let output = PDFDocument()
for (i, n) in args.dropFirst(3).compactMap({ Int($0) }).enumerated() {
    output.insert(source.page(at: n - 1)!.copy() as! PDFPage, at: i)
}
precondition(output.write(to: URL(fileURLWithPath: args[2])))
print(output.pageCount)
