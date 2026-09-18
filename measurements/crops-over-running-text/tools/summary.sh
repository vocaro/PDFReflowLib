#!/bin/zsh
# usage: summary.sh <base dir> <cand dir> [docs...]
B=$1; C=$2; shift 2
docs=("$@")
if (( ${#docs} == 0 )); then docs=(dga usgs nbs arxiv census courts gwl mag dasc slides thm flag cdc fed loper wallace 911 faa bluebook warren noaa); fi
for d in $docs; do
  echo -n "$d: "
  python3 /private/tmp/claude-501/i158/tools/sdiff.py $B/$d.txt $C/$d.txt 100 | head -1
done
