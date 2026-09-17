#!/bin/bash
# usage: build.sh tool.swift [output]
set -e
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0ba3a7886d1b0e32
T=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i141/tools
src="$1"; out="${2:-${src%.swift}}"
files=$(ls $W/Sources/PDFReflowLib/*.swift | grep -v -e EPUBWriter -e PDFConverter)
swiftc -O -enable-bare-slash-regex -parse-as-library -module-name Diag $files "$src" -o "$out" 2>&1 | grep -E "error" | head -20
