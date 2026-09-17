#!/bin/bash
# usage: lane.sh <scratch> <case-id> <label: base|cand>  one corpus-lane case with <scratch>/bin/<label> and
# <scratch>/bin/probe; the output is kept for compare.sh and the summary copied to lane-summaries/.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=$1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$S/lane/$3-$2
rm -rf "$out"; mkdir -p "$S/lane" "$T/../lane-summaries"
cd "$W"
start=$(date +%s)
python3 tools/run_corpus_regressions.py --converter "$S/bin/$3" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$2" --environment-probe "$S/bin/probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G secs=$(( $(date +%s) - start ))"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
print('summary passed:', s.get('passed'), 'converter', s.get('converterSHA256', '')[:16])
for r in s['results']:
    keys = {k: r[k] for k in r if 'check' in k.lower() or 'rss' in k.lower() or 'memory' in k.lower()}
    print(r['case'], 'passed', r['passed'], keys, 'errors', len(r['errors']))
    for e in r['errors']: print('   ', e[:300])
EOF
cp "$out/summary.json" "$T/../lane-summaries/$3-$2.json"
