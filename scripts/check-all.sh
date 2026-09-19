#!/usr/bin/env bash
# Gates run in three steps. First the Swift suite and the release build, one after the other
# because they share .build's lock, alongside the Python tool tests. Then the PDFKit concurrency
# stress on its own: contention from other gates would change the thread interleavings it samples.
# Then every remaining gate at once, each in its own processes with its own log, the corpus lane
# converting PDFREFLOW_CORPUS_JOBS (default 6) cases at a time. PDFREFLOW_CHECKS_SERIAL=1 runs
# every gate and corpus case one at a time with output on the terminal, the reference a
# parallel-only failure is checked against (doc/regression-testing.md "Parallel gates").
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
FAST=0
CORPUS=0
case "${1:-}" in
    --fast) FAST=1; shift ;;
    --corpus) CORPUS=1; shift ;;
esac
if [[ $# != 0 ]]; then echo "usage: scripts/check-all.sh [--fast|--corpus]" >&2; exit 2; fi
if [[ $CORPUS == 1 ]] && ! command -v epubcheck >/dev/null; then
    echo "The corpus gate requires epubcheck on PATH." >&2
    exit 2
fi
SERIAL="${PDFREFLOW_CHECKS_SERIAL:-0}"
CORPUS_JOBS="${PDFREFLOW_CORPUS_JOBS:-6}"
if [[ ! $CORPUS_JOBS =~ ^[1-9][0-9]*$ ]]; then echo "PDFREFLOW_CORPUS_JOBS must be a positive integer." >&2; exit 2; fi
if [[ $SERIAL == 1 ]]; then CORPUS_JOBS=1; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pdfreflow-checks.XXXXXX")"
LOGS="$WORK/logs"
mkdir "$LOGS"
echo "Validation results: $WORK"

GATES=()
PIDS=()
TIMINGS=()
FAILED=0

# NAME COMMAND...: runs one gate, logging to $LOGS/NAME.log (and the terminal when serial) and
# recording its exit status and seconds in $LOGS/NAME.status.
run_gate() {
    local name="$1" start=$SECONDS status=0
    shift
    if [[ $SERIAL == 1 ]]; then
        "$@" 2>&1 | tee "$LOGS/$name.log" || status=$?
    else
        "$@" > "$LOGS/$name.log" 2>&1 || status=$?
    fi
    echo "$status $((SECONDS - start))" > "$LOGS/$name.status"
}

# NAME COMMAND...: runs a gate now and waits for it.
foreground() {
    echo "RUN $1"
    GATES+=("$1")
    run_gate "$@"
}

# NAME COMMAND...: starts a gate without waiting for it, unless the run is serial.
background() {
    echo "RUN $1"
    GATES+=("$1")
    if [[ $SERIAL == 1 ]]; then
        run_gate "$@"
    else
        run_gate "$@" &
        PIDS+=($!)
    fi
}

# Waits for every started gate and reports each; a failed gate's log tail is printed unless its
# output already went to the terminal. Returns nonzero when any gate in this step failed.
finish_gates() {
    local pid name status seconds step_failed=0
    for pid in ${PIDS[@]+"${PIDS[@]}"}; do wait "$pid" || true; done
    for name in ${GATES[@]+"${GATES[@]}"}; do
        read -r status seconds < "$LOGS/$name.status"
        TIMINGS+=("$(printf '%-28s %5ss  %s' "$name" "$seconds" "$([[ $status == 0 ]] && echo PASS || echo FAIL)")")
        if [[ $status == 0 ]]; then
            echo "PASS $name (${seconds}s)"
        else
            step_failed=1
            echo "FAIL $name (${seconds}s, exit $status; log $LOGS/$name.log)"
            if [[ $SERIAL != 1 ]]; then tail -n 40 "$LOGS/$name.log" | sed 's/^/    /'; fi
        fi
    done
    GATES=()
    PIDS=()
    return $step_failed
}

report_timings() {
    echo "Gate timings (wall-clock ${SECONDS}s, $([[ $SERIAL == 1 ]] && echo serial || echo "parallel, corpus jobs $CORPUS_JOBS")):"
    printf '  %s\n' "${TIMINGS[@]}"
}

background python-tool-tests python3 -m unittest discover -s tools -p 'test_*.py' -v
background measurements-policy python3 tools/check_measurements.py
foreground swift-tests swift test
foreground release-build swift build -c release
if ! finish_gates; then report_timings; exit 1; fi
BINARY_DIR="$(swift build -c release --show-bin-path)"

# Exercise the real extraction path in fresh processes. Raw PDFKit controls are an
# explicit diagnostic campaign because they can reproduce the upstream exception.
foreground pdfkit-concurrency python3 tools/check_pdfkit_concurrency.py --output "$WORK/concurrency" \
    --modes native --workers 1 8 --trials 2 --iterations 50
finish_gates || FAILED=1

EPUBCHECK=()
if command -v epubcheck >/dev/null; then EPUBCHECK=(--epubcheck "$(command -v epubcheck)"); fi
background fixture-epubs python3 tools/check-epubs.py --converter "$BINARY_DIR/pdf-reflow" \
    --output "$WORK/epubs" ${EPUBCHECK[@]+"${EPUBCHECK[@]}"}
background conversion-policies python3 tools/check-conversion-policies.py --converter "$BINARY_DIR/pdf-reflow" \
    --output "$WORK/policies" ${EPUBCHECK[@]+"${EPUBCHECK[@]}"}
if [[ $CORPUS == 1 ]]; then
    background structure-memory python3 tools/check_structure_memory.py
    # PDFKit's attributed-text leak across three in-process Fed conversions (#4); builds its own
    # scratch package, so it shares nothing with .build.
    background repeated-conversions python3 tools/check_repeated_conversions.py
    background corpus python3 tools/run_corpus_regressions.py --converter "$BINARY_DIR/pdf-reflow" \
        --epubcheck "$(command -v epubcheck)" --output "$WORK/corpus" --jobs "$CORPUS_JOBS"
elif [[ $FAST == 0 && -f "${PDFREFLOW_REAL_PDF:-corpus/cache/faa-h-8083-25c.pdf}" ]]; then
    background faa-memory scripts/check-pdf-reflow-memory.sh ${EPUBCHECK[@]+"${EPUBCHECK[@]}"}
else
    echo "Skipped real-document memory gate (--fast or source absent; set PDFREFLOW_REAL_PDF)."
fi
finish_gates || FAILED=1
report_timings
exit $FAILED
