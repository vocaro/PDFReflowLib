#!/bin/bash
# Builds `tools/probes/probe-ocr-coverage-signals.swift` from the one source list the gates read,
# and runs it over the corpus cases given on the command line (#240). Run from the repository root:
#
#   measurements/ocr-coverage-written-width/run-probe.sh <output-directory> <label>:<case>[:first:last] ...
#
# Each argument writes <output-directory>/<label>.jsonl and, beside it, <label>-text/ holding both
# readings of every page and their line geometry, which label_pages.py and the calibration read.
set -euo pipefail

out="$1"; shift
mkdir -p "$out"

# shellcheck disable=SC2046
xcrun swiftc -swift-version 6 -O \
  $(python3 tools/pdfreflow_tools/swift_sources.py probe-ocr-coverage-signals.swift) \
  -o "$out/probe-ocr-coverage-signals"

for spec in "$@"; do
  IFS=: read -r label case first last <<<"$spec"
  echo "probing $label ($case ${first:-1}-${last:-end})" >&2
  mkdir -p "$out/$label-text"
  PROBE_RETRY=always PROBE_TEXT="$out/$label-text" \
    "$out/probe-ocr-coverage-signals" "$case" ${first:+$first} ${last:+$last} > "$out/$label.jsonl"
done
