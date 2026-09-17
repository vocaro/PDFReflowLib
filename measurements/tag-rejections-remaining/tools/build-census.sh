#!/bin/bash
# usage: build-census.sh <source-tree-root> <output-binary>
# Generates CensusReader.swift from <root>/Sources/PDFReflowLib/MarkedTextReader.swift and compiles it with
# that tree's library sources (no EPUB writer or converter front end) and main.swift.
set -e
T=$(cd "$(dirname "$0")" && pwd)
work="$2.build"
rm -rf "$work" "$2"; mkdir -p "$work"
python3 "$T/gen-census-reader.py" "$1/Sources/PDFReflowLib/MarkedTextReader.swift" "$work/CensusReader.swift"
cp "$T/main.swift" "$work/main.swift"
files=$(ls "$1"/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter -e '/PDFReflowLib.swift$' -e SpineWriter)
/usr/bin/xcrun swiftc -O -enable-bare-slash-regex -module-cache-path "$work/mc" $files "$work/CensusReader.swift" "$work/main.swift" -o "$2" 2>&1 | grep error | head || true
rm -rf "$work"
test -x "$2"
