#!/bin/bash
# usage: lane.sh <case-id> <label: base|cand>
# One corpus-lane case with the labelled converter; the output is kept for compare.sh.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=${ISSUE65_SCRATCH:?set ISSUE65_SCRATCH to the scratch directory holding bin/base, bin/cand and bin/probe}
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$S/lane/$2-$1
rm -rf "$out"; mkdir -p "$S/lane" "$T/../lane-summaries"
cd "$W"
start=$(date +%s)
python3 tools/run_corpus_regressions.py --converter "$S/bin/$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$1" --environment-probe "$S/bin/probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G secs=$(( $(date +%s) - start ))"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
print('summary passed:', s.get('passed'))
for r in s['results']:
    print(r['case'], 'passed', r['passed'], 'errors', len(r['errors']))
    for e in r['errors']: print('   ', e[:300])
EOF
cp "$out/summary.json" "$T/../lane-summaries/$2-$1.json"
