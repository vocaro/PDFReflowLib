#!/bin/bash
# usage: build.sh tool.swift [output] [sourcesdir]
set -e
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a752a17bcd29a7f86
src="$1"; out="${2:-${src%.swift}}"; S="${3:-$W/Sources/PDFReflowLib}"
files=$(ls $S/*.swift | grep -v -e EPUBWriter -e PDFConverter)
swiftc -O -enable-bare-slash-regex -parse-as-library -module-name Diag $files "$src" -o "$out" 2>&1 | grep -E "error" | head -20
