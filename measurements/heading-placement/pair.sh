#!/bin/bash
# usage: pair.sh <pdf-path> <label>  — baseline b9efcc9 vs candidate; EPUBs deleted afterwards.
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad
CAND=${CAND:-$S/pdf-reflow-cand3}
pdf=$1; label=$2
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
mkdir -p "$S/pairs"
for side in base cand; do
  bin=${BASE:-$S/pdf-reflow-04efe85}; [ $side = cand ] && bin=$CAND
  "$bin" "$pdf" "$S/pairs/$label-$side.epub" --package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 \
    --modification-date 2026-01-01T00:00:00Z > "$S/pairs/$label-$side.json" 2> /dev/null
  echo "$side rc=$?"
done
a=$(shasum -a 256 "$S/pairs/$label-base.epub" | cut -c1-16); b=$(shasum -a 256 "$S/pairs/$label-cand.epub" | cut -c1-16)
echo "$label base $a candidate $b" | tee -a "$S/pairs/identity.txt"
if [ "$a" != "$b" ]; then
  python3 "$S/dump.py" "$S/pairs/$label-base.epub" > "$S/pairs/$label-base.txt"
  python3 "$S/dump.py" "$S/pairs/$label-cand.epub" > "$S/pairs/$label-cand.txt"
  diff "$S/pairs/$label-base.txt" "$S/pairs/$label-cand.txt" > "$S/pairs/$label.diff"
  echo "diff lines: $(grep -c '^[<>]' "$S/pairs/$label.diff")"
fi
rm -f "$S/pairs/$label-base.epub" "$S/pairs/$label-cand.epub"
