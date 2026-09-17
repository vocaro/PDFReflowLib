#!/bin/zsh
# usage: compare.sh <case>   (run from the worktree root) — base vs c2 strict comparison + page digest
S=${0:A:h}
python3 tools/compare_conversion_runs.py --baseline "$S/base-$1/$1" --candidate "$S/c2-$1/$1" \
  --output "$S/cmp-$1.json" --allow-different-converters > /dev/null 2>&1
python3 - "$S/cmp-$1.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
keep = ['passed', 'provenanceErrors', 'sameConverter', 'changedPages', 'changedImages', 'navigationChanged',
        'changedNavigationPages', 'pageMarkersEqual', 'changedReportFields']
print({k: d[k] for k in keep})
EOF
epub=$(ls "$S/base-$1/$1/"*.epub)
cepub=$(ls "$S/c2-$1/$1/"*.epub)
python3 "$S/digest.py" "$epub" "$cepub" --pages --out "$S/digest-$1.json" | head -60
