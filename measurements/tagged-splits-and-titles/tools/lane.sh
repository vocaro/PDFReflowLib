#!/bin/bash
# usage: lane.sh <case-id> <binary-label> [keep]  one corpus-lane case; summary kept, EPUBs deleted unless keep
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-aa53f40688524c305
I=$W/.build/i
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$I/lane/$2-$1
rm -rf "$out"; mkdir -p "$I/lane/keep"
cd "$W"
python3 tools/run_corpus_regressions.py --converter "$I/bin/pdf-reflow-$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$1" --environment-probe "$I/rp-probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
print('summary passed:', s.get('passed'), 'converter', s.get('converterSHA256', '')[:16])
for r in s['results']:
    keys = {k: r[k] for k in r if 'check' in k.lower() or 'rss' in k.lower() or 'memory' in k.lower()}
    print(r['case'], 'passed', r['passed'], keys, 'errors', len(r['errors']))
    for e in r['errors']: print('   ', e[:300])
EOF
cp "$out/summary.json" "$I/lane/keep/$2-$1.json"
if [ "$3" != "keep" ]; then find "$out" -name '*.epub' -delete; fi
