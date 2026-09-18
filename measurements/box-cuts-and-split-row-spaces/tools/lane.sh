#!/bin/zsh
# usage: lane.sh <case> <label>
cd /Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2
S=/private/tmp/claude-501/i177
df -h /System/Volumes/Data | tail -1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if (( free < 8 )); then echo "STOP: under 8 GB free"; exit 3; fi
rm -rf "$S/$2-$1"
python3 tools/run_corpus_regressions.py --converter "$S/bin/pdf-reflow-$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$S/$2-$1" --case "$1" --environment-probe .build/raster-environment/probe \
  --execution-context host-terminal 2>&1 | grep -v "NOT RUN\|NOT COVERED" | tail -8
