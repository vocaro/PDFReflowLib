#!/bin/bash
# usage: PROBE=<raster-environment probe> lane.sh <converter> <outdir> case... — one run_corpus_regressions call per case, then ligature counts
conv=$1; out=$2; shift 2
repo=$(cd "$(dirname "$0")/../../.." && pwd); T=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
for c in "$@"; do
  avail=$(df -g /System/Volumes/Data | awk 'NR==2{print $4}')
  if [ "$avail" -lt 8 ]; then echo "STOP disk ${avail}G before $c"; exit 1; fi
  python3 $repo/tools/run_corpus_regressions.py --converter "$conv" --epubcheck /opt/homebrew/bin/epubcheck --output "$out/$c" --case $c --environment-probe "$PROBE" --execution-context host-terminal > "$out/$c.summary" 2>&1
  echo "$c exit=$? $(tail -1 $out/$c.summary | cut -c1-200)"
  for e in $(find "$out/$c" -name '*.epub'); do python3 $T/count.py "$e"; done
done
echo LANE-DONE
