#!/bin/zsh
# Runs the #109 and #95/#71 suites against d333b4d's LayoutReconstructor.swift, with only the new
# pure helper `opensWithMinusSign` grafted on so the test target compiles.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0c3e3503c0e70d2e
cd $W || exit 1
cp Sources/PDFReflowLib/LayoutReconstructor.swift $S/LayoutReconstructor.candidate.swift
git show HEAD:Sources/PDFReflowLib/LayoutReconstructor.swift > Sources/PDFReflowLib/LayoutReconstructor.swift
cat > Sources/PDFReflowLib/ZZBaselineShim.swift <<'EOF'
extension LayoutReconstructor {
    static func opensWithMinusSign(_ text: String) -> Bool {
        text.range(of: "^−\\s+(?:[0-9]|[A-Za-z](?![A-Za-z]))", options: .regularExpression) != nil
    }
}
EOF
swift test --filter "TallRowsAndMinusTests|RowPiecesAndSpacedParagraphTests|ExerciseNumberingTests|MarkerPieceTests|InlineFormulaProseTests" > $S/issue109/before-tests.log 2>&1
rm Sources/PDFReflowLib/ZZBaselineShim.swift
cp $S/LayoutReconstructor.candidate.swift Sources/PDFReflowLib/LayoutReconstructor.swift
git status --short
grep -E "^✘ Test .*(failed|recorded)|Test run with" $S/issue109/before-tests.log | grep -E "failed after|Test run with"
