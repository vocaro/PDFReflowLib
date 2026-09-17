#!/bin/bash
# usage: compare.sh <scratch> <case-id> [keep]  compare_conversion_runs on the base and cand lane outputs; the
# JSON goes to lane-summaries/compare-<case>.json. Both outputs are deleted afterwards unless `keep` is given.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=$1; case=$2
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
    if isinstance(v, list): print(k, len(v), json.dumps(v)[:600])
    elif isinstance(v, dict): print(k, json.dumps(v)[:800])
    else: print(k, v)
EOF
head -5 "$keep/compare-$case.err"
[ -s "$keep/compare-$case.err" ] || rm -f "$keep/compare-$case.err"
if [ "$3" != keep ]; then
  rm -rf "$S/lane/base-$case" "$S/lane/cand-$case" "$cmp" "$S/lane/base-$case.log" "$S/lane/cand-$case.log"
fi
