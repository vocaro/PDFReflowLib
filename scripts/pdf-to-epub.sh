#!/usr/bin/env bash
# Developer entry point for the independent converter; input files are never modified.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR
    DEVELOPER_DIR="$(xcode-select -p)"
fi
exec swift run --package-path "$ROOT" pdf-reflow "$@"
