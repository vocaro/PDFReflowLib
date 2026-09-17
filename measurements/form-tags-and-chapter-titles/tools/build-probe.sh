#!/bin/bash
# usage: build-probe.sh <name>  (compiles me/<name>.swift with the worktree library sources)
P=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/me
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a85805ea97e861ace
files=$(ls $W/Sources/PDFReflowLib/*.swift | grep -v "EPUBWriter\|PDFConverter\|/PDFReflowLib.swift$\|SpineWriter")
/usr/bin/xcrun swiftc -parse-as-library -O -enable-bare-slash-regex -module-cache-path $P/mc $files $P/$1.swift -o $P/$1 2>&1 | grep "error" | head
