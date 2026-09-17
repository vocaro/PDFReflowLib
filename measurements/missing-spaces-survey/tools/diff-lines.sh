#!/bin/bash
# usage: diff-lines.sh <work-dir> <base-binary> <cand-binary> <pdf>... : for each PDF in corpus/cache, product
# NativeTextReader lines from both survey-lines builds; prints the line count and every changed line
# (page, index, before, after) to <work-dir>/diff-<pdf>.tsv, then deletes the line dumps.
T=$(cd "$(dirname "$0")" && pwd)
C="$T/../../../corpus/cache"
cd "$1" || exit 2
base=$2; cand=$3; shift 3
for pdf in "$@"; do
  free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
  if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
  s=$(date +%s)
  "$base" "$C/$pdf" 2>/dev/null | cut -f1-3 > "lines-base-$pdf.tsv"
  "$cand" "$C/$pdf" 2>/dev/null | cut -f1-3 > "lines-cand-$pdf.tsv"
  python3 - "lines-base-$pdf.tsv" "lines-cand-$pdf.tsv" > "diff-$pdf.tsv" <<'EOF'
import sys
a = [l.rstrip('\n').split('\t') for l in open(sys.argv[1], encoding='utf-8')]
b = [l.rstrip('\n').split('\t') for l in open(sys.argv[2], encoding='utf-8')]
if len(a) != len(b):
    print(f"#line counts differ {len(a)} {len(b)}")
for x, y in zip(a, b):
    if x != y:
        print(f"{x[0]}\t{x[1]}\t{x[2]}\t{y[2]}")
EOF
  echo "$pdf lines=$(wc -l < lines-base-$pdf.tsv | tr -d ' ') changed=$(wc -l < diff-$pdf.tsv | tr -d ' ') secs=$(($(date +%s)-s)) free=${free}G"
  rm -f "lines-base-$pdf.tsv" "lines-cand-$pdf.tsv"
done
