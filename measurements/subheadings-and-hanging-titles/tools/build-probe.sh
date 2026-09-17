#!/bin/bash
# Builds the line probe against the worktree's library sources (minus the EPUB writer).
P=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w3/probe
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-af73341b125d9562a
files=$(ls $W/Sources/PDFReflowLib/*.swift | grep -v "EPUBWriter\|PDFConverter\|/PDFReflowLib.swift$\|SpineWriter")
xcrun swiftc -parse-as-library -O -module-cache-path $P/mc $files $P/${1:-probe}.swift -o $P/${1:-probe} 2>&1 | grep "error" | head
