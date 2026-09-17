#!/bin/bash
# usage: survey-book.sh <work-dir> <base-survey-lines> <cand-survey-lines> <pdf-name> <label>
# Product NativeTextReader lines from both builds for corpus/cache/<pdf-name>, then every inserted space
# (insertions.py) to <work-dir>/<label>-insertions.tsv. Line dumps are deleted afterwards. Stops under 5 GB free.
T=$(cd "$(dirname "$0")" && pwd)
C="$T/../../../corpus/cache"
free=$(df -g /System/Volumes/Data | tail -1 | awk '{print $4}')
if [ "$free" -lt 5 ]; then echo "only ${free}G free; stopping"; exit 3; fi
cd "$1" || exit 2
s=$(date +%s)
"$2" "$C/$4" 2>/dev/null | cut -f1-3 > "$5-base.tsv"
"$3" "$C/$4" 2>/dev/null | cut -f1-3 > "$5-cand.tsv"
python3 "$T/insertions.py" "$5-base.tsv" "$5-cand.tsv" "$5" > "$5-insertions.tsv"
echo "$5 lines=$(wc -l < "$5-base.tsv" | tr -d ' ')/$(wc -l < "$5-cand.tsv" | tr -d ' ') insertions=$(wc -l < "$5-insertions.tsv" | tr -d ' ') secs=$(($(date +%s)-s)) free=${free}G"
rm -f "$5-base.tsv" "$5-cand.tsv"
