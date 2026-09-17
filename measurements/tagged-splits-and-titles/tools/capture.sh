#!/bin/bash
# usage: capture.sh <case-id> <prefix> <page>...  -> Tests/PDFReflowLibTests/fixtures/<prefix>-<page>-tagged-layout.json
W=/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-aa53f40688524c305
cd "$W"
id=$1; prefix=$2; shift 2
for p in "$@"; do
  out=Tests/PDFReflowLibTests/fixtures/$prefix-$p-tagged-layout.json
  .build/i/capture-layout-fixture "$id" "$p" "$out" 2>/dev/null
  echo "$p $(wc -c < "$out") bytes, tagged lines: $(grep -c '"structure"' "$out")"
done
