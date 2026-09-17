#!/bin/zsh
# usage: memrepeat.sh converter case prefix runs [converter options...]
conv=$1; case=$2; prefix=$3; n=$4; shift 4
for r in $(seq 1 $n); do
  zsh /private/tmp/claude-501/i140/tools/evalrun.sh $conv $case $prefix-$r "$@"
  rm -f /private/tmp/claude-501/i140/runs/$prefix-$r/*.epub
done
