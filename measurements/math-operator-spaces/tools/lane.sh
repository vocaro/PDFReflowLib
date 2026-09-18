#!/bin/bash
# usage: lane.sh <scratch> <case-id> <label: base|cand>
# One corpus-lane case with <scratch>/<label>/pdf-reflow (both binaries share the executable name, so
# one Vision model cache, #94) and <scratch>/probe. Stops under 8 GB free. The output is kept for
# compare.sh; the summary is copied to lane-summaries/.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=$1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 8 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$S/lane/$3-$2
rm -rf "$out"; mkdir -p "$S/lane" "$T/../lane-summaries"
cd "$W" || exit 1
start=$(date +%s)
python3 tools/run_corpus_regressions.py --converter "$S/$3/pdf-reflow" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$2" --environment-probe "$S/probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G secs=$(( $(date +%s) - start ))"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
for r in s['results']:
    print(r['case'], 'passed', r['passed'], 'errors', len(r['errors']))
    for e in r['errors'][:20]: print('   ', e[:300])
EOF
cp "$out/summary.json" "$T/../lane-summaries/$3-$2.json"
