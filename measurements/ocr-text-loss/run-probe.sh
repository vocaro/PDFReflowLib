#!/bin/bash
# Builds `tools/probes/probe-ocr-text-loss.swift` from the one source list the gates read, and
# runs it over the corpus cases given on the command line (#116). Run from the repository root:
#
#   measurements/ocr-text-loss/run-probe.sh <output-directory> <label>:<corpus-case-id>[:first:last] ...
#
# Each argument writes <output-directory>/<label>.jsonl, which summarize.py reads.
set -euo pipefail

out="$1"; shift
mkdir -p "$out"

# shellcheck disable=SC2046
xcrun swiftc -swift-version 6 -O \
  $(python3 tools/pdfreflow_tools/swift_sources.py probe-ocr-text-loss.swift) \
  -o "$out/probe-ocr-text-loss"

for spec in "$@"; do
  IFS=: read -r label case first last <<<"$spec"
  echo "probing $label ($case ${first:-1}-${last:-end})" >&2
  "$out/probe-ocr-text-loss" "$case" ${first:+$first} ${last:+$last} > "$out/$label.jsonl"
done
