import Foundation
import PDFKit

// Enlarges exact reviewed source pages by 3x, preserving their content. At 600 DPI each
// would exceed 48 Mpx, so every 6/12/24/48 Mpx setting exercises the ceiling itself.
let args = CommandLine.arguments
precondition(args.count == 4, "make-stress BLUE_BOOK FAA OUTPUT")
let output = URL(fileURLWithPath: args[3])
guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else { fatalError("PDF context") }
for (source, number) in [(args[1], 74), (args[2], 121)] {
    guard let document = CGPDFDocument(URL(fileURLWithPath: source) as CFURL),
          let page = document.page(at: number) else { fatalError("Source page") }
    let bounds = page.getBoxRect(.cropBox)
    var box = CGRect(x: 0, y: 0, width: bounds.width * 3, height: bounds.height * 3)
    let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
    context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
    context.scaleBy(x: 3, y: 3)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    context.drawPDFPage(page)
    context.endPDFPage()
}
context.closePDF()
