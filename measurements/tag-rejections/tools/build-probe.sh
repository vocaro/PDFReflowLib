#!/bin/bash
# build.sh <main.swift> <output> : compile a probe with the library sources (no EPUBWriter/PDFConverter)
set -e
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a90893956cdc3fa18
SRCS=$(ls $W/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter)
swiftc -O $SRCS $1 -o "$2" 2>&1 | grep -E "error" || true
test -x "$2"
