#!/bin/bash
# usage: timing.sh pdf rounds: alternates base and candidate, printing user CPU seconds
D=/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i200
PDF=/Users/trevorharmon/Development/PDFReflowLib/corpus/cache/$1
for r in $(seq 1 $2); do
  for side in base cand; do
    rm -f $D/t.epub
    /usr/bin/time -p $D/pdf-reflow-$side $PDF $D/t.epub 2>&1 >/dev/null | grep -E "^(user|real)" | tr '\n' ' ' | sed "s/^/$side /"
    echo " load $(uptime | awk -F'averages: ' '{print $2}')"
  done
done
rm -f $D/t.epub
