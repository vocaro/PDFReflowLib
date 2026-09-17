#!/bin/bash
# usage: build.sh <source-tree-root> <tool.swift> <output-binary> : compiles a tool (as main.swift) with that
# tree's library sources.
set -e
work="$3.build"
rm -rf "$work" "$3"; mkdir -p "$work"
cp "$2" "$work/main.swift"
files=$(ls "$1"/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter -e '/PDFReflowLib.swift$' -e SpineWriter)
/usr/bin/xcrun swiftc -O -enable-bare-slash-regex -module-cache-path "$work/mc" $files "$work/main.swift" -o "$3" 2>&1 | grep error | head || true
rm -rf "$work"
test -x "$3"
