import Foundation
import CoreGraphics
import PDFKit

// The #274 survey. Over every page of a source, finds every space PDFKit reports that the page's
// own shows do not draw, on lines whose shows spell PDFKit's reading exactly apart from whitespace,
// and records the gap the space stands at, the characters on either side, and the space width the
// font itself states. Run from the repository root, once per cached source:
//
//   swiftc -O $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift \
//       | tr ' ' '\n' | grep -v tools/probes) \
//       measurements/numbers-drawn-in-two-shows/tools/survey-invented-spaces.swift -o /tmp/survey
//   /tmp/survey corpus/cache/faa-h-8083-25c.pdf faa-phak-8083-25c > /tmp/faa.json
//
// This reads extraction evidence only; it writes no converter output.

struct Finding: Codable {
    var book: String
    var page: Int
    var left: String
    var right: String
    var gapEm: Double
    var betweenShows: Bool
    var sameFont: Bool
    var sizeRatio: Double
    var context: String
    var source: String
    var spaced: Bool
    var rightSpaceWidth: Double
    var spaceWidthEm: Double
}

@main struct Survey {
  static func main() throws {
    let args = CommandLine.arguments
    guard args.count >= 3 else { fatalError("usage: survey <pdf> <book-id> [firstPage lastPage]") }
    let url = URL(fileURLWithPath: args[1])
    let book = args[2]
    let first = args.count >= 5 ? Int(args[3])! : 1
    let last = args.count >= 5 ? Int(args[4])! : Int.max

    guard let provider = CGDataProvider(url: url as CFURL), let cgDocument = CGPDFDocument(provider),
          let pdfDocument = PDFDocument(url: url) else { fatalError("cannot open") }

    var findings: [Finding] = []
    var linesConsidered = 0, linesAligned = 0

    for pageNumber in first...min(last, cgDocument.numberOfPages) {
        autoreleasepool {
            guard let cgPage = cgDocument.page(at: pageNumber), let page = pdfDocument.page(at: pageNumber - 1) else { return }
            let evidence = NativeSpacingReader.read(cgPage)
            guard !evidence.isEmpty else { return }
            guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
            let selections = selection.selectionsByLine()
            guard selections.count <= 10_000, evidence.count <= 10_000 else { return }
            let allBounds = selections.map { $0.bounds(for: page) }
            for (index, line) in selections.enumerated() {
                guard let extractedText = line.string, !extractedText.isEmpty else { continue }
                linesConsidered += 1
                let owning = NativeSpacingReader.owningShows(evidence, bounds: allBounds[index], allBounds: allBounds)
                    .sorted { $0.origin.x < $1.origin.x }
                guard !owning.isEmpty, owning.allSatisfy({ $0.unicode != nil }) else { continue }

                // The source reading, with each character's originating show and the gap in em at the
                // boundary that opens each show.
                var scalars: [Unicode.Scalar] = []
                // For scalar k: the index of the show it came from.
                var owner: [Int] = []
                var gapAtShowStart: [Int: Double] = [:]
                var previous: NativeSpacingReader.Evidence?
                var ok = true
                for (k, show) in owning.enumerated() {
                    guard let unicode = show.unicode else { ok = false; break }
                    if let previous, let end = previous.end {
                        let size = max(previous.size, show.size)
                        if size > 0, abs(previous.origin.y - show.origin.y) <= size * 0.1 {
                            gapAtShowStart[scalars.count] = Double((show.origin.x - end) / size)
                        }
                    }
                    scalars += unicode.unicodeScalars
                    owner += Array(repeating: k, count: unicode.unicodeScalars.count)
                    previous = show
                }
                guard ok else { continue }

                let sourceSqueezed = scalars.enumerated().filter { !$0.element.properties.isWhitespace }
                let extractedScalars = Array(extractedText.unicodeScalars)
                let extractedSqueezed = extractedScalars.enumerated().filter { !$0.element.properties.isWhitespace && $0.element.value != 0xFFFD }
                guard !sourceSqueezed.isEmpty, sourceSqueezed.count == extractedSqueezed.count,
                      zip(sourceSqueezed, extractedSqueezed).allSatisfy({ $0.0.element == $0.1.element }) else { continue }
                linesAligned += 1

                // Each extracted whitespace run between two non-blank characters: does the source draw
                // whitespace there too?
                for n in 1..<extractedSqueezed.count {
                    let leftExtracted = extractedSqueezed[n - 1].offset, rightExtracted = extractedSqueezed[n].offset
                    guard rightExtracted > leftExtracted + 1 else { continue }   // no space reported
                    guard extractedScalars[(leftExtracted + 1)..<rightExtracted].allSatisfy({ $0.properties.isWhitespace }) else { continue }
                    let leftSource = sourceSqueezed[n - 1].offset, rightSource = sourceSqueezed[n].offset
                    // The source draws whitespace here too: PDFKit's space is the page's own.
                    if rightSource > leftSource + 1 { continue }

                    let leftShow = owning[owner[leftSource]], rightShow = owning[owner[rightSource]]
                    let between = owner[leftSource] != owner[rightSource]
                    let gap = gapAtShowStart[rightSource] ?? Double.nan
                    let contextStart = max(0, leftSource - 12), contextEnd = min(scalars.count, rightSource + 12)
                    let size = max(leftShow.size, rightShow.size)
                    findings.append(Finding(
                        book: book, page: pageNumber,
                        left: String(scalars[leftSource]), right: String(scalars[rightSource]),
                        gapEm: between && gap.isFinite ? gap : -99,
                        betweenShows: between,
                        sameFont: leftShow.font == rightShow.font,
                        sizeRatio: size > 0 ? Double(min(leftShow.size, rightShow.size) / size) : 0,
                        context: String(String.UnicodeScalarView(scalars[contextStart..<contextEnd])),
                        source: extractedText, spaced: leftShow.spaced || rightShow.spaced, rightSpaceWidth: rightShow.spaceWidth.map(Double.init) ?? -99,
                        spaceWidthEm: leftShow.spaceWidth.map(Double.init) ?? -99))
                }
            }
        }
    }

    FileHandle.standardError.write("\(book): lines \(linesConsidered), aligned \(linesAligned), findings \(findings.count)\n".data(using: .utf8)!)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try! encoder.encode(findings))
  }
}
