#!/bin/zsh
# Compile one of this directory's tools with the library's current sources (internal types visible).
# usage: build-tool.sh <tool.swift> <output executable>
root=${0:A:h}/../..
sources=(${(f)"$(ls $root/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter.swift -e PDFConverter.swift)"})
xcrun swiftc -parse-as-library -enable-bare-slash-regex -swift-version 6 -O $sources $1 -o $2 2> $2.build.log \
  || { grep error: $2.build.log | head -20; exit 1 }
