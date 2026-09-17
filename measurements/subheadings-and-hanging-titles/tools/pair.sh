#!/bin/bash
# usage: pair.sh <pdf-basename> <label> — 5bf5e59 baseline vs cand3; block dumps kept, EPUBs deleted.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w3
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-af73341b125d9562a
"$S/one.sh" "$S/pdf-reflow-7a29c09" "$W/corpus/cache/$1" "$2-b7a" || exit 3
"$S/one.sh" "$S/pdf-reflow-cand4" "$W/corpus/cache/$1" "$2-c4" || exit 3
echo "$2 diff lines: $(diff "$S/$2-b7a.txt" "$S/$2-c4.txt" | grep -c '^[<>]')"
python3 - "$S/$2-b7a.json" "$S/$2-c4.json" <<'EOF'
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
print('report keys differing:', [k for k in a if k != 'outputURL' and a[k] != b.get(k)])
EOF
