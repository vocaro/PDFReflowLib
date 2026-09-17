#!/bin/bash
# usage: pair.sh <case-id>  baseline and candidate lanes, comparison summary, outputs deleted
I=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue97
echo "== $1 baseline"
bash "$I/lane.sh" "$1" base | head -8
echo "== $1 candidate"
bash "$I/lane.sh" "$1" cand | head -8
echo "== $1 compare"
bash "$I/compare.sh" "$1" | grep -E "^(passed|changedPages|changedPageFields|navigationChanged|changedNavigationPages|pageMarkersEqual|changedReportFields|changedImages) "
