#!/bin/zsh
# usage: lane.sh <case> <label>   (run from the worktree root)
set -e
S=${0:A:h:h}
df -h /System/Volumes/Data | tail -1
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if (( free < 5 )); then echo "STOP: under 5 GB free"; exit 3; fi
rm -rf "$S/$2-$1"
python3 tools/run_corpus_regressions.py --converter "$S/bin/pdf-reflow-$2" --epubcheck /opt/homebrew/bin/epubcheck \
  --output "$S/$2-$1" --case "$1" --environment-probe .build/raster-environment/probe \
  --execution-context host-terminal 2>&1 | grep -v "NOT RUN\|NOT COVERED" | tail -20
