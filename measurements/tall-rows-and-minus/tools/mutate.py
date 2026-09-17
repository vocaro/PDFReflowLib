import subprocess, sys, shutil, re
W = "/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0c3e3503c0e70d2e"
S = "/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad"
src = f"{W}/Sources/PDFReflowLib/LayoutReconstructor.swift"
original = open(src).read()
shutil.copy(src, f"{S}/LayoutReconstructor.candidate.swift")
mutants = {
    "leading-recorded": ("attachedGap = inflation > 0 ? previousGap : verticalGap", "attachedGap = verticalGap"),
    "no-prose-row-guard": ("                              isProseRow(neighbour, in: free, body: body) else { return 0 }", "                              true else { return 0 }"),
    "no-display-cap": ("                              neighbour.rect.height <= ordinary * 2,\n", ""),
    "no-list-exemption": ("func listLine(_ line: TextLine) -> Bool { isList(line.text) && !mathMinusRows.contains(line) }", "func listLine(_ line: TextLine) -> Bool { isList(line.text) }"),
    "any-list-join": ("guard opensWithMinusSign(content.text) else { continue }", ""),
    "no-min-excess": ("neighbour.rect.height > ordinary + body * 0.25,", "neighbour.rect.height > ordinary,"),
}
log = open(f"{S}/issue109/guard-mutations.log", "w")
try:
    for name in sys.argv[1:] or mutants:
        old, new = mutants[name]
        assert original.count(old) == 1, name
        open(src, "w").write(original.replace(old, new))
        run = subprocess.run(["swift", "test", "--filter", "TallRowsAndMinusTests|RowPiecesAndSpacedParagraphTests|ExerciseNumberingTests|MarkerPieceTests|InlineFormulaProseTests"],
                             cwd=W, capture_output=True, text=True)
        out = run.stdout + run.stderr
        failed = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
        summary = re.findall(r"Test run with .*", out)
        line = f"{name}: {'KILLED' if failed else 'SURVIVED'} {failed} {summary[-1] if summary else 'no summary (build error?)'}"
        print(line); log.write(line + "\n"); log.flush()
finally:
    open(src, "w").write(original)
