# Feature removals and guard mutations for #122 and #123 items 1–2: each mutant removes one change
# or weakens one guard, runs the affected suites and records the tests that kill it. The sources
# are restored afterwards.
# Usage: python3 mutate.py <worktree> <log> [mutant ...]
import re
import subprocess
import sys

W, LOG = sys.argv[1], sys.argv[2]
LAYOUT = f"{W}/Sources/PDFReflowLib/LayoutReconstructor.swift"
OCR = f"{W}/Sources/PDFReflowLib/OCRReader.swift"
mutants = {
    # Each change removed: its reproducers must fail and its controls pass.
    "remove-block-step": (LAYOUT, "        if let blocks = interleavedBlocks(elements, bodySize: bodySize) {", "        if false, let blocks = interleavedBlocks(elements, bodySize: bodySize) {"),
    "remove-rotated-order": (LAYOUT, "        if let rotated = rotatedLineOrder(elements) { return rotated }", ""),
    "remove-ligature-vocabulary": (LAYOUT, "                if word.contains(where: isLigature) { vocabulary.insert(ligaturesSpelledOut(word)) }", ""),
    "remove-spaced-item-line": (LAYOUT, "            if let ordinary = listGap(line.fontSize), verticalGap >= ordinary + body * 0.5,", "            if false, let ordinary = listGap(line.fontSize), verticalGap >= ordinary + body * 0.5,"),
    # Block step guards.
    "blocks-allow-lists": (LAYOUT, "            return !isList(line.text)", "            return true"),
    "blocks-any-count": (LAYOUT, "        guard blocks.count == 2 else { return nil }", "        guard blocks.count >= 2 else { return nil }"),
    "blocks-no-centres-apart": (LAYOUT, "        guard abs(first.midX - second.midX) > max(first.width, second.width) * 0.25 else { return nil }", ""),
    "blocks-no-centred": (LAYOUT, "        guard blocks.allSatisfy(centred) else { return nil }", ""),
    "blocks-no-baseline-guard": (LAYOUT, "        guard shared.count * 3 <= small.count else { return nil }", ""),
    "blocks-no-alternation": (LAYOUT, "        guard zip(owners, owners.dropFirst()).filter({ $0 != $1 }).count >= 3 else { return nil }", ""),
    "blocks-row-by-sameRow": (LAYOUT, "                if min(lowest.maxY, rect.maxY) - max(lowest.minY, rect.minY) >= max(lowest.height, rect.height) * 0.5 {", "                if min(lowest.maxY, rect.maxY) - max(lowest.minY, rect.minY) >= min(lowest.height, rect.height) * 0.5 {"),
    "blocks-row-overlapping-pieces": (LAYOUT, "                    guard gap >= 0, gap <= bodySize else { continue }", "                    guard gap <= bodySize else { continue }"),
    # Rotated order guards.
    "rotated-any-direction": (LAYOUT, "                  return direction.dx * other.dx + direction.dy * other.dy >= cos(CGFloat.pi / 9)", "                  return true"),
    "rotated-with-upright": (LAYOUT, "                  guard let other = element.line?.readingDirection, element.box == nil else { return false }", "                  let other = element.line?.readingDirection ?? direction"),
    "ocr-direction-for-upright": (OCR, "        guard length > 0, abs(dy) > abs(dx) || dx < 0 else { return nil }", "        guard length > 0 else { return nil }"),
    "ocr-band-edge-unscaled": (OCR, "                      topEdge: line.topEdge.map { CGVector(dx: $0.dx, dy: $0.dy * height) })", "                      topEdge: line.topEdge)"),
    # Spaced list line guards.
    "spaced-no-capital": (LAYOUT, "               line.text.first(where: { !\"([\\u{201C}\\u{2018}\\\"'\".contains($0) && !$0.isWhitespace })?.isUppercase == true {", "               true {"),
    "spaced-no-added-space": (LAYOUT, "            if let ordinary = listGap(line.fontSize), verticalGap >= ordinary + body * 0.5,", "            if let ordinary = listGap(line.fontSize), verticalGap >= ordinary,"),
    "spaced-median-gap": (LAYOUT, "        return gaps.isEmpty ? nil : gaps[gaps.count / 4]", "        return gaps.isEmpty ? nil : gaps[gaps.count / 2]"),
}
originals = {path: open(path).read() for path in (LAYOUT, OCR)}
log = open(LOG, "a")
try:
    for name in sys.argv[3:] or mutants:
        path, old, new = mutants[name]
        assert originals[path].count(old) == 1, name
        open(path, "w").write(originals[path].replace(old, new))
        run = subprocess.run(["swift", "test", "--filter",
                              "FallbackBlocksAndLigaturesTests|ColumnCutTests|ListBulletsAndCodedReportsTests|ListContinuationTests|HyphenFragmentTests|AddressHyphenTests|RowPiecesAndSpacedParagraphTests"],
                             cwd=W, capture_output=True, text=True)
        out = run.stdout + run.stderr
        failed = sorted(set(re.findall(r"✘ Test (\w+)\(", out)))
        summary = re.findall(r"Test run with .*", out)
        line = f"{name}: {'KILLED' if failed else 'SURVIVED'} {failed} {summary[-1] if summary else 'no summary (build error?)'}"
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()
        open(path, "w").write(originals[path])
finally:
    for path, text in originals.items():
        open(path, "w").write(text)
