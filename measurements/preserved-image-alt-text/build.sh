#!/bin/zsh
# usage: build.sh <output-binary>   (run from the worktree root)
set -e
D=${0:A:h}
files=(${(f)"$(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter\|PDFReflowLibPipeline\|EPUBTextEncoder')"})
xcrun swiftc -parse-as-library -O -swift-version 6 -module-cache-path .build/raster-environment/module-cache "${files[@]}" "$D/survey.swift" -o "$1"
