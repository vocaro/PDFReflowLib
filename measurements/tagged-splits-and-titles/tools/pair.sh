#!/bin/bash
# usage: pair.sh <case-id>  baseline and candidate lanes (kept), comparison, outputs deleted
I=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-aa53f40688524c305/.build/i
echo "== baseline $BASE"
bash $I/lane.sh "$1" ${BASE:-b9cf} keep
echo "== candidate"
bash $I/lane.sh "$1" ${CAND:-cand} keep
echo "== compare"
bash $I/compare.sh "$1" | cut -c1-700
