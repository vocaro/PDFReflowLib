#!/usr/bin/env bash
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
swift test
python3 -m unittest discover -s tools -p 'test_*.py' -v
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pdfreflow-checks.XXXXXX")"
echo "Validation results: $WORK"
EPUBCHECK=()
if command -v epubcheck >/dev/null; then EPUBCHECK=(--epubcheck "$(command -v epubcheck)"); fi
python3 tools/check-epubs.py --converter "$BINARY_DIR/pdf-reflow" --output "$WORK/epubs" "${EPUBCHECK[@]}"
python3 tools/check-conversion-policies.py --converter "$BINARY_DIR/pdf-reflow" --output "$WORK/policies" "${EPUBCHECK[@]}"
if [[ $CORPUS == 1 ]]; then
    python3 tools/run_corpus_regressions.py --converter "$BINARY_DIR/pdf-reflow" \
        --epubcheck "$(command -v epubcheck)" --output "$WORK/corpus"
elif [[ $FAST == 0 && -f "${PDFREFLOW_REAL_PDF:-corpus/cache/faa-h-8083-25c.pdf}" ]]; then
    scripts/check-pdf-reflow-memory.sh "${EPUBCHECK[@]}"
else
    echo "Skipped real-document memory gate (--fast or source absent; set PDFREFLOW_REAL_PDF)."
fi
