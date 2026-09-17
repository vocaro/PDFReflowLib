#!/bin/bash
# usage: census.sh <label: base|cand> <book: faa|dga|fed|our-flag> : census/<book>-<label>.tsv and .samples
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue91
case $2 in
  faa) pdf=faa-h-8083-25c.pdf ;; dga) pdf=DGA.pdf ;; fed) pdf=the-fed-explained.pdf ;; our-flag) pdf=CDOC-108hdoc97.pdf ;;
  *) echo "unknown book"; exit 2 ;;
esac
mkdir -p "$T/../census"
start=$(date +%s)
"$S/bin/census-$1" "$W/corpus/cache/$pdf" > "$T/../census/$2-$1.tsv" 2> "$S/tmp/$2-$1.stderr"
echo "rc=$? secs=$(( $(date +%s) - start ))"
grep '^SAMPLE' "$S/tmp/$2-$1.stderr" > "$T/../census/$2-$1.samples" || true
grep -v '^SAMPLE' "$S/tmp/$2-$1.stderr" | head -5
