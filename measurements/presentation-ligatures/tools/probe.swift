// usage: probe <pdf>... — prints each page whose PDFKit text holds U+FB00–U+FB06, with the context.
import Foundation
import PDFKit

for path in CommandLine.arguments.dropFirst() {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { print("unreadable \(path)"); continue }
    var total = 0
    for index in 0..<document.pageCount {
        autoreleasepool {
            guard let text = document.page(at: index)?.string else { return }
            let scalars = Array(text.unicodeScalars)
            for (i, s) in scalars.enumerated() where (0xFB00...0xFB06).contains(s.value) {
                total += 1
                let lo = max(0, i - 30), hi = min(scalars.count, i + 30)
                var context = String.UnicodeScalarView(); context.append(contentsOf: scalars[lo..<hi])
                print("\((path as NSString).lastPathComponent) p\(index + 1) U+\(String(s.value, radix: 16, uppercase: true)) \(String(context).replacingOccurrences(of: "\n", with: "⏎"))")
            }
        }
    }
    print("TOTAL \((path as NSString).lastPathComponent) \(total) pages=\(document.pageCount)")
}
