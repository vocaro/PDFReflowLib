#!/bin/zsh
# usage: case.sh <case> <base-label> <cand-label> [previous-cand-label] [keep]  (run from the worktree root)
S=${0:A:h:h}
$S/tools/lane.sh $1 $2 || exit 3
$S/tools/lane.sh $1 $3 || exit 3
$S/tools/compare.sh $1 $3 $2 | cut -c1-400
python3 measurements/titles-and-prose-in-crops/tools/recheck.py $1 "$S/$2-$1/$1" "$S/$3-$1/$1" | grep -v "^    "
if [[ -n "$4" && -f "$S/pagediff-$4-$1.txt" ]]; then
  if diff -q "$S/pagediff-$4-$1.txt" "$S/pagediff-$3-$1.txt" > /dev/null; then echo "page diff identical to $4"
  else echo "page diff differs from $4:"; diff "$S/pagediff-$4-$1.txt" "$S/pagediff-$3-$1.txt" | cut -c1-250 | head -40; fi
fi
python3 $S/tools/joins.py $PWD "$S/$2-$1/$1/$1.epub" "$S/$3-$1/$1/$1.epub" --json "$S/joins-$3-$1.json" | head -1
cp "$S/$2-$1/summary.json" "$S/summary-$2-$1.json"; cp "$S/$3-$1/summary.json" "$S/summary-$3-$1.json"
if [[ -z "$5" ]]; then rm -rf "$S/$2-$1" "$S/$3-$1"; fi
