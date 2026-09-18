#!/bin/bash
# usage: lane.sh side case...  (side = base|cand); runs one case per runner call, records PASS/FAIL
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1cbbc24d84b92807
D=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i200
cd $W
side=$1; shift
for c in "$@"; do
  df -h /System/Volumes/Data | tail -1 | awk '{print "free", $4}'
  rm -rf $D/$side-$c
  python3 tools/run_corpus_regressions.py --converter $D/pdf-reflow-$side --epubcheck /opt/homebrew/bin/epubcheck \
    --output $D/$side-$c --case $c 2>&1 | grep -E "^(PASS|FAIL|ERROR)|failed|Error" | head -5 | sed "s/^/$side /" | tee -a $D/lanes.log
done
