#!/bin/bash
# usage: recheck.sh <case-id>  re-assess the kept base and cand lane outputs against the working-tree contract
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=${ISSUE65_SCRATCH:?set ISSUE65_SCRATCH}
cd "$W"
for label in cand base; do
  echo "== $label"
  python3 tools/check_corpus_content.py --case "$1" --evaluation "$S/lane/$label-$1/$1" > "$S/lane/$label-$1-recheck.json"
  python3 - "$S/lane/$label-$1-recheck.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
print('passed', d.get('passed'))
for error in d.get('errors', []): print('  ', error)
EOF
done
