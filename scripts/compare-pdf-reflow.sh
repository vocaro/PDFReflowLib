#!/usr/bin/env bash
# Optional local development comparison; Poppler is never a library/app dependency.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
swift build --package-path "$ROOT" -c release
BINARY_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
exec python3 "$ROOT/tools/compare_pdf.py" \
    --converter "$BINARY_DIR/pdf-reflow" "$@"
