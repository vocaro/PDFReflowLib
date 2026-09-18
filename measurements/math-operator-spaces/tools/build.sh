#!/bin/bash
# usage: build.sh <source-tree-root> <output-binary> [probe.swift]
# Compiles a probe (default: this directory's operators.swift) with that tree's library sources,
# as missing-spaces-survey/tools/build.sh does for survey-lines.
set -e
T=$(cd "$(dirname "$0")" && pwd)
probe="${3:-$T/operators.swift}"
work="$2.build"
rm -rf "$work" "$2"; mkdir -p "$work"
files=$(ls "$1"/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter -e '/PDFReflowLib.swift$' -e SpineWriter)
cp "$probe" "$work/main.swift"
/usr/bin/xcrun swiftc -O -enable-bare-slash-regex -module-cache-path "$work/mc" $files "$work/main.swift" -o "$2" 2>&1 | grep error | head || true
rm -rf "$work"
test -x "$2"
