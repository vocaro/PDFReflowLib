import Foundation
import PDFKit
// usage: pipelines <pdf> <page> <substring>  lines as the pipeline extracts them: plain, with column joints, with borderless-table ink
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let n = Int(CommandLine.arguments[2])!, needle = CommandLine.arguments[3]
let page = doc.page(at: n - 1)!
let graphics = GraphicsReader.read(page.pageRef!)
let joints = GraphicsReader.columnJoints(graphics.paints.map(\.rect))
let plain = try NativeTextReader.lines(on: page, limit: 10_000_000)
let jointed = try NativeTextReader.lines(on: page, limit: 10_000_000, columnJoints: joints)
let full = try NativeTextReader.lines(on: page, limit: 10_000_000, columnJoints: joints, borderlessTableInk: graphics.paints.map(\.rect))
for (label, lines) in [("plain", plain), ("joints", jointed), ("full", full)] {
    for line in lines where line.text.contains(needle) { print(label, "|", line.text) }
}
print("joints", joints.count)
