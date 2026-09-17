#!/bin/bash
# usage: run-books.sh <work-dir> <survey-lines-binary> <book>... : <book>.tsv (lines) and <book>-fused.tsv in work-dir
T=$(cd "$(dirname "$0")" && pwd)
C="$T/../../../corpus/cache"
cd "$1" || exit 2
bin=$2; shift 2
for n in "$@"; do
  case $n in
    faa) pdf=faa-h-8083-25c.pdf ;; dga) pdf=DGA.pdf ;; fed) pdf=the-fed-explained.pdf ;; flag) pdf=CDOC-108hdoc97.pdf ;;
    911) pdf=GPO-911REPORT.pdf ;; wallace) pdf=Beginning_and_Intermediate_Algebra.pdf ;; loper) pdf=22-451_7m58.pdf ;;
    replay) pdf=2311.07842v1.pdf ;; usgs) pdf=mcs2025-copper.pdf ;; *) echo "unknown $n"; exit 2 ;;
  esac
  free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
  if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
  s=$(date +%s)
  "$bin" "$C/$pdf" 2>/dev/null > "$n.tsv"
  python3 "$T/fused.py" "$n.tsv" "$C/$pdf" > "$n-fused.tsv"
  echo "$n pages=$(cut -f1 $n.tsv | sort -u | wc -l | tr -d ' ') lines=$(wc -l < $n.tsv | tr -d ' ') misaligned=$(grep -c '#misaligned' $n.tsv) unstyled=$(awk -F'\t' '$4==""' $n.tsv | wc -l | tr -d ' ') candidates=$(($(wc -l < $n-fused.tsv)-1)) word=$(awk -F'\t' '$5=="word"' $n-fused.tsv | wc -l | tr -d ' ') wordAtRun=$(awk -F'\t' '$5=="word"&&$6=="yes"' $n-fused.tsv | wc -l | tr -d ' ') punctAtRun=$(awk -F'\t' '$5=="punct"&&$6=="yes"' $n-fused.tsv | wc -l | tr -d ' ') free=${free}G secs=$(($(date +%s)-s))"
done
