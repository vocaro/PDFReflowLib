#!/usr/bin/env bash
# Explicit real-document gate: source absence is an error; no downloads or silent passes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PDF="${PDFREFLOW_REAL_PDF:-$ROOT/corpus/cache/faa-h-8083-25c.pdf}"
if [[ ! -f "$PDF" ]]; then
    echo "Missing handbook PDF: $PDF (set PDFREFLOW_REAL_PDF to the pinned corpus source)" >&2
    exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
swift build --package-path "$ROOT" -c release
BINARY_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pdfreflow-memory.XXXXXX")"
# Preserve failures, reports and output for diagnosis; caller can remove this printed directory.
echo "PDFReflowLib memory results: $WORK/result"
exec python3 "$ROOT/tools/evaluate-real-document.py" \
    --case faa-phak-8083-25c --pdf "$PDF" --converter "$BINARY_DIR/pdf-reflow" \
    --output "$WORK/result" "$@"
