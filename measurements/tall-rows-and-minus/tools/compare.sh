#!/bin/bash
# usage: compare.sh <case-id>  compares lane outputs base-<case> and cand-<case>, writes block diff, then deletes both
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0c3e3503c0e70d2e
I=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue109
case=$1
cmp=$I/lane/cmp-$case
rm -rf "$cmp"
cd "$W" || exit 1
python3 tools/compare_conversion_runs.py --baseline "$I/lane/base-$case/$case" --candidate "$I/lane/cand-$case/$case" \
  --output "$cmp" --allow-different-converters > "$I/lane/keep/compare-$case.json" 2> "$I/lane/keep/compare-$case.err"
echo "compare rc=$?"
ls "$cmp" 2>/dev/null
python3 - "$I/lane/keep/compare-$case.json" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("no json", e); sys.exit()
for k, v in d.items():
    if isinstance(v, list): print(k, len(v), str(v[:40])[:1200])
    elif isinstance(v, dict): print(k, json.dumps(v)[:1200])
    else: print(k, v)
EOF
tail -3 "$I/lane/keep/compare-$case.err"
diff "$I/lane/keep/base-$case.blocks.txt" "$I/lane/keep/cand-$case.blocks.txt" > "$I/lane/keep/$case.blocks.diff"
echo "block diff lines: $(wc -l < "$I/lane/keep/$case.blocks.diff")"
rm -rf "$I/lane/base-$case" "$I/lane/cand-$case" "$cmp"
