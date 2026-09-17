#!/bin/zsh
# usage: cmp.sh <case>   -- compare base and cand lane evaluations; print summary; delete EPUBs afterwards
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0ba3a7886d1b0e32
L=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i141/lane
cd $W
python3 tools/compare_conversion_runs.py --baseline $L/base-$1/$1 --candidate $L/cand-$1/$1 --output $L/cmp-$1.json --allow-different-converters --detail > $L/cmp-$1.log 2>&1
echo "exit $?"
python3 - "$L/cmp-$1.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
def short(v):
    s = json.dumps(v)
    return s if len(s) < 400 else s[:400] + '...'
for k, v in d.items():
    print(k, short(v))
EOF
for side in base cand; do
  python3 -c "import json,sys; r=json.load(open('$L/'+sys.argv[1]+'-$1/summary.json'))['results'][0]; print(sys.argv[1], 'passed', r['passed'], 'checks', r['contentChecks'], 'errors', len(r['errors']))" $side
  python3 -c "import json,sys; r=json.load(open('$L/'+sys.argv[1]+'-$1/$1/result.json')); print(sys.argv[1], {k: r[k] for k in r if k in ('converterPeakRSSBytes','conversionSeconds','epubcheckExitCode','runPassed')})" $side 2>/dev/null
done
