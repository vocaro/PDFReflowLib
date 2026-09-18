#!/bin/zsh
# usage: pair.sh <case>  — run both lanes for a case, compare them, then delete the EPUBs.
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1a8c9518159e03c1
S=/private/tmp/claude-501/i158
case=$1
for side in base cand; do
  $S/tools/lane.sh $case $side | tail -2
done
cd $W
python3 tools/compare_conversion_runs.py --baseline $S/lane/base-$case/$case --candidate $S/lane/cand-$case/$case \
  --output $S/lane/cmp-$case.json --allow-different-converters --detail > $S/lane/cmp-$case.log 2>&1
echo "compare exit $?"
python3 - "$S/lane/cmp-$case.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    s = json.dumps(v)
    print(' ', k, s if len(s) < 300 else s[:300] + '...')
EOF
for side in base cand; do
  python3 - $S/lane/$side-$case $side <<'EOF'
import json, sys, os
directory, side = sys.argv[1], sys.argv[2]
summary = json.load(open(os.path.join(directory, 'summary.json')))['results'][0]
print(' ', side, 'passed', summary['passed'], 'checks', summary.get('contentChecks'), 'errors', len(summary['errors']))
for error in summary['errors'][:6]:
    print('    -', error[:200])
result = os.path.join(directory, os.path.basename(directory).split('-', 1)[1], 'result.json')
if os.path.exists(result):
    r = json.load(open(result))
    print(' ', side, {k: r[k] for k in r if k in ('converterPeakRSSBytes', 'conversionSeconds', 'epubcheckExitCode', 'runPassed')})
EOF
done
find $S/lane -name '*.epub' -delete
df -h /System/Volumes/Data | tail -1
