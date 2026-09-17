#!/bin/bash
# usage: build-census.sh <source-tree-root> <output-binary> [--accept-textless-gs]
# Compiles main.swift with that tree's library sources (no EPUB writer or converter front end).
set -e
T=$(cd "$(dirname "$0")" && pwd)
work="$2.build"
rm -rf "$work" "$2"; mkdir -p "$work"
cp "$T/main.swift" "$work/main.swift"
python3 "$T/gen-census-reader.py" "$1/Sources/PDFReflowLib/NativeSpacingReader.swift" "$work/CensusSpacingReader.swift" $3
files=$(ls "$1"/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter -e '/PDFReflowLib.swift$' -e SpineWriter)
/usr/bin/xcrun swiftc -O -enable-bare-slash-regex -module-cache-path "$work/mc" $files "$work/CensusSpacingReader.swift" "$work/main.swift" -o "$2" 2>&1 | grep error | head || true
rm -rf "$work"
test -x "$2"
