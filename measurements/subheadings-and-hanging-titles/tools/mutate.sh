#!/bin/bash
# usage: mutate.sh <name> <python-replace-old> <python-replace-new>
# Applies one textual mutation to LayoutReconstructor.swift, runs the heading tests, restores.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w3
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-af73341b125d9562a
F=$W/Sources/PDFReflowLib/LayoutReconstructor.swift
cp "$F" "$S/LayoutReconstructor.backup.swift"
python3 - "$F" "$2" "$3" <<'EOF'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
assert text.count(old) == 1, f"pattern count {text.count(old)}"
open(path, 'w').write(text.replace(old, new))
EOF
if [ $? -ne 0 ]; then cp "$S/LayoutReconstructor.backup.swift" "$F"; exit 2; fi
cd "$W"
echo "== mutation $1"
swift test --filter "HeadingPlacement|AcademicFrontMatter|NavigationHeading|SectionLeadIn" 2>&1 | grep -E "^✘ Test [a-zA-Z]+\(\) failed|Test run|error:" | sed 's/ recorded.*//'
cp "$S/LayoutReconstructor.backup.swift" "$F"
