#!/bin/zsh
# usage: all.sh case...  — pair.sh for each case in turn, one log per case.
for c in "$@"; do
  echo "=== $c $(date +%H:%M:%S)"
  /private/tmp/claude-501/i181/tools/pair.sh $c > /private/tmp/claude-501/i181/lane/pair-$c.log 2>&1
  grep -E "changedPages|passed True|passed False|STOP|errors [1-9]" /private/tmp/claude-501/i181/lane/pair-$c.log | cut -c1-200
done
