#!/bin/zsh
# Runs the #115/#96 suites (and the two suites whose expectations moved) against <baseline>'s
# LayoutReconstructor.swift, with only the new pure helpers grafted on so the test target compiles:
# the coded-report recogniser (`codedReportGroupCount`, `isCodedReportType`, `codedReportRuns`)
# and the inflection evidence (`inflectedForms`, `inflectionVouches`). Neither is called by the
# baseline's `blocks` or `joinOperation`.
# Usage: negative-control.sh <worktree> <scratch-dir> <baseline-commit>
W=$1
S=$2
B=$3
cd $W || exit 1
cp Sources/PDFReflowLib/LayoutReconstructor.swift $S/LayoutReconstructor.candidate.swift
python3 - $S/LayoutReconstructor.candidate.swift Sources/PDFReflowLib/ZZBaselineShim.swift <<'EOF'
import sys
source = open(sys.argv[1]).read()
def between(start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]
coded = between("    /// The groups of the aviation weather report formats", "    /// A numeric parenthesis marker")
inflection = between("    private static let inflections", "    static func join(_ left: String")
open(sys.argv[2], "w").write("import CoreGraphics\nimport Foundation\n\nextension LayoutReconstructor {\n" + coded + inflection + "}\n")
EOF
git show $B:Sources/PDFReflowLib/LayoutReconstructor.swift > Sources/PDFReflowLib/LayoutReconstructor.swift
swift test --filter "ListBulletsAndCodedReportsTests|TallRowsAndMinusTests|TaggedSplitsAndTitlesTests" > $S/before-tests.log 2>&1
rm Sources/PDFReflowLib/ZZBaselineShim.swift
cp $S/LayoutReconstructor.candidate.swift Sources/PDFReflowLib/LayoutReconstructor.swift
git status --short
grep -E "^✘ Test .*failed after|Test run with" $S/before-tests.log
