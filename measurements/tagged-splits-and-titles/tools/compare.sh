#!/bin/bash
# usage: compare.sh <case-id>  compares kept lane outputs b9cf-<case> and cand-<case>, then deletes both
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-aa53f40688524c305
I=$W/.build/i
case=$1
cmp=$I/lane/cmp-$case
rm -rf "$cmp"
cd "$W"
python3 tools/compare_conversion_runs.py --baseline "$I/lane/${BASE:-b9cf}-$case/$case" --candidate "$I/lane/${CAND:-cand}-$case/$case" \
  --output "$cmp" --allow-different-converters > "$I/lane/keep/compare-$case.json" 2> "$I/lane/keep/compare-$case.err"
echo "compare rc=$?"
python3 - "$I/lane/keep/compare-$case.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if isinstance(v, list): print(k, len(v), v[:40])
    elif isinstance(v, dict): print(k, json.dumps(v)[:600])
    else: print(k, v)
EOF
rm -rf "$I/lane/${BASE:-b9cf}-$case" "$I/lane/${CAND:-cand}-$case" "$cmp"
