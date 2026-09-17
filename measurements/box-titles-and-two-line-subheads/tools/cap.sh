#!/bin/bash
# usage: cap.sh <case-id> <prefix> <page>...  -> scratch fx/<prefix>-<page>.json and a line dump
S=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue100
cd /Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-af49577801f931b5f || exit 1
id=$1; prefix=$2; shift 2
pages="$*"
if [ "$1" = "range" ]; then pages=$(seq "$2" "$3"); fi
for p in $pages; do
  "$S/bin/capture" "$id" "$p" "$S/fx/$prefix-$p.json" > /dev/null 2>&1
  python3 "$S/tools/lines.py" "$S/fx/$prefix-$p.json" > "$S/fx/$prefix-$p.txt"
  echo "$p: $(wc -l < "$S/fx/$prefix-$p.txt") lines"
done
