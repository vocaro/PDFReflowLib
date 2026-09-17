#!/bin/bash
# usage: pair.sh <case-id> — baseline b7c4 and candidate final7 lanes, compare_conversion_runs, then delete outputs.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a85805ea97e861ace
case=$1
for label in b7c4 final7; do
  free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
  if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
  out=$S/me/pair/$label-$case
  rm -rf "$out"; mkdir -p "$S/me/pair"
  (cd "$W" && python3 tools/run_corpus_regressions.py --converter "$S/bin/$label" --epubcheck /opt/homebrew/bin/epubcheck \
    --output "$out" --case "$case" --environment-probe "$S/me/rp/probe" --execution-context host-terminal > "$out.log" 2>&1)
  echo "$label lane rc=$? free=${free}G"
done
cmp=$S/me/pair/cmp-$case
rm -rf "$cmp"
(cd "$W" && python3 tools/compare_conversion_runs.py --baseline "$S/me/pair/b7c4-$case/$case" \
  --candidate "$S/me/pair/final7-$case/$case" --output "$cmp" --allow-different-converters > "$cmp.log" 2>&1)
echo "compare rc=$?"
mkdir -p "$S/me/lane/keep"
cp "$cmp.log" "$S/me/lane/keep/compare-$case.json"
python3 "$S/me/cmpsummary.py" "$cmp.log" "$S/me/pair/b7c4-$case/$case" "$S/me/pair/final7-$case/$case"
rm -rf "$S/me/pair/b7c4-$case" "$S/me/pair/final7-$case" "$cmp"
