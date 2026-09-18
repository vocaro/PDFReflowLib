#!/bin/bash
# usage: compare.sh <scratch> <case-id>  compares the base and cand lanes of one case, writes the
# comparison to lane-summaries/compare-<case>.json and prints its summary.
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=$1
cd "$W" || exit 1
python3 tools/compare_conversion_runs.py --baseline "$S/lane/base-$2/$2" --candidate "$S/lane/cand-$2/$2" \
  --output "$T/../lane-summaries/compare-$2.json" --allow-different-converters > "$S/lane/compare-$2.log" 2>&1
echo "rc=$?"
tail -30 "$S/lane/compare-$2.log"
