#!/bin/bash
# usage: RUNS=<dir> compare.sh case... — comparator, textdiff, bodies and ligature counts for each case.
repo=$(cd "$(dirname "$0")/../../.." && pwd); tools=$(cd "$(dirname "$0")" && pwd)
T=${RUNS:?set RUNS to the directory holding runs-base and runs-cand}
mkdir -p $T/cmp
for c in "$@"; do
  python3 $repo/tools/compare_conversion_runs.py --baseline $T/runs-base/$c/$c --candidate $T/runs-cand/$c/$c \
    --output $T/cmp/$c.json --allow-different-converters --detail > $T/cmp/$c.out 2>&1
  echo "== $c comparator exit $?"
  python3 $tools/summarize.py $T/cmp/$c.json
  python3 $tools/textdiff.py $T/runs-base/$c/$c/$c.epub $T/runs-cand/$c/$c/$c.epub
  python3 $tools/bodies.py $T/runs-base/$c/$c/$c.epub $T/runs-cand/$c/$c/$c.epub
  python3 $tools/count.py $T/runs-base/$c/$c/$c.epub $T/runs-cand/$c/$c/$c.epub | sed 's|.*/||'
done
