#!/bin/zsh
# usage: build-tool.sh <tool.swift> <output>   compile the library sources into a survey tool.
# Run from the repository root. EPUBWriter (ZIPFoundation) and PDFConverter, which needs it, are
# left out; nothing the surveys call depends on them.
set -e
SRCS=$(ls Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter)
swiftc -O -swift-version 6 -enable-bare-slash-regex ${=SRCS} "$1" -o "$2"
