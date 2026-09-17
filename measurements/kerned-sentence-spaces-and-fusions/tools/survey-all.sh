#!/bin/bash
# usage: survey-all.sh <work-dir> <label:pdf>...  runs same-font-word-spaces/tools/survey-book.sh in <work-dir> for each book,
# with <work-dir>/bin/lines-base and <work-dir>/bin/lines-cand (missing-spaces-survey/tools/build.sh); writes <label>-insertions.tsv.
T=$(cd "$(dirname "$0")" && pwd)
cd "$1" || exit 2
shift
for pair in "$@"; do
  label=${pair%%:*}; pdf=${pair#*:}
  bash "$T/../../same-font-word-spaces/tools/survey-book.sh" . bin/lines-base bin/lines-cand "$pdf" "$label" 2>&1 | tail -2
done
