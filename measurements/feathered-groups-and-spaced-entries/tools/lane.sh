#!/bin/zsh
# usage: lane.sh <case> <base|cand>   (runs from the worktree; deletes nothing)
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a752a17bcd29a7f86
S=/private/tmp/claude-501/i181
cd $W
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
echo "free ${free} GB"
if (( free < 8 )); then echo "STOP: under 8 GB free"; exit 3; fi
rm -rf "$S/lane/$2-$1"
mkdir -p "$S/lane"
python3 tools/run_corpus_regressions.py --converter "$S/$2/bin/pdf-reflow" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$S/lane/$2-$1" --case "$1" --environment-probe "$S/probe/probe" \
  --execution-context host-terminal 2>&1 | grep -v "NOT RUN\|NOT COVERED" | tail -6
