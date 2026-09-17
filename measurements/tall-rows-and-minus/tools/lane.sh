#!/bin/bash
# usage: lane.sh <case-id> <base|cand>   one corpus-lane case; summary kept in lane/keep
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0c3e3503c0e70d2e
I=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue109
df -h /System/Volumes/Data | tail -1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$I/lane/$2-$1
rm -rf "$out"; mkdir -p "$I/lane/keep"
cd "$W" || exit 1
start=$(date +%s)
python3 tools/run_corpus_regressions.py --converter "$I/bin/pdf-reflow-$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$1" --environment-probe "$I/bin/rp-probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? seconds=$(( $(date +%s) - start ))"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
for r in s['results']:
    print(r['case'], 'passed', r['passed'], 'errors', len(r['errors']))
    for e in r['errors']: print('   ', str(e)[:400])
EOF
cp "$out/summary.json" "$I/lane/keep/$2-$1.json"
epub=$(find "$out" -name '*.epub' | head -1)
echo "epub: $epub"
python3 measurements/heading-placement/block-dump.py "$epub" > "$I/lane/keep/$2-$1.blocks.txt"
wc -l "$I/lane/keep/$2-$1.blocks.txt"
