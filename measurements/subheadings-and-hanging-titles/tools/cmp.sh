#!/bin/bash
# usage: cmp.sh <case-id> — compare base/cand lane evaluations, then delete both EPUBs.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w3
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-af73341b125d9562a
cd "$W"
python3 tools/compare_conversion_runs.py --baseline "$S/lane/base-$1/$1" --candidate "$S/lane/cand-$1/$1" \
  --output "$S/lane/compare-$1.json" --allow-different-converters > /dev/null
echo "compare rc=$?"
python3 - "$S/lane/compare-$1.json" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
for k, v in r.items():
    if isinstance(v, list):
        print(k, len(v), json.dumps(v)[:300])
    elif isinstance(v, dict):
        print(k, json.dumps(v)[:300])
    else:
        print(k, v)
EOF
find "$S/lane/base-$1" "$S/lane/cand-$1" -name "*.epub" -delete
