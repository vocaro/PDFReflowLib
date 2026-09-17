#!/bin/zsh
# usage: build.sh tool.swift output [source-dir]
set -e
SRC=${3:-/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1f4f642d57375727/Sources/PDFReflowLib}
files=($(ls $SRC/*.swift | grep -v -e EPUBWriter -e PDFConverter))
swiftc -O -enable-bare-slash-regex -parse-as-library -module-name Diag $files "$1" -o "$2" 2>&1 | grep -E "error" | head -20 || true
