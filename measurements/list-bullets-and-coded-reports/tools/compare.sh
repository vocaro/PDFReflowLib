#!/bin/bash
# usage: compare.sh <worktree> <scratch> <case-id> [baseline-side, default base]
# Compares lane outputs base-<case> and cand-<case>, writes the block diff, then deletes both.
W=$1; I=$2; case=$3; base=${4:-base}
cmp=$I/lane/cmp-$case
rm -rf "$cmp"
cd "$W" || exit 1
python3 tools/compare_conversion_runs.py --baseline "$I/lane/$base-$case/$case" --candidate "$I/lane/cand-$case/$case" \
  --output "$cmp" --allow-different-converters --detail > "$I/lane/keep/compare-$case.json" 2> "$I/lane/keep/compare-$case.err"
echo "compare rc=$?"
python3 - "$I/lane/keep/compare-$case.json" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("no json", e); sys.exit()
for k, v in d.items():
    if isinstance(v, list): print(k, len(v), str(v[:60])[:1500])
    elif isinstance(v, dict): print(k, json.dumps(v)[:1500])
    else: print(k, v)
EOF
tail -3 "$I/lane/keep/compare-$case.err"
diff "$I/lane/keep/$base-$case.blocks.txt" "$I/lane/keep/cand-$case.blocks.txt" > "$I/lane/keep/$case.blocks.diff"
echo "block diff lines: $(wc -l < "$I/lane/keep/$case.blocks.diff")"
rm -rf "$I/lane/$base-$case" "$I/lane/cand-$case" "$cmp"
