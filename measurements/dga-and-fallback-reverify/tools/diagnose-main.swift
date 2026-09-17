
import CoreGraphics
import Foundation
enum Diag { nonisolated(unsafe) static var hits: [Int: Int] = [:]; nonisolated(unsafe) static var ops = 0; static func hit(_ l: Int) { hits[l, default: 0] += 1 } }
let args = CommandLine.arguments
let doc = CGPDFDocument(URL(fileURLWithPath: args[1]) as CFURL)!
let pages: [Int] = args.count > 2 ? args[2].split(separator: ",").map { Int($0)! } : Array(1...doc.numberOfPages)
for p in pages {
  Diag.hits = [:]; Diag.ops = 0
  let page = doc.page(at: p)!
  let t0 = Date(); let r = GraphicsReader.read(page); let dt = Date().timeIntervalSince(t0)
  let b = page.getBoxRect(.cropBox)
  let big = r.regions.filter { $0.width*$0.height > b.width*b.height*0.75 }.count
  print("page \(p) unsupported=\(r.unsupported) rotation=\(page.rotationAngle) hits=\(Diag.hits.sorted{$0.key<$1.key}) regions=\(r.regions.count) pageSized=\(big) ops=\(Diag.ops) seconds=\(String(format: "%.3f", dt)) paints=\(r.paints.count) shows=\(r.textShows.count)")
  if ProcessInfo.processInfo.environment["DUMP"] != nil { for g in r.regions { print("  region", g) }; for q in r.paints.sorted(by: { $0.rect.width*$0.rect.height > $1.rect.width*$1.rect.height }).prefix(12) { print("  paint", q.rect, q.frame) }; print("  paints", r.paints.count); for q in r.paints where q.rect.minX < 284 && q.rect.maxX > 275 { print("  bridge", q.rect, q.frame) } }
}
