# Guard mutations for #115/#96: each mutant weakens one guard, runs the affected suites and
# records whether a test kills it. The source file is restored afterwards.
# Usage: python3 mutate.py <worktree> <scratch-dir> [mutant ...]
import re, shutil, subprocess, sys
W, S = sys.argv[1], sys.argv[2]
src = f"{W}/Sources/PDFReflowLib/LayoutReconstructor.swift"
original = open(src).read()
shutil.copy(src, f"{S}/LayoutReconstructor.candidate.swift")
mutants = {
    # #115 list allowance
    "list-no-allowance": ("let inflation = extraHeight(item.last, listText: true) + extraHeight(line, listText: true)", "let inflation: CGFloat = 0"),
    "list-no-sentence-guard": ("isWordy(line.text) && readsAsSentence(line.text)", "true"),
    "no-display-cap": ("                  line.rect.height <= ordinary * 2 else { return 0 }", "                  true else { return 0 }"),
    # #115 inflection evidence
    "inflection-off": ("        if inflectionVouches(prefix: String(prefix).lowercased(), suffix: suffix.lowercased(), vocabulary: vocabulary) {", "        if false {"),
    "inflection-no-halves-guard": ("              !(vocabulary.contains(prefix) && vocabulary.contains(suffix)) else { return false }", "              true else { return false }"),
    "inflection-no-compound-forms": ("        guard !compounds.contains(where: vocabulary.contains) else { return false }", ""),
    "inflection-no-length-floor": ("prefix.count >= 2, suffix.count >= 2, prefix.count + suffix.count >= 6,", "true,"),
    # #96 coded reports
    "reports-no-change-group-break": ("current.append((index, isCodedReportType(last.text) || changeGroup))", "current.append((index, isCodedReportType(last.text)))"),
    "reports-no-opens-report": ("gap >= -body * 0.4, gap < body * 0.9, !opensReport, count >= 1 || remarks {", "gap >= -body * 0.4, gap < body * 0.9, count >= 1 || remarks {"),
    "reports-free-capitals": ("gap >= -body * 0.4, gap < body * 0.9, !opensReport, count >= 1 || remarks {", "gap >= -body * 0.4, gap < body * 0.9, !opensReport {"),
    "reports-no-geometry": ("                if abs(last.rect.minX - line.rect.minX) <= body * 0.5, abs(last.fontSize - line.fontSize) <= 0.5,\n                   gap >= -body * 0.4, gap < body * 0.9, !opensReport,", "                if !opensReport,"),
    "reports-two-groups-open": ("if count >= 3 || isCodedReportType(line.text) && next >= 3 {", "if count >= 2 || isCodedReportType(line.text) && next >= 2 {"),
}
log = open(f"{S}/guard-mutations.log", "w")
try:
    for name in sys.argv[3:] or mutants:
        old, new = mutants[name]
        assert original.count(old) == 1, name
        open(src, "w").write(original.replace(old, new))
        run = subprocess.run(["swift", "test", "--filter",
                              "ListBulletsAndCodedReportsTests|TallRowsAndMinusTests|TaggedSplitsAndTitlesTests|ListContinuationTests|HyphenFragmentTests|AddressHyphenTests|RowPiecesAndSpacedParagraphTests"],
                             cwd=W, capture_output=True, text=True)
        out = run.stdout + run.stderr
        failed = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
        summary = re.findall(r"Test run with .*", out)
        line = f"{name}: {'KILLED' if failed else 'SURVIVED'} {failed} {summary[-1] if summary else 'no summary (build error?)'}"
        print(line, flush=True); log.write(line + "\n"); log.flush()
finally:
    open(src, "w").write(original)
