#!/bin/bash
# usage: lane.sh <worktree> <scratch> <case-id> <base|cand>
# One corpus-lane case with <scratch>/bin/pdf-reflow-<base|cand> and <scratch>/bin/rp-probe.
# Stops when under 5 GB are free. The summary and a block dump are kept in <scratch>/lane/keep.
W=$1; I=$2; case=$3; side=$4
df -h /System/Volumes/Data | tail -1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$I/lane/$side-$case
rm -rf "$out"; mkdir -p "$I/lane/keep"
cd "$W" || exit 1
start=$(date +%s)
python3 tools/run_corpus_regressions.py --converter "$I/bin/pdf-reflow-$side" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$case" --environment-probe "$I/bin/rp-probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? seconds=$(( $(date +%s) - start ))"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
for r in s['results']:
    print(r['case'], 'passed', r['passed'], 'errors', len(r['errors']))
    for e in r['errors']: print('   ', str(e)[:400])
EOF
cp "$out/summary.json" "$I/lane/keep/$side-$case.json"
cp "$out.log" "$I/lane/keep/$side-$case.log"
epub=$(find "$out" -name '*.epub' | head -1)
python3 measurements/heading-placement/block-dump.py "$epub" > "$I/lane/keep/$side-$case.blocks.txt"
wc -l "$I/lane/keep/$side-$case.blocks.txt"
