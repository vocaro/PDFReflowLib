#!/bin/bash
# usage: lane.sh <case-id> <base|cand> — one corpus-lane case with the shared raster probe.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w3
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-af73341b125d9562a
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
bin=$S/pdf-reflow-7a29c09; [ "$2" = cand ] && bin=$S/pdf-reflow-cand4
[ -n "$BIN" ] && bin=$BIN
out=$S/lane/$2-$1
rm -rf "$out"
cd "$W"
python3 tools/run_corpus_regressions.py --converter "$bin" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$out" --case "$1" --environment-probe "$S/rasterprobe/probe" --execution-context host-terminal > "$out.log" 2>&1
echo "rc=$? free=${free}G"
python3 - "$out/summary.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
print('summary passed:', s['passed'], 'converter', s['converterSHA256'][:16])
for r in s['results']:
    print(r['case'], 'passed', r['passed'], 'contentChecks', r.get('contentChecks'), 'errors', len(r['errors']))
    for e in r['errors']: print('   ', e)
EOF
