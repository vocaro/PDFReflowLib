#!/bin/bash
# usage: build-probe-base.sh <name> <output>  (worktree sources with the 7c46377 MarkedTextReader)
P=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/me
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a85805ea97e861ace
files=$(ls $W/Sources/PDFReflowLib/*.swift | grep -v "EPUBWriter\|PDFConverter\|/PDFReflowLib.swift$\|SpineWriter\|MarkedTextReader")
/usr/bin/xcrun swiftc -parse-as-library -O -enable-bare-slash-regex -module-cache-path $P/mc $files $P/MarkedTextReader-7c46377.swift $P/$1.swift -o $P/$2 2>&1 | grep "error" | head
