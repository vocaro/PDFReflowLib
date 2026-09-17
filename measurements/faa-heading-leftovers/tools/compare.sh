#!/bin/bash
# usage: compare.sh <case-id>  compares lane outputs base-<case> and cand-<case>, then deletes both
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a397b1066057391a4
I=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue97
case=$1
cmp=$I/lane/cmp-$case
rm -rf "$cmp"
cd "$W"
python3 tools/compare_conversion_runs.py --baseline "$I/lane/base-$case/$case" --candidate "$I/lane/cand-$case/$case" \
  --output "$cmp" --allow-different-converters > "$I/lane/keep/compare-$case.json" 2> "$I/lane/keep/compare-$case.err"
echo "compare rc=$?"
python3 - "$I/lane/keep/compare-$case.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if isinstance(v, list): print(k, len(v), v[:40])
    elif isinstance(v, dict): print(k, json.dumps(v)[:900])
    else: print(k, v)
EOF
if [ "$2" != "keep" ]; then rm -rf "$I/lane/base-$case" "$I/lane/cand-$case" "$cmp"; fi
