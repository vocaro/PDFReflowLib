#!/bin/bash
# usage: case.sh <case-id>  baseline and candidate lane runs, comparison, page diff, then delete outputs.
# One case per invocation (FAA takes about two minutes on a loaded host).
T=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$T/../../.." && pwd)
S=${ISSUE65_SCRATCH:?set ISSUE65_SCRATCH}
case=$1
"$T/lane.sh" "$case" base || [ $? -eq 1 ] || exit 3
"$T/lane.sh" "$case" cand || [ $? -eq 1 ] || exit 3
"$T/compare.sh" "$case" | grep -E "^passed|^changedPages |^changedImages |^navigationChanged|^pageMarkersEqual|^changedReportFields|^changedOCRPages" | cut -c1-400
cd "$W"
python3 "$T/pagediff.py" "$S/lane/base-$case/$case/$case.epub" "$S/lane/cand-$case/$case/$case.epub" > "$T/../pagediff-$case.txt"
cut -c1-300 "$T/../pagediff-$case.txt"
rm -rf "$S/lane/base-$case" "$S/lane/cand-$case" "$S/lane/cmp-$case" "$S/lane/base-$case.log" "$S/lane/cand-$case.log"
