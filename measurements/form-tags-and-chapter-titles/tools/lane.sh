#!/bin/bash
# usage: lane.sh <case-id> <binary-label> — one corpus-lane case; keeps summary.json, deletes EPUB outputs.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a85805ea97e861ace
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
out=$S/me/lane/$2-$1
rm -rf "$out"; mkdir -p "$S/me/lane/keep"
cd "$W"
python3 tools/run_corpus_regressions.py --converter "$S/bin/$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$1" --environment-probe "$S/me/rp/probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
print('summary passed:', s['passed'], 'converter', s['converterSHA256'][:16])
for r in s['results']:
    print(r['case'], 'passed', r['passed'], 'contentChecks', r.get('contentChecks'), 'errors', len(r['errors']),
          'peakRSS', r.get('peakResidentMiB') or r.get('peakRSSMiB') or {k: v for k, v in r.items() if 'rss' in k.lower() or 'memory' in k.lower()})
    for e in r['errors']: print('   ', e[:300])
EOF
cp "$out/summary.json" "$S/me/lane/keep/$2-$1.json"
find "$out" -name '*.epub' -delete
