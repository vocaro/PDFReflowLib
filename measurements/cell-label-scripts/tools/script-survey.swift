import PDFKit
// Lists every run the #138-era script rule marks sup/sub, with its size relative to the other
// visible runs of the same PDFKit line selection. usage: scripts <pdf> [pages]
let args = CommandLine.arguments
let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
struct Run { var text: String; var size: Double; var offset: Double }
var counts: [String: Int] = [:]
var examples: [String: [String]] = [:]
let pages = args.count > 2 ? args[2].split(separator: ",").map { Int($0)! - 1 } : Array(0..<doc.pageCount)
for p in pages {
  guard let page = doc.page(at: p), let sel = page.selection(for: page.bounds(for: .cropBox)) else { continue }
  for line in sel.selectionsByLine() {
    guard let a = line.attributedString, a.length > 0 else { continue }
    var runs: [Run] = []
    a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { at, r, _ in
      guard let f = at[.font] as? NSFont else { return }
      let off = (at[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber ?? at[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
      runs.append(Run(text: (a.string as NSString).substring(with: r), size: Double(f.pointSize), offset: off))
    }
    for (i, run) in runs.enumerated() where !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let tol = max(0.5, run.size * 0.12)
      guard run.offset.isFinite, abs(run.offset) <= run.size * 0.75, abs(run.offset) > tol else { continue }
      let neighbours = [i > 0 ? runs[i-1] : nil, i + 1 < runs.count ? runs[i+1] : nil].compactMap { $0 }.map(\.size)
      if !neighbours.isEmpty && neighbours.allSatisfy({ run.size >= $0 * 2 }) { continue }
      let kind = run.offset > 0 ? "sup" : "sub"
      let others = runs.enumerated().filter { $0.offset != i && !$0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.element)
      let cls: String
      if others.isEmpty { cls = "lone" }
      else if let m = others.map(\.size).max(), run.size > m * 1.1 { cls = "larger" }
      else if let m = others.map(\.size).max(), run.size >= m * 0.9 { cls = "same" }
      else { cls = "smaller" }
      let key = "\(kind) \(cls)"
      counts[key, default: 0] += 1
      if examples[key, default: []].count < 400 {
        let ctx = others.map { String(format: "%.1f/%.2f", $0.size, $0.offset) }.prefix(3).joined(separator: " ")
        examples[key, default: []].append(String(format: "p%d %@ size=%.1f off=%.2f others[%@] line=%@", p + 1,
          run.text.debugDescription, run.size, run.offset, ctx, String(a.string.prefix(70)).debugDescription))
      }
    }
  }
}
for key in counts.keys.sorted() { print("\(key): \(counts[key]!)") }
for key in examples.keys.sorted() where !key.hasSuffix("smaller") {
  print("--- \(key)")
  for e in examples[key]! { print("  " + e) }
}
