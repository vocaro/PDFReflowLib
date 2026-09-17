#!/bin/bash
# usage: compare.sh <case-id>
# compare_conversion_runs on the base and cand lane outputs. Outputs are kept for page review;
# clean.sh deletes them once the review is recorded.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=${ISSUE65_SCRATCH:?set ISSUE65_SCRATCH}
case=$1
keep=$T/../lane-summaries
cmp=$S/lane/cmp-$case
rm -rf "$cmp"
cd "$W"
python3 tools/compare_conversion_runs.py --baseline "$S/lane/base-$case/$case" --candidate "$S/lane/cand-$case/$case" \
  --output "$cmp" --allow-different-converters > "$keep/compare-$case.json" 2> "$keep/compare-$case.err"
echo "compare rc=$?"
python3 - "$keep/compare-$case.json" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as error:
    print('unreadable comparison', error); sys.exit()
for k, v in d.items():
    if isinstance(v, list): print(k, len(v), json.dumps(v)[:800])
    elif isinstance(v, dict): print(k, json.dumps(v)[:1200])
    else: print(k, v)
EOF
head -5 "$keep/compare-$case.err"
[ -s "$keep/compare-$case.err" ] || rm -f "$keep/compare-$case.err"
