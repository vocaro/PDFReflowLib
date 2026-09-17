// Survey for #143: index-named glyph fonts, letter-shifted text and large character spacing.
//
// Build (from the repository root):
//   swiftc -O Sources/PDFReflowLib/FontWeightReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
//     Sources/PDFReflowLib/TextEncodingCheck.swift Sources/PDFReflowLib/GlyphIndexDecoder.swift \
//     measurements/glyph-index-decoding/survey.swift -module-name survey -parse-as-library -o <scratch>/survey
// Run:
//   <scratch>/survey corpus/cache/<file>.pdf > measurements/glyph-index-decoding/survey/<case>.txt
//
// For one PDF it reports:
// 1. every font with index-style `Differences` names and no ToUnicode (`FontWeightReader.indexGlyphFont`),
//    with its glyph count and the English statistics of the best offsets (`GlyphIndexDecoder.candidates`),
//    and whether `GlyphIndexDecoder` decodes it;
// 2. PDFKit text lines of at least four words (three or more ASCII letters) whose words are under 25%
//    dictionary words as extracted but at least 75% under one Caesar shift (1–25), from
//    `/usr/share/dict/words`: the letter-shift symptom independent of any font evidence;
// 3. TJ boundaries drawn with character spacing of at least 0.1 em, and those in arrays whose adjustments
//    offset it (an adjustment of at least half the spacing), where `NativeSpacingReader` now measures
//    word gaps as adjustment plus spacing and reads gaps inside strings.
import Foundation
import PDFKit

final class Spacing {
    var tc: CGFloat = 0, tfs: CGFloat = 1, saved: [(CGFloat, CGFloat)] = []
    var boundaries = 0, wide = 0, compensated = 0, pages: Set<Int> = [], compensatedPages: Set<Int> = [], page = 0
}

