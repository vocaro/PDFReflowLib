import AppKit
import PDFKit

// usage: render <pdf> <outdir> <page>...  — writes page-N.png at 100 DPI
let args = CommandLine.arguments
let document = PDFDocument(url: URL(fileURLWithPath: args[1]))!
for number in args.dropFirst(3).compactMap({ Int($0) }) {
    guard let page = document.page(at: number - 1) else { continue }
    let box = page.bounds(for: .mediaBox)
    let scale: CGFloat = 100.0 / 72.0
    let size = NSSize(width: box.width * scale, height: box.height * scale)
    let image = page.thumbnail(of: size, for: .mediaBox)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: args[2]).appendingPathComponent("page-\(number).png"))
}
