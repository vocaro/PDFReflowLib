#!/bin/bash
# usage: run-book.sh <book> : census for base, cand and gs; reasons per label; product line diff base vs cand
T=$(cd "$(dirname "$0")" && pwd)
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/spacing-maps
for label in base cand gs; do
  echo "== $1 $label"
  "$T/census.sh" $label "$1" 2>&1 | grep -v attributedString
  echo "reasons:"; tail -n +2 "$T/../census/$1-$label.tsv" | cut -f10 | sed 's/@.*//' | sort | uniq -c | sort -rn | head -8
  echo "repairs: $(wc -l < "$T/../census/$1-$label.repairs.tsv")"
done
echo "== product lines base vs cand (NativeTextReader)"
if cmp -s "$S/lines/$1-base.tsv" "$S/lines/$1-cand.tsv"; then echo "identical ($(wc -l < "$S/lines/$1-base.tsv") lines)"; else diff "$S/lines/$1-base.tsv" "$S/lines/$1-cand.tsv" | head -40; fi
rm -f "$S/lines/$1-"*
