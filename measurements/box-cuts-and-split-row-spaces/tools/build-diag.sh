#!/bin/bash
# usage: build.sh <source-tree-root> <output-binary> : compiles main.swift with that tree's library sources.
set -e
T=$(cd "$(dirname "$0")" && pwd)
work="$2.build"
rm -rf "$work" "$2"; mkdir -p "$work"
files=$(ls "$1"/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter -e '/PDFReflowLib.swift$' -e SpineWriter)
/usr/bin/xcrun swiftc -Onone -enable-bare-slash-regex -module-cache-path "$work/mc" $files "$3" -o "$2" 2>&1 | grep error | head || true
rm -rf "$work"
test -x "$2"
