#!/bin/zsh
# usage: lane.sh <case> <label>   (run from the worktree root)
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue117
df -h /System/Volumes/Data | tail -1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if (( free < 5 )); then echo "STOP: under 5 GB free"; exit 3; fi
rm -rf "$S/lane/$2-$1"
mkdir -p "$S/lane"
python3 tools/run_corpus_regressions.py --converter "$S/bin/pdf-reflow-$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$S/lane/$2-$1" --case "$1" --environment-probe .build/raster-environment/probe \
  --execution-context host-terminal 2>&1 | grep -v "NOT RUN\|NOT COVERED" | tail -12
