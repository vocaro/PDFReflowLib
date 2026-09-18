#!/bin/zsh
# usage: pair.sh <case> [keep]  — run both lanes for a case, compare, keep a page-block dump of
# the changed pages, then delete the EPUBs (unless `keep`).
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a752a17bcd29a7f86
S=/private/tmp/claude-501/i181
case=$1
for side in base cand; do
  $S/tools/lane.sh $case $side | tail -3
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
    print(' ', k, s if len(s) < 400 else s[:400] + '...')
EOF
for side in base cand; do
  python3 - $S/lane/$side-$case $side <<'EOF'
import json, sys, os
directory, side = sys.argv[1], sys.argv[2]
summary = json.load(open(os.path.join(directory, 'summary.json')))['results'][0]
print(' ', side, 'passed', summary['passed'], 'checks', summary.get('contentChecks'), 'errors', len(summary['errors']))
for error in summary['errors'][:8]:
    print('    -', error[:240])
EOF
done
python3 - $S/lane/cmp-$case.json $S/lane/base-$case $S/lane/cand-$case $S/lane/blocks-$case.txt <<'EOF'
import json, sys, glob, subprocess
d = json.load(open(sys.argv[1]))
pages = []
def walk(v):
    if isinstance(v, dict):
        for k, x in v.items():
            if k in ('changedPages', 'pages') and isinstance(x, list): pages.extend(p if isinstance(p, int) else p.get('page') for p in x)
            else: walk(x)
    elif isinstance(v, list):
        for x in v: walk(x)
walk(d)
pages = sorted({p for p in pages if isinstance(p, int)})
with open(sys.argv[4], 'w') as out:
    out.write(f'changed pages {pages}\n')
    for side, directory in (('base', sys.argv[2]), ('cand', sys.argv[3])):
        epub = (glob.glob(directory + '/**/*.epub', recursive=True) or [None])[0]
        if epub and pages:
            text = subprocess.run(['python3', '/private/tmp/claude-501/i181/tools/blocks.py', epub] + [str(p) for p in pages[:400]],
                                  capture_output=True, text=True).stdout
            out.write(f'######## {side}\n{text}')
print('  blocks dump', sys.argv[4], len(pages), 'pages')
EOF
if [[ "$2" != "keep" ]]; then find $S/lane -name '*.epub' -delete; fi
df -h /System/Volumes/Data | tail -1
