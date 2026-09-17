#!/bin/zsh
# Evidence set for the #68 record on the current .build/release/pdf-reflow.
# usage: measurements/reproducibility/run_all.sh <scratch-dir>; results land in results/.
set -eu
HERE=${0:A:h}
S=$1
mkdir -p $S
for c in fed-explained-2021 gpo-our-flag-2003 cdc-zombie-pandemic-2011 arxiv-replay-clocks-2023 usgs-mcs2025-copper; do
  for m in concurrent sequential; do
    python3 $HERE/run_case.py $S $c $m | tail -1
  done
done
python3 $HERE/loaded_cdc.py $S 1 | grep exit
python3 $HERE/ocr_control.py $S cdc-zombie-pandemic-2011 17 5
python3 $HERE/ocr_control.py $S fed-explained-2021 7 32
