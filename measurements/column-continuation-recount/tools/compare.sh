#!/bin/zsh
# usage: compare.sh <case> <candidate-label>   (run from the worktree root)
S=${0:A:h:h}
python3 tools/compare_conversion_runs.py --baseline "$S/${3:-base}-$1/$1" --candidate "$S/$2-$1/$1" \
  --output "$S/cmp-$2-$1.json" --allow-different-converters > /dev/null 2>&1
python3 - "$S/cmp-$2-$1.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
keep = ['passed', 'provenanceErrors', 'sameConverter', 'changedPages', 'changedImages', 'navigationChanged',
        'changedNavigationPages', 'pageMarkersEqual', 'changedReportFields']
print({k: d.get(k) for k in keep})
EOF
python3 "$S/tools/pagediff.py" "$PWD" "$S/${3:-base}-$1/$1/$1.epub" "$S/$2-$1/$1/$1.epub" > "$S/pagediff-$2-$1.txt"
tail -1 "$S/pagediff-$2-$1.txt"
