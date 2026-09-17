#!/bin/bash
# usage: lane.sh baseline|candidate <case> <short>   (runs one case, prints PASS/FAIL)
#        lane.sh compare <case> <short>              (compares base-<short> with cand-<short>, saves summaries, deletes EPUBs)
set -e
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue37
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a11a7ffaa3ea102c4
L=$S/lane
M=$W/measurements/scan-figure-regions/lane-summaries
cd "$W"
df -h /System/Volumes/Data | tail -1
case "$1" in
  baseline|candidate)
    [ "$1" = baseline ] && conv=$S/baseline/pdf-reflow && out=$L/base-$3 || { conv=$S/candidate/pdf-reflow; out=$L/cand-$3; }
    rm -rf "$out"
    python3 tools/run_corpus_regressions.py --converter "$conv" --epubcheck /opt/homebrew/bin/epubcheck \
      --environment-probe "$S/probe/probe" --execution-context host-terminal --case "$2" --output "$out" 2>&1 | grep -E "^PASS|^FAIL" || true
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [print(e) for r in d['results'] for e in r['errors']]" "$out/summary.json"
    ;;
  compare)
    python3 tools/compare_conversion_runs.py --allow-different-converters --baseline "$L/base-$3/$2" \
      --candidate "$L/cand-$3/$2" --output "$L/compare-$3.json" > "$L/compare-$3.stdout" 2>&1 || true
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print({k: d.get(k) for k in ['passed','changedPages','changedPageFields','changedImages','navigationChanged','changedReportFields','provenanceErrors','idOnlyShifts','imageRenames']})" "$L/compare-$3.json"
    cp "$L/base-$3/summary.json" "$M/$2-baseline-bfe0476.json"
    cp "$L/cand-$3/summary.json" "$M/$2-candidate.json"
    cp "$L/compare-$3.json" "$M/$2-comparison.json"
    ;;
  clean)
    rm -f "$L/base-$3/$2"/*.epub "$L/cand-$3/$2"/*.epub
    ;;
esac
