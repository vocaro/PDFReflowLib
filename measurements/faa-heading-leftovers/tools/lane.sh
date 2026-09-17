#!/bin/bash
# usage: lane.sh <case-id> <binary-label>   one corpus-lane case; summary kept, EPUBs deleted after compare
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a397b1066057391a4
I=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue97
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$I/lane/$2-$1
rm -rf "$out"; mkdir -p "$I/lane/keep"
cd "$W"
start=$(date +%s)
python3 tools/run_corpus_regressions.py --converter "$I/bin/pdf-reflow-$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$1" --environment-probe "$I/probe/probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G seconds=$(( $(date +%s) - start ))"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
print('summary passed:', s.get('passed'))
for r in s['results']:
    keys = {k: r[k] for k in r if 'check' in k.lower() or 'rss' in k.lower() or 'memory' in k.lower()}
    print(r['case'], 'passed', r['passed'], keys, 'errors', len(r['errors']))
    for e in r['errors']: print('   ', e[:300])
EOF
cp "$out/summary.json" "$I/lane/keep/$2-$1.json"