@main
struct Survey {
    static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)

        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let document = PDFDocument(url: url), let cg = CGPDFDocument(url as CFURL) else { fatalError("unreadable") }
        print("# \(url.lastPathComponent): \(document.pageCount) pages")

        // 1. Index-glyph fonts.
        var evidence: [String: GlyphIndexDecoder.FontEvidence] = [:]
        var indexPages = 0
        for number in 1...cg.numberOfPages {
            autoreleasepool {
                guard let page = cg.page(at: number) else { return }
                guard TextEncodingCheck.hasUnmappedFont(page) else { return }
                indexPages += 1
                var fonts: [Int: FontWeightReader.FontInfo] = [:]
                let shows = FontWeightReader.read(page, fonts: { fonts[$0] = $1 })
                GlyphIndexDecoder.collect(shows, fonts: fonts, into: &evidence)
            }
        }
        let decoded = try GlyphIndexDecoder.read(url, language: "en")
        print("## index-glyph fonts: \(evidence.count) on \(indexPages) pages with unmapped-font evidence; decoded \(decoded.count)")
        for (key, font) in evidence.sorted(by: { $0.value.glyphs > $1.value.glyphs }) {
            let candidates = GlyphIndexDecoder.candidates(for: font.words).sorted { ($0.passes ? 0 : 1, -$0.stopwordRate) < ($1.passes ? 0 : 1, -$1.stopwordRate) }
            print("\(font.baseFont ?? "(Type3)")\tglyphs \(font.glyphs)\tdistinct words \(font.words.count)\tdecoded \(decoded[key] != nil)")
            for candidate in candidates.prefix(3) {
                print(String(format: "\toffset %+d words %d long %d capitalized %d inner %.3f stop %.3f rare %.3f lower %.3f %@", candidate.offset, candidate.words, candidate.longWords, candidate.capitalizedWords, candidate.innerCapitalRate,
                             candidate.stopwordRate, candidate.rareBigramRate, candidate.lowercaseRate, candidate.passes ? "PASSES" : ""))
            }
        }

        // 2. Letter-shifted lines.
        let dictionary = Set((try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8))?
            .split(separator: "\n").map { $0.lowercased() } ?? [])
        func shifted(_ word: [UInt8], by k: Int) -> String {
            String(decoding: word.map { UInt8((Int($0) - 97 - k + 26) % 26 + 97) }, as: UTF8.self)
        }
        var shiftedLines: [(Int, Int, String)] = []
        var judgedLines = 0
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let text = document.page(at: index)?.string else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    let words = line.split(whereSeparator: { !($0.isASCII && $0.isLetter) }).filter { $0.count >= 3 }
                        .map { Array($0.lowercased().utf8) }
                    guard words.count >= 4 else { continue }
                    judgedLines += 1
                    let plain = words.filter { dictionary.contains(String(decoding: $0, as: UTF8.self)) }.count
                    guard plain * 4 < words.count else { continue }
                    let best = (1...25).map { k in (k, words.filter { dictionary.contains(shifted($0, by: k)) }.count) }.max { $0.1 < $1.1 }!
                    if best.1 * 4 >= words.count * 3 { shiftedLines.append((index + 1, best.0, String(line))) }
                }
            }
        }
        print("## letter-shifted lines: \(shiftedLines.count) of \(judgedLines) lines with four or more words")
        for (page, k, line) in shiftedLines.prefix(12) { print("\tpage \(page) shift \(k): \(line.prefix(100))") }
        if !shiftedLines.isEmpty {
            print("\tpages: \(Array(Set(shiftedLines.map(\.0))).sorted())")
        }

        // 3. Character spacing of at least 0.1 em under TJ adjustments.
        let spacing = Spacing()
        for number in 1...cg.numberOfPages {
            autoreleasepool {
                guard let page = cg.page(at: number), let table = CGPDFOperatorTableCreate() else { return }
                defer { CGPDFOperatorTableRelease(table) }
                spacing.page = number
                spacing.tc = 0; spacing.tfs = 1; spacing.saved = []
                CGPDFOperatorTableSetCallback(table, "q") { _, info in
                    let s = Unmanaged<Spacing>.fromOpaque(info!).takeUnretainedValue(); s.saved.append((s.tc, s.tfs))
                }
                CGPDFOperatorTableSetCallback(table, "Q") { _, info in
                    let s = Unmanaged<Spacing>.fromOpaque(info!).takeUnretainedValue(); if let last = s.saved.popLast() { (s.tc, s.tfs) = last }
                }
                CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
                    let s = Unmanaged<Spacing>.fromOpaque(info!).takeUnretainedValue()
                    var value: CGPDFReal = 0; if CGPDFScannerPopNumber(scanner, &value) { s.tc = value }
                }
                CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
                    let s = Unmanaged<Spacing>.fromOpaque(info!).takeUnretainedValue()
                    var value: CGPDFReal = 0; if CGPDFScannerPopNumber(scanner, &value) { s.tfs = value }
                }
                CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
                    let s = Unmanaged<Spacing>.fromOpaque(info!).takeUnretainedValue()
                    var array: CGPDFArrayRef?
                    guard CGPDFScannerPopArray(scanner, &array), let array else { return }
                    var sawString = false, number = false, offsets = false
                    // `NativeSpacingReader`'s compensated spacing: Tc of 0.1 em or more and an adjustment of half of it.
                    for i in 0..<CGPDFArrayGetCount(array) where s.tfs > 0 && s.tc / s.tfs >= 0.1 {
                        var value: CGPDFReal = 0
                        if CGPDFArrayGetNumber(array, i, &value), value / 1000 >= s.tc / s.tfs / 2 { offsets = true }
                    }
                    for i in 0..<CGPDFArrayGetCount(array) {
                        var string: CGPDFStringRef?, value: CGPDFReal = 0
                        if CGPDFArrayGetString(array, i, &string) {
                            if sawString && number {
                                s.boundaries += 1
                                if s.tfs > 0, abs(s.tc / s.tfs) >= 0.1 { s.wide += 1; s.pages.insert(s.page) }
                                if offsets { s.compensated += 1; s.compensatedPages.insert(s.page) }
                            }
                            sawString = true; number = false
                        } else if CGPDFArrayGetNumber(array, i, &value) { number = true }
                    }
                }
                let stream = CGPDFContentStreamCreateWithPage(page)
                defer { CGPDFContentStreamRelease(stream) }
                let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(spacing).toOpaque())
                defer { CGPDFScannerRelease(scanner) }
                CGPDFScannerScan(scanner)
            }
        }
        let widePages = spacing.pages.sorted()
        print("## TJ boundaries: \(spacing.boundaries); with character spacing of at least 0.1 em: \(spacing.wide) on \(widePages.count) pages \(widePages.prefix(30)); in compensated arrays: \(spacing.compensated) on pages \(spacing.compensatedPages.sorted().prefix(30))")
    }
}
